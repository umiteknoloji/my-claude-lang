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

# Self-project guard: MCL must not process its own repo (recursive friction).
_MCL_REPO_PATH_SG="${MCL_REPO_PATH:-$HOME/my-claude-lang}"
_MCL_CWD_SG="$(cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null && pwd || true)"
_MCL_REPO_SG="$(cd "$_MCL_REPO_PATH_SG" 2>/dev/null && pwd || true)"
if [ -n "$_MCL_REPO_SG" ] && [ "$_MCL_CWD_SG" = "$_MCL_REPO_SG" ]; then
  cat >/dev/null 2>&1 || true
  exit 0
fi

# Hook health timestamp (since 8.2.7) — writes hook_last_run_ts to
# .mcl/hook-health.json so `mcl check-up` can detect an unregistered or
# silently broken hook (no recent timestamp = WARN).
_HH_FILE="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/hook-health.json"
mkdir -p "$(dirname "$_HH_FILE")" 2>/dev/null || true
python3 - "$_HH_FILE" "pre_tool" "$(date +%s)" 2>/dev/null <<'PYEOF' || true
import json, os, sys
path, hook, ts = sys.argv[1], sys.argv[2], int(sys.argv[3])
data = {}
try:
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            data = {}
except Exception:
    data = {}
data[hook] = ts
tmp = path + ".tmp"
try:
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f)
    os.replace(tmp, path)
except Exception:
    pass
PYEOF

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
        "permissionDecision": "allow",
        "permissionDecisionReason": reason
    }
}))
' "$GATE_REASON"
    exit 0
  fi
fi

# -------- Skill calls pass through --------
if [ "$TOOL_NAME" = "Skill" ]; then
  exit 0
fi

# -------- Branch: block TodoWrite in Aşama 1-3 --------
# MCL manages phase state via state.json, not todo checklists. Todo checklists
# during Aşama 1-3 duplicate and conflict with MCL phase logic.
# Aşama 7+ TodoWrite is allowed (legitimate task tracking during code execution).
if [ "$TOOL_NAME" = "TodoWrite" ] && command -v python3 >/dev/null 2>&1; then
  _TW_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
  # Default: block if phase unknown (no state yet = new session = Aşama 1).
  # Allow only when phase is explicitly >= 4.
  _TW_ALLOW=0
  [ -n "$_TW_PHASE" ] && [ "$_TW_PHASE" -ge 4 ] 2>/dev/null && _TW_ALLOW=1
  if [ "$_TW_ALLOW" = "0" ]; then
    mcl_audit_log "block-todowrite" "pre-tool" "phase=${_TW_PHASE}"
    python3 -c '
import json, sys
print(json.dumps({
    "decision": "approve",
    "reason": "MCL ACTIVE (Aşama 1-3) — TodoWrite is blocked. MCL manages phase state via state.json. Todo checklists during Aşama 1-3 duplicate and conflict with MCL phase logic. Proceed directly with MCL Aşama 1 parameter gathering."
}))
' 2>/dev/null
    exit 0
  fi
fi
# TodoWrite in Aşama 7+ passes through — allow.
if [ "$TOOL_NAME" = "TodoWrite" ]; then
  exit 0
fi

# -------- Branch: block Task dispatch of Aşama 8/10/5 as sub-agent --------
# sub-agent-phase-discipline: Aşama 8 (Risk Review), 4.6 (Impact Review),
# and Aşama 11 (Verification Report) MUST run in the main MCL session as
# interactive AskUserQuestion dialogs. Sub-agents cannot substitute them.
if [ "$TOOL_NAME" = "Task" ] && command -v python3 >/dev/null 2>&1; then
  _TASK_DESC="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys, re
try:
    obj = json.loads(sys.stdin.read())
    tin = obj.get("tool_input") or {}
    desc = (tin.get("description") or tin.get("prompt") or "").lower()
    # Check for Aşama 8/10/5 keywords indicating sub-agent substitution
    patterns = [
        r"phase\s*4\.5", r"phase\s*4\.6", r"phase\s*5",
        r"risk\s+review", r"impact\s+review", r"verification\s+report",
        r"phase\s+review", r"spec.compliance.review",
    ]
    for pat in patterns:
        if re.search(pat, desc):
            print("block:" + desc[:80])
            sys.exit(0)
except Exception:
    pass
print("")
' 2>/dev/null)"
  if printf '%s' "$_TASK_DESC" | grep -q "^block:"; then
    _MATCHED="${_TASK_DESC#block:}"
    mcl_audit_log "block-task-phase-dispatch" "pre-tool" "desc=${_MATCHED}"
    python3 -c '
import json, sys
print(json.dumps({
    "decision": "approve",
    "reason": "MCL SUB-AGENT DISCIPLINE — Aşama 8 (Risk Review), Aşama 10 (Impact Review), and Aşama 11 (Verification Report) cannot be dispatched to sub-agents. These phases require the main MCL session to run the interactive AskUserQuestion dialog directly with the developer. Run them in this session after all code sub-agents complete."
}))
' 2>/dev/null
    exit 0
  fi
fi
# -------- Branch: plan critique substance gate (Gap 3 + 8.3.3) --------
# Task with subagent_type containing "general-purpose" AND model containing
# "sonnet" is the plan-critique shape. 8.2.10 set plan_critique_done=true on
# this shape alone — bypassable via Task(prompt="say hi"). 8.3.3 adds an
# intent-validation step: pre-tool scans the transcript for a recent
# `Task(subagent_type=*mcl-intent-validator*)` call and reads its JSON
# verdict. Recursion-safe — the validator subagent has its own subagent_type
# so its own Task call passes through this gate without re-entry.
if [ "$TOOL_NAME" = "Task" ] && command -v python3 >/dev/null 2>&1; then
  _PCD_TASK_INFO="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    tin = obj.get("tool_input") or {}
    sub = (tin.get("subagent_type") or "").lower()
    mdl = (tin.get("model") or "").lower()
    if "general-purpose" in sub and "sonnet" in mdl:
        print(sub + "|" + mdl)
except Exception:
    pass
' 2>/dev/null)"
  if [ -n "$_PCD_TASK_INFO" ]; then
    _PCD_SUB="${_PCD_TASK_INFO%%|*}"
    _PCD_MDL="${_PCD_TASK_INFO#*|}"

    # 8.3.3: scan transcript for the most recent mcl-intent-validator Task
    # call + tool_result, parse the JSON verdict, branch accordingly.
    _PCD_VALIDATION="missing|"
    if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
      _PCD_VALIDATION="$(python3 - "$TRANSCRIPT_PATH" 2>/dev/null <<'PYEOF'
import json, sys

path = sys.argv[1]

tool_uses, tool_results, order = {}, {}, []

try:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            msg = obj.get("message") or obj
            if not isinstance(msg, dict):
                continue
            role = msg.get("role")
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            for item in content:
                if not isinstance(item, dict):
                    continue
                t = item.get("type")
                if role == "assistant" and t == "tool_use" and item.get("name") == "Task":
                    inp = item.get("input") or {}
                    sub = (inp.get("subagent_type") or "").lower()
                    if "mcl-intent-validator" in sub:
                        tid = item.get("id") or ""
                        if tid:
                            tool_uses[tid] = inp
                            order.append(tid)
                elif role == "user" and t == "tool_result":
                    tid = item.get("tool_use_id") or ""
                    if tid in tool_uses:
                        raw = item.get("content")
                        text_val = ""
                        if isinstance(raw, str):
                            text_val = raw
                        elif isinstance(raw, list):
                            parts = [b.get("text", "") for b in raw
                                     if isinstance(b, dict) and b.get("type") == "text"]
                            text_val = "\n".join(parts)
                        tool_results[tid] = text_val
except Exception:
    pass

# Walk in reverse to find LATEST validator with a result.
for tid in reversed(order):
    res = tool_results.get(tid)
    if not res:
        continue
    # Try to extract the JSON object from the response. Validator is
    # instructed to return a single-line JSON; tolerate leading/trailing
    # whitespace and stray text — find the first {...} block.
    s = res.strip()
    parsed = None
    try:
        parsed = json.loads(s)
    except Exception:
        # Fallback: scan for a JSON object substring.
        depth = 0
        start = -1
        for i, ch in enumerate(s):
            if ch == "{":
                if depth == 0:
                    start = i
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0 and start >= 0:
                    try:
                        parsed = json.loads(s[start:i + 1])
                        break
                    except Exception:
                        pass
                    start = -1
    if not isinstance(parsed, dict):
        print("parse-error|invalid-json")
        sys.exit(0)
    verdict = (parsed.get("verdict") or "").strip().lower()
    reason = (parsed.get("reason") or "").strip()
    if verdict in ("yes", "no"):
        # Sanitize reason for audit log: strip pipes and newlines.
        reason = reason.replace("|", "/").replace("\n", " ").replace("\r", " ")
        if len(reason) > 120:
            reason = reason[:120] + "…"
        print(f"{verdict}|{reason}")
        sys.exit(0)
    print("parse-error|verdict-missing-or-invalid")
    sys.exit(0)

# No validator call found in transcript at all.
print("missing|")
PYEOF
)"
    fi
    _PCD_VVERDICT="${_PCD_VALIDATION%%|*}"
    _PCD_VREASON="${_PCD_VALIDATION#*|}"

    case "$_PCD_VVERDICT" in
      yes)
        mcl_state_set plan_critique_done true >/dev/null 2>&1 || true
        mcl_audit_log "plan-critique-done" "pre-tool" "subagent=${_PCD_SUB} model=${_PCD_MDL} intent_validated reason=${_PCD_VREASON}"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append plan_critique_done "${_PCD_MDL}"
        ;;
      no)
        mcl_audit_log "plan-critique-substance-fail" "pre-tool" "intent=no reason=${_PCD_VREASON}"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append plan_critique_substance_fail "intent=no"
        python3 -c '
import json, sys
reason_text = sys.argv[1]
print(json.dumps({
    "decision": "approve",
    "reason": "MCL PLAN CRITIQUE SUBSTANCE GATE — Intent validator rejected the prompt. Reason: " + reason_text + ". Refine the Task prompt so it clearly carries plan critique intent (concrete plan reference + analytical scope), or skip the critique step if not needed."
}))
' "$_PCD_VREASON" 2>/dev/null
        exit 0
        ;;
      missing)
        mcl_audit_log "plan-critique-substance-fail" "pre-tool" "validator=not-called"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append plan_critique_substance_fail "validator=not-called"
        python3 -c '
import json, sys
print(json.dumps({
    "decision": "approve",
    "reason": "MCL PLAN CRITIQUE SUBSTANCE GATE — Plan critique requires intent validation since 8.3.3. Before this Task(subagent_type=general-purpose, model=*sonnet*), dispatch Task(subagent_type=\"mcl-intent-validator\", prompt=<the same prompt>) FIRST. Wait for its JSON verdict; if {\"verdict\":\"yes\"} re-issue this Task; if {\"verdict\":\"no\"} refine the prompt or skip."
}))
' 2>/dev/null
        exit 0
        ;;
      parse-error|*)
        # Fail-open: validator runtime issue (malformed output, transient
        # error). Don't lock the user out — proceed but record a warn so
        # patterns are visible via audit / mcl check-up.
        mcl_state_set plan_critique_done true >/dev/null 2>&1 || true
        mcl_audit_log "intent-validator-parse-error" "pre-tool" "fail-open detail=${_PCD_VREASON}"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append intent_validator_parse_error
        ;;
    esac
  fi
fi

# Non-phase-dispatch Task calls pass through — allow.
if [ "$TOOL_NAME" = "Task" ]; then
  exit 0
fi

# -------- Branch: ExitPlanMode gate (Gap 3, since 8.2.10) --------
# Block ExitPlanMode when plan_critique_done is false. Critique subagent
# (Sonnet 4.6) must run before plan approval to avoid bias-aligned plans.
if [ "$TOOL_NAME" = "ExitPlanMode" ]; then
  _PLAN_CRITIQUE_DONE="$(mcl_state_get plan_critique_done 2>/dev/null)"
  if [ "$_PLAN_CRITIQUE_DONE" != "true" ]; then
    mcl_audit_log "plan-critique-block" "pre-tool" "tool=ExitPlanMode plan_critique_done=false"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append plan_critique_block
    python3 -c '
import json, sys
print(json.dumps({
    "decision": "approve",
    "reason": "MCL PLAN CRITIQUE GATE — Plan critique subagent (Sonnet 4.6) must run before plan approval. Call Agent (Task) with subagent_type containing \"general-purpose\" AND model containing \"sonnet\" to critique the plan, then re-attempt ExitPlanMode."
}))
' 2>/dev/null
    exit 0
  fi
fi

# -------- Branch: protect .mcl/state.json from direct Bash writes --------
# MCL's state machine is owned exclusively by the hook system (mcl-state.sh).
# Direct writes to .mcl/state.json via Bash (cat >, echo >, tee, etc.) bypass
# phase transitions — e.g. manually setting current_phase=7 skips Aşama 6a/4b.
if [ "$TOOL_NAME" = "Bash" ] && command -v python3 >/dev/null 2>&1; then
  _STATE_WRITE="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, re, sys
try:
    obj = json.loads(sys.stdin.read())
    cmd = (obj.get("tool_input") or {}).get("command","") or ""
    # Detect writes where the state file is the DIRECT target of >> or tee.
    # A >/dev/null or >> elsewhere in the command must NOT trigger.
    hits = re.findall(r">>?\s*([^\s;|&]+)", cmd)
    direct_write = any("state.json" in h for h in hits)
    tee_write = bool(re.search(r"\btee\b", cmd) and "state.json" in cmd
                     and not re.search(r"tee.*[|;&].*state\.json", cmd))
    if direct_write or tee_write:
        print("block")
    else:
        print("")
except Exception:
    pass
' 2>/dev/null)"
  if [ "$_STATE_WRITE" = "block" ]; then
    mcl_audit_log "block-state-write" "pre-tool" "cmd=direct-write-to-state-json"
    python3 -c '
import json, sys
print(json.dumps({
    "decision": "approve",
    "reason": "MCL STATE PROTECTION — Direct writes to .mcl/state.json via Bash are forbidden. State transitions are owned exclusively by the hook system (mcl-stop.sh, mcl-state.sh). If spec approval is not advancing phase, it means the AskUserQuestion tool_result was not processed yet — do NOT manually patch state. Wait for the stop hook to run, or ask the developer to re-send their approval."
}))
' 2>/dev/null
    exit 0
  fi
fi

# Fast-path: non-mutating tool → allow.
# Skill, TodoWrite, and Task MCL-specific blocks run BEFORE this fast-path.
case "$TOOL_NAME" in
  Write|Edit|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

# -------- Security: secret / credential scan (all phases) --------
# Runs before the phase gate so credentials are blocked even in Aşama 1-3.
# Never blocks on scanner error (fallback = safe).
_SECRET_SCAN_LIB="$SCRIPT_DIR/lib/mcl-secret-scan.py"
if [ -f "$_SECRET_SCAN_LIB" ] && command -v python3 >/dev/null 2>&1; then
  _SEC_RESULT="$(printf '%s' "$RAW_INPUT" | python3 "$_SECRET_SCAN_LIB" 2>/dev/null || echo safe)"
  if [ "${_SEC_RESULT%%|*}" = "block" ]; then
    _SEC_REASON="${_SEC_RESULT#block|}"
    mcl_audit_log "secret-scan-block" "pre-tool" "tool=${TOOL_NAME}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append secret_scan_block
    python3 -c '
import json, sys
reason = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": "MCL SECURITY — " + reason
    }
}))
' "$_SEC_REASON" 2>/dev/null
    exit 0
  fi
fi

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
if { [ "$CURRENT_PHASE" -lt 7 ] 2>/dev/null || [ "$SPEC_APPROVED" != "true" ]; } \
   && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] \
   && [ -f "$JIT_SCANNER" ] && command -v python3 >/dev/null 2>&1; then
  # Pass restart_turn_ts (since 8.2.13) so the scanner drops pre-restart
  # askq's. Without this filter, /mcl-restart would be defeated by JIT
  # re-promoting on an old approve askq still in the session transcript.
  JIT_RESTART_TS="$(mcl_state_get restart_turn_ts 2>/dev/null)"
  JIT_JSON="$(python3 "$JIT_SCANNER" "$TRANSCRIPT_PATH" "$JIT_RESTART_TS" 2>/dev/null)"
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
      if [ "$SPEC_APPROVED" = "true" ] && [ "$CURRENT_PHASE" -ge 7 ] 2>/dev/null \
         && [ "$STATE_SPEC_HASH" = "$JIT_SPEC_HASH" ]; then
        mcl_debug_log "pre-tool" "askq-jit-idempotent" "hash=${JIT_SPEC_HASH:0:12}"
      else
        mcl_state_set spec_hash "\"$JIT_SPEC_HASH\""
        mcl_state_set spec_approved true
        mcl_state_set current_phase 7
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
        mcl_audit_log "askq-advance-jit" "pre-tool" "hash=${JIT_SPEC_HASH:0:12} phase=${CURRENT_PHASE}->7 ui_flow=${UI_FLOW_ON}"
        mcl_debug_log "pre-tool" "askq-advance-jit" "hash=${JIT_SPEC_HASH:0:12} phase=${CURRENT_PHASE}->7"
        command -v mcl_trace_append >/dev/null 2>&1 && {
          mcl_trace_append spec_approved "${JIT_SPEC_HASH:0:12}"
          mcl_trace_append phase_transition "$CURRENT_PHASE" 7
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
      mcl_state_set current_phase 4
      mcl_state_set phase_name '"SPEC_REVIEW"'
      mcl_audit_log "askq-advance-jit" "pre-tool" "summary-confirm phase=1->2"
      mcl_debug_log "pre-tool" "askq-advance-jit" "summary-confirm phase=1->2"
      command -v mcl_trace_append >/dev/null 2>&1 && {
        mcl_trace_append summary_confirmed approved
        mcl_trace_append phase_transition 1 4
      }
      CURRENT_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
      PHASE_NAME="$(mcl_state_get phase_name 2>/dev/null)"
    fi
  fi
fi


# --- Layer 4 escape hatch (since v10.1.7) ---
# Before deciding on the spec-approval block, scan audit.log for an
# `asama-4-complete` emit (mandated by skills/asama4-spec.md). If
# present in current session, force-progress state — same mechanism
# Stop hook uses, but applied at PreToolUse so the model can recover
# from a classifier miss WITHOUT waiting for end-of-turn. Combined
# with Option 3 (real spec-approval block below), this creates the
# enforcement+recovery pattern: writes blocked when spec_approved=
# false, but model can emit `asama-4-complete` to unlock immediately.
if [ "$SPEC_APPROVED" != "true" ] && command -v python3 >/dev/null 2>&1; then
  _PRE_AUDIT="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  _PRE_TRACE="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  _PRE_A4_HIT="$(python3 - "$_PRE_AUDIT" "$_PRE_TRACE" 2>/dev/null <<'PYEOF' || echo 0
import os, sys
audit_path, trace_path = sys.argv[1], sys.argv[2]
session_ts = ""
try:
    if os.path.isfile(trace_path):
        for line in open(trace_path, "r", encoding="utf-8", errors="replace"):
            if "| session_start |" in line:
                session_ts = line.split("|", 1)[0].strip()
except Exception:
    pass
hit = 0
try:
    if os.path.isfile(audit_path):
        for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
            if "| asama-4-complete |" not in line:
                continue
            ts = line.split("|", 1)[0].strip()
            if session_ts and ts < session_ts:
                continue
            hit = 1
            break
except Exception:
    pass
print(hit)
PYEOF
)"
  if [ "${_PRE_A4_HIT:-0}" = "1" ]; then
    mcl_state_set spec_approved true
    mcl_state_set current_phase 7
    mcl_state_set phase_name '"EXECUTE"'
    mcl_audit_log "asama-4-progression-from-emit" "pre-tool" "via-asama-4-complete-bash-emit"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition 4 7
    SPEC_APPROVED="$(mcl_state_get spec_approved 2>/dev/null)"
    CURRENT_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
    PHASE_NAME="$(mcl_state_get phase_name 2>/dev/null)"
  fi
fi

REASON=""
REASON_KIND=""
if [ "$SPEC_APPROVED" != "true" ]; then
  REASON="MCL LOCK — spec_approved=false. Mutating tool \`${TOOL_NAME}\` is blocked (since v10.1.7 — real block, not advisory). Recovery options: (A) re-emit AskUserQuestion with prefix \`MCL <ver> | \` for spec approval; (B) if developer already approved but classifier missed, run: \`bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log asama-4-complete mcl-stop \"spec_hash=<H> approver=user\"'\` to force-progress state; (C) loop-breaker fail-open after 3 consecutive blocks."
  REASON_KIND="spec-approval"
fi

# -------- Branch: UI flow path-exception (Aşama 6a BUILD_UI / 4b REVIEW) --------
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
      REASON="MCL UI-BUILD LOCK — ui_sub_phase=${UI_SUB_PHASE}. Backend path \`${DENIED_PATH}\` is blocked until the developer approves the UI and MCL advances to the BACKEND sub-phase. Frontend code (components, pages, styles, fixtures), \`public/\`, \`.mcl/\` temp files, and framework-neutral files (README, package.json) are allowed. Build the UI with mock/fixture data only; integrate backend in Aşama 6c."
    fi
  fi
fi

# -------- Branch: Pattern Matching guard (Aşama 5) --------
# When pattern_scan_due=true, Claude must read existing sibling files before
# writing anything. One-turn grace: after the first Aşama 7 turn the stop
# hook clears the flag and writes are unblocked.
if [ -z "$REASON" ] && [ "$CURRENT_PHASE" = "7" ]; then
  _PS_DUE_PT="$(mcl_state_get pattern_scan_due 2>/dev/null)"
  if [ "$_PS_DUE_PT" = "true" ]; then
    _PAT_FILES_PT="$(mcl_state_get pattern_files 2>/dev/null)"
    REASON="MCL PHASE 3.5 — Pattern scan pending. Before writing any Aşama 7 code, read the existing sibling files listed in the PATTERN_MATCHING_NOTICE to extract naming, error handling, import style, and test structure patterns. Write nothing this turn — use Read tool on each listed file, note the patterns, then end the turn. Writes will unblock automatically on the next turn."
    mcl_audit_log "pattern-scan-block" "pre-tool" "tool=${TOOL_NAME}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append pattern_scan_block
  fi
fi

# -------- Branch: Scope Guard (Aşama 7) --------
# When scope_paths is non-empty (spec listed explicit file paths / globs),
# block writes to paths that don't match any declared pattern.
# Empty scope_paths = spec had no explicit paths = no restriction.
if [ -z "$REASON" ] && [ "$CURRENT_PHASE" = "7" ] && command -v python3 >/dev/null 2>&1; then
  _SCOPE_VERDICT="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, fnmatch, os, sys

try:
    obj = json.loads(sys.stdin.read())
except Exception:
    print("allow"); sys.exit(0)

tin = obj.get("tool_input") or {}
# Write/Edit use file_path; MultiEdit uses file_path[]; NotebookEdit uses notebook_path
paths_to_check = []
fp = tin.get("file_path") or tin.get("notebook_path")
if fp:
    paths_to_check.append(str(fp))
# MultiEdit: edits is a list of {file_path: ...}
edits = tin.get("edits")
if isinstance(edits, list):
    for e in edits:
        if isinstance(e, dict) and e.get("file_path"):
            paths_to_check.append(str(e["file_path"]))

if not paths_to_check:
    print("allow"); sys.exit(0)

# Read scope_paths from state.json directly
import os
state_file = os.path.join(os.getcwd(), ".mcl", "state.json")
try:
    with open(state_file, encoding="utf-8") as sf:
        state = json.load(sf)
    scope_paths = state.get("scope_paths") or []
    if not isinstance(scope_paths, list):
        scope_paths = []
except Exception:
    scope_paths = []

if not scope_paths:
    print("allow"); sys.exit(0)  # No declared paths — no restriction

def matches(file_abs, patterns):
    """True if file_abs matches any pattern (relative glob or absolute)."""
    file_abs = os.path.normpath(file_abs)
    for pat in patterns:
        pat = pat.lstrip("./")
        if not pat:
            continue
        # Absolute match
        if fnmatch.fnmatch(file_abs, pat):
            return True
        # Suffix match: pattern relative to any parent dir
        if fnmatch.fnmatch(file_abs, "*/" + pat):
            return True
        # Exact suffix without glob
        if file_abs.endswith("/" + pat) or file_abs == pat:
            return True
    return False

# Check all paths; report the first out-of-scope path
for p in paths_to_check:
    if not matches(p, scope_paths):
        # Skip .mcl/ internals and temp files — always allowed
        norm = p.replace("\\\\", "/")
        if "/.mcl/" in norm or norm.endswith("/.mcl") or "/tmp/" in norm:
            continue
        print("deny|" + p)
        sys.exit(0)

print("allow")
' 2>/dev/null || echo "allow")"
  if [ "${_SCOPE_VERDICT%%|*}" = "deny" ]; then
    _SCOPE_DENIED_PATH="${_SCOPE_VERDICT#deny|}"
    REASON="MCL SCOPE GUARD (Rule 2 — File Scope) — \`${_SCOPE_DENIED_PATH}\` is not in the spec's declared file scope. This also likely violates Rule 1 (Spec-Only): if this file needs changes, it should have been in the spec. Options: (A) surface as a Aşama 8 risk and request scope extension; (B) if genuinely required now, ask the developer via AskUserQuestion BEFORE writing — never silently touch out-of-scope files."
    mcl_audit_log "scope-guard-block" "pre-tool" "path=${_SCOPE_DENIED_PATH} tool=${TOOL_NAME}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append scope_guard_block "${_SCOPE_DENIED_PATH}"
  fi
fi

if [ -n "$REASON" ]; then
  # Decision matrix (since v10.1.7):
  #   REASON_KIND=spec-approval → REAL block (deny). Was advisory in
  #   v10.0.0; reverted because herta v10.1.4 showed advisory mode
  #   lets writes through at phase=4/spec_approved=false, breaking
  #   the spec-approval contract.
  #   Other kinds (UI path-exception, pattern scan, scope guard) →
  #   stay advisory (allow with reason) for now — same as v10.0.0+.
  DECISION="allow"
  if [ "$REASON_KIND" = "spec-approval" ]; then
    _SA_LB_COUNT="$(_mcl_loop_breaker_count "spec-approval-block" 2>/dev/null || echo 0)"
    if [ "${_SA_LB_COUNT:-0}" -ge 3 ]; then
      mcl_audit_log "spec-approval-loop-broken" "pre-tool" "count=${_SA_LB_COUNT} fail-open"
      command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append spec_approval_loop_broken "${_SA_LB_COUNT}"
      DECISION="allow"
    else
      DECISION="deny"
      mcl_audit_log "spec-approval-block" "pre-tool" "tool=${TOOL_NAME} strike=$((_SA_LB_COUNT + 1))"
      command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append spec_approval_block "$((_SA_LB_COUNT + 1))"
    fi
  fi

  mcl_audit_log "deny-tool" "pre-tool" "tool=${TOOL_NAME} phase=${CURRENT_PHASE} approved=${SPEC_APPROVED} decision=${DECISION} kind=${REASON_KIND:-other}"
  mcl_debug_log "pre-tool" "deny" "tool=${TOOL_NAME} phase=${CURRENT_PHASE} approved=${SPEC_APPROVED} decision=${DECISION}"
  python3 -c '
import json, sys
reason, decision = sys.argv[1], sys.argv[2]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason
    }
}))
' "$REASON" "$DECISION"
  exit 0
fi

# -------- Plan critique reset on plan-file modification (Gap 3, since 8.2.10) --------
# When Write/Edit/MultiEdit targets a `.claude/plans/*.md` file, the plan
# content is changing — a fresh critique is required for the new plan.
# Runs after all gating decisions so we only reset on tool calls that the
# pre-tool hook is actually allowing through.
case "$TOOL_NAME" in
  Write|Edit|MultiEdit)
    _PCR_PATH="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print((obj.get("tool_input") or {}).get("file_path","") or "")
except Exception:
    pass
' 2>/dev/null)"
    case "$_PCR_PATH" in
      */.claude/plans/*.md|.claude/plans/*.md)
        _PCR_NOW="$(mcl_state_get plan_critique_done 2>/dev/null)"
        if [ "$_PCR_NOW" = "true" ]; then
          mcl_state_set plan_critique_done false >/dev/null 2>&1 || true
          mcl_audit_log "plan-critique-reset" "pre-tool" "path=${_PCR_PATH}"
          command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append plan_critique_reset "${_PCR_PATH}"
        fi
        ;;
    esac
    ;;
esac

mcl_debug_log "pre-tool" "allow" "tool=${TOOL_NAME} phase=${CURRENT_PHASE}"
exit 0
