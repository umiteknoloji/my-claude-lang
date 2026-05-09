"""secrets — credential / kimlik bilgisi pattern taraması.

Pseudocode referansı: MyCL_Pseudocode.md §2 PreToolUse'da bahsedilen
"sır/kimlik bilgisi taraması".

Sözleşme:
    - Pattern listesi sabit (SECRET_PATTERNS), her biri severity
      etiketli (high / medium / low).
    - `scan_text(text)` matches listesi döner. False positive'ler
      kabul edilir; caller (pre_tool.py) severity'ye göre block/warn
      kararı verir.
    - **Fail-safe = allow**: regex hatası, encode hatası, beklenmeyen
      input → boş liste (block etme). Sır taraması güvenlik *katmanı*
      değil tek savunma değil; yanlış-pozitif kullanıcıyı kızdırmasın.
    - 1.0.0'da production-grade scanner değil; gerçek SAST ihtiyacında
      semgrep / truffleHog Bash CLI ile çağrılır (Plugin Kural C
      "binary CLI izinli" istisnası).

Pattern stratejisi:
    Spesifik prefix-based pattern'ler (AKIA, ghp_, sk_live_, vb.) +
    PEM/JWT yapısal pattern'ler. Generic `password=...` pattern'leri
    daha düşük severity (false positive yüksek).

API:
    SECRET_PATTERNS         — sabit liste
    scan_text(text)         → list[dict(name, severity, match_start, match_end)]
    scan_tool_input(name, input) → tool input içinde tarama
    has_severity(matches, level) → en az bir bulgu o severity'de mi?
"""

from __future__ import annotations

import re
from typing import Any

# Severity hiyerarşisi (high > medium > low)
_SEVERITY_ORDER = {"high": 3, "medium": 2, "low": 1}


SECRET_PATTERNS: list[dict[str, Any]] = [
    # AWS Access Key (AKIA prefix + 16 char alphanumeric)
    {
        "name": "aws-access-key",
        "regex": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
        "severity": "high",
    },
    # AWS Secret Key (40 char base64) — daha generic, MEDIUM
    {
        "name": "aws-secret-key",
        "regex": re.compile(
            r"(?i)aws[_-]?secret[_-]?(?:access[_-]?)?key\s*[:=]\s*['\"]?([A-Za-z0-9/+=]{40})['\"]?"
        ),
        "severity": "medium",
    },
    # GitHub Personal Access Token (ghp_, ghs_, gho_, ghu_, ghr_)
    {
        "name": "github-token",
        "regex": re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{36,}\b"),
        "severity": "high",
    },
    # Stripe live secret key
    {
        "name": "stripe-secret-key",
        "regex": re.compile(r"\bsk_live_[A-Za-z0-9]{24,}\b"),
        "severity": "high",
    },
    # Stripe restricted key
    {
        "name": "stripe-restricted-key",
        "regex": re.compile(r"\brk_live_[A-Za-z0-9]{24,}\b"),
        "severity": "high",
    },
    # Slack tokens (xoxb-, xoxp-, xoxa-, xoxr-, xoxs-)
    {
        "name": "slack-token",
        "regex": re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"),
        "severity": "high",
    },
    # PEM private key block
    {
        "name": "pem-private-key",
        "regex": re.compile(
            r"-----BEGIN(?:[ ](?:RSA|DSA|EC|OPENSSH|PGP|ENCRYPTED))?[ ]PRIVATE KEY-----"
        ),
        "severity": "high",
    },
    # SSH private key OpenSSH format (alternate)
    {
        "name": "openssh-private-key",
        "regex": re.compile(r"-----BEGIN OPENSSH PRIVATE KEY-----"),
        "severity": "high",
    },
    # JWT token (3 segments separated by dots, base64url)
    {
        "name": "jwt-token",
        "regex": re.compile(
            r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"
        ),
        "severity": "medium",
    },
    # Generic API key assignment (password/secret/token=...)
    {
        "name": "generic-secret-assignment",
        "regex": re.compile(
            r"(?i)(?:password|api[_-]?key|secret[_-]?key|access[_-]?token)\s*[:=]\s*['\"]?([A-Za-z0-9_\-]{16,})['\"]?"
        ),
        "severity": "low",
    },
    # Google API key (AIzaSy...)
    {
        "name": "google-api-key",
        "regex": re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b"),
        "severity": "high",
    },
]


def scan_text(text: str | None) -> list[dict[str, Any]]:
    """Text içinde credential pattern'leri ara.

    Returns:
        Liste of dict: {name, severity, match_start, match_end, snippet}.
        snippet: ilk 8 karakter + "..." (kayıt için, log'a tam basılmasın).

    Fail-safe: input None / boş / yanlış tip → boş liste.
    """
    if not text or not isinstance(text, str):
        return []

    matches: list[dict[str, Any]] = []
    for pattern in SECRET_PATTERNS:
        try:
            for m in pattern["regex"].finditer(text):
                snippet = m.group(0)
                if len(snippet) > 8:
                    snippet = snippet[:8] + "..."
                matches.append({
                    "name": pattern["name"],
                    "severity": pattern["severity"],
                    "match_start": m.start(),
                    "match_end": m.end(),
                    "snippet": snippet,
                })
        except (re.error, TypeError):
            # Fail-safe: regex hatası olursa pattern'i atla, taramaya devam.
            continue
    return matches


def scan_tool_input(
    tool_name: str | None,
    tool_input: dict[str, Any] | None,
) -> list[dict[str, Any]]:
    """Tool input içeriğini tara.

    Hangi alan taranır:
        - Write          → content
        - Edit           → new_string + old_string (eski içerik de credential olabilir)
        - MultiEdit      → her edits[i].new_string + old_string
        - NotebookEdit   → new_source
        - Bash           → command
        - Diğer          → boş (taranacak içerik yok)
    """
    if not tool_name or not isinstance(tool_input, dict):
        return []

    fields_to_scan: list[str] = []

    if tool_name == "Write":
        fields_to_scan.append(str(tool_input.get("content", "")))
    elif tool_name in ("Edit",):
        fields_to_scan.append(str(tool_input.get("new_string", "")))
        fields_to_scan.append(str(tool_input.get("old_string", "")))
    elif tool_name == "MultiEdit":
        edits = tool_input.get("edits", [])
        if isinstance(edits, list):
            for e in edits:
                if isinstance(e, dict):
                    fields_to_scan.append(str(e.get("new_string", "")))
                    fields_to_scan.append(str(e.get("old_string", "")))
    elif tool_name == "NotebookEdit":
        fields_to_scan.append(str(tool_input.get("new_source", "")))
    elif tool_name == "Bash":
        fields_to_scan.append(str(tool_input.get("command", "")))
    else:
        return []

    all_matches: list[dict[str, Any]] = []
    for field_text in fields_to_scan:
        if field_text:
            all_matches.extend(scan_text(field_text))
    return all_matches


def has_severity(
    matches: list[dict[str, Any]],
    level: str = "high",
) -> bool:
    """matches içinde en az `level` seviyede bulgu var mı?

    'high' → sadece HIGH bulgular. 'medium' → MEDIUM ve HIGH.
    'low' → tüm bulgular.
    """
    threshold = _SEVERITY_ORDER.get(level, 0)
    if not threshold:
        return False
    for m in matches:
        sev = _SEVERITY_ORDER.get(m.get("severity", ""), 0)
        if sev >= threshold:
            return True
    return False


def filter_by_severity(
    matches: list[dict[str, Any]],
    level: str = "high",
) -> list[dict[str, Any]]:
    """matches'i en az `level` seviyede olanlarla filtrele."""
    threshold = _SEVERITY_ORDER.get(level, 0)
    if not threshold:
        return []
    return [
        m for m in matches
        if _SEVERITY_ORDER.get(m.get("severity", ""), 0) >= threshold
    ]
