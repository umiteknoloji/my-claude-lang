#!/usr/bin/env python3
"""pre_tool — PreToolUse hook (Layer B + spec-approval + state lock).

Pseudocode §2 PreToolUse + CLAUDE.md design principles.

Akış (sırasıyla):
    1. Self-project guard (recursive friction)
    2. Phase transition emit denylist (Bash içinde audit hile)
    3. State-mutation lock (Bash kanalından state.set_field DENY)
    4. Spec-approval block (spec_approved=false → mutating Bash/Write/Edit
       DENY; git init Plugin Kural A istisna)
    5. Layer B: gate.evaluate(tool, file_path) → deny olursa
       phase-allowlist audit + REASON döner
    6. 5 strike sonrası `*-escalation-needed` audit (görünür sinyal)

STRICT mode: fail-open YOK. Block sonsuza kadar; kullanıcı
müdahalesine kadar deny sürer.

Output (Claude Code JSON):
    {"hookSpecificOutput": {"hookEventName": "PreToolUse",
     "permissionDecision": "allow" | "deny",
     "permissionDecisionReason": "..."}}
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from hooks.lib import activation, audit, bilingual, gate, state  # noqa: E402


def _read_version() -> str:
    """VERSION dosyasından sürümü oku — banner/block prefix'leri için."""
    version_file = _REPO_ROOT / "VERSION"
    try:
        return version_file.read_text(encoding="utf-8").strip() or "0.0.0"
    except OSError:
        return "0.0.0"


_MYCL_VERSION = _read_version()

_STRIKE_ESCALATION_THRESHOLD = 5

# Mutating Bash detection
_BASH_REDIRECT_RE = re.compile(r"(?:^|[^<>&0-9])>>?\s*[^&\s]")
_BASH_TEE_RE = re.compile(r"\btee\b(?!\s*--help)")
_BASH_MUTATING_PATTERNS = [
    re.compile(r"(?:^|[\s|;&`(])(rm|mv|cp|touch|mkdir|rmdir|chmod|chown|chgrp|ln|truncate|dd|patch|install|unlink)\b"),
    re.compile(r"(?:^|[\s|;&`(])sed\b[^|;&`]*?\s-i\b"),
    re.compile(r"(?:^|[\s|;&`(])git\s+(commit|push|add|rm|mv|reset|checkout|restore|switch|rebase|merge|pull|fetch|clone|stash|tag|branch|clean|cherry-pick|revert|apply|am|worktree)\b"),
    re.compile(r"(?:^|[\s|;&`(])(npm|yarn|pnpm|bun|pip|pip3|poetry|uv|gem|bundle|cargo|go|brew|apt|apt-get|dnf|yum|pacman|zypper)\s+(install|i|ci|add|remove|uninstall|update|upgrade|mod)\b"),
]
# State mutation pattern (Python lib çağrıları)
_STATE_MUTATION_RE = re.compile(
    r"\b(?:hooks\.lib\.state\.|state\.)(?:set_field|update|reset)\b"
)
# Audit hile (phase_transition / asama-N-progression-from-emit yasak)
_PHASE_TRANSITION_EMIT_RE = re.compile(
    r"phase_transition\s+\d+\s+\d+|asama-\d+-progression-from-emit"
)


def _is_self_project(project_dir: str) -> bool:
    repo_path = os.environ.get("MYCL_REPO_PATH") or str(Path.home() / "my-claude-lang")
    try:
        cwd = Path(project_dir).resolve()
        myc = Path(repo_path).resolve()
    except OSError:
        return False
    return cwd == myc


def _read_input() -> dict:
    try:
        raw = sys.stdin.read()
    except (OSError, ValueError):
        return {}
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def _emit(decision: str, reason: str = "") -> None:
    """Claude Code permission JSON output."""
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
        }
    }
    if reason:
        out["hookSpecificOutput"]["permissionDecisionReason"] = reason
    print(json.dumps(out))


def _allow() -> int:
    _emit("allow")
    return 0


def _deny(reason: str) -> int:
    _emit("deny", reason)
    return 0


def _is_bash_mutating(cmd: str) -> bool:
    """Bash command mutating mi?"""
    if not cmd:
        return False
    if _BASH_REDIRECT_RE.search(cmd) or _BASH_TEE_RE.search(cmd):
        return True
    return any(p.search(cmd) for p in _BASH_MUTATING_PATTERNS)


_BOOTSTRAP_CMD_PATTERNS = [
    re.compile(r"^\s*git\s+init\s*$"),
    re.compile(r"^\s*mkdir(?:\s+-p)?\s+\.mycl(?:/[^\s]*)?\s*$"),
]


def _is_bootstrap_command(cmd: str) -> bool:
    """Plugin Kural A bootstrap için izinli komut(lar) mı?

    Kabul: `git init`, `mkdir [-p] .mycl[/sub]`. Compound separator'lar
    `&&` ve `;` desteklenir — her parça allowlist'ten birini matchlemeli.
    Pipe (`|`) ve OR (`||`) reddedilir (riskli akış kontrolü).

    1.0.11: 1.0.10'daki `_is_git_init_only` `git init && mkdir -p .mycl`
    gibi compound bootstrap'leri kaçırıyordu; model'in tek turda hem
    git init hem `.mycl/` setup yapması doğal → kapsam genişletildi.
    """
    if not cmd:
        return False
    parts = re.split(r"\s*(?:&&|;)\s*", cmd.strip())
    return bool(parts) and all(
        any(p.match(part) for p in _BOOTSTRAP_CMD_PATTERNS)
        for part in parts if part
    )


def _bilingual_block(key: str, **kwargs) -> str:
    """bilingual.render — fail-safe (eksik key → key adı).

    1.0.9: `version` placeholder otomatik enjekte edilir — block
    template'lerinde `MyCL {version} | ` prefix kullanılır.
    """
    kwargs.setdefault("version", _MYCL_VERSION)
    text = bilingual.render(key, **kwargs)
    return text if text and not text.startswith("[") else ""


def _record_strike_and_escalation(
    block_kind: str, tool: str, project_root: str,
) -> None:
    """Block audit + 5 strike eşiği aşılırsa escalation audit."""
    audit.log_event(
        block_kind, "pre_tool.py",
        f"tool={tool}", project_root=project_root,
    )
    count = gate.deny_count_in_session(block_kind, project_root=project_root)
    if count == _STRIKE_ESCALATION_THRESHOLD:
        audit.log_event(
            f"{block_kind}-escalation-needed", "pre_tool.py",
            f"strike={count} developer-intervention-required",
            project_root=project_root,
        )


def main() -> int:
    payload = _read_input()
    project_dir = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

    if _is_self_project(project_dir):
        return _allow()

    # 1.0.5: opt-in `/mycl` — aktif değilse hook no-op (her tool allow).
    session_id = str(payload.get("session_id", "") or "")
    if not activation.is_session_active(session_id, project_root=project_dir):
        return _allow()

    tool_name = str(payload.get("tool_name", ""))
    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        tool_input = {}

    # Bash command extract
    bash_cmd = ""
    if tool_name == "Bash":
        bash_cmd = str(tool_input.get("command", ""))

    # ---------- 2. Phase transition emit denylist ----------
    if tool_name == "Bash" and _PHASE_TRANSITION_EMIT_RE.search(bash_cmd):
        audit.log_event(
            "phase-transition-illegal-emit-attempt", "pre_tool.py",
            f"tool=Bash", project_root=project_dir,
        )
        return _deny(
            "MyCL deterministic gate: phase_transition / asama-N-progression-from-emit "
            "model tarafından emit edilemez. Hook bu audit'leri yazar.\n\n"
            "MyCL deterministic gate: phase_transition / asama-N-progression-from-emit "
            "cannot be model-emitted. Hook writes these audits."
        )

    # ---------- 3. State-mutation lock ----------
    if tool_name == "Bash" and _STATE_MUTATION_RE.search(bash_cmd):
        audit.log_event(
            "state-mutation-attempt", "pre_tool.py",
            "tool=Bash", project_root=project_dir,
        )
        return _deny(
            _bilingual_block("state_mutation_block")
            or "STATE LOCK — state.set_field/update/reset Bash kanalından çağrılamaz."
        )

    # ---------- 3.5. MyCL state dosyaları koruma (H-5 fix) ----------
    # .mycl/state.json ve .mycl/audit.log doğrudan Write/Edit/Bash ile
    # değiştirilemez. Elle spec_approved=True yazmak kilidi bypass eder;
    # bu özel blok faz/spec durumundan bağımsız her zaman aktiftir.
    _PROTECTED_MYCL_PATTERNS = re.compile(
        r"\.mycl[\\/](?:state\.json|audit\.log)",
        re.IGNORECASE,
    )
    if tool_name in {"Write", "Edit", "MultiEdit"}:
        fp_check = str(tool_input.get("file_path") or tool_input.get("path") or "")
        if _PROTECTED_MYCL_PATTERNS.search(fp_check):
            audit.log_event(
                "mycl-state-direct-write-attempt", "pre_tool.py",
                f"tool={tool_name} path={fp_check}", project_root=project_dir,
            )
            return _deny(
                "MyCL koruma: `.mycl/state.json` ve `.mycl/audit.log` "
                "doğrudan yazılamaz — state hook'lar tarafından yönetilir.\n\n"
                "MyCL guard: `.mycl/state.json` and `.mycl/audit.log` "
                "cannot be written directly — state is managed by hooks."
            )
    if tool_name == "Bash" and _PROTECTED_MYCL_PATTERNS.search(bash_cmd):
        # Bash ile state.json veya audit.log redirect/yazma girişimi
        if _BASH_REDIRECT_RE.search(bash_cmd) or _BASH_TEE_RE.search(bash_cmd):
            audit.log_event(
                "mycl-state-direct-write-attempt", "pre_tool.py",
                f"tool=Bash cmd_excerpt={bash_cmd[:80]}", project_root=project_dir,
            )
            return _deny(
                "MyCL koruma: `.mycl/state.json` ve `.mycl/audit.log` "
                "Bash redirect ile yazılamaz — state hook'lar tarafından yönetilir.\n\n"
                "MyCL guard: `.mycl/state.json` and `.mycl/audit.log` "
                "cannot be overwritten via Bash redirect — hooks manage state."
            )

    # ---------- 4. Spec-approval block ----------
    spec_approved = bool(state.get("spec_approved", False, project_root=project_dir))
    if not spec_approved:
        # Mutating tool mu? (Write/Edit/MultiEdit/NotebookEdit veya mutating Bash)
        is_mutating = tool_name in {"Write", "Edit", "MultiEdit", "NotebookEdit"}
        if tool_name == "Bash" and _is_bash_mutating(bash_cmd):
            # Plugin Kural A bootstrap istisnası (git init + .mycl mkdir)
            if _is_bootstrap_command(bash_cmd):
                is_mutating = False
            else:
                is_mutating = True
        if is_mutating:
            _record_strike_and_escalation(
                "spec-approval-block", tool_name, project_dir,
            )
            return _deny(
                _bilingual_block("spec_approval_block", tool=tool_name)
                or f"Spec onayı yok; `{tool_name}` engellendi."
            )

    # ---------- 4.5. Plugin Kural A bootstrap istisnası ----------
    # `git init` ve `.mycl/` mkdir zararsız (remote yok, push yok);
    # consent prompt'u activate.py'de zaten gösteriliyor. Faz
    # allowlist'inin Bash'i kapsamadığı Aşama 1 dahil her durumda
    # allow et — başarılı çağrı sonrası post_tool.py consent'i
    # `approved` olarak işaretler. Compound (`git init && mkdir -p
    # .mycl`) destekli (1.0.11).
    if tool_name == "Bash" and _is_bootstrap_command(bash_cmd):
        return _allow()

    # ---------- 5. Layer B (gate.evaluate) ----------
    file_path = tool_input.get("file_path") or tool_input.get("path") or ""
    allowed, reason = gate.evaluate(
        tool_name,
        file_path=file_path or None,
        project_root=project_dir,
    )
    if not allowed:
        # phase-allowlist veya phase-path audit (gate'e göre)
        block_kind = (
            "phase-allowlist-tool"
            if "izinli değil" in reason or "fail-closed" in reason
            else "phase-allowlist-path"
        )
        _record_strike_and_escalation(block_kind, tool_name, project_dir)
        # bilingual mesaj — phase_allowlist_block veya phase_path_block
        msg_key = "phase_allowlist_block" if block_kind == "phase-allowlist-tool" else "phase_path_block"
        phase = gate.active_phase(project_root=project_dir)
        msg = _bilingual_block(
            msg_key,
            phase=phase,
            tool=tool_name,
            allowed="(see gate_spec.json)",
            path=str(file_path),
            denied="(see gate_spec.json)",
        )
        return _deny(msg or reason)

    # ---------- 6. ALLOW ----------
    return _allow()


if __name__ == "__main__":
    sys.exit(main())
