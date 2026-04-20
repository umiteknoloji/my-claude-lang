#!/bin/bash
# MCL Stop Hook — parse Claude's final assistant message, detect the
# `📋 Spec:` block, compute sha256 over a normalized body, and update
# `.mcl/state.json` accordingly.
#
# Transitions driven here (v1):
#   - phase 1 → 2 (SPEC_REVIEW)      : first time a spec block appears
#   - no-op                          : same spec emitted again (same hash)
#   - drift_detected=true flag       : different hash appears while
#                                      spec_approved=true (v2 will act on it)
#
# Never regresses phase. Never overwrites an approved spec's hash.
# Stop hook input: JSON on stdin with `transcript_path` (Claude Code's
# jsonl transcript for the current session).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mcl-state.sh
source "$SCRIPT_DIR/lib/mcl-state.sh"

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

# Parse the transcript: find the last assistant message, extract its
# text content, locate the `📋 Spec:` block (bounded by the next
# markdown heading `^#...` or EOF), normalize, sha256.
# Output to stdout: a single hex digest if a spec block was found,
# otherwise nothing.
SPEC_HASH="$(python3 -c '
import json, sys, hashlib, re

path = sys.argv[1]

def extract_text(msg):
    # Handle both {"message": {...}} wrappers and flat {role, content}.
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
            if text:
                last_text = text
except Exception:
    sys.exit(0)

if not last_text:
    sys.exit(0)

# Spec block: from first line matching `📋 Spec:` up to next markdown
# heading (^#) on its own line, or EOF. Keep the header line in the body.
lines = last_text.splitlines()
start = None
for i, ln in enumerate(lines):
    if ln.lstrip().startswith("📋 Spec:"):
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

# Normalize: strip trailing whitespace per line, collapse consecutive
# blank lines, trim leading/trailing blanks.
normalized = []
prev_blank = False
for ln in body_lines:
    ln = ln.rstrip()
    is_blank = (ln == "")
    if is_blank and prev_blank:
        continue
    normalized.append(ln)
    prev_blank = is_blank
# Trim leading/trailing blanks
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

# Detect the approval marker — a line matching exactly
# `^\s*✅\s*MCL\s+APPROVED\s*$` in the last assistant message. Strict
# line-anchor + whole-line match avoids rhetorical false positives.
APPROVAL_MARKER="$(python3 -c '
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
            if text:
                last_text = text
except Exception:
    sys.exit(0)

if not last_text:
    sys.exit(0)

pattern = re.compile(r"^[ \t]*\u2705[ \t]*MCL[ \t]+APPROVED[ \t]*$", re.MULTILINE)
if pattern.search(last_text):
    print("1")
' "$TRANSCRIPT_PATH" 2>/dev/null)"

# If neither spec nor marker present, nothing to do.
if [ -z "$SPEC_HASH" ] && [ -z "$APPROVAL_MARKER" ]; then
  exit 0
fi

# Apply transitions to state.json.
mcl_state_init
CURRENT_PHASE="$(mcl_state_get current_phase)"
CURRENT_HASH="$(mcl_state_get spec_hash)"
SPEC_APPROVED="$(mcl_state_get spec_approved)"
# Capture drift state BEFORE the spec-hash block potentially mutates it.
# Drift re-approval must only fire when drift pre-existed this turn — a
# turn that emits both new-spec AND marker together would otherwise
# bypass developer review.
PRE_DRIFT_DETECTED="$(mcl_state_get drift_detected)"

# --- Spec-hash transitions (only when a fresh spec is in this turn) ---
if [ -n "$SPEC_HASH" ]; then
  case "$CURRENT_PHASE" in
    1)
      mcl_state_set current_phase 2
      mcl_state_set phase_name '"SPEC_REVIEW"'
      mcl_state_set spec_hash "\"$SPEC_HASH\""
      mcl_debug_log "stop" "transition-1-to-2" "hash=${SPEC_HASH:0:12}"
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
      if [ "$SPEC_APPROVED" = "true" ] && [ -n "$CURRENT_HASH" ] && [ "$CURRENT_HASH" != "$SPEC_HASH" ]; then
        mcl_state_set drift_detected true
        mcl_state_set drift_hash "\"$SPEC_HASH\""
        mcl_debug_log "stop" "drift-detected" "approved=${CURRENT_HASH:0:12} new=${SPEC_HASH:0:12}"
      else
        mcl_debug_log "stop" "post-approval-noop" "phase=${CURRENT_PHASE} hash=${SPEC_HASH:0:12}"
      fi
      ;;
  esac
fi

# --- Approval-marker transition (Domino 4) ---
# Marker only lifts the gate when:
#   - marker matched in the last assistant message
#   - current_phase in {2,3} (SPEC_REVIEW or USER_VERIFY — approval-ready)
#   - a spec_hash is already recorded (something real to approve)
# Any other combination is a no-op. Fires AFTER the spec-hash block so
# that phase 1→2 in the same turn still gets advanced to 4 if the
# marker also appeared (rare but possible on the very first spec turn).
if [ -n "$APPROVAL_MARKER" ]; then
  # Re-read phase in case the spec-hash block just advanced 1→2.
  CURRENT_PHASE="$(mcl_state_get current_phase)"
  CURRENT_HASH="$(mcl_state_get spec_hash)"
  SPEC_APPROVED="$(mcl_state_get spec_approved)"
  if [ "$PRE_DRIFT_DETECTED" = "true" ] && [ -n "$SPEC_HASH" ]; then
    # Drift re-approval: developer re-emitted a spec (original, divergent, or
    # new) and issued the marker AFTER MCL LOCK engaged in a prior turn.
    # Gated on PRE_DRIFT_DETECTED so a single turn that simultaneously drifts
    # AND emits the marker cannot self-approve — developer must see the lock
    # at least once before re-approval counts.
    mcl_state_set spec_hash "\"$SPEC_HASH\""
    mcl_state_set drift_detected false
    mcl_state_set drift_hash null
    mcl_audit_log "drift-reapproved" "stop" "prior=${CURRENT_HASH:0:12} new=${SPEC_HASH:0:12}"
    mcl_debug_log "stop" "drift-reapproved" "prior=${CURRENT_HASH:0:12} new=${SPEC_HASH:0:12} phase=${CURRENT_PHASE}"
  elif [ "$SPEC_APPROVED" = "true" ] || [ "$CURRENT_PHASE" -ge 4 ] 2>/dev/null; then
    mcl_debug_log "stop" "marker-idempotent" "phase=${CURRENT_PHASE} approved=${SPEC_APPROVED}"
  elif [ -z "$CURRENT_HASH" ]; then
    mcl_debug_log "stop" "marker-ignored-no-spec" "phase=${CURRENT_PHASE}"
  elif [ "$CURRENT_PHASE" = "2" ] || [ "$CURRENT_PHASE" = "3" ]; then
    mcl_state_set spec_approved true
    mcl_state_set current_phase 4
    mcl_state_set phase_name '"EXECUTE"'
    mcl_debug_log "stop" "marker-approve" "hash=${CURRENT_HASH:0:12} phase=${CURRENT_PHASE}->4"
  else
    mcl_debug_log "stop" "marker-ignored-wrong-phase" "phase=${CURRENT_PHASE}"
  fi
fi

exit 0
