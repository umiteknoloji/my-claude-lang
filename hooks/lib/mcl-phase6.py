#!/usr/bin/env python3
"""MCL Phase 6 — Double-check.

Three checks:
  (a) Audit trail completeness — required STEP audit events present in
      current session window
  (b) Final scan aggregation — re-run codebase/security/db/ui full scans;
      compare HIGH count against phase4_high_baseline; new HIGH = regression
  (c) Promise-vs-delivery — Phase 1 confirmed params (intent/constraints)
      keyword-match against modified files

Modes:
  run     — enforcement (returns JSON consumed by mcl-stop.sh)
  report  — on-demand markdown for /mcl-phase6-report

Trigger: mcl-stop.sh after standard Phase 4 reminder, when
phase_review_state=="done" AND phase6_double_check_done!=true.

Since 8.11.0.
"""
from __future__ import annotations
import argparse, json, os, re, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

REQUIRED_EVENTS = {
    "precision-audit": "Phase 1.7 Precision Audit",
    "engineering-brief": "Phase 1.5 Engineering Brief",
    "spec-approve": "Phase 3 spec approval",
    "phase-review-pending": "Phase 4 → 4.5 transition",
    "phase-review-running": "Phase 4 dialog active",
    "phase-review-impact": "Phase 4 (impact lens) impact review",
}
# phase5-verify is opt-in (8.11.0+ skill emits); soft fail on absence.
SOFT_REQUIRED_EVENTS = {
    "phase5-verify": "Phase 5 verification report",
    "spec-extract": "Phase 2 spec emit",
    "spec-save": "Phase 2 spec save (alternative)",
}

# State-population audit events (since 8.16.0). Skill prose emits these
# after `mcl_state_set` calls in Phase 1 handoff, Phase 1.7 audit
# emission, and Phase 4a → 4b transition. Missing event = LOW soft fail
# (skill prose model behavior; hook does not block).
STATE_POPULATION_EVENTS = {
    "phase1_state_populated": "Phase 1 → 1.7 handoff (intent/constraints/stack)",
    "phase1_ops_populated":   "Phase 1.7 ops dimensions classified",
    "phase1_perf_populated":  "Phase 1.7 perf budget classified",
    "ui_sub_phase_set":       "Phase 4a → 4b UI_REVIEW transition",
}

STOPWORDS = {
    "the", "a", "an", "and", "or", "but", "if", "then", "else", "for",
    "with", "to", "from", "of", "in", "on", "at", "by", "as", "is", "are",
    "was", "were", "be", "been", "being", "have", "has", "had", "do",
    "does", "did", "will", "would", "should", "could", "may", "might",
    "must", "shall", "can", "this", "that", "these", "those", "it", "its",
    "they", "them", "user", "users",  # generic user-* often false-positive
    "ile", "için", "ama", "veya", "ve", "bir", "bu", "şu", "olan", "var",
    "yok", "değil", "kullanıcı", "kullanıcılar",
}


def session_window(audit_log: Path, trace_log: Path) -> set[str]:
    """Return set of audit events seen in the current session window.

    Window = since the last `session_start` event in trace.log; falls back
    to last 200 audit lines if no session marker found.
    """
    events: set[str] = set()
    if not audit_log.exists():
        return events
    try:
        lines = audit_log.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return events
    # Find last session_start in trace.log to anchor window timestamp.
    anchor_ts: str | None = None
    if trace_log.exists():
        try:
            for tline in reversed(trace_log.read_text(encoding="utf-8", errors="replace").splitlines()):
                if "session_start" in tline:
                    parts = tline.split("|", 2)
                    if parts:
                        anchor_ts = parts[0].strip()
                    break
        except OSError:
            pass
    relevant = lines
    if anchor_ts:
        # Audit lines start with "YYYY-MM-DD HH:MM:SS | event | hook | detail".
        relevant = [ln for ln in lines if (ln.split(" | ", 1)[0] or "") >= anchor_ts]
    elif len(lines) > 200:
        relevant = lines[-200:]
    for ln in relevant:
        parts = ln.split(" | ")
        if len(parts) >= 2:
            events.add(parts[1].strip())
    return events


def check_audit_trail(state_dir: Path) -> tuple[list[dict], list[dict]]:
    """Return (high_findings, low_findings)."""
    audit_log = state_dir / "audit.log"
    trace_log = state_dir / "trace.log"
    seen = session_window(audit_log, trace_log)
    high: list[dict] = []
    low: list[dict] = []
    for ev, label in REQUIRED_EVENTS.items():
        if ev not in seen:
            high.append({
                "severity": "HIGH", "source": "phase6", "rule_id": f"P6-A-missing-{ev}",
                "file": str(audit_log), "line": 0,
                "message": f"Required audit event '{ev}' ({label}) missing from current session — phase may have been skipped.",
                "category": "phase6-audit-trail",
            })
    # Soft: spec-extract OR spec-save satisfies Phase 2.
    if not (("spec-extract" in seen) or ("spec-save" in seen)):
        high.append({
            "severity": "HIGH", "source": "phase6", "rule_id": "P6-A-missing-spec-emit",
            "file": str(audit_log), "line": 0,
            "message": "Neither 'spec-extract' nor 'spec-save' audit event found — Phase 2 spec emit appears skipped.",
            "category": "phase6-audit-trail",
        })
    if "phase5-verify" not in seen:
        low.append({
            "severity": "LOW", "source": "phase6", "rule_id": "P6-A-missing-phase5-verify",
            "file": str(audit_log), "line": 0,
            "message": "phase5-verify audit event missing — 8.10.x and earlier projects do not emit this; soft-fail (advisory).",
            "category": "phase6-audit-trail",
        })
    # State-population events (since 8.16.0): each missing event surfaces
    # as a LOW soft fail. They detect the case where skill prose forgot
    # to call the corresponding `mcl_state_set` + `mcl_audit_log` Bash.
    for ev, label in STATE_POPULATION_EVENTS.items():
        if ev not in seen:
            low.append({
                "severity": "LOW", "source": "phase6", "rule_id": f"P6-A-missing-{ev}",
                "file": str(audit_log), "line": 0,
                "message": f"State-population audit event '{ev}' ({label}) missing — skill prose Bash may not have run; downstream phases may have read default state.",
                "category": "phase6-audit-trail",
            })
    # Severity-skip violation check (since 8.19.0): for each HIGH or
    # MEDIUM-sec/db finding that the dialog SKIPPED (rather than fixing
    # or overriding), require a matching `phase4_override` audit event
    # naming the same rule_id. Mismatch → LOW soft fail.
    low.extend(check_severity_skip_violations(audit_log))
    # State-hack attempt check (since 9.0.0): any `deny-write | bash |
    # unauthorized` events surface as HIGH soft fail. The auth-check
    # rejected the writes, but the attempt itself is a misalignment
    # signal worth surfacing prominently in the Phase 6 report.
    high.extend(check_state_hack_attempts(audit_log))
    return high, low


def check_state_hack_attempts(audit_log: Path) -> list[dict]:
    """Count `deny-write | bash | unauthorized` events in current session.

    Each occurrence means the model tried to write state.json from an
    unauthorized caller (typically a `bash -c '... mcl_state_set ...'`
    invocation that failed token-auth). The write was rejected, but the
    attempt is forensically significant — it usually indicates the
    model is trying to bypass MCL phase logic rather than follow it.
    Surfaces as HIGH (single finding aggregating all occurrences) so
    it's prominent in the Phase 6 report, not buried as advisory.
    """
    findings: list[dict] = []
    if not audit_log.exists():
        return findings
    deny_count = 0
    try:
        for ln in audit_log.read_text(encoding="utf-8", errors="replace").splitlines():
            # Audit format: `<ts> | deny-write | <caller> | unauthorized`
            parts = [p.strip() for p in ln.split("|")]
            if len(parts) < 4:
                continue
            if parts[1] == "deny-write" and "unauthorized" in parts[3]:
                deny_count += 1
    except OSError:
        return findings
    if deny_count == 0:
        return findings
    return [{
        "severity": "HIGH",
        "source": "phase6",
        "rule_id": "P6-A-state-hack-attempt",
        "file": str(audit_log),
        "line": 0,
        "message": (
            f"Model attempted {deny_count} unauthorized state.json write(s) — "
            "auth-check rejected each one but the attempt itself signals a "
            "misaligned approach (e.g. trying to bypass MCL phase logic, "
            "patch state directly to skip a gate). Review session prose / "
            "skill prose drift; consider /mcl-restart on next stuck loop."
        ),
        "category": "phase6-audit-trail",
    }]


def check_severity_skip_violations(audit_log: Path) -> list[dict]:
    """Cross-reference Phase 4 dialog skip events against override events.

    Audit format expected (skill prose / hook records, all best-effort):
      `phase4_dialog | phase4 | rule=<RULE_ID> severity=<HIGH|MED|LOW> category=<sec|db|...> action=<apply|skip|override|make-rule>`
      `phase4_override | phase4 | rule=<RULE_ID> severity=<HIGH|MEDIUM> category=<sec|db|...> reason=<text>`

    The `8.19.0` skill prose emits the override event whenever the
    severity-aware dialog forces an override. If a HIGH or MEDIUM-sec/db
    finding shows action=skip without a corresponding override event,
    the developer bypassed the gate prematurely — surface advisory.
    """
    findings: list[dict] = []
    if not audit_log.exists():
        return findings
    skipped_strict: list[tuple[str, str]] = []  # (rule_id, severity)
    overridden: set[str] = set()
    try:
        for ln in audit_log.read_text(encoding="utf-8", errors="replace").splitlines():
            parts = ln.split(" | ")
            if len(parts) < 4:
                continue
            event, _, detail = parts[1].strip(), parts[2].strip(), parts[3].strip()
            if event == "phase4_dialog":
                d = _parse_kv(detail)
                rule = d.get("rule") or ""
                sev = (d.get("severity") or "").upper()
                cat = (d.get("category") or "").lower()
                action = (d.get("action") or "").lower()
                if action != "skip" or not rule:
                    continue
                strict = sev == "HIGH" or (sev in ("MED", "MEDIUM") and cat in ("sec", "security", "db", "database"))
                if strict:
                    skipped_strict.append((rule, sev))
            elif event == "phase4_override":
                d = _parse_kv(detail)
                rule = d.get("rule") or ""
                if rule:
                    overridden.add(rule)
    except OSError:
        return findings
    for rule, sev in skipped_strict:
        if rule in overridden:
            continue
        findings.append({
            "severity": "LOW", "source": "phase6",
            "rule_id": "P6-A-severity-skip-without-override",
            "file": str(audit_log), "line": 0,
            "message": (
                f"Phase 4 dialog skipped {sev} finding '{rule}' without a "
                f"matching `phase4_override` audit event — severity-aware "
                f"enforcement (8.19.0) requires override-with-reason for HIGH "
                f"and MEDIUM-sec/db findings."
            ),
            "category": "phase6-audit-trail",
        })
    return findings


def _parse_kv(detail: str) -> dict:
    """Parse `key=value key=value ...` audit detail into a dict.

    Tolerant of values containing spaces only when followed by another
    `key=` token; long free-text reasons survive as the trailing run.
    """
    out: dict = {}
    if not detail:
        return out
    # Greedy: split on whitespace, accumulate "key=value" pairs.
    tokens = detail.split()
    current_key = None
    current_val: list[str] = []
    for tok in tokens:
        if "=" in tok:
            if current_key is not None:
                out[current_key] = " ".join(current_val).strip()
            k, v = tok.split("=", 1)
            current_key = k.strip()
            current_val = [v]
        else:
            current_val.append(tok)
    if current_key is not None:
        out[current_key] = " ".join(current_val).strip()
    return out


def run_scan(orch_path: Path, state_dir: Path, project_dir: Path, lang: str) -> dict:
    """Run a scan orchestrator in --mode=full and return parsed JSON or {}."""
    if not orch_path.exists():
        return {}
    try:
        out = subprocess.run(
            ["python3", str(orch_path), "--mode=full",
             "--state-dir", str(state_dir), "--project-dir", str(project_dir),
             "--lang", lang],
            capture_output=True, text=True, timeout=180,
        )
    except Exception:
        return {}
    try:
        return json.loads(out.stdout or "{}")
    except json.JSONDecodeError:
        return {}


def check_final_scans(state_dir: Path, project_dir: Path, lang: str) -> list[dict]:
    """(b) re-run 4 scans; compare HIGH against phase4_high_baseline."""
    here = Path(__file__).parent
    state_file = state_dir / "state.json"
    baseline = {"security": 0, "db": 0, "ui": 0}
    try:
        d = json.loads(state_file.read_text(encoding="utf-8"))
        b = d.get("phase4_high_baseline") or {}
        for k in ("security", "db", "ui"):
            baseline[k] = int(b.get(k, 0))
    except Exception:
        pass

    findings: list[dict] = []
    scans = [
        ("security", here / "mcl-security-scan.py"),
        ("db", here / "mcl-db-scan.py"),
        ("ui", here / "mcl-ui-scan.py"),
    ]
    for cat, orch in scans:
        r = run_scan(orch, state_dir, project_dir, lang)
        # Skip on no-stack outcomes (no_db_stack / no_fe_stack / orchestrator error)
        if r.get("error") or r.get("no_db_stack") or r.get("no_fe_stack"):
            continue
        cur = int(r.get("high_count") or 0)
        delta = cur - baseline[cat]
        if delta > 0:
            sample = next((f for f in r.get("findings", []) if f.get("severity") == "HIGH"), {})
            findings.append({
                "severity": "HIGH", "source": "phase6", "rule_id": f"P6-B-{cat}-regression",
                "file": sample.get("file", "?"), "line": sample.get("line", 0),
                "message": f"{cat}: {delta} new HIGH finding(s) since Phase 4 baseline (was {baseline[cat]}, now {cur}). Phase 4 dialog fixes may have introduced regression.",
                "category": "phase6-regression",
            })
    # codebase-scan does not have severity routing the same way — skip in MVP
    return findings


def extract_keywords(text: str) -> set[str]:
    """Extract 4+ char alphabetic tokens, lowercase, stopwords filtered."""
    if not text:
        return set()
    tokens = re.findall(r"[A-Za-zÇĞİÖŞÜçğıöşü]{4,}", text)
    return {t.lower() for t in tokens if t.lower() not in STOPWORDS}


def check_promise_delivery(state_dir: Path, project_dir: Path) -> list[dict]:
    """(c) Phase 1 confirmed params → Phase 4 implementation keyword match."""
    state_file = state_dir / "state.json"
    intent = ""
    constraints = ""
    try:
        d = json.loads(state_file.read_text(encoding="utf-8"))
        intent = d.get("phase1_intent") or ""
        cs = d.get("phase1_constraints")
        if isinstance(cs, list):
            constraints = " ".join(str(c) for c in cs)
        else:
            constraints = str(cs or "")
    except Exception:
        pass

    if not intent and not constraints:
        # No Phase 1 state stored — soft skip (8.10.x and earlier)
        return [{
            "severity": "LOW", "source": "phase6", "rule_id": "P6-C-no-phase1-state",
            "file": str(state_file), "line": 0,
            "message": "Phase 1 intent/constraints not in state.json — promise-vs-delivery check skipped. Update Phase 1 skill to call mcl_state_set phase1_intent ...",
            "category": "phase6-promise",
        }]

    keywords = extract_keywords(intent + " " + constraints)
    if not keywords:
        return []

    # Walk source files, collect content for keyword search.
    EXTS = {".ts", ".tsx", ".js", ".jsx", ".py", ".rb", ".go", ".rs", ".java",
            ".kt", ".swift", ".cs", ".php", ".cpp", ".vue", ".svelte"}
    EXCL = {".git", "node_modules", "dist", "build", ".next", "target", "vendor",
            ".venv", "__pycache__", "coverage"}
    seen_words: set[str] = set()
    file_count = 0
    for dp, dns, fns in os.walk(project_dir):
        dns[:] = [d for d in dns if d not in EXCL and not d.startswith(".")]
        for fn in fns:
            p = Path(dp) / fn
            if p.suffix.lower() not in EXTS:
                continue
            try:
                if p.stat().st_size > 200_000:
                    continue
                txt = p.read_text(encoding="utf-8", errors="replace").lower()
            except OSError:
                continue
            file_count += 1
            for kw in keywords - seen_words:
                if kw in txt:
                    seen_words.add(kw)
            if seen_words == keywords:
                break
        if seen_words == keywords:
            break

    missing = sorted(keywords - seen_words)
    if not missing:
        return []
    return [{
        "severity": "MEDIUM", "source": "phase6", "rule_id": "P6-C-promise-gap",
        "file": str(state_file), "line": 0,
        "message": f"Phase 1 keyword(s) without implementation match (heuristic, {file_count} files scanned): {', '.join(missing[:8])}{' ...' if len(missing) > 8 else ''}",
        "category": "phase6-promise",
    }]


def audit_log(state_dir: Path, event: str, hook: str, detail: str) -> None:
    state_dir.mkdir(parents=True, exist_ok=True)
    log = state_dir / "audit.log"
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with log.open("a", encoding="utf-8") as f:
            f.write(f"{ts} | {event} | {hook} | {detail}\n")
    except OSError:
        pass


LOC = {
    "en": {
        "title": "Phase 6 Double-check Report",
        "audit_trail": "(a) Audit trail completeness",
        "final_scan": "(b) Final scan aggregation",
        "promise": "(c) Promise-vs-delivery",
        "no_findings": "All checks passed.",
        "duration": "Duration",
    },
    "tr": {
        "title": "Faz 6 Çift-kontrol Raporu",
        "audit_trail": "(a) Audit trail tamlığı",
        "final_scan": "(b) Final scan kümülasyonu",
        "promise": "(c) Söz-vs-teslimat",
        "no_findings": "Tüm kontroller geçti.",
        "duration": "Süre",
    },
}


def L(lang: str, key: str) -> str:
    return LOC.get(lang, LOC["en"]).get(key, LOC["en"][key])


def render_markdown(result: dict, lang: str, state_dir: Path) -> str:
    parts = [f"# {L(lang, 'title')}", ""]
    parts.append(f"_{L(lang, 'duration')}: {result.get('duration_ms', 0)} ms_")
    parts.append("")
    a = result.get("a_findings", [])
    b = result.get("b_findings", [])
    c = result.get("c_findings", [])
    soft_a = result.get("a_soft_findings", [])

    def render_block(title, items):
        if not items:
            return [f"## {title}", "", "_OK._", ""]
        out = [f"## {title} ({len(items)})", ""]
        for f in items:
            sev = f.get("severity", "?")
            out.append(f"- **[{sev}]** `{f['rule_id']}` — {f['message']}")
        out.append("")
        return out

    parts += render_block(L(lang, "audit_trail"), a + soft_a)
    parts += render_block(L(lang, "final_scan"), b)
    parts += render_block(L(lang, "promise"), c)
    if not (a or b or c):
        parts.append(f"_{L(lang, 'no_findings')}_")
    return "\n".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["run", "report"], required=True)
    ap.add_argument("--state-dir", required=True, type=Path)
    ap.add_argument("--project-dir", required=True, type=Path)
    ap.add_argument("--lang", default="en")
    ap.add_argument("--markdown", action="store_true")
    args = ap.parse_args()

    start = datetime.now(timezone.utc)
    a_high, a_low = check_audit_trail(args.state_dir)
    b_high = check_final_scans(args.state_dir, args.project_dir, args.lang)
    c_findings = check_promise_delivery(args.state_dir, args.project_dir)

    duration_ms = int((datetime.now(timezone.utc) - start).total_seconds() * 1000)
    high_count = len(a_high) + len(b_high) + sum(1 for f in c_findings if f["severity"] == "HIGH")
    med_count = sum(1 for f in c_findings if f["severity"] == "MEDIUM")
    low_count = len(a_low) + sum(1 for f in c_findings if f["severity"] == "LOW")

    audit_log(args.state_dir, "phase6-run-start",
              "mcl-phase6" if args.mode == "report" else "mcl-stop",
              f"required_events={len(REQUIRED_EVENTS)}")
    if a_high:
        audit_log(args.state_dir, "phase6-audit-gap", "mcl-phase6",
                  f"missing={','.join(f['rule_id'] for f in a_high)}")
    if b_high:
        audit_log(args.state_dir, "phase6-scan-regression", "mcl-phase6",
                  f"new_high={len(b_high)}")
    if any(f["severity"] != "LOW" for f in c_findings):
        audit_log(args.state_dir, "phase6-promise-gap", "mcl-phase6",
                  f"missing={len([f for f in c_findings if f['severity']=='MEDIUM'])}")

    result = {
        "a_findings": a_high, "a_soft_findings": a_low,
        "b_findings": b_high, "c_findings": c_findings,
        "high_count": high_count, "med_count": med_count, "low_count": low_count,
        "duration_ms": duration_ms,
    }

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
