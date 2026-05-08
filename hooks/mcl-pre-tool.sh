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

# -------- Branch: v13.0 Universal Model Emit Denylist (soft) --------
# v13.0 BRIDGE: deny sadece `phase_transition` ve `asama-N-progression-from-emit`
# için aktif. `asama-N-complete` model tarafından emit edilebilir (legacy v12
# pattern); gate engine bunu legacy fallback ile algılar. v13.1 hard cutover'da
# `asama-N-complete` model emit'i de yasaklanır — o zaman tüm 24 skill MD dosyası
# yeni emit pattern'lerine (items-declared/scan/triple) geçmiş olmalı.
# Deny scope dar (Risk #2): TOOL_NAME=Bash AND command body içinde mcl_audit_log
# veya mcl_trace_append çağrısı varsa.
if [ "$TOOL_NAME" = "Bash" ]; then
  _BASH_CMD="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print((obj.get("tool_input") or {}).get("command","") or "")
except Exception:
    pass
' 2>/dev/null)"
  # Emit-tool çağrısı + yasak token kontrolü (her ikisi şart)
  if echo "$_BASH_CMD" | grep -qE '(mcl_audit_log|mcl_trace_append)' && \
     echo "$_BASH_CMD" | grep -qE '(phase_transition[[:space:]]+[0-9]+[[:space:]]+[0-9]+|asama-[0-9]+-progression-from-emit)'; then
    _BAD_TOKEN="$(echo "$_BASH_CMD" | grep -oE '(phase_transition[[:space:]]+[0-9]+[[:space:]]+[0-9]+|asama-[0-9]+-progression-from-emit)' | head -1)"
    _DENY_PHASE="$(echo "$_BAD_TOKEN" | grep -oE '[0-9]+' | head -1)"
    mcl_audit_log "asama-${_DENY_PHASE:-?}-illegal-emit-attempt" "pre-tool" "token=${_BAD_TOKEN} tool=${TOOL_NAME}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append illegal_emit_attempt "${_BAD_TOKEN}"
    python3 -c '
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": sys.argv[1]
    }
}))' "v13.0 deterministic gate: \`${_BAD_TOKEN}\` is hook-emitted only via universal completeness loop. Model must NOT emit phase transitions directly. Hook reads gate-spec.json and writes phase_transition + state advance when per-phase gate criteria are met."
    exit 0
  fi
fi

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
# -------- Branch: Aşama 4 spec-approval askq requires precision-audit (since v13.0.5) --------
# Layer 2 of v13.0.5 deterministic enforcement. The Aşama 2 skip-block at
# line ~1028 fires AFTER spec is approved (post-hoc detection). This earlier
# gate fires when the model attempts to OPEN the spec-approval askq before
# precision-audit ran — forcing it into the correct order: Aşama 1 → 2 → 3
# → 4 (spec emit + askq). Detects spec-approval askq via question prefix
# matching `MCL <ver> | Faz 4` / `MCL <ver> | Phase 4` / `MCL <ver> | Aşama 4`.
if [ "$TOOL_NAME" = "AskUserQuestion" ] && command -v python3 >/dev/null 2>&1; then
  _A4_QUESTION="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print((obj.get("tool_input") or {}).get("question") or "")
except Exception:
    print("")
' 2>/dev/null)"
  if printf '%s' "$_A4_QUESTION" | grep -qiE "MCL[[:space:]]+[0-9]+(\.[0-9]+){2}[[:space:]]*\|[[:space:]]*(Faz|Phase|Aşama|Etape|Étape|Fase|フェーズ|阶段|단계|مرحلة|שלב|चरण|Tahap|Этап|Step)[[:space:]]+4[[:space:]]"; then
    _A4_AUDIT="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
    _A4_TRACE="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
    _A4_PRECISION="$(python3 - "$_A4_AUDIT" "$_A4_TRACE" 2>/dev/null <<'PYEOF'
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
seen = False
try:
    if os.path.isfile(audit_path):
        for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
            ts = line.split("|", 1)[0].strip()
            if session_ts and ts < session_ts:
                continue
            if "| asama-2-complete |" in line or "| precision-audit |" in line:
                seen = True; break
except Exception:
    pass
print("present" if seen else "missing")
PYEOF
)"
    if [ "$_A4_PRECISION" = "missing" ]; then
      mcl_audit_log "asama-4-askq-gate-block" "pre-tool" "no-precision-audit"
      python3 -c '
import json, sys
print(json.dumps({
    "decision": "block",
    "reason": "MCL ASAMA 4 ASKQ GATE (v13.0.5) — Aşama 4 spec onay AskUserQuestion'"'"'i acilamaz: bu oturumda asama-2-complete ya da precision-audit audit i yok. Spec tum 7 boyutluk precision audit ten gecmemis parametreler uzerine kurulu olur — yanlis kod riski. Onceki spec emisyonunu unut. Sirayla: (1) Asama 2 (skills/my-claude-lang/asama2-precision-audit.md) 7 boyutu walk et SILENT-ASSUME / SKIP-MARK / GATE classification yap; (2) Closing AskUserQuestion `MCL <ver> | Faz 2 — Precision-audit niyet onayi:` ile niyet onayi al; (3) Asama 3 brief uret; (4) Sonra Asama 4 spec emit + onay askq."
}))
'
      exit 0
    fi
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

# Fast-path: non-mutating, non-gated tool → allow.
# Skill, TodoWrite, and Task MCL-specific blocks run BEFORE this fast-path.
# v13.0.9: AskUserQuestion + TodoWrite must proceed past fast-path so the
# Layer B phase allowlist branch (line ~875) can check them per gate-spec.
case "$TOOL_NAME" in
  Write|Edit|MultiEdit|NotebookEdit|AskUserQuestion|TodoWrite) ;;
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
      # v13.0.11: post-spec-approval canonical phase is 5 (Pattern Matching).
      # Universal completeness loop advances 5→6→...→9 as audits emit.
      if [ "$SPEC_APPROVED" = "true" ] && [ "$CURRENT_PHASE" -ge 5 ] 2>/dev/null \
         && [ "$STATE_SPEC_HASH" = "$JIT_SPEC_HASH" ]; then
        mcl_debug_log "pre-tool" "askq-jit-idempotent" "hash=${JIT_SPEC_HASH:0:12}"
      else
        mcl_state_set spec_hash "\"$JIT_SPEC_HASH\""
        mcl_state_set spec_approved true
        mcl_state_set current_phase 5
        mcl_state_set phase_name '"PATTERN_MATCHING"'
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
        mcl_audit_log "askq-advance-jit" "pre-tool" "hash=${JIT_SPEC_HASH:0:12} phase=${CURRENT_PHASE}->5 ui_flow=${UI_FLOW_ON}"
        mcl_debug_log "pre-tool" "askq-advance-jit" "hash=${JIT_SPEC_HASH:0:12} phase=${CURRENT_PHASE}->5"
        command -v mcl_trace_append >/dev/null 2>&1 && {
          mcl_trace_append spec_approved "${JIT_SPEC_HASH:0:12}"
          mcl_trace_append phase_transition "$CURRENT_PHASE" 5
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
    mcl_state_set current_phase 5
    mcl_state_set phase_name '"PATTERN_MATCHING"'
    mcl_audit_log "asama-4-progression-from-emit" "pre-tool" "via-asama-4-complete-bash-emit"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition 4 5
    SPEC_APPROVED="$(mcl_state_get spec_approved 2>/dev/null)"
    CURRENT_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
    PHASE_NAME="$(mcl_state_get phase_name 2>/dev/null)"
  fi
fi

REASON=""
REASON_KIND=""
if [ "$SPEC_APPROVED" != "true" ]; then
  # v13.0.5: When the session has zero Aşama 1-4 audit evidence, the model
  # is attempting a fast-skip (Write/Edit before any phase). Surface a
  # directive that walks Aşama 1 → 2 → 3 → 4 sequentially. When at least
  # one Aşama 1+ audit exists, fall back to the original recovery options
  # message (preserves backward-compat with existing skip-block tests).
  _MCLLOCK_AUDIT="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  _MCLLOCK_TRACE="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  _MCLLOCK_HAS_A1="absent"
  if command -v python3 >/dev/null 2>&1; then
    _MCLLOCK_HAS_A1="$(python3 - "$_MCLLOCK_AUDIT" "$_MCLLOCK_TRACE" 2>/dev/null <<'PYEOF'
import os, sys
audit_path, trace_path = sys.argv[1], sys.argv[2]
session_ts = ""
try:
    if os.path.isfile(trace_path):
        for l in open(trace_path, "r", encoding="utf-8", errors="replace"):
            if "| session_start |" in l:
                session_ts = l.split("|", 1)[0].strip()
except Exception:
    pass
seen = False
try:
    if os.path.isfile(audit_path):
        for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
            ts = line.split("|", 1)[0].strip()
            if session_ts and ts < session_ts:
                continue
            for marker in ("| asama-1-", "| summary-confirm-approve |", "| asama-2-", "| asama-3-", "| asama-4-", "| precision-audit |", "| engineering-brief |"):
                if marker in line:
                    seen = True; break
            if seen: break
except Exception:
    pass
print("present" if seen else "absent")
PYEOF
)"
  fi
  if [ "$_MCLLOCK_HAS_A1" = "absent" ]; then
    REASON="MCL LOCK — spec_approved=false (yeni oturum, hicbir Asama 1-4 audit i yok). Mutating tool \`${TOOL_NAME}\` blocked. ASLA kod yazma, ASLA spec emit etme. Sirayla yap: (1) Asama 1 — gelistiricinin niyetini anla, tek soru sor (one-question-at-a-time) VEYA tum parametreler net ise SILENT-ASSUME path le ozet uret + summary-confirm-approve audit emit. (2) Asama 2 — 7 boyutluk precision audit (skills/my-claude-lang/asama2-precision-audit.md) walk et + closing AskUserQuestion ile asama-2-complete audit. (3) Asama 3 — engineering brief (audit: engineering-brief). (4) Asama 4 — spec emit + AskUserQuestion onay askq. Mutating tools yalnizca asama-4-complete audit i emit edildikten sonra acilir. Recovery: spec onayindan kacis yok — pipeline sirasini izle."
  else
    REASON="MCL LOCK — spec_approved=false. Mutating tool \`${TOOL_NAME}\` is blocked (since v10.1.7 — real block, not advisory). Recovery options: (A) re-emit AskUserQuestion with prefix \`MCL <ver> | \` for spec approval; (B) if developer already approved but classifier missed, run: \`bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log asama-4-complete mcl-stop \"spec_hash=<H> approver=user\"'\` to force-progress state; (C) loop-breaker fail-open after 3 consecutive blocks."
  fi
  REASON_KIND="spec-approval"
fi

# -------- Branch: phase allowlist (v13.0.9 Layer B — hard gate) --------
# Reads gate-spec.json for current_phase's `allowed_tools` + `denied_paths`.
# Read/Glob/Grep/LS/WebFetch/WebSearch/Task/Skill always allowed (investigation
# valves). Bash always allowed (audit-emit + investigation; Layer C/D handles
# Bash content-level checks). TodoWrite is explicit per gate-spec.json
# (currently allowed at phases 6+ where execution work happens).
#
# When TOOL_NAME is in {Write, Edit, MultiEdit, NotebookEdit, AskUserQuestion,
# TodoWrite}, check if it's in the active phase's allowed_tools list.
# If not → deny + REASON "Aşama N bu tool'a izin vermez".
# Then if denied_paths is set, check tool's file_path against globs.
# Match → deny + REASON "Aşama N denied_paths kuralı: <path> yasak".
#
# Skipped when spec_approved=false (MCL LOCK already denies; no need for
# double layer). Skipped when current_phase is empty/invalid.
if [ -z "$REASON" ] && [ "$SPEC_APPROVED" = "true" ] && command -v python3 >/dev/null 2>&1; then
  case "$TOOL_NAME" in
    Read|Glob|Grep|LS|WebFetch|WebSearch|Task|Skill|Bash) : ;;  # always allowed
    Write|Edit|MultiEdit|NotebookEdit|AskUserQuestion|TodoWrite)
      _PA_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
      if [ -n "$_PA_PHASE" ] && [ "$_PA_PHASE" -ge 1 ] 2>/dev/null && [ "$_PA_PHASE" -le 22 ] 2>/dev/null; then
        _PA_GATE_SPEC="${MCL_GATE_SPEC:-${HOME}/.claude/skills/my-claude-lang/gate-spec.json}"
        _PA_AUDIT_PATH="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
        _PA_TRACE_PATH="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
        if [ -f "$_PA_GATE_SPEC" ]; then
          _PA_VERDICT="$(printf '%s' "$RAW_INPUT" | python3 -c "
import json, re, sys, fnmatch, os
spec_path = '$_PA_GATE_SPEC'
state_phase = '$_PA_PHASE'
tool = '$TOOL_NAME'
audit_path = '$_PA_AUDIT_PATH'
trace_path = '$_PA_TRACE_PATH'
try:
    obj = json.loads(sys.stdin.read())
    tin = obj.get('tool_input') or {}
except Exception:
    print('allow|'); sys.exit(0)
file_path = tin.get('file_path') or tin.get('notebook_path') or ''
try:
    spec = json.load(open(spec_path))
except Exception:
    print('allow|'); sys.exit(0)

# v13.0.10: audit-derived active phase resolver. Legacy code sets
# state.current_phase=7 after asama-4-complete (catch-all sentinel for
# 'post spec approval'). v12+ canonical splits this into 5,6,7,8,9.
# When state=7 (or any \\\"post-approval\\\" value), derive the ACTUAL active
# phase from audit.log: walk phases 5..22, find first incomplete phase.
session_ts = ''
try:
    if os.path.isfile(trace_path):
        for line in open(trace_path, 'r', encoding='utf-8', errors='replace'):
            if '| session_start |' in line:
                session_ts = line.split('|', 1)[0].strip()
except Exception:
    pass

audit_lines = []
try:
    if os.path.isfile(audit_path):
        for line in open(audit_path, 'r', encoding='utf-8', errors='replace'):
            ts = line.split('|', 1)[0].strip()
            if session_ts and ts < session_ts:
                continue
            audit_lines.append(line)
except Exception:
    pass

def has_audit_marker(needle):
    return any(f'| {needle} |' in l for l in audit_lines) or any(f'| {needle}' in l for l in audit_lines)

def phase_complete_basic(p_str):
    p = spec['phases'].get(p_str, {})
    if has_audit_marker(f'asama-{p_str}-complete'): return True
    if 'required_audits_any' in p:
        return any(has_audit_marker(a) for a in p['required_audits_any'])
    if 'required_audits' in p:
        return all(has_audit_marker(a) for a in p['required_audits'])
    if 'required_sections' in p:
        return all(has_audit_marker(a) for a in p['required_sections'])
    return False

# Derive active phase. Only walk audit log when state=7 (legacy
# post-approval catch-all sentinel that v10/v11 progression code uses).
# Other state values (1-6, 8-22) are treated as canonical v12+ phase
# numbers and used directly.
sp = int(state_phase)
if sp == 7:
    # Legacy sentinel — derive from audit. Walk 5..22, first incomplete.
    derived = None
    for p in range(5, 23):
        if not phase_complete_basic(str(p)):
            derived = p
            break
    if derived is None:
        derived = 22
    active_phase = str(derived)
elif sp >= 1 and sp <= 22:
    active_phase = str(sp)
else:
    print('allow|'); sys.exit(0)

try:
    pspec = spec['phases'][active_phase]
except Exception:
    print('allow|'); sys.exit(0)

allowed = pspec.get('allowed_tools', None)
if allowed is None:
    print('allow|'); sys.exit(0)
if tool not in allowed:
    print(f'deny:tool|tool={tool} state_phase={state_phase} active_phase={active_phase} allowed={\",\".join(allowed) if allowed else \"none\"}')
    sys.exit(0)
denied = pspec.get('denied_paths', [])
if denied and file_path:
    norm = file_path.replace('\\\\\\\\', '/').lstrip('./')
    for pat in denied:
        if fnmatch.fnmatch(norm, pat) or fnmatch.fnmatch('/' + norm, pat) or fnmatch.fnmatch(norm, pat.lstrip('*/').lstrip('/')):
            print(f'deny:path|path={file_path} pattern={pat} active_phase={active_phase}')
            sys.exit(0)
print('allow|')
" 2>/dev/null)"
          # Extract derived active_phase from verdict detail for accurate REASON.
          _PA_ACTIVE="$(printf '%s' "$_PA_VERDICT" | grep -oE 'active_phase=[0-9]+' | head -1 | cut -d= -f2)"
          [ -z "$_PA_ACTIVE" ] && _PA_ACTIVE="$_PA_PHASE"
          case "${_PA_VERDICT%%|*}" in
            deny:tool)
              _PA_DETAIL="${_PA_VERDICT#deny:tool|}"
              REASON="MCL PHASE ALLOWLIST (v13.0.10 Layer B STRICT) — Audit'ten türetilen aktif faz: Aşama ${_PA_ACTIVE} (state.current_phase=${_PA_PHASE} legacy değer). \`${TOOL_NAME}\` tool'una bu fazda izin verilmez. ${_PA_DETAIL}. Aşama ${_PA_ACTIVE}'in izinli tool'ları gate-spec.json'da. \`asama-${_PA_ACTIVE}-complete\` veya \`asama-${_PA_ACTIVE}-skipped\` audit emit edilirse otomatik bir sonraki faza geçer. Read/Glob/Grep/LS/WebFetch/WebSearch/Task/Skill/Bash her fazda izinli (investigation + audit-emit valve). KATI MOD (v13.0.10): fail-open YOK; 5 strike sonrası user'a escalate audit emit edilir, block kalkmaz."
              REASON_KIND="phase-allowlist-tool"
              mcl_audit_log "phase-allowlist-tool-block" "pre-tool" "tool=${TOOL_NAME} state_phase=${_PA_PHASE} active_phase=${_PA_ACTIVE}"
              ;;
            deny:path)
              _PA_DETAIL="${_PA_VERDICT#deny:path|}"
              REASON="MCL PHASE PATH-LOCK (v13.0.10 Layer B STRICT) — Audit'ten türetilen aktif faz: Aşama ${_PA_ACTIVE} (state.current_phase=${_PA_PHASE}). Bu yol yasak. ${_PA_DETAIL}. Örnek: Aşama 6 (UI Build) backend yollarını (\`src/api/**\`, \`prisma/**\`, ...) yasaklar — backend Aşama 9 TDD veya Aşama 8 DB Design'da yazılır. KATI MOD: fail-open YOK."
              REASON_KIND="phase-allowlist-path"
              mcl_audit_log "phase-allowlist-path-block" "pre-tool" "state_phase=${_PA_PHASE} active_phase=${_PA_ACTIVE}"
              ;;
          esac
        fi
      fi
      ;;
  esac
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
    REASON="MCL PHASE 5 — Pattern scan pending. Before writing any Aşama 9 TDD code, read the existing sibling files listed in the PATTERN_MATCHING_NOTICE to extract naming, error handling, import style, and test structure patterns. Write nothing this turn — use Read tool on each listed file, note the patterns, then end the turn. Writes will unblock automatically on the next turn."
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
    REASON="MCL SCOPE GUARD (Rule 2 — File Scope) — \`${_SCOPE_DENIED_PATH}\` is not in the spec's declared file scope. This also likely violates Rule 1 (Spec-Only): if this file needs changes, it should have been in the spec. Options: (A) surface as a Aşama 10 risk and request scope extension; (B) if genuinely required now, ask the developer via AskUserQuestion BEFORE writing — never silently touch out-of-scope files."
    mcl_audit_log "scope-guard-block" "pre-tool" "path=${_SCOPE_DENIED_PATH} tool=${TOOL_NAME}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append scope_guard_block "${_SCOPE_DENIED_PATH}"
  fi
fi

# -------- Branch: Aşama 2 skip-block (since v10.1.14) --------
# Replaces the v10.1.12 Aşama 1 OR-list check. Per the deterministic-
# GATE design principle, Aşama 4 (SPEC) emission requires exactly one
# audit: `asama-2-complete`. That audit is emitted by the Stop hook
# only when the Aşama 2 closing AskUserQuestion (intent: precision-
# confirm) returns an approve-family answer. Because Aşama 2 is
# canonically called only after Aşama 1's summary-confirm-approve, a
# valid `asama-2-complete` implicitly proves Aşama 1 also ran — one
# gate, full chain.
#
# This replaces the previous OR-list (summary-confirm-approve |
# precision-audit | asama-1-complete) which was too permissive: any
# of three signals would unblock SPEC, allowing the model to skip the
# precision audit entirely while still passing the gate.
#
# Recovery: model runs the Aşama 2 closing askq cycle properly
# (7-dimension scan, GATE answers, then closing AskUserQuestion with
# title prefix `MCL <ver> | Faz 2 — Precision-audit niyet onayı:`),
# OR emits the explicit Bash audit hatch.
if [ -z "$REASON" ] && [ "$SPEC_APPROVED" = "true" ]; then
  _A2_HIT_AC="$(_mcl_audit_emitted_in_session "asama-2-complete" "" 2>/dev/null || echo 0)"
  if [ "${_A2_HIT_AC:-0}" != "1" ]; then
    REASON="MCL ASAMA 2 SKIP-BLOCK (since v10.1.14) — spec onaylandı (spec_approved=true) AMA Aşama 2 (precision audit + niyet onayı) tamamlandığına dair \`asama-2-complete\` audit'i yok. Bu, spec'in **doğrulanmamış / precision-audit'ten geçmemiş parametreler** üzerine kurulduğu anlamına gelir → yanlış kod riski downstream gate'ler geçse bile sürer. Mutating tool \`${TOOL_NAME}\` bloke edildi. Recovery options: (A) Aşama 2 closing askq cycle'ı düzgün çalıştır — 7 boyutluk precision audit (skills/my-claude-lang/asama2-precision-audit.md) tamamla, ardından \`MCL <ver> | Faz 2 — Precision-audit niyet onayı:\` başlıklı AskUserQuestion ile niyet onayı al; (B) Aşama 2 sözel olarak MCL dışı tamamlandıysa: \`bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log asama-2-complete mcl-stop \"params=precision-audit-confirmed\"'\` ile audit emit et. Loop-breaker: 3 üst üste blok → fail-open."
    REASON_KIND="asama-2-skip"
  fi
fi

# -------- Branch: Aşama 8/9 skip-block (since v10.1.8) --------
# When Stop hook detected `asama-{8,9}-emit-missing` (model wrote
# production code without running risk review / quality+tests), block
# subsequent mutating tools until the model emits the missing
# `asama-N-complete` audit. Mirrors v10.1.7 spec-approval-block
# pattern but for behavioral skip detection. Only fires when
# SPEC_APPROVED=true (otherwise spec-approval-block handles it first).
#
# Real-world trigger: the grom backoffice case — model wrote 29 prod
# files without Aşama 8 dialog, soft visibility surfaced the skip but
# 7 security findings (2 HIGH + 5 MEDIUM, independently audited)
# still landed. Soft visibility was not enough; v10.1.8 turns the
# emit-missing audit into an actionable block on the next turn.
if [ -z "$REASON" ] && [ "$SPEC_APPROVED" = "true" ]; then
  for _SKIP_PH in 8 9; do
    _EM_HIT="$(_mcl_audit_emitted_in_session "asama-${_SKIP_PH}-emit-missing" "" 2>/dev/null || echo 0)"
    _AC_HIT="$(_mcl_audit_emitted_in_session "asama-${_SKIP_PH}-complete" "" 2>/dev/null || echo 0)"
    if [ "${_EM_HIT:-0}" = "1" ] && [ "${_AC_HIT:-0}" != "1" ]; then
      REASON="MCL ASAMA ${_SKIP_PH} SKIP-BLOCK (since v10.1.7 — real block, not advisory) — Stop hook detected the model wrote production code without running Aşama ${_SKIP_PH} (audit: \`asama-${_SKIP_PH}-emit-missing\`). Mutating tool \`${TOOL_NAME}\` is blocked until the phase-completion audit is recorded. Recovery: bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log asama-${_SKIP_PH}-complete mcl-stop \"<details>\"' — see \`skills/my-claude-lang/asama${_SKIP_PH}-*.md\` for required detail format. Loop-breaker: 3 consecutive blocks → fail-open."
      REASON_KIND="asama-${_SKIP_PH}-skip"
      break
    fi
  done
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
  elif [ "$REASON_KIND" = "asama-2-skip" ] \
       || [ "$REASON_KIND" = "asama-8-skip" ] \
       || [ "$REASON_KIND" = "asama-9-skip" ]; then
    # v10.1.8 + v10.1.12: phase-skip blocks. Same loop-breaker shape
    # as spec-approval-block. Recovery is the asama-N-complete Bash
    # emit (parallels v10.1.7 spec-approval recovery via asama-4-complete).
    _SKIP_PH_NUM="${REASON_KIND#asama-}"
    _SKIP_PH_NUM="${_SKIP_PH_NUM%-skip}"
    _SK_LB_COUNT="$(_mcl_loop_breaker_count "asama-${_SKIP_PH_NUM}-skip-block" 2>/dev/null || echo 0)"
    if [ "${_SK_LB_COUNT:-0}" -ge 3 ]; then
      mcl_audit_log "asama-${_SKIP_PH_NUM}-skip-loop-broken" "pre-tool" "count=${_SK_LB_COUNT} fail-open"
      command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append "asama_${_SKIP_PH_NUM}_skip_loop_broken" "${_SK_LB_COUNT}"
      DECISION="allow"
    else
      DECISION="deny"
      mcl_audit_log "asama-${_SKIP_PH_NUM}-skip-block" "pre-tool" "tool=${TOOL_NAME} strike=$((_SK_LB_COUNT + 1))"
      command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append "asama_${_SKIP_PH_NUM}_skip_block" "$((_SK_LB_COUNT + 1))"
    fi
  elif [ "$REASON_KIND" = "phase-allowlist-tool" ] \
       || [ "$REASON_KIND" = "phase-allowlist-path" ]; then
    # v13.0.10 STRICT — phase allowlist hard gate. NO fail-open.
    # Each strike logged for /mcl-checkup visibility. After 5 strikes,
    # an escalation audit is emitted (mcl-activate.sh injects user-visible
    # warning notice on next turn — developer must intervene). Block STAYS.
    # Rationale: v13.0.9 had 5-strike fail-open which let 30-file dump
    # through after model exhausted strikes. STRICT mode forces developer
    # intervention rather than silent escape.
    _PA_LB_COUNT="$(_mcl_loop_breaker_count "${REASON_KIND}" 2>/dev/null || echo 0)"
    DECISION="deny"
    mcl_audit_log "${REASON_KIND}" "pre-tool" "tool=${TOOL_NAME} strike=$((_PA_LB_COUNT + 1))"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append "${REASON_KIND}" "$((_PA_LB_COUNT + 1))"
    if [ "${_PA_LB_COUNT:-0}" -ge 5 ]; then
      # Escalation audit — surfaced by activate hook as a user-visible
      # notice. NOT fail-open; block continues.
      _PA_ESC_AUDIT="${REASON_KIND}-escalate"
      _PA_ESC_SEEN="$(_mcl_audit_emitted_in_session "$_PA_ESC_AUDIT" "" 2>/dev/null || echo 0)"
      if [ "${_PA_ESC_SEEN:-0}" != "1" ]; then
        mcl_audit_log "$_PA_ESC_AUDIT" "pre-tool" "count=${_PA_LB_COUNT} tool=${TOOL_NAME}"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append "${REASON_KIND}_escalate" "${_PA_LB_COUNT}"
      fi
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
