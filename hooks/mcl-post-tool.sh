#!/bin/bash
# MCL PostToolUse Hook — log each tool call to the active session diary.
# One Turkish sentence + estimated token cost per tool call.

set -u

# Hook health timestamp (since 8.2.7) — writes hook_last_run_ts to
# .mcl/hook-health.json so `mcl check-up` can detect an unregistered or
# silently broken hook (no recent timestamp = WARN).
_HH_FILE="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/hook-health.json"
mkdir -p "$(dirname "$_HH_FILE")" 2>/dev/null || true
python3 - "$_HH_FILE" "post_tool" "$(date +%s)" 2>/dev/null <<'PYEOF' || true
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
LOG_LIB="$SCRIPT_DIR/lib/mcl-log-append.sh"
[ -f "$LOG_LIB" ] && source "$LOG_LIB"

RAW_INPUT="$(cat 2>/dev/null || true)"

[ -z "$RAW_INPUT" ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

MSG="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys

raw = sys.stdin.read()
try:
    obj = json.loads(raw)
except Exception:
    sys.exit(0)

tool = str(obj.get("tool_name", "") or "")
inp  = obj.get("tool_input", {}) or {}

try:
    token_est = max(1, len(json.dumps(inp).encode("utf-8")) // 4)
except Exception:
    token_est = 0

def trunc(s, n=70):
    s = str(s)
    return (s[:n] + "…") if len(s) > n else s

if tool == "Write":
    fp = inp.get("file_path", "?")
    sentence = f"`{fp}` dosyası yazıldı."
elif tool == "Edit":
    fp = inp.get("file_path", "?")
    sentence = f"`{fp}` dosyası düzenlendi."
elif tool in ("MultiEdit", "NotebookEdit"):
    fp = inp.get("file_path", "?")
    sentence = f"`{fp}` dosyasında toplu düzenleme yapıldı."
elif tool == "Bash":
    cmd = inp.get("command", "?")
    sentence = f"`{trunc(cmd)}` komutu çalıştırıldı."
elif tool == "Read":
    fp = inp.get("file_path", "?")
    sentence = f"`{fp}` dosyası okundu."
elif tool == "Glob":
    pat = inp.get("pattern", "?")
    sentence = f"`{pat}` deseniyle dosya arandı."
elif tool == "Grep":
    pat = inp.get("pattern", "?")
    sentence = f"`{pat}` için içerik tarandı."
elif tool == "TodoWrite":
    sentence = "Görev listesi güncellendi."
elif tool == "AskUserQuestion":
    questions = inp.get("questions", [])
    q_text = questions[0].get("question", "?") if questions else "?"
    sentence = f"Kullanıcıya soru soruldu: {trunc(q_text, 60)}"
elif tool == "WebFetch":
    url = inp.get("url", "?")
    sentence = f"`{trunc(url, 60)}` adresi getirildi."
elif tool == "WebSearch":
    q = inp.get("query", "?")
    sentence = f"`{trunc(q, 60)}` için web araması yapıldı."
elif tool == "Agent":
    desc = inp.get("description", "alt görev")
    sentence = f"Alt ajan başlatıldı: {trunc(desc, 60)}"
else:
    sentence = f"`{tool}` aracı kullanıldı."

tok = f"{token_est:,}".replace(",", ".")
print(f"{sentence} | ~{tok} token")
' 2>/dev/null)"

if [ -n "$MSG" ] && command -v mcl_log_append >/dev/null 2>&1; then
  mcl_log_append "$MSG"
fi

# Regression guard clearance: when Claude runs tests via mcl-test-runner.sh
# and they pass (GREEN), clear regression_block_active so Aşama 8 unblocks.
TOOL_NAME_POST="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json,sys
try: print(json.loads(sys.stdin.read()).get("tool_name",""))
except: pass
' 2>/dev/null)"

# --- TDD compliance audit (since v10.1.4) ---
# When a write tool fires, classify the file as test/prod/skip via
# path heuristics and emit `tdd-test-write` or `tdd-prod-write` audit.
# Stop hook scans these to compute compliance ratio. No block, audit
# only — visible in /mcl-checkup.
if printf '%s' "$TOOL_NAME_POST" | grep -qE '^(Write|Edit|MultiEdit|NotebookEdit)$' 2>/dev/null; then
  _TDD_FILE="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    tin = obj.get("tool_input") or {}
    print(tin.get("file_path") or tin.get("notebook_path") or "")
except Exception:
    pass
' 2>/dev/null)"
  if [ -n "$_TDD_FILE" ]; then
    _TDD_KIND="$(python3 -c '
import os, re, sys
path = sys.argv[1]
SKIP_DIR_RE = re.compile(r"(^|/)(node_modules|dist|build|\.next|\.nuxt|\.cache|coverage|\.git)/")
if SKIP_DIR_RE.search(path):
    print("skip"); sys.exit(0)
ext = os.path.splitext(path)[1].lower()
TEST_PATTERNS = [
    r"__tests__/",
    r"(^|/)tests?/",
    r"(^|/)specs?/",
    r"\.test\.(ts|tsx|js|jsx|mts|cts|mjs|cjs)$",
    r"\.spec\.(ts|tsx|js|jsx|mts|cts|mjs|cjs)$",
    r"_test\.(go|py)$",
    r"_spec\.rb$",
    r"(^|/)test_[^/]+\.py$",
    r"\.test\.[a-z]+$",
]
for pat in TEST_PATTERNS:
    if re.search(pat, path):
        print("test"); sys.exit(0)
SRC_EXT = {".ts",".tsx",".js",".jsx",".mts",".cts",".mjs",".cjs",".py",".go",".rb",".java",".kt",".rs",".cpp",".cc",".c",".cs",".php",".swift",".lua",".ex",".exs",".vue",".svelte"}
if ext in SRC_EXT:
    print("prod"); sys.exit(0)
print("skip")
' "$_TDD_FILE" 2>/dev/null)"
    case "${_TDD_KIND:-skip}" in
      test)
        _SCRIPT_DIR_TDD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        [ -f "$_SCRIPT_DIR_TDD/lib/mcl-state.sh" ] && source "$_SCRIPT_DIR_TDD/lib/mcl-state.sh" 2>/dev/null
        command -v mcl_audit_log >/dev/null 2>&1 && mcl_audit_log "tdd-test-write" "post-tool" "file=${_TDD_FILE}"
        ;;
      prod)
        _SCRIPT_DIR_TDD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        [ -f "$_SCRIPT_DIR_TDD/lib/mcl-state.sh" ] && source "$_SCRIPT_DIR_TDD/lib/mcl-state.sh" 2>/dev/null
        command -v mcl_audit_log >/dev/null 2>&1 && mcl_audit_log "tdd-prod-write" "post-tool" "file=${_TDD_FILE}"
        ;;
    esac
  fi
fi

# UI flow re-evaluation (since v10.1.11) — when ui_flow_active=false
# but a Write/Edit creates a UI-pattern file (HTML/CSS/JS in public/,
# EJS/HBS/Pug/Twig template anywhere, root *.html), bump
# ui_flow_active=true. Catches sessions where the project started
# bare (autodetect correctly returned false at session_start) but a
# UI surface emerged mid-session — the grom backoffice case where
# autodetect ran on an empty repo and never re-evaluated after the
# model wrote 29 prod files including public/js/*, views/*.ejs.
if printf '%s' "$TOOL_NAME_POST" | grep -qE '^(Write|Edit|MultiEdit|NotebookEdit)$' 2>/dev/null; then
  _UI_RE_PATH="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    tin = obj.get("tool_input") or {}
    print(tin.get("file_path") or tin.get("notebook_path") or "")
except Exception:
    pass
' 2>/dev/null)"
  if [ -n "$_UI_RE_PATH" ]; then
    _SCRIPT_DIR_UI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _STATE_LIB_UI="$_SCRIPT_DIR_UI/lib/mcl-state.sh"
    if [ -f "$_STATE_LIB_UI" ]; then
      source "$_STATE_LIB_UI" 2>/dev/null
      _UI_NOW="$(mcl_state_get ui_flow_active 2>/dev/null)"
      if [ "$_UI_NOW" = "false" ]; then
        case "$_UI_RE_PATH" in
          */public/*.html|*/public/*.css|*/public/*.js|\
*/public/*/*.html|*/public/*/*.css|*/public/*/*.js|\
*/views/*.ejs|*/views/*.hbs|*/views/*.pug|*/views/*.twig|\
*/views/*.html|*/views/*/*.ejs|*/views/*/*.hbs|*/views/*/*.html|\
*.ejs|*.hbs|*.pug|*.twig|\
*/templates/*.html|*/templates/*.ejs)
            mcl_state_set ui_flow_active true >/dev/null 2>&1 || true
            mcl_audit_log "ui-flow-reevaluated" "post-tool" "trigger=${_UI_RE_PATH##*/} prev=false now=true"
            [ -f "$_SCRIPT_DIR_UI/lib/mcl-trace.sh" ] && source "$_SCRIPT_DIR_UI/lib/mcl-trace.sh" 2>/dev/null
            command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append ui_flow_reevaluated "${_UI_RE_PATH##*/}"
            ;;
        esac
      fi
    fi
  fi
fi

# Track last write timestamp for Regression Guard smart-skip staleness check.
if printf '%s' "$TOOL_NAME_POST" | grep -qE '^(Write|Edit|MultiEdit|NotebookEdit)$' 2>/dev/null; then
  _SCRIPT_DIR_WT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _STATE_LIB_WT="$_SCRIPT_DIR_WT/lib/mcl-state.sh"
  if [ -f "$_STATE_LIB_WT" ]; then
    source "$_STATE_LIB_WT" 2>/dev/null
    mcl_state_init 2>/dev/null || true
    _WT_NOW="$(date +%s 2>/dev/null || echo 0)"
    mcl_state_set last_write_ts "$_WT_NOW" >/dev/null 2>&1 || true
  fi
fi
if [ "$TOOL_NAME_POST" = "Bash" ]; then
  TOOL_OUTPUT="$(printf '%s' "$RAW_INPUT" | python3 -c '
import json,sys
try:
    obj = json.loads(sys.stdin.read())
    out = obj.get("tool_response","") or obj.get("output","") or ""
    print(str(out)[:200])
except: pass
' 2>/dev/null)"
  if printf '%s' "$TOOL_OUTPUT" | grep -q "✅ Tests: GREEN"; then
    _SCRIPT_DIR_PT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _STATE_LIB_PT="$_SCRIPT_DIR_PT/lib/mcl-state.sh"
    if [ -f "$_STATE_LIB_PT" ]; then
      source "$_STATE_LIB_PT" 2>/dev/null
      mcl_state_init 2>/dev/null || true
      _RG_WAS="$(mcl_state_get regression_block_active 2>/dev/null)"
      if [ "$_RG_WAS" = "true" ]; then
        mcl_state_set regression_block_active false >/dev/null 2>&1 || true
        mcl_state_set regression_output '""' >/dev/null 2>&1 || true
        mcl_audit_log "regression-guard-cleared" "mcl-post-tool.sh" "tests-green"
        [ -f "$_SCRIPT_DIR_PT/lib/mcl-trace.sh" ] && source "$_SCRIPT_DIR_PT/lib/mcl-trace.sh" 2>/dev/null
        command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append regression_cleared
      fi
    fi
  fi
fi

exit 0
