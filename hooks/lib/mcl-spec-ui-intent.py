#!/usr/bin/env python3
# MCL spec-body UI intent scanner (since 6.5.4; in 6.5.5 the text
# selector was changed from "last assistant text" to "last assistant
# text that contains a 📋 Spec: block" — mirror of the same fix in
# hooks/mcl-stop.sh).
#
# Reads the Claude Code transcript at argv[1], finds the most recent
# spec-bearing assistant text, isolates the `📋 Spec:` block, and
# checks for strong UI-framework markers. Single-match is enough — the
# marker set is designed to avoid false positives in non-UI specs (a
# Python script spec, a bash bug fix, etc. will never contain any of
# these tokens).
#
# Output: literal "true" or "false" on stdout. No stderr on normal paths.
# Exit code: always 0.

import json
import re
import sys

def extract_text(msg):
    if isinstance(msg, dict) and "message" in msg and isinstance(msg["message"], dict):
        msg = msg["message"]
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


SPEC_MARKER_RE = re.compile(r"\U0001F4CB[ \t]+Spec:")


def last_assistant_spec_text(path):
    # Since 6.5.5: pick the most recent assistant text that CONTAINS a
    # `📋 Spec:` block. Earlier versions returned the most recent text
    # unconditionally, so trailing narration in a spec-bearing turn (e.g.
    # "Kodu yazıyorum") hid the spec from this scanner and UI intent
    # never fired on well-formed but tail-padded turns.
    last = None
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
                text = extract_text(obj)
                if text and SPEC_MARKER_RE.search(text):
                    last = text
    except Exception:
        return None
    return last


def extract_spec_body(text):
    spec_line_re = re.compile(r"^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?\U0001F4CB[ \t]+Spec:")
    lines = text.splitlines()
    start = None
    for i, ln in enumerate(lines):
        if spec_line_re.match(ln):
            start = i
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start + 1, len(lines)):
        stripped = lines[j].lstrip()
        if re.match(r"^#+\s", stripped):
            end = j
            break
    return "\n".join(lines[start:end])


STRONG_MARKERS = [
    # Framework names (word-boundary aware; escape dots)
    r"\bNext\.js\b",
    r"\bReact\b",
    r"\bVue(?:\.js)?\b",
    r"\bSvelte\b",
    r"\bAngular\b",
    r"\bNuxt\b",
    r"\bSvelteKit\b",
    r"\bRemix\b",
    r"\bAstro\b",
    r"\bSolidJS\b",
    r"\bSolid\.js\b",
    r"\bQwik\b",
    r"\bPreact\b",
    # Template extensions
    r"\bTSX\b",
    r"\bJSX\b",
    r"\.tsx\b",
    r"\.jsx\b",
    r"\.vue\b",
    r"\.svelte\b",
    # Styling libraries (strong)
    r"\bTailwind(?:\s*CSS)?\b",
    r"\bshadcn(?:/ui)?\b",
    r"\bRadix(?:\s*UI)?\b",
    r"\bChakra(?:\s*UI)?\b",
    r"\bMaterial-UI\b",
    r"\bMUI\b",
    r"\bHeroUI\b",
    r"\bNextUI\b",
    # App-shell signals (unambiguous)
    r"\bcomponents/ui\b",
    r"\bApp\s*Router\b",
    r"\bPages\s*Router\b",
    r"\bserver\s+component\b",
    r"\bserver\s+action\b",
    r"\buse\s+client\b",
    r"\buse\s+server\b",
    # Backend-templated UI (template-folder context)
    r"\bBlade\s+template\b",
    r"\bTwig\s+template\b",
    r"\bERB\s+template\b",
    r"\bJinja\s+template\b",
    # React / Vue hook and ecosystem tokens
    r"\buseState\b",
    r"\buseEffect\b",
    r"\bReact\s+Router\b",
    r"\bVue\s+Router\b",
    # Static HTML + JS declared as the UI approach
    r"\bindex\.html\b",
]

MARKER_RE = re.compile("|".join(STRONG_MARKERS), re.IGNORECASE)


def has_ui_intent(body):
    if not body:
        return False
    return bool(MARKER_RE.search(body))


def main():
    if len(sys.argv) < 2:
        print("false")
        return 0
    path = sys.argv[1]
    text = last_assistant_spec_text(path)
    if not text:
        print("false")
        return 0
    body = extract_spec_body(text)
    if not body:
        print("false")
        return 0
    print("true" if has_ui_intent(body) else "false")
    return 0


if __name__ == "__main__":
    sys.exit(main())
