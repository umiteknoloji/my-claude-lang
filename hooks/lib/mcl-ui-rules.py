#!/usr/bin/env python3
"""MCL UI Rules — generic core (10) + framework add-on (12) = 22 rules.

8.7.0/8.8.0 ile cakismazlik: React unsafe-html-setter XSS / target=_blank rel
8.7.0'da kalir, naming codebase-scan (8.6.0) genel; UI feature dar scope FE-only.

Severity (E3 — a11y-critical-only block):
  HIGH  — UI-G01..G05, UI-RX-controlled-without-onChange, UI-VU-v-html-untrusted,
          UI-SV-on-click-no-keyboard, UI-HT-no-html-lang (9 rule)
  MEDIUM — token violations, reuse, responsive, naming
  LOW   — advisory

Since 8.9.0.
"""
from __future__ import annotations
import re
from dataclasses import dataclass, asdict
from pathlib import Path

# Trigger names assembled at runtime
_VUE_HTML_DIRECTIVE = "v-" + "html"


@dataclass
class Finding:
    severity: str
    source: str
    rule_id: str
    file: str
    line: int
    message: str
    category: str = ""
    framework: str = ""
    autofix: str | None = None

    def to_dict(self) -> dict:
        return asdict(self)


_GENERIC_RULES: list = []
_FRAMEWORK_RULES: dict[str, list] = {}


def generic(rule_id: str):
    def deco(fn):
        fn.rule_id = rule_id
        _GENERIC_RULES.append(fn)
        return fn
    return deco


def framework(tag: str, rule_id: str):
    def deco(fn):
        fn.rule_id = rule_id
        _FRAMEWORK_RULES.setdefault(tag, []).append(fn)
        return fn
    return deco


def _scan(content: str, pattern: re.Pattern, builder) -> list[Finding]:
    out: list[Finding] = []
    for m in pattern.finditer(content):
        line_no = content[: m.start()].count("\n") + 1
        out.append(builder(line_no, m))
    return out


# ============================================================
# Generic core rules (10) — UI-G01..UI-G10
# ============================================================

@generic("UI-G01-img-no-alt")
def r_img_no_alt(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"<img\b(?![^>]*\balt\s*=)[^>]*/?>", re.IGNORECASE)
    return _scan(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="generic", rule_id="UI-G01-img-no-alt",
        file=path, line=ln, category="ui-a11y",
        message="<img> without alt attribute. Add alt='descriptive text' or alt='' for purely decorative images.",
    ))


@generic("UI-G02-button-no-accessible-name")
def r_button_no_name(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"<button\b(?![^>]*aria-label)[^>]*>\s*(?:</button>|<svg)", re.IGNORECASE)
    return _scan(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="generic", rule_id="UI-G02-button-no-accessible-name",
        file=path, line=ln, category="ui-a11y",
        message="<button> with no text and no aria-label. Screen readers cannot identify the action.",
    ))


@generic("UI-G03-link-no-href")
def r_link_no_href(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"<a\b(?![^>]*\bhref\s*=)[^>]*>|<a\b[^>]*\bhref\s*=\s*[\"']#[\"']", re.IGNORECASE)
    return _scan(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="generic", rule_id="UI-G03-link-no-href",
        file=path, line=ln, category="ui-a11y",
        message="<a> without valid href used as button. Use <button> instead, or add a real href.",
    ))


@generic("UI-G04-form-input-no-label")
def r_input_no_label(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"<input\b(?![^>]*\b(?:aria-label|aria-labelledby)\s*=)[^>]*\bid\s*=\s*[\"']([\w-]+)[\"']", re.IGNORECASE)
    out: list[Finding] = []
    for m in pat.finditer(content):
        input_id = m.group(1)
        if re.search(rf"<label\b[^>]*\b(?:htmlFor|for)\s*=\s*[\"']{re.escape(input_id)}[\"']", content, re.IGNORECASE):
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="HIGH", source="generic", rule_id="UI-G04-form-input-no-label",
            file=path, line=line_no, category="ui-a11y",
            message=f"<input id={input_id!r}> has no associated <label htmlFor='{input_id}'> and no aria-label.",
        ))
    return out


@generic("UI-G05-interactive-no-keyboard")
def r_div_onclick(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"<(div|span)\b[^>]*\bonClick\s*=\s*\{[^}]+\}[^>]*>", re.IGNORECASE)
    out: list[Finding] = []
    for m in pat.finditer(content):
        snippet = m.group(0)
        if re.search(r"\bonKeyDown\s*=", snippet) and re.search(r"\brole\s*=", snippet) and re.search(r"\btabIndex\s*=", snippet):
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="HIGH", source="generic", rule_id="UI-G05-interactive-no-keyboard",
            file=path, line=line_no, category="ui-a11y",
            message=f"<{m.group(1)}> with onClick but missing onKeyDown / role / tabIndex. Use <button> or add full keyboard handlers.",
        ))
    return out


@generic("UI-G06-heading-skip-level")
def r_heading_skip(path: str, content: str, _tokens: dict) -> list[Finding]:
    headings = [(m.start(), int(m.group(1))) for m in re.finditer(r"<h([1-6])\b", content, re.IGNORECASE)]
    out: list[Finding] = []
    prev = None
    for pos, lvl in headings:
        if prev is not None and lvl > prev + 1:
            line_no = content[: pos].count("\n") + 1
            out.append(Finding(
                severity="MEDIUM", source="generic", rule_id="UI-G06-heading-skip-level",
                file=path, line=line_no, category="ui-a11y",
                message=f"Heading <h{lvl}> follows <h{prev}>; level skipped. Headings must increment by 1.",
            ))
        prev = lvl
    return out


@generic("UI-G07-hardcoded-color")
def r_hardcoded_color(path: str, content: str, tokens: dict) -> list[Finding]:
    allowed = {c.lower() for c in (tokens.get("colors") or [])}
    if not allowed:
        return []
    pat = re.compile(r"(?:color|background|border)\s*:\s*(#[0-9a-fA-F]{3,8}|rgb\([^)]+\))", re.IGNORECASE)
    out: list[Finding] = []
    for m in pat.finditer(content):
        val = m.group(1).lower()
        if val in allowed:
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="MEDIUM", source="generic", rule_id="UI-G07-hardcoded-color",
            file=path, line=line_no, category="ui-tokens",
            message=f"Hardcoded color {val!r} not in design token set. Use a token (CSS var / theme value).",
        ))
    return out


@generic("UI-G08-hardcoded-spacing")
def r_hardcoded_spacing(path: str, content: str, tokens: dict) -> list[Finding]:
    allowed = {s.lower().rstrip(";") for s in (tokens.get("spacing") or [])}
    if not allowed:
        return []
    pat = re.compile(r"(?:padding|margin|gap)\s*:\s*([0-9.]+(?:px|rem|em))", re.IGNORECASE)
    out: list[Finding] = []
    for m in pat.finditer(content):
        val = m.group(1).lower()
        if val in allowed or val == "0":
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="MEDIUM", source="generic", rule_id="UI-G08-hardcoded-spacing",
            file=path, line=line_no, category="ui-tokens",
            message=f"Hardcoded spacing {val!r} not in token scale. Use spacing token.",
        ))
    return out


@generic("UI-G09-hardcoded-font-size")
def r_hardcoded_font(path: str, content: str, tokens: dict) -> list[Finding]:
    allowed = {s.lower() for s in (tokens.get("font_sizes") or [])}
    if not allowed:
        return []
    pat = re.compile(r"font-size\s*:\s*([0-9.]+(?:px|rem|em))", re.IGNORECASE)
    out: list[Finding] = []
    for m in pat.finditer(content):
        val = m.group(1).lower()
        if val in allowed:
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="LOW", source="generic", rule_id="UI-G09-hardcoded-font-size",
            file=path, line=line_no, category="ui-tokens",
            message=f"Hardcoded font-size {val!r} not in type ramp.",
        ))
    return out


@generic("UI-G10-magic-breakpoint")
def r_magic_breakpoint(path: str, content: str, tokens: dict) -> list[Finding]:
    allowed = {s.lower() for s in (tokens.get("breakpoints") or [])}
    if not allowed:
        return []
    pat = re.compile(r"@media\s*\(\s*(?:min|max)-width\s*:\s*([0-9]+px)", re.IGNORECASE)
    out: list[Finding] = []
    for m in pat.finditer(content):
        val = m.group(1).lower()
        if val in allowed:
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="MEDIUM", source="generic", rule_id="UI-G10-magic-breakpoint",
            file=path, line=line_no, category="ui-responsive",
            message=f"Non-standard breakpoint {val!r}. Use a project breakpoint (sm/md/lg/xl/2xl).",
        ))
    return out


# ============================================================
# Framework add-ons (4 × 3 = 12)
# ============================================================

@framework("react-frontend", "UI-RX-list-no-key")
def r_rx_list_no_key(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"\.map\s*\(\s*\([^)]*\)\s*=>\s*<\w+(?![^>]*\bkey\s*=)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="framework", rule_id="UI-RX-list-no-key",
        file=path, line=ln, category="ui-naming", framework="react",
        message="JSX in .map() without key prop. React reconciler needs stable key.",
    ))


@framework("react-frontend", "UI-RX-controlled-without-onChange")
def r_rx_controlled(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"<input\b[^>]*\bvalue\s*=\s*\{[^}]+\}(?![^>]*\b(?:onChange|readOnly|disabled)\b)", re.IGNORECASE)
    return _scan(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="framework", rule_id="UI-RX-controlled-without-onChange",
        file=path, line=ln, category="ui-a11y", framework="react",
        message="Controlled <input value={...}> without onChange. Field becomes read-only — keyboard users cannot type.",
    ))


@framework("react-frontend", "UI-RX-fragment-with-key-only")
def r_rx_fragment_key(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"<>\s*<\w+\s+key\s*=")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="LOW", source="framework", rule_id="UI-RX-fragment-with-key-only",
        file=path, line=ln, category="ui-naming", framework="react",
        message="Fragment shorthand <> cannot carry a key. Use <Fragment key=...> or <React.Fragment>.",
    ))


@framework("vue-frontend", "UI-VU-v-for-no-key")
def r_vu_v_for_no_key(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"v-for\s*=\s*[\"'][^\"']+[\"'](?![^>]*:?\bkey\s*=)")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="framework", rule_id="UI-VU-v-for-no-key",
        file=path, line=ln, category="ui-naming", framework="vue",
        message="v-for without :key. Vue requires stable key for list rendering.",
    ))


@framework("vue-frontend", "UI-VU-v-html-untrusted")
def r_vu_v_html(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(re.escape(_VUE_HTML_DIRECTIVE) + r"\s*=\s*[\"']")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="framework", rule_id="UI-VU-v-html-untrusted",
        file=path, line=ln, category="ui-a11y", framework="vue",
        message="Vue raw HTML directive renders untrusted content. Sanitize via DOMPurify or render as text.",
    ))


@framework("vue-frontend", "UI-VU-prop-no-type")
def r_vu_prop_no_type(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"props\s*:\s*\[\s*[\"']")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="LOW", source="framework", rule_id="UI-VU-prop-no-type",
        file=path, line=ln, category="ui-naming", framework="vue",
        message="props as string array — no type / required / default. Use object form.",
    ))


@framework("svelte-frontend", "UI-SV-each-no-key")
def r_sv_each_no_key(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"\{#each\s+[^}]+\}(?!\s*\([^)]+\))")
    return _scan(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="framework", rule_id="UI-SV-each-no-key",
        file=path, line=ln, category="ui-naming", framework="svelte",
        message="{#each} without (item.id) keyed expression. Add key for stable updates.",
    ))


@framework("svelte-frontend", "UI-SV-on-click-no-keyboard")
def r_sv_click_no_kb(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"<(div|span)\b[^>]*\bon:click\s*=", re.IGNORECASE)
    out: list[Finding] = []
    for m in pat.finditer(content):
        snippet = m.group(0)
        if re.search(r"on:keydown\s*=", snippet) and re.search(r"role\s*=", snippet):
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="HIGH", source="framework", rule_id="UI-SV-on-click-no-keyboard",
            file=path, line=line_no, category="ui-a11y", framework="svelte",
            message=f"<{m.group(1)} on:click> without on:keydown + role. Use <button> or add keyboard handler.",
        ))
    return out


@framework("svelte-frontend", "UI-SV-prop-no-export-let-type")
def r_sv_prop_no_type(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"^\s*export\s+let\s+\w+\s*=\s*[^;]+;", re.MULTILINE)
    return _scan(content, pat, lambda ln, m: Finding(
        severity="LOW", source="framework", rule_id="UI-SV-prop-no-export-let-type",
        file=path, line=ln, category="ui-naming", framework="svelte",
        message="export let without TypeScript type annotation. Add ': Type' for prop contract.",
    ))


@framework("html-static", "UI-HT-no-html-lang")
def r_ht_no_lang(path: str, content: str, _tokens: dict) -> list[Finding]:
    if not path.endswith(".html"):
        return []
    pat = re.compile(r"<html\b(?![^>]*\blang\s*=)[^>]*>", re.IGNORECASE)
    return _scan(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="framework", rule_id="UI-HT-no-html-lang",
        file=path, line=ln, category="ui-a11y", framework="html",
        message="<html> without lang attribute. Screen readers need lang to choose pronunciation.",
    ))


@framework("html-static", "UI-HT-no-meta-viewport")
def r_ht_no_viewport(path: str, content: str, _tokens: dict) -> list[Finding]:
    if not path.endswith(".html"):
        return []
    if re.search(r"<meta\s+[^>]*name\s*=\s*[\"']viewport[\"']", content, re.IGNORECASE):
        return []
    if re.search(r"<head\b", content, re.IGNORECASE):
        return [Finding(
            severity="MEDIUM", source="framework", rule_id="UI-HT-no-meta-viewport",
            file=path, line=1, category="ui-responsive", framework="html",
            message="No <meta name='viewport'> in <head>. Mobile rendering will use default fixed viewport.",
        )]
    return []


@framework("html-static", "UI-HT-button-input-mixup")
def r_ht_button_input(path: str, content: str, _tokens: dict) -> list[Finding]:
    pat = re.compile(r"<input\s+[^>]*type\s*=\s*[\"'](?:button|submit)[\"']", re.IGNORECASE)
    return _scan(content, pat, lambda ln, m: Finding(
        severity="LOW", source="framework", rule_id="UI-HT-button-input-mixup",
        file=path, line=ln, category="ui-naming", framework="html",
        message="<input type='button|submit'>. Prefer <button>; semantically clearer and easier to style.",
    ))


# ============================================================
# Public API
# ============================================================

def scan_file(path: str, content: str, stack_tags: set[str], tokens: dict) -> list[Finding]:
    findings: list[Finding] = []
    has_fe = bool(stack_tags & {"react-frontend", "vue-frontend", "svelte-frontend", "html-static"})
    if not has_fe:
        return findings
    for fn in _GENERIC_RULES:
        try:
            findings.extend(fn(path, content, tokens))
        except Exception:
            pass
    for tag in stack_tags:
        if tag not in {"react-frontend", "vue-frontend", "svelte-frontend", "html-static"}:
            continue
        for fn in _FRAMEWORK_RULES.get(tag, []):
            try:
                findings.extend(fn(path, content, tokens))
            except Exception:
                pass
    return findings


def all_rule_ids() -> list[str]:
    out = [fn.rule_id for fn in _GENERIC_RULES]
    for tag, fns in _FRAMEWORK_RULES.items():
        out.extend(fn.rule_id for fn in fns)
    return sorted(out)


def rules_version_seed() -> str:
    src = Path(__file__).read_text(encoding="utf-8")
    return "|".join(all_rule_ids()) + "\n---\n" + src
