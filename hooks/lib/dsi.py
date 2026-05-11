"""dsi — Dynamic Status Injection (her turun başı, activate.py'den).

Pseudocode §5 DSI:
    Aktif faz odağını gönderir — model 'ortada kaybolma' yaşamasın.
    PHASE_META'dan aktif faz görev/emit/skip cue'ları + faz index
    tablosu render edilir.

XML tag vocabulary (CLAUDE.md tag-schema):
    <mycl_active_phase_directive>  — şu an aktif faz, ne yazılmalı
    <mycl_phase_status>            — ilerleme tablosu (✅⏳ glyph'ler)
    <mycl_phase_allowlist_escalate>— 5+ strike escalation uyarısı
    <mycl_token_visibility>        — tur/toplam token (Disiplin #7)

Sözleşme:
    - activate.py her UserPromptSubmit'te `render_full_dsi()` çağırır.
    - render fonksiyonları çift dil (bilingual.py, progress.py kullanır).
    - Tag içeriği boş string ise tag hiç emit edilmez (gürültü yok).
    - Token visibility para göstermez (Disiplin #7).

API:
    render_active_phase_directive(phase, project_root) → str
    render_phase_status(project_root) → str
    render_phase_allowlist_escalate(project_root) → str
    render_token_visibility(turn_tokens, project_root) → str
    render_full_dsi(turn_tokens, project_root) → str
"""

from __future__ import annotations

from hooks.lib import audit, gate, progress, tokens

_ESCALATION_SUFFIX = "escalation-needed"


def _phase_directive_text(phase: int) -> str:
    """phase_meta.json'dan aktif faz directive'ini al (TR + EN).

    Not: project_root parametresi yok — phase_meta.json global
    (~/.claude/data veya repo'ya bakılır), project-specific değil.
    """
    meta = progress.load_phase_meta()
    phase_def = meta.get("phases", {}).get(str(phase), {})
    if not isinstance(phase_def, dict):
        return ""
    tr = phase_def.get("directive_tr", "") or ""
    en = phase_def.get("directive_en", "") or ""
    if tr and en:
        return f"{tr}\n\n{en}"
    return tr or en


def render_active_phase_directive(
    phase: int,
    project_root: str | None = None,
) -> str:
    """<mycl_active_phase_directive> içeriği.

    project_root API simetrisi için tutuldu (diğer render fonksiyonları
    proje-spesifik); _phase_directive_text bunu kullanmıyor (phase_meta
    global).
    """
    _ = project_root  # API simetrisi için; phase_meta global
    text = _phase_directive_text(phase)
    if not text:
        return ""
    return f"<mycl_active_phase_directive>\n{text}\n</mycl_active_phase_directive>"


def render_phase_status(project_root: str | None = None) -> str:
    """<mycl_phase_status> ASCII pipeline + ilerleme."""
    current = gate.active_phase(project_root=project_root)
    bar = progress.pipeline_block(current_phase=current, project_root=project_root)
    if not bar:
        return ""
    return f"<mycl_phase_status>\n{bar}\n</mycl_phase_status>"


def render_phase_allowlist_escalate(
    project_root: str | None = None,
) -> str:
    """<mycl_phase_allowlist_escalate> uyarı.

    Sadece audit log'da escalation tespit edildiyse emit; yoksa boş.
    Tek pass: audit.read_all bir kez okunur, filter + last in tek geçiş.
    """
    last_escalation: dict | None = None
    for ev in audit.read_all(project_root=project_root):
        if ev.get("name", "").endswith(_ESCALATION_SUFFIX):
            last_escalation = ev
    if last_escalation is None:
        return ""
    return (
        "<mycl_phase_allowlist_escalate>\n"
        f"⚠️ Escalation: {last_escalation['name']} (audit: {last_escalation['detail']})\n"
        f"Geliştirici müdahalesi gerekiyor; pipeline pasif bekliyor.\n"
        f"Developer intervention required; pipeline is waiting.\n"
        "</mycl_phase_allowlist_escalate>"
    )


def render_token_visibility(
    turn_tokens: int,
    project_root: str | None = None,
) -> str:
    """<mycl_token_visibility> turn + total token (para YOK)."""
    if turn_tokens <= 0:
        return ""
    text = tokens.format_visibility(
        turn_tokens=turn_tokens,
        project_root=project_root,
    )
    if not text or text.startswith("["):
        return ""
    return f"<mycl_token_visibility>\n{text}\n</mycl_token_visibility>"


def render_full_dsi(
    turn_tokens: int = 0,
    project_root: str | None = None,
    include_directive: bool = True,
) -> str:
    """Tüm DSI bloğu — activate.py her tur başı çağırır.

    Boş içerikli tag'ler emit edilmez (gürültü engellenir).

    `include_directive=False`: subagent_orchestration aktif fazlarda
    çakışan yönlendirmeyi önlemek için aktif faz directive'i atlanır;
    phase_status + escalation + tokens hâlâ emit edilir (bilgi katmanı).
    """
    current = gate.active_phase(project_root=project_root)
    blocks: list[str] = []

    if include_directive:
        directive = render_active_phase_directive(current, project_root=project_root)
        if directive:
            blocks.append(directive)

    status = render_phase_status(project_root=project_root)
    if status:
        blocks.append(status)

    escalate = render_phase_allowlist_escalate(project_root=project_root)
    if escalate:
        blocks.append(escalate)

    if turn_tokens > 0:
        tok = render_token_visibility(turn_tokens, project_root=project_root)
        if tok:
            blocks.append(tok)

    return "\n\n".join(blocks)
