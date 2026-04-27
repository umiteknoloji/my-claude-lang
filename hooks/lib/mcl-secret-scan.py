#!/usr/bin/env python3
"""Scan Write/Edit/MultiEdit/NotebookEdit tool inputs for hardcoded secrets.

Reads the raw hook JSON from stdin. Outputs one of:
  safe
  block|<reason>

Three detection tiers:
  1. Sensitive file path  — .env (non-example), *.pem, *.key, credentials.json …
  2. Known secret pattern — sk-…, ghp_…, AKIA…, AIza…, PEM headers, JWT, …
  3. High-entropy assignment — SECRET_VAR = "<long-random-string>"

Never blocks on scanner error (outputs "safe" as fallback).
"""

import json, math, os, re, sys
from collections import Counter

# ── Known secret patterns (high confidence) ───────────────────────────────────

_SECRET_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    # OpenAI
    (re.compile(r'\bsk-[A-Za-z0-9]{32,}\b'),                     "OpenAI API key"),
    (re.compile(r'\bsk-proj-[A-Za-z0-9_\-]{32,}\b'),             "OpenAI project key"),
    # GitHub
    (re.compile(r'\bghp_[A-Za-z0-9]{36,}\b'),                    "GitHub personal access token"),
    (re.compile(r'\bghs_[A-Za-z0-9]{36,}\b'),                    "GitHub Actions token"),
    (re.compile(r'\bgho_[A-Za-z0-9]{36,}\b'),                    "GitHub OAuth token"),
    # AWS
    (re.compile(r'\bAKIA[0-9A-Z]{16}\b'),                        "AWS access key ID"),
    (re.compile(r'(?i)aws.{0,20}secret.{0,20}[=:]\s*["\']?[A-Za-z0-9/+]{40}["\']?'),
                                                                   "AWS secret access key"),
    # Slack
    (re.compile(r'\bxoxb-[0-9]+-[0-9]+-[A-Za-z0-9]+\b'),        "Slack bot token"),
    (re.compile(r'\bxoxp-[0-9]+-[0-9]+-[0-9]+-[A-Za-z0-9]+\b'), "Slack user token"),
    # Google
    (re.compile(r'\bAIza[0-9A-Za-z_\-]{35}\b'),                  "Google API key"),
    # Anthropic
    (re.compile(r'\bsk-ant-[A-Za-z0-9_\-]{30,}\b'),              "Anthropic API key"),
    # Stripe
    (re.compile(r'\bsk_live_[A-Za-z0-9]{24,}\b'),                "Stripe live secret key"),
    (re.compile(r'\brk_live_[A-Za-z0-9]{24,}\b'),                "Stripe restricted key"),
    # Twilio
    (re.compile(r'\bSK[0-9a-f]{32}\b'),                          "Twilio auth token"),
    # PEM / SSH private keys
    (re.compile(r'-----BEGIN\s+(?:RSA\s+)?PRIVATE KEY-----'),    "PEM private key"),
    (re.compile(r'-----BEGIN OPENSSH PRIVATE KEY-----'),          "OpenSSH private key"),
    # Bearer tokens / JWTs that look real (3-part, long signature)
    (re.compile(r'\beyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]{20,}\b'),
                                                                   "JWT token"),
]

# ── Sensitive file-path matcher ───────────────────────────────────────────────

_SENSITIVE_PATH = re.compile(
    r'(?i)'
    r'(^|[/\\])('
    r'\.env(\.(local|prod(uction)?|staging|test|development|ci|secrets?))?'
    r'|[^/\\]*\.pem'
    r'|[^/\\]*\.p12'
    r'|[^/\\]*\.pfx'
    r'|[^/\\]*\.key$'             # ends in .key (not .keywords etc.)
    r'|[^/\\]*\.(cer|cert)$'
    r'|credentials\.json'
    r'|client_secret[^/\\]*\.json'
    r'|service[_\-]?account[^/\\]*\.json'
    r'|secrets\.(yaml|yml|json|toml)'
    r')$'
)
# Safe exemptions: .env.example, .env.template, anything.example, etc.
_SAFE_PATH = re.compile(
    r'(?i)\.(example|template|sample|tmpl|dist|tpl)$'
    r'|\.env\.example'
    r'|[/\\]example[s]?[/\\]'
)

# ── Content helpers ───────────────────────────────────────────────────────────

# Values that are obviously placeholders — skip these
_PLACEHOLDER = re.compile(
    r'(?i)(your[_\-]|<[^>]+>|change[_\-]?me|placeholder|example|here|'
    r'todo|fixme|replace|insert|add[_\-]your|put[_\-]your|\*{3,}|'
    r'dummy|fake|test_?key|mock_|sample_|demo_|secret123|password123|'
    r'not[_\-]a[_\-]real|fake[_\-]key|example[_\-]key)'
    # Note: short sequences like "12345" or "xxx" removed — they match as
    # substrings of longer real-looking values and cause false negatives.
)

# Values that are env-var references, NOT hardcoded
_ENV_REF = re.compile(
    r'(process\.env\.|os\.environ|ENV\[|System\.getenv\(|getenv\('
    r'|\$\{[A-Z_][A-Z0-9_]*\}|\$[A-Z_][A-Z0-9_]*(?=\s|;|$|"|\'|\n))'
)

# Variable names that suggest the value should be secret
_SECRET_VAR = re.compile(
    r'(?i)(password|passwd|secret|api[_\-]?key|access[_\-]?key|auth[_\-]?token'
    r'|private[_\-]?key|credential|client[_\-]?secret|app[_\-]?secret'
    r'|database[_\-]?url|db[_\-]?pass|encryption[_\-]?key|signing[_\-]?key'
    r'|webhook[_\-]?secret|jwt[_\-]?secret|cookie[_\-]?secret)'
)

# Assignment: VAR_NAME = "value" in various syntaxes
_ASSIGNMENT = re.compile(
    r'(?i)'
    r'(?P<var>'
    r'password|passwd|secret|api[_\-]?key|access[_\-]?key|auth[_\-]?token'
    r'|private[_\-]?key|credential|client[_\-]?secret|app[_\-]?secret'
    r'|database[_\-]?url|db[_\-]?pass|encryption[_\-]?key|signing[_\-]?key'
    r'|webhook[_\-]?secret|jwt[_\-]?secret|cookie[_\-]?secret'
    r')'
    r'[^\n=:]{0,25}[=:]\s*["\']?'
    r'(?P<val>[A-Za-z0-9+/\-_.@!#$%^&*]{20,})'
    r'["\']?'
)


def _entropy(s: str) -> float:
    if not s:
        return 0.0
    freq = Counter(s)
    n = len(s)
    return -sum((c / n) * math.log2(c / n) for c in freq.values())


def _mask(s: str) -> str:
    if len(s) <= 8:
        return s[:2] + '***'
    return s[:4] + '...' + s[-3:]


def _scan_content(content: str) -> str | None:
    """Return block reason or None."""

    # Tier 2: known secret patterns
    for pat, name in _SECRET_PATTERNS:
        m = pat.search(content)
        if m:
            return (
                f"Hardcoded {name} detected (`{_mask(m.group(0))}`). "
                f"Never commit real credentials — use environment variables or a secrets manager."
            )

    # Tier 3: high-entropy assignment to sensitive variable name
    for m in _ASSIGNMENT.finditer(content):
        var, val = m.group('var'), m.group('val')
        if _PLACEHOLDER.search(val):
            continue
        if _ENV_REF.search(val):
            continue
        # Require ≥ 20 chars AND high entropy
        if len(val) >= 20 and _entropy(val) >= 3.5:
            return (
                f"Possible hardcoded secret in `{var}` (high-entropy value `{_mask(val)}`). "
                f"If real: use an environment variable. "
                f"If a placeholder: add a comment or use `.env.example`."
            )

    return None


def scan(tool_name: str, tool_input: dict) -> str:
    """Return 'safe' or 'block|<reason>'."""

    # Build list of (file_path, content) pairs from this tool call
    pairs: list[tuple[str, str]] = []
    if tool_name in ('Write', 'Edit', 'NotebookEdit'):
        fp = str(tool_input.get('file_path') or tool_input.get('notebook_path') or '')
        content = str(
            tool_input.get('content') or
            tool_input.get('new_string') or
            ''
        )
        pairs.append((fp, content))
    elif tool_name == 'MultiEdit':
        for e in (tool_input.get('edits') or []):
            if isinstance(e, dict):
                pairs.append((
                    str(e.get('file_path') or ''),
                    str(e.get('new_string') or ''),
                ))

    for fp, content in pairs:
        basename = os.path.basename(fp)

        # ── Tier 1: sensitive file path ──────────────────────────────────────
        if _SENSITIVE_PATH.search(fp) and not _SAFE_PATH.search(fp):
            # Only block if content has non-comment, non-placeholder lines with values
            value_lines = [
                ln for ln in content.splitlines()
                if ln.strip() and not ln.strip().startswith('#')
                and ('=' in ln or ':' in ln)
            ]
            real = [
                ln for ln in value_lines
                if not _PLACEHOLDER.search(ln.split('=', 1)[-1].split(':', 1)[-1].strip())
                and not _ENV_REF.search(ln)
            ]
            if real:
                return (
                    f"block|Writing `{basename}` with apparent real credentials. "
                    f"Commit `.env.example` with placeholders instead; "
                    f"inject real values via environment variables at runtime."
                )

        # ── Tier 2 + 3: content scan ─────────────────────────────────────────
        if content:
            reason = _scan_content(content)
            if reason:
                return f"block|{reason}"

    return "safe"


if __name__ == '__main__':
    try:
        obj = json.loads(sys.stdin.read())
        result = scan(
            str(obj.get('tool_name') or ''),
            obj.get('tool_input') or {},
        )
        print(result)
    except Exception:
        print('safe')   # never block on scanner error
