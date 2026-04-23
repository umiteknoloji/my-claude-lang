#!/bin/bash
# MCL PostToolUse Hook — log each tool call to the active session diary.
# One Turkish sentence + estimated token cost per tool call.

set -u

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

exit 0
