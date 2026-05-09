"""framing — Co-author manifesto + somut maliyet hikayesi (Disiplin #14, #15).

Pseudocode + CLAUDE.md disiplin katmanları:
    #14: Co-author framing (adversarial yerine kollaboratif)
    #15: Somut negatif örnek hikaye (47 dakika rework)

Sözleşme:
    - `data/manifesto.txt` çift dil (TR + EN) önceden formatlı.
    - Manifesto STATIC_CONTEXT bloğuna gömülür (activate.py her tur).
    - İçerik önişlemine gerek yok — manifesto.txt zaten render-ready.
    - Cache: ilk yüklemede process-global.

API:
    load_manifesto(path=None) → str (full text)
    for_context() → str (STATIC_CONTEXT'e gömülecek tam metin)
    reset_cache()
"""

from __future__ import annotations

from pathlib import Path

_manifesto_cache: str | None = None
_DEFAULT_EMPTY = ""


def _data_dir_candidates() -> list[Path]:
    return [
        Path.home() / ".claude" / "data",
        Path(__file__).resolve().parent.parent.parent / "data",
    ]


def load_manifesto(path: str | Path | None = None) -> str:
    """manifesto.txt yükle. path verilmezse data dizini ara."""
    global _manifesto_cache
    if path is None and _manifesto_cache is not None:
        return _manifesto_cache

    if path is not None:
        p: Path | None = Path(path)
    else:
        p = None
        for c in _data_dir_candidates():
            cand = c / "manifesto.txt"
            if cand.exists():
                p = cand
                break

    if p is None or not p.exists():
        return _DEFAULT_EMPTY

    try:
        text = p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return _DEFAULT_EMPTY

    if path is None:
        _manifesto_cache = text
    return text


def reset_cache() -> None:
    global _manifesto_cache
    _manifesto_cache = None


def for_context() -> str:
    """STATIC_CONTEXT'e gömülecek tam manifesto metni.

    activate.py her tur sonu STATIC_CONTEXT bloğunu hazırlarken çağırır.
    """
    return load_manifesto()
