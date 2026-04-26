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

# Everything else (Read, Glob, Grep, WebFetch, WebSearch, TodoWrite,
# Bash, Task, ...) passes through unchanged. Bash and Task are handled
# by the prose layer in v1.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mcl-state.sh
source "$SCRIPT_DIR/lib/mcl-state.sh"
# shellcheck source=lib/mcl-trace.sh
[ -f "$SCRIPT_DIR/lib/mcl-trace.sh" ] && source "$SCRIPT_DIR/lib/mcl-trace.sh"

RAW_INPUT="$(cat 2>/dev/null || true)"

TOOL_NAME="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print(obj.get("tool_name", "") or "")
except Exception:
    pass
' 2>/dev/null)"

TRANSCRIPT_PATH="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print(obj.get("transcript_path", "") or "")
except Exception:
    pass
' 2>/dev/null)"

# Trace: Task tool dispatch records which subagent MCL invoked.
if [ "$TOOL_NAME" = "Task" ] && command -v mcl_trace_append >/dev/null 2>&1; then
  SUBAGENT_TYPE="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print((obj.get("tool_input") or {}).get("subagent_type","") or "")
except Exception:
    pass
' 2>/dev/null)"
  [ -n "$SUBAGENT_TYPE" ] && mcl_trace_append plugin_dispatched "$SUBAGENT_TYPE"
fi

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
PHASE_NAME="$(mcl_state_get phase_name 2>/dev/null)"

# Default everything if state missing.
CURRENT_PHASE="${CURRENT_PHASE:-1}"
SPEC_APPROVED="${SPEC_APPROVED:-false}"
PHASE_NAME="${PHASE_NAME:-COLLECT}"

# --- Just-in-time askq advance (since 6.5.6) ---
# Stop hook only fires at end-of-turn. When the model chains
# summary-askq → spec → approve-askq → Write in a single turn, Stop has
# not run yet and state is still phase=1. We rescan the transcript for
# an already-approved MCL askq and advance state before evaluating the
# phase gate, so a spec approved mid-turn doesn't force the developer
# to pay for a second turn (or pay tokens for a re-emitted spec).
_mcl_pre_is_approve_option() {
  local raw="$1"
  [ -z "$raw" ] && return 1
  local norm
  norm="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$norm" in
    *onayla*|*onaylıyorum*|*evet*|*kabul*|*tamam*) return 0 ;;
    *approve*|*yes*|*confirm*|*ok*|*proceed*|*accept*) return 0 ;;
    *aprobar*|*sí*|*si*|*confirmar*) return 0 ;;
    *approuver*|*oui*|*confirmer*) return 0 ;;
    *genehmigen*|*bestätigen*|*ja*) return 0 ;;
    *承認*|*はい*|*確認*|*了解*) return 0 ;;
    *승인*|*네*|*확인*|*예*) return 0 ;;
    *批准*|*是*|*确认*) return 0 ;;
    *موافق*|*نعم*|*تأكيد*) return 0 ;;
    *אשר*|*כן*|*אישור*) return 0 ;;
    *स्वीकार*|*हाँ*|*हां*) return 0 ;;
    *setujui*|*ya*|*konfirmasi*) return 0 ;;
    *aprovar*|*sim*) return 0 ;;
    *одобрить*|*да*|*подтвердить*) return 0 ;;
  esac
  return 1
}

JIT_SCANNER="$SCRIPT_DIR/lib/mcl-askq-scanner.py"
if { [ "$CURRENT_PHASE" -lt 4 ] 2>/dev/null || [ "$SPEC_APPROVED" != "true" ]; } \
   && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] \
   && [ -f "$JIT_SCANNER" ] && command -v python3 >/dev/null 2>&1; then
  JIT_JSON="$(python3 "$JIT_SCANNER" "$TRANSCRIPT_PATH" 2>/dev/null)"
  if [ -n "$JIT_JSON" ]; then
    JIT_INTENT="$(printf '%s' "$JIT_JSON" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print(obj.get("intent","") or "")
except Exception:
    pass
' 2>/dev/null)"
    JIT_SELECTED="$(printf '%s' "$JIT_JSON" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print(obj.get("selected","") or "")
except Exception:
    pass
' 2>/dev/null)"
    JIT_SPEC_HASH="$(printf '%s' "$JIT_JSON" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print(obj.get("spec_hash","") or "")
except Exception:
    pass
' 2>/dev/null)"
    PARTIAL_NOW="$(mcl_state_get partial_spec 2>/dev/null)"
    STATE_SPEC_HASH="$(mcl_state_get spec_hash 2>/dev/null)"
    if [ "$JIT_INTENT" = "spec-approve" ] \
       && [ -n "$JIT_SPEC_HASH" ] \
       && [ "$PARTIAL_NOW" != "true" ] \
       && _mcl_pre_is_approve_option "$JIT_SELECTED"; then
      # Idempotency: if state already matches this approval, skip.
      if [ "$SPEC_APPROVED" = "true" ] && [ "$CURRENT_PHASE" -ge 4 ] 2>/dev/null \
         && [ "$STATE_SPEC_HASH" = "$JIT_SPEC_HASH" ]; then
        mcl_debug_log "pre-tool" "askq-jit-idempotent" "hash=${JIT_SPEC_HASH:0:12}"
      else
        mcl_state_set spec_hash "\"$JIT_SPEC_HASH\""
        mcl_state_set spec_approved true
        mcl_state_set current_phase 4
        mcl_state_set phase_name '"EXECUTE"'
        # UI intent scan mirrors stop.sh: bootstrap projects whose
        # file-system UI signals fired `false` at session start still
        # enter BUILD_UI if the approved spec has UI-framework markers.
        UI_FLOW_ON="$(mcl_state_get ui_flow_active 2>/dev/null)"
        UI_INTENT_SCANNER="$SCRIPT_DIR/lib/mcl-spec-ui-intent.py"
        if [ "$UI_FLOW_ON" != "true" ] && [ -f "$UI_INTENT_SCANNER" ]; then
          UI_INTENT_VERDICT="$(python3 "$UI_INTENT_SCANNER" "$TRANSCRIPT_PATH" 2>/dev/null)"
          if [ "$UI_INTENT_VERDICT" = "true" ]; then
            mcl_state_set ui_flow_active true
            UI_FLOW_ON="true"
            mcl_audit_log "ui-flow-spec-intent" "pre-tool" "hash=${JIT_SPEC_HASH:0:12}"
            command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append ui_flow_spec_intent "${JIT_SPEC_HASH:0:12}"
          fi
        fi
        if [ "$UI_FLOW_ON" = "true" ]; then
          mcl_state_set ui_sub_phase '"BUILD_UI"'
          mcl_audit_log "ui-flow-enter-build" "pre-tool" "hash=${JIT_SPEC_HASH:0:12}"
        fi
        mcl_audit_log "askq-advance-jit" "pre-tool" "hash=${JIT_SPEC_HASH:0:12} phase=${CURRENT_PHASE}->4 ui_flow=${UI_FLOW_ON}"
        mcl_debug_log "pre-tool" "askq-advance-jit" "hash=${JIT_SPEC_HASH:0:12} phase=${CURRENT_PHASE}->4"
        command -v mcl_trace_append >/dev/null 2>&1 && {
          mcl_trace_append spec_approved "${JIT_SPEC_HASH:0:12}"
          mcl_trace_append phase_transition "$CURRENT_PHASE" 4
          [ "$UI_FLOW_ON" = "true" ] && mcl_trace_append ui_flow_enabled
          mcl_trace_append askq_advance_jit "${JIT_SPEC_HASH:0:12}"
        }
        bash "$SCRIPT_DIR/lib/mcl-spec-save.sh" "$TRANSCRIPT_PATH" "$JIT_SPEC_HASH" 2>/dev/null || true
        # Re-read state for downstream gate evaluation.
        CURRENT_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
        SPEC_APPROVED="$(mcl_state_get spec_approved 2>/dev/null)"
        PHASE_NAME="$(mcl_state_get phase_name 2>/dev/null)"
      fi
    elif [ "$JIT_INTENT" = "summary-confirm" ] \
         && _mcl_pre_is_approve_option "$JIT_SELECTED" \
         && [ "$CURRENT_PHASE" = "1" ]; then
      # Phase-1 → Phase-2 advance. Does NOT unlock mutating tools
      # (still phase<4) but keeps audit/trace parity with Stop.
      mcl_state_set current_phase 2
      mcl_state_set phase_name '"SPEC_REVIEW"'
      mcl_audit_log "askq-advance-jit" "pre-tool" "summary-confirm phase=1->2"
      mcl_debug_log "pre-tool" "askq-advance-jit" "summary-confirm phase=1->2"
      command -v mcl_trace_append >/dev/null 2>&1 && {
        mcl_trace_append summary_confirmed approved
        mcl_trace_append phase_transition 1 2
      }
      CURRENT_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
      PHASE_NAME="$(mcl_state_get phase_name 2>/dev/null)"
    fi
  fi
fi


REASON=""
if [ "$CURRENT_PHASE" -lt 4 ] 2>/dev/null; then
  REASON="MCL LOCK — current_phase=${CURRENT_PHASE} (${PHASE_NAME}). Mutating tool \`${TOOL_NAME}\` is blocked until Phase 4 (EXECUTE). Emit the 📋 Spec: block, get the developer's explicit approval via AskUserQuestion, then proceed."
elif [ "$SPEC_APPROVED" != "true" ]; then
  REASON="MCL LOCK — spec_approved=false. Mutating tool \`${TOOL_NAME}\` is blocked until the developer explicitly approves the 📋 Spec: block via AskUserQuestion."
fi

# -------- Branch: UI flow path-exception (Phase 4a BUILD_UI / 4b REVIEW) --------
# When UI flow is active AND we're in BUILD_UI or REVIEW sub-phase, only
# frontend paths + .mcl/ internals are writeable. Backend paths stay
# locked until the developer approves the UI and MCL advances to the
# BACKEND sub-phase. This prevents "Claude wrote the backend before I
# saw the UI" regressions.
if [ -z "$REASON" ]; then
  UI_FLOW_ACTIVE="$(mcl_state_get ui_flow_active 2>/dev/null)"
  UI_SUB_PHASE="$(mcl_state_get ui_sub_phase 2>/dev/null)"
  if [ "$UI_FLOW_ACTIVE" = "true" ] && { [ "$UI_SUB_PHASE" = "BUILD_UI" ] || [ "$UI_SUB_PHASE" = "REVIEW" ]; }; then
    UI_PATH_VERDICT="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, re, sys
try:
    obj = json.loads(sys.stdin.read())
except Exception:
    print("allow|"); sys.exit(0)
tin = obj.get("tool_input") or {}
# Write/Edit/MultiEdit use file_path; NotebookEdit uses notebook_path.
p = tin.get("file_path") or tin.get("notebook_path") or ""
if not p:
    print("allow|"); sys.exit(0)

# Normalize relative-style path for matching (strip leading ./, leave
# absolute paths alone — classifier uses substring search anchored by
# path separators).
norm = p.replace("\\\\", "/")

# Backend path globs — checked FIRST so `pages/api/**` wins over the
# broader `pages/**` frontend allow. If any backend pattern matches,
# deny.
backend_patterns = [
    r"(^|/)src/api(/|$)",
    r"(^|/)src/server(/|$)",
    r"(^|/)src/services(/|$)",
    r"(^|/)src/lib/db(/|$)",
    r"(^|/)src/db(/|$)",
    r"(^|/)src/backend(/|$)",
    r"(^|/)pages/api(/|$)",          # Next.js pages router
    r"(^|/)app/api(/|$)",            # Next.js app router
    r"(^|/)prisma(/|$)",
    r"(^|/)drizzle(/|$)",
    r"(^|/)supabase/migrations(/|$)",
    r"(^|/)migrations(/|$)",
    r"(^|/)\.env(\.|$)",             # .env, .env.local, .env.production
    r"(^|/)vercel\.json$",
    r"(^|/)netlify\.toml$",
    r"(^|/)server\.(js|ts|mjs)$",
    r"(^|/)index\.server\.",
]
for pat in backend_patterns:
    if re.search(pat, norm):
        print(f"deny|{p}"); sys.exit(0)
print("allow|")
' 2>/dev/null)"
    if [ "${UI_PATH_VERDICT%%|*}" = "deny" ]; then
      DENIED_PATH="${UI_PATH_VERDICT#deny|}"
      REASON="MCL UI-BUILD LOCK — ui_sub_phase=${UI_SUB_PHASE}. Backend path \`${DENIED_PATH}\` is blocked until the developer approves the UI and MCL advances to the BACKEND sub-phase. Frontend code (components, pages, styles, fixtures), \`public/\`, \`.mcl/\` temp files, and framework-neutral files (README, package.json) are allowed. Build the UI with mock/fixture data only; integrate backend in Phase 4c."
    fi
  fi
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
