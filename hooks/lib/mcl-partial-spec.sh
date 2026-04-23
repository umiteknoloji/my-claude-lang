#!/bin/bash
# MCL Partial Spec Detection — inspect the last assistant turn in a
# transcript and determine whether a `📋 Spec:` block is structurally
# complete (all seven required section headers present) or truncated
# mid-emission (e.g., by a rate-limit interruption).
#
# Required headers (presence-only; empty bodies are legitimate):
#   Objective, MUST, SHOULD, Acceptance Criteria, Edge Cases,
#   Technical Approach, Out of Scope
#
# CLI:
#   bash ~/.claude/hooks/lib/mcl-partial-spec.sh check <transcript_path>
#
# Exit codes:
#   0  — spec block present but one or more required headers missing
#        (stdout: newline-separated list of missing header names)
#   1  — spec block present and structurally complete
#   2  — no `📋 Spec:` marker in last assistant turn (nothing to check)
#
# Diagnostics (e.g., unreadable transcript) go to stderr with exit 2.
# The caller treats exit 2 as "not a spec turn" either way — this is a
# defense helper, not a validation gate.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -z "${SCRIPT_DIR:-}" ]; then
  echo "mcl-partial-spec: cannot locate own directory" >&2
  exit 2
fi

_mcl_partial_spec_check() {
  local transcript="$1"
  python3 - "$transcript" <<'PY'
import json, sys, re

path = sys.argv[1]

def extract_text(msg):
    if isinstance(msg, dict) and "message" in msg and isinstance(msg["message"], dict):
        msg = msg["message"]
    if not isinstance(msg, dict):
        return None
    if msg.get("role") != "assistant":
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

# Since 6.5.5: select the most recent assistant text that CONTAINS a
# `📋 Spec:` block, not the most recent text overall. Mirrors the fix
# in hooks/mcl-stop.sh — trailing narration in a spec-bearing turn
# (e.g. spec + "Kodu yazıyorum") must not hide the spec from partial
# detection.
spec_line_re = re.compile(
    r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?\U0001F4CB[ \t]+Spec:",
    re.MULTILINE,
)

last_text = None
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
                last_text = text
except Exception:
    sys.exit(2)

if not last_text:
    sys.exit(2)

lines = last_text.splitlines()
start = None
for i, ln in enumerate(lines):
    if spec_line_re.match(ln):
        start = i
        break
if start is None:
    sys.exit(2)

body = "\n".join(lines[start:])

required = [
    "Objective",
    "MUST",
    "SHOULD",
    "Acceptance Criteria",
    "Edge Cases",
    "Technical Approach",
    "Out of Scope",
]

missing = []
for name in required:
    esc = re.escape(name)
    pattern = re.compile(
        r"(?im)^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?(?:[*_]{1,2})?" + esc + r"(?:[*_]{1,2})?[ \t]*:?",
    )
    if not pattern.search(body):
        missing.append(name)

if missing:
    sys.stdout.write("\n".join(missing))
    sys.exit(0)
sys.exit(1)
PY
}

if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
  case "${1:-}" in
    check)
      if [ -z "${2:-}" ] || [ ! -f "${2:-}" ]; then
        echo "mcl-partial-spec: missing or unreadable transcript path" >&2
        exit 2
      fi
      _mcl_partial_spec_check "$2"
      ;;
    *)
      echo "usage: $(basename "$0") check <transcript_path>" >&2
      exit 2
      ;;
  esac
fi
