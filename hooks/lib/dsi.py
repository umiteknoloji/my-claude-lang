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

from hooks.lib import audit, bilingual, gate, progress, state, tokens

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


def render_pattern_rules_notice(
    phase: int,
    project_root: str | None = None,
) -> str:
    """<mycl_pattern_rules> — Aşama 5'te depolanan pattern özetini
    Aşama 9 TDD boyunca her turda model'e hatırlatır.

    1.0.20: skill `asama09-tdd.md:62` ve `asama05-desen.md:62` iki dosyada
    "her tur başı DSI'da pattern_summary görünür" dictat'ı var; ama
    dsi.py 1.0.19'a kadar bunu emit etmiyordu. Aşama 5'in varoluş amacı
    (Aşama 9 TDD tutarlılığı) buraya bağlı.

    Sadece Aşama 9'da + state.pattern_summary set ise emit; aksi halde
    boş.
    """
    if phase != 9:
        return ""
    summary = state.get(
        "pattern_summary", None, project_root=project_root,
    )
    if not summary:
        return ""
    return (
        "<mycl_pattern_rules>\n"
        f"Aşama 5'te öğrenilen proje desenleri (Aşama 9 TDD'de uyulmalı):\n"
        f"{summary}\n\n"
        f"Phase 5 patterns (Phase 9 TDD must conform):\n"
        f"{summary}\n"
        "</mycl_pattern_rules>"
    )


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


def render_selfcritique_notice(
    project_root: str | None = None,
) -> str:
    """1.0.33: self_critique_required disiplin direktifi.

    Audit log'da `selfcritique-needed phase=N` audit'i var ve aynı faz
    için henüz `selfcritique-passed phase=N` veya `selfcritique-gap-
    found phase=N` audit'i yoksa, modele yönlendirme enjekte eder.
    Cevap geldiğinde (passed/gap) direktif susar.

    Soft guidance — hard deny değil; CLAUDE.md "soft guidance over
    fail-fast" kuralı.
    """
    needed_phases: set[int] = set()
    responded_phases: set[int] = set()
    for ev in audit.read_all(project_root=project_root):
        name = ev.get("name", "")
        detail = ev.get("detail", "")
        if name == "selfcritique-needed":
            # phase=N detail'dan parse
            for token in detail.split():
                if token.startswith("phase="):
                    try:
                        needed_phases.add(int(token[len("phase="):]))
                    except ValueError:
                        pass
        elif name in ("selfcritique-passed", "selfcritique-gap-found"):
            for token in detail.split():
                if token.startswith("phase="):
                    try:
                        responded_phases.add(int(token[len("phase="):]))
                    except ValueError:
                        pass
    pending = sorted(needed_phases - responded_phases)
    if not pending:
        return ""
    # Bilingual prompt — `self_critique_request` key 1.0.x'ten beri var
    prompt = bilingual.render("self_critique_request", phase=pending[0])
    return (
        "<mycl_selfcritique_notice>\n"
        f"{prompt}\n"
        f"Bekleyen faz(lar) / Pending phase(s): {pending}. Cevabını "
        f"`selfcritique-passed phase=N` veya `selfcritique-gap-found "
        f"phase=N items=\"...\"` formatında yaz.\n"
        "</mycl_selfcritique_notice>"
    )


def render_mid_reconfirm_notice(
    project_root: str | None = None,
) -> str:
    """1.0.29: Aşama 19 mid-pipeline reconfirmation direktifi.

    Audit log'da `asama-19-mid-reconfirm-needed` varsa ve
    `asama-19-mid-reconfirm-acked` yoksa, modele "askq aç" yönlendirmesi
    emit eder. Acked sonrası direktif susar.

    Soft guidance — hard deny değil; CLAUDE.md "soft guidance over
    fail-fast" kuralı.
    """
    needed = False
    acked = False
    for ev in audit.read_all(project_root=project_root):
        name = ev.get("name", "")
        if name == "asama-19-mid-reconfirm-needed":
            needed = True
        elif name == "asama-19-mid-reconfirm-acked":
            acked = True
    if not needed or acked:
        return ""
    return (
        "<mycl_mid_reconfirm_notice>\n"
        "Aşama 19 etki listesi 10+ maddeye ulaştı. Devam etmeden önce "
        "geliştiriciye AskUserQuestion ile 'hâlâ bu yönde mi ilerleyelim?' "
        "sor; cevap alındığında metnine `asama-19-mid-reconfirm-acked` "
        "yaz.\n\n"
        "Phase 19 impact list reached 10+ items. Before continuing, open "
        "an AskUserQuestion asking the developer 'still on this path?'; "
        "after the answer, emit `asama-19-mid-reconfirm-acked` in your "
        "reply text.\n"
        "</mycl_mid_reconfirm_notice>"
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

    # 1.0.20: Aşama 9 TDD'de pattern_rules hatırlatması (Aşama 5 çıktısı).
    pattern_block = render_pattern_rules_notice(
        current, project_root=project_root,
    )
    if pattern_block:
        blocks.append(pattern_block)

    status = render_phase_status(project_root=project_root)
    if status:
        blocks.append(status)

    escalate = render_phase_allowlist_escalate(project_root=project_root)
    if escalate:
        blocks.append(escalate)

    # 1.0.29: Aşama 19 mid-pipeline reconfirmation (10+ item-resolved
    # eşiği aşıldıysa askq yönlendirmesi).
    mid_reconfirm = render_mid_reconfirm_notice(project_root=project_root)
    if mid_reconfirm:
        blocks.append(mid_reconfirm)

    # 1.0.33: self_critique_required disiplin direktifi (Aşama
    # 2/4/8/9/10/14/19 — soft guidance).
    selfcritique_notice = render_selfcritique_notice(
        project_root=project_root,
    )
    if selfcritique_notice:
        blocks.append(selfcritique_notice)

    if turn_tokens > 0:
        tok = render_token_visibility(turn_tokens, project_root=project_root)
        if tok:
            blocks.append(tok)

    return "\n\n".join(blocks)
