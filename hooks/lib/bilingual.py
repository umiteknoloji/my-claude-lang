"""bilingual — TR + EN mesaj render (tek noktadan).

Pseudocode referansı: MyCL_Pseudocode.md çift dil çıktı kuralı +
CLAUDE.md captured-rule "TR + EN only" + Disiplin #11.

Sözleşme:
    - `data/bilingual_messages.json` mesajları tutar; her key
      `{"tr": "...", "en": "..."}` çifti.
    - render(key, **kwargs) → "TR_block\n\nEN_block" (boş satır ayırır).
    - Etiket (TR:/EN:) yok — gereksiz gürültü.
    - kwargs ile `{phase}`, `{tool}`, `{strike}` placeholder doldurur.
    - Eksik key veya eksik placeholder → fail-safe (key adı + raw kwargs).

İstisnalar (CLAUDE.md kuralı, çevrilmez):
    Kod tanımlayıcıları, dosya yolları, audit isimleri, CLI komutları,
    sabit teknik tokenlar (MUST/SHOULD). Bu lib genel mesajlar için;
    teknik token'lar mesaj içinde inline kalır.

API:
    load_messages(path=None)  — JSON yükle (cache)
    render(key, **kwargs)     → "TR\n\nEN"
    render_tr / render_en     — tek dil (testing/special-case)
    has_key(key)              → bool
    reset_cache()             — test/runtime cache temizle
"""

from __future__ import annotations

import json
from pathlib import Path

# Process-global cache
_messages_cache: dict | None = None

_DEFAULT_EMPTY: dict[str, dict] = {"messages": {}}


def _data_dir_candidates() -> list[Path]:
    return [
        Path.home() / ".claude" / "data",
        Path(__file__).resolve().parent.parent.parent / "data",
    ]


def load_messages(path: str | Path | None = None) -> dict:
    """bilingual_messages.json yükle. path verilmezse data dizini ara."""
    global _messages_cache
    if path is None and _messages_cache is not None:
        return _messages_cache

    if path is not None:
        p: Path | None = Path(path)
    else:
        p = None
        for c in _data_dir_candidates():
            cand = c / "bilingual_messages.json"
            if cand.exists():
                p = cand
                break

    if p is None or not p.exists():
        return _DEFAULT_EMPTY

    try:
        with p.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return _DEFAULT_EMPTY

    if not isinstance(data, dict) or "messages" not in data:
        return _DEFAULT_EMPTY

    if path is None:
        _messages_cache = data
    return data


def reset_cache() -> None:
    global _messages_cache
    _messages_cache = None


def has_key(key: str, messages: dict | None = None) -> bool:
    """key bilingual_messages içinde tanımlı mı?"""
    msgs = messages if messages is not None else load_messages()
    return key in msgs.get("messages", {})


def _safe_format(template: str, kwargs: dict) -> str:
    """str.format ama eksik placeholder hata vermez — placeholder'ı korur."""
    if not template:
        return ""
    try:
        return template.format(**kwargs)
    except (KeyError, IndexError, ValueError):
        # Eksik veya hatalı placeholder → orijinal template (debug için).
        return template


def render_tr(
    key: str,
    messages: dict | None = None,
    **kwargs,
) -> str:
    """Sadece Türkçe blok render. Eksik key → key adını döner."""
    msgs = messages if messages is not None else load_messages()
    entry = msgs.get("messages", {}).get(key)
    if not isinstance(entry, dict):
        return f"[{key}]"
    return _safe_format(entry.get("tr", ""), kwargs)


def render_en(
    key: str,
    messages: dict | None = None,
    **kwargs,
) -> str:
    """Sadece İngilizce blok render."""
    msgs = messages if messages is not None else load_messages()
    entry = msgs.get("messages", {}).get(key)
    if not isinstance(entry, dict):
        return f"[{key}]"
    return _safe_format(entry.get("en", ""), kwargs)


def render(
    key: str,
    messages: dict | None = None,
    **kwargs,
) -> str:
    """TR + EN render → 'TR\\n\\nEN' (boş satır ayraç).

    Eksik key → '[key]\\n\\n[key]' (debug-friendly fail-safe).
    Tek dil eksikse (sadece tr veya sadece en) → mevcut dili döner.
    """
    msgs = messages if messages is not None else load_messages()
    entry = msgs.get("messages", {}).get(key)
    if not isinstance(entry, dict):
        return f"[{key}]"

    tr = _safe_format(entry.get("tr", ""), kwargs)
    en = _safe_format(entry.get("en", ""), kwargs)

    if tr and en:
        return f"{tr}\n\n{en}"
    if tr:
        return tr
    if en:
        return en
    return f"[{key}]"
