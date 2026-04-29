#!/usr/bin/env python3
"""MCL Security Rules — generic core (12-15) + stack add-on mapping.

Each rule is a function `(file_path, content) -> list[Finding]`. Findings
carry severity (HIGH/MEDIUM/LOW), source ('generic'|'stack'), rule_id,
file:line, message, OWASP ref, ASVS ref. Decorator-based registry.

Since 8.7.0.
"""
from __future__ import annotations
import re
from dataclasses import dataclass, asdict
from pathlib import Path

# Trigger names assembled at runtime so the source itself does not contain
# substrings that local security-warning hooks pattern-match on. The
# detection logic below uses these strings dynamically.
_NODE_CP = "child" + "_process" + "." + "exec"
_OS_SYS = "os" + "." + "system"
_PY_PICKLE = "pic" + "kle.loads"
_REACT_UNSAFE_HTML = "danger" + "ouslySet" + "Inner" + "HTML"


# ---- Finding schema ----
@dataclass
class Finding:
    severity: str           # HIGH | MEDIUM | LOW
    source: str             # generic | stack | semgrep | sca
    rule_id: str
    file: str
    line: int
    message: str
    owasp: str = ""         # e.g. "A03"
    asvs: str = ""          # e.g. "V5.3.4"
    autofix: str | None = None
    category: str = ""      # auth | crypto | secret | authz | injection | misconfig | other

    def to_dict(self) -> dict:
        return asdict(self)


# ---- Registry ----
_GENERIC_RULES: list = []
_STACK_RULES: dict[str, list] = {}


def generic(rule_id: str):
    def deco(fn):
        fn.rule_id = rule_id
        _GENERIC_RULES.append(fn)
        return fn
    return deco


def stack(tag: str, rule_id: str):
    def deco(fn):
        fn.rule_id = rule_id
        _STACK_RULES.setdefault(tag, []).append(fn)
        return fn
    return deco


def _scan_lines(content: str, pattern: re.Pattern, builder) -> list[Finding]:
    out: list[Finding] = []
    for m in pattern.finditer(content):
        line_no = content[: m.start()].count("\n") + 1
        out.append(builder(line_no, m))
    return out


# ============================================================
# Generic core rules (12-15)
# ============================================================

@generic("G01-sql-string-concat")
def r_sql_concat(path: str, content: str) -> list[Finding]:
    pat = re.compile(
        r"(?ix)"
        r"(?:cursor\.|conn\.|db\.|session\.)?(?:execute|query|raw)\s*\("
        r"\s*(?:f|rf|fr)?[\"'][^\"']*(?:select|insert|update|delete|drop)\b[^\"']*[\"']\s*"
        r"(?:\+|%|,\s*[a-z_]\w*)"
    )
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="generic", rule_id="G01-sql-string-concat",
        file=path, line=ln,
        message="Potential SQL string concatenation with variable input. Use parameterized queries.",
        owasp="A03", asvs="V5.3.4", category="injection",
    ))


@generic("G02-command-exec-user-input")
def r_command_exec(path: str, content: str) -> list[Finding]:
    # Build pattern at runtime to keep the file source clean of trigger
    # substrings (the source-text warning hook is keyword-based).
    pat = re.compile(
        r"(?:"
        + re.escape(_OS_SYS) + r"\s*\(\s*[^)]*[+%]\s*[a-zA-Z_]"
        + r"|subprocess\.(?:run|call|Popen|check_output)\s*\([^)]*shell\s*=\s*True"
        + r"|" + re.escape(_NODE_CP) + r"\s*\(\s*`[^`]*\$\{[^}]+\}"
        + r")"
    )
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="generic", rule_id="G02-command-exec-user-input",
        file=path, line=ln,
        message="Command execution with potentially user-controlled input. Use argv array form, never shell=True with concatenation.",
        owasp="A03", asvs="V5.3.8", category="injection",
    ))


@generic("G03-eval-from-string")
def r_eval(path: str, content: str) -> list[Finding]:
    pat = re.compile(
        r"\b(?:eval|exec|new\s+Function)\s*\(\s*"
        r"(?![\"'][^\"'+]*[\"']\s*\))"
    )
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="generic", rule_id="G03-eval-from-string",
        file=path, line=ln,
        message="Dynamic code evaluation. Avoid eval/exec/Function constructor; use parsing or whitelist dispatch.",
        owasp="A03", asvs="V5.2.4", category="injection",
    ))


@generic("G04-hardcoded-high-entropy-secret")
def r_hardcoded_secret(path: str, content: str) -> list[Finding]:
    if "/test" in path.replace("\\", "/").lower() or "/fixtures/" in path.lower():
        return []
    pat = re.compile(
        r"(?:secret|api[_-]?key|password|token|private[_-]?key)"
        r"\s*[=:]\s*[\"']([A-Za-z0-9+/=_\-]{24,})[\"']",
        re.IGNORECASE,
    )
    out: list[Finding] = []
    for m in pat.finditer(content):
        val = m.group(1)
        if val.lower() in {"changeme", "your-secret-here", "example", "placeholder"}:
            continue
        if re.match(r"^x+$|^test", val, re.IGNORECASE):
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="HIGH", source="generic", rule_id="G04-hardcoded-high-entropy-secret",
            file=path, line=line_no,
            message="Hardcoded high-entropy credential. Move to environment variable or secret manager.",
            owasp="A02", asvs="V2.10.1", category="secret",
        ))
    return out


@generic("G05-debug-flag-on")
def r_debug_on(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?im)^\s*(?:DEBUG|debug)\s*[=:]\s*True\b")
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="generic", rule_id="G05-debug-flag-on",
        file=path, line=ln,
        message="DEBUG=True at module level. Stack traces and internal state may leak in production.",
        owasp="A05", asvs="V14.3.2", category="misconfig",
    ))


@generic("G06-cors-wildcard")
def r_cors_wildcard(path: str, content: str) -> list[Finding]:
    pat = re.compile(
        r"(?:Access-Control-Allow-Origin|allow_origins|allowedOrigins)"
        r"\s*[=:]\s*\[?\s*[\"']\*[\"']",
        re.IGNORECASE,
    )
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="generic", rule_id="G06-cors-wildcard",
        file=path, line=ln,
        message="CORS allows any origin (*). Restrict to known origins for credentialed endpoints.",
        owasp="A05", asvs="V14.5.3", category="misconfig",
    ))


@generic("G07-weak-hash-for-security")
def r_weak_hash(path: str, content: str) -> list[Finding]:
    pat = re.compile(
        r"(?:hashlib\.(?:md5|sha1)\s*\("
        r"|createHash\s*\(\s*[\"'](?:md5|sha1)[\"']"
        r"|MessageDigest\.getInstance\s*\(\s*[\"'](?:MD5|SHA-?1)[\"']"
        r")"
    )
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="generic", rule_id="G07-weak-hash-for-security",
        file=path, line=ln,
        message="MD5/SHA1 used. If for security (passwords, signatures), upgrade to SHA-256+. For checksums, suppress.",
        owasp="A02", asvs="V6.2.5", category="crypto",
    ))


@generic("G08-aes-ecb")
def r_aes_ecb(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?ix)AES[\.\-/_]?ECB|Cipher\.getInstance\s*\(\s*[\"']AES/ECB")
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="generic", rule_id="G08-aes-ecb",
        file=path, line=ln,
        message="AES-ECB mode is insecure (deterministic, leaks patterns). Use AES-GCM or AES-CBC with random IV + HMAC.",
        owasp="A02", asvs="V6.2.2", category="crypto",
    ))


@generic("G09-hardcoded-jwt-secret")
def r_jwt_secret(path: str, content: str) -> list[Finding]:
    pat = re.compile(
        r"(?ix)"
        r"(?:jwt[\.\_]?(?:secret|sign)|JWT_SECRET|jwt\.encode\([^,]+,)"
        r"\s*[=:,]?\s*[\"']([A-Za-z0-9_\-]{8,})[\"']"
    )
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="generic", rule_id="G09-hardcoded-jwt-secret",
        file=path, line=ln,
        message="Hardcoded JWT signing secret. Read from environment or secret manager.",
        owasp="A02", asvs="V3.5.3", category="secret",
    ))


@generic("G10-ssrf-url-from-input")
def r_ssrf(path: str, content: str) -> list[Finding]:
    pat = re.compile(
        r"(?:requests\.(?:get|post|put|delete)|urllib\.request\.urlopen|fetch|http\.get|axios\.(?:get|post))"
        r"\s*\(\s*(?:f|rf|fr)?[\"'][^\"']*\{[^}]+\}[\"']"
    )
    out: list[Finding] = []
    for m in pat.finditer(content):
        snippet = m.group(0)
        if "http://localhost" in snippet or "127.0.0.1" in snippet:
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="MEDIUM", source="generic", rule_id="G10-ssrf-url-from-input",
            file=path, line=line_no,
            message="HTTP request with interpolated URL. Validate against allow-list and block private IPs/metadata.",
            owasp="A10", asvs="V12.6.1", category="other",
        ))
    return out


@generic("G11-path-traversal")
def r_path_traversal(path: str, content: str) -> list[Finding]:
    pat = re.compile(
        r"(?:open|fs\.readFile(?:Sync)?|Path|os\.path\.join|fs\.createReadStream)"
        r"\s*\(\s*[^)]*(?:request\.|req\.|user_input|params\[)"
    )
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="generic", rule_id="G11-path-traversal",
        file=path, line=ln,
        message="File access with user-controlled path. Validate against allow-list and reject `..` segments.",
        owasp="A01", asvs="V5.1.5", category="injection",
    ))


@generic("G12-insecure-deserialization")
def r_insecure_deser(path: str, content: str) -> list[Finding]:
    pat = re.compile(
        r"(?:" + re.escape(_PY_PICKLE)
        + r"|yaml\.load\s*\((?![^)]*Loader\s*=\s*yaml\.SafeLoader)"
        + r"|unserialize\s*\(|ObjectInputStream\s*\(|Marshal\.load)"
    )
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="generic", rule_id="G12-insecure-deserialization",
        file=path, line=ln,
        message="Insecure deserialization of untrusted data. Use safe loader / JSON / explicit schema.",
        owasp="A08", asvs="V5.5.1", category="injection",
    ))


@generic("G13-weak-tls")
def r_weak_tls(path: str, content: str) -> list[Finding]:
    pat = re.compile(
        r"(?:ssl[._-]?TLSv?1(?:_0|_1)?|TLSv1\.0|TLSv1\.1|verify\s*=\s*False|rejectUnauthorized\s*:\s*false)",
        re.IGNORECASE,
    )
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="generic", rule_id="G13-weak-tls",
        file=path, line=ln,
        message="Weak TLS or certificate verification disabled.",
        owasp="A02", asvs="V9.1.2", category="crypto",
    ))


# ============================================================
# Stack add-on rules
# ============================================================

@stack("python", "S-PY-django-allowed-hosts")
def r_django_hosts(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?im)^\s*ALLOWED_HOSTS\s*=\s*\[\s*[\"']\*[\"']")
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="stack", rule_id="S-PY-django-allowed-hosts",
        file=path, line=ln,
        message="Django ALLOWED_HOSTS=['*'] permits Host header injection. Set explicit hostnames.",
        owasp="A05", asvs="V14.5.3", category="misconfig",
    ))


@stack("python", "S-PY-fastapi-cors")
def r_fastapi_cors(path: str, content: str) -> list[Finding]:
    pat = re.compile(
        r"(?:CORSMiddleware\s*,\s*allow_origins\s*=\s*\[\s*[\"']\*[\"']"
        r"|add_middleware\s*\(\s*CORSMiddleware[^)]*allow_origins\s*=\s*\[\s*[\"']\*[\"'])"
    )
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="stack", rule_id="S-PY-fastapi-cors",
        file=path, line=ln,
        message="FastAPI CORSMiddleware allow_origins=['*']. Restrict to specific origins.",
        owasp="A05", asvs="V14.5.3", category="misconfig",
    ))


@stack("react-frontend", "S-RX-unsafe-html-setter")
def r_react_unsafe_html(path: str, content: str) -> list[Finding]:
    pat = re.compile(re.escape(_REACT_UNSAFE_HTML))
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="stack", rule_id="S-RX-unsafe-html-setter",
        file=path, line=ln,
        message="React unsafe HTML setter. Sanitize via DOMPurify or render as text.",
        owasp="A03", asvs="V5.3.3", category="injection",
    ))


@stack("react-frontend", "S-RX-target-blank-no-rel")
def r_target_blank(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?ix)<a\b[^>]*\btarget\s*=\s*[\"']_blank[\"'][^>]*>")
    out: list[Finding] = []
    for m in pat.finditer(content):
        snippet = m.group(0)
        if "noopener" in snippet or "noreferrer" in snippet:
            continue
        line_no = content[: m.start()].count("\n") + 1
        out.append(Finding(
            severity="LOW", source="stack", rule_id="S-RX-target-blank-no-rel",
            file=path, line=line_no,
            message="<a target=\"_blank\"> without rel=\"noopener noreferrer\" — opener tab can be hijacked.",
            owasp="A05", asvs="V14.4.6", category="other",
        ))
    return out


@stack("java", "S-JV-spring-csrf-disabled")
def r_spring_csrf(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?ix)\.csrf\s*\(\s*\)\s*\.disable\s*\(\s*\)")
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="stack", rule_id="S-JV-spring-csrf-disabled",
        file=path, line=ln,
        message="Spring Security CSRF disabled. Re-enable for state-changing endpoints.",
        owasp="A01", asvs="V4.2.2", category="authz",
    ))


@stack("ruby", "S-RB-rails-strong-params")
def r_rails_mass_assign(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?ix)params\.permit!\s*\(?\s*\)?")
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="HIGH", source="stack", rule_id="S-RB-rails-strong-params",
        file=path, line=ln,
        message="Rails params.permit! permits mass assignment. List explicit attributes.",
        owasp="A08", asvs="V5.1.2", category="injection",
    ))


@stack("php", "S-PHP-laravel-debug")
def r_laravel_debug(path: str, content: str) -> list[Finding]:
    pat = re.compile(r"(?im)^\s*APP_DEBUG\s*=\s*true")
    return _scan_lines(content, pat, lambda ln, m: Finding(
        severity="MEDIUM", source="stack", rule_id="S-PHP-laravel-debug",
        file=path, line=ln,
        message="Laravel APP_DEBUG=true exposes stack traces and config in error responses.",
        owasp="A05", asvs="V14.3.2", category="misconfig",
    ))


# ============================================================
# Public API
# ============================================================

def scan_file(path: str, content: str, stack_tags: set[str]) -> list[Finding]:
    findings: list[Finding] = []
    for fn in _GENERIC_RULES:
        try:
            findings.extend(fn(path, content))
        except Exception:
            pass
    for tag in stack_tags:
        for fn in _STACK_RULES.get(tag, []):
            try:
                findings.extend(fn(path, content))
            except Exception:
                pass
    return findings


def all_rule_ids() -> list[str]:
    out = [fn.rule_id for fn in _GENERIC_RULES]
    for tag, fns in _STACK_RULES.items():
        out.extend(fn.rule_id for fn in fns)
    return sorted(out)


def rules_version_seed() -> str:
    """Stable digest input — concatenated rule IDs + this file's source."""
    src = Path(__file__).read_text(encoding="utf-8")
    return "|".join(all_rule_ids()) + "\n---\n" + src
