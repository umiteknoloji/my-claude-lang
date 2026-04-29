#!/usr/bin/env python3
"""MCL Perf Rules (8.14.0) — 3 rule packs (bundle / cwv / image), 11 rules.

8.13.0 MON metrics (server observability) ile çakışmaz: 8.14.0 client-side
runtime perf. category=perf-bundle | perf-cwv | perf-image ayrım.
"""
from __future__ import annotations
from dataclasses import dataclass, asdict
from pathlib import Path


@dataclass
class Finding:
    severity: str
    source: str         # generic | delegate
    rule_id: str
    file: str
    line: int
    message: str
    category: str = ""  # perf-bundle | perf-cwv | perf-image
    autofix: str | None = None

    def to_dict(self) -> dict:
        return asdict(self)


# ============================================================
# Bundle (4 rule)
# ============================================================

def bundle_rules(metrics: dict, config: dict) -> list[Finding]:
    """Inputs: metrics={total_gzip_bytes, files: [...], output_dir, found}.
       config={bundle_budget_kb, bundle_critical_multiplier}."""
    out: list[Finding] = []
    budget_bytes = config.get("bundle_budget_kb", 200) * 1024
    critical_mult = config.get("bundle_critical_multiplier", 2)
    if not metrics.get("found"):
        out.append(Finding(
            severity="LOW", source="generic", rule_id="PRF-B03-bundle-no-build-output",
            file=metrics.get("checked_dirs", "?"), line=0, category="perf-bundle",
            message="No build output found (dist/, build/, .next/static/chunks/, out/). Run `npm run build` before scan to measure bundle size.",
        ))
        return out
    total = metrics.get("total_gzip_bytes", 0)
    if total > budget_bytes * critical_mult:
        out.append(Finding(
            severity="HIGH", source="delegate", rule_id="PRF-B01-bundle-over-budget-critical",
            file=metrics.get("output_dir", "?"), line=0, category="perf-bundle",
            message=f"Bundle gzipped JS = {total/1024:.1f} KB, > {critical_mult}× budget ({budget_bytes/1024:.0f} KB). Critical. Code-split / lazy-load / drop deps.",
        ))
    elif total > budget_bytes:
        out.append(Finding(
            severity="MEDIUM", source="delegate", rule_id="PRF-B02-bundle-over-budget",
            file=metrics.get("output_dir", "?"), line=0, category="perf-bundle",
            message=f"Bundle gzipped JS = {total/1024:.1f} KB, over budget {budget_bytes/1024:.0f} KB ({100*total/budget_bytes:.0f}%). Investigate top chunks.",
        ))
    # Top-3 chunks > 50KB advisory
    big_files = [f for f in metrics.get("files", []) if f.get("gzip_size", 0) > 50 * 1024]
    if big_files:
        top = sorted(big_files, key=lambda f: -f.get("gzip_size", 0))[0]
        out.append(Finding(
            severity="LOW", source="delegate", rule_id="PRF-B04-large-chunk",
            file=top.get("path", "?"), line=0, category="perf-bundle",
            message=f"Largest chunk {top.get('path', '?')}: {top.get('gzip_size', 0)/1024:.1f} KB gzip. Consider splitting.",
        ))
    return out


# ============================================================
# CWV (4 rule)
# ============================================================

def cwv_rules(metrics: dict, config: dict) -> list[Finding]:
    """metrics from lighthouse: {lcp_ms, cls, tbt_ms, tti_ms} or {} when skipped."""
    out: list[Finding] = []
    if not metrics.get("ran"):
        return out
    url = metrics.get("url", "?")
    lcp = metrics.get("lcp_ms")
    cls = metrics.get("cls")
    tbt = metrics.get("tbt_ms")
    lcp_high = config.get("lcp_high_ms", 4000)
    lcp_med = config.get("lcp_medium_ms", 2500)
    cls_high = config.get("cls_high", 0.25)
    tbt_high = config.get("tbt_high_ms", 600)
    if lcp is not None:
        if lcp > lcp_high:
            out.append(Finding(severity="HIGH", source="delegate", rule_id="PRF-C01-lcp-poor",
                               file=url, line=0, category="perf-cwv",
                               message=f"LCP {lcp:.0f} ms > {lcp_high} ms. Largest contentful paint poor — fix render-blocking resources, image LCP, server response."))
        elif lcp > lcp_med:
            out.append(Finding(severity="MEDIUM", source="delegate", rule_id="PRF-C02-lcp-needs-improvement",
                               file=url, line=0, category="perf-cwv",
                               message=f"LCP {lcp:.0f} ms in {lcp_med}-{lcp_high} ms range. Optimize hero image / font loading / SSR."))
    if cls is not None and cls > cls_high:
        out.append(Finding(severity="MEDIUM", source="delegate", rule_id="PRF-C03-cls-poor",
                           file=url, line=0, category="perf-cwv",
                           message=f"CLS {cls:.3f} > {cls_high}. Layout shifts during load — reserve space for images/ads/embeds."))
    if tbt is not None and tbt > tbt_high:
        out.append(Finding(severity="MEDIUM", source="delegate", rule_id="PRF-C04-tbt-poor",
                           file=url, line=0, category="perf-cwv",
                           message=f"TBT {tbt:.0f} ms > {tbt_high} ms (FID/INP proxy). Long main-thread tasks — defer scripts, code-split."))
    return out


# ============================================================
# Image (3 rule)
# ============================================================

ASSET_DIRS = ("public", "static", "assets", "src/assets", "app/static")
IMG_EXTS = {".png", ".jpg", ".jpeg"}


def image_rules(project_dir: Path, config: dict) -> list[Finding]:
    out: list[Finding] = []
    high_kb = config.get("image_high_kb", 500)
    med_kb = config.get("image_medium_kb", 100)
    png_webp_kb = 50
    seen = []
    for d in ASSET_DIRS:
        p = project_dir / d
        if not p.is_dir():
            continue
        for img in p.rglob("*"):
            if img.suffix.lower() not in IMG_EXTS:
                continue
            try:
                size_b = img.stat().st_size
            except OSError:
                continue
            seen.append((img, size_b))
    for img, size_b in seen:
        size_kb = size_b / 1024
        rel = str(img.relative_to(project_dir))
        if size_kb > high_kb:
            out.append(Finding(severity="HIGH", source="generic", rule_id="PRF-I01-image-huge",
                               file=rel, line=0, category="perf-image",
                               message=f"{rel} is {size_kb:.0f} KB > {high_kb} KB. Compress + convert to WebP/AVIF — blocks page load."))
        elif size_kb > med_kb:
            out.append(Finding(severity="MEDIUM", source="generic", rule_id="PRF-I02-image-large",
                               file=rel, line=0, category="perf-image",
                               message=f"{rel} is {size_kb:.0f} KB. Compress / serve responsive sizes / consider WebP."))
        if img.suffix.lower() == ".png" and size_kb > png_webp_kb:
            webp = img.with_suffix(".webp")
            avif = img.with_suffix(".avif")
            if not webp.exists() and not avif.exists():
                out.append(Finding(severity="LOW", source="generic", rule_id="PRF-I03-png-no-webp-fallback",
                                   file=rel, line=0, category="perf-image",
                                   message=f"{rel} ({size_kb:.0f} KB PNG) has no WebP/AVIF sibling. Add a modern-format fallback."))
    return out


# ============================================================
# Public API
# ============================================================

def scan(project_dir: Path, bundle_metrics: dict, cwv_metrics: dict, config: dict) -> list[Finding]:
    findings: list[Finding] = []
    findings.extend(bundle_rules(bundle_metrics, config))
    findings.extend(cwv_rules(cwv_metrics, config))
    findings.extend(image_rules(project_dir, config))
    return findings


def all_rule_ids() -> list[str]:
    return ["PRF-B01-bundle-over-budget-critical", "PRF-B02-bundle-over-budget",
            "PRF-B03-bundle-no-build-output", "PRF-B04-large-chunk",
            "PRF-C01-lcp-poor", "PRF-C02-lcp-needs-improvement",
            "PRF-C03-cls-poor", "PRF-C04-tbt-poor",
            "PRF-I01-image-huge", "PRF-I02-image-large", "PRF-I03-png-no-webp-fallback"]


def rules_version_seed() -> str:
    return "|".join(all_rule_ids()) + "\n---\n" + Path(__file__).read_text(encoding="utf-8")
