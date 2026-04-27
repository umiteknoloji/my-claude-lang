#!/bin/bash
# MCL Stop Hook — parse Claude's final assistant message, detect the
# `📋 Spec:` block, compute sha256 over a normalized body, and update
# `.mcl/state.json` accordingly.
#
# Transitions driven here:
#   - phase 1 → 2 (SPEC_REVIEW)      : first time a spec block appears
#   - phase 2/3 → 4 (EXECUTE)        : AskUserQuestion spec-approval call
#                                      returned an "Approve" family option

# Never regresses phase. Never overwrites an approved spec's hash
# without an explicit new AskUserQuestion approval.
#
# Stop hook input: JSON on stdin with `transcript_path` (Claude Code's
# jsonl transcript for the current session).
#
# Since 6.0.0: the text-based `✅ MCL APPROVED` marker protocol is
# REMOVED. Approval signals come from `AskUserQuestion` tool_use /
# tool_result pairs whose `question` begins with `MCL {version} | `.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Save hook dir before sourcing libs — some lib files (mcl-test-runner.sh)
# reset SCRIPT_DIR to their own directory, clobbering the hook's own path.
_MCL_HOOK_DIR="$SCRIPT_DIR"
INSTALLED_VERSION="$(grep -oE '🌐 MCL [0-9]+\.[0-9]+\.[0-9]+' "$SCRIPT_DIR/mcl-activate.sh" 2>/dev/null | head -1 | awk '{print $3}')"
INSTALLED_VERSION="${INSTALLED_VERSION:-unknown}"
# shellcheck source=lib/mcl-state.sh
source "$_MCL_HOOK_DIR/lib/mcl-state.sh"
# shellcheck source=lib/mcl-trace.sh
[ -f "$_MCL_HOOK_DIR/lib/mcl-trace.sh" ] && source "$_MCL_HOOK_DIR/lib/mcl-trace.sh"
# shellcheck source=lib/mcl-test-runner.sh
[ -f "$_MCL_HOOK_DIR/lib/mcl-test-runner.sh" ] && source "$_MCL_HOOK_DIR/lib/mcl-test-runner.sh"
# shellcheck source=lib/mcl-log-append.sh
[ -f "$_MCL_HOOK_DIR/lib/mcl-log-append.sh" ] && source "$_MCL_HOOK_DIR/lib/mcl-log-append.sh"

RAW_INPUT="$(cat 2>/dev/null || true)"

TRANSCRIPT_PATH="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print(obj.get("transcript_path", "") or "")
except Exception:
    pass
' 2>/dev/null)"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  mcl_debug_log "stop" "no-transcript" "path='${TRANSCRIPT_PATH}'"
  exit 0
fi

# Parse the transcript: find the most recent assistant message whose
# text CONTAINS a `📋 Spec:` block (since 6.5.5 — earlier versions took
# the last assistant text unconditionally, so trailing non-spec
# narration in a spec-bearing turn hid the spec from the hook and
# forced the model to re-emit it on recovery turns). Bound the block
# by the next markdown heading `^#...` or EOF, normalize, sha256.
# Output to stdout: a single hex digest if a spec block was found,
# otherwise nothing.
SPEC_HASH="$(python3 -c '
import json, sys, hashlib, re

path = sys.argv[1]

def extract_text(msg):
    if isinstance(msg, dict) and "message" in msg and isinstance(msg["message"], dict):
        msg = msg["message"]
    if not isinstance(msg, dict):
        return None
    role = msg.get("role")
    if role != "assistant":
        return None
    content = msg.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                t = item.get("text")
                if isinstance(t, str):
                    parts.append(t)
        return "\n".join(parts) if parts else None
    return None

spec_line_re = re.compile(r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?\U0001F4CB[ \t]+Spec:", re.MULTILINE)

last_spec_text = None
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
            text = extract_text(obj)
            if text and spec_line_re.search(text):
                last_spec_text = text
except Exception:
    sys.exit(0)

if not last_spec_text:
    sys.exit(0)

lines = last_spec_text.splitlines()
start = None
for i, ln in enumerate(lines):
    if spec_line_re.match(ln):
        start = i
        break
if start is None:
    sys.exit(0)

end = len(lines)
for j in range(start + 1, len(lines)):
    stripped = lines[j].lstrip()
    if re.match(r"^#+\s", stripped):
        end = j
        break

body_lines = lines[start:end]

normalized = []
prev_blank = False
for ln in body_lines:
    ln = ln.rstrip()
    is_blank = (ln == "")
    if is_blank and prev_blank:
        continue
    normalized.append(ln)
    prev_blank = is_blank
while normalized and normalized[0] == "":
    normalized.pop(0)
while normalized and normalized[-1] == "":
    normalized.pop()

body = "\n".join(normalized)
if not body:
    sys.exit(0)

print(hashlib.sha256(body.encode("utf-8")).hexdigest())
' "$TRANSCRIPT_PATH" 2>/dev/null)"

if [ -z "$SPEC_HASH" ]; then
  mcl_debug_log "stop" "no-spec" "transcript=${TRANSCRIPT_PATH}"
fi

# --- Partial spec detection (rate-limit interruption defense) ---
# Unchanged from 5.x. Claude must re-emit a complete spec before the
# AskUserQuestion approval call can advance state; while partial_spec
# is true, any approval tool_result is ignored as defense-in-depth.
PARTIAL_MISSING="$(bash "$_MCL_HOOK_DIR/lib/mcl-partial-spec.sh" check "$TRANSCRIPT_PATH" 2>/dev/null)"
PARTIAL_RC=$?
PARTIAL_STATE="$(mcl_state_get partial_spec 2>/dev/null)"
case "$PARTIAL_RC" in
  0)
    mcl_state_set partial_spec true
    if [ -n "$SPEC_HASH" ]; then
      mcl_state_set partial_spec_body_sha "\"${SPEC_HASH:0:16}\""
    fi
    mcl_audit_log "partial-spec" "stop" "missing=$(printf '%s' "$PARTIAL_MISSING" | tr '\n' ',' | sed 's/,$//')"
    mcl_debug_log "stop" "partial-spec" "missing=$(printf '%s' "$PARTIAL_MISSING" | tr '\n' '|')"
    ;;
  1)
    if [ "$PARTIAL_STATE" = "true" ]; then
      mcl_state_set partial_spec false
      mcl_state_set partial_spec_body_sha null
      mcl_audit_log "partial-spec-cleared" "stop" ""
      mcl_debug_log "stop" "partial-spec-cleared" ""
    fi
    ;;
  *)
    :
    ;;
esac

# --- AskUserQuestion approval scanner (shared lib since 6.5.6) ---
# The scanner lives at hooks/lib/mcl-askq-scanner.py. Stop and PreToolUse
# invoke the same script so intent classification + selected-option
# extraction cannot drift between hooks. Scanner output is JSON with
# fields {intent, selected, spec_hash}; stop consumes intent + selected
# (spec_hash is computed separately above as SPEC_HASH for compatibility
# with the existing post-approval branches). Intent is one of:
#   spec-approve      — Phase 3 spec approval
#   summary-confirm   — Phase 1 summary confirmation (audit-only here)
#   ui-review         — Phase 4b UI review approval
#   other             — recognized MCL question but not state-transitioning
ASKQ_SCANNER="$_MCL_HOOK_DIR/lib/mcl-askq-scanner.py"
if [ -f "$ASKQ_SCANNER" ] && command -v python3 >/dev/null 2>&1; then
  ASKQ_JSON="$(python3 "$ASKQ_SCANNER" "$TRANSCRIPT_PATH" 2>/dev/null)"
else
  ASKQ_JSON=""
fi
ASKQ_RECORD="$(printf '%s' "$ASKQ_JSON" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    intent = obj.get("intent","") or ""
    selected = obj.get("selected","") or ""
    if intent or selected:
        print(f"{intent}|{selected}")
except Exception:
    pass
' 2>/dev/null)"


ASKQ_INTENT=""
ASKQ_SELECTED=""
if [ -n "$ASKQ_RECORD" ]; then
  ASKQ_INTENT="${ASKQ_RECORD%%|*}"
  ASKQ_SELECTED="${ASKQ_RECORD#*|}"
fi

# Plain-text approval fallback (since 7.9.8):
# Developers sometimes type approval words in the chat input instead of
# clicking the AskUserQuestion button. When no tool-based spec-approve
# was detected AND current_phase=2 AND spec_hash is set, scan the most
# recent USER message for approve-family text. If found, synthesize a
# spec-approve intent so the phase-advance branch below fires.
_PLAINTEXT_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
_PLAINTEXT_HASH="$(mcl_state_get spec_hash 2>/dev/null)"
if [ "$ASKQ_INTENT" != "spec-approve" ] && \
   [ "$_PLAINTEXT_PHASE" = "2" ] && \
   [ -n "$_PLAINTEXT_HASH" ] && \
   [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && \
   command -v python3 >/dev/null 2>&1; then
  _PT_RESULT="$(python3 - "$TRANSCRIPT_PATH" 2>/dev/null <<'PYEOF'
import json, sys

path = sys.argv[1]
approve_words = {
    "onayla", "onaylıyorum", "onayliyorum", "onaylıyorum", "evet", "kabul", "tamam",
    "approve", "yes", "confirm", "ok", "proceed", "accept",
    "aprobar", "sí", "si", "confirmar",
    "approuver", "oui", "confirmer",
    "genehmigen", "bestätigen", "ja",
    "承認", "はい", "確認", "了解",
    "승인", "네", "확인", "예",
    "批准", "是", "确认",
    "موافق", "نعم",
    "אשר", "כן",
    "स्वीकार", "हाँ", "हां",
    "setujui", "ya",
    "aprovar", "sim",
    "одобрить", "да",
}
last_user_text = None
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
            msg = obj if "role" in obj else obj.get("message", {})
            if not isinstance(msg, dict):
                continue
            if msg.get("role") == "user":
                content = msg.get("content", "")
                if isinstance(content, str):
                    last_user_text = content.strip()
                elif isinstance(content, list):
                    parts = [b.get("text","") for b in content if isinstance(b,dict) and b.get("type")=="text"]
                    last_user_text = " ".join(parts).strip()
except Exception:
    pass

if last_user_text:
    norm = last_user_text.lower().strip(" .,!?")
    if norm in approve_words or any(norm.startswith(w) for w in approve_words):
        print(f"approve|{last_user_text}")
PYEOF
)"
  if [ -n "$_PT_RESULT" ]; then
    ASKQ_INTENT="spec-approve"
    ASKQ_SELECTED="${_PT_RESULT#*|}"
    mcl_audit_log "plaintext-approve-detected" "stop" "text=${ASKQ_SELECTED}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append plaintext_approve_detected "${ASKQ_SELECTED}"
  fi
fi

# Helper: is $1 an "approve family" option string?
# Lowercase substring match on a fixed 14-language whitelist.
_mcl_is_approve_option() {
  local raw="$1"
  [ -z "$raw" ] && return 1
  local norm
  norm="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$norm" in
    *onayla*|*onaylıyorum*|*onaylıyorum*|*evet*|*kabul*|*tamam*) return 0 ;;
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
    *aprovar*|*sim*|*confirmar*) return 0 ;;
    *одобрить*|*да*|*подтвердить*) return 0 ;;
  esac
  return 1
}

# Helper: does the selected option on the Phase 4b ui-review askq ask
# MCL to visually inspect the built UI itself (opt-in vision loop)?
# Returns 0 when the developer picks the "see and report back yourself"
# option. 14-language substring match via direct UTF-8 characters.
_mcl_is_vision_request_option() {
  local raw="$1"
  [ -z "$raw" ] && return 1
  local norm
  norm="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$norm" in
    *"sen de bak"*|*"kendin bak"*|*"kendin gör"*) return 0 ;;
    *"see it yourself"*|*"look yourself"*|*"inspect yourself"*|*"you look"*) return 0 ;;
    *"míralo tú"*|*"revisa tú mismo"*) return 0 ;;
    *"regarde toi-même"*|*"inspecte toi-même"*) return 0 ;;
    *"schau selbst"*|*"selbst prüfen"*) return 0 ;;
    *"自分で確認"*|*"自分で見"*) return 0 ;;
    *"직접 확인"*|*"직접 보"*) return 0 ;;
    *"你自己看"*|*"自己检查"*) return 0 ;;
    *"تحقق بنفسك"*) return 0 ;;
    *"תבדוק בעצמך"*) return 0 ;;
    *"खुद देखें"*) return 0 ;;
    *"lihat sendiri"*|*"cek sendiri"*) return 0 ;;
    *"veja você mesmo"*|*"inspecione você"*) return 0 ;;
    *"посмотри сам"*|*"проверь сам"*) return 0 ;;
  esac
  return 1
}

# Initialise state early — needed by phase review guard below as well as the
# existing spec/askq transition branches.
mcl_state_init
CURRENT_PHASE="$(mcl_state_get current_phase)"

# --- Phase 4.5 / 4.6 / 5 review enforcement (since 7.1.3) ---
#
# Core invariant: after Phase 4 code is written, Claude MUST run Phase 4.5
# Risk Review, Phase 4.6 Impact Review, and Phase 5 Verification Report before
# the session can end. This is enforced via `decision: block` — Claude Code
# refuses to close the turn until Claude starts Phase 4.5.
#
# State machine (stored in phase_review_state):
#   null / absent — Phase 4 hasn't written code yet (no enforcement needed)
#   "pending"     — code was written, Phase 4.5 not yet started → BLOCK
#   "running"     — Phase 4.5/4.6 dialog is in progress → allow through
#
# Transitions:
#   code_written=true AND askuq=false         → pending  (block)
#   code_written=true AND askuq=true          → running  (Phase 4.5 fix + next-risk)
#   code_written=false AND askuq=true         → running  (pure dialog turn)
#   pending AND code_written=false AND askuq=false → pending  (sticky — re-block)
#   Session boundary resets state to null (mcl-activate.sh).
#
# "pending" is STICKY: once set, the BLOCK re-fires on every subsequent turn
# until askuq=true clears it. This prevents a Bash-only or text-only follow-up
# turn from silently escaping the enforcement gate.
_PR_GUARD="$_MCL_HOOK_DIR/lib/mcl-phase-review-guard.py"
if [ -f "$_PR_GUARD" ] && command -v python3 >/dev/null 2>&1 \
   && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  _PR_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
  _PR_APPROVED="$(mcl_state_get spec_approved 2>/dev/null)"
  _PR_REVIEW_STATE="$(mcl_state_get phase_review_state 2>/dev/null)"

  if [ "$_PR_PHASE" = "4" ] && [ "$_PR_APPROVED" = "true" ]; then
    _PR_JSON="$(python3 "$_PR_GUARD" "$TRANSCRIPT_PATH" 2>/dev/null)"
    _PR_CODE="$(printf '%s' "$_PR_JSON" | python3 -c \
      'import json,sys; d=json.loads(sys.stdin.read()); print("true" if d.get("code_written") else "false")' 2>/dev/null)"
    _PR_ASKUQ="$(printf '%s' "$_PR_JSON" | python3 -c \
      'import json,sys; d=json.loads(sys.stdin.read()); print("true" if d.get("askuq_present") else "false")' 2>/dev/null)"

    if [ "$_PR_ASKUQ" = "true" ]; then
      # Phase 4.5/4.6 dialog is running this turn — transition to "running"
      # regardless of whether code was also written (risk-fix + next-risk turn).
      if [ "$_PR_REVIEW_STATE" != "running" ]; then
        mcl_state_set phase_review_state '"running"' >/dev/null 2>&1 || true
        mcl_audit_log "phase-review-running" "stop" "prev=${_PR_REVIEW_STATE}"
        command -v mcl_trace_append >/dev/null 2>&1 && \
          mcl_trace_append phase_review_running "${_PR_REVIEW_STATE:-null}"
      fi
    elif [ "$_PR_CODE" = "true" ] || [ "$_PR_REVIEW_STATE" = "pending" ]; then
      # Code written this turn, OR pending state persists from a prior turn
      # (sticky enforcement — Bash-only/text-only turns cannot escape the gate).
      mcl_state_set phase_review_state '"pending"' >/dev/null 2>&1 || true
      mcl_audit_log "phase-review-pending" "stop" \
        "prev=${_PR_REVIEW_STATE} phase=${_PR_PHASE} code=${_PR_CODE}"
      command -v mcl_trace_append >/dev/null 2>&1 && \
        mcl_trace_append phase_review_pending "${_PR_REVIEW_STATE:-null}"

      # Regression guard — run full test suite on FIRST transition to pending.
      # Sticky re-triggers (already pending) skip re-run to avoid slowdown.
      # Smart-skip: if TDD's last green-verify was GREEN within this turn
      # (timestamp within 120s), the suite already passed — skip re-run.
      _RG_SKIP=false
      if [ "$_PR_CODE" = "true" ] && [ "$_PR_REVIEW_STATE" != "pending" ]; then
        _RG_SKIP="$(python3 - <<'PYEOF' 2>/dev/null || echo false
import json, os, time
_proj = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
state_file = os.environ.get("MCL_STATE_FILE",
    os.path.join(os.environ.get("MCL_STATE_DIR", os.path.join(_proj, ".mcl")), "state.json"))
try:
    obj = json.loads(open(state_file).read())
    lg = obj.get("tdd_last_green")
    if not (isinstance(lg, dict) and lg.get("result") == "GREEN"):
        print("false"); raise SystemExit
    green_ts = float(lg.get("ts", 0))
    age = time.time() - green_ts
    if age >= 120:
        print("false"); raise SystemExit
    # Stale if any write happened after the green-verify
    lw = obj.get("last_write_ts")
    if lw is not None and float(lw) > green_ts:
        print("false"); raise SystemExit
    print("true")
except SystemExit:
    pass
except Exception:
    print("false")
PYEOF
)"
        if [ "$_RG_SKIP" = "true" ]; then
          mcl_audit_log "regression-guard-skipped" "stop" "reason=tdd-green-verify-fresh"
        fi
      fi

      if [ "$_PR_CODE" = "true" ] && [ "$_PR_REVIEW_STATE" != "pending" ] \
         && [ "$_RG_SKIP" != "true" ] \
         && command -v mcl_test_run >/dev/null 2>&1; then
        _RG_OUTPUT="$(mcl_test_run "regression-guard" 2>/dev/null)"
        if printf '%s' "$_RG_OUTPUT" | grep -q "^❌ Tests: RED"; then
          # Store failing output (JSON-safe, truncated to 1KB)
          _RG_JSON="$(printf '%s' "$_RG_OUTPUT" | python3 -c \
            'import json,sys; print(json.dumps(sys.stdin.read()[:1024]))' 2>/dev/null || echo '""')"
          mcl_state_set regression_block_active true >/dev/null 2>&1 || true
          mcl_state_set regression_output "$_RG_JSON" >/dev/null 2>&1 || true
          mcl_audit_log "regression-guard-red" "stop" "prev=${_PR_REVIEW_STATE}"
          command -v mcl_trace_append >/dev/null 2>&1 && \
            mcl_trace_append regression_guard_red
        else
          # GREEN or no test command — clear any stale block
          mcl_state_set regression_block_active false >/dev/null 2>&1 || true
          mcl_state_set regression_output '""' >/dev/null 2>&1 || true
          [ -n "$_RG_OUTPUT" ] && mcl_audit_log "regression-guard-green" "stop" ""
        fi
      fi

      # Return decision:block so Claude is forced to continue.
      printf '%s\n' "{
  \"decision\": \"block\",
  \"reason\": \"⚠️ MCL PHASE REVIEW ENFORCEMENT (mandatory, non-skippable)\n\nPhase 4 code was written but Phase 4.5 Risk Review has NOT been started. You have two valid responses:\n\n(A) IF Phase 4c BACKEND is NOT yet fully complete:\n    Continue writing the remaining code. State explicitly which files still need to be written. The enforcement block will repeat on each code-write turn until Phase 4.5 starts.\n\n(B) IF ALL Phase 4 code is NOW complete:\n    Start Phase 4.5 Risk Review IMMEDIATELY in this response. Do NOT delay, do NOT summarize what you built, do NOT ask the developer a question unrelated to risks. Begin Phase 4.5 now:\n    1. Review the code you just wrote for: security vulnerabilities (injection, auth bypass, XSS, CSRF, insecure defaults), performance bottlenecks (N+1, unbounded queries, missing indexes), edge cases (null/empty/overflow inputs), data integrity issues (missing transactions, inconsistent state), race conditions, regression surfaces.\n    2. Present ONE risk at a time via AskUserQuestion with prefix MCL ${INSTALLED_VERSION} |\n    3. After ALL Phase 4.5 risks are resolved → run Phase 4.6 Impact Review.\n    4. After Phase 4.6 → run Phase 5 Verification Report.\n\nPhase 4.5 → 4.6 → 5 are MANDATORY. Skipping them violates the MCL contract.\"
}"
      exit 0
    fi
  fi
fi

# --- Phase 3.5 pattern-scan clearance (runs before early exit) ---
# Must run before the spec/askq gate below because the Phase 3.5 turn has
# no spec block and no AskUQ — the early exit would skip this otherwise.
_PS_DUE_EARLY="$(mcl_state_get pattern_scan_due 2>/dev/null)"
_PS_PHASE_EARLY="$(mcl_state_get current_phase 2>/dev/null)"
if [ "$_PS_DUE_EARLY" = "true" ] && [ "$_PS_PHASE_EARLY" = "4" ] \
   && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  _PS_SUMMARY_EARLY="$(python3 - "$TRANSCRIPT_PATH" << 'PYPS_EARLY'
import json, re, sys
path = sys.argv[1]
HEADING_RE = re.compile(
    r'\*\*Naming Convention:\*\*\s*(.+?)(?:\n|$).*?'
    r'\*\*Error Handling Pattern:\*\*\s*(.+?)(?:\n|$).*?'
    r'\*\*Test Pattern:\*\*\s*(.+?)(?:\n|$)',
    re.DOTALL)
last_text = ''
try:
    with open(path, encoding='utf-8', errors='replace') as f:
        for raw in f:
            raw = raw.strip()
            if not raw: continue
            try: obj = json.loads(raw)
            except Exception: continue
            msg = obj if 'role' in obj else obj.get('message', obj)
            if not isinstance(msg, dict) or msg.get('role') != 'assistant': continue
            content = msg.get('content', '')
            text = content if isinstance(content, str) else '\n'.join(
                item.get('text','') for item in content
                if isinstance(item, dict) and item.get('type') == 'text')
            if text.strip(): last_text = text
except Exception: pass
m = HEADING_RE.search(last_text)
if m:
    print(json.dumps({"naming": m.group(1).strip(), "error": m.group(2).strip(), "test": m.group(3).strip()}))
else:
    print('null')
PYPS_EARLY
  2>/dev/null)"
  if [ -n "$_PS_SUMMARY_EARLY" ] && [ "$_PS_SUMMARY_EARLY" != "null" ]; then
    mcl_state_set pattern_summary "$_PS_SUMMARY_EARLY" >/dev/null 2>&1 || true
    mcl_audit_log "pattern-summary-stored" "stop" "early"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append pattern_summary_stored
  fi
  mcl_state_set pattern_scan_due false >/dev/null 2>&1 || true
  mcl_audit_log "pattern-scan-cleared" "stop" "early"
  command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append pattern_scan_cleared
fi

# If neither spec nor AskUserQuestion approval present, nothing to do.
if [ -z "$SPEC_HASH" ] && [ -z "$ASKQ_INTENT" ]; then
  exit 0
fi
CURRENT_HASH="$(mcl_state_get spec_hash)"
SPEC_APPROVED="$(mcl_state_get spec_approved)"

# --- Spec-hash transitions (when a fresh spec is in this turn) ---
if [ -n "$SPEC_HASH" ]; then
  case "$CURRENT_PHASE" in
    1)
      mcl_state_set current_phase 2
      mcl_state_set phase_name '"SPEC_REVIEW"'
      mcl_state_set spec_hash "\"$SPEC_HASH\""
      mcl_debug_log "stop" "transition-1-to-2" "hash=${SPEC_HASH:0:12}"
      command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition 1 2
      command -v mcl_log_append >/dev/null 2>&1 && mcl_log_append "Faz 1 → 2 geçişi (spec algılandı)."
      ;;
    2|3)
      if [ "$CURRENT_HASH" != "$SPEC_HASH" ]; then
        mcl_state_set spec_hash "\"$SPEC_HASH\""
        mcl_debug_log "stop" "hash-update-pre-approval" "old=${CURRENT_HASH:0:12} new=${SPEC_HASH:0:12}"
      else
        mcl_debug_log "stop" "idempotent-noop" "hash=${SPEC_HASH:0:12}"
      fi
      ;;
    4|5)
      mcl_debug_log "stop" "post-approval-noop" "phase=${CURRENT_PHASE} hash=${SPEC_HASH:0:12}"
      ;;
  esac
fi

# --- AskUserQuestion approval transition (replaces marker branch) ---
if [ "$ASKQ_INTENT" = "spec-approve" ]; then
  CURRENT_PHASE="$(mcl_state_get current_phase)"
  CURRENT_HASH="$(mcl_state_get spec_hash)"
  SPEC_APPROVED="$(mcl_state_get spec_approved)"
  PARTIAL_NOW="$(mcl_state_get partial_spec 2>/dev/null)"
  if [ "$PARTIAL_NOW" = "true" ]; then
    mcl_audit_log "askq-ignored-partial-spec" "stop" "phase=${CURRENT_PHASE}"
    mcl_debug_log "stop" "askq-ignored-partial-spec" "phase=${CURRENT_PHASE}"
  elif ! _mcl_is_approve_option "$ASKQ_SELECTED"; then
    mcl_audit_log "askq-non-approve" "stop" "phase=${CURRENT_PHASE} selected=${ASKQ_SELECTED}"
    mcl_debug_log "stop" "askq-non-approve" "phase=${CURRENT_PHASE} selected=${ASKQ_SELECTED}"
  elif [ "$SPEC_APPROVED" = "true" ] || [ "$CURRENT_PHASE" -ge 4 ] 2>/dev/null; then
    mcl_debug_log "stop" "askq-idempotent" "phase=${CURRENT_PHASE} approved=${SPEC_APPROVED}"
  elif [ -z "$CURRENT_HASH" ]; then
    mcl_audit_log "askq-ignored-no-spec" "stop" "phase=${CURRENT_PHASE}"
    mcl_debug_log "stop" "askq-ignored-no-spec" "phase=${CURRENT_PHASE}"
  elif [ "$CURRENT_PHASE" = "2" ] || [ "$CURRENT_PHASE" = "3" ]; then
    mcl_state_set spec_approved true
    mcl_state_set current_phase 4
    mcl_state_set phase_name '"EXECUTE"'
    UI_FLOW_ON="$(mcl_state_get ui_flow_active 2>/dev/null)"
    # Spec-body UI intent detection (since 6.5.4). Bootstrap / scaffold
    # sessions have no file-system UI signals at session start, so the
    # activate-hook heuristic sets ui_flow_active=false. If the approved
    # spec body contains strong UI-framework markers (Next.js, React,
    # TSX, Tailwind, shadcn, components/ui, etc.), we flip the flag here
    # so Phase 4a BUILD_UI engages and mcl-pre-tool.sh path-exception
    # locks backend paths until the developer reviews the UI.
    SPEC_INTENT_SCANNER="$_MCL_HOOK_DIR/lib/mcl-spec-ui-intent.py"
    if [ "$UI_FLOW_ON" != "true" ] && [ -f "$SPEC_INTENT_SCANNER" ] && command -v python3 >/dev/null 2>&1; then
      UI_INTENT="$(python3 "$SPEC_INTENT_SCANNER" "$TRANSCRIPT_PATH" 2>/dev/null)"
      if [ "$UI_INTENT" = "true" ]; then
        mcl_state_set ui_flow_active true
        UI_FLOW_ON="true"
        mcl_audit_log "ui-flow-spec-intent" "stop" "hash=${CURRENT_HASH:0:12}"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append ui_flow_spec_intent "${CURRENT_HASH:0:12}"
      fi
    fi
    # If UI flow is on (from Phase 1 heuristic OR spec-intent scan above),
    # enter BUILD_UI sub-phase. Otherwise stay in the classic phase-4 path.
    if [ "$UI_FLOW_ON" = "true" ]; then
      mcl_state_set ui_sub_phase '"BUILD_UI"'
      mcl_audit_log "ui-flow-enter-build" "stop" "hash=${CURRENT_HASH:0:12}"
    fi
    mcl_audit_log "approve-via-askuserquestion" "stop" "hash=${CURRENT_HASH:0:12} phase=${CURRENT_PHASE}->4 ui_flow=${UI_FLOW_ON}"
    mcl_debug_log "stop" "approve-via-askuserquestion" "hash=${CURRENT_HASH:0:12} phase=${CURRENT_PHASE}->4"
    command -v mcl_trace_append >/dev/null 2>&1 && {
      mcl_trace_append spec_approved "${CURRENT_HASH:0:12}"
      mcl_trace_append phase_transition "$CURRENT_PHASE" 4
      [ "$UI_FLOW_ON" = "true" ] && mcl_trace_append ui_flow_enabled
    }
    command -v mcl_log_append >/dev/null 2>&1 && mcl_log_append "Spec onaylandı. Faz ${CURRENT_PHASE} → 4 geçişi."
    bash "$_MCL_HOOK_DIR/lib/mcl-spec-save.sh" "$TRANSCRIPT_PATH" "$CURRENT_HASH" 2>/dev/null || true
    # Rollback checkpoint — record HEAD SHA before any Phase 4 writes.
    # Stored once; never overwritten on subsequent turns in the same session.
    _ROLLBACK_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
    if [ -n "$_ROLLBACK_SHA" ]; then
      mcl_state_set rollback_sha "\"${_ROLLBACK_SHA}\"" >/dev/null 2>&1 || true
      mcl_audit_log "rollback-checkpoint" "stop" "sha=${_ROLLBACK_SHA:0:12}"
      command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append rollback_checkpoint "${_ROLLBACK_SHA:0:12}"
    fi
    # Scope Guard — extract file-path tokens from the spec body and store
    # in state.scope_paths so mcl-pre-tool.sh can block Phase 4 writes
    # that land outside the declared scope. Empty array = no restriction.
    _SCOPE_PATHS_LIB="$_MCL_HOOK_DIR/lib/mcl-spec-paths.py"
    if [ -f "$_SCOPE_PATHS_LIB" ] && command -v python3 >/dev/null 2>&1; then
      _SCOPE_JSON="$(python3 - "$TRANSCRIPT_PATH" "$_SCOPE_PATHS_LIB" 2>/dev/null << 'PYEXTRACT'
import json, re, sys, subprocess

transcript_path, paths_lib = sys.argv[1], sys.argv[2]
spec_line_re = re.compile(
    r'^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?\U0001F4CB[ \t]+Spec:', re.MULTILINE)

spec_body = ''
try:
    with open(transcript_path, encoding='utf-8', errors='replace') as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
            except Exception:
                continue
            msg = obj if 'role' in obj else obj.get('message', obj)
            if not isinstance(msg, dict) or msg.get('role') != 'assistant':
                continue
            content = msg.get('content', '')
            text = ''
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                text = '\n'.join(
                    item.get('text', '')
                    for item in content
                    if isinstance(item, dict) and item.get('type') == 'text'
                )
            if spec_line_re.search(text):
                spec_body = text  # keep last spec-bearing turn
except Exception:
    pass

if not spec_body:
    print('[]')
    sys.exit(0)

r = subprocess.run(['python3', paths_lib], input=spec_body.encode(),
                   capture_output=True, timeout=10)
result = r.stdout.decode().strip()
try:
    parsed = json.loads(result)
    print(json.dumps(parsed) if isinstance(parsed, list) else '[]')
except Exception:
    print('[]')
PYEXTRACT
      )"
      _SCOPE_VALID="$(printf '%s' "${_SCOPE_JSON:-[]}" | python3 -c \
        'import json,sys; a=json.loads(sys.stdin.read()); print(json.dumps(a)) if isinstance(a,list) else print("[]")' \
        2>/dev/null || echo '[]')"
      mcl_state_set scope_paths "${_SCOPE_VALID}" >/dev/null 2>&1 || true
      _SCOPE_COUNT="$(printf '%s' "$_SCOPE_VALID" | python3 -c \
        'import json,sys; print(len(json.loads(sys.stdin.read())))' 2>/dev/null || echo 0)"
      mcl_audit_log "scope-paths-set" "stop" "count=${_SCOPE_COUNT} hash=${CURRENT_HASH:0:12}"
      command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append scope_guard_init "${_SCOPE_COUNT}"
    fi
    # Pattern Matching — Phase 3.5. Find existing sibling files for the
    # declared scope so Claude reads them BEFORE writing Phase 4 code.
    # pattern_scan_due=true blocks writes in pre-tool until first Phase 4
    # turn completes (stop hook clears it below).
    _PATSCAN_LIB="$_MCL_HOOK_DIR/lib/mcl-pattern-scan.py"
    if [ -f "$_PATSCAN_LIB" ] && command -v python3 >/dev/null 2>&1; then
      _PAT_FILES="$(printf '%s' "${_SCOPE_VALID:-[]}" \
        | python3 "$_PATSCAN_LIB" "$(pwd)" 2>/dev/null || echo '[]')"
      _PAT_VALID="$(printf '%s' "${_PAT_FILES:-[]}" | python3 -c \
        'import json,sys; a=json.loads(sys.stdin.read()); print(json.dumps(a)) if isinstance(a,list) else print("[]")' \
        2>/dev/null || echo '[]')"
      _PAT_COUNT="$(printf '%s' "$_PAT_VALID" | python3 -c \
        'import json,sys; print(len(json.loads(sys.stdin.read())))' 2>/dev/null || echo 0)"
      mcl_state_set pattern_files "${_PAT_VALID}" >/dev/null 2>&1 || true
      if [ "$_PAT_COUNT" -gt 0 ] 2>/dev/null; then
        mcl_state_set pattern_scan_due true >/dev/null 2>&1 || true
        mcl_audit_log "pattern-scan-pending" "stop" "count=${_PAT_COUNT} hash=${CURRENT_HASH:0:12}"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append pattern_scan_pending "${_PAT_COUNT}"
      else
        mcl_state_set pattern_scan_due false >/dev/null 2>&1 || true
      fi
    fi
  else
    mcl_debug_log "stop" "askq-ignored-wrong-phase" "phase=${CURRENT_PHASE}"
  fi
fi

# --- Phase 1 summary-confirm ---
# Since 6.5.2 ui_flow_active is owned by mcl-activate.sh (stack
# heuristic). The summary-confirm askq is a plain 3-option form
# (approve / edit / cancel) with NO UI opt-out. This branch only
# logs the approve/non-approve decision for auditability.
if [ "$ASKQ_INTENT" = "summary-confirm" ]; then
  if _mcl_is_approve_option "$ASKQ_SELECTED"; then
    mcl_audit_log "summary-confirm-approve" "stop" "selected=${ASKQ_SELECTED}"
    mcl_debug_log "stop" "summary-confirm-approve" "selected=${ASKQ_SELECTED}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append summary_confirmed approved
  else
    mcl_debug_log "stop" "summary-confirm-non-approve" "selected=${ASKQ_SELECTED}"
  fi
fi

# --- Phase 4b ui-review dispatch ---
# Emitted when the developer selects an option on the UI review askq.
# - approve-family: advance ui_sub_phase to BACKEND, unlock backend paths
# - vision-request: noop here. The skill tells Claude to run the
#   visual-inspect pipeline in its next turn by reading the transcript.
#   No persistent flag needed.
# - revise or cancel: noop. Free-text feedback is handled inline by
#   Claude on the next turn.
if [ "$ASKQ_INTENT" = "ui-review" ]; then
  UI_FLOW_ON="$(mcl_state_get ui_flow_active 2>/dev/null)"
  UI_SUB_NOW="$(mcl_state_get ui_sub_phase 2>/dev/null)"
  if [ "$UI_FLOW_ON" != "true" ]; then
    mcl_audit_log "ui-review-stray" "stop" "ui_flow=${UI_FLOW_ON} sub=${UI_SUB_NOW}"
    mcl_debug_log "stop" "ui-review-stray" "ui_flow=${UI_FLOW_ON} sub=${UI_SUB_NOW}"
  elif _mcl_is_approve_option "$ASKQ_SELECTED"; then
    mcl_state_set ui_reviewed true
    mcl_state_set ui_sub_phase '"BACKEND"'
    mcl_audit_log "approve-ui-review-via-askuserquestion" "stop" "sub=${UI_SUB_NOW}->BACKEND"
    mcl_debug_log "stop" "ui-review-approve" "sub=${UI_SUB_NOW}->BACKEND"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append ui_review_approved
  elif _mcl_is_vision_request_option "$ASKQ_SELECTED"; then
    mcl_audit_log "ui-review-vision-request" "stop" "selected=${ASKQ_SELECTED}"
    mcl_debug_log "stop" "ui-review-vision-request" "selected=${ASKQ_SELECTED}"
  else
    mcl_audit_log "ui-review-noop" "stop" "selected=${ASKQ_SELECTED}"
    mcl_debug_log "stop" "ui-review-noop" "selected=${ASKQ_SELECTED}"
  fi
fi

# --- Phase 3.5 pattern-scan clearance (late fallback for code-write turns) ---
# Handles the case where pattern_scan_due=true but a Write call happened in the
# same turn — the early block above ran, so this is now a no-op guard.
_PS_DUE="$(mcl_state_get pattern_scan_due 2>/dev/null)"
_PS_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
if [ "$_PS_DUE" = "true" ] && [ "$_PS_PHASE" = "4" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  _PS_SUMMARY="$(python3 - "$TRANSCRIPT_PATH" << 'PYPS'
import json, re, sys

path = sys.argv[1]
HEADING_RE = re.compile(
    r'\*\*Naming Convention:\*\*\s*(.+?)(?:\n|$)'
    r'.*?'
    r'\*\*Error Handling Pattern:\*\*\s*(.+?)(?:\n|$)'
    r'.*?'
    r'\*\*Test Pattern:\*\*\s*(.+?)(?:\n|$)',
    re.DOTALL
)

last_text = ''
try:
    with open(path, encoding='utf-8', errors='replace') as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
            except Exception:
                continue
            msg = obj if 'role' in obj else obj.get('message', obj)
            if not isinstance(msg, dict) or msg.get('role') != 'assistant':
                continue
            content = msg.get('content', '')
            text = ''
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                text = '\n'.join(
                    item.get('text', '')
                    for item in content
                    if isinstance(item, dict) and item.get('type') == 'text'
                )
            if text.strip():
                last_text = text
except Exception:
    pass

m = HEADING_RE.search(last_text)
if m:
    naming = m.group(1).strip()
    error  = m.group(2).strip()
    test   = m.group(3).strip()
    print(json.dumps({"naming": naming, "error": error, "test": test}))
else:
    print('null')
PYPS
  2>/dev/null)"
  if [ -n "$_PS_SUMMARY" ] && [ "$_PS_SUMMARY" != "null" ]; then
    mcl_state_set pattern_summary "$_PS_SUMMARY" >/dev/null 2>&1 || true
    mcl_audit_log "pattern-summary-stored" "stop" ""
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append pattern_summary_stored
  fi
  mcl_state_set pattern_scan_due false >/dev/null 2>&1 || true
  mcl_audit_log "pattern-scan-cleared" "stop" ""
  command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append pattern_scan_cleared
fi

# --- Session log: turn summary with actual token counts (since 6.5.7) ---
_STOP_LOG_LIB="$_MCL_HOOK_DIR/lib/mcl-log-append.sh"
_STOP_TURN_SCRIPT="$_MCL_HOOK_DIR/lib/mcl-log-turn.py"
if [ -f "$_STOP_LOG_LIB" ] && [ -f "$_STOP_TURN_SCRIPT" ] \
   && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] \
   && command -v python3 >/dev/null 2>&1; then
  source "$_STOP_LOG_LIB"
  TURN_MSG="$(python3 "$_STOP_TURN_SCRIPT" "$TRANSCRIPT_PATH" 2>/dev/null)"
  [ -n "$TURN_MSG" ] && mcl_log_append "$TURN_MSG"
fi

exit 0
