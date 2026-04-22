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

# -------- Branch: plugin gate (hard gate, overrides phase logic) --------
# When `plugin_gate_active=true` in state, mutating tools AND writer-Bash
# commands are denied regardless of phase/approval. Read-only tools still
# pass through. The gate is set by mcl-activate.sh on the first message of
# a session when curated / LSP plugins or their binaries are missing.
PLUGIN_GATE_ACTIVE="$(mcl_state_get plugin_gate_active 2>/dev/null)"
if [ "$PLUGIN_GATE_ACTIVE" = "true" ]; then
  GATE_DENY=0
  case "$TOOL_NAME" in
    Write|Edit|MultiEdit|NotebookEdit)
      GATE_DENY=1
      ;;
    Bash)
      BASH_CMD="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print((obj.get("tool_input") or {}).get("command","") or "")
except Exception:
    pass
' 2>/dev/null)"
      if [ -n "$BASH_CMD" ]; then
        IS_WRITER="$(printf '%s' "$BASH_CMD" | python3 -c '
import re, sys
cmd = sys.stdin.read()
# Shell-redirection writers: `> file`, `>> file`, `>|`, `|& tee`.
if re.search(r"(^|[^<>&0-9])>>?\s*[^&\s]", cmd) or re.search(r"\btee\b(?!\s*--help)", cmd):
    print("1"); sys.exit(0)
# Mutating commands at token boundary.
token_re = r"(?:^|[\s|;&`(])"
patterns = [
    token_re + r"(rm|mv|cp|touch|mkdir|rmdir|chmod|chown|chgrp|ln|truncate|dd|patch|install|unlink)\b",
    token_re + r"sed\b[^|;&`]*?\s-i\b",
    token_re + r"git\s+(commit|push|add|rm|mv|reset|checkout|restore|switch|rebase|merge|pull|fetch|init|clone|stash|tag|branch|clean|cherry-pick|revert|apply|am|worktree)\b",
    token_re + r"(npm|yarn|pnpm|bun|pip|pip3|poetry|uv|gem|bundle|cargo|go|brew|apt|apt-get|dnf|yum|pacman|zypper)\s+(install|i|ci|add|remove|uninstall|update|upgrade|mod)\b",
    # NOTE: we deliberately do NOT block `bash foo.sh` / `python3 foo.py`.
    # Read-only helper scripts (our own `mcl-plugin-gate.sh check`, lint
    # dry-runs, stat collectors) would otherwise be false-positived. Real
    # mutating scripts still hit the other patterns when they reach a
    # mutating shell command inside.
    token_re + r"(docker|docker-compose|kubectl|terraform|ansible|helm|systemctl|launchctl)\s+\w+",
    token_re + r"(curl|wget)\s+[^|;&`]*(-o|--output|-O|--download)\b",
]
for p in patterns:
    if re.search(p, cmd):
        print("1"); sys.exit(0)
print("0")
' 2>/dev/null)"
        [ "$IS_WRITER" = "1" ] && GATE_DENY=1
      fi
      ;;
    *)
      # Read-only tools (Read, Glob, Grep, TodoWrite, WebFetch, WebSearch, Task, AskUserQuestion, ...).
      ;;
  esac
  if [ "$GATE_DENY" = "1" ]; then
    MISSING_SUMMARY="$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        obj = json.load(f)
    arr = obj.get("plugin_gate_missing") or []
    bits = []
    for item in arr:
        k = item.get("kind")
        if k == "plugin":
            bits.append("plugin:" + item.get("name",""))
        elif k == "binary":
            bits.append("binary:" + item.get("plugin","") + "/" + item.get("name",""))
    print(" ".join(bits))
except Exception:
    print("")
' "$MCL_STATE_FILE" 2>/dev/null)"
    GATE_REASON="MCL PLUGIN GATE — required plugins or binaries are missing (${MISSING_SUMMARY}). Mutating tools and writer-Bash commands are blocked for this project until every missing item is installed and MCL reloads in a new session. Read-only tools (Read / Grep / Glob / read-only Bash) still work. Tell the developer which items are missing and the /plugin install commands; do NOT retry the blocked tool."
    mcl_audit_log "plugin-gate-block" "pre-tool" "tool=${TOOL_NAME} missing=${MISSING_SUMMARY}"
    mcl_debug_log "pre-tool" "plugin-gate-block" "tool=${TOOL_NAME}"
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
' "$GATE_REASON"
    exit 0
  fi
fi

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
