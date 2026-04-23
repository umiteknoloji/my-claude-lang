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
# Output: a single JSON object on stdout with fields:
#   {
#     "intent":    "spec-approve" | "summary-confirm" | "ui-review" | "other",
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

import hashlib
import json
import re
import sys

PREFIX_RE = re.compile(r"^MCL\s+[0-9]+\.[0-9]+\.[0-9]+\s*\|\s*(.+)$", re.DOTALL)

SPEC_APPROVE_TOKENS = [
    "approve this spec", "approve the spec",
    "spec\u0027i onayl",
    "spec\u2019i onayl",
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
    r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?\U0001F4CB[ \t]+Spec:",
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


def _classify_intent(question_body_lower):
    for tok in SPEC_APPROVE_TOKENS:
        if tok in question_body_lower:
            return "spec-approve"
    for tok in SUMMARY_CONFIRM_TOKENS:
        if tok in question_body_lower:
            return "summary-confirm"
    for tok in UI_REVIEW_TOKENS:
        if tok in question_body_lower:
            return "ui-review"
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


def scan(path):
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
    for tid in reversed(order):
        use = tool_uses.get(tid)
        res = tool_results.get(tid)
        if not use or not res:
            continue
        m = PREFIX_RE.match(use["question"].strip())
        if not m:
            continue
        body_lower = m.group(1).lower()
        intent = _classify_intent(body_lower)
        res_norm = res.strip()
        for opt in use.get("options", []):
            if opt and opt in res_norm:
                selected = opt
                break
        if not selected:
            selected = res_norm.splitlines()[0].strip() if res_norm else ""
        break

    spec_hash = _compute_spec_hash(last_spec_text)
    return {"intent": intent, "selected": selected, "spec_hash": spec_hash}


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"intent": "", "selected": "", "spec_hash": ""}))
        return 0
    path = sys.argv[1]
    result = scan(path)
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
