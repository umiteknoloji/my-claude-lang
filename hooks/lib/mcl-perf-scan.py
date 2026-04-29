#!/usr/bin/env python3
"""MCL Perf Scan Orchestrator (8.14.0).

Modes: incremental | full | report | lighthouse
FE-only trigger (react-frontend/vue-frontend/svelte-frontend/html-static).
Reuses MCL_UI_URL env (shared with axe).
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, os, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

FE_TAGS = {"react-frontend", "vue-frontend", "svelte-frontend", "html-static"}
DEFAULT_CONFIG = {
    "bundle_budget_kb": 200,
    "bundle_critical_multiplier": 2,
    "image_high_kb": 500,
    "image_medium_kb": 100,
    "lcp_high_ms": 4000,
    "lcp_medium_ms": 2500,
    "cls_high": 0.25,
    "tbt_high_ms": 600,
}

LOC = {
    "en": {"title": "Performance Budget Report",
           "high": "HIGH severity", "medium": "MEDIUM severity", "low": "LOW severity",
           "no_findings": "All perf checks passed.",
           "duration": "Duration", "bundle_total": "Bundle gzipped",
           "no_fe": "No FE stack detected; perf scan skipped."},
    "tr": {"title": "Performans Bütçe Raporu",
           "high": "Yüksek şiddet", "medium": "Orta şiddet", "low": "Düşük şiddet",
           "no_findings": "Tüm perf kontrolleri geçti.",
           "duration": "Süre", "bundle_total": "Bundle (gzip)",
           "no_fe": "FE stack tespit edilmedi; perf taraması atlandı."},
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


def load_config(state_dir: Path) -> dict:
    cfg_file = state_dir / "perf-config.json"
    cfg = dict(DEFAULT_CONFIG)
    if cfg_file.exists():
        try:
            d = json.loads(cfg_file.read_text(encoding="utf-8"))
            cfg.update(d.get("perf") or d or {})
        except Exception:
            pass
    return cfg


def run_bundle(project_dir: Path) -> dict:
    here = Path(__file__).parent
    sh = here / "mcl-perf-bundle.sh"
    if not sh.exists():
        return {"found": False, "error": "delegate missing"}
    try:
        out = subprocess.run(["bash", str(sh), str(project_dir)],
                             capture_output=True, text=True, timeout=60)
        return json.loads(out.stdout or "{}")
    except Exception:
        return {"found": False}


def run_lighthouse(project_dir: Path) -> dict:
    here = Path(__file__).parent
    sh = here / "mcl-perf-lighthouse.sh"
    if not sh.exists():
        return {"ran": False, "reason": "delegate missing"}
    try:
        out = subprocess.run(["bash", str(sh), str(project_dir), "en", "--json"],
                             capture_output=True, text=True, timeout=120)
        return json.loads(out.stdout or "{}")
    except Exception:
        return {"ran": False, "reason": "delegate-error"}


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
    log = state_dir / "perf-findings.jsonl"
    try:
        with log.open("a", encoding="utf-8") as f:
            for x in findings:
                f.write(json.dumps(x) + "\n")
    except OSError:
        pass


def mode_full(project_dir: Path, state_dir: Path, stack_tags: set[str], lang: str,
              run_lh: bool) -> dict:
    has_fe = bool(stack_tags & FE_TAGS)
    if not has_fe:
        audit_log(state_dir, "perf-scan-skipped", "mcl-stop", "reason=no-fe-stack-tag")
        return {"findings": [], "no_fe_stack": True, "high_count": 0,
                "med_count": 0, "low_count": 0, "duration_ms": 0}
    cfg = load_config(state_dir)
    rules_mod = _load("mcl-perf-rules")
    start = datetime.now(timezone.utc)

    print("[MCL] Bundle delegate...", file=sys.stderr)
    bundle = run_bundle(project_dir)
    if bundle.get("found"):
        audit_log(state_dir, "perf-bundle-delegate", "mcl-perf-scan",
                  f"total_gzip_kb={bundle.get('total_gzip_bytes', 0)/1024:.1f} file_count={bundle.get('file_count', 0)} output_dir={bundle.get('output_dir', '?')}")
    else:
        audit_log(state_dir, "perf-bundle-skip", "mcl-perf-scan", "reason=no-build-output")

    cwv = {"ran": False}
    if run_lh and os.environ.get("MCL_UI_URL"):
        print("[MCL] Lighthouse delegate...", file=sys.stderr)
        cwv = run_lighthouse(project_dir)
        if cwv.get("ran"):
            audit_log(state_dir, "perf-lighthouse-delegate", "mcl-perf-scan",
                      f"url={cwv.get('url', '?')} lcp_ms={cwv.get('lcp_ms')} cls={cwv.get('cls')} tbt_ms={cwv.get('tbt_ms')}")

    print("[MCL] Image walk...", file=sys.stderr)
    findings_obj = rules_mod.scan(project_dir, bundle, cwv, cfg)
    findings = [f.to_dict() for f in findings_obj]
    duration_ms = int((datetime.now(timezone.utc) - start).total_seconds() * 1000)
    high = sum(1 for f in findings if f["severity"] == "HIGH")
    med = sum(1 for f in findings if f["severity"] == "MEDIUM")
    low = sum(1 for f in findings if f["severity"] == "LOW")
    if findings:
        append_findings(state_dir, findings)
    audit_log(state_dir, "perf-scan-full", "mcl-stop",
              f"high={high} med={med} low={low} duration_ms={duration_ms} categories=bundle,cwv,image bundle_kb={bundle.get('total_gzip_bytes', 0)/1024:.1f}")
    return {"findings": findings, "no_fe_stack": False,
            "high_count": high, "med_count": med, "low_count": low,
            "duration_ms": duration_ms,
            "bundle_total_kb": bundle.get("total_gzip_bytes", 0) / 1024,
            "cwv_ran": cwv.get("ran", False)}


def render_markdown(result: dict, lang: str, state_dir: Path) -> str:
    if result.get("no_fe_stack"):
        return f"# {L(lang, 'title')}\n\n_{L(lang, 'no_fe')}_\n"
    parts = [f"# {L(lang, 'title')}", ""]
    parts.append(f"_{L(lang, 'duration')}: {result.get('duration_ms', 0)} ms; "
                 f"{L(lang, 'bundle_total')}: {result.get('bundle_total_kb', 0):.1f} KB; "
                 f"CWV: {'ran' if result.get('cwv_ran') else 'skipped (no MCL_UI_URL)'}_")
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
            parts.append(f"- **{f['rule_id']}** [{cat}] `{f['file']}` — {f['message']}")
        parts.append("")
    if not result["findings"]:
        parts.append(f"_{L(lang, 'no_findings')}_")
    parts.append(f"\n**Findings log:** `{state_dir}/perf-findings.jsonl`")
    return "\n".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["incremental", "full", "report", "lighthouse"], required=True)
    ap.add_argument("--state-dir", required=True, type=Path)
    ap.add_argument("--project-dir", required=True, type=Path)
    ap.add_argument("--target", type=Path)
    ap.add_argument("--lang", default="en")
    ap.add_argument("--markdown", action="store_true")
    args = ap.parse_args()

    if args.mode == "lighthouse":
        here = Path(__file__).parent
        sh = here / "mcl-perf-lighthouse.sh"
        if not sh.exists():
            print("lighthouse helper missing", file=sys.stderr)
            return 1
        os.execvp("bash", ["bash", str(sh), str(args.project_dir), args.lang])
        return 0

    stack_tags = detect_stack_tags(args.project_dir)
    # Run lighthouse only when explicitly invoked via /mcl-perf-report (not L3 — avoids 60s in stop hook).
    run_lh = (args.mode == "report")
    result = mode_full(args.project_dir, args.state_dir, stack_tags, args.lang, run_lh)

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
