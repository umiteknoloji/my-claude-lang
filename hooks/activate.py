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

from hooks.lib import (  # noqa: E402
    activation, audit, bilingual, dsi, framing, orchestrator, plugin,
    state, trace,
)


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


def _check_stuck_state(project_root: str) -> str | None:
    """Önceki oturum stuck state bıraktıysa soft warning üret.

    1.0.16: Aşama 4'ten ileride `spec_approved == False` → stuck.
    Yeni oturumda kullanıcı `/mycl` ile aktive ederse eski state
    yüklü; spec_approved=False ile mutating tool deny edilir,
    pipeline ilerleyemez. Soft warning: kullanıcı durumu görsün
    + recovery yolu önerilsin. Hard deny YOK.
    """
    cp = state.get("current_phase", 1, project_root=project_root)
    spec_approved = bool(
        state.get("spec_approved", False, project_root=project_root)
    )
    if cp >= 4 and not spec_approved:
        return (
            f"⚠️ Önceki oturum stuck state bıraktı: current_phase={cp} "
            "+ spec_approved=False. Aşama 4 spec onayı yapılmamış, "
            "Aşama 5+ ilerleyemez. Önerim: `.mycl` ve `.git` "
            "dizinlerini sil + yeniden `/mycl <niyet>` ile başla. "
            "Alternatif manuel kurtarma: `python3 -c \"from hooks.lib "
            "import audit; audit.log_event('asama-4-complete', "
            "'recovery', 'manual')\"`.\n\n"
            f"⚠️ Previous session left stuck state: current_phase={cp} "
            "+ spec_approved=False. Phase 4 spec approval missing, "
            "Phase 5+ cannot advance. Suggestion: delete `.mycl` and "
            "`.git`, restart with `/mycl <intent>`. Manual recovery "
            "alternative: `python3 -c \"from hooks.lib import audit; "
            "audit.log_event('asama-4-complete', 'recovery', "
            "'manual')\"`."
        )
    return None


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

    # 4. Reinforcement reminder — en sonda emit (Anthropic resmi öneri:
    # "Append a condensed reminder at the end of your system prompt").
    # Uzun konuşma + post-compaction sonrası model'in faz disiplinini
    # unutmasını önler. Bilingual TR + EN, spec_approved durumuna göre
    # dinamik vurgu.
    spec_approved = bool(state.get("spec_approved", False, project_root=project_root))
    reminder_cp = cp_for_dsi
    if spec_approved:
        mutating_rule_tr = (
            "Mutating tool (Write/Edit/Bash) izinli — spec onayı geçerli."
        )
        mutating_rule_en = (
            "Mutating tools (Write/Edit/Bash) permitted — spec is approved."
        )
    else:
        mutating_rule_tr = (
            "Mutating tool (Write/Edit/Bash) YASAK — Aşama 4 spec onayı "
            "yapılmadan kod yazımı yok."
        )
        mutating_rule_en = (
            "Mutating tools (Write/Edit/Bash) FORBIDDEN — no code writes "
            "until Phase 4 spec is approved."
        )
    reminder_tr = (
        f"• Aşamalar sıralı: atlamak veya geri zıplamak yasak "
        f"(şu an Aşama {reminder_cp}/22).\n"
        f"• {mutating_rule_tr}\n"
        f"• Audit kayıtlarını hook yazar; sen yalnız `asama-N-complete` "
        f"tetik kelimesini cevap metnine düz yazıyla zikret.\n"
        f"• Belirsizlik = fail-closed deny; tahmin yapma, kullanıcıya "
        f"tek soru sor."
    )
    reminder_en = (
        f"• Phase order is strict: no jumps or back-skips allowed "
        f"(currently Phase {reminder_cp}/22).\n"
        f"• {mutating_rule_en}\n"
        f"• Audit records are written by hooks; you only mention "
        f"`asama-N-complete` trigger words plainly in your reply text.\n"
        f"• Ambiguity = fail-closed deny; never guess, ask the user "
        f"one question."
    )
    blocks.append(
        "<mycl_reinforcement_reminder>\n"
        f"{reminder_tr}\n\n{reminder_en}\n"
        "</mycl_reinforcement_reminder>"
    )

    return "\n\n".join(blocks)


def main() -> int:
    """Hook girişi."""
    payload = _read_input()
    project_dir = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

    # Self-project guard (recursive friction önleme)
    if _is_self_project(project_dir):
        return 0

    # 1.0.5: opt-in `/mycl` session trigger.
    # Trigger varsa session'ı aktive et + prompt'tan sıyır. Aktif değilse
    # hook tamamen sessiz — banner yok, deny yok, audit yok.
    session_id = str(payload.get("session_id", "") or "")
    prompt = str(payload.get("prompt", "") or "")
    has_trigger, stripped = activation.extract_trigger(prompt)
    if has_trigger:
        activation.activate_session(session_id, project_root=project_dir)
    if not activation.is_session_active(session_id, project_root=project_dir):
        return 0

    # Token sayısı — Claude Code transcript_path'ten input'ta gelebilir;
    # 1.0.0'da pratik: payload.get("turn_tokens", 0). Mevcut Claude Code
    # versiyonunda bu alan yok → 0; gelecekte eklenirse otomatik aktif.
    turn_tokens = int(payload.get("turn_tokens", 0) or 0)

    # İlk turda session_start trace'e
    audits = audit.read_all(project_root=project_dir)
    if not any(a.get("name", "").startswith("session_start") for a in audits):
        trace.session_start(_MYCL_VERSION, project_root=project_dir)

    # Context render — trigger varsa baş'a aktivasyon notu ekle.
    parts: list[str] = []
    if has_trigger:
        note_tr = (
            "MyCL bu turdan itibaren bu projede aktif.\n"
            "Kullanıcının `/mycl` sonrası asıl mesajı: "
            + (f"'{stripped}'" if stripped else "(boş — yalnızca aktivasyon onayı)")
        )
        note_en = (
            "MyCL is active in this project from this turn onward.\n"
            "User's actual message after `/mycl`: "
            + (f"'{stripped}'" if stripped else "(empty — activation acknowledgment only)")
        )
        parts.append(
            "<mycl_activation_note>\n"
            f"{note_tr}\n\n{note_en}\n"
            "</mycl_activation_note>"
        )
        # 1.0.16: Stuck state soft warning — yalnızca aktivasyon turunda
        stuck_msg = _check_stuck_state(project_dir)
        if stuck_msg:
            parts.append(
                "<mycl_stuck_state_warning>\n"
                f"{stuck_msg}\n"
                "</mycl_stuck_state_warning>"
            )
    main_ctx = _build_context(project_dir, turn_tokens=turn_tokens)
    if main_ctx:
        parts.append(main_ctx)
    _emit("\n\n".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
