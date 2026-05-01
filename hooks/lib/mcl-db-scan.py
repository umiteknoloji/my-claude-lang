#!/usr/bin/env python3
"""MCL DB Scan Orchestrator.

Modes:
  --mode=incremental --target <file>   single file, generic+ORM, cache-aware
  --mode=full                          all eligible files, all rules + migration delegate
  --mode=report                        full mode + cache bypass + localized markdown
  --mode=explain                       defer to mcl-db-explain.sh

State:
  $MCL_STATE_DIR/db-cache.json      — {rules_version, files: {path: {sha1, ...}}}
  $MCL_STATE_DIR/db-findings.jsonl  — append-only

Trigger gating: if no `db-*` stack tag detected, exits with empty result
(Phase 4.5 START gate sets phase4_db_scan_done=true and skips).

Since 8.8.0.
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
    ".sql", ".prisma",  # schema files
}
MAX_FILE_BYTES = 1024 * 1024

LOC = {
    "en": {
        "title": "DB Design Scan Report",
        "high": "HIGH severity", "medium": "MEDIUM severity", "low": "LOW severity",
        "no_findings": "No findings.",
        "files_scanned": "Files scanned",
        "scan_complete": "Scan complete.",
        "duration": "Duration",
        "saved_to": "Findings log",
        "no_db": "No DB stack detected; nothing to scan.",
    },
    "tr": {
        "title": "Veritabanı Tasarım Raporu",
        "high": "Yüksek şiddet", "medium": "Orta şiddet", "low": "Düşük şiddet",
        "no_findings": "Bulgu yok.",
        "files_scanned": "Taranan dosya",
        "scan_complete": "Tarama tamamlandı.",
        "duration": "Süre",
        "saved_to": "Bulgu kaydı",
        "no_db": "Bu projede DB stack tespit edilmedi; taranacak bir şey yok.",
    },
}


def L(lang: str, key: str) -> str:
    return LOC.get(lang, LOC["en"]).get(key, LOC["en"][key])


def load_rules():
    here = Path(__file__).parent
    rules_path = here / "mcl-db-rules.py"
    spec = importlib.util.spec_from_file_location("mcl_db_rules", rules_path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["mcl_db_rules"] = mod
    spec.loader.exec_module(mod)
    return mod


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


def enumerate_sources(root: Path) -> list[Path]:
    out: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS and not d.startswith(".")]
        for fn in filenames:
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


def file_sha1(path: Path) -> str:
    h = hashlib.sha1()
    try:
        h.update(path.read_bytes())
    except OSError:
        return ""
    return h.hexdigest()


def compute_rules_version(rules_mod) -> str:
    return hashlib.sha1(rules_mod.rules_version_seed().encode("utf-8")).hexdigest()


def load_cache(state_dir: Path, rules_version: str) -> dict:
    f = state_dir / "db-cache.json"
    if not f.exists():
        return {"rules_version": rules_version, "files": {}}
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except Exception:
        return {"rules_version": rules_version, "files": {}}
    if data.get("rules_version") != rules_version:
        return {"rules_version": rules_version, "files": {}}
    return data


def save_cache(state_dir: Path, cache: dict) -> None:
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / "db-cache.json").write_text(json.dumps(cache, indent=2), encoding="utf-8")


def run_migration_delegate(project_dir: Path, stack_tags: set[str]) -> list[dict]:
    here = Path(__file__).parent
    mig_sh = here / "mcl-db-migration.sh"
    if not mig_sh.exists():
        return []
    try:
        out = subprocess.run(
            ["bash", str(mig_sh), str(project_dir), ",".join(sorted(stack_tags))],
            capture_output=True, text=True, timeout=60,
        )
    except Exception:
        return []
    if out.returncode != 0 or not out.stdout.strip():
        return []
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        return []


def audit_log(state_dir: Path, event: str, hook: str, detail: str) -> None:
    state_dir.mkdir(parents=True, exist_ok=True)
    log = state_dir / "audit.log"
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with log.open("a", encoding="utf-8") as f:
            f.write(f"{ts} | {event} | {hook} | {detail}\n")
    except OSError:
        pass


def append_findings(state_dir: Path, findings: list[dict]) -> None:
    if not findings:
        return
    state_dir.mkdir(parents=True, exist_ok=True)
    log = state_dir / "db-findings.jsonl"
    try:
        with log.open("a", encoding="utf-8") as f:
            for fnd in findings:
                f.write(json.dumps(fnd) + "\n")
    except OSError:
        pass


def mode_incremental(rules_mod, target: Path, project_dir: Path,
                     state_dir: Path, stack_tags: set[str]) -> dict:
    rv = compute_rules_version(rules_mod)
    cache = load_cache(state_dir, rv)
    findings: list[dict] = []
    skipped = False
    has_db = any(t.startswith("db-") for t in stack_tags)
    if not has_db:
        return {"findings": [], "skipped_via_cache": False, "no_db_stack": True,
                "high_count": 0, "med_count": 0, "low_count": 0, "rules_version": rv}
    if not target.exists() or target.suffix.lower() not in SOURCE_EXTS:
        return {"findings": [], "skipped_via_cache": False, "no_db_stack": False,
                "high_count": 0, "med_count": 0, "low_count": 0, "rules_version": rv}
    sha = file_sha1(target)
    cached = cache["files"].get(str(target))
    if cached and cached.get("sha1") == sha:
        skipped = True
    else:
        try:
            content = target.read_text(encoding="utf-8", errors="replace")
        except OSError:
            content = ""
        for f in rules_mod.scan_file(str(target), content, stack_tags):
            findings.append(f.to_dict())
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
        append_findings(state_dir, findings)
    audit_log(state_dir, "db-scan-incremental", "mcl-pre-tool",
              f"file={target} high={high} med={med} low={low} skipped_via_cache={'true' if skipped else 'false'}")
    return {
        "findings": findings, "skipped_via_cache": skipped, "no_db_stack": False,
        "high_count": high, "med_count": med, "low_count": low, "rules_version": rv,
    }


def mode_full(rules_mod, project_dir: Path, state_dir: Path,
              stack_tags: set[str], cache_bypass: bool = False) -> dict:
    rv = compute_rules_version(rules_mod)
    has_db = any(t.startswith("db-") for t in stack_tags)
    if not has_db:
        audit_log(state_dir, "db-scan-skipped", "mcl-stop", "reason=no-db-stack-tag")
        return {"findings": [], "no_db_stack": True, "high_count": 0, "med_count": 0,
                "low_count": 0, "duration_ms": 0, "rules_version": rv, "files_scanned": 0}
    cache = {"rules_version": rv, "files": {}} if cache_bypass else load_cache(state_dir, rv)
    sources = enumerate_sources(project_dir)
    findings: list[dict] = []
    start = datetime.now(timezone.utc)
    for i, p in enumerate(sources):
        if (i % 50) == 0:
            print(f"[MCL] DB scan... {i}/{len(sources)}", file=sys.stderr)
        sha = file_sha1(p)
        cached = cache["files"].get(str(p))
        if cached and cached.get("sha1") == sha and not cache_bypass:
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
    print(f"[MCL] Migration delegate...", file=sys.stderr)
    findings.extend(run_migration_delegate(project_dir, stack_tags))
    save_cache(state_dir, cache)
    duration_ms = int((datetime.now(timezone.utc) - start).total_seconds() * 1000)
    high = sum(1 for f in findings if f["severity"] == "HIGH")
    med = sum(1 for f in findings if f["severity"] == "MEDIUM")
    low = sum(1 for f in findings if f["severity"] == "LOW")
    if findings:
        append_findings(state_dir, findings)
    sources_used = "generic,orm"
    if any(f["source"] == "migration" for f in findings):
        sources_used += ",migration"
    audit_log(state_dir, "db-scan-full", "mcl-stop",
              f"high={high} med={med} low={low} duration_ms={duration_ms} sources={sources_used} tags=" + ",".join(sorted(stack_tags)))
    return {
        "findings": findings, "no_db_stack": False,
        "high_count": high, "med_count": med, "low_count": low,
        "duration_ms": duration_ms, "rules_version": rv,
        "files_scanned": len(sources),
    }


def render_markdown(result: dict, lang: str, state_dir: Path) -> str:
    if result.get("no_db_stack"):
        return f"# {L(lang, 'title')}\n\n_{L(lang, 'no_db')}_\n"
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
            cat = f.get("category", "")
            cat_suffix = f" [{cat}]" if cat else ""
            parts.append(f"- **{f['rule_id']}**{cat_suffix} `{f['file']}:{f['line']}` — {f['message']}")
        parts.append("")
    if not result["findings"]:
        parts.append(f"_{L(lang, 'no_findings')}_")
    parts.append("")
    parts.append(f"**{L(lang, 'saved_to')}:** `{state_dir}/db-findings.jsonl`")
    return "\n".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["incremental", "full", "report", "explain"], required=True)
    ap.add_argument("--state-dir", required=True, type=Path)
    ap.add_argument("--project-dir", required=True, type=Path)
    ap.add_argument("--target", type=Path)
    ap.add_argument("--lang", default="en")
    ap.add_argument("--markdown", action="store_true")
    args = ap.parse_args()

    if args.mode == "explain":
        # Defer to mcl-db-explain.sh
        here = Path(__file__).parent
        explain_sh = here / "mcl-db-explain.sh"
        if not explain_sh.exists():
            print("explain helper missing", file=sys.stderr)
            return 1
        os.execvp("bash", ["bash", str(explain_sh), str(args.project_dir), args.lang])
        return 0  # unreachable

    rules_mod = load_rules()
    stack_tags = detect_stack_tags(args.project_dir)

    if args.mode == "incremental":
        if not args.target:
            print("--target required for incremental", file=sys.stderr)
            return 2
        result = mode_incremental(rules_mod, args.target, args.project_dir,
                                  args.state_dir, stack_tags)
    elif args.mode == "full":
        result = mode_full(rules_mod, args.project_dir, args.state_dir, stack_tags,
                           cache_bypass=False)
    else:  # report
        result = mode_full(rules_mod, args.project_dir, args.state_dir, stack_tags,
                           cache_bypass=True)

    if args.markdown or args.mode == "report":
        print(render_markdown(result, args.lang, args.state_dir))
    else:
        print(json.dumps(result))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as _e:
        import traceback as _tb
        print(json.dumps({"error": str(_e)[:500], "traceback": _tb.format_exc()[-1500:]}))
        sys.exit(3)
