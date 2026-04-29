#!/usr/bin/env python3
"""MCL UI Scan Orchestrator (8.9.0).

Modes: incremental | full | report | axe
8.7.0/8.8.0 mirror — same finding schema, severity routing.
Trigger: only when FE stack-tag detected.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, os, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

EXCLUDE_DIRS = {".git", "node_modules", "dist", "build", ".next", ".nuxt", "target",
                "vendor", ".venv", "venv", "__pycache__", ".cache", "coverage",
                "out", ".turbo", ".parcel-cache", ".svelte-kit"}
UI_EXTS = {".tsx", ".jsx", ".ts", ".js", ".vue", ".svelte", ".html", ".css", ".scss", ".module.css"}
MAX_FILE_BYTES = 1024 * 1024
FE_TAGS = {"react-frontend", "vue-frontend", "svelte-frontend", "html-static"}

LOC = {
    "en": {"title": "UI Design & A11y Scan", "high": "HIGH severity",
           "medium": "MEDIUM severity", "low": "LOW severity",
           "no_findings": "No findings.", "files_scanned": "Files scanned",
           "scan_complete": "Scan complete.", "duration": "Duration",
           "saved_to": "Findings log", "no_fe": "No FE stack detected; nothing to scan."},
    "tr": {"title": "UI Tasarım & Erişilebilirlik Raporu", "high": "Yüksek şiddet",
           "medium": "Orta şiddet", "low": "Düşük şiddet",
           "no_findings": "Bulgu yok.", "files_scanned": "Taranan dosya",
           "scan_complete": "Tarama tamamlandı.", "duration": "Süre",
           "saved_to": "Bulgu kaydı", "no_fe": "FE stack tespit edilmedi; taranacak bir şey yok."},
}


def L(lang: str, key: str) -> str:
    return LOC.get(lang, LOC["en"]).get(key, LOC["en"][key])


def _load(name: str):
    here = Path(__file__).parent
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), here / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name.replace("-", "_")] = mod
    spec.loader.exec_module(mod)
    return mod


def detect_stack_tags(project_dir: Path) -> set[str]:
    here = Path(__file__).parent
    detect_sh = here / "mcl-stack-detect.sh"
    try:
        out = subprocess.run(["bash", "-c", f'source "{detect_sh}" && mcl_stack_detect "{project_dir}"'],
                             capture_output=True, text=True, timeout=15)
        return {t for t in out.stdout.split() if t}
    except Exception:
        return set()


def enumerate_ui(root: Path) -> list[Path]:
    out: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS and not d.startswith(".")]
        for fn in filenames:
            p = Path(dirpath) / fn
            if p.suffix.lower() not in UI_EXTS:
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


def load_cache(state_dir: Path, rv: str) -> dict:
    f = state_dir / "ui-cache.json"
    if not f.exists():
        return {"rules_version": rv, "files": {}}
    try:
        d = json.loads(f.read_text(encoding="utf-8"))
    except Exception:
        return {"rules_version": rv, "files": {}}
    if d.get("rules_version") != rv:
        return {"rules_version": rv, "files": {}}
    return d


def save_cache(state_dir: Path, cache: dict) -> None:
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / "ui-cache.json").write_text(json.dumps(cache, indent=2), encoding="utf-8")


def run_eslint(project_dir: Path, files: list[Path], stack_tags: set[str]) -> list[dict]:
    here = Path(__file__).parent
    sh = here / "mcl-ui-eslint.sh"
    if not sh.exists() or not files:
        return []
    try:
        out = subprocess.run(["bash", str(sh), str(project_dir), ",".join(sorted(stack_tags))]
                             + [str(f) for f in files[:50]],
                             capture_output=True, text=True, timeout=60)
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
    log = state_dir / "ui-findings.jsonl"
    try:
        with log.open("a", encoding="utf-8") as f:
            for x in findings:
                f.write(json.dumps(x) + "\n")
    except OSError:
        pass


def mode_incremental(rules_mod, tokens_mod, target: Path, project_dir: Path,
                     state_dir: Path, stack_tags: set[str]) -> dict:
    rv = hashlib.sha1(rules_mod.rules_version_seed().encode("utf-8")).hexdigest()
    has_fe = bool(stack_tags & FE_TAGS)
    if not has_fe:
        return {"findings": [], "no_fe_stack": True, "skipped_via_cache": False,
                "high_count": 0, "med_count": 0, "low_count": 0, "rules_version": rv}
    if not target.exists() or target.suffix.lower() not in UI_EXTS:
        return {"findings": [], "no_fe_stack": False, "skipped_via_cache": False,
                "high_count": 0, "med_count": 0, "low_count": 0, "rules_version": rv}
    cache = load_cache(state_dir, rv)
    sha = file_sha1(target)
    cached = cache["files"].get(str(target))
    skipped = False
    findings: list[dict] = []
    if cached and cached.get("sha1") == sha:
        skipped = True
    else:
        try:
            content = target.read_text(encoding="utf-8", errors="replace")
        except OSError:
            content = ""
        tokens = tokens_mod.detect(project_dir)
        for f in rules_mod.scan_file(str(target), content, stack_tags, tokens):
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
    audit_log(state_dir, "ui-scan-incremental", "mcl-pre-tool",
              f"file={target} high={high} med={med} low={low} skipped_via_cache={'true' if skipped else 'false'}")
    return {"findings": findings, "no_fe_stack": False, "skipped_via_cache": skipped,
            "high_count": high, "med_count": med, "low_count": low, "rules_version": rv}


def mode_full(rules_mod, tokens_mod, project_dir: Path, state_dir: Path,
              stack_tags: set[str], cache_bypass: bool = False) -> dict:
    rv = hashlib.sha1(rules_mod.rules_version_seed().encode("utf-8")).hexdigest()
    has_fe = bool(stack_tags & FE_TAGS)
    if not has_fe:
        audit_log(state_dir, "ui-scan-skipped", "mcl-stop", "reason=no-fe-stack-tag")
        return {"findings": [], "no_fe_stack": True, "high_count": 0, "med_count": 0,
                "low_count": 0, "duration_ms": 0, "rules_version": rv, "files_scanned": 0}
    cache = {"rules_version": rv, "files": {}} if cache_bypass else load_cache(state_dir, rv)
    sources = enumerate_ui(project_dir)
    findings: list[dict] = []
    start = datetime.now(timezone.utc)
    tokens = tokens_mod.detect(project_dir)
    audit_log(state_dir, "ui-tokens-detected", "mcl-ui-scan",
              f"source={tokens.get('source','?')} count={len(tokens.get('colors',[])) + len(tokens.get('spacing',[]))}")
    for i, p in enumerate(sources):
        if (i % 50) == 0:
            print(f"[MCL] UI scan... {i}/{len(sources)}", file=sys.stderr)
        sha = file_sha1(p)
        cached = cache["files"].get(str(p))
        if cached and cached.get("sha1") == sha and not cache_bypass:
            continue
        try:
            content = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        ff = [f.to_dict() for f in rules_mod.scan_file(str(p), content, stack_tags, tokens)]
        findings.extend(ff)
        cache["files"][str(p)] = {
            "sha1": sha,
            "last_scan_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "findings_count": len(ff),
            "high_count": sum(1 for f in ff if f["severity"] == "HIGH"),
        }
    print("[MCL] ESLint a11y delegate...", file=sys.stderr)
    findings.extend(run_eslint(project_dir, sources, stack_tags))
    save_cache(state_dir, cache)
    duration_ms = int((datetime.now(timezone.utc) - start).total_seconds() * 1000)
    high = sum(1 for f in findings if f["severity"] == "HIGH")
    med = sum(1 for f in findings if f["severity"] == "MEDIUM")
    low = sum(1 for f in findings if f["severity"] == "LOW")
    if findings:
        append_findings(state_dir, findings)
    src = "generic,framework"
    if any(f["source"] == "eslint" for f in findings):
        src += ",eslint"
    audit_log(state_dir, "ui-scan-full", "mcl-stop",
              f"high={high} med={med} low={low} duration_ms={duration_ms} sources={src} tags=" + ",".join(sorted(stack_tags)))
    return {"findings": findings, "no_fe_stack": False, "high_count": high,
            "med_count": med, "low_count": low, "duration_ms": duration_ms,
            "rules_version": rv, "files_scanned": len(sources),
            "tokens_source": tokens.get("source", "?")}


def render_markdown(result: dict, lang: str, state_dir: Path) -> str:
    if result.get("no_fe_stack"):
        return f"# {L(lang, 'title')}\n\n_{L(lang, 'no_fe')}_\n"
    parts = [f"# {L(lang, 'title')}", ""]
    parts.append(f"_{L(lang, 'scan_complete')} {L(lang, 'files_scanned')}: {result.get('files_scanned', '?')}; "
                 f"{L(lang, 'duration')}: {result.get('duration_ms', 0)} ms; tokens={result.get('tokens_source','?')}_")
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
    parts.append(f"**{L(lang, 'saved_to')}:** `{state_dir}/ui-findings.jsonl`")
    return "\n".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["incremental", "full", "report", "axe"], required=True)
    ap.add_argument("--state-dir", required=True, type=Path)
    ap.add_argument("--project-dir", required=True, type=Path)
    ap.add_argument("--target", type=Path)
    ap.add_argument("--lang", default="en")
    ap.add_argument("--markdown", action="store_true")
    args = ap.parse_args()

    if args.mode == "axe":
        here = Path(__file__).parent
        sh = here / "mcl-ui-axe.sh"
        if not sh.exists():
            print("axe helper missing", file=sys.stderr)
            return 1
        os.execvp("bash", ["bash", str(sh), str(args.project_dir), args.lang])
        return 0

    rules_mod = _load("mcl-ui-rules")
    tokens_mod = _load("mcl-ui-tokens")
    stack_tags = detect_stack_tags(args.project_dir)

    if args.mode == "incremental":
        if not args.target:
            print("--target required", file=sys.stderr); return 2
        result = mode_incremental(rules_mod, tokens_mod, args.target, args.project_dir,
                                  args.state_dir, stack_tags)
    elif args.mode == "full":
        result = mode_full(rules_mod, tokens_mod, args.project_dir, args.state_dir, stack_tags, False)
    else:
        result = mode_full(rules_mod, tokens_mod, args.project_dir, args.state_dir, stack_tags, True)

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
