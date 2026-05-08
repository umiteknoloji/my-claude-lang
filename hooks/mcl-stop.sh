#!/bin/bash
_BT='`'  # literal backtick for embedding in double-quoted strings without command substitution
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

# Loop-breaker helper has moved to hooks/lib/mcl-state.sh (since
# v10.1.7) so both Stop and PreToolUse can use it. Lib version uses
# proper timestamp normalization (since v10.1.13) — handles both
# legacy local-tz space format AND ISO UTC format. The duplicate
# definition that used to live here has been removed; the lib's
# `_mcl_loop_breaker_count` is in scope via the `source` of
# mcl-state.sh near the top of this file.

# --- Aşama 4 spec-presence audit (since v10.0.4) ---
# Scan the latest assistant message: if it called Edit/Write/MultiEdit/
# NotebookEdit AND no preceding 📋 Spec: text appears in the same
# message, write `spec-required-warn` to audit. Stop hook timing is
# correct (turn complete = transcript flushed), unlike pre-tool which
# can't see in-progress message text.
_mcl_spec_presence_audit() {
  local transcript="${1:-}"
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$transcript" 2>/dev/null <<'PYEOF' || true
import json, re, sys
path = sys.argv[1]
SPEC_RE = re.compile(r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?\U0001F4CB[ \t]+Spec\b[^\n:]*:", re.MULTILINE)
EDIT_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
last_assistant_blocks = None
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
            if msg.get("role") == "assistant":
                content = msg.get("content")
                if isinstance(content, list):
                    last_assistant_blocks = content
except Exception:
    sys.exit(0)
if not last_assistant_blocks:
    sys.exit(0)
text_so_far = ""
edit_called = False
spec_seen_before_edit = False
for block in last_assistant_blocks:
    if not isinstance(block, dict):
        continue
    btype = block.get("type")
    if btype == "text":
        t = block.get("text") or ""
        if isinstance(t, str):
            text_so_far += "\n" + t
            if SPEC_RE.search(t) and not edit_called:
                spec_seen_before_edit = True
    elif btype == "tool_use":
        name = block.get("name") or ""
        if name in EDIT_TOOLS:
            edit_called = True
            # Once Edit fires, freeze spec_seen_before_edit
            break
print("warn" if (edit_called and not spec_seen_before_edit) else "ok")
PYEOF
}

# --- Aşama 6 server-without-browser strict check (v13.0.6, hardened v13.0.8) ---
# Aşama 6 spec (MCL_Pipeline.md): "Front-end dummy data ile yapılır. Proje ve
# tüm bağımlılıkları ayağa kaldırılır. Proje otomatik olarak tarayıcıda
# açılır." → 3 invariants:
#   (a) frontend code written
#   (b) server brought up
#   (c) browser auto-opened
# v13.0.6 only enforced (b)→(c). v13.0.8 enforces BOTH (b) AND (c) at stop:
#   - missing server-start → block "start server first"
#   - missing browser-open → block "open browser"
#   - both present → ok
# Scan SCOPE: session-wide (all assistant turns since session_start), not
# just last turn — accommodates multi-turn workflows (write code in turn 1,
# install deps in turn 2, start server + open browser in turn 3).
# Returns: "block:no-server" | "block:no-browser" | "block:neither" | "ok".
# STRICT: no loop-breaker — every stop in current_phase=6 with missing
# evidence triggers block until model emits both commands or `asama-6-end` /
# `asama-6-skipped` audit.
_mcl_asama_6_server_browser_check() {
  local transcript="${1:-}"
  [ -n "$transcript" ] && [ -f "$transcript" ] || { echo "ok"; return 0; }
  command -v python3 >/dev/null 2>&1 || { echo "ok"; return 0; }
  python3 - "$transcript" 2>/dev/null <<'PYEOF' || echo "ok"
import json, re, sys
path = sys.argv[1]
SERVER_RE = re.compile(
    r"(?:^|\s|;|&&|\|\|)("
    r"(?:npm|pnpm|yarn)\s+(?:run\s+)?(?:dev|start|serve)"
    r"|node\s+(?:[\w./\-]*/)?(?:server|index|app|dist|src|bin|backend|main)"
    r"|nodemon\s+"
    r"|deno\s+(?:run|task)"
    r"|bun\s+(?:run|dev|start)"
    r"|python3?\s+(?:-m\s+)?(?:http\.server|flask|manage\.py\s+runserver|uvicorn|fastapi)"
    r"|flask\s+run"
    r"|fastapi\s+(?:run|dev)"
    r"|uvicorn\s+"
    r"|gunicorn\s+"
    r"|php\s+(?:-S|artisan\s+serve)"
    r"|rails\s+(?:server|s)\b"
    r"|bundle\s+exec\s+rails"
    r"|dotnet\s+(?:run|watch)"
    r"|go\s+run"
    r"|cargo\s+run"
    r"|mvn\s+(?:spring-boot:run|jetty:run|tomcat:run)"
    r"|gradle\s+bootRun"
    r")", re.IGNORECASE,
)
BROWSER_RE = re.compile(
    r"(?:^|\s|;|&&|\|\|)("
    r"open\s+[\"']?(?:https?://|localhost|127\.0\.0\.1|0\.0\.0\.0)"
    r"|xdg-open\s+[\"']?(?:https?://|localhost|127\.0\.0\.1)"
    r"|start\s+[\"']?(?:https?://|localhost|127\.0\.0\.1)"
    r"|cmd(?:\.exe)?\s+/c\s+start\s+(?:https?://|localhost)"
    r"|powershell\s+.*Start-Process"
    r"|python3?\s+-m\s+webbrowser"
    r"|google-chrome\s+(?:https?://|localhost)"
    r"|firefox\s+(?:https?://|localhost)"
    r")", re.IGNORECASE,
)
server_started = False
browser_opened = False
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
            if msg.get("role") != "assistant":
                continue
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") != "tool_use":
                    continue
                if (block.get("name") or "") != "Bash":
                    continue
                cmd = ((block.get("input") or {}).get("command") or "")
                if SERVER_RE.search(cmd):
                    server_started = True
                if BROWSER_RE.search(cmd):
                    browser_opened = True
except Exception:
    print("ok"); sys.exit(0)
if server_started and browser_opened:
    print("ok")
elif server_started and not browser_opened:
    print("block:no-browser")
elif not server_started and browser_opened:
    print("block:no-server")
else:
    print("block:neither")
PYEOF
}

RAW_INPUT="$(cat 2>/dev/null || true)"

TRANSCRIPT_PATH="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    print(obj.get("transcript_path", "") or "")
except Exception:
    pass
' 2>/dev/null)"

# Spec-presence audit (since v10.0.4, ordering fix v10.1.16) — must
# run AFTER TRANSCRIPT_PATH is assigned. Prior to v10.1.16 this call
# sat above the assignment and tripped `set -u` on every Stop hook
# invocation, breaking phase-state advancement silently.
_SP_AUDIT="$(_mcl_spec_presence_audit "$TRANSCRIPT_PATH" 2>/dev/null || echo ok)"
if [ "$_SP_AUDIT" = "warn" ]; then
  mcl_audit_log "spec-required-warn" "stop" "edit-without-preceding-spec-in-turn"
  command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append spec_required_warn
fi

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

# --- Aşama 6 server-without-browser STRICT lens (v13.0.6) ---
# Real-world failure: model runs `npm run dev` then says "Tarayıcıyı açıyorum:"
# and stops without actually running `open <url>`. Aşama 6 spec explicitly
# requires "Proje otomatik olarak tarayıcıda açılır". This lens fires when:
#   - current_phase=6 OR ui_sub_phase=BUILD_UI
#   - asama-6-end / asama-6-skipped not yet in audit (this session)
#   - Last assistant turn ran a server-start Bash command
#   - Last assistant turn did NOT run a browser-open Bash command
# STRICT — no loop-breaker, no fail-open. User directive: "katı olsun".
# Bypass only via emitting asama-6-end or asama-6-skipped audit.
_A6_PHASE_FOR_LENS="$(mcl_state_get current_phase 2>/dev/null)"
_A6_UISUB_FOR_LENS="$(mcl_state_get ui_sub_phase 2>/dev/null)"
if [ "$_A6_PHASE_FOR_LENS" = "6" ] || [ "$_A6_UISUB_FOR_LENS" = "BUILD_UI" ]; then
  _A6_AUDIT_PATH="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  _A6_TRACE_PATH="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  _A6_ALREADY_DONE="$(python3 - "$_A6_AUDIT_PATH" "$_A6_TRACE_PATH" 2>/dev/null <<'PYEOF' || echo "no"
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
done = False
try:
    if os.path.isfile(audit_path):
        for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
            ts = line.split("|", 1)[0].strip()
            if session_ts and ts < session_ts:
                continue
            if "| asama-6-end |" in line or "| asama-6-skipped |" in line or "| asama-6-complete |" in line:
                done = True; break
except Exception:
    pass
print("yes" if done else "no")
PYEOF
)"
  if [ "$_A6_ALREADY_DONE" = "no" ] && \
     [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    _A6_LENS="$(_mcl_asama_6_server_browser_check "$TRANSCRIPT_PATH" 2>/dev/null || echo "ok")"
    case "$_A6_LENS" in
      block:no-server)
        _A6_AUDIT_TAG="asama-6-server-not-started-block"
        _A6_REASON_BODY="$(_mcl_runtime_reason \
          "⛔ MCL AŞAMA 6 EKSİK — Sunucu hiç başlatılmadı. Aşama 6 spec'i (MCL_Pipeline.md) şu üçünü zorunlu kılar:\n  (1) Frontend dummy data ile yazıldı ✓\n  (2) Proje ve bağımlılıkları **ayağa kaldırıldı** ✗\n  (3) Proje **otomatik olarak tarayıcıda açıldı** ✗\n\n${_BT}npm install${_BT} paket kurulumu — sunucuyu başlatmaz. ${_BT}node -e ${_BT} test komutu da değil. Sunucuyu çalıştır:\n  - Vite/React/Vue: ${_BT}npm run dev${_BT}\n  - Express/Node API: ${_BT}node server.js${_BT} veya ${_BT}npm start${_BT}\n  - Flask: ${_BT}flask run${_BT}\n  - Django: ${_BT}python manage.py runserver${_BT}\n  - vb.\n\nSunucu run_in_background:true ile başlatılmalı (bloklamasın). Sonra kısa sleep + tarayıcı aç:\n  ${_BT}sleep 2 && open http://localhost:<port>${_BT} (macOS) / ${_BT}xdg-open${_BT} (Linux)\n\nAşama 6 audit'i: ${_BT}bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log asama-6-end mcl-stop \\\"server_started=true browser_opened=true\\\"'${_BT}\n\nKATI MOD: fail-open yok. Sunucu + tarayıcı + audit zinciri tamamlanmadan stop kalkmaz." \
          "Aşama 6 eksik: sunucu başlatılmadı. ${_BT}npm run dev${_BT} (veya stack'ine uygun komut) çalıştır + tarayıcı aç (${_BT}open http://localhost:<port>${_BT}).")"
        ;;
      block:no-browser)
        _A6_AUDIT_TAG="asama-6-server-without-browser-block"
        _A6_REASON_BODY="$(_mcl_runtime_reason \
          "⛔ MCL AŞAMA 6 EKSİK — Sunucu başlatıldı AMA tarayıcı açılmadı. Aşama 6 spec'i: 'Proje otomatik olarak tarayıcıda açılır.' Tarayıcı açma komutu çalıştırılmadan Aşama 6 tamamlanmış sayılmaz.\n\nBu turda yap:\n1. Tarayıcıyı aç. macOS: ${_BT}open http://localhost:<port>${_BT}. Linux: ${_BT}xdg-open http://localhost:<port>${_BT}. Windows: ${_BT}start http://localhost:<port>${_BT}. Port'u sunucu çıktısından oku.\n2. Aşama 6 audit: ${_BT}bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log asama-6-end mcl-stop \\\"server_started=true browser_opened=true\\\"'${_BT}\n3. Aşama 7 (UI Review) AskUserQuestion: prefix ${_BT}MCL ${INSTALLED_VERSION} | Faz 7 — UI onayı:${_BT}.\n\nKATI MOD: fail-open yok." \
          "Aşama 6 eksik: sunucu çalışıyor ama tarayıcı açılmadı. ${_BT}open http://localhost:<port>${_BT} (macOS) veya ${_BT}xdg-open${_BT} (Linux) ile tarayıcıyı aç.")"
        ;;
      block:neither)
        _A6_AUDIT_TAG="asama-6-server-and-browser-missing-block"
        _A6_REASON_BODY="$(_mcl_runtime_reason \
          "⛔ MCL AŞAMA 6 TAMAMLANMADI — Ne sunucu başlatıldı ne tarayıcı açıldı. Aşama 6 invariant'ları (MCL_Pipeline.md):\n  (1) Frontend dummy data ile yazıldı ✓ (kod yazıldı)\n  (2) Proje ayağa kaldırıldı ✗\n  (3) Tarayıcıda açıldı ✗\n\n'Tamamlandı' demek yetmez — sunucu ve tarayıcı ÇALIŞTIRILMALI. Bu turda:\n1. ${_BT}npm install${_BT} (gerekirse — paket kurulumu)\n2. Sunucuyu başlat (background): ${_BT}npm run dev${_BT} / ${_BT}node server.js${_BT} / ${_BT}flask run${_BT} run_in_background:true\n3. Sleep + tarayıcı aç: ${_BT}sleep 2 && open http://localhost:<port>${_BT}\n4. Audit emit: ${_BT}bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log asama-6-end mcl-stop \\\"server_started=true browser_opened=true\\\"'${_BT}\n5. Aşama 7 (UI Review) askq.\n\nProje 'kullanılabilir hale gelmeden' Aşama 6 bitmez. UI flow yoksa: ${_BT}mcl_audit_log asama-6-skipped mcl-stop \\\"reason=no-ui-flow\\\"${_BT}." \
          "Aşama 6 tamamlanmadı: ne sunucu çalışıyor ne tarayıcı açık. ${_BT}npm run dev${_BT} (background) + ${_BT}open http://localhost:<port>${_BT} ile projeyi ayağa kaldır.")"
        ;;
      *) _A6_AUDIT_TAG=""; _A6_REASON_BODY="" ;;
    esac
    if [ -n "$_A6_AUDIT_TAG" ]; then
      mcl_audit_log "$_A6_AUDIT_TAG" "stop" "phase=${_A6_PHASE_FOR_LENS} ui_sub=${_A6_UISUB_FOR_LENS} verdict=${_A6_LENS}"
      command -v mcl_trace_append >/dev/null 2>&1 && \
        mcl_trace_append asama_6_block "${_A6_LENS}"
      printf '%s\n' "{
  \"decision\": \"block\",
  \"reason\": \"${_A6_REASON_BODY}\"
}"
      exit 0
    fi
  fi
fi

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

  # Aşama 5/6a/6b/6c/7 means approved and executing (pattern + UI sub-phases + code).
  if echo "$_PR_ACTIVE_PHASE" | grep -qE '^(5|6a|6b|6c|7)$'; then
    _PR_JSON="$(python3 "$_PR_GUARD" "$TRANSCRIPT_PATH" 2>/dev/null)"
    _PR_CODE="$(printf '%s' "$_PR_JSON" | python3 -c \
      'import json,sys; d=json.loads(sys.stdin.read()); print("true" if d.get("code_written") else "false")' 2>/dev/null)"
    _PR_ASKUQ="$(printf '%s' "$_PR_JSON" | python3 -c \
      'import json,sys; d=json.loads(sys.stdin.read()); print("true" if d.get("askuq_present") else "false")' 2>/dev/null)"

    # --- Aşama 6b enforcement (since v10.0.2) ---
    # When in 6a (BUILD_UI): if model wrote UI but did NOT emit
    # AskUserQuestion this turn, block — designer approval is required
    # before the turn can end. Loop-breaker after 3 strikes.
    if [ "$_PR_ACTIVE_PHASE" = "6a" ] && [ "$_PR_CODE" = "true" ] && [ "$_PR_ASKUQ" != "true" ]; then
      _UR_BLOCK_COUNT="$(_mcl_loop_breaker_count "ui-review-skip-block" 2>/dev/null || echo 0)"
      if [ "${_UR_BLOCK_COUNT:-0}" -ge 3 ]; then
        mcl_audit_log "ui-review-loop-broken" "stop" "count=${_UR_BLOCK_COUNT} fail-open"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append ui_review_loop_broken "${_UR_BLOCK_COUNT}"
        # Force-mark UI as reviewed so downstream phases can proceed.
        mcl_state_set ui_reviewed true >/dev/null 2>&1 || true
        mcl_state_set ui_sub_phase '"BACKEND"' >/dev/null 2>&1 || true
      else
        mcl_audit_log "ui-review-skip-block" "stop" "count=${_UR_BLOCK_COUNT}"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append ui_review_skip_block "${_UR_BLOCK_COUNT}"
        printf '%s\n' "{
  \"decision\": \"block\",
  \"reason\": \"⚠️ MCL AŞAMA 6b GEREKLİ — UI dosyaları yazıldı ama tasarım onayı sorulmadı.\n\nBu turda eksiksiz şu adımları yap:\n1. (Yapmadıysan) Bash ile dev server: ${_BT}npm install${_BT} → ${_BT}npm run dev${_BT} (run_in_background:true) → sleep 3 → ${_BT}open <url>${_BT} (macOS) / ${_BT}xdg-open <url>${_BT} (Linux). Geliştirici UI'ı tarayıcıda görmeden onay veremez.\n2. AskUserQuestion çağır — prefix ${_BT}MCL ${INSTALLED_VERSION} | ${_BT}, soru (geliştiricinin dilinde): 'Tasarımı onaylıyor musun?'. Options: 'Onayla' / 'Revize' / 'İptal'. Approve label BARE VERB ('Onayla' — açıklama yok; açıklama description'da).\n3. STOP. AskUserQuestion sonrası response BİTER. Geliştiricinin tool_result cevabını bekle.\n\nLoop-breaker: 3 üst üste skip → fail-open (ui_reviewed=true zorla set edilir, downstream açılır). Şu anki sayı: ${_UR_BLOCK_COUNT}/3.\"
}"
        exit 0
      fi
    fi

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
        "prev=${_PR_REVIEW_STATE} phase=${_PR_ACTIVE_PHASE} code=${_PR_CODE}"
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

      # Loop-breaker (since v9.0.0): if this enforcement already fired
      # 3+ times in the current session, fail-open. Repeated stickies
      # without a Aşama 8 dialog mean the model can't recover; further
      # blocks would just trap the developer.
      _PR_BLOCK_COUNT="$(_mcl_loop_breaker_count "phase-review-pending" 2>/dev/null || echo 0)"
      if [ "${_PR_BLOCK_COUNT:-0}" -ge 3 ]; then
        mcl_audit_log "phase-review-loop-broken" "stop" "count=${_PR_BLOCK_COUNT} fail-open"
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append risk_review_loop_broken "${_PR_BLOCK_COUNT}"
        # Mark risk review complete so downstream phases (Aşama 9/10/11)
        # can proceed. Aşama 8 was effectively skipped this session.
        mcl_state_set risk_review_state '"complete"' >/dev/null 2>&1 || true
      else
      # Return decision:block so Claude is forced to continue.
      printf '%s\n' "{
  \"decision\": \"block\",
  \"reason\": \"⚠️ MCL PHASE REVIEW ENFORCEMENT (mandatory, non-skippable)\n\nAşama 7 code was written but Aşama 8 Risk Review has NOT been started. You have two valid responses:\n\n(A) IF Aşama 6c BACKEND is NOT yet fully complete:\n    Continue writing the remaining code. State explicitly which files still need to be written. The enforcement block will repeat on each code-write turn until Aşama 8 starts.\n\n(B) IF ALL Aşama 7 code is NOW complete:\n    Start Aşama 8 Risk Review IMMEDIATELY in this response. Do NOT delay, do NOT summarize what you built, do NOT ask the developer a question unrelated to risks. Begin Aşama 8 now:\n    1. Review the code you just wrote for: security vulnerabilities (injection, auth bypass, XSS, CSRF, insecure defaults), performance bottlenecks (N+1, unbounded queries, missing indexes), edge cases (null/empty/overflow inputs), data integrity issues (missing transactions, inconsistent state), race conditions, regression surfaces.\n    2. Present ONE risk at a time via AskUserQuestion with prefix MCL ${INSTALLED_VERSION} |\n    3. After ALL Aşama 8 risks are resolved → run Aşama 10 Impact Review.\n    4. After Aşama 10 → run Aşama 11 Verification Report.\n\nAşama 8 → 4.6 → 5 are MANDATORY. Skipping them violates the MCL contract.\"
}"
      exit 0
      fi
    fi
  fi
fi

# --- Aşama 7 TDD compliance audit (since v10.1.4) ---
# Layer 1 (cheapest): scan session audit.log for tdd-test-write and
# tdd-prod-write events emitted by mcl-post-tool.sh. Compute
# compliance ratio: of all prod writes, how many had a preceding
# test write in the same session? Pure audit, no block. Visible via
# /mcl-checkup.
_mcl_tdd_compliance() {
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  if [ ! -f "$audit_file" ]; then echo "0|0|0"; return; fi
  python3 - "$audit_file" "$trace_file" 2>/dev/null <<'PYEOF' || echo "0|0|0"
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
test_writes = []  # list of timestamps
prod_writes = []
try:
    for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
        if "| tdd-test-write |" not in line and "| tdd-prod-write |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        if "tdd-test-write" in line:
            test_writes.append(ts)
        else:
            prod_writes.append(ts)
except Exception:
    pass
# Of each prod_write, count those preceded by at least one test_write.
# `<=` (not `<`) handles same-second ties: when test+prod fire in the
# same wall-clock second (date granularity), the test still counts as
# "preceding" — second-level granularity is too coarse to call this a
# TDD violation. Real-use timing has multiple seconds between events;
# the tie case appears in fast tests and rare Multi-Edit pairs.
preceded = sum(1 for p in prod_writes if any(t <= p for t in test_writes))
total_prod = len(prod_writes)
score = round((preceded / total_prod) * 100) if total_prod else (100 if test_writes else 0)
print(f"{score}|{preceded}|{total_prod}")
PYEOF
}

_TDD_RESULT="$(_mcl_tdd_compliance 2>/dev/null || echo "0|0|0")"
_TDD_SCORE="${_TDD_RESULT%%|*}"
_TDD_REST="${_TDD_RESULT#*|}"
_TDD_PRECEDED="${_TDD_REST%%|*}"
_TDD_TOTAL="${_TDD_REST##*|}"
# Only emit when there was at least one prod write this session
# (avoid noise on Read-only / non-code turns).
if [ "${_TDD_TOTAL:-0}" -gt 0 ]; then
  mcl_audit_log "tdd-compliance" "stop" "score=${_TDD_SCORE}% preceded=${_TDD_PRECEDED} prod=${_TDD_TOTAL}"
  command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append tdd_compliance "${_TDD_SCORE}%"
  mcl_state_set tdd_compliance_score "${_TDD_SCORE:-0}" >/dev/null 2>&1 || true
fi

# --- Audit-driven Aşama 1→2 progression (since v10.1.6) ---
# When the model emits the existing `precision-audit asama2` audit
# (mandated by skills/asama2-precision-audit.md), set
# precision_audit_done=true. Previously this state field was reset
# to false on restart but never set to true — the field was dead.
# Reuses the existing audit name (no new emit instruction needed).
_mcl_precision_audit_emitted() {
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  if [ ! -f "$audit_file" ]; then echo 0; return; fi
  python3 - "$audit_file" "$trace_file" 2>/dev/null <<'PYEOF' || echo 0
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
    for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
        if "| precision-audit |" not in line:
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
}

_PA_EMITTED="$(_mcl_precision_audit_emitted 2>/dev/null || echo 0)"
if [ "${_PA_EMITTED:-0}" = "1" ]; then
  _PA_DONE="$(mcl_state_get precision_audit_done 2>/dev/null)"
  if [ "$_PA_DONE" != "true" ]; then
    mcl_state_set precision_audit_done true >/dev/null 2>&1 || true
    mcl_audit_log "asama-2-progression-from-emit" "stop" "prev=${_PA_DONE:-null}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition 1 2
  fi
fi

# --- Audit-driven Aşama 4 progression (since v10.1.6) ---
# When the model emits `asama-4-complete` after AskUserQuestion returns
# an approve-family tool_result for spec approval, force-progress
# `spec_approved=true` and `current_phase=7`. Catches askq classifier
# coverage gaps that left the herta project frozen at phase 4 even
# though the model proceeded to Aşama 7 code-writing behaviorally.
# State machine becomes resilient to classifier intent-detection misses.
_mcl_asama_4_complete_emitted() {
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  if [ ! -f "$audit_file" ]; then echo 0; return; fi
  python3 - "$audit_file" "$trace_file" 2>/dev/null <<'PYEOF' || echo 0
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
}

_A4_EMITTED="$(_mcl_asama_4_complete_emitted 2>/dev/null || echo 0)"
if [ "${_A4_EMITTED:-0}" = "1" ]; then
  _A4_SA="$(mcl_state_get spec_approved 2>/dev/null)"
  _A4_PH="$(mcl_state_get current_phase 2>/dev/null)"
  # v13.0.11: post-spec-approval canonical phase is 5 (Pattern Matching).
  # Universal completeness loop below advances 5→6→...→9 as audits emit.
  # Guard with `-lt 5` so we don't pull state BACKWARD if the loop has
  # already advanced beyond Aşama 5 (e.g., asama-5-skipped already emitted).
  if [ "$_A4_SA" != "true" ] || [ "${_A4_PH:-0}" -lt 5 ] 2>/dev/null; then
    mcl_state_set spec_approved true >/dev/null 2>&1 || true
    mcl_state_set current_phase 5 >/dev/null 2>&1 || true
    mcl_state_set phase_name '"PATTERN_MATCHING"' >/dev/null 2>&1 || true
    mcl_audit_log "asama-4-progression-from-emit" "stop" "prev_approved=${_A4_SA:-null} prev_phase=${_A4_PH:-null}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition 4 5
  fi
fi

# --- v13.0.7 — Aşama 2 zero-gate synthesis ---
# Real-world failure: model walks Aşama 2 in prose only (silently classifies
# all 7 dimensions as SILENT-ASSUME), never emits the precision-audit Bash
# audit, and never asks a GATE askq. Result: gate engine has nothing to read,
# returns "incomplete", phase 2 stuck forever.
#
# Synthesis trigger (all must hold, in current session):
#   1. current_phase = 2
#   2. summary-confirm-approve audit present (Aşama 1 done)
#   3. NO precision-audit audit (model didn't emit dimension scan)
#   4. NO MCL `Faz 2 / Phase 2 / etc.` AskUserQuestion (no GATE asked)
#   5. NO asama-2-complete audit (not already done)
# When all hold, synthesize:
#   - precision-audit | stop-auto | core_gates=0 stack_gates=0 assumes=7 skipmarks=0 stack_tags= skipped=false synthesized=true
# Then the universal loop below will see the gate as complete (via
# auto_complete_check no_gates_or_skipped) and auto-emit asama-2-complete.
#
# Safe by construction: if model is mid-walk and about to emit audit /
# ask GATE next turn, conditions (3) and (4) are intentionally narrow —
# the synthesis only fires when model produced ZERO Aşama 2 evidence.
_A2_SYN_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
if [ "$_A2_SYN_PHASE" = "2" ] && command -v python3 >/dev/null 2>&1; then
  _A2_SYN_AUDIT="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  _A2_SYN_TRACE="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  _A2_SYN_VERDICT="$(python3 - "$_A2_SYN_AUDIT" "$_A2_SYN_TRACE" "$TRANSCRIPT_PATH" 2>/dev/null <<'PYEOF'
import json, os, re, sys
audit_path, trace_path, transcript_path = sys.argv[1], sys.argv[2], sys.argv[3]
session_ts = ""
try:
    if os.path.isfile(trace_path):
        for line in open(trace_path, "r", encoding="utf-8", errors="replace"):
            if "| session_start |" in line:
                session_ts = line.split("|", 1)[0].strip()
except Exception:
    pass
has_summary = False
has_precision = False
has_a2_complete = False
try:
    if os.path.isfile(audit_path):
        for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
            ts = line.split("|", 1)[0].strip()
            if session_ts and ts < session_ts:
                continue
            if "| summary-confirm-approve |" in line:
                has_summary = True
            if "| precision-audit |" in line:
                has_precision = True
            if "| asama-2-complete |" in line:
                has_a2_complete = True
except Exception:
    pass
# Check transcript for any Faz 2 / Phase 2 askq this turn
faz2_askq = False
PHASE2_PREFIX_RE = re.compile(
    r"MCL\s+\d+(\.\d+){2}\s*\|\s*(Faz|Phase|Aşama|Etape|Étape|Fase|Schritt|フェーズ|阶段|단계|مرحلة|שלב|चरण|Tahap|Этап|Step)\s+2\b",
    re.IGNORECASE,
)
try:
    if transcript_path and os.path.isfile(transcript_path):
        with open(transcript_path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                msg = obj.get("message") or obj
                if not isinstance(msg, dict) or msg.get("role") != "assistant":
                    continue
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("name") == "AskUserQuestion":
                        q = ((block.get("input") or {}).get("question") or "")
                        if PHASE2_PREFIX_RE.search(q):
                            faz2_askq = True
                            break
except Exception:
    pass
# Synthesis criteria
if has_summary and not has_precision and not has_a2_complete and not faz2_askq:
    print("synthesize")
else:
    print("skip")
PYEOF
)"
  if [ "$_A2_SYN_VERDICT" = "synthesize" ]; then
    mcl_audit_log "precision-audit" "stop-auto" "core_gates=0 stack_gates=0 assumes=7 skipmarks=0 stack_tags= skipped=false synthesized=true"
    mcl_audit_log "asama-2-zero-gate-synthesis" "stop-auto" "reason=no-precision-audit-no-faz2-askq"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append asama_2_synth zero_gate
  fi
fi

# --- v13.0 — Universal phase completion loop ---
# Replaces all hardcoded asama-8/9/10/11/12 progression blocks (v11/v12 era).
# Reads gate-spec.json via lib/mcl-gate.sh, walks current_phase forward,
# auto-emits *-complete + phase_transition for each gate that passes.
# Loop bound: max 22 iterations (defensive cap, never reached in practice).
if [ -f "$_MCL_HOOK_DIR/lib/mcl-gate.sh" ]; then
  source "$_MCL_HOOK_DIR/lib/mcl-gate.sh"
  _V13_CUR="$(mcl_state_get current_phase 2>/dev/null || echo 1)"
  _V13_ITER=0
  while [ "$_V13_ITER" -lt 22 ]; do
    _V13_ITER=$((_V13_ITER + 1))
    _V13_PHASE="$_V13_CUR"
    _V13_RESULT="$(_mcl_gate_check "$_V13_PHASE" 2>/dev/null || echo incomplete)"
    if [ "$_V13_RESULT" != "complete" ]; then
      break
    fi
    # Idempotency: skip emit if asama-N-complete already in session audit
    _V13_HAS="$(_mcl_audit_emitted_in_session "asama-${_V13_PHASE}-complete" "" 2>/dev/null || echo 0)"
    if [ "${_V13_HAS:-0}" != "1" ]; then
      mcl_audit_log "asama-${_V13_PHASE}-complete" "stop-auto" "gate=passed"
    fi
    _V13_NEXT=$((_V13_PHASE + 1))
    if [ "$_V13_NEXT" -gt 22 ]; then
      command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition "$_V13_PHASE" "done"
      break
    fi
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition "$_V13_PHASE" "$_V13_NEXT"
    mcl_state_set current_phase "$_V13_NEXT" >/dev/null 2>&1 || true
    _V13_CUR="$_V13_NEXT"
  done
fi

# --- Legacy: Aşama 9 auto-complete (since v10.1.11) — kept for v12 fallback ---
# v13.0 universal loop (above) is primary. This block remains for v12.x
# audit format detection (asama-N-N-end pattern). Sunset v13.1.
# Real-world failure mode (grom backoffice): all 8 sub-step audits
# (asama-9-N-start/end OR asama-9-N-not-applicable) fired correctly
# but model forgot to emit the final `asama-10-complete` summary
# audit. Result: trace.log missed `phase_transition 9 10`, Aşama 11
# Process Trace appeared to skip Aşama 9, developer concluded the
# phase was atlanmış even though every sub-step actually ran.
#
# Fix: when Stop sees all 8 sub-step completion signals AND
# `asama-10-complete` is missing, auto-emit it. Existing v10.1.5
# progression scanner (below) then promotes quality_review_state to
# complete normally. The auto-emit is logged with caller=mcl-stop-auto
# so it's distinguishable from a model-generated emit during forensics.
_mcl_asama_9_substeps_complete() {
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  if [ ! -f "$audit_file" ]; then echo "0|0"; return; fi
  python3 - "$audit_file" "$trace_file" 2>/dev/null <<'PYEOF' || echo "0|0"
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
done = {n: False for n in range(10, 18)}
try:
    for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        # v11 (since v11.0.0): scan asama-10..17 (the dedicated quality
        # phases). Either asama-N-end (phase ran) OR asama-N-not-applicable
        # (phase soft-skipped with reason) counts as completion. Pre-v11
        # this scanned asama-9-1..9-8 sub-steps; the rename matches the
        # v11 architecture's flat phase numbering.
        for n in range(10, 18):
            if (f"| asama-{n}-end |" in line or
                f"| asama-{n}-not-applicable |" in line):
                done[n] = True
except Exception:
    pass
all_done = all(done.values())
done_count = sum(1 for v in done.values() if v)
print(f"{done_count}|{1 if all_done else 0}")
PYEOF
}

_A9_SUB_RESULT="$(_mcl_asama_9_substeps_complete 2>/dev/null || echo "0|0")"
_A9_SUB_DONE_COUNT="${_A9_SUB_RESULT%%|*}"
_A9_SUB_ALL_DONE="${_A9_SUB_RESULT##*|}"
if [ "${_A9_SUB_ALL_DONE:-0}" = "1" ]; then
  _A9_HAS_COMPLETE="$(_mcl_audit_emitted_in_session "asama-10-complete" "" 2>/dev/null || echo 0)"
  if [ "${_A9_HAS_COMPLETE:-0}" != "1" ]; then
    mcl_audit_log "asama-10-complete" "mcl-stop-auto" "substeps_done=8 (auto-emitted; model forgot summary)"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append asama_9_auto_complete "8/8"
  fi
fi

# --- Audit-driven Aşama 8 progression (since v10.1.5, PILOT) ---
# When the model emits an explicit `asama-8-complete` audit at the end
# of risk review, force-progress `risk_review_state` to `complete` even
# if the askq classifier missed the normal transition. This catches:
#   - Classifier intent gaps (off-language wording, prefix dropped)
#   - Sessions where spec_approved=false but Aşama 8 still ran
#   - Behavioral progression that bypassed AskUserQuestion entirely
# Pure audit-trail mechanic; emits trace + audit so bypass is visible.
_mcl_asama_8_complete_emitted() {
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  if [ ! -f "$audit_file" ]; then echo 0; return; fi
  python3 - "$audit_file" "$trace_file" 2>/dev/null <<'PYEOF' || echo 0
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
    for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
        if "| asama-8-complete |" not in line:
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
}

_A8_EMITTED="$(_mcl_asama_8_complete_emitted 2>/dev/null || echo 0)"
if [ "${_A8_EMITTED:-0}" = "1" ]; then
  _A8_CUR="$(mcl_state_get risk_review_state 2>/dev/null)"
  if [ "$_A8_CUR" != "complete" ]; then
    mcl_state_set risk_review_state '"complete"' >/dev/null 2>&1 || true
    mcl_audit_log "asama-8-progression-from-emit" "stop" "prev=${_A8_CUR:-null}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition 8 9
  fi
fi

# --- Audit-driven Aşama 9 progression (since v10.1.5, PILOT) ---
# Symmetric to the Aşama 8 progression above. When the model emits
# `asama-10-complete` after 9.1–9.8 sub-steps, force-progress
# `quality_review_state` to `complete`. Behavioral skips that bypass
# the normal "all sub-steps end" transition still get tracked.
# Severity gate (v10.1.2 open_severity_count check) still applies
# downstream — this only unblocks the state, not the severity invariant.
_mcl_asama_9_complete_emitted() {
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  if [ ! -f "$audit_file" ]; then echo 0; return; fi
  python3 - "$audit_file" "$trace_file" 2>/dev/null <<'PYEOF' || echo 0
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
    for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
        if "| asama-10-complete |" not in line:
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
}

_A9_EMITTED="$(_mcl_asama_9_complete_emitted 2>/dev/null || echo 0)"
if [ "${_A9_EMITTED:-0}" = "1" ]; then
  _A9_CUR="$(mcl_state_get quality_review_state 2>/dev/null)"
  if [ "$_A9_CUR" != "complete" ]; then
    mcl_state_set quality_review_state '"complete"' >/dev/null 2>&1 || true
    mcl_audit_log "asama-10-progression-from-emit" "stop" "prev=${_A9_CUR:-null}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition 9 10
  fi
fi

# --- Audit-driven Aşama 10/11/12 transient-phase trace (since v10.1.6) ---
# These phases are transient (no persisted state field). Each emits a
# completion audit so trace.log reflects the full pipeline run.
# Aşama 12 reuses the existing `localize-report asama12` audit
# (mandated by skills/asama21-localized-report.md) — no new emit needed.
# Idempotent: re-runs of Stop in same session skip if progression
# already traced.
# `_mcl_audit_emitted_in_session` helper has moved to
# hooks/lib/mcl-state.sh (since v10.1.8) and uses proper timestamp
# normalization (since v10.1.13). The duplicate that used to live
# here has been removed; the lib version is in scope via the
# `source` of mcl-state.sh at the top of this file.

# Aşama 10 — explicit asama-10-complete emit
_A10_FIRE="$(_mcl_audit_emitted_in_session "asama-10-complete" "asama-10-progression-from-emit" 2>/dev/null || echo 0)"
if [ "${_A10_FIRE:-0}" = "1" ]; then
  mcl_audit_log "asama-10-progression-from-emit" "stop" ""
  command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition 10 11
fi

# Aşama 11 — explicit asama-11-complete emit
_A11_FIRE="$(_mcl_audit_emitted_in_session "asama-11-complete" "asama-11-progression-from-emit" 2>/dev/null || echo 0)"
if [ "${_A11_FIRE:-0}" = "1" ]; then
  mcl_audit_log "asama-11-progression-from-emit" "stop" ""
  command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition 11 12
fi

# Aşama 12 — reuses existing localize-report audit
_A12_FIRE="$(_mcl_audit_emitted_in_session "localize-report" "asama-12-progression-from-emit" 2>/dev/null || echo 0)"
if [ "${_A12_FIRE:-0}" = "1" ]; then
  mcl_audit_log "asama-12-progression-from-emit" "stop" ""
  command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition 12 done
fi

# --- Layer 3: Skip-detection (since v10.1.6) ---
# When code-write activity occurred this session (tdd-prod-write
# audit emitted by post-tool) but the corresponding asama-N-complete
# emit is missing for phase N ∈ {4, 8, 9}, write `asama-N-emit-missing`
# audit. Pure visibility — no block, no decision change. Surfaces in
# /mcl-checkup so the developer can see when the model bypassed the
# explicit phase-completion contract.
_mcl_skip_detection() {
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  if [ ! -f "$audit_file" ]; then echo ""; return; fi
  python3 - "$audit_file" "$trace_file" 2>/dev/null <<'PYEOF' || echo ""
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
prod_write = False
emits = {"4": False, "8": False, "9": False}
already = {"4": False, "8": False, "9": False}
try:
    for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        if "| tdd-prod-write |" in line:
            prod_write = True
        for n in ("4", "8", "9"):
            if f"| asama-{n}-complete |" in line:
                emits[n] = True
            if f"| asama-{n}-emit-missing |" in line:
                already[n] = True
except Exception:
    pass
# Only flag missing emits when there was actual code-write activity.
# A no-code session (only Read/Grep) is not a violation.
missing = []
if prod_write:
    for n in ("4", "8", "9"):
        if not emits[n] and not already[n]:
            missing.append(n)
print(" ".join(missing))
PYEOF
}

_MISSING_EMITS="$(_mcl_skip_detection 2>/dev/null || echo "")"
if [ -n "$_MISSING_EMITS" ]; then
  for _ph in $_MISSING_EMITS; do
    mcl_audit_log "asama-${_ph}-emit-missing" "stop" "skip-detect prod-write-without-emit"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_emit_missing "$_ph"
  done
fi

# --- MEDIUM/HIGH must-resolve invariant (since v10.1.2) ---
# Compute the count of open HIGH/MEDIUM findings in the current
# session. A finding is "open" when an `asama-9-4-ambiguous` audit
# event exists for it AND no matching `asama-9-4-resolved` event
# exists. The count is stored in state.open_severity_count for
# downstream gates (Aşama 9 complete / Aşama 11 fire) to consult.
_mcl_open_severity_count() {
  local audit_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/audit.log"
  local trace_file="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/trace.log"
  if [ ! -f "$audit_file" ]; then echo 0; return; fi
  python3 - "$audit_file" "$trace_file" 2>/dev/null <<'PYEOF' || echo 0
import os, re, sys
audit_path, trace_path = sys.argv[1], sys.argv[2]
session_ts = ""
try:
    if os.path.isfile(trace_path):
        for line in open(trace_path, "r", encoding="utf-8", errors="replace"):
            if "| session_start |" in line:
                session_ts = line.split("|", 1)[0].strip()
except Exception:
    pass
ambiguous, resolved = set(), set()
def _key(detail):
    m = re.search(r"rule=(\S+)\s+file=(\S+)", detail or "")
    return m.group(0) if m else None
try:
    for line in open(audit_path, "r", encoding="utf-8", errors="replace"):
        if "| asama-9-4-ambiguous |" not in line and "| asama-9-4-resolved |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        parts = line.split("|", 3)
        detail = parts[3].strip() if len(parts) > 3 else ""
        k = _key(detail)
        if not k:
            continue
        if "asama-9-4-ambiguous" in line:
            ambiguous.add(k)
        elif "asama-9-4-resolved" in line:
            resolved.add(k)
except Exception:
    pass
print(len(ambiguous - resolved))
PYEOF
}

_OS_OPEN_COUNT="$(_mcl_open_severity_count 2>/dev/null || echo 0)"
mcl_state_set open_severity_count "${_OS_OPEN_COUNT:-0}" >/dev/null 2>&1 || true

# Block Aşama 11 / quality-complete advance when open M/H findings
# exist. Loop-breaker: 3 strikes → fail-open + force resolved (every
# open finding marked resolved with `loop-broken` reason in audit).
_QR_FOR_OS="$(mcl_state_get quality_review_state 2>/dev/null)"
if [ "$_QR_FOR_OS" = "complete" ] && [ "${_OS_OPEN_COUNT:-0}" -gt 0 ]; then
  _OS_BLOCK_COUNT="$(_mcl_loop_breaker_count "open-severity-block" 2>/dev/null || echo 0)"
  if [ "${_OS_BLOCK_COUNT:-0}" -ge 3 ]; then
    mcl_audit_log "open-severity-loop-broken" "stop" "count=${_OS_BLOCK_COUNT} open=${_OS_OPEN_COUNT} fail-open"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append open_severity_loop_broken "${_OS_BLOCK_COUNT}"
  else
    mcl_audit_log "open-severity-block" "stop" "count=${_OS_BLOCK_COUNT} open=${_OS_OPEN_COUNT}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append open_severity_block "${_OS_BLOCK_COUNT}"
    printf '%s\n' "{
  \"decision\": \"block\",
  \"reason\": \"⚠️ MCL MEDIUM/HIGH MUST-RESOLVE INVARIANT — Aşama 9 quality_review_state=complete olarak işaretlendi AMA hâlâ ${_OS_OPEN_COUNT} adet HIGH/MEDIUM seviyeli açık bulgu var (asama-9-4-ambiguous emit edilmiş ama asama-9-4-resolved yazılmamış).\n\nAşama 11'e geçmeden önce her açık bulgu çözülmeli:\n1. Aşama 8 risk-dialog'ina geri dön (her açık bulgu için bir AskUserQuestion turu).\n2. Geliştirici karar verir — apply specific fix / accept with rule-capture justification / cancel.\n3. Her resolution için ${_BT}bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log asama-9-4-resolved stop \\\"rule=<id> file=<f>:<l> status=fixed|accepted\\\"'${_BT} yaz.\n4. open_severity_count 0 olunca block kalkar, Aşama 11 fire eder.\n\nLoop-breaker: 3 üst üste skip → fail-open. Şu anki sayı: ${_OS_BLOCK_COUNT}/3.\"
}"
    exit 0
  fi
fi

# --- Aşama 9 quality+tests hard-enforcement (since v10.1.0) ---
# When Aşama 8 risk dialog completed (risk_review_state=complete) AND
# Aşama 9 quality pipeline did NOT complete (quality_review_state ≠
# complete) AND code was written this session, block. The 8 sequential
# sub-steps (9.1-9.8) MUST run before Aşama 10 / Aşama 11 can fire.
# Loop-breaker after 3 strikes preserves v9.0.1 fail-open guarantee.
_QR_STATE="$(mcl_state_get quality_review_state 2>/dev/null)"
_RR_STATE_FOR_QC="$(mcl_state_get risk_review_state 2>/dev/null)"
if [ "$_RR_STATE_FOR_QC" = "complete" ] && [ "$_QR_STATE" != "complete" ]; then
  _QR_BLOCK_COUNT="$(_mcl_loop_breaker_count "quality-review-pending" 2>/dev/null || echo 0)"
  if [ "${_QR_BLOCK_COUNT:-0}" -ge 3 ]; then
    mcl_audit_log "quality-review-loop-broken" "stop" "count=${_QR_BLOCK_COUNT} fail-open"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append quality_review_loop_broken "${_QR_BLOCK_COUNT}"
    mcl_state_set quality_review_state '"complete"' >/dev/null 2>&1 || true
  else
    mcl_audit_log "quality-review-pending" "stop" "count=${_QR_BLOCK_COUNT} qstate=${_QR_STATE:-null}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append quality_review_pending "${_QR_BLOCK_COUNT}"
    printf '%s\n' "{
  \"decision\": \"block\",
  \"reason\": \"⚠️ MCL AŞAMA 9 ENFORCEMENT — Aşama 8 risk review tamamlandı ama Aşama 9 (quality+tests pipeline) çalışmadı. 8 sıralı sub-step ZORUNLU: 9.1 Code Review → 9.2 Simplify → 9.3 Performance → 9.4 Security (otomatik semgrep + npm audit) → 9.5 Unit tests → 9.6 Integration tests → 9.7 E2E tests → 9.8 Load tests. Her sub-step için audit entry (asama-9-N-start ve asama-9-N-end) yazılmalı. Yumuşak katılık: applicable değilse 'asama-9-N-not-applicable | reason=...' audit yaz + skip silently. NOT applicable iken bile audit emit zorunlu (skip-detection için). Şu anki sayı: ${_QR_BLOCK_COUNT}/3 (loop-breaker)\n\nAşama 9 fast-path YOK — görev küçük olsa, prototip olsa, 'sadece UI tweak' olsa bile çalışır. Tek istisna: hiç kod yazılmadıysa.\"
}"
    exit 0
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
      # --- Aşama 2 precision-audit skip detection (since v9.0.0) ---
      # Aşama 1 → 4 transition: Aşama 2 should have emitted a precision-audit
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
          # Loop-breaker (since v9.0.0): if this block already fired 3+
          # times in the current session, fail-open. The model couldn't
          # recover after 3 attempts; further blocks would just trap
          # the developer. Audit the loop-broken decision so it's
          # visible in `/mcl-checkup`.
          _PA_BLOCK_COUNT="$(_mcl_loop_breaker_count "precision-audit-block" 2>/dev/null || echo 0)"
          if [ "${_PA_BLOCK_COUNT:-0}" -ge 3 ]; then
            mcl_audit_log "precision-audit-loop-broken" "mcl-stop.sh" "count=${_PA_BLOCK_COUNT} fail-open"
            command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append precision_audit_loop_broken "${_PA_BLOCK_COUNT}"
            # Allow the Aşama 1→4 transition to proceed (the spec is
            # accepted as-is; precision_audit was missed).
            mcl_state_set precision_audit_done false >/dev/null 2>&1 || true
          else
          mcl_audit_log "precision-audit-block" "mcl-stop.sh" "summary-confirmed-but-no-audit; transition-rewind count=${_PA_BLOCK_COUNT}"
          command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append precision_audit_block "count=${_PA_BLOCK_COUNT}"
          printf '%s\n' "{
  \"decision\": \"approve\",
  \"reason\": \"⚠️ MCL AŞAMA 2 PRECISION AUDIT ENFORCEMENT (mandatory, non-skippable)\n\nA Aşama 4 spec block was emitted but Aşama 2 Precision Audit has NOT been run. The Aşama 1→4 transition is blocked. NOTE: even an all-SILENT-ASSUME pass with zero GATE questions still requires the audit entry — "no GATEs" does NOT mean "skip the audit". In this SAME response, before the turn closes:\n\n1. Read ~/.claude/skills/my-claude-lang/asama2-precision-audit.md for the dimension list and classification rules.\n2. Walk the 7 core dimensions (permission/access, algorithmic failure modes, out-of-scope boundaries, PII handling, audit/observability, performance SLA, idempotency/retry) plus any matching stack add-ons returned by: bash ~/.claude/hooks/lib/mcl-stack-detect.sh detect \\\"\$(pwd)\\\"\n3. Classify each dimension: SILENT-ASSUME (mark [assumed: X]), SKIP-MARK (mark [unspecified: X] — currently only Performance SLA), or GATE (architectural impact → ask one question via AskUserQuestion).\n4. Emit the audit entry via: bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log precision-audit asama2 \\\"core_gates=N stack_gates=M assumes=K skipmarks=L stack_tags=<tags> skipped=false\\\"' (substitute counts and tags).\n5. Re-emit the spec block with precision-enriched parameters. The prior spec is discarded — replaced, not duplicated.\n\nIf detected language is English, emit the audit with skipped=true (Aşama 1 already in English; behavioral prior assumed sufficient — same single-line `mcl_audit_log` call, just with skipped=true) and the block clears immediately on the next turn.\n\nRecovery: if you believe this block fired in error (e.g., audit emit failed silently), type /mcl-restart to clear phase state.\"
}"
          exit 0
          fi
        fi
      fi

      # v13.0.11 — A-2 fix: Aşama 1'de spec emit'i sıralılık ihlali.
      # Önceden bu blok durumu zorla 4'e atıyordu (legacy 1→4 atlama).
      # Sıralılık disiplini gereği state advance KALDIRILDI — durum 1'de kalır.
      # Universal completeness döngüsü (stop hook sonunda) audit log'u okur:
      # `summary-confirm-approve` varsa otomatik 1→2 ilerletir, audit chain
      # tamsa 2→3→4 zincirini izler. Hook artık sıralılığı zorla atlamaz.
      # spec_hash kaydı da kaldırıldı: durum 1'de spec hash'i tutmak yanlış
      # sinyal verir (üst blokta precision-audit-block zaten gerekli kontrolü
      # yapıyor; eğer geçerse universal loop spec emit'ini doğal yolla işler).
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
  elif [ "$SPEC_APPROVED" = "true" ] || [ "$CURRENT_PHASE" -ge 5 ] 2>/dev/null; then
    mcl_debug_log "stop" "askq-idempotent" "phase=${CURRENT_PHASE} approved=${SPEC_APPROVED}"
  elif [ -z "$CURRENT_HASH" ]; then
    mcl_audit_log "askq-ignored-no-spec" "stop" "phase=${CURRENT_PHASE}"
    mcl_debug_log "stop" "askq-ignored-no-spec" "phase=${CURRENT_PHASE}"
  elif [ "$CURRENT_PHASE" = "4" ] || [ "$CURRENT_PHASE" = "3" ]; then
    # v13.0.15 — Hard enforce sıralılık: spec-approve advance hakkı için
    # Aşama 1, 2, 3 audit'leri tam olmalı. Eksikse atlama tespit edildi —
    # state advance YAPILMAZ + decision:block + REASON.
    _CHAIN_STATUS="$(_mcl_pre_spec_audit_chain_status 2>/dev/null || echo ok)"
    if [ -n "$_CHAIN_STATUS" ] && [ "$_CHAIN_STATUS" != "ok" ]; then
      mcl_audit_log "spec-approve-chain-incomplete" "stop" "missing=${_CHAIN_STATUS}"
      command -v mcl_trace_append >/dev/null 2>&1 && \
        mcl_trace_append spec_approve_chain_incomplete "${_CHAIN_STATUS}"
      _CHAIN_REASON="$(_mcl_runtime_reason \
        "MCL ASAMA SIRALILIK IHLALI (v13.0.15) — Spec-approve askq onayı geldi AMA Aşama 1/2/3 audit zinciri eksik. Eksik audit'ler: ${_CHAIN_STATUS}. State advance YAPILMADI. Sıralılık invariantı: Aşama 4 onayı verilebilmesi için 1, 2, 3 fazlarının audit'leri zincirde bulunmalı. Recovery: her eksik audit için bash recovery hatch kullan: bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log <name> <caller> \"<details>\"'. Eksik audit'ler: summary-confirm-approve (Aşama 1 onayı), asama-2-complete (Aşama 2 precision-audit kapanışı), asama-3-complete (Aşama 3 engineering brief). Bunlar emit edildikten sonra spec-approve advance otomatik gerçekleşir." \
        "Aşama atlandı: spec onayı verildi ama Aşama 1/2/3 audit'leri eksik (${_CHAIN_STATUS}). Bu fazları sırasıyla tamamla, sonra spec onayı geçerli olur.")"
      printf '%s\n' "{
  \"decision\": \"block\",
  \"reason\": \"${_CHAIN_REASON}\"
}"
      exit 0
    fi
    mcl_state_set spec_approved true
    mcl_state_set current_phase 5
    mcl_state_set phase_name '"PATTERN_MATCHING"'
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
    mcl_audit_log "approve-via-askuserquestion" "stop" "hash=${CURRENT_HASH:0:12} phase=${CURRENT_PHASE}->5 ui_flow=${UI_FLOW_ON}"
    mcl_debug_log "stop" "approve-via-askuserquestion" "hash=${CURRENT_HASH:0:12} phase=${CURRENT_PHASE}->5"
    command -v mcl_trace_append >/dev/null 2>&1 && {
      mcl_trace_append spec_approved "${CURRENT_HASH:0:12}"
      mcl_trace_append phase_transition "$CURRENT_PHASE" 5
      [ "$UI_FLOW_ON" = "true" ] && mcl_trace_append ui_flow_enabled
    }
    command -v mcl_log_append >/dev/null 2>&1 && mcl_log_append "Spec onaylandı. Faz ${CURRENT_PHASE} → 5 geçişi."
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

# --- Aşama 2 precision-confirm (since v10.1.14) ---
# Aşama 2 closing askq: emitted after the 7-dimension scan + GATE
# answers, asks the developer to approve the precision-audited intent
# before Aşama 4 (SPEC) emits. On approve, this branch emits the
# `asama-2-complete` audit which is the deterministic gate enforced by
# mcl-pre-tool.sh's Aşama 2 SKIP-BLOCK. Mirrors the summary-confirm
# pattern above. The approve-family detection is the same 14-language
# whitelist used by other gates.
if [ "$ASKQ_INTENT" = "precision-confirm" ]; then
  if _mcl_is_approve_option "$ASKQ_SELECTED"; then
    mcl_audit_log "asama-2-complete" "stop" "selected=${ASKQ_SELECTED}"
    mcl_debug_log "stop" "asama-2-complete" "selected=${ASKQ_SELECTED}"
    command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append asama_2_complete approved
  else
    mcl_debug_log "stop" "precision-confirm-non-approve" "selected=${ASKQ_SELECTED}"
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
