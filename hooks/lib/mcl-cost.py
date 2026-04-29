#!/usr/bin/env python3
"""MCL token & cost accounting report.

Usage: python3 mcl-cost.py <project_dir>
Output: markdown-formatted report to stdout.
"""
import json
import os
import re
import sys
from pathlib import Path

# Claude Sonnet 4.6 pricing (USD per million tokens, 2026)
PRICE_INPUT        = 3.00
PRICE_CACHE_WRITE  = 3.75
PRICE_CACHE_READ   = 0.30
PRICE_OUTPUT       = 15.00

CHARS_PER_TOKEN    = 4  # rough estimate

def fmt_tok(n):
    return f"{n:,.0f}".replace(",", ".")

def fmt_usd(x):
    if x < 0.001:
        return f"< $0.001"
    return f"${x:.4f}"

def load_cost_json(mcl_dir):
    path = mcl_dir / "cost.json"
    if not path.is_file():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data.get("turns", [])
    except Exception:
        return []

def parse_log_turns(mcl_dir):
    """Return list of (tur_tokens, bagnam_tokens) from latest log file."""
    log_dir = mcl_dir / "log"
    if not log_dir.is_dir():
        return []
    files = sorted(log_dir.glob("*.md"))
    if not files:
        return []
    latest = files[-1]
    turns = []
    pattern = re.compile(r"Tur: ([\d.]+) token \| Ba[gğ]lam: ([\d.]+) /")
    for line in latest.read_text(encoding="utf-8", errors="replace").splitlines():
        m = pattern.search(line)
        if m:
            tur = int(m.group(1).replace(".", ""))
            ctx = int(m.group(2).replace(".", ""))
            turns.append((tur, ctx))
    return turns

def main():
    project_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    # Since 8.5.0: prefer MCL_STATE_DIR env var (set by mcl-claude
    # wrapper to ~/.mcl/projects/<key>/state). Fall back to legacy
    # in-project .mcl/ for users still on the pre-8.5 install.
    state_dir_env = os.environ.get("MCL_STATE_DIR")
    if state_dir_env:
        mcl_dir = Path(state_dir_env)
    else:
        mcl_dir = project_dir / ".mcl"

    injection_turns = load_cost_json(mcl_dir)
    log_turns = parse_log_turns(mcl_dir)

    lines = []
    lines.append("## MCL Token & Maliyet Raporu\n")

    # --- Injection overhead ---
    if injection_turns:
        chars = [t["chars"] for t in injection_turns]
        avg_chars = sum(chars) / len(chars)
        est_tok = avg_chars / CHARS_PER_TOKEN
        n = len(chars)
        total_est = est_tok * n

        lines.append("### MCL Injection Overhead (per-turn)")
        lines.append(f"  Tur sayısı (bu oturum): {n}")
        lines.append(f"  Ortalama injection: ~{avg_chars:,.0f} karakter → ~{fmt_tok(est_tok)} token")
        lines.append(f"  Toplam tahmini overhead: ~{fmt_tok(est_tok)} × {n} = ~{fmt_tok(total_est)} token")
        lines.append("")

        # Pricing breakdown
        cache_write = (est_tok / 1_000_000) * PRICE_CACHE_WRITE
        cache_reads = ((est_tok * max(0, n - 1)) / 1_000_000) * PRICE_CACHE_READ
        total_mcl_cost = cache_write + cache_reads

        lines.append("### MCL Maliyet Tahmini (Sonnet 4.6)")
        lines.append(f"  Cache write (ilk tur): ~{fmt_tok(est_tok)} tok × ${PRICE_CACHE_WRITE}/MTok = {fmt_usd(cache_write)}")
        if n > 1:
            lines.append(f"  Cache read  ({n-1} tur): ~{fmt_tok(est_tok * (n-1))} tok × ${PRICE_CACHE_READ}/MTok = {fmt_usd(cache_reads)}")
        lines.append(f"  MCL toplam ek maliyet: {fmt_usd(total_mcl_cost)}")
        lines.append("")
        lines.append("  Cache verimliliği: STATIC_CONTEXT ilk turda yazılır ($3.75/MTok),")
        lines.append(f"  sonraki turlarda %90 daha ucuz okunur ($0.30/MTok).")
        lines.append("")
    else:
        lines.append("### MCL Injection Overhead")
        lines.append("  Henüz veri yok — injection logging bu oturumda başlamadı.")
        lines.append("  (MCL 7.8.0+ sonrası her turda .mcl/cost.json'a yazılır.)")
        lines.append("")

    # --- Session token summary ---
    if log_turns:
        last_tur, last_ctx = log_turns[-1]
        lines.append("### Oturum Token Özeti (son log'dan)")
        lines.append(f"  Son tur: {fmt_tok(last_tur)} token")
        lines.append(f"  Bağlam:  {fmt_tok(last_ctx)} / 200.000  ({100*last_ctx/200_000:.1f}%)")
        if len(log_turns) > 1:
            total_tur = sum(t for t, _ in log_turns)
            lines.append(f"  Toplam  ({len(log_turns)} tur): {fmt_tok(total_tur)} token")
        lines.append("")
    else:
        lines.append("### Oturum Token Özeti")
        lines.append("  Log bulunamadı (.mcl/log/*.md yok).")
        lines.append("")

    # --- Comparison ---
    if injection_turns and log_turns:
        n = len(injection_turns)
        avg_chars = sum(t["chars"] for t in injection_turns) / n
        est_tok = avg_chars / CHARS_PER_TOKEN
        # Without MCL: same turns but cache_read cost is 0
        # MCL saves by caching; baseline (no cache) would cost est_tok*n at full input price
        no_cache_cost = (est_tok * n / 1_000_000) * PRICE_INPUT
        cache_write = (est_tok / 1_000_000) * PRICE_CACHE_WRITE
        cache_reads = ((est_tok * max(0, n - 1)) / 1_000_000) * PRICE_CACHE_READ
        mcl_cost = cache_write + cache_reads
        delta = mcl_cost - no_cache_cost

        lines.append("### MCL Açık vs Kapalı (tahmini)")
        lines.append(f"  MCL olmadan (uncached input): {fmt_usd(no_cache_cost)}")
        lines.append(f"  MCL ile (cache write + read):  {fmt_usd(mcl_cost)}")
        if delta < 0:
            lines.append(f"  → Cache sayesinde MCL tasarruf sağlar: {fmt_usd(-delta)}")
        else:
            lines.append(f"  → MCL net ek maliyet: {fmt_usd(delta)}")
        lines.append("")

    lines.append("---")
    lines.append("_Not: Token sayıları .mcl/cost.json ve log dosyalarından._")
    lines.append("_Fiyatlar tahmini — gerçek fatura için Claude Console'u kontrol edin._")
    lines.append("_Cost.json sıfırlamak için: `rm .mcl/cost.json`_")

    print("\n".join(lines))

if __name__ == "__main__":
    main()
