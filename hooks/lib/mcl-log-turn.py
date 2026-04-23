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

    turn_tok = usage_tokens(usages[-1])
    cumulative = sum(usage_tokens(u) for u in usages)
    remaining = max(0, CONTEXT_LIMIT - cumulative)

    def fmt(n: int) -> str:
        return f"{n:,}".replace(",", ".")

    print(
        f"Bu tur tamamlandı. | "
        f"Tur: {fmt(turn_tok)} token | "
        f"Toplam: {fmt(cumulative)} token | "
        f"Kalan: {fmt(remaining)} / 200.000"
    )
except Exception:
    pass
