#!/usr/bin/env python3
"""MCL Ops Scan Orchestrator (8.13.0).

Modes: incremental | full | report
Aggregates file metrics (env_var_refs, manifest_deps, adhoc_logging_count,
loc_total, function_count, function_doc_count, api_routes_count,
changed_files_no_test, coverage_total) then runs ops rules.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, os, re, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

EXCLUDE_DIRS = {".git", "node_modules", "dist", "build", ".next", ".nuxt",
                "target", "vendor", ".venv", "venv", "__pycache__", ".cache",
                "coverage", ".pytest_cache", ".mypy_cache", ".ruff_cache",
                "out", ".turbo", ".parcel-cache", ".svelte-kit"}
SOURCE_EXTS = {".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs",
               ".py", ".rb", ".go", ".rs", ".java", ".kt", ".swift",
               ".cs", ".php", ".cpp", ".cc", ".c", ".h"}
MAX_FILE_BYTES = 512 * 1024

LOC = {
    "en": {"title": "Operational Discipline Report",
           "high": "HIGH severity", "medium": "MEDIUM severity", "low": "LOW severity",
           "no_findings": "All checks passed.", "duration": "Duration",
           "categories": "Categories scanned"},
    "tr": {"title": "Operasyonel Disiplin Raporu",
           "high": "Yüksek şiddet", "medium": "Orta şiddet", "low": "Düşük şiddet",
           "no_findings": "Tüm kontroller geçti.", "duration": "Süre",
           "categories": "Taranan kategoriler"},
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


def collect_manifest_deps(project_dir: Path) -> set[str]:
    deps = set()
    pkg = project_dir / "package.json"
    if pkg.exists():
        try:
            d = json.loads(pkg.read_text(encoding="utf-8"))
            for k in ("dependencies", "devDependencies"):
                deps |= set((d.get(k) or {}).keys())
        except Exception:
            pass
    for r in ("requirements.txt", "requirements-dev.txt"):
        f = project_dir / r
        if f.exists():
            for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
                m = re.match(r"^\s*([a-zA-Z0-9_\-\.]+)", line)
                if m:
                    deps.add(m.group(1).lower())
    if (project_dir / "Gemfile").exists():
        for line in (project_dir / "Gemfile").read_text(encoding="utf-8", errors="replace").splitlines():
            m = re.match(r"^\s*gem\s+[\"']([\w\-]+)[\"']", line)
            if m:
                deps.add(m.group(1))
    return deps


def aggregate_metrics(project_dir: Path, stack_tags: set[str], threshold_high: int, threshold_medium: int) -> dict:
    """Walk source files; aggregate env refs, log calls, function counts, api routes."""
    metrics = {
        "env_var_refs": 0, "env_var_keys": set(),
        "adhoc_logging_count": 0, "logger_no_level_count": 0,
        "loc_total": 0,
        "function_count": 0, "function_doc_count": 0,
        "api_routes_count": 0,
        "changed_files_no_test": [],
        "manifest_deps": collect_manifest_deps(project_dir),
        "coverage_total": None,
        "coverage_threshold_high": threshold_high,
        "coverage_threshold_medium": threshold_medium,
    }
    sources: list[Path] = []
    for dp, dns, fns in os.walk(project_dir):
        dns[:] = [d for d in dns if d not in EXCLUDE_DIRS and not d.startswith(".")]
        for fn in fns:
            p = Path(dp) / fn
            if p.suffix.lower() not in SOURCE_EXTS:
                continue
            try:
                if p.stat().st_size > MAX_FILE_BYTES:
                    continue
            except OSError:
                continue
            sources.append(p)

    env_pat = re.compile(r"(?:process\.env\.([A-Z][A-Z0-9_]*)|os\.getenv\([\"']([A-Z][A-Z0-9_]*)[\"']\)|os\.environ\[[\"']([A-Z][A-Z0-9_]*)[\"']\]|ENV\[[\"']([A-Z][A-Z0-9_]*)[\"']\]|getenv\([\"']([A-Z][A-Z0-9_]*)[\"']\))")
    log_adhoc_pat = re.compile(r"\b(?:console\.(?:log|info|warn|error|debug)|print\s*\(|println!|fmt\.Println)")
    log_no_level_pat = re.compile(r"\blog(?:ger)?\s*\(\s*[\"']")
    fn_pat = re.compile(r"^\s*(?:async\s+)?(?:function\s+\w+|def\s+\w+|fn\s+\w+|public\s+\w+\s+\w+\s*\()", re.MULTILINE)
    docstring_pat = re.compile(r'(?:^\s*"""|^\s*/\*\*|^\s*///)', re.MULTILINE)
    api_route_pat = re.compile(r"@(?:app|router)\.(?:get|post|put|delete|patch)\s*\(|app\.(?:get|post|put|delete|patch)\s*\(|router\.(?:get|post|put|delete|patch)\s*\(")

    for p in sources[:1000]:
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        metrics["loc_total"] += text.count("\n")
        for m in env_pat.finditer(text):
            metrics["env_var_refs"] += 1
            for g in m.groups():
                if g:
                    metrics["env_var_keys"].add(g)
        metrics["adhoc_logging_count"] += len(log_adhoc_pat.findall(text))
        metrics["logger_no_level_count"] += len(log_no_level_pat.findall(text))
        metrics["function_count"] += len(fn_pat.findall(text))
        metrics["function_doc_count"] += len(docstring_pat.findall(text))
        metrics["api_routes_count"] += len(api_route_pat.findall(text))

    # Changed files w/o test (heuristic — last 20 modified source files via mtime)
    by_mtime = sorted(sources, key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    test_pats = ("test", "spec", "_test", "tests/", "__tests__/")
    for p in by_mtime[:30]:
        rel = str(p.relative_to(project_dir))
        if any(t in rel for t in test_pats):
            continue
        # Look for sibling test
        candidate_names = [
            p.with_name(p.stem + ".test" + p.suffix),
            p.with_name(p.stem + ".spec" + p.suffix),
            p.with_name(f"test_{p.stem}.py"),
            p.with_name(p.stem + "_test.go"),
        ]
        if not any(c.exists() for c in candidate_names):
            tests_dir = project_dir / "tests" / p.relative_to(project_dir).parent / p.name
            if not tests_dir.exists():
                metrics["changed_files_no_test"].append(rel)
        if len(metrics["changed_files_no_test"]) >= 10:
            break

    return metrics


def run_coverage_delegate(project_dir: Path, stack_tags: set[str]) -> float | None:
    here = Path(__file__).parent
    sh = here / "mcl-ops-coverage.sh"
    if not sh.exists():
        return None
    rules_mod = _load("mcl-ops-rules")
    has, framework = rules_mod.has_test_framework(project_dir, stack_tags)
    if not has or not framework:
        return None
    try:
        out = subprocess.run(["bash", str(sh), str(project_dir), framework],
                             capture_output=True, text=True, timeout=90)
        d = json.loads(out.stdout or "{}")
        return d.get("total")
    except Exception:
        return None


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
    log = state_dir / "ops-findings.jsonl"
    try:
        with log.open("a", encoding="utf-8") as f:
            for x in findings:
                f.write(json.dumps(x) + "\n")
    except OSError:
        pass


def load_threshold(state_dir: Path) -> tuple[int, int]:
    cfg = state_dir / "ops-config.json"
    if not cfg.exists():
        return 50, 70
    try:
        d = json.loads(cfg.read_text(encoding="utf-8"))
        ops = d.get("ops") or d
        return int(ops.get("coverage_threshold_high", 50)), int(ops.get("coverage_threshold_medium", 70))
    except Exception:
        return 50, 70


def mode_full(rules_mod, project_dir: Path, state_dir: Path,
              stack_tags: set[str]) -> dict:
    rv = hashlib.sha1(rules_mod.rules_version_seed().encode("utf-8")).hexdigest()
    start = datetime.now(timezone.utc)
    th_high, th_med = load_threshold(state_dir)
    print("[MCL] Aggregating ops metrics...", file=sys.stderr)
    metrics = aggregate_metrics(project_dir, stack_tags, th_high, th_med)
    print("[MCL] Coverage delegate...", file=sys.stderr)
    metrics["coverage_total"] = run_coverage_delegate(project_dir, stack_tags)
    if metrics["coverage_total"] is not None:
        audit_log(state_dir, "ops-coverage-delegate", "mcl-ops-scan",
                  f"total={metrics['coverage_total']:.1f} threshold_high={th_high} threshold_med={th_med}")
    else:
        audit_log(state_dir, "ops-coverage-skip", "mcl-ops-scan",
                  "reason=binary-missing-or-no-test-framework")
    findings = [f.to_dict() for f in rules_mod.scan_project(project_dir, stack_tags, metrics)]
    duration_ms = int((datetime.now(timezone.utc) - start).total_seconds() * 1000)
    high = sum(1 for f in findings if f["severity"] == "HIGH")
    med = sum(1 for f in findings if f["severity"] == "MEDIUM")
    low = sum(1 for f in findings if f["severity"] == "LOW")
    if findings:
        append_findings(state_dir, findings)
    cats = sorted({f.get("category", "") for f in findings} - {""})
    audit_log(state_dir, "ops-scan-full", "mcl-stop",
              f"high={high} med={med} low={low} duration_ms={duration_ms} categories={','.join(cats) or 'none'} tags={','.join(sorted(stack_tags))}")
    return {"findings": findings, "high_count": high, "med_count": med, "low_count": low,
            "duration_ms": duration_ms, "rules_version": rv,
            "categories_scanned": cats, "coverage_total": metrics["coverage_total"]}


def render_markdown(result: dict, lang: str, state_dir: Path) -> str:
    parts = [f"# {L(lang, 'title')}", ""]
    parts.append(f"_{L(lang, 'duration')}: {result.get('duration_ms', 0)} ms; "
                 f"{L(lang, 'categories')}: {', '.join(result.get('categories_scanned') or ['none'])}; "
                 f"coverage={result.get('coverage_total') if result.get('coverage_total') is not None else 'n/a'}_")
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
            parts.append(f"- **{f['rule_id']}** [{cat}] `{f['file']}:{f['line']}` — {f['message']}")
        parts.append("")
    if not result["findings"]:
        parts.append(f"_{L(lang, 'no_findings')}_")
    parts.append(f"\n**Findings log:** `{state_dir}/ops-findings.jsonl`")
    return "\n".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["incremental", "full", "report"], required=True)
    ap.add_argument("--state-dir", required=True, type=Path)
    ap.add_argument("--project-dir", required=True, type=Path)
    ap.add_argument("--target", type=Path)
    ap.add_argument("--lang", default="en")
    ap.add_argument("--markdown", action="store_true")
    args = ap.parse_args()

    rules_mod = _load("mcl-ops-rules")
    stack_tags = detect_stack_tags(args.project_dir)
    result = mode_full(rules_mod, args.project_dir, args.state_dir, stack_tags)

    if args.markdown or args.mode == "report":
        print(render_markdown(result, args.lang, args.state_dir))
    else:
        print(json.dumps(result, default=lambda o: list(o) if isinstance(o, set) else str(o)))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as _e:
        import traceback as _tb
        print(json.dumps({"error": str(_e)[:500], "traceback": _tb.format_exc()[-1500:]}))
        sys.exit(3)
