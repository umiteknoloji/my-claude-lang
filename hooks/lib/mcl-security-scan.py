#!/usr/bin/env python3
"""MCL Security Scan Orchestrator.

Modes:
  --mode=incremental --target <file>   one file, generic+stack HIGH-only +
                                       optional Semgrep --severity=ERROR;
                                       severity-cache aware
  --mode=full                          all source files, all rules,
                                       Semgrep packs + SCA tool
  --mode=report                        same as full but cache-bypass and
                                       prints localized markdown to stdout

State files in $MCL_STATE_DIR:
  security-cache.json     — {rules_version, files: {path: {sha1, ...}}}
  security-findings.jsonl — append-only log

Output:
  --json (default for hook integration): JSON to stdout
  --markdown: human-readable localized markdown to stdout (used by /mcl-security-report)

Since 8.7.0.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# Excludes (mirror codebase-scan)
EXCLUDE_DIRS = {
    ".git", "node_modules", "dist", "build", ".next", ".nuxt",
    "target", "vendor", ".venv", "venv", "__pycache__", ".cache",
    "coverage", ".pytest_cache", ".mypy_cache", ".ruff_cache",
    "out", ".turbo", ".parcel-cache", ".svelte-kit",
}
SOURCE_EXTS = {
    ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs",
    ".py", ".rb", ".go", ".rs", ".java", ".kt", ".swift",
    ".cs", ".php", ".cpp", ".cc", ".c", ".h", ".hpp",
    ".lua", ".vue", ".svelte", ".scala", ".dart",
}
SKIP_FILE_PATTERNS = (".min.", ".bundle.", "-lock.", ".lock")
MAX_FILE_BYTES = 1024 * 1024

LOC = {
    "en": {
        "title": "Security Scan Report",
        "high": "HIGH severity",
        "medium": "MEDIUM severity",
        "low": "LOW severity",
        "no_findings": "No findings.",
        "files_scanned": "Files scanned",
        "scan_complete": "Scan complete.",
        "duration": "Duration",
        "saved_to": "Findings log",
    },
    "tr": {
        "title": "Güvenlik Tarama Raporu",
        "high": "Yüksek şiddet",
        "medium": "Orta şiddet",
        "low": "Düşük şiddet",
        "no_findings": "Bulgu yok.",
        "files_scanned": "Taranan dosya",
        "scan_complete": "Tarama tamamlandı.",
        "duration": "Süre",
        "saved_to": "Bulgu kaydı",
    },
}


def L(lang: str, key: str) -> str:
    return LOC.get(lang, LOC["en"]).get(key, LOC["en"][key])


# ---- Load rules module ----
def load_rules():
    here = Path(__file__).parent
    rules_path = here / "mcl-security-rules.py"
    spec = importlib.util.spec_from_file_location("mcl_security_rules", rules_path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["mcl_security_rules"] = mod
    spec.loader.exec_module(mod)
    return mod


# ---- Stack detection ----
def detect_stack_tags(project_dir: Path) -> set[str]:
    here = Path(__file__).parent
    detect_sh = here / "mcl-stack-detect.sh"
    try:
        out = subprocess.run(
            ["bash", "-c", f'source "{detect_sh}" && mcl_stack_detect "{project_dir}"'],
            capture_output=True, text=True, timeout=15,
        )
        return {t for t in out.stdout.split() if t}
    except Exception:
        return set()


# ---- File enumeration ----
def enumerate_sources(root: Path) -> list[Path]:
    out: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS and not d.startswith(".")]
        for fn in filenames:
            if any(p in fn for p in SKIP_FILE_PATTERNS):
                continue
            p = Path(dirpath) / fn
            if p.suffix.lower() not in SOURCE_EXTS:
                continue
            try:
                if p.stat().st_size > MAX_FILE_BYTES:
                    continue
            except OSError:
                continue
            out.append(p)
    out.sort()
    return out


# ---- Cache ----
def file_sha1(path: Path) -> str:
    h = hashlib.sha1()
    try:
        h.update(path.read_bytes())
    except OSError:
        return ""
    return h.hexdigest()


def compute_rules_version(rules_mod) -> str:
    seed = rules_mod.rules_version_seed()
    return hashlib.sha1(seed.encode("utf-8")).hexdigest()


def load_cache(state_dir: Path, rules_version: str) -> dict:
    cache_file = state_dir / "security-cache.json"
    if not cache_file.exists():
        return {"rules_version": rules_version, "files": {}}
    try:
        data = json.loads(cache_file.read_text(encoding="utf-8"))
    except Exception:
        return {"rules_version": rules_version, "files": {}}
    if data.get("rules_version") != rules_version:
        # Invalidate entire cache when rule pack changes.
        return {"rules_version": rules_version, "files": {}}
    return data


def save_cache(state_dir: Path, cache: dict) -> None:
    cache_file = state_dir / "security-cache.json"
    state_dir.mkdir(parents=True, exist_ok=True)
    cache_file.write_text(json.dumps(cache, indent=2), encoding="utf-8")


# ---- Semgrep wrapper ----
def run_semgrep(targets: list[Path], severity_filter: str | None = None) -> list[dict]:
    """Run semgrep with default ruleset; severity_filter='ERROR' for HIGH-only.
    Returns normalized findings dicts. Returns [] if semgrep missing or error."""
    if not targets:
        return []
    cmd = ["semgrep", "--config", "p/default", "--json", "--quiet"]
    if severity_filter:
        cmd += ["--severity", severity_filter]
    cmd += [str(p) for p in targets]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return []
    if out.returncode not in (0, 1):
        return []
    try:
        data = json.loads(out.stdout or "{}")
    except json.JSONDecodeError:
        return []
    findings = []
    for r in data.get("results", []):
        sev = r.get("extra", {}).get("severity", "INFO").upper()
        sev_map = {"ERROR": "HIGH", "WARNING": "MEDIUM", "INFO": "LOW"}
        findings.append({
            "severity": sev_map.get(sev, "LOW"),
            "source": "semgrep",
            "rule_id": r.get("check_id", "semgrep-unknown"),
            "file": r.get("path", ""),
            "line": r.get("start", {}).get("line", 0),
            "message": (r.get("extra", {}).get("message") or "").splitlines()[0][:200],
            "owasp": "",
            "asvs": "",
            "autofix": r.get("extra", {}).get("fix") or None,
            "category": "other",
        })
    return findings


# ---- SCA wrapper ----
def run_sca(project_dir: Path, stack_tags: set[str]) -> list[dict]:
    here = Path(__file__).parent
    sca_sh = here / "mcl-sca.sh"
    if not sca_sh.exists():
        return []
    try:
        out = subprocess.run(
            ["bash", str(sca_sh), str(project_dir), ",".join(sorted(stack_tags))],
            capture_output=True, text=True, timeout=120,
        )
    except Exception:
        return []
    if out.returncode != 0 or not out.stdout.strip():
        return []
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        return []


# ---- Audit log ----
def audit_log(state_dir: Path, event: str, hook: str, detail: str) -> None:
    state_dir.mkdir(parents=True, exist_ok=True)
    log = state_dir / "audit.log"
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"{ts} | {event} | {hook} | {detail}\n"
    try:
        with log.open("a", encoding="utf-8") as f:
            f.write(line)
    except OSError:
        pass


def append_findings_log(state_dir: Path, findings: list[dict]) -> None:
    if not findings:
        return
    state_dir.mkdir(parents=True, exist_ok=True)
    log = state_dir / "security-findings.jsonl"
    try:
        with log.open("a", encoding="utf-8") as f:
            for fnd in findings:
                f.write(json.dumps(fnd) + "\n")
    except OSError:
        pass


# ---- Modes ----
def mode_incremental(rules_mod, target: Path, project_dir: Path,
                     state_dir: Path, stack_tags: set[str],
                     run_semgrep_too: bool) -> dict:
    rules_version = compute_rules_version(rules_mod)
    cache = load_cache(state_dir, rules_version)
    findings: list[dict] = []
    skipped_via_cache = False

    if not target.exists() or target.suffix.lower() not in SOURCE_EXTS:
        return {"findings": [], "skipped_via_cache": False, "high_count": 0,
                "med_count": 0, "low_count": 0, "rules_version": rules_version}

    sha = file_sha1(target)
    cached = cache["files"].get(str(target))
    if cached and cached.get("sha1") == sha:
        skipped_via_cache = True
    else:
        try:
            content = target.read_text(encoding="utf-8", errors="replace")
        except OSError:
            content = ""
        # Generic + stack rules — keep all severities for full reporting,
        # caller filters HIGH-only when integrating with pre-tool block.
        for f in rules_mod.scan_file(str(target), content, stack_tags):
            findings.append(f.to_dict())
        if run_semgrep_too:
            findings.extend(run_semgrep([target], severity_filter="ERROR"))

        cache["files"][str(target)] = {
            "sha1": sha,
            "last_scan_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "findings_count": len(findings),
            "high_count": sum(1 for f in findings if f["severity"] == "HIGH"),
        }
        save_cache(state_dir, cache)

    high = sum(1 for f in findings if f["severity"] == "HIGH")
    med = sum(1 for f in findings if f["severity"] == "MEDIUM")
    low = sum(1 for f in findings if f["severity"] == "LOW")
    if findings:
        append_findings_log(state_dir, findings)
    audit_log(state_dir, "security-scan-incremental", "mcl-pre-tool",
              f"file={target} high={high} med={med} low={low} skipped_via_cache={'true' if skipped_via_cache else 'false'}")
    return {
        "findings": findings,
        "skipped_via_cache": skipped_via_cache,
        "high_count": high, "med_count": med, "low_count": low,
        "rules_version": rules_version,
    }


def mode_full(rules_mod, project_dir: Path, state_dir: Path,
              stack_tags: set[str], cache_bypass: bool = False) -> dict:
    rules_version = compute_rules_version(rules_mod)
    cache = {"rules_version": rules_version, "files": {}} if cache_bypass else load_cache(state_dir, rules_version)
    sources = enumerate_sources(project_dir)
    findings: list[dict] = []
    start = datetime.now(timezone.utc)

    for i, p in enumerate(sources):
        if (i % 50) == 0:
            print(f"[MCL] Scanning... {i}/{len(sources)}", file=sys.stderr)
        sha = file_sha1(p)
        cached = cache["files"].get(str(p))
        if cached and cached.get("sha1") == sha and not cache_bypass:
            # cache hit — re-use prior findings? for MVP, skip and trust cache count.
            continue
        try:
            content = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        file_findings = [f.to_dict() for f in rules_mod.scan_file(str(p), content, stack_tags)]
        findings.extend(file_findings)
        cache["files"][str(p)] = {
            "sha1": sha,
            "last_scan_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "findings_count": len(file_findings),
            "high_count": sum(1 for f in file_findings if f["severity"] == "HIGH"),
        }

    # Semgrep on full project (rule pack)
    print(f"[MCL] Running Semgrep packs...", file=sys.stderr)
    findings.extend(run_semgrep([project_dir]))

    # SCA on lockfiles
    print(f"[MCL] Running SCA tools...", file=sys.stderr)
    findings.extend(run_sca(project_dir, stack_tags))

    save_cache(state_dir, cache)
    duration_ms = int((datetime.now(timezone.utc) - start).total_seconds() * 1000)

    high = sum(1 for f in findings if f["severity"] == "HIGH")
    med = sum(1 for f in findings if f["severity"] == "MEDIUM")
    low = sum(1 for f in findings if f["severity"] == "LOW")

    if findings:
        append_findings_log(state_dir, findings)
    sources_used = "generic,stack"
    if any(f["source"] == "semgrep" for f in findings):
        sources_used += ",semgrep"
    if any(f["source"] == "sca" for f in findings):
        sources_used += ",sca"
    audit_log(state_dir, "security-scan-full", "mcl-stop",
              f"high={high} med={med} low={low} duration_ms={duration_ms} sources={sources_used}")

    return {
        "findings": findings, "high_count": high, "med_count": med, "low_count": low,
        "duration_ms": duration_ms, "rules_version": rules_version,
        "files_scanned": len(sources),
    }


# ---- Markdown render ----
def render_markdown(result: dict, lang: str, state_dir: Path) -> str:
    parts = [f"# {L(lang, 'title')}", ""]
    parts.append(f"_{L(lang, 'scan_complete')} {L(lang, 'files_scanned')}: {result.get('files_scanned', '?')}; "
                 f"{L(lang, 'duration')}: {result.get('duration_ms', 0)} ms_")
    parts.append("")
    high = [f for f in result["findings"] if f["severity"] == "HIGH"]
    med = [f for f in result["findings"] if f["severity"] == "MEDIUM"]
    low = [f for f in result["findings"] if f["severity"] == "LOW"]
    for label_key, items in (("high", high), ("medium", med), ("low", low)):
        if not items:
            continue
        parts.append(f"## {L(lang, label_key)} ({len(items)})")
        parts.append("")
        for f in items:
            owasp = f" [{f['owasp']}]" if f.get("owasp") else ""
            parts.append(f"- **{f['rule_id']}**{owasp} `{f['file']}:{f['line']}` — {f['message']}")
        parts.append("")
    if not result["findings"]:
        parts.append(f"_{L(lang, 'no_findings')}_")
    parts.append("")
    parts.append(f"**{L(lang, 'saved_to')}:** `{state_dir}/security-findings.jsonl`")
    return "\n".join(parts)


# ---- Main ----
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["incremental", "full", "report"], required=True)
    ap.add_argument("--state-dir", required=True, type=Path)
    ap.add_argument("--project-dir", required=True, type=Path)
    ap.add_argument("--target", type=Path, help="for incremental mode")
    ap.add_argument("--lang", default="en")
    ap.add_argument("--markdown", action="store_true")
    args = ap.parse_args()

    rules_mod = load_rules()
    stack_tags = detect_stack_tags(args.project_dir)

    if args.mode == "incremental":
        if not args.target:
            print("--target required for incremental", file=sys.stderr)
            return 2
        result = mode_incremental(rules_mod, args.target, args.project_dir,
                                  args.state_dir, stack_tags,
                                  run_semgrep_too=True)
    elif args.mode == "full":
        result = mode_full(rules_mod, args.project_dir, args.state_dir,
                           stack_tags, cache_bypass=False)
    else:  # report
        result = mode_full(rules_mod, args.project_dir, args.state_dir,
                           stack_tags, cache_bypass=True)

    if args.markdown or args.mode == "report":
        print(render_markdown(result, args.lang, args.state_dir))
    else:
        print(json.dumps(result))
    return 0


if __name__ == "__main__":
    # 8.10.0: top-level try/except — pause-on-error compatible
    try:
        sys.exit(main())
    except Exception as _e:
        import traceback as _tb
        _err = {"error": str(_e)[:500], "traceback": _tb.format_exc()[-1500:]}
        print(json.dumps(_err))
        sys.exit(3)  # 3 = orchestrator crash (caller pauses)
