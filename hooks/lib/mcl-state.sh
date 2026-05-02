#!/bin/bash
# MCL State — .mcl/state.json schema + atomic helpers.
#
# Sourceable library AND CLI. All reads survive corruption by falling
# back to a default Aşama-1 state and logging to stderr. All writes use
# tmp-file + mv (atomic rename) so a crash mid-write cannot leave the
# state file half-serialized.
#
# State file lives at `<project>/.mcl/state.json` — one file per working
# directory.
#
# Schema v3 (since MCL 9.0.0):
#   current_phase: 1, 4, 7, 11 (coarse buckets — Aşama 1=GATHER,
#                  4=SPEC_REVIEW, 7=EXECUTE, 11=DELIVER)
#   Sub-states refine within Aşama 7: pattern_scan_due, ui_sub_phase,
#   risk_review_state, quality_review_state.
#
# Schema v3 is INCOMPATIBLE with prior versions. On schema mismatch the
# state file is reset to v3 default — no migration. v9.0.0 is a major
# rewrite; in-progress task state from older MCL is discarded.
#
# CLI usage:
#   mcl-state.sh init                          # create default if missing
#   mcl-state.sh get <field>                   # print one field
#   mcl-state.sh dump                          # print full JSON
#
# Sourced usage:
#   source hooks/lib/mcl-state.sh
#   mcl_state_get current_phase
#   mcl_state_set spec_approved true

set -u

MCL_STATE_SCHEMA_VERSION=3
MCL_STATE_DIR="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}"
MCL_STATE_FILE="${MCL_STATE_FILE:-$MCL_STATE_DIR/state.json}"

_mcl_state_default() {
  local now
  now="$(date +%s)"
  cat <<JSON
{
  "schema_version": ${MCL_STATE_SCHEMA_VERSION},
  "current_phase": 1,
  "phase_name": "GATHER",
  "spec_approved": false,
  "spec_hash": null,
  "plugin_gate_active": false,
  "plugin_gate_missing": [],
  "ui_flow_active": false,
  "ui_sub_phase": null,
  "ui_build_hash": null,
  "ui_reviewed": false,
  "scope_paths": [],
  "pattern_scan_due": false,
  "pattern_files": [],
  "pattern_summary": null,
  "pattern_level": null,
  "pattern_ask_pending": false,
  "precision_audit_done": false,
  "risk_review_state": null,
  "quality_review_state": null,
  "open_severity_count": 0,
  "tdd_compliance_score": null,
  "rollback_sha": null,
  "rollback_notice_shown": false,
  "tdd_last_green": null,
  "last_write_ts": null,
  "plan_critique_done": false,
  "restart_turn_ts": null,
  "last_update": ${now}
}
JSON
}

_mcl_state_auth_check() {
  # Return 0 iff the ENTRY script (what the OS executed) is one of our
  # own hook files under hooks/. `$0` in a sourced library reflects the
  # parent script, so this catches:
  #   - CLI invocations of mcl-state.sh itself → $0 = mcl-state.sh → deny
  #   - `bash -c "source .../mcl-state.sh; mcl_state_set ..."` → $0 = bash → deny
  #   - Hooks that source this lib → $0 = hook path → allow
  # Does NOT rely on env tokens (children would inherit them, unsafe).
  local entry_abs hooks_dir
  entry_abs="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
  hooks_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
  case "$entry_abs" in
    "$hooks_dir"/mcl-activate.sh)    return 0 ;;
    "$hooks_dir"/mcl-stop.sh)        return 0 ;;
    "$hooks_dir"/mcl-pre-tool.sh)    return 0 ;;
    "$hooks_dir"/mcl-post-tool.sh)   return 0 ;;
    "$hooks_dir"/mcl-user-prompt.sh) return 0 ;;
  esac
  return 1
}

_mcl_state_valid() {
  # Return 0 if stdin is parseable JSON with v3 schema. Older schemas
  # are rejected so mcl_state_init can reset them to v3 default — no
  # backward-compat migration in v9.0.0.
  python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    assert isinstance(obj, dict)
    assert obj.get("schema_version") == 3
    assert isinstance(obj.get("current_phase"), int)
    assert 1 <= obj["current_phase"] <= 11
except Exception:
    sys.exit(1)
' 2>/dev/null
}

mcl_state_init() {
  mkdir -p "$MCL_STATE_DIR" 2>/dev/null || true
  if [ ! -f "$MCL_STATE_FILE" ]; then
    _mcl_state_write_raw "$(_mcl_state_default)"
    return 0
  fi
  # File exists — check schema version. On mismatch, reset (no migration).
  local current_version
  current_version="$(python3 -c '
import json, sys
try:
    obj = json.load(open(sys.argv[1]))
    print(obj.get("schema_version", 0))
except Exception:
    print(0)
' "$MCL_STATE_FILE" 2>/dev/null)"
  if [ "$current_version" != "3" ]; then
    cp "$MCL_STATE_FILE" "${MCL_STATE_FILE}.pre-v9-backup" 2>/dev/null || true
    _mcl_state_write_raw "$(_mcl_state_default)"
    mcl_audit_log "schema-reset-to-v3" "$(basename "${0:-unknown}")" "old_version=${current_version} backup=${MCL_STATE_FILE}.pre-v9-backup"
  fi
}

mcl_state_read() {
  # Echo the current state JSON. On any failure, echo the default and
  # log the reason to stderr — NEVER block the caller.
  if [ ! -f "$MCL_STATE_FILE" ]; then
    _mcl_state_default
    return 0
  fi
  local body
  body="$(cat "$MCL_STATE_FILE" 2>/dev/null)"
  if [ -z "$body" ]; then
    echo "mcl-state: empty state file, returning default" >&2
    _mcl_state_default
    return 0
  fi
  if ! printf '%s' "$body" | _mcl_state_valid; then
    echo "mcl-state: corrupt or wrong-schema state file, returning default (keeping copy at ${MCL_STATE_FILE}.corrupt)" >&2
    cp "$MCL_STATE_FILE" "${MCL_STATE_FILE}.corrupt" 2>/dev/null || true
    _mcl_state_default
    return 0
  fi
  printf '%s\n' "$body"
}

_mcl_state_write_raw() {
  # Atomic write: tmp file in same dir, then mv. Same-dir mv is atomic
  # on POSIX filesystems. Gated by auth check so no unauthorized caller
  # can reach the filesystem write path — even if they know the helper
  # name.
  local caller="${0:-unknown}"
  if ! _mcl_state_auth_check; then
    echo "mcl-state: write denied — unauthorized caller: $caller" >&2
    mcl_audit_log "deny-write" "$caller" "unauthorized"
    return 2
  fi
  mkdir -p "$MCL_STATE_DIR" 2>/dev/null || true
  local tmp
  tmp="${MCL_STATE_FILE}.tmp.$$"
  if printf '%s\n' "$1" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$MCL_STATE_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
    return 1
  fi
}

mcl_state_get() {
  # mcl_state_get <field> — prints scalar value (bool/int as literals,
  # null as empty string, string without quotes).
  local field="$1"
  mcl_state_read | python3 -c '
import json, sys
field = sys.argv[1]
try:
    obj = json.loads(sys.stdin.read())
    val = obj.get(field)
    if val is None:
        print("")
    elif isinstance(val, bool):
        print("true" if val else "false")
    else:
        print(val)
except Exception:
    sys.exit(1)
' "$field" 2>/dev/null
}

mcl_state_set() {
  # mcl_state_set <field> <value> — value is interpreted as JSON if it
  # parses, otherwise as a string. Always bumps last_update.
  local field="$1" value="$2"
  local current
  current="$(mcl_state_read)"
  local updated
  updated="$(printf '%s' "$current" | python3 -c '
import json, sys, time
field, raw = sys.argv[1], sys.argv[2]
obj = json.loads(sys.stdin.read())
try:
    val = json.loads(raw)
except Exception:
    val = raw
obj[field] = val
obj["last_update"] = int(time.time())
print(json.dumps(obj, indent=2))
' "$field" "$value" 2>/dev/null)"
  if [ -z "$updated" ]; then
    echo "mcl-state: set failed for field=$field" >&2
    return 1
  fi
  if _mcl_state_write_raw "$updated"; then
    mcl_audit_log "set" "$(basename "${0:-unknown}")" "field=${field} value=${value}"
    return 0
  fi
  return 1
}

mcl_state_dump() {
  mcl_state_read
}

mcl_state_reset() {
  _mcl_state_write_raw "$(_mcl_state_default)"
}

mcl_debug_log() {
  # Append one forensic line to `.mcl/debug.log` when MCL_DEBUG=1.
  # Fields: timestamp | hook | event | detail. No rotation, no levels.
  [ "${MCL_DEBUG:-0}" = "1" ] || return 0
  local dir="${MCL_STATE_DIR}"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s | %s | %s | %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" "$3" \
    >> "$dir/debug.log" 2>/dev/null || true
}

mcl_audit_log() {
  # Security-relevant audit trail — ALWAYS ON regardless of MCL_DEBUG.
  # Every state write attempt (allow or deny) lands here so Claude-
  # driven bypass attempts are visible to the developer after the fact.
  # Fields: timestamp | event | caller | detail.
  local dir="${MCL_STATE_DIR}"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s | %s | %s | %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" "$3" \
    >> "$dir/audit.log" 2>/dev/null || true
}

_mcl_audit_emitted_in_session() {
  # Returns 1 if `event_name` audit fired in current session, else 0.
  # Optional `idem_marker` (arg 2): if that marker is also present in
  # the session, returns 0 (already-handled). Used by phase-progression
  # scanners and by v10.1.8 skip enforcement gate.
  #
  # Defined here (since v10.1.8) so both mcl-stop.sh and mcl-pre-tool.sh
  # can use it. Stop hook keeps a local copy for backward-compat.
  local event_name="$1"
  local idem_marker="${2:-}"
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  if [ ! -f "$audit_file" ]; then echo 0; return; fi
  python3 - "$audit_file" "$trace_file" "$event_name" "$idem_marker" 2>/dev/null <<'PYEOF' || echo 0
import os, sys
audit_path, trace_path, event_name, idem = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
session_ts = ""
try:
    if os.path.isfile(trace_path):
        for line in open(trace_path, "r", encoding="utf-8", errors="replace"):
            if "| session_start |" in line:
                session_ts = line.split("|", 1)[0].strip()
except Exception:
    pass
emitted = False
already = False
try:
    needle_emit = f"| {event_name} |"
    needle_idem = f"| {idem} |" if idem else None
    for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        if needle_emit in line:
            emitted = True
        if needle_idem and needle_idem in line:
            already = True
except Exception:
    pass
print(1 if (emitted and not already) else 0)
PYEOF
}

_mcl_loop_breaker_count() {
  # Counts how many times a given audit event fired in the current
  # session. Used by hard-enforcement blocks to fail-open after 3
  # consecutive same-cause blocks so a stuck model cannot trap the
  # developer in an infinite loop. Session boundary = most recent
  # `session_start` event in trace.log.
  #
  # Defined here (since v10.1.7) so both mcl-stop.sh and mcl-pre-tool.sh
  # can use it. Stop hook keeps a local copy for backward-compat.
  local event="$1"
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  if [ ! -f "$audit_file" ]; then echo 0; return; fi
  python3 - "$audit_file" "$trace_file" "$event" 2>/dev/null <<'PYEOF' || echo 0
import os, sys
audit_path, trace_path, event = sys.argv[1], sys.argv[2], sys.argv[3]
session_ts = ""
try:
    if os.path.isfile(trace_path):
        with open(trace_path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                if "| session_start |" in line:
                    parts = line.split("|", 1)
                    if parts:
                        session_ts = parts[0].strip()
except Exception:
    pass
count = 0
needle = f"| {event} |"
try:
    with open(audit_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if needle not in line:
                continue
            ts = line.split("|", 1)[0].strip()
            if not session_ts or ts >= session_ts:
                count += 1
except Exception:
    pass
print(count)
PYEOF
}

mcl_get_active_phase() {
  # Returns the active aşama string (1..12) from state.
  #
  # Mapping rules:
  #   current_phase == 1  AND precision_audit_done == false → "1" (gather)
  #   current_phase == 1  AND precision_audit_done == true  → "2" (audit just done; brief is transient)
  #                                                            (Aşama 3 translator is single-turn, never persisted)
  #   current_phase == 7  AND spec_hash set, spec_approved == false → "4" (spec review)
  #   current_phase == 7  AND pattern_scan_due == true  → "5" (pattern matching)
  #   current_phase == 7  AND ui_flow_active == true    → "6a"|"6b"|"6c" by ui_sub_phase
  #   current_phase == 7  AND risk_review_state == running    → "8"
  #   current_phase == 7  AND quality_review_state == running → "9"
  #   current_phase == 7  AND otherwise → "7" (code+TDD)
  #   current_phase == 11 → "11" (verify report)
  #   (Aşama 10 impact + Aşama 12 translation are transient single-turn states)
  #
  # Optional arg: path to state.json (default: $MCL_STATE_FILE)
  local state_file="${1:-${MCL_STATE_FILE}}"
  [ -f "$state_file" ] || { echo "1"; return 0; }

  python3 - "$state_file" 2>/dev/null <<'PYEOF'
import json, sys

try:
    obj = json.loads(open(sys.argv[1]).read())
except Exception:
    print("?"); sys.exit(0)

phase       = int(obj.get("current_phase") or 1)
approved    = obj.get("spec_approved") is True
spec_hash   = obj.get("spec_hash")
precision_done = obj.get("precision_audit_done") is True
ui_active   = obj.get("ui_flow_active") is True
ui_sub      = obj.get("ui_sub_phase") or ""
scan_due    = obj.get("pattern_scan_due") is True
risk_state  = obj.get("risk_review_state") or ""
qual_state  = obj.get("quality_review_state") or ""

if phase <= 1:
    print("2" if precision_done else "1"); sys.exit(0)

if phase == 4:
    print("4"); sys.exit(0)

if phase == 7:
    if scan_due:
        print("5"); sys.exit(0)
    if ui_active:
        sub_map = {"BUILD_UI": "6a", "REVIEW": "6b", "BACKEND": "6c"}
        if ui_sub in sub_map:
            print(sub_map[ui_sub]); sys.exit(0)
    if risk_state == "running":
        print("8"); sys.exit(0)
    if qual_state == "running":
        print("9"); sys.exit(0)
    print("7"); sys.exit(0)

if phase == 11:
    print("11"); sys.exit(0)

print("?")
PYEOF
}

# CLI dispatch — only when invoked directly, not when sourced.
# READ-ONLY from CLI. All write operations (set/init/reset) are gated by
# `_mcl_state_auth_check` and will be denied from this entry point —
# $0 would be mcl-state.sh, not an MCL hook. Write ops live inside the
# hooks only. To hard-reset state, delete `.mcl/state.json` directly.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cmd="${1:-dump}"
  case "$cmd" in
    get)    shift; mcl_state_get "$@" ;;
    dump)   mcl_state_dump ;;
    *)      echo "usage: $0 {get <field>|dump}  (read-only — writes live in hooks)" >&2; exit 2 ;;
  esac
fi
