"""activation — opt-in `/mycl` session trigger (1.0.5+).

MyCL artık her promptta otomatik aktif değil: session başına bir kez
`/mycl` (veya `/mycl <prompt>`) ile etkinleşir. Yeni Claude Code
session'ı yeni session_id'ye sahip olduğu için MyCL pasif başlar —
kullanıcı tekrar `/mycl` yazana kadar hiçbir hook çıktı vermez ve
hiçbir tool deny edilmez.

Token davranışı: prompt başındaki `/mycl` prefix'i sıyrılır; sıyrılmış
prompt activate.py'nin additionalContext bloğunda model'e "gerçek
istek" olarak iletilir.

Kalıcılık: aktif session_id `.mycl/active_session.txt` dosyasında
tutulur. Dosya kalıcı (proje bazlı) ama içerik session_id ile
karşılaştırıldığı için yeni session açılınca otomatik pasifleşir.

API:
    extract_trigger(prompt) → (has_trigger, stripped_prompt)
    activate_session(session_id, project_root)
    is_session_active(session_id, project_root) → bool
    deactivate(project_root)  — sadece testler için
"""

from __future__ import annotations

import os
import re
from pathlib import Path

# Prompt başında "/mycl" (büyük/küçük harf duyarsız) + boşluk veya satır sonu.
# Sadece prefix yakalanır — orta satırda geçen "/mycl" sıyrılmaz.
_TRIGGER_RE = re.compile(r"^\s*/mycl(?:\b|$)", re.IGNORECASE)


def extract_trigger(prompt: str | None) -> tuple[bool, str]:
    """Prompt başındaki `/mycl` trigger'ını ayıkla.

    Returns:
        (has_trigger, stripped_prompt). Trigger varsa True ve trigger
        sonrası kalan metin (baştaki boşluklar trim); yoksa False ve
        orijinal prompt.
    """
    if not prompt:
        return False, prompt or ""
    m = _TRIGGER_RE.match(prompt)
    if not m:
        return False, prompt
    return True, prompt[m.end():].lstrip()


def _active_session_path(project_root: str | None = None) -> Path:
    root = Path(project_root) if project_root else Path.cwd()
    return root / ".mycl" / "active_session.txt"


def activate_session(
    session_id: str, project_root: str | None = None,
) -> bool:
    """Session'ı aktif olarak kaydet.

    Returns:
        Dosya başarıyla yazıldıysa True; session_id boşsa veya I/O
        hatası varsa False.
    """
    if not session_id or not session_id.strip():
        return False
    path = _active_session_path(project_root)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(session_id.strip(), encoding="utf-8")
        return True
    except OSError:
        return False


def is_session_active(
    session_id: str | None, project_root: str | None = None,
) -> bool:
    """session_id, kayıtlı aktif session ile eşleşir mi?

    Eşleşmiyor veya dosya yoksa False — MyCL pasif kalır.

    Test bypass: `MYCL_TEST_FORCE_ACTIVE=1` env varsa True döner. Bu
    sadece test ortamı için; kullanıcı runtime'ında set edilmez.
    """
    if os.environ.get("MYCL_TEST_FORCE_ACTIVE") == "1":
        return True
    if not session_id or not session_id.strip():
        return False
    path = _active_session_path(project_root)
    try:
        stored = path.read_text(encoding="utf-8").strip()
    except OSError:
        return False
    return stored == session_id.strip()


def deactivate(project_root: str | None = None) -> None:
    """Test/diagnostic için: aktif session kaydını sil."""
    path = _active_session_path(project_root)
    try:
        path.unlink()
    except OSError:
        pass
