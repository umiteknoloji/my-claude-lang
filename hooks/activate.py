#!/usr/bin/env python3
"""activate — UserPromptSubmit hook.

Pseudocode §2 UserPromptSubmit:
    - state.json + audit.log oku
    - Bildirimler hazırla:
        <mycl_active_phase_directive>
        <mycl_phase_status>
        <mycl_phase_allowlist_escalate>
        <mycl_token_visibility>
        + Plugin Kural A git_init consent (ilk-açılış)
    - STATIC_CONTEXT (static_context.md) + tüm bildirimler → modele

Self-project guard: MyCL kendi repo'sunda çalışırken pipeline tetiklenmez
(recursive friction). MCL_REPO_PATH veya CWD == bu repo ise exit 0.

API: stdin'den Claude Code JSON input alır, stdout'a JSON çıkar:
    {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
     "additionalContext": "<text>"}}
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

# sys.path repo köküne eklenmezse hooks.lib import edilemez
_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from hooks.lib import audit, bilingual, dsi, framing, plugin, trace  # noqa: E402

_MYCL_VERSION = "1.0.0"


def _is_self_project(project_dir: str) -> bool:
    """MyCL kendi repo'sunda mı çalışıyor (recursive friction guard)?"""
    repo_path = os.environ.get("MYCL_REPO_PATH") or str(Path.home() / "my-claude-lang")
    try:
        cwd = Path(project_dir).resolve()
        myc = Path(repo_path).resolve()
    except OSError:
        return False
    return cwd == myc


def _read_input() -> dict:
    """stdin'den Claude Code JSON input."""
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


def _emit(text: str) -> None:
    """stdout'a additionalContext JSON yaz."""
    if not text:
        # Boş context → hook çıktısı yok; Claude Code'a sinyal gerekmez
        return
    out = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": text,
        }
    }
    print(json.dumps(out))


def _build_context(project_root: str, turn_tokens: int = 0) -> str:
    """Banner + Manifesto + DSI + Plugin Kural A consent prompt (varsa)."""
    blocks: list[str] = []

    # 0. Banner — sade görünür sinyal (sürüm + dil); TR + boş satır + EN
    blocks.append(
        f"MyCL {_MYCL_VERSION} — Anlam Doğrulama Katmanı aktif\n"
        f"\n"
        f"MyCL {_MYCL_VERSION} — Semantic Verification Layer active"
    )

    # 1. Manifesto (co-author framing — Disiplin #14, #15)
    manifesto = framing.for_context()
    if manifesto:
        blocks.append(manifesto)

    # 2. DSI (active phase directive + status + escalation + tokens)
    dsi_text = dsi.render_full_dsi(
        turn_tokens=turn_tokens,
        project_root=project_root,
    )
    if dsi_text:
        blocks.append(dsi_text)

    # 3. Plugin Kural A: git init consent (ilk-açılışta sor, sonra asla tekrar)
    if plugin.should_ask_git_init_consent(project_root=project_root):
        prompt = bilingual.render("git_init_consent_request")
        if prompt and not prompt.startswith("["):
            blocks.append(
                "<mycl_git_init_consent_request>\n"
                f"{prompt}\n"
                "</mycl_git_init_consent_request>"
            )

    return "\n\n".join(blocks)


def main() -> int:
    """Hook girişi."""
    payload = _read_input()
    project_dir = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

    # Self-project guard (recursive friction önleme)
    if _is_self_project(project_dir):
        return 0

    # Token sayısı — Claude Code transcript_path'ten input'ta gelebilir;
    # 1.0.0'da pratik: payload.get("turn_tokens", 0). Mevcut Claude Code
    # versiyonunda bu alan yok → 0; gelecekte eklenirse otomatik aktif.
    turn_tokens = int(payload.get("turn_tokens", 0) or 0)

    # İlk turda session_start trace'e
    audits = audit.read_all(project_root=project_dir)
    if not any(a.get("name", "").startswith("session_start") for a in audits):
        trace.session_start(_MYCL_VERSION, project_root=project_dir)

    # Context render
    context = _build_context(project_dir, turn_tokens=turn_tokens)
    _emit(context)
    return 0


if __name__ == "__main__":
    sys.exit(main())
