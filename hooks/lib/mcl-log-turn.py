#!/usr/bin/env python3
"""Compute per-turn and cumulative token counts from a JSONL transcript.

Output (stdout): one Turkish sentence for the session log, or nothing on error.
"""
import json
import sys

path = sys.argv[1] if len(sys.argv) > 1 else None
if not path:
    sys.exit(0)

CONTEXT_LIMIT = 200_000

try:
    usages = []
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
            if isinstance(msg, dict) and msg.get("role") == "assistant":
                u = msg.get("usage")
                if isinstance(u, dict):
                    usages.append(u)

    if not usages:
        sys.exit(0)

    def usage_tokens(u: dict) -> int:
        return (
            (u.get("input_tokens") or 0)
            + (u.get("output_tokens") or 0)
            + (u.get("cache_creation_input_tokens") or 0)
            + (u.get("cache_read_input_tokens") or 0)
        )

    def input_context(u: dict) -> int:
        # The actual context window occupied = all input-side tokens.
        # cache_read_input_tokens dominates in cached sessions; plain
        # input_tokens alone is only the non-cached slice (typically < 10).
        return (
            (u.get("input_tokens") or 0)
            + (u.get("cache_creation_input_tokens") or 0)
            + (u.get("cache_read_input_tokens") or 0)
        )

    last = usages[-1]
    turn_tok = usage_tokens(last)
    cumulative = sum(usage_tokens(u) for u in usages)
    remaining = max(0, CONTEXT_LIMIT - input_context(last))

    def fmt(n: int) -> str:
        return f"{n:,}".replace(",", ".")

    ctx = input_context(last)
    print(
        f"Bu tur tamamlandı. | "
        f"Tur: {fmt(turn_tok)} token | "
        f"Bağlam: {fmt(ctx)} / 200.000 | "
        f"Kalan: {fmt(remaining)}"
    )
except Exception:
    pass
