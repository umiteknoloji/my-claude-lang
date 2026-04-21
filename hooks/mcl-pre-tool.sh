#!/bin/bash
# MCL PreToolUse Hook — mechanical gate that blocks mutating tools
# until the spec has been emitted AND approved by the developer.
#
# V1 block list (mutating tools):
#   Write, Edit, MultiEdit, NotebookEdit
#
# Allow conditions (all must hold for a mutating tool to pass):
#   current_phase >= 4
#   spec_approved == true
#
# Since 6.0.0: drift_detected no longer denies tools — it only emits a
# `drift-warn` audit entry and passes the tool through. The activate
# hook is responsible for surfacing the drift to the developer on their
# NEXT turn via a DRIFT_NOTICE block; resolution is a fresh
# AskUserQuestion approval call, not a hook-level block.
#
# Everything else (Read, Glob, Grep, WebFetch, WebSearch, TodoWrite,
# Bash, Task, ...) passes through unchanged. Bash and Task are handled
# by the prose layer in v1.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mcl-state.sh
source "$SCRIPT_DIR/lib/mcl-state.sh"

RAW_INPUT="$(cat 2>/dev/null || true)"

TOOL_NAME="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print(obj.get("tool_name", "") or "")
except Exception:
    pass
' 2>/dev/null)"

# Fast-path: non-mutating tool → allow.
case "$TOOL_NAME" in
  Write|Edit|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

# Mutating tool attempted — consult state.
CURRENT_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
SPEC_APPROVED="$(mcl_state_get spec_approved 2>/dev/null)"
DRIFT_DETECTED="$(mcl_state_get drift_detected 2>/dev/null)"
PHASE_NAME="$(mcl_state_get phase_name 2>/dev/null)"

# Default everything if state missing.
CURRENT_PHASE="${CURRENT_PHASE:-1}"
SPEC_APPROVED="${SPEC_APPROVED:-false}"
PHASE_NAME="${PHASE_NAME:-COLLECT}"

# Drift is now warn-only (since 6.0.0): emit audit entry and fall through.
if [ "$DRIFT_DETECTED" = "true" ]; then
  mcl_audit_log "drift-warn" "pre-tool" "tool=${TOOL_NAME} phase=${CURRENT_PHASE}"
  mcl_debug_log "pre-tool" "drift-warn" "tool=${TOOL_NAME} phase=${CURRENT_PHASE}"
fi

REASON=""
if [ "$CURRENT_PHASE" -lt 4 ] 2>/dev/null; then
  REASON="MCL LOCK — current_phase=${CURRENT_PHASE} (${PHASE_NAME}). Mutating tool \`${TOOL_NAME}\` is blocked until Phase 4 (EXECUTE). Emit the 📋 Spec: block, get the developer's explicit approval via AskUserQuestion, then proceed."
elif [ "$SPEC_APPROVED" != "true" ]; then
  REASON="MCL LOCK — spec_approved=false. Mutating tool \`${TOOL_NAME}\` is blocked until the developer explicitly approves the 📋 Spec: block via AskUserQuestion."
fi

if [ -n "$REASON" ]; then
  mcl_audit_log "deny-tool" "pre-tool" "tool=${TOOL_NAME} phase=${CURRENT_PHASE} approved=${SPEC_APPROVED}"
  mcl_debug_log "pre-tool" "deny" "tool=${TOOL_NAME} phase=${CURRENT_PHASE} approved=${SPEC_APPROVED}"
  python3 -c '
import json, sys
reason = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason
    }
}))
' "$REASON"
  exit 0
fi

mcl_debug_log "pre-tool" "allow" "tool=${TOOL_NAME} phase=${CURRENT_PHASE}"
exit 0
