#!/bin/bash
# MCL Stop Hook — parse Claude's final assistant message, detect the
# `📋 Spec:` block, compute sha256 over a normalized body, and update
# `.mcl/state.json` accordingly.
#
# Transitions driven here:
#   - phase 1 → 2 (SPEC_REVIEW)      : first time a spec block appears
#   - phase 2/3 → 4 (EXECUTE)        : AskUserQuestion spec-approval call
#                                      returned an "Approve" family option
#   - drift_detected=true flag       : different hash appears while
#                                      spec_approved=true (warn-only in
#                                      PreToolUse; visible in activate
#                                      hook DRIFT_NOTICE)
#   - drift_detected=false           : developer reverted to the approved
#                                      body (hash equals stored spec_hash)
#                                      OR re-approved via AskUserQuestion
#
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
# shellcheck source=lib/mcl-state.sh
source "$SCRIPT_DIR/lib/mcl-state.sh"
# shellcheck source=lib/mcl-trace.sh
[ -f "$SCRIPT_DIR/lib/mcl-trace.sh" ] && source "$SCRIPT_DIR/lib/mcl-trace.sh"

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
PARTIAL_MISSING="$(bash "$SCRIPT_DIR/lib/mcl-partial-spec.sh" check "$TRANSCRIPT_PATH" 2>/dev/null)"
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

# --- AskUserQuestion approval scanner (replaces marker regex in 6.0.0) ---
# Scan the transcript for the most recent AskUserQuestion tool_use/tool_result
# pair whose question begins with "MCL {version} | ". Emit a pipe-separated
# record on stdout:
#   <semantic_intent>|<selected_option>
# where semantic_intent is one of:
#   spec-approve      — Phase 3 spec approval
#   summary-confirm   — Phase 1 summary confirmation (no state mutation here)
#   other             — recognized MCL question but not a state-transitioning one
# and selected_option is the raw option string picked by the developer
# (or empty if cancelled).
ASKQ_RECORD="$(python3 -c '
import json, sys, re

path = sys.argv[1]

PREFIX_RE = re.compile(r"^MCL\s+[0-9]+\.[0-9]+\.[0-9]+\s*\|\s*(.+)$", re.DOTALL)

# Semantic intent detectors: lowercase substring match on question body.
# English + major MCL languages. The skill file enumerates the exact
# canonical strings; these regexes are a superset so localization drift
# does not break detection.
SPEC_APPROVE_TOKENS = [
    "approve this spec", "approve the spec",
    "spec\u0027i onayl",    # tr: ASCII apostrophe
    "spec\u2019i onayl",    # tr: curly apostrophe
    "spec onay",
    "aprobar esta spec", "aprueba este spec",
    "approuver ce spec", "approuver cette sp",
    "genehmigen sie diese spec",
    "\u3053\u306e\u30b9\u30da\u30c3\u30af\u3092\u627f\u8a8d",
    "\uc2a4\ud399\uc744 \uc2b9\uc778",
    "\u6279\u51c6\u6b64\u89c4\u8303",
    "\u0627\u0644\u0645\u0648\u0627\u0641\u0642\u0629 \u0639\u0644\u0649 \u0647\u0630\u0647 \u0627\u0644\u0645\u0648\u0627\u0635\u0641\u0627\u062a",
    "\u05d0\u05e9\u05e8 \u05d0\u05ea \u05d4\u05de\u05e4\u05e8\u05d8",
    "\u0907\u0938 \u0938\u094d\u092a\u0947\u0915 \u0915\u094b \u0938\u094d\u0935\u0940\u0915\u093e\u0930",
    "setujui spec ini",
    "aprovar este spec",
    "\u043e\u0434\u043e\u0431\u0440\u0438\u0442\u044c \u044d\u0442\u043e\u0442 \u0441\u043f\u0435\u043a",
]

SUMMARY_CONFIRM_TOKENS = [
    # English
    "is this correct",
    "is this summary correct",
    "summary correct",
    # Turkish — accept both "bu özet doğru" and the shorter
    # "özet doğru" / "doğru mu" variants that drift in the wild.
    "\u00f6zet do\u011fru",     # "özet doğru"
    "do\u011fru mu",             # "doğru mu"
    # Spanish — "es" (sometimes spelled "és") + correcto variants
    "\u00e8s esto correcto",
    "es correcto",
    "resumen correcto",
    # French
    "r\u00e9sum\u00e9 est-il correct",
    "est-il correct",
    "r\u00e9sum\u00e9 correct",
    # German
    "zusammenfassung korrekt",
    "ist das korrekt",
    # Japanese
    "\u8981\u7d04\u306f\u6b63\u3057\u3044",   # 要約は正しい
    "\u6b63\u3057\u3044\u3067\u3059\u304b",  # 正しいですか
    # Korean
    "\uc694\uc57d\uc774 \ub9de",              # 요약이 맞
    "\ub9de\uc2b5\ub2c8\uae4c",               # 맞습니까
    # Chinese
    "\u6458\u8981\u662f\u5426\u6b63\u786e",   # 摘要是否正确
    "\u6b63\u786e\u5417",                     # 正确吗
    # Arabic
    "\u0647\u0644 \u0647\u0630\u0627 \u0635\u062d\u064a\u062d",  # هل هذا صحيح
    "\u0627\u0644\u0645\u0644\u062e\u0635 \u0635\u062d\u064a\u062d", # الملخص صحيح
    # Hebrew
    "\u05d4\u05d0\u05dd \u05d6\u05d4 \u05e0\u05db\u05d5\u05df",   # האם זה נכון
    "\u05d4\u05e1\u05d9\u05db\u05d5\u05dd \u05e0\u05db\u05d5\u05df", # הסיכום נכון
    # Hindi
    "\u0915\u094d\u092f\u093e \u092f\u0939 \u0938\u0939\u0940",     # क्या यह सही
    "\u0938\u093e\u0930\u093e\u0902\u0936 \u0938\u0939\u0940",     # सारांश सही
    # Indonesian
    "apakah ini benar",
    "ringkasan benar",
    # Portuguese
    "est\u00e1 correto",
    "resumo est\u00e1 correto",
    # Russian
    "\u044d\u0442\u043e \u043f\u0440\u0430\u0432\u0438\u043b\u044c\u043d\u043e",  # это правильно
    "\u0440\u0435\u0437\u044e\u043c\u0435 \u043f\u0440\u0430\u0432\u0438\u043b\u044c\u043d\u043e",  # резюме правильно
]

# UI_REVIEW_TOKENS: detect Phase 4b review question body.
# Canonical anchor per skill file is "UI review" (en) or the localized
# equivalent per language. Lowercased substring match with generous
# drift tolerance. The skill enumerates canonical strings; this is a
# superset so localization drift does not break detection.
UI_REVIEW_TOKENS = [
    "ui review",
    "review the ui",
    "proceed to backend",
    "ui incele",            # tr
    "backend\u0027e ge\u00e7",
    "backend\u2019e ge\u00e7",
    "arka uca",
    "revisi\u00f3n de ui",  # es
    "pasar a backend",
    "revue ui",             # fr
    "examiner l\u0027ui",
    "passer au backend",
    "ui-\u00fcberpr\u00fcfung",  # de
    "ui \u00fcberpr\u00fcfen",
    "zum backend",
    "ui \u30ec\u30d3\u30e5\u30fc",  # ja
    "\u30d0\u30c3\u30af\u30a8\u30f3\u30c9\u3078",
    "ui \u691c\u53ce",              # ko
    "\ubc31\uc5d4\ub4dc\ub85c",
    "ui \u5ba1\u67e5",              # zh
    "\u8f6c\u5230\u540e\u7aef",
    "\u0645\u0631\u0627\u062c\u0639\u0629 \u0627\u0644\u0648\u0627\u062c\u0647\u0629",  # ar
    "\u0627\u0644\u0627\u0646\u062a\u0642\u0627\u0644 \u0625\u0644\u0649 \u0627\u0644\u062e\u0644\u0641\u064a\u0629",
    "\u05e1\u05e7\u05d9\u05e8\u05ea \u05de\u05de\u05e9\u05e7",  # he
    "\u05de\u05e2\u05d1\u05e8 \u05dc\u05d1\u05d0\u05e7\u05d0\u05e0\u05d3",
    "ui \u0938\u092e\u0940\u0915\u094d\u0937\u093e",           # hi
    "\u092c\u0948\u0915\u090f\u0902\u0921 \u092a\u0930",
    "tinjauan ui",           # id
    "lanjut ke backend",
    "revis\u00e3o de ui",    # pt
    "ir para backend",
    "\u043f\u0440\u043e\u0432\u0435\u0440\u043a\u0430 ui",  # ru
    "\u043f\u0435\u0440\u0435\u0439\u0442\u0438 \u043a \u0431\u044d\u043a\u0435\u043d\u0434\u0443",
]

def extract_message(obj):
    if isinstance(obj, dict) and "message" in obj and isinstance(obj["message"], dict):
        return obj["message"]
    return obj if isinstance(obj, dict) else None

# Collect AskUserQuestion tool_use + paired tool_result.
tool_uses = {}      # tool_use_id -> {question, options}
tool_results = {}   # tool_use_id -> raw content string
order = []          # preserve tool_use order for "most recent"

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
            msg = extract_message(obj)
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
                if role == "assistant" and t == "tool_use" and item.get("name") == "AskUserQuestion":
                    tid = item.get("id") or ""
                    inp = item.get("input") or {}
                    q = ""
                    opts = []
                    if isinstance(inp, dict):
                        questions = inp.get("questions")
                        first = None
                        if isinstance(questions, list) and questions and isinstance(questions[0], dict):
                            first = questions[0]
                        elif isinstance(inp.get("question"), str):
                            first = inp
                        if isinstance(first, dict):
                            q = first.get("question") or ""
                            raw_opts = first.get("options") or []
                            if isinstance(raw_opts, list):
                                for o in raw_opts:
                                    if isinstance(o, str):
                                        opts.append(o)
                                    elif isinstance(o, dict):
                                        lbl = o.get("label") or o.get("option") or o.get("text") or ""
                                        if lbl:
                                            opts.append(lbl)
                    if tid:
                        tool_uses[tid] = {"question": q, "options": opts}
                        order.append(tid)
                elif role == "user" and t == "tool_result":
                    tid = item.get("tool_use_id") or ""
                    if not tid:
                        continue
                    raw = item.get("content")
                    text = ""
                    if isinstance(raw, str):
                        text = raw
                    elif isinstance(raw, list):
                        parts = []
                        for sub in raw:
                            if isinstance(sub, dict):
                                if sub.get("type") == "text" and isinstance(sub.get("text"), str):
                                    parts.append(sub["text"])
                        text = "\n".join(parts)
                    tool_results[tid] = text
except Exception:
    sys.exit(0)

# Find the most recent MCL-prefixed AskUserQuestion with a paired tool_result.
record = None
for tid in reversed(order):
    use = tool_uses.get(tid)
    res = tool_results.get(tid)
    if not use:
        continue
    if not res:
        # Skip still-unanswered askq so the scanner descends to the
        # most-recent *answered* one. Prevents summary-confirm approval
        # loss when spec-approve is emitted in the same turn.
        continue
    m = PREFIX_RE.match(use["question"].strip())
    if not m:
        continue
    body = m.group(1).lower()
    # Decide semantic intent.
    intent = "other"
    for tok in SPEC_APPROVE_TOKENS:
        if tok in body:
            intent = "spec-approve"
            break
    if intent == "other":
        for tok in SUMMARY_CONFIRM_TOKENS:
            if tok in body:
                intent = "summary-confirm"
                break
    if intent == "other":
        for tok in UI_REVIEW_TOKENS:
            if tok in body:
                intent = "ui-review"
                break
    # Extract selected option from tool_result. The tool_result payload
    # format varies; we search for the first option label that appears
    # as a substring, else fall back to the raw text.
    selected = ""
    if res:
        res_norm = res.strip()
        for opt in use.get("options", []):
            if opt and opt in res_norm:
                selected = opt
                break
        if not selected:
            selected = res_norm.splitlines()[0].strip() if res_norm else ""
    record = f"{intent}|{selected}"
    break

if record:
    print(record)
' "$TRANSCRIPT_PATH" 2>/dev/null)"

ASKQ_INTENT=""
ASKQ_SELECTED=""
if [ -n "$ASKQ_RECORD" ]; then
  ASKQ_INTENT="${ASKQ_RECORD%%|*}"
  ASKQ_SELECTED="${ASKQ_RECORD#*|}"
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

# If neither spec nor AskUserQuestion approval present, nothing to do.
if [ -z "$SPEC_HASH" ] && [ -z "$ASKQ_INTENT" ]; then
  exit 0
fi

mcl_state_init
CURRENT_PHASE="$(mcl_state_get current_phase)"
CURRENT_HASH="$(mcl_state_get spec_hash)"
SPEC_APPROVED="$(mcl_state_get spec_approved)"
PRE_DRIFT_DETECTED="$(mcl_state_get drift_detected)"

# --- Spec-hash transitions (when a fresh spec is in this turn) ---
if [ -n "$SPEC_HASH" ]; then
  case "$CURRENT_PHASE" in
    1)
      mcl_state_set current_phase 2
      mcl_state_set phase_name '"SPEC_REVIEW"'
      mcl_state_set spec_hash "\"$SPEC_HASH\""
      mcl_debug_log "stop" "transition-1-to-2" "hash=${SPEC_HASH:0:12}"
      command -v mcl_trace_append >/dev/null 2>&1 && mcl_trace_append phase_transition 1 2
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
      if [ "$SPEC_APPROVED" = "true" ] && [ -n "$CURRENT_HASH" ]; then
        if [ "$CURRENT_HASH" = "$SPEC_HASH" ]; then
          # Same body as the approved spec — if drift was flagged, clear.
          if [ "$PRE_DRIFT_DETECTED" = "true" ]; then
            mcl_state_set drift_detected false
            mcl_state_set drift_hash null
            mcl_audit_log "drift-reverted" "stop" "hash=${SPEC_HASH:0:12}"
            mcl_debug_log "stop" "drift-reverted" "hash=${SPEC_HASH:0:12}"
          else
            mcl_debug_log "stop" "post-approval-noop" "phase=${CURRENT_PHASE} hash=${SPEC_HASH:0:12}"
          fi
        else
          mcl_state_set drift_detected true
          mcl_state_set drift_hash "\"$SPEC_HASH\""
          mcl_debug_log "stop" "drift-detected" "approved=${CURRENT_HASH:0:12} new=${SPEC_HASH:0:12}"
        fi
      else
        mcl_debug_log "stop" "post-approval-noop" "phase=${CURRENT_PHASE} hash=${SPEC_HASH:0:12}"
      fi
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
  elif [ "$PRE_DRIFT_DETECTED" = "true" ] && [ -n "$CURRENT_HASH" ]; then
    # Drift re-approval via AskUserQuestion: the recorded spec_hash was
    # just updated above if a new spec was emitted this turn; clear drift.
    mcl_state_set drift_detected false
    mcl_state_set drift_hash null
    mcl_audit_log "drift-reapproved" "stop" "hash=${CURRENT_HASH:0:12} via=askuserquestion"
    mcl_debug_log "stop" "drift-reapproved" "hash=${CURRENT_HASH:0:12}"
    bash "$SCRIPT_DIR/lib/mcl-spec-save.sh" "$TRANSCRIPT_PATH" "$CURRENT_HASH" 2>/dev/null || true
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
    SPEC_INTENT_SCANNER="$SCRIPT_DIR/lib/mcl-spec-ui-intent.py"
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
    bash "$SCRIPT_DIR/lib/mcl-spec-save.sh" "$TRANSCRIPT_PATH" "$CURRENT_HASH" 2>/dev/null || true
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

exit 0
