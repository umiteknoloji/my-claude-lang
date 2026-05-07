#!/usr/bin/env bash
# Universal gate engine — v13.0.0
#
# Reads gate-spec.json and audit.log, decides if a phase is complete.
# Stdout: "complete" | "incomplete" | "skipped"
# Side effect: caller is responsible for auto-emit + state advance.
#
# Public API: _mcl_gate_check <phase>
#
# Gate types supported:
#   - single     : required_audits all present (or required_audits_any one present)
#   - section    : required_sections all present
#   - list       : declared count K, K item-N-resolved audits present
#   - iterative  : last rescan count==0 (scan→fix→rescan loop)
#   - substep    : Faz 9 — ac_source emit (must=N should=M), N+M acceptance criteria,
#                  each with red/green/refactor triple audits
#   - self-check : Faz 22 — all listed phases have *-complete audits
#
# Legacy v12 fallback: if `asama-N-complete` already exists in session
# audit (model emit from v12.x era), treat as complete. Sunset in v13.1.

_MCL_GATE_SPEC="${MCL_GATE_SPEC:-${HOME}/.claude/skills/my-claude-lang/gate-spec.json}"

_mcl_gate_check() {
  local phase="$1"
  [ -z "$phase" ] && echo "incomplete" && return
  [ ! -f "$_MCL_GATE_SPEC" ] && echo "incomplete" && return
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"

  python3 - "$_MCL_GATE_SPEC" "$audit_file" "$trace_file" "$phase" 2>/dev/null <<'PYEOF' || echo "incomplete"
import json, os, re, sys
spec_path, audit_path, trace_path, phase = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

# Session boundary — only consider audits emitted in current session
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

try:
    spec = json.load(open(spec_path))
    pspec = spec["phases"][phase]
except Exception:
    print("incomplete"); sys.exit(0)

def has_audit(name):
    needle = f"| {name} |"
    return any(needle in l for l in audit_lines)

def parse_kv(name, key):
    needle = f"| {name} |"
    for l in audit_lines:
        if needle in l:
            m = re.search(rf"\b{re.escape(key)}=(\d+)", l)
            if m:
                return int(m.group(1))
    return None

def parse_kv_last(name, key):
    needle = f"| {name} |"
    val = None
    for l in audit_lines:
        if needle in l:
            m = re.search(rf"\b{re.escape(key)}=(\d+)", l)
            if m:
                val = int(m.group(1))
    return val

# ── Legacy v12 fallback (sunset v13.1) ────────────────────────────
# If model already emitted asama-N-complete (v12.x emit pattern), accept.
if has_audit(f"asama-{phase}-complete"):
    print("complete"); sys.exit(0)

t = pspec["type"]

# ── single ────────────────────────────────────────────────────────
if t == "single":
    if "required_audits_any" in pspec:
        if any(has_audit(n) for n in pspec["required_audits_any"]):
            print("complete"); sys.exit(0)
        print("incomplete"); sys.exit(0)
    if "required_audits" in pspec:
        if all(has_audit(n) for n in pspec["required_audits"]):
            print("complete"); sys.exit(0)
    print("incomplete"); sys.exit(0)

# ── section ───────────────────────────────────────────────────────
if t == "section":
    if all(has_audit(n) for n in pspec["required_sections"]):
        print("complete"); sys.exit(0)
    print("incomplete"); sys.exit(0)

# ── list ──────────────────────────────────────────────────────────
if t == "list":
    declared = parse_kv_last(pspec["declared_audit"], pspec.get("count_key", "count"))
    if declared is None or declared <= 0:
        print("incomplete"); sys.exit(0)
    pat = pspec["item_audit_pattern"]
    rx = re.compile(r"\| " + re.escape(pat).replace(r"\{n\}", r"\d+") + r" \|")
    resolved = sum(1 for l in audit_lines if rx.search(l))
    print("complete" if resolved >= declared else "incomplete"); sys.exit(0)

# ── iterative ─────────────────────────────────────────────────────
if t == "iterative":
    rescan = parse_kv_last(pspec["rescan_audit"], "count")
    if rescan is not None and rescan == 0:
        print("complete"); sys.exit(0)
    # Sonsuz loop koruması — max_rescans aşıldıysa warn-complete
    max_rescans = int(pspec.get("max_rescans", 5))
    rescan_count = sum(1 for l in audit_lines if f"| {pspec['rescan_audit']} |" in l)
    if rescan_count >= max_rescans:
        print("complete"); sys.exit(0)  # warn-only; caller emits give-up audit
    print("incomplete"); sys.exit(0)

# ── substep (Faz 9) ───────────────────────────────────────────────
if t == "substep":
    must = parse_kv(pspec["ac_source_audit"], "must")
    should = parse_kv(pspec["ac_source_audit"], "should")
    if must is None or should is None:
        print("incomplete"); sys.exit(0)
    total = must + should
    if total <= 0:
        print("complete"); sys.exit(0)  # nothing to TDD against
    pat = pspec["audit_pattern"]
    triples = pspec["triple_audits"]
    needed = total * len(triples)
    rx_str = re.escape(pat).replace(r"\{i\}", r"\d+").replace(r"\{tag\}", r"(?:" + r"|".join(re.escape(t) for t in triples) + r")")
    rx = re.compile(r"\| " + rx_str + r" \|")
    seen = sum(1 for l in audit_lines if rx.search(l))
    print("complete" if seen >= needed else "incomplete"); sys.exit(0)

# ── self-check (Faz 22) ───────────────────────────────────────────
if t == "self-check":
    needed = pspec["required_phases_complete"]
    for n in needed:
        if not has_audit(f"asama-{n}-complete"):
            print("incomplete"); sys.exit(0)
    print("complete"); sys.exit(0)

print("incomplete")
PYEOF
}
