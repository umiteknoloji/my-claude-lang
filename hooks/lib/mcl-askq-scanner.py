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

# 10.0.1: Token sets reduced to TR + EN only (the only two languages MCL
# officially supports). All other-language scaffolding removed.
SPEC_APPROVE_TOKENS = [
    # Retained for backward compat with legacy transcripts. 10.0.0 removed
    # the spec-approve askq mechanism — tokens stay so old transcripts
    # don't break the scanner contract, but the hook no longer transitions
    # state on this intent.
    "approve this spec",
    "approve the spec",
    "spec'i onayl",
    "spec’i onayl",
    "spec onay",
]

SUMMARY_CONFIRM_TOKENS = [
    "is this correct",
    "is this summary correct",
    "summary correct",
    "özet doğru",
    "doğru mu",
]

UI_REVIEW_TOKENS = [
    # 10.0.0 Phase 2 DESIGN_REVIEW askq body tokens (TR + EN).
    "tasarımı onayl",
    "tasarım onay",
    "tasarimi onayl",
    "approve this design",
    "approve the design",
    "design approval",
    "review the design",
    # Legacy aliases (kept for old transcript replay)
    "ui review",
    "review the ui",
    "proceed to backend",
    "ui incele",
    "backend'e geç",
    "backend’e geç",
    "arka uca",
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
