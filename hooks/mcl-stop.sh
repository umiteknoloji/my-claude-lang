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
python3 - "$_HH_FILE" "stop" "$(date +%s)" 2>/dev/null <<'PYEOF' || true
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

# Session-context bridge (since 8.2.11) — writes .mcl/session-context.md on
# every exit (trap EXIT) so the next session's mcl-activate.sh can resume
# with active phase, last commit, next step, and any half-finished work.
# Trap-based so the file lands even when stop returns decision:block early.
_mcl_session_context_write() {
  command -v python3 >/dev/null 2>&1 || return 0
  [ -f "${MCL_STATE_FILE:-}" ] || return 0
  local sc_file proj_dir git_sha git_msg
  sc_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/session-context.md"
  proj_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  git_sha="$(cd "$proj_dir" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || true)"
  git_msg="$(cd "$proj_dir" 2>/dev/null && git log -1 --pretty=%s 2>/dev/null || true)"
  python3 - "$sc_file" "$MCL_STATE_FILE" "$git_sha" "$git_msg" "$proj_dir" 2>/dev/null <<'PYEOF' || true
import json, os, sys, glob
sc_path, state_path, git_sha, git_msg, project_dir = sys.argv[1:6]
try:
    state = json.load(open(state_path, "r", encoding="utf-8"))
except Exception:
    sys.exit(0)
phase = state.get("current_phase") or 1
phase_name = state.get("phase_name") or ""
spec_hash = (state.get("spec_hash") or "")[:8]
spec_approved = state.get("spec_approved") is True
risk_review_state = state.get("risk_review_state") or ""
pattern_scan_due = state.get("pattern_scan_due") is True
plan_critique_done = state.get("plan_critique_done") is True
plan_files = []
try:
    plan_files = sorted(glob.glob(os.path.join(project_dir, ".claude", "plans", "*.md")))
except Exception:
    pass
if spec_hash:
    active = f"Phase {phase} ({phase_name}) — spec {spec_hash}"
else:
    active = f"Phase {phase} ({phase_name})"
def resolve_next():
    if risk_review_state == "pending":
        return "Aşama 8 risk review başlat"
    if risk_review_state == "running":
        return "Aşama 8/10 dialog'u devam ettir"
    if pattern_scan_due:
        return "Aşama 5 pattern scan"
    if plan_files and not plan_critique_done:
        return "Plan critique subagent çalıştır (Sonnet 4.6)"
    if phase == 1:
        return "Aşama 1 parametre toplama"
    if phase in (2, 3) and not spec_approved:
        return "Spec onayı bekleniyor"
    if phase >= 4 and spec_approved:
        return "Aşama 7 execute (kod yazımı)"
    return "Belirsiz — state'e bak"
next_step = resolve_next()
lines = [
    "# MCL Session Context (auto-generated)",
    "",
    f"**Aktif iş:** {active}",
]
if git_sha:
    msg = (git_msg or "").strip()
    if len(msg) > 60:
        msg = msg[:60] + "…"
    lines.append(f"**Son commit:** {git_sha} — {msg}" if msg else f"**Son commit:** {git_sha}")
lines.append(f"**Sıradaki adım:** {next_step}")
if plan_files and not plan_critique_done:
    lines.append(f"**Yarım plan:** {os.path.relpath(plan_files[0], project_dir)} — critique pending")
elif risk_review_state == "pending":
    lines.append("**Yarım iş:** Aşama 8 başlatılmadı")
body = "\n".join(lines) + "\n"
tmp = sc_path + ".tmp"
try:
    os.makedirs(os.path.dirname(sc_path), exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(body)
    os.replace(tmp, sc_path)
except Exception:
    try: os.unlink(tmp)
    except Exception: pass
PYEOF
}
trap _mcl_session_context_write EXIT

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

spec_line_re = re.compile(r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?\U0001F4CB[ \t]+Spec\b[^\n:]*:", re.MULTILINE)

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
#   spec-approve      — Aşama 4 spec approval
#   summary-confirm   — Aşama 1 summary confirmation (audit-only here)
#   ui-review         — Aşama 6b UI review approval
#   other             — recognized MCL question but not state-transitioning
ASKQ_SCANNER="$_MCL_HOOK_DIR/lib/mcl-askq-scanner.py"
if [ -f "$ASKQ_SCANNER" ] && command -v python3 >/dev/null 2>&1; then
  # Pass restart_turn_ts (since 8.2.13) so pre-restart askq's are filtered
  # out — same defense applied here as in pre-tool's JIT scanner call.
  ASKQ_RESTART_TS="$(mcl_state_get restart_turn_ts 2>/dev/null)"
  ASKQ_JSON="$(python3 "$ASKQ_SCANNER" "$TRANSCRIPT_PATH" "$ASKQ_RESTART_TS" 2>/dev/null)"
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
# was detected AND current_phase=4 AND spec_hash is set, scan the most
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

# Helper: does the selected option on the Aşama 6b ui-review askq ask
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

# --- Aşama 8 / 4.6 / 5 review enforcement (since 7.1.3) ---
#
# Core invariant: after Aşama 7 code is written, Claude MUST run Aşama 8
# Risk Review, Aşama 10 Impact Review, and Aşama 11 Verification Report before
# the session can end. This is enforced via `decision: block` — Claude Code
# refuses to close the turn until Claude starts Aşama 8.
#
# State machine (stored in risk_review_state):
#   null / absent — Aşama 7 hasn't written code yet (no enforcement needed)
#   "pending"     — code was written, Aşama 8 not yet started → BLOCK
#   "running"     — Aşama 8/10 dialog is in progress → allow through
#
# Transitions:
#   code_written=true AND askuq=false         → pending  (block)
#   code_written=true AND askuq=true          → running  (Aşama 8 fix + next-risk)
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
  _PR_ACTIVE_PHASE="$(mcl_get_active_phase 2>/dev/null)"
  _PR_REVIEW_STATE="$(mcl_state_get risk_review_state 2>/dev/null)"

  # Aşama 7+ means approved and executing (4, 4a, 4b, 4c, 4.5, 3.5 all qualify)
  if echo "$_PR_ACTIVE_PHASE" | grep -qE '^(4|4a|4b|4c|3\.5)$'; then
    _PR_JSON="$(python3 "$_PR_GUARD" "$TRANSCRIPT_PATH" 2>/dev/null)"
    _PR_CODE="$(printf '%s' "$_PR_JSON" | python3 -c \
      'import json,sys; d=json.loads(sys.stdin.read()); print("true" if d.get("code_written") else "false")' 2>/dev/null)"
    _PR_ASKUQ="$(printf '%s' "$_PR_JSON" | python3 -c \
      'import json,sys; d=json.loads(sys.stdin.read()); print("true" if d.get("askuq_present") else "false")' 2>/dev/null)"

    if [ "$_PR_ASKUQ" = "true" ]; then
      # Aşama 8/10 dialog is running this turn — transition to "running"
      # regardless of whether code was also written (risk-fix + next-risk turn).
      if [ "$_PR_REVIEW_STATE" != "running" ]; then
        mcl_state_set risk_review_state '"running"' >/dev/null 2>&1 || true
        mcl_audit_log "phase-review-running" "stop" "prev=${_PR_REVIEW_STATE}"
        command -v mcl_trace_append >/dev/null 2>&1 && \
          mcl_trace_append risk_review_running "${_PR_REVIEW_STATE:-null}"
      fi
    elif [ "$_PR_CODE" = "true" ] || [ "$_PR_REVIEW_STATE" = "pending" ]; then
      # Code written this turn, OR pending state persists from a prior turn
      # (sticky enforcement — Bash-only/text-only turns cannot escape the gate).
      mcl_state_set risk_review_state '"pending"' >/dev/null 2>&1 || true
      mcl_audit_log "phase-review-pending" "stop" \
        "prev=${_PR_REVIEW_STATE} phase=${_PR_PHASE} code=${_PR_CODE}"
      command -v mcl_trace_append >/dev/null 2>&1 && \
        mcl_trace_append risk_review_pending "${_PR_REVIEW_STATE:-null}"

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
  \"reason\": \"⚠️ MCL PHASE REVIEW ENFORCEMENT (mandatory, non-skippable)\n\nAşama 7 code was written but Aşama 8 Risk Review has NOT been started. You have two valid responses:\n\n(A) IF Aşama 6c BACKEND is NOT yet fully complete:\n    Continue writing the remaining code. State explicitly which files still need to be written. The enforcement block will repeat on each code-write turn until Aşama 8 starts.\n\n(B) IF ALL Aşama 7 code is NOW complete:\n    Start Aşama 8 Risk Review IMMEDIATELY in this response. Do NOT delay, do NOT summarize what you built, do NOT ask the developer a question unrelated to risks. Begin Aşama 8 now:\n    1. Review the code you just wrote for: security vulnerabilities (injection, auth bypass, XSS, CSRF, insecure defaults), performance bottlenecks (N+1, unbounded queries, missing indexes), edge cases (null/empty/overflow inputs), data integrity issues (missing transactions, inconsistent state), race conditions, regression surfaces.\n    2. Present ONE risk at a time via AskUserQuestion with prefix MCL ${INSTALLED_VERSION} |\n    3. After ALL Aşama 8 risks are resolved → run Aşama 10 Impact Review.\n    4. After Aşama 10 → run Aşama 11 Verification Report.\n\nAşama 8 → 4.6 → 5 are MANDATORY. Skipping them violates the MCL contract.\"
}"
      exit 0
    fi
  fi
fi

# --- Aşama 11 skip detection (since 8.2.7) ---
# When risk_review_state="running" persists at stop AND no MCL-prefixed
# AskUserQuestion ran this turn (ASKQ_INTENT empty), the Aşama 8/10 dialog
# has ended but Aşama 11 Verification Report did not clear the state — Aşama 11
# was skipped. Audit-only (non-blocking); mcl-activate.sh injects the warn
# next turn as PHASE5_SKIP_NOTICE. Detection is state-driven (no transcript
# scan) so abnormal session exits still surface the skip.
_PR_FINAL_STATE="$(mcl_state_get risk_review_state 2>/dev/null)"
if [ "$_PR_FINAL_STATE" = "running" ] && [ -z "$ASKQ_INTENT" ]; then
  mcl_audit_log "phase5-skipped-warn" "mcl-stop.sh" "risk_review_state=running"
  command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase5_skipped_warn
fi

# --- Root Cause Chain keyword scan after ExitPlanMode (since 8.2.8 — Gap 2) ---
# When the last assistant turn used ExitPlanMode, scan its text + tool inputs
# for the 3-check chain keywords. Pairs (EN OR TR per pair, case-insensitive):
#   removal test / kaldırma testi
#   falsification / yanlışlama
#   visible process / görünür süreç
# If any pair has neither EN nor TR → audit `root-cause-chain-skipped-warn`.
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && command -v python3 >/dev/null 2>&1; then
  _RCC_RESULT="$(python3 - "$TRANSCRIPT_PATH" 2>/dev/null <<'PYEOF'
import json, sys

path = sys.argv[1]
last_text = []
last_tools = []
last_inputs = []

try:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
            except Exception:
                continue
            msg = obj.get("message") or obj
            if not isinstance(msg, dict) or msg.get("role") != "assistant":
                continue
            content = msg.get("content")
            text_parts, tool_inputs, tool_names = [], [], []
            if isinstance(content, str):
                text_parts.append(content)
            elif isinstance(content, list):
                for item in content:
                    if not isinstance(item, dict):
                        continue
                    t = item.get("type")
                    if t == "text":
                        v = item.get("text", "")
                        if isinstance(v, str):
                            text_parts.append(v)
                    elif t == "tool_use":
                        tool_names.append(item.get("name", ""))
                        inp = item.get("input", {})
                        if isinstance(inp, dict):
                            for v in inp.values():
                                if isinstance(v, str):
                                    tool_inputs.append(v)
            last_text, last_tools, last_inputs = text_parts, tool_names, tool_inputs
except Exception:
    pass

if "ExitPlanMode" not in last_tools:
    print("")
    sys.exit(0)

haystack = "\n".join(last_text + last_inputs).lower()
pairs = [
    ("removal test",   "kaldırma testi"),
    ("falsification",  "yanlışlama"),
    ("visible process","görünür süreç"),
]
missing = [en for en, tr in pairs if (en not in haystack and tr not in haystack)]
print(",".join(missing) if missing else "OK")
PYEOF
)"
  if [ -n "$_RCC_RESULT" ] && [ "$_RCC_RESULT" != "OK" ]; then
    mcl_audit_log "root-cause-chain-skipped-warn" "mcl-stop.sh" "missing=$_RCC_RESULT"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append root_cause_chain_skipped_warn "$_RCC_RESULT"
  fi
fi

# --- Root Cause Chain all-mode keyword scan (since 8.2.9 — Gap 2 expansion) ---
# Runs every turn, not only after ExitPlanMode. When the LAST USER message
# contains a problem/anomaly trigger keyword (14-lang heuristic) AND the LAST
# ASSISTANT text + tool inputs are missing any of the 3 keyword pairs, audit
# `root-cause-chain-skipped-warn` with `source=all-mode`. Coexists with the
# block above — both can fire on the same turn; auto-display reads only the
# event name so duplicate audit entries don't change visible behavior.
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && command -v python3 >/dev/null 2>&1; then
  _RCC_ALLMODE_RESULT="$(python3 - "$TRANSCRIPT_PATH" 2>/dev/null <<'PYEOF'
import json, sys

path = sys.argv[1]

trigger_words = {
    # TR
    "neden", "niye", "bug", "çalışmıyor", "hata", "sorun", "kırıldı",
    # EN
    "why", "broken", "error", "fail", "issue", "wrong",
    # ES
    "por qué", "falla", "roto", "problema",
    # FR
    "pourquoi", "erreur", "bogue", "cassé", "problème",
    # DE
    "warum", "fehler", "kaputt", "problem",
    # JA
    "なぜ", "バグ", "エラー", "壊れ", "問題",
    # KO
    "왜", "버그", "오류", "깨졌", "문제",
    # ZH
    "为什么", "错误", "崩溃", "问题", "故障",
    # AR
    "لماذا", "خطأ", "عطل", "مشكلة",
    # HE
    "למה", "שגיאה", "תקלה", "בעיה",
    # HI
    "क्यों", "गलती", "समस्या", "टूट",
    # ID
    "kenapa", "mengapa", "rusak", "masalah",
    # PT
    "por que", "erro", "quebrado",
    # RU
    "почему", "ошибка", "сбой", "проблема", "сломан",
}

last_user_text = ""
last_assistant_text = []
last_assistant_inputs = []

try:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
            except Exception:
                continue
            msg = obj.get("message") or obj
            if not isinstance(msg, dict):
                continue
            role = msg.get("role")
            content = msg.get("content")
            if role == "user":
                if isinstance(content, str):
                    last_user_text = content
                elif isinstance(content, list):
                    parts = [b.get("text", "") for b in content
                             if isinstance(b, dict) and b.get("type") == "text"]
                    last_user_text = " ".join(parts)
            elif role == "assistant":
                text_parts, tool_inputs = [], []
                if isinstance(content, str):
                    text_parts.append(content)
                elif isinstance(content, list):
                    for item in content:
                        if not isinstance(item, dict):
                            continue
                        t = item.get("type")
                        if t == "text":
                            v = item.get("text", "")
                            if isinstance(v, str):
                                text_parts.append(v)
                        elif t == "tool_use":
                            inp = item.get("input", {})
                            if isinstance(inp, dict):
                                for v in inp.values():
                                    if isinstance(v, str):
                                        tool_inputs.append(v)
                last_assistant_text, last_assistant_inputs = text_parts, tool_inputs
except Exception:
    pass

user_lower = last_user_text.lower()
if not any(kw in user_lower for kw in trigger_words):
    print("")
    sys.exit(0)

haystack = "\n".join(last_assistant_text + last_assistant_inputs).lower()
pairs = [
    ("removal test",   "kaldırma testi"),
    ("falsification",  "yanlışlama"),
    ("visible process","görünür süreç"),
]
missing = [en for en, tr in pairs if (en not in haystack and tr not in haystack)]
print(",".join(missing) if missing else "OK")
PYEOF
)"
  if [ -n "$_RCC_ALLMODE_RESULT" ] && [ "$_RCC_ALLMODE_RESULT" != "OK" ]; then
    mcl_audit_log "root-cause-chain-skipped-warn" "mcl-stop.sh" "source=all-mode missing=$_RCC_ALLMODE_RESULT"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append root_cause_chain_skipped_warn "all-mode:$_RCC_ALLMODE_RESULT"
  fi
fi

# --- Plan critique skip detection (since 8.2.10 — Gap 3 meta-control) ---
# When ExitPlanMode tool_use appears in the LAST assistant turn AND state
# `plan_critique_done` is still false at stop time, the pre-tool hook blocked
# the call (or should have) — record the skip attempt in audit. State-driven
# read; transcript scan only runs when state is false to avoid wasted I/O.
_PCS_DONE="$(mcl_state_get plan_critique_done 2>/dev/null)"
if [ "$_PCS_DONE" != "true" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] \
   && command -v python3 >/dev/null 2>&1; then
  _PCS_HIT="$(python3 - "$TRANSCRIPT_PATH" 2>/dev/null <<'PYEOF'
import json, sys
path = sys.argv[1]
last_tools = []
try:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
            except Exception:
                continue
            msg = obj.get("message") or obj
            if not isinstance(msg, dict) or msg.get("role") != "assistant":
                continue
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            tools = [item.get("name", "") for item in content
                     if isinstance(item, dict) and item.get("type") == "tool_use"]
            if tools:
                last_tools = tools
except Exception:
    pass
print("hit" if "ExitPlanMode" in last_tools else "")
PYEOF
)"
  if [ "$_PCS_HIT" = "hit" ]; then
    mcl_audit_log "plan-critique-skipped-warn" "mcl-stop.sh" "tool=ExitPlanMode plan_critique_done=false"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append plan_critique_skipped_warn
  fi
fi

# --- Aşama 5 pattern-scan clearance (runs before early exit) ---
# Must run before the spec/askq gate below because the Aşama 5 turn has
# no spec block and no AskUQ — the early exit would skip this otherwise.
_PS_DUE_EARLY="$(mcl_state_get pattern_scan_due 2>/dev/null)"
_PS_ACTIVE_PHASE_EARLY="$(mcl_get_active_phase 2>/dev/null)"
if [ "$_PS_DUE_EARLY" = "true" ] && echo "$_PS_ACTIVE_PHASE_EARLY" | grep -qE '^(4|4a|4b|4c|3\.5)$' \
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
      # --- Aşama 2 precision-audit skip detection (since 8.3.0) ---
      # Aşama 1 → 2 transition: Aşama 2 should have emitted a precision-audit
      # entry before the spec block was written. Scan audit.log for the entry,
      # scoped to current session via last `session_start` in trace.log. If
      # missing → write `precision-audit-skipped-warn`. Audit-only, non-blocking.
      _PA_AUDIT_FILE="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
      _PA_TRACE_FILE="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
      if [ -f "$_PA_AUDIT_FILE" ] && command -v python3 >/dev/null 2>&1; then
        _PA_HIT="$(python3 - "$_PA_AUDIT_FILE" "$_PA_TRACE_FILE" 2>/dev/null <<'PYEOF'
import os, sys
audit_path, trace_path = sys.argv[1], sys.argv[2]
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
hit = False
try:
    with open(audit_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if "| precision-audit |" not in line:
                continue
            ts = line.split("|", 1)[0].strip()
            if not session_ts or ts >= session_ts:
                hit = True
                break
except Exception:
    pass
print("hit" if hit else "")
PYEOF
)"
        if [ "$_PA_HIT" != "hit" ]; then
          # Backward-compat: 8.3.0 skip-detection signal still emitted.
          mcl_audit_log "precision-audit-skipped-warn" "mcl-stop.sh" "summary-confirmed-but-no-audit"
          command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append precision_audit_skipped_warn

          # 8.3.2: hard block — Aşama 8-tier enforcement. State stays
          # at phase=1; the spec is treated as not-yet-final; Claude must
          # complete Aşama 2 in this same response before re-emitting
          # the precision-enriched spec. English-language sessions emit
          # `precision-audit | ... skipped=true` (handled in skill file)
          # which counts as `hit` above and bypasses this block — the
          # implicit safety valve for English source.
          mcl_audit_log "precision-audit-block" "mcl-stop.sh" "summary-confirmed-but-no-audit; transition-rewind"
          command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append precision_audit_block
          printf '%s\n' "{
  \"decision\": \"block\",
  \"reason\": \"⚠️ MCL PHASE 1.7 PRECISION AUDIT ENFORCEMENT (mandatory, non-skippable)\n\nA Aşama 4 spec block was emitted but Aşama 2 Precision Audit has NOT been run. The Aşama 1→2 transition is blocked. In this SAME response, before the turn closes:\n\n1. Read ~/.claude/skills/my-claude-lang/asama2-precision-audit.md for the dimension list and classification rules.\n2. Walk the 7 core dimensions (permission/access, algorithmic failure modes, out-of-scope boundaries, PII handling, audit/observability, performance SLA, idempotency/retry) plus any matching stack add-ons returned by: bash ~/.claude/hooks/lib/mcl-stack-detect.sh detect \\\"\$(pwd)\\\"\n3. Classify each dimension: SILENT-ASSUME (mark [assumed: X]), SKIP-MARK (mark [unspecified: X] — currently only Performance SLA), or GATE (architectural impact → ask one question via AskUserQuestion).\n4. Emit the audit entry via: bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log precision-audit phase1-7 \\\"core_gates=N stack_gates=M assumes=K skipmarks=L stack_tags=<tags> skipped=false\\\"' (substitute counts and tags).\n5. Re-emit the spec block with precision-enriched parameters. The prior spec is discarded — replaced, not duplicated.\n\nIf detected language is English, emit the audit with skipped=true (Aşama 1 already in English; behavioral prior assumed sufficient) and the block clears immediately on the next turn.\n\nRecovery: if you believe this block fired in error (e.g., audit emit failed silently), type /mcl-restart to clear phase state.\"
}"
          exit 0
        fi
      fi

      mcl_state_set current_phase 4
      mcl_state_set phase_name '"SPEC_REVIEW"'
      mcl_state_set spec_hash "\"$SPEC_HASH\""
      mcl_debug_log "stop" "transition-1-to-2" "hash=${SPEC_HASH:0:12}"
      command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition 1 4
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
  elif [ "$SPEC_APPROVED" = "true" ] || [ "$CURRENT_PHASE" -ge 7 ] 2>/dev/null; then
    mcl_debug_log "stop" "askq-idempotent" "phase=${CURRENT_PHASE} approved=${SPEC_APPROVED}"
  elif [ -z "$CURRENT_HASH" ]; then
    mcl_audit_log "askq-ignored-no-spec" "stop" "phase=${CURRENT_PHASE}"
    mcl_debug_log "stop" "askq-ignored-no-spec" "phase=${CURRENT_PHASE}"
  elif [ "$CURRENT_PHASE" = "4" ] || [ "$CURRENT_PHASE" = "3" ]; then
    mcl_state_set spec_approved true
    mcl_state_set current_phase 7
    mcl_state_set phase_name '"EXECUTE"'
    UI_FLOW_ON="$(mcl_state_get ui_flow_active 2>/dev/null)"
    # Spec-body UI intent detection (since 6.5.4). Bootstrap / scaffold
    # sessions have no file-system UI signals at session start, so the
    # activate-hook heuristic sets ui_flow_active=false. If the approved
    # spec body contains strong UI-framework markers (Next.js, React,
    # TSX, Tailwind, shadcn, components/ui, etc.), we flip the flag here
    # so Aşama 6a BUILD_UI engages and mcl-pre-tool.sh path-exception
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
    # If UI flow is on (from Aşama 1 heuristic OR spec-intent scan above),
    # enter BUILD_UI sub-phase. Otherwise stay in the classic phase-4 path.
    if [ "$UI_FLOW_ON" = "true" ]; then
      mcl_state_set ui_sub_phase '"BUILD_UI"'
      mcl_audit_log "ui-flow-enter-build" "stop" "hash=${CURRENT_HASH:0:12}"
    fi
    mcl_audit_log "approve-via-askuserquestion" "stop" "hash=${CURRENT_HASH:0:12} phase=${CURRENT_PHASE}->7 ui_flow=${UI_FLOW_ON}"
    mcl_debug_log "stop" "approve-via-askuserquestion" "hash=${CURRENT_HASH:0:12} phase=${CURRENT_PHASE}->7"
    command -v mcl_trace_append >/dev/null 2>&1 && {
      mcl_trace_append spec_approved "${CURRENT_HASH:0:12}"
      mcl_trace_append phase_transition "$CURRENT_PHASE" 7
      [ "$UI_FLOW_ON" = "true" ] && mcl_trace_append ui_flow_enabled
    }
    command -v mcl_log_append >/dev/null 2>&1 && mcl_log_append "Spec onaylandı. Faz ${CURRENT_PHASE} → 4 geçişi."
    bash "$_MCL_HOOK_DIR/lib/mcl-spec-save.sh" "$TRANSCRIPT_PATH" "$CURRENT_HASH" 2>/dev/null || true
    # Rollback checkpoint — record HEAD SHA before any Aşama 7 writes.
    # Stored once; never overwritten on subsequent turns in the same session.
    _ROLLBACK_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
    if [ -n "$_ROLLBACK_SHA" ]; then
      mcl_state_set rollback_sha "\"${_ROLLBACK_SHA}\"" >/dev/null 2>&1 || true
      mcl_audit_log "rollback-checkpoint" "stop" "sha=${_ROLLBACK_SHA:0:12}"
      command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append rollback_checkpoint "${_ROLLBACK_SHA:0:12}"
    fi
    # Scope Guard — extract file-path tokens from the spec body and store
    # in state.scope_paths so mcl-pre-tool.sh can block Aşama 7 writes
    # that land outside the declared scope. Empty array = no restriction.
    _SCOPE_PATHS_LIB="$_MCL_HOOK_DIR/lib/mcl-spec-paths.py"
    if [ -f "$_SCOPE_PATHS_LIB" ] && command -v python3 >/dev/null 2>&1; then
      _SCOPE_JSON="$(python3 - "$TRANSCRIPT_PATH" "$_SCOPE_PATHS_LIB" 2>/dev/null << 'PYEXTRACT'
import json, re, sys, subprocess

transcript_path, paths_lib = sys.argv[1], sys.argv[2]
spec_line_re = re.compile(
    r'^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?\U0001F4CB[ \t]+Spec\b[^\n:]*:', re.MULTILINE)

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
    # Pattern Matching — Aşama 5. Cascade: Level 1 (siblings) → Level 2
    # (project-wide recent) → Level 3 (ecosystem default) → Level 4 (ask user).
    # pattern_scan_due=true blocks writes in pre-tool until first Aşama 7
    # turn completes (stop hook clears it below).
    _PATSCAN_LIB="$_MCL_HOOK_DIR/lib/mcl-pattern-scan.py"
    if [ -f "$_PATSCAN_LIB" ] && command -v python3 >/dev/null 2>&1; then
      # Capture both stdout and exit code; stderr suppressed
      _PAT_FILES="$(printf '%s' "${_SCOPE_VALID:-[]}" \
        | python3 "$_PATSCAN_LIB" "$(pwd)" 2>/dev/null)"
      _PAT_EXIT=$?
      # exit 3 means "no files found at any project level — use ecosystem"
      if [ "$_PAT_EXIT" = "3" ]; then
        _PAT_FILES='[]'
      fi
      _PAT_VALID="$(printf '%s' "${_PAT_FILES:-[]}" | python3 -c \
        'import json,sys; a=json.loads(sys.stdin.read()); print(json.dumps(a)) if isinstance(a,list) else print("[]")' \
        2>/dev/null || echo '[]')"
      _PAT_COUNT="$(printf '%s' "$_PAT_VALID" | python3 -c \
        'import json,sys; print(len(json.loads(sys.stdin.read())))' 2>/dev/null || echo 0)"
      mcl_state_set pattern_files "${_PAT_VALID}" >/dev/null 2>&1 || true
      if [ "$_PAT_COUNT" -gt 0 ] 2>/dev/null; then
        # Level 1 or 2: real files found
        _PAT_LEVEL="$([ "$_PAT_EXIT" = "0" ] && echo 1 || echo 2)"
        mcl_state_set pattern_level "$_PAT_LEVEL" >/dev/null 2>&1 || true
        mcl_state_set pattern_scan_due true >/dev/null 2>&1 || true
        mcl_state_set pattern_ask_pending false >/dev/null 2>&1 || true
        mcl_audit_log "pattern-scan-pending" "stop" "level=${_PAT_LEVEL} count=${_PAT_COUNT} hash=${CURRENT_HASH:0:12}"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append pattern_scan_pending "${_PAT_COUNT}"
      elif [ "$_PAT_EXIT" = "3" ]; then
        # Level 3: no project files — determine ecosystem from scope_paths extension
        _ECO_EXT="$(printf '%s' "${_SCOPE_VALID:-[]}" | python3 -c '
import json,sys,os
paths = json.loads(sys.stdin.read())
exts = [os.path.splitext(p)[-1].lstrip(".").lower() for p in paths if p]
ts_like = {"ts","tsx","mts","cts"}
js_like = {"js","jsx","mjs","cjs"}
eco_map = {
  **{e: "typescript" for e in ts_like},
  **{e: "javascript" for e in js_like},
  "py": "python",
  "go": "go",
  "rs": "rust",
  "java": "java",
  "rb": "ruby",
  "php": "php",
  "cs": "csharp",
  "kt": "kotlin",
  "swift": "swift",
}
for e in exts:
  if e in eco_map:
    print(eco_map[e]); break
else:
  print("unknown")
' 2>/dev/null || echo 'unknown')"
        mcl_state_set pattern_level 3 >/dev/null 2>&1 || true
        mcl_state_set pattern_scan_due true >/dev/null 2>&1 || true
        mcl_state_set pattern_ask_pending false >/dev/null 2>&1 || true
        # Store ecosystem as a synthetic "file" signal for activate hook
        _ECO_JSON="$(printf '["%s-ecosystem-standard"]' "$_ECO_EXT")"
        mcl_state_set pattern_files "$_ECO_JSON" >/dev/null 2>&1 || true
        mcl_audit_log "pattern-scan-ecosystem" "stop" "ecosystem=${_ECO_EXT} hash=${CURRENT_HASH:0:12}"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append pattern_scan_ecosystem "$_ECO_EXT"
      else
        # No files and not exit 3 — fall to Level 4: ask user
        mcl_state_set pattern_level 4 >/dev/null 2>&1 || true
        mcl_state_set pattern_scan_due true >/dev/null 2>&1 || true
        mcl_state_set pattern_ask_pending true >/dev/null 2>&1 || true
        mcl_state_set pattern_files '[]' >/dev/null 2>&1 || true
        mcl_audit_log "pattern-scan-ask" "stop" "hash=${CURRENT_HASH:0:12}"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append pattern_scan_ask
      fi
    fi
  else
    mcl_debug_log "stop" "askq-ignored-wrong-phase" "phase=${CURRENT_PHASE}"
  fi
fi

# --- Aşama 1 summary-confirm ---
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

# --- Aşama 6b ui-review dispatch ---
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

# --- Aşama 5 pattern-scan clearance (late fallback for code-write turns) ---
# Handles the case where pattern_scan_due=true but a Write call happened in the
# same turn — the early block above ran, so this is now a no-op guard.
_PS_DUE="$(mcl_state_get pattern_scan_due 2>/dev/null)"
_PS_ACTIVE_PHASE="$(mcl_get_active_phase 2>/dev/null)"
if [ "$_PS_DUE" = "true" ] && echo "$_PS_ACTIVE_PHASE" | grep -qE '^(4|4a|4b|4c|3\.5)$' && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
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
