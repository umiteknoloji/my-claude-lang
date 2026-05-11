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

from hooks.lib import audit, bilingual, dsi, framing, orchestrator, plugin, state, trace  # noqa: E402


def _read_version() -> str:
    """VERSION dosyasından sürümü oku — tek-kaynak.

    Repo kökünde VERSION; bulunmazsa "0.0.0" (defansif default).
    """
    version_file = _REPO_ROOT / "VERSION"
    try:
        return version_file.read_text(encoding="utf-8").strip() or "0.0.0"
    except OSError:
        return "0.0.0"


_MYCL_VERSION = _read_version()


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

    # 0. Banner — sade görünür sinyal (bilingual.render → TR + boş satır + EN)
    banner = bilingual.render("mycl_banner", version=_MYCL_VERSION)
    if banner and not banner.startswith("["):
        blocks.append(banner)

    # 1. Manifesto (co-author framing — Disiplin #14, #15)
    manifesto = framing.for_context()
    if manifesto:
        blocks.append(manifesto)

    # 2. DSI (active phase directive + status + escalation + tokens)
    # Subagent orchestration aktif fazda DSI'nın active_phase_directive
    # kısmı atlanır — çakışan yönlendirme model'i kafasız bırakıyordu
    # (POC trace kanıtı). Phase status + escalation + tokens kalır
    # (bilgi katmanı, çelişen yön değil).
    cp_for_dsi = state.get("current_phase", 1, project_root=project_root)
    dsi_text = dsi.render_full_dsi(
        turn_tokens=turn_tokens,
        project_root=project_root,
        include_directive=not orchestrator.is_orchestration_enabled(cp_for_dsi),
    )
    if dsi_text:
        blocks.append(dsi_text)

    # 2.5. Subagent orchestration directive — aktif fazda
    # `subagent_orchestration: true` ise modeli mycl-phase-runner Task
    # çağrısına yönlendir. Subagent text döner, stop hook parse eder.
    cp = state.get("current_phase", 1, project_root=project_root)
    if orchestrator.is_orchestration_enabled(cp):
        try:
            skill_content = orchestrator.read_skill(cp)
        except FileNotFoundError:
            skill_content = ""
        state_snapshot = {
            "current_phase": cp,
            "spec_must_list": state.get(
                "spec_must_list", [], project_root=project_root,
            ),
            "pattern_summary": state.get(
                "pattern_summary", "n/a", project_root=project_root,
            ),
        }
        prior_output = state.get(
            "last_phase_output", "none", project_root=project_root,
        )
        subagent_prompt = orchestrator.build_subagent_prompt(
            phase_n=cp,
            skill_content=skill_content,
            state_snapshot=state_snapshot,
            prior_output=prior_output,
        )
        directive_tr = (
            f"Aşama {cp} için **mycl-phase-runner** subagent'ını "
            f"**Task** tool ile çağır. Subagent text döner "
            f"(`complete: <özet>` formatında); hook bunu okur. Başka "
            f"tool çağırma — sadece Task ile subagent başlat."
        )
        directive_en = (
            f"For Phase {cp}, invoke the **mycl-phase-runner** subagent "
            f"via **Task** tool. Subagent returns text "
            f"(`complete: <summary>` format); hook reads it. Don't call "
            f"other tools; only Task to start the subagent."
        )
        blocks.append(
            "<mycl_phase_subagent_directive>\n"
            f"{directive_tr}\n\n{directive_en}\n\n"
            f"Subagent prompt:\n```\n{subagent_prompt}\n```\n"
            "</mycl_phase_subagent_directive>"
        )

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
