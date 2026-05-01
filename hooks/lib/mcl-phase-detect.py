#!/usr/bin/env python3
"""MCL phase-detection helper (since 8.19.0).

Reads a Claude Code transcript JSONL file and infers state values that
skill prose Bash was supposed to write (but the model often omits in
practice — see audit telemetry from 8.10.0-8.17.0). Output is a flat
JSON object on stdout that mcl-stop.sh consumes for hook-level
fallback population — fields ALREADY set in state.json are not
overwritten (idempotency is enforced by the caller).

Usage:
    python3 mcl-phase-detect.py <transcript_path>

Output schema (any field may be null):
    {
        "phase1_intent":          "<one-line EN summary>",
        "phase1_constraints":     "<one-line EN CSV>",
        "phase1_stack_declared":  "tag1,tag2,tag3",
        "phase1_ops":             {...} | null,
        "phase1_perf":            {...} | null,
        "ui_sub_phase_signal":    "UI_REVIEW" | null,
        "phase4_overrides":     [{...}, ...] | null,
    }

Sources, in order of preference:
    1. Engineering Brief block in the most recent assistant turn
       (`<details>...🔄 Engineering Brief [EN]...</details>` —
       structured Task/Requirements/Success criteria/Context lines).
    2. `<mcl_state_emit kind="...">PAYLOAD</mcl_state_emit>` markers
       anywhere in the most recent assistant turn (kind-specific
       payloads, JSON or string).

Best-effort: any parse failure yields null for the affected field; the
helper never raises non-zero. The caller (mcl-stop.sh) treats missing
fields as "skill prose did the write" or "feature absent this turn".
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path
from typing import Any


# Stack tag inference — keyword patterns mapped to canonical tags from
# mcl-state.sh:_MCL_KNOWN_STACK_TAGS. Matched case-insensitively against
# the brief Context/Constraints body. Order does not matter; output is
# a deduplicated CSV.
STACK_KEYWORD_MAP: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\breact\b", re.I),                         "react-frontend"),
    (re.compile(r"\bvue(\.js)?\b", re.I),                    "vue-frontend"),
    (re.compile(r"\bsvelte(kit)?\b", re.I),                  "svelte-frontend"),
    (re.compile(r"\bnext\.?js\b", re.I),                     "react-frontend"),
    (re.compile(r"\bnuxt\b", re.I),                          "vue-frontend"),
    (re.compile(r"\btypescript\b|\bts\b", re.I),             "typescript"),
    (re.compile(r"\bjavascript\b|\bes6\b", re.I),            "javascript"),
    (re.compile(r"\bpython\b|\bfastapi\b|\bdjango\b|\bflask\b", re.I), "python"),
    (re.compile(r"\bjava\b(?!script)", re.I),                "java"),
    (re.compile(r"\bkotlin\b", re.I),                        "java"),  # JVM family
    (re.compile(r"\bspring(\s*boot)?\b", re.I),              "java"),
    (re.compile(r"\bgo(?:lang)?\b", re.I),                   "go"),
    (re.compile(r"\brust\b|\bcargo\b", re.I),                "rust"),
    (re.compile(r"\bruby\b|\brails\b|\bsinatra\b", re.I),    "ruby"),
    (re.compile(r"\bphp\b|\blaravel\b|\bsymfony\b", re.I),   "php"),
    (re.compile(r"\bc#\b|\bdotnet\b|\basp\.?net\b", re.I),   "csharp"),
    (re.compile(r"\bpostgres(ql)?\b", re.I),                 "db-postgres"),
    (re.compile(r"\bmysql\b|\bmariadb\b", re.I),             "db-mysql"),
    (re.compile(r"\bsqlite\b", re.I),                        "db-sqlite"),
    (re.compile(r"\bmongo(db)?\b", re.I),                    "db-mongo"),
    (re.compile(r"\bredis\b", re.I),                         "db-redis"),
    (re.compile(r"\bdynamo(db)?\b", re.I),                   "db-dynamodb"),
    (re.compile(r"\bbigquery\b", re.I),                      "db-bigquery"),
    (re.compile(r"\bsnowflake\b", re.I),                     "db-snowflake"),
    (re.compile(r"\bprisma\b", re.I),                        "orm-prisma"),
    (re.compile(r"\bsqlalchemy\b", re.I),                    "orm-sqlalchemy"),
    (re.compile(r"\btypeorm\b", re.I),                       "orm-typeorm"),
    (re.compile(r"\bsequelize\b", re.I),                     "orm-sequelize"),
    (re.compile(r"\bgorm\b", re.I),                          "orm-gorm"),
]


# Fields recognized inside the Engineering Brief body. The active brief
# format (mcl-activate.sh STATIC_CONTEXT) uses Task/Requirements/Success
# criteria/Context; the extended format in
# skills/.../phase1-5-engineering-brief.md uses Goal/Actor/Constraints/
# Success criteria/Out of scope. Both are recognized.
INTENT_KEYS = ("Task", "Goal", "Objective")
CONSTRAINTS_KEYS = ("Requirements", "Constraints")
CONTEXT_KEYS = ("Context", "Out of scope", "Out_of_scope", "Actor")


def _last_assistant_text(transcript_path: str) -> str:
    """Concatenate text content of the most recent assistant message.

    Returns "" if no assistant messages or transcript unreadable.
    """
    last_text: str = ""
    try:
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
                if not isinstance(msg, dict):
                    continue
                if msg.get("role") != "assistant":
                    continue
                content = msg.get("content")
                pieces: list[str] = []
                if isinstance(content, str):
                    pieces.append(content)
                elif isinstance(content, list):
                    for item in content:
                        if isinstance(item, dict) and item.get("type") == "text":
                            t = item.get("text") or ""
                            if isinstance(t, str):
                                pieces.append(t)
                if pieces:
                    last_text = "\n".join(pieces)
    except OSError:
        return ""
    return last_text


def _extract_brief(text: str) -> str | None:
    """Pull the Engineering Brief block out of an assistant text.

    Looks for `<details>...🔄 Engineering Brief...</details>` first
    (the canonical wrapping); falls back to a `[ENGINEERING BRIEF` /
    `[MCL TRANSLATOR PASS` line marker if the wrapper is absent.
    """
    if not text:
        return None
    # Wrapped form (collapsible details).
    m = re.search(
        r"<details[^>]*>\s*<summary>[^<]*Engineering Brief[^<]*</summary>(.*?)</details>",
        text,
        re.DOTALL | re.IGNORECASE,
    )
    if m:
        return m.group(1)
    # Unwrapped form — STATIC_CONTEXT style.
    m = re.search(
        r"\[(?:MCL TRANSLATOR PASS|ENGINEERING BRIEF)[^\]]*\](.*?)(?=\n\n[A-Z一-鿿À-ſ]|\Z)",
        text,
        re.DOTALL,
    )
    if m:
        return m.group(0)
    return None


def _extract_field(brief: str, keys: tuple[str, ...]) -> str | None:
    """Return the value of the first matching `<Key>:` line in the brief.

    Value is everything from the colon to the next field-style line or
    end of brief. Stripped, single-line-flattened.
    """
    if not brief:
        return None
    keys_re = "|".join(re.escape(k) for k in keys)
    pat = re.compile(
        rf"^\s*(?:{keys_re})\s*:\s*(.+?)(?=^\s*[A-Z][A-Za-z _-]{{0,30}}\s*:\s|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    m = pat.search(brief)
    if not m:
        return None
    val = m.group(1).strip()
    # Collapse whitespace; trim trailing markdown noise.
    val = re.sub(r"\s+", " ", val).strip()
    val = val.rstrip(",.; ")
    return val or None


def _infer_stack(blob: str) -> str | None:
    """Scan freeform text for known stack keywords; return CSV of tags."""
    if not blob:
        return None
    seen: list[str] = []
    for pat, tag in STACK_KEYWORD_MAP:
        if pat.search(blob) and tag not in seen:
            seen.append(tag)
    return ",".join(seen) if seen else None


def _extract_markers(text: str) -> dict[str, Any]:
    """Pull `<mcl_state_emit kind="K">PAYLOAD</mcl_state_emit>` blocks.

    Returns a dict keyed by `kind` with parsed payloads. JSON-shaped
    payloads are parsed; anything else is left as a stripped string.
    Multiple markers with the same kind: last one wins, except for
    `phase4-override` which accumulates into a list.
    """
    out: dict[str, Any] = {}
    overrides: list[Any] = []
    if not text:
        return out
    pat = re.compile(
        r"<mcl_state_emit\s+kind=\"([^\"]+)\">(.*?)</mcl_state_emit>",
        re.DOTALL,
    )
    for kind, payload in pat.findall(text):
        payload = payload.strip()
        parsed: Any = payload
        if payload.startswith(("{", "[")):
            try:
                parsed = json.loads(payload)
            except Exception:
                parsed = payload  # keep as string for forensic
        if kind == "phase4-override":
            overrides.append(parsed)
        else:
            out[kind] = parsed
    if overrides:
        out["phase4-override"] = overrides
    return out


def detect(transcript_path: str) -> dict[str, Any]:
    """Run the full detection pass; return result dict (all keys present)."""
    result: dict[str, Any] = {
        "phase1_intent": None,
        "phase1_constraints": None,
        "phase1_stack_declared": None,
        "phase1_ops": None,
        "phase1_perf": None,
        "ui_sub_phase_signal": None,
        "phase4_overrides": None,
    }
    if not transcript_path or not Path(transcript_path).exists():
        return result

    text = _last_assistant_text(transcript_path)

    # Brief-driven Phase 1 fields.
    brief = _extract_brief(text)
    if brief:
        result["phase1_intent"] = _extract_field(brief, INTENT_KEYS)
        result["phase1_constraints"] = _extract_field(brief, CONSTRAINTS_KEYS)
        # Stack inference: scan brief body in full (Constraints + Context).
        result["phase1_stack_declared"] = _infer_stack(brief)

    # Marker-driven fields (override or supplement brief).
    markers = _extract_markers(text)
    if "phase1-7-ops" in markers:
        v = markers["phase1-7-ops"]
        result["phase1_ops"] = v if isinstance(v, dict) else None
    if "phase1-7-perf" in markers:
        v = markers["phase1-7-perf"]
        result["phase1_perf"] = v if isinstance(v, dict) else None
    if "ui-sub-phase" in markers:
        v = markers["ui-sub-phase"]
        if isinstance(v, str) and v.strip() in ("UI_REVIEW", "BACKEND"):
            result["ui_sub_phase_signal"] = v.strip()
    if "phase4-override" in markers:
        v = markers["phase4-override"]
        if isinstance(v, list) and v:
            result["phase4_overrides"] = v

    return result


# --- 9.1.0 hook-first additions ----------------------------------------
# Three narrow detection helpers used by mcl-stop.sh fallback paths.
# Each runs in its own --mode so callers don't pay for a full detect()
# when only one fact is needed.

# Phase 5 verification report headers across the 14 supported MCL
# locales. Kept in sync with skills/.../phase5-5-localize-report.md and
# the mcl-stop.sh:1769 trigger fallback regex. Single source-of-truth
# would be a constants module — deferred to 9.2 (see CHANGELOG limits).
_P5V_HEADERS = [
    "Verification Report",
    "Doğrulama Raporu",
    "Rapport de Vérification",
    "Verifizierungsbericht",
    "Informe de Verificación",
    "検証レポート",
    "검증 보고서",
    "验证报告",
    "تقرير التحقق",
    "דוח אימות",
    "सत्यापन रिपोर्ट",
    "Laporan Verifikasi",
    "Relatório de Verificação",
    "Отчёт о проверке",
]
_P5V_RE = re.compile(
    r"^\s*(?:#+\s+|━+\s*\n\s*)?(?:" +
    "|".join(re.escape(h) for h in _P5V_HEADERS) +
    r")\b",
    re.MULTILINE,
)

# `[assumed: ...]` and `[unspecified: ...]` markers. Phase 1.7 skill
# prose mandates these inside the spec body for SILENT-ASSUME and
# SKIP-MARK classifications respectively.
_ASSUMED_RE = re.compile(r"\[assumed:[^\]]*\]")
_UNSPEC_RE = re.compile(r"\[unspecified:[^\]]*\]")

# Last-assistant-text patterns indicating a UI build is done and
# review-ready. Conservative — needs BOTH a localhost URL AND at least
# one localized "browser-opened" cue OR a Bash dev-server invocation.
_UI_LOCALHOST_RE = re.compile(r"\bhttps?://(?:localhost|127\.0\.0\.1)(?::\d+)?", re.I)
_UI_OPENED_PROSE_RE = re.compile(
    r"(UI hazır|UI ready|UI açıld|UI launched|browser|tarayıcı|ブラウザ|"
    r"navigate to|open .* in your browser|otevř|brauseri|abriendo)",
    re.I,
)


def detect_spec_markers(transcript_path: str) -> dict[str, Any]:
    """Count `[assumed: ...]` and `[unspecified: ...]` markers in the spec.

    Returns {"assumed_count": int, "unspecified_count": int}. Counts the
    LAST assistant text containing a `📋 Spec:` block — falls back to
    full last-assistant text if no spec block is found (so a brief-only
    or pre-spec turn yields 0/0 rather than crashing).
    """
    out = {"assumed_count": 0, "unspecified_count": 0}
    if not transcript_path or not Path(transcript_path).exists():
        return out
    text = _last_assistant_text(transcript_path)
    if not text:
        return out
    # Prefer the spec body if present (most accurate scope); fall back
    # to the full last-assistant text.
    spec_match = re.search(
        r"📋\s*Spec:.*",
        text,
        re.DOTALL,
    )
    body = spec_match.group(0) if spec_match else text
    out["assumed_count"] = len(_ASSUMED_RE.findall(body))
    out["unspecified_count"] = len(_UNSPEC_RE.findall(body))
    return out


def detect_ui_review_signal(transcript_path: str) -> dict[str, Any]:
    """Heuristic: is the most-recent assistant turn signaling that the
    UI is built and ready for review?

    Conservative — both signals required:
      - localhost URL pattern in the assistant text, AND
      - a "browser-opened" / "UI ready" prose cue in any of the
        supported locales

    Returns {"ui_review_signal": bool}.
    """
    out = {"ui_review_signal": False}
    if not transcript_path or not Path(transcript_path).exists():
        return out
    text = _last_assistant_text(transcript_path)
    if not text:
        return out
    if _UI_LOCALHOST_RE.search(text) and _UI_OPENED_PROSE_RE.search(text):
        out["ui_review_signal"] = True
    return out


def detect_phase5_verify(transcript_path: str) -> dict[str, Any]:
    """Detect a Phase 5 Verification Report header in the most-recent
    assistant turn (any of 14 supported locales).

    Returns {"phase5_verify_detected": bool, "header_match": str|None}.
    Used by mcl-stop.sh to auto-emit the `phase5-verify` audit when the
    skill prose Bash was not invoked.
    """
    out: dict[str, Any] = {"phase5_verify_detected": False, "header_match": None}
    if not transcript_path or not Path(transcript_path).exists():
        return out
    text = _last_assistant_text(transcript_path)
    if not text:
        return out
    m = _P5V_RE.search(text)
    if m:
        out["phase5_verify_detected"] = True
        out["header_match"] = m.group(0).strip().lstrip("#").strip()
    return out


def main() -> int:
    # 9.1.0: --mode flag selects a narrow detection. Default mode (no
    # flag, or `--mode=full`) preserves the pre-9.1.0 behavior so
    # existing callers (mcl-stop.sh state-population block) keep working.
    args = sys.argv[1:]
    mode = "full"
    transcript_path = None
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--mode" and i + 1 < len(args):
            mode = args[i + 1]
            i += 2
            continue
        if a.startswith("--mode="):
            mode = a.split("=", 1)[1]
            i += 1
            continue
        if transcript_path is None:
            transcript_path = a
        i += 1

    if not transcript_path:
        print("{}")
        return 0

    try:
        if mode == "spec-markers":
            print(json.dumps(detect_spec_markers(transcript_path)))
        elif mode == "ui-review-signal":
            print(json.dumps(detect_ui_review_signal(transcript_path)))
        elif mode == "phase5-verify-detected":
            print(json.dumps(detect_phase5_verify(transcript_path)))
        else:
            # full mode — pre-9.1.0 behavior
            result = detect(transcript_path)
            print(json.dumps(result))
    except Exception:
        # Fail-open: emit a mode-appropriate empty shell. Caller treats
        # missing/null fields as "skip" — never as a write trigger.
        if mode == "spec-markers":
            print(json.dumps({"assumed_count": 0, "unspecified_count": 0}))
        elif mode == "ui-review-signal":
            print(json.dumps({"ui_review_signal": False}))
        elif mode == "phase5-verify-detected":
            print(json.dumps({"phase5_verify_detected": False, "header_match": None}))
        else:
            print(json.dumps({k: None for k in (
                "phase1_intent", "phase1_constraints", "phase1_stack_declared",
                "phase1_ops", "phase1_perf", "ui_sub_phase_signal",
                "phase4_overrides",
            )}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
