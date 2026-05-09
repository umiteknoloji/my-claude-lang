#!/usr/bin/env python3
# MCL shared AskUserQuestion scanner (since 6.5.6).
#
# Extracted from the previously-inline Python block in hooks/mcl-stop.sh
# so both Stop and PreToolUse can classify the latest MCL askq
# tool_use/tool_result pair from the same source of truth. PreToolUse
# uses this to just-in-time advance state when an askq approval exists
# in the transcript but Stop has not yet fired (mid-turn chain:
# askq → spec → askq → Write).
#
# Input:  argv[1] = path to the current session's transcript jsonl.
#         argv[2] (optional, since 8.2.13) = min_ts_epoch (integer or
#                  empty/"null"). When non-zero, transcript entries with
#                  `timestamp` field strictly before this epoch are
#                  treated as stale and skipped. Used by /mcl-restart to
#                  drop pre-restart askq's from the scan.
# Output: a single JSON object on stdout with fields:
#   {
#     "intent":    "spec-approve" | "precision-confirm" | "summary-confirm" | "ui-review" | "other",
#     "selected":  "<developer's selected option label, raw>",
#     "spec_hash": "<sha256 of the latest 📋 Spec: block visible
#                    in the transcript, or empty string>"
#   }
# Empty string fields indicate "not found". Exit code is always 0.
#
# NOTE: spec_hash reflects the transcript's MOST RECENT spec block
# (matching the Stop hook's SPEC_HASH extractor since 6.5.5 — a
# spec-bearing text that has trailing non-spec narration still wins).
# Callers that need askq-vs-spec-body drift detection should compare
# this hash to the state's recorded spec_hash.

import datetime
import hashlib
import json
import re
import sys


def _entry_epoch(obj):
    """Parse the top-level `timestamp` field (ISO-8601 with optional Z)
    into a POSIX epoch float. Returns None when the field is missing or
    unparseable so callers default to "include the entry" (defensive)."""
    ts = obj.get("timestamp")
    if not isinstance(ts, str) or not ts:
        return None
    try:
        s = ts.replace("Z", "+00:00")
        return datetime.datetime.fromisoformat(s).timestamp()
    except Exception:
        return None

PREFIX_RE = re.compile(r"^MCL\s+[0-9]+\.[0-9]+\.[0-9]+\s*\|\s*(.+)$", re.DOTALL)

SPEC_APPROVE_TOKENS = [
    # English (spec / specification)
    "approve this spec", "approve the spec",
    "approve this specification", "approve the specification",
    # Turkish — both "spec" loanword AND native "şartname"
    "spec\u0027i onayl",
    "spec\u2019i onayl",
    "spec onay",
    "şartname\u0027yi onayl",
    "şartname\u2019yi onayl",
    "şartnameyi onayl",
    "şartnameyi onay",
    "şartname onay",
    # Spanish
    "aprobar esta spec", "aprueba este spec",
    "aprobar esta especificaci", "aprueba esta especificaci",
    # French
    "approuver ce spec", "approuver cette sp",
    "approuver cette spécification",
    # German
    "genehmigen sie diese spec",
    "diese spezifikation genehmig",
    # Japanese — スペック + 仕様 (specification)
    "\u3053\u306e\u30b9\u30da\u30c3\u30af\u3092\u627f\u8a8d",
    "\u4ed5\u69d8\u3092\u627f\u8a8d",
    # Korean
    "\uc2a4\ud399\uc744 \uc2b9\uc778",
    "\uba85\uc138\uc11c\ub97c \uc2b9\uc778",
    # Chinese
    "\u6279\u51c6\u6b64\u89c4\u8303",
    "\u6279\u51c6\u8fd9\u4e2a\u89c4\u8303",
    # Arabic
    "\u0627\u0644\u0645\u0648\u0627\u0641\u0642\u0629 \u0639\u0644\u0649 \u0647\u0630\u0647 \u0627\u0644\u0645\u0648\u0627\u0635\u0641\u0627\u062a",
    # Hebrew
    "\u05d0\u05e9\u05e8 \u05d0\u05ea \u05d4\u05de\u05e4\u05e8\u05d8",
    # Hindi
    "\u0907\u0938 \u0938\u094d\u092a\u0947\u0915 \u0915\u094b \u0938\u094d\u0935\u0940\u0915\u093e\u0930",
    # Indonesian
    "setujui spec ini", "setujui spesifikasi",
    # Portuguese
    "aprovar este spec", "aprovar esta especifica",
    # Russian
    "\u043e\u0434\u043e\u0431\u0440\u0438\u0442\u044c \u044d\u0442\u043e\u0442 \u0441\u043f\u0435\u043a",
    "\u043e\u0434\u043e\u0431\u0440\u0438\u0442\u044c \u044d\u0442\u0443 \u0441\u043f\u0435\u0446\u0438\u0444\u0438\u043a\u0430\u0446\u0438\u044e",
]

# Approve-family verbs across 14 supported languages. Used by the
# fallback heuristic when the strict SPEC_APPROVE_TOKENS list misses
# a wording variant (e.g., model writes "Bunu onaylıyor musun?"
# without the literal "spec/şartname" keyword) but a spec block
# exists in the transcript and an approve-family option label was
# selected.
APPROVE_VERBS = [
    # English
    "approve", "confirm", "accept", "proceed",
    # Turkish
    "onayla", "onayl\u0131",
    "evet", "kabul", "tamam",
    # Spanish
    "aprueb", "confirmar", "aceptar",
    # French
    "approuv", "confirmer",
    # German
    "genehmig", "best\u00e4tig",
    # Japanese
    "\u627f\u8a8d", "\u4e86\u89e3", "\u78ba\u8a8d",
    "\u306f\u3044",
    # Korean
    "\uc2b9\uc778", "\ud655\uc778", "\uc608",
    "\ub124",
    # Chinese
    "\u6279\u51c6", "\u786e\u8ba4", "\u662f",
    "\u540c\u610f",
    # Arabic
    "\u0645\u0648\u0627\u0641\u0642", "\u0646\u0639\u0645",
    "\u062a\u0623\u0643\u064a\u062f",
    # Hebrew
    "\u05d0\u05e9\u05e8", "\u05db\u05df", "\u05d0\u05d9\u05e9\u05d5\u05e8",
    # Hindi
    "\u0938\u094d\u0935\u0940\u0915\u093e\u0930",
    "\u0939\u093e\u0901", "\u0939\u093e\u0902",
    # Indonesian
    "setuju", "konfirmasi",
    # Portuguese
    "aprovar", "sim",
    # Russian
    "\u043e\u0434\u043e\u0431\u0440", "\u0434\u0430",
    "\u043f\u043e\u0434\u0442\u0432\u0435\u0440\u0436\u0434",
]

# PRECISION_CONFIRM_TOKENS — added in v10.1.14.
# Aşama 2 (precision audit) closing askq: after the 7-dimension scan +
# any GATE answers, the model emits a closing AskUserQuestion that
# asks the developer to approve the precision-audited intent before
# Aşama 4 (SPEC) emits. Title prefix template:
#
#   MCL <ver> | Faz 2 — Precision-audit niyet onayı: ...   (TR)
#   MCL <ver> | Phase 2 — Precision-audit intent confirmation: ...  (EN)
#
# `Precision-audit` is treated as a fixed MCL technical token across
# all languages (like "MCL", "GATE", "Spec") — same convention used
# in CLAUDE.md for technical-token preservation. The detection token
# combines this anchor with the language-specific "intent/niyet"
# word so the scanner does not mis-match the existing `precision-audit`
# audit name appearing elsewhere in question prose.
PRECISION_CONFIRM_TOKENS = [
    # Turkish (calibration language)
    "precision-audit niyet",
    "precision audit niyet",
    # English
    "precision-audit intent",
    "precision audit intent",
    "precision-audited intent",
    # Spanish
    "precision-audit intención",
    "intención auditada",
    # French
    "precision-audit intention",
    "intention auditée",
    # German
    "precision-audit absicht",
    "auditierte absicht",
    # Japanese
    "precision-audit 意図",
    # Korean
    "precision-audit 의도",
    # Chinese
    "precision-audit 意图",
    # Arabic
    "precision-audit النية",
    # Hebrew
    "precision-audit כוונה",
    # Hindi
    "precision-audit इरादा",
    # Indonesian
    "precision-audit niat",
    # Portuguese
    "precision-audit intenção",
    # Russian
    "precision-audit намерен",
]

SUMMARY_CONFIRM_TOKENS = [
    "is this correct",
    "is this summary correct",
    "summary correct",
    "\u00f6zet do\u011fru",
    "do\u011fru mu",
    "\u00e8s esto correcto",
    "es correcto",
    "resumen correcto",
    "r\u00e9sum\u00e9 est-il correct",
    "est-il correct",
    "r\u00e9sum\u00e9 correct",
    "zusammenfassung korrekt",
    "ist das korrekt",
    "\u8981\u7d04\u306f\u6b63\u3057\u3044",
    "\u6b63\u3057\u3044\u3067\u3059\u304b",
    "\uc694\uc57d\uc774 \ub9de",
    "\ub9de\uc2b5\ub2c8\uae4c",
    "\u6458\u8981\u662f\u5426\u6b63\u786e",
    "\u6b63\u786e\u5417",
    "\u0647\u0644 \u0647\u0630\u0627 \u0635\u062d\u064a\u062d",
    "\u0627\u0644\u0645\u0644\u062e\u0635 \u0635\u062d\u064a\u062d",
    "\u05d4\u05d0\u05dd \u05d6\u05d4 \u05e0\u05db\u05d5\u05df",
    "\u05d4\u05e1\u05d9\u05db\u05d5\u05dd \u05e0\u05db\u05d5\u05df",
    "\u0915\u094d\u092f\u093e \u092f\u0939 \u0938\u0939\u0940",
    "\u0938\u093e\u0930\u093e\u0902\u0936 \u0938\u0939\u0940",
    "apakah ini benar",
    "ringkasan benar",
    "est\u00e1 correto",
    "resumo est\u00e1 correto",
    "\u044d\u0442\u043e \u043f\u0440\u0430\u0432\u0438\u043b\u044c\u043d\u043e",
    "\u0440\u0435\u0437\u044e\u043c\u0435 \u043f\u0440\u0430\u0432\u0438\u043b\u044c\u043d\u043e",
]

UI_REVIEW_TOKENS = [
    "ui review",
    "review the ui",
    "proceed to backend",
    "ui incele",
    "backend\u0027e ge\u00e7",
    "backend\u2019e ge\u00e7",
    "arka uca",
    "revisi\u00f3n de ui",
    "pasar a backend",
    "revue ui",
    "examiner l\u0027ui",
    "passer au backend",
    "ui-\u00fcberpr\u00fcfung",
    "ui \u00fcberpr\u00fcfen",
    "zum backend",
    "ui \u30ec\u30d3\u30e5\u30fc",
    "\u30d0\u30c3\u30af\u30a8\u30f3\u30c9\u3078",
    "ui \u691c\u53ce",
    "\ubc31\uc5d4\ub4dc\ub85c",
    "ui \u5ba1\u67e5",
    "\u8f6c\u5230\u540e\u7aef",
    "\u0645\u0631\u0627\u062c\u0639\u0629 \u0627\u0644\u0648\u0627\u062c\u0647\u0629",
    "\u0627\u0644\u0627\u0646\u062a\u0642\u0627\u0644 \u0625\u0644\u0649 \u0627\u0644\u062e\u0644\u0641\u064a\u0629",
    "\u05e1\u05e7\u05d9\u05e8\u05ea \u05de\u05de\u05e9\u05e7",
    "\u05de\u05e2\u05d1\u05e8 \u05dc\u05d1\u05d0\u05e7\u05d0\u05e0\u05d3",
    "ui \u0938\u092e\u0940\u0915\u094d\u0937\u093e",
    "\u092c\u0948\u0915\u090f\u0902\u0921 \u092a\u0930",
    "tinjauan ui",
    "lanjut ke backend",
    "revis\u00e3o de ui",
    "ir para backend",
    "\u043f\u0440\u043e\u0432\u0435\u0440\u043a\u0430 ui",
    "\u043f\u0435\u0440\u0435\u0439\u0442\u0438 \u043a \u0431\u044d\u043a\u0435\u043d\u0434\u0443",
]

SPEC_LINE_RE = re.compile(
    # Tolerant match: 📋 Spec[ optional-text ]: — accepts forms like
    # "📋 Spec:", "📋 Spec (revised):", "📋 Spec — Web Calculator:".
    # The colon is still required as a body anchor.
    r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?(?:\U0001F4CB[ \t]+)?Spec\b[^\n:]*:",
    re.MULTILINE,
)


def _extract_message(obj):
    if isinstance(obj, dict) and "message" in obj and isinstance(obj["message"], dict):
        return obj["message"]
    return obj if isinstance(obj, dict) else None


def _extract_text(msg):
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


def _has_approve_signal(text_lower):
    """True when text contains any 14-language approve verb."""
    if not text_lower:
        return False
    for verb in APPROVE_VERBS:
        if verb in text_lower:
            return True
    return False


def _classify_intent(question_body_lower, options_lower=None,
                     selected_lower="", has_spec=False):
    """Classify the askq intent.

    Order:
      1. Strict UI review tokens.
      2. Strict spec approve tokens (english/turkish/etc).
      3. Strict precision confirm tokens (Aşama 2 closing askq).
         Checked BEFORE summary-confirm because the precision-audit
         closing question may also contain generic confirm phrasing
         and we want the more specific phase-2 intent to win.
      4. Strict summary confirm tokens (Aşama 1 closing askq).
      5. FALLBACK heuristic — when none of the strict token lists match
         AND a \U0001F4CB Spec block exists in the transcript AND an
         approve-family verb appears in either the question body or a
         user-selected option, classify as `spec-approve`. This catches
         model wording variants like "Şartname yukarıdaki gibi.
         Onaylıyor musun?" that don't carry the literal "spec"
         keyword but are structurally a spec-approve question following
         a spec emit.
      6. FALLBACK for summary-confirm — if no spec exists and an approve
         verb appears, classify as `summary-confirm`.
      7. Else `other`.
    """
    options_lower = options_lower or []

    for tok in UI_REVIEW_TOKENS:
        if tok in question_body_lower:
            return "ui-review"
    for tok in SPEC_APPROVE_TOKENS:
        if tok in question_body_lower:
            return "spec-approve"
    for tok in PRECISION_CONFIRM_TOKENS:
        if tok in question_body_lower:
            return "precision-confirm"
    for tok in SUMMARY_CONFIRM_TOKENS:
        if tok in question_body_lower:
            return "summary-confirm"

    # Fallback heuristic: structural rather than vocabulary-based.
    approve_in_question = _has_approve_signal(question_body_lower)
    approve_in_selected = _has_approve_signal(selected_lower)
    approve_in_any_option = any(_has_approve_signal(o) for o in options_lower)
    has_approve_signal = approve_in_question or approve_in_selected or approve_in_any_option

    if has_approve_signal and has_spec:
        return "spec-approve"
    if has_approve_signal:
        # No spec emitted yet — likely Aşama 1 summary confirm.
        return "summary-confirm"

    return "other"


def _compute_spec_hash(last_spec_text):
    if not last_spec_text:
        return ""
    lines = last_spec_text.splitlines()
    start = None
    for i, ln in enumerate(lines):
        if SPEC_LINE_RE.match(ln):
            start = i
            break
    if start is None:
        return ""
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
        return ""
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def scan(path, min_ts_epoch=0.0):
    tool_uses = {}
    tool_results = {}
    order = []
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
                # Stale-entry filter (since 8.2.13) — when min_ts_epoch is
                # non-zero, drop transcript entries whose timestamp is
                # strictly before the threshold. Used by /mcl-restart so
                # JIT cannot re-promote using a pre-restart askq still in
                # the same-session transcript. Entries without parseable
                # timestamps are kept (defensive: scanner metadata lines).
                if min_ts_epoch:
                    entry_epoch = _entry_epoch(obj)
                    if entry_epoch is not None and entry_epoch < min_ts_epoch:
                        continue
                msg = _extract_message(obj)
                if not isinstance(msg, dict):
                    continue
                role = msg.get("role")
                content = msg.get("content")
                # Spec-bearing assistant text tracking.
                if role == "assistant":
                    text = _extract_text(msg)
                    if text and SPEC_LINE_RE.search(text):
                        last_spec_text = text
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
                        text_val = ""
                        if isinstance(raw, str):
                            text_val = raw
                        elif isinstance(raw, list):
                            parts = []
                            for sub in raw:
                                if isinstance(sub, dict):
                                    if sub.get("type") == "text" and isinstance(sub.get("text"), str):
                                        parts.append(sub["text"])
                            text_val = "\n".join(parts)
                        tool_results[tid] = text_val
    except Exception:
        return {"intent": "", "selected": "", "spec_hash": ""}

    intent = ""
    selected = ""
    last_question_body = ""
    has_spec = last_spec_text is not None
    for tid in reversed(order):
        use = tool_uses.get(tid)
        res = tool_results.get(tid)
        if not use or not res:
            continue
        # PREFIX_RE strict match; if model dropped the prefix, fall back
        # to the raw question text (lowercased). The fallback heuristic
        # in _classify_intent still requires an approve signal + spec
        # context to promote, so this stays safe.
        m = PREFIX_RE.match(use["question"].strip())
        question_body = m.group(1) if m else use["question"]
        body_lower = question_body.lower()
        last_question_body = question_body
        res_norm = res.strip()
        # Selected option resolution (must come before classification so
        # selected-text approve signal feeds the fallback heuristic).
        for opt in use.get("options", []):
            if opt and opt in res_norm:
                selected = opt
                break
        if not selected:
            selected = res_norm.splitlines()[0].strip() if res_norm else ""
        options_lower = [o.lower() for o in use.get("options", []) if isinstance(o, str)]
        intent = _classify_intent(body_lower,
                                  options_lower=options_lower,
                                  selected_lower=selected.lower(),
                                  has_spec=has_spec)
        break

    spec_hash = _compute_spec_hash(last_spec_text)

    # Inline-spec fallback (since v10.1.9). When the classifier reports
    # spec-approve intent but no `\U0001F4CB Spec:` block was found in
    # plain assistant text, the model likely embedded spec content
    # directly inside the askq question body (real-world pattern seen
    # in v10.1.8 deployment). Without a hash, JIT askq advance refuses
    # to fire (requires non-empty spec_hash) → user lockout despite
    # correct intent classification. Fall back to hashing the askq
    # question body itself, prefixed with "inline-" so downstream drift
    # detection can distinguish synthetic from block-derived hashes.
    if intent == "spec-approve" and not spec_hash and last_question_body:
        spec_hash = "inline-" + hashlib.sha256(
            last_question_body.encode("utf-8")
        ).hexdigest()[:12]

    return {"intent": intent, "selected": selected, "spec_hash": spec_hash}


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"intent": "", "selected": "", "spec_hash": ""}))
        return 0
    path = sys.argv[1]
    min_ts_epoch = 0.0
    if len(sys.argv) >= 3:
        raw = (sys.argv[2] or "").strip()
        if raw and raw.lower() != "null":
            try:
                min_ts_epoch = float(raw)
            except Exception:
                min_ts_epoch = 0.0
    result = scan(path, min_ts_epoch=min_ts_epoch)
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
