#!/usr/bin/env bash
# Dynamic Status Injection — v13.0.4
#
# Reads gate-spec.json + audit.log + state.json, renders a focused
# per-turn phase status block. Read-only — never writes state.
#
# Public API:
#   _mcl_dsi_render <phase>            → stdout text (status block body)
#   _mcl_dsi_render_cli <args>         → standalone CLI for unit tests
#
# CLI mode:
#   bash mcl-dsi.sh --phase N --audit <audit.log> --spec <gate-spec.json> \
#                   [--lang tr|en] [--state <state.json>]
#
# Output language: TR by default; EN when --lang=en or MCL_LANG=en.
# All other languages fall back to EN labels (v13.1 will extend).
#
# Fail-open: any error prints a single diagnostic line; never exits non-zero.

_mcl_dsi_render() {
  local phase="$1"
  local spec_file="${MCL_GATE_SPEC:-${HOME}/.claude/skills/my-claude-lang/gate-spec.json}"
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  local state_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/state.json"
  local lang="${MCL_LANG:-tr}"

  python3 - "$spec_file" "$audit_file" "$trace_file" "$state_file" "$phase" "$lang" 2>/dev/null <<'PYEOF' || echo "DSI unavailable: helper crashed"
import json, os, re, sys

spec_path, audit_path, trace_path, state_path, phase, lang = sys.argv[1:7]

# Label tables — TR (calibration) + EN. Other 12 langs fall back to EN in v13.0.4.
L = {
    "tr": {
        "current": "Mevcut Aşama",
        "this_turn": "Bu turun zorunlu çıktısı",
        "remaining": "Bu fazda kalan",
        "next_phase": "Bir sonraki faz",
        "completed": "Tamamlandı — sonraki faza geç",
        "skip_eligible": "skip-eligible",
        "of": "/",
        "current_item": "Şu anda görüşülen",
        "items_declared_missing": "ZORUNLU: önce {audit} emit et (count=K). K bilinmeden dialog başlayamaz.",
        "ac_status": "AC {i}/{N}: red {r} green {g} refactor {x}",
        "scan_state": "Scan: {k} issue → Fixed: {m}/{k} → Rescan {rs}",
        "rescan_due": "rescan due",
        "rescan_zero": "0 (stable)",
        "yes": "evet", "no": "hayır",
        "partial_recovery": "⚠ PARTIAL SPEC RECOVERY — Spec yeniden emit edilmeli. Aşama 4'e dön.",
        "minimal_pre_spec": "Aşama {n} aktif — niyet/spec aşamasında. Tek odak: {next}.",
    },
    "en": {
        "current": "Current Phase",
        "this_turn": "This turn must produce",
        "remaining": "Remaining in this phase",
        "next_phase": "Next phase",
        "completed": "Completed — advance to next phase",
        "skip_eligible": "skip-eligible",
        "of": "/",
        "current_item": "Currently discussing",
        "items_declared_missing": "MANDATORY: emit {audit} first (count=K). Dialog cannot start without K.",
        "ac_status": "AC {i}/{N}: red {r} green {g} refactor {x}",
        "scan_state": "Scan: {k} issue → Fixed: {m}/{k} → Rescan {rs}",
        "rescan_due": "rescan due",
        "rescan_zero": "0 (stable)",
        "yes": "yes", "no": "no",
        "partial_recovery": "⚠ PARTIAL SPEC RECOVERY — Re-emit spec. Return to Aşama 4.",
        "minimal_pre_spec": "Aşama {n} active — intent/spec stage. Single focus: {next}.",
    },
}
labels = L.get(lang, L["en"])
TICK = "✓"; CROSS = "✗"

# Phase name lookup (Turkish canonical from MCL_Pipeline.md)
phase_names = {
    "1": "Niyet (gather)", "2": "Precision Audit", "3": "Engineering Brief",
    "4": "Spec + Verify", "5": "Pattern Matching", "6": "UI Build",
    "7": "UI Review", "8": "DB Design", "9": "TDD Execute",
    "10": "Risk Review", "11": "Code Review", "12": "Simplify",
    "13": "Performance", "14": "Security", "15": "Unit Tests",
    "16": "Integration Tests", "17": "E2E Tests", "18": "Load Tests",
    "19": "Impact Review", "20": "Verify Report", "21": "Localized Report",
    "22": "Completeness Audit",
}

# Session boundary
session_ts = ""
try:
    if os.path.isfile(trace_path):
        for line in open(trace_path, "r", encoding="utf-8", errors="replace"):
            if "| session_start |" in line:
                session_ts = line.split("|", 1)[0].strip()
except Exception:
    pass

audit_lines = []
try:
    if os.path.isfile(audit_path):
        for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
            ts = line.split("|", 1)[0].strip()
            if session_ts and ts < session_ts:
                continue
            audit_lines.append(line)
except Exception:
    pass

state = {}
try:
    if os.path.isfile(state_path):
        state = json.load(open(state_path, "r", encoding="utf-8"))
except Exception:
    pass

# Partial spec recovery override
if state.get("partial_spec") is True:
    print(labels["partial_recovery"])
    sys.exit(0)

try:
    spec = json.load(open(spec_path))
    pspec = spec["phases"][phase]
except Exception as e:
    print(f"DSI unavailable: spec load failed ({e})")
    sys.exit(0)

def has_audit(name):
    needle = f"| {name} |"
    return any(needle in l for l in audit_lines)

def parse_kv_last(name, key):
    needle = f"| {name} |"
    val = None
    for l in audit_lines:
        if needle in l:
            m = re.search(rf"\b{re.escape(key)}=(\d+)", l)
            if m:
                val = int(m.group(1))
    return val

def count_matching(pattern_regex):
    rx = re.compile(pattern_regex)
    return sum(1 for l in audit_lines if rx.search(l))

def distinct_indices(pattern_regex):
    rx = re.compile(pattern_regex)
    seen = set()
    for l in audit_lines:
        m = rx.search(l)
        if m:
            seen.add(int(m.group(1)))
    return seen

phase_int = int(phase)
phase_name = phase_names.get(phase, "?")
next_phase_int = phase_int + 1 if phase_int < 22 else None
next_phase_name = phase_names.get(str(next_phase_int), "—") if next_phase_int else None

# Skip-eligibility derived from gate-spec
skip_eligible = (
    "required_audits_any" in pspec
    and any("skipped" in a or "not-applicable" in a for a in pspec.get("required_audits_any", []))
)
next_skip = ""
if next_phase_int and str(next_phase_int) in spec["phases"]:
    nspec = spec["phases"][str(next_phase_int)]
    if "required_audits_any" in nspec and any(
        "skipped" in a or "not-applicable" in a for a in nspec["required_audits_any"]
    ):
        next_skip = f" ({labels['skip_eligible']})"

# Header
header = f"{labels['current']}: {phase} — {phase_name}"
print(header)

# Aşama 1-4 (pre-spec phases). Two modes:
# - Empty session (no Aşama 1 audit yet) → LOUD forbidden-list mode (v13.0.5)
# - Normal phase 2/3/4 → minimal status (cognitive overhead low)
if phase_int <= 4:
    has_any_a1 = any(
        any(marker in l for marker in (
            "| asama-1-", "| summary-confirm-approve |",
            "| asama-2-", "| asama-3-", "| asama-4-",
            "| precision-audit |", "| engineering-brief |",
        ))
        for l in audit_lines
    )
    if phase_int == 1 and not has_any_a1:
        # LOUD mode — first turn of session, no audit emitted yet.
        if lang == "tr":
            print("⛔ ASAMA 1 ZORUNLU — Henuz hicbir Asama 1 audit i emit edilmedi.")
            print("YASAK: Spec yazma. Write/Edit/MultiEdit cagirma. AskUserQuestion (Faz 4 spec onayi) acmaya kalkma.")
            print("ILK IS: Gelistiricinin niyetini anla. Tek soru sor (one-question-at-a-time)")
            print("       VEYA tum parametreler net ise SILENT-ASSUME path ile ozet uret.")
            print("Sonra: Bash mcl_audit_log ile asama-1-question-N veya summary-confirm-approve audit i emit et.")
            print("Audit i seed eden Bash + Read/Glob/Grep/LS aracilari serbest. Mutating tools KILITLI.")
        else:
            print("⛔ ASAMA 1 MANDATORY — No Aşama 1 audit emitted in this session yet.")
            print("FORBIDDEN: emitting a spec, calling Write/Edit/MultiEdit, opening AskUserQuestion (Faz 4 spec approval).")
            print("FIRST ACTION: understand developer intent. Ask one disambiguation question (one-question-at-a-time)")
            print("              OR if all parameters are clear, produce a SILENT-ASSUME summary.")
            print("Then: emit asama-1-question-N or summary-confirm-approve audit via Bash mcl_audit_log.")
            print("Audit-seed Bash + Read/Glob/Grep/LS are allowed; mutating tools are LOCKED.")
        sys.exit(0)
    # Normal minimal mode for phase 2/3/4 or phase 1 after first audit
    next_audit_hint = ""
    if "required_audits" in pspec:
        missing = [a for a in pspec["required_audits"] if not has_audit(a)]
        if missing:
            next_audit_hint = ", ".join(missing)
    if not next_audit_hint:
        next_audit_hint = "advance gate"
    print(labels["minimal_pre_spec"].format(n=phase, next=next_audit_hint))
    sys.exit(0)

t = pspec["type"]

# ── single ────────────────────────────────────────────────────────
if t == "single":
    if "required_audits_any" in pspec:
        missing = [a for a in pspec["required_audits_any"] if not has_audit(a)]
        if not missing or len(missing) < len(pspec["required_audits_any"]):
            print(labels["completed"])
            sys.exit(0)
        print(f"{labels['this_turn']}: {pspec['required_audits_any'][0]} (or any of: {', '.join(pspec['required_audits_any'])})")
    elif "required_audits" in pspec:
        missing = [a for a in pspec["required_audits"] if not has_audit(a)]
        if not missing:
            print(labels["completed"])
            sys.exit(0)
        print(f"{labels['this_turn']}: {missing[0]}")
        if len(missing) > 1:
            print(f"{labels['remaining']}: {', '.join(missing[1:])}")
    print(f"{labels['next_phase']}: {next_phase_int} — {next_phase_name}{next_skip}")
    sys.exit(0)

# ── section ───────────────────────────────────────────────────────
if t == "section":
    missing = [a for a in pspec["required_sections"] if not has_audit(a)]
    if not missing:
        print(labels["completed"])
    else:
        print(f"{labels['this_turn']}: {missing[0]}")
        if len(missing) > 1:
            print(f"{labels['remaining']}: {', '.join(missing[1:])}")
    print(f"{labels['next_phase']}: {next_phase_int} — {next_phase_name}{next_skip}")
    sys.exit(0)

# ── list (Aşama 10, 19) — KEY: unlimited-question handling ────────
if t == "list":
    declared_audit = pspec["declared_audit"]
    K = parse_kv_last(declared_audit, pspec.get("count_key", "count"))
    if K is None:
        print(labels["items_declared_missing"].format(audit=declared_audit))
        sys.exit(0)
    pat = pspec["item_audit_pattern"]
    rx_str = re.escape(pat).replace(r"\{n\}", r"(\d+)")
    resolved_indices = distinct_indices(r"\| " + rx_str + r" \|")
    M = len(resolved_indices)
    pending = K - M
    if pending <= 0:
        print(labels["completed"])
        print(f"{labels['next_phase']}: {next_phase_int} — {next_phase_name}{next_skip}")
        sys.exit(0)
    current_idx = (max(resolved_indices) + 1) if resolved_indices else 1
    print(f"{labels['remaining']}: {M}{labels['of']}{K} resolved, {pending} pending")
    print(f"{labels['current_item']}: #{current_idx}")
    next_audit = pat.replace("{n}", str(current_idx))
    print(f"{labels['this_turn']}: {next_audit}")
    sys.exit(0)

# ── iterative (11-14) ─────────────────────────────────────────────
if t == "iterative":
    scan_audit = pspec["scan_audit"]
    rescan_audit = pspec["rescan_audit"]
    K = parse_kv_last(scan_audit, "count") or 0
    if K == 0 and not has_audit(scan_audit):
        print(f"{labels['this_turn']}: {scan_audit} count=K")
        sys.exit(0)
    fix_pat = pspec["fix_audit_pattern"]
    fix_rx = re.escape(fix_pat).replace(r"\{n\}", r"(\d+)")
    M = len(distinct_indices(r"\| " + fix_rx + r" \|"))
    rescan_count = parse_kv_last(rescan_audit, "count")
    if rescan_count == 0:
        print(labels["completed"])
        print(f"{labels['next_phase']}: {next_phase_int} — {next_phase_name}{next_skip}")
        sys.exit(0)
    rs_label = labels["rescan_due"] if rescan_count is None or rescan_count > 0 else labels["rescan_zero"]
    print(labels["scan_state"].format(k=K, m=M, rs=rs_label))
    if M < K:
        next_audit = fix_pat.replace("{n}", str(M + 1))
        print(f"{labels['this_turn']}: {next_audit}")
    else:
        print(f"{labels['this_turn']}: {rescan_audit} count=<recount>")
    sys.exit(0)

# ── substep (Faz 9 — TDD) ────────────────────────────────────────
if t == "substep":
    must = parse_kv_last(pspec["ac_source_audit"], "must") or 0
    should = parse_kv_last(pspec["ac_source_audit"], "should") or 0
    total = must + should
    if total <= 0:
        print(labels["completed"])
        sys.exit(0)
    pat = pspec["audit_pattern"]
    triples = pspec["triple_audits"]
    # Per-AC status grid — render only the "current" AC (first incomplete)
    for i in range(1, total + 1):
        statuses = {}
        for tag in triples:
            audit_name = pat.replace("{i}", str(i)).replace("{tag}", tag)
            statuses[tag] = TICK if has_audit(audit_name) else CROSS
        if any(v == CROSS for v in statuses.values()):
            print(labels["ac_status"].format(
                i=i, N=total,
                r=statuses.get("red", "?"),
                g=statuses.get("green", "?"),
                x=statuses.get("refactor", "?"),
            ))
            # Next missing tag
            next_tag = next((tag for tag in triples if statuses[tag] == CROSS), None)
            if next_tag:
                next_audit = pat.replace("{i}", str(i)).replace("{tag}", next_tag)
                print(f"{labels['this_turn']}: {next_audit}")
            sys.exit(0)
    print(labels["completed"])
    print(f"{labels['next_phase']}: {next_phase_int} — {next_phase_name}{next_skip}")
    sys.exit(0)

# ── self-check (Faz 22) ───────────────────────────────────────────
if t == "self-check":
    needed = pspec["required_phases_complete"]
    missing = [n for n in needed if not has_audit(f"asama-{n}-complete")]
    if not missing:
        print(labels["completed"])
        sys.exit(0)
    print(f"{labels['remaining']}: {len(needed) - len(missing)}{labels['of']}{len(needed)} phases verified, {len(missing)} missing")
    print(f"{labels['this_turn']}: deep-dive Aşama {missing[0]} — verify completion")
    sys.exit(0)

print("DSI: unrecognized phase type")
PYEOF
}

# CLI entrypoint for unit tests
if [ "${1:-}" = "--cli" ] || [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  _PHASE=""; _AUDIT=""; _SPEC=""; _STATE=""; _LANG="tr"
  shift 2>/dev/null  # consume --cli if present
  while [ $# -gt 0 ]; do
    case "$1" in
      --phase) _PHASE="$2"; shift 2;;
      --audit) _AUDIT="$2"; shift 2;;
      --spec)  _SPEC="$2";  shift 2;;
      --state) _STATE="$2"; shift 2;;
      --lang)  _LANG="$2";  shift 2;;
      *) shift;;
    esac
  done
  [ -n "$_AUDIT" ] && export MCL_STATE_DIR="$(dirname "$_AUDIT")"
  [ -n "$_SPEC" ] && export MCL_GATE_SPEC="$_SPEC"
  export MCL_LANG="$_LANG"
  _mcl_dsi_render "$_PHASE"
fi
