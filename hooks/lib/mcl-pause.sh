#!/usr/bin/env bash
# MCL Pause Helper (8.10.0).
#
# Public API (when sourced from a hook):
#   mcl_pause_on_error <source> <tool> <error_msg> <suggested_fix>
#       - Set state.paused_on_error.active=true with full context
#       - Audit pause-on-error
#       - Caller responsibility: emit decision:block JSON
#   mcl_pause_check
#       - Print "true" if paused, "false" otherwise
#       - Used by hook short-circuits
#   mcl_pause_resume <resolution>
#       - Clear paused_on_error.active, save resolution
#       - Audit resume-from-pause
#   mcl_pause_block_reason
#       - Render the "MCL PAUSED" decision:block reason text
#         (used by mcl-pre-tool.sh and mcl-stop.sh sticky-pause guards)
#
# Persistence: paused state survives session boundaries (sticky).
# Only /mcl-resume keyword or natural-language ack via skill clears it.

# Guard against double-source.
if [ -n "${_MCL_PAUSE_LIB_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
_MCL_PAUSE_LIB_LOADED=1

mcl_pause_on_error() {
  local src="$1" tool="$2" emsg="$3" sfix="$4"
  local ts current_phase phase_name
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  current_phase="$(mcl_state_get current_phase 2>/dev/null || echo unknown)"
  phase_name="$(mcl_state_get phase_name 2>/dev/null || echo unknown)"

  # Truncate error to 500 chars for state safety.
  emsg="$(printf '%s' "$emsg" | head -c 500)"
  sfix="$(printf '%s' "$sfix" | head -c 500)"

  # Build paused_on_error JSON via python (handles escaping).
  local payload
  payload="$(python3 -c '
import json, sys
print(json.dumps({
    "active": True,
    "timestamp": sys.argv[1],
    "source": sys.argv[2],
    "tool": sys.argv[3],
    "error_msg": sys.argv[4],
    "last_phase": sys.argv[5],
    "last_phase_name": sys.argv[6],
    "suggested_fix": sys.argv[7],
    "user_resolution": None,
}))
' "$ts" "$src" "$tool" "$emsg" "$current_phase" "$phase_name" "$sfix" 2>/dev/null)"

  if [ -n "$payload" ]; then
    mcl_state_set paused_on_error "$payload" >/dev/null 2>&1 || true
  fi
  mcl_audit_log "pause-on-error" "$(basename "${0:-mcl-pause.sh}")" \
    "source=${src} tool=${tool} phase=${current_phase}"
  command -v mcl_trace_append >/dev/null 2>&1 && \
    mcl_trace_append pause_on_error "$src"
}

mcl_pause_check() {
  local active
  active="$(python3 -c '
import json, os, sys
sf = os.environ.get("MCL_STATE_FILE") or os.path.join(
    os.environ.get("MCL_STATE_DIR") or
    os.path.join(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd(), ".mcl"),
    "state.json")
try:
    with open(sf) as f:
        d = json.load(f)
    p = d.get("paused_on_error") or {}
    print("true" if p.get("active") else "false")
except Exception:
    print("false")
' 2>/dev/null)"
  printf '%s\n' "${active:-false}"
}

mcl_pause_resume() {
  local resolution="$1"
  resolution="$(printf '%s' "$resolution" | head -c 500)"
  # Read existing paused_on_error, set active=false, store user_resolution.
  local payload
  payload="$(python3 -c '
import json, os, sys
sf = os.environ.get("MCL_STATE_FILE") or os.path.join(
    os.environ.get("MCL_STATE_DIR") or
    os.path.join(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd(), ".mcl"),
    "state.json")
res = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    with open(sf) as f:
        d = json.load(f)
    p = dict(d.get("paused_on_error") or {})
    p["active"] = False
    p["user_resolution"] = res
    print(json.dumps(p))
except Exception:
    print(json.dumps({"active": False, "user_resolution": res}))
' "$resolution" 2>/dev/null)"
  if [ -n "$payload" ]; then
    mcl_state_set paused_on_error "$payload" >/dev/null 2>&1 || true
  fi
  mcl_audit_log "resume-from-pause" "$(basename "${0:-mcl-pause.sh}")" \
    "resolution_len=${#resolution}"
  command -v mcl_trace_append >/dev/null 2>&1 && \
    mcl_trace_append resume_from_pause ""
}

mcl_pause_on_scan_error() {
  # Args: <orchestrator_name> <result_json>
  # If result_json has "error" key → pause + emit decision:deny block + return 0
  # If no error → return 1 (caller continues normally)
  local orch="$1" rj="$2"
  local err
  err="$(printf '%s' "$rj" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read() or "{}")
    if d.get("error"):
        print(d.get("error"))
except Exception:
    pass
' 2>/dev/null)"
  if [ -z "$err" ]; then
    return 1
  fi
  mcl_pause_on_error "scan-helper" "$orch" "$err" \
    "Re-run scan or check dependencies. Traceback in audit.log via stderr."
  local reason
  reason="$(mcl_pause_block_reason)"
  python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": sys.argv[1]
    }
}))
' "$reason" 2>/dev/null
  return 0
}

mcl_pause_block_reason() {
  # Render the localized-ish block reason from current state.
  python3 -c '
import json, os, sys
sf = os.environ.get("MCL_STATE_FILE") or os.path.join(
    os.environ.get("MCL_STATE_DIR") or
    os.path.join(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd(), ".mcl"),
    "state.json")
try:
    with open(sf) as f:
        d = json.load(f)
    p = d.get("paused_on_error") or {}
except Exception:
    p = {}
src = p.get("source", "?")
tool = p.get("tool", "?")
err = p.get("error_msg", "")
fix = p.get("suggested_fix", "")
phase = p.get("last_phase", "?")
phase_name = p.get("last_phase_name", "")
ts = p.get("timestamp", "?")
out = (
  "⚠️ MCL PAUSED — " + src + "\n\n"
  "Tool: " + tool + "\n"
  "Error: " + err + "\n\n"
  "Suggested fix:\n" + fix + "\n\n"
  "Last phase: " + str(phase) + " (" + phase_name + ")\n\n"
  "MCL will not advance until you resolve this. Two ways to resume:\n\n"
  "  (A) Run `/mcl-resume <your resolution>` keyword command\n"
  "  (B) Explain your resolution in natural language; MCL detects acknowledgment\n\n"
  "Audit: pause-on-error logged at " + ts
)
print(out)
' 2>/dev/null
}
