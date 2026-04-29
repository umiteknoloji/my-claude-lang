#!/usr/bin/env python3
"""MCL UI Tokens — design token detector.

C3 hybrid: project'te token dosyası varsa onları parse, yoksa MCL default.

Sources detected:
  - tailwind.config.js / .ts / .cjs / .mjs    (theme.colors, theme.spacing, etc.)
  - :root { --color-x: ... } in CSS files     (CSS custom properties)
  - design-tokens.json                        (W3C draft format)
  - theme.ts / theme.js (default export)      (loose regex extraction)

Returns dict:
  {
    "source": "tailwind|css-vars|theme-ts|design-tokens|mcl-default",
    "colors": [hex/rgb strings],
    "spacing": [px/rem values as strings],
    "font_sizes": [px/rem values],
    "breakpoints": [px values]
  }

Since 8.9.0.
"""
from __future__ import annotations
import json
import re
from pathlib import Path

# MCL default fallback set (8px grid spacing, Tailwind-ish 50-900 colors, type ramp)
MCL_DEFAULT = {
    "source": "mcl-default",
    "colors": [],  # Empty — accept any color when no project tokens defined
    "spacing": ["0", "2px", "4px", "8px", "12px", "16px", "20px", "24px", "32px",
                "40px", "48px", "64px", "80px", "96px", "128px",
                "0rem", "0.125rem", "0.25rem", "0.5rem", "0.75rem", "1rem",
                "1.25rem", "1.5rem", "2rem", "2.5rem", "3rem", "4rem", "5rem", "6rem", "8rem"],
    "font_sizes": ["12px", "14px", "16px", "18px", "20px", "24px", "30px", "36px", "48px", "60px",
                   "0.75rem", "0.875rem", "1rem", "1.125rem", "1.25rem", "1.5rem",
                   "1.875rem", "2.25rem", "3rem", "3.75rem"],
    "breakpoints": ["640px", "768px", "1024px", "1280px", "1536px"],
}


def _read(p: Path) -> str:
    try:
        return p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def _parse_tailwind(text: str) -> dict | None:
    """Extract theme.colors/spacing/fontSize/screens from tailwind config."""
    # Loose JS-like regex (not a real JS parser).
    out = {"colors": [], "spacing": [], "font_sizes": [], "breakpoints": []}
    # Colors: capture hex/rgb literals inside theme.extend.colors / theme.colors blocks.
    for m in re.finditer(r"['\"](#[0-9a-fA-F]{3,8}|rgb\([^)]+\))['\"]", text):
        out["colors"].append(m.group(1).lower())
    # Spacing/fontSize: capture string values like '0.5rem' / '12px'.
    for m in re.finditer(r"spacing\s*:\s*\{([^}]+)\}", text, re.DOTALL):
        for v in re.findall(r"['\"]([0-9.]+(?:px|rem|em))['\"]", m.group(1)):
            out["spacing"].append(v)
    for m in re.finditer(r"fontSize\s*:\s*\{([^}]+)\}", text, re.DOTALL):
        for v in re.findall(r"['\"]([0-9.]+(?:px|rem|em))['\"]", m.group(1)):
            out["font_sizes"].append(v)
    for m in re.finditer(r"screens\s*:\s*\{([^}]+)\}", text, re.DOTALL):
        for v in re.findall(r"['\"]([0-9]+px)['\"]", m.group(1)):
            out["breakpoints"].append(v)
    if any(out.values()):
        out["source"] = "tailwind"
        return out
    return None


def _parse_css_vars(text: str) -> dict | None:
    if ":root" not in text and ":host" not in text:
        return None
    out = {"colors": [], "spacing": [], "font_sizes": [], "breakpoints": []}
    for m in re.finditer(r"--([\w-]+)\s*:\s*([^;]+);", text):
        name, val = m.group(1).lower(), m.group(2).strip()
        if "color" in name or re.match(r"#[0-9a-f]{3,8}|rgb\(|hsl\(", val):
            out["colors"].append(val)
        elif "space" in name or "spacing" in name or "gap" in name:
            out["spacing"].append(val)
        elif "font-size" in name or "text-" in name:
            out["font_sizes"].append(val)
        elif "breakpoint" in name or "screen" in name:
            out["breakpoints"].append(val)
    if any(out.values()):
        out["source"] = "css-vars"
        return out
    return None


def _parse_design_tokens_json(text: str) -> dict | None:
    try:
        data = json.loads(text)
    except Exception:
        return None
    out = {"colors": [], "spacing": [], "font_sizes": [], "breakpoints": []}

    def walk(node, prefix=""):
        if isinstance(node, dict):
            if "$value" in node:
                v = str(node["$value"])
                t = (node.get("$type") or prefix or "").lower()
                if "color" in t:
                    out["colors"].append(v.lower())
                elif "dimension" in t or "spacing" in t:
                    out["spacing"].append(v)
                elif "fontsize" in t or "typography" in t:
                    out["font_sizes"].append(v)
                return
            for k, vv in node.items():
                walk(vv, prefix=k)

    walk(data)
    if any(out.values()):
        out["source"] = "design-tokens"
        return out
    return None


def detect(project_dir: Path) -> dict:
    """Detect tokens; returns combined dict (source field indicates origin)."""
    # 1) Tailwind config
    for name in ("tailwind.config.js", "tailwind.config.ts", "tailwind.config.cjs", "tailwind.config.mjs"):
        f = project_dir / name
        if f.exists():
            r = _parse_tailwind(_read(f))
            if r:
                return _enrich(r)
    # 2) design-tokens.json
    f = project_dir / "design-tokens.json"
    if f.exists():
        r = _parse_design_tokens_json(_read(f))
        if r:
            return _enrich(r)
    # 3) CSS custom properties — scan top-level CSS files (limit depth/count)
    css_text = []
    for ext in ("css", "scss"):
        for p in list(project_dir.rglob(f"*.{ext}"))[:30]:
            if any(x in str(p) for x in ("/node_modules/", "/dist/", "/build/", "/.next/")):
                continue
            css_text.append(_read(p))
    if css_text:
        r = _parse_css_vars("\n".join(css_text))
        if r:
            return _enrich(r)
    # 4) theme.ts / theme.js loose extraction
    for name in ("theme.ts", "theme.js", "src/theme.ts", "src/theme.js"):
        f = project_dir / name
        if f.exists():
            r = _parse_tailwind(_read(f))  # reuse tailwind regex (literal string-ish)
            if r:
                r["source"] = "theme-ts"
                return _enrich(r)
    # 5) MCL default
    return MCL_DEFAULT


def _enrich(r: dict) -> dict:
    """Ensure all keys present + dedupe."""
    for k in ("colors", "spacing", "font_sizes", "breakpoints"):
        r[k] = sorted(set(r.get(k, [])))
    return r


if __name__ == "__main__":
    import sys
    pd = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    print(json.dumps(detect(pd), indent=2))
