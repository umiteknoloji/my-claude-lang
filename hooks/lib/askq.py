"""askq — AskUserQuestion intent classifier (TR + EN).

Pseudocode referansı: MyCL_Pseudocode.md §2 Stop hook adım 2 (askq
onayı işle) + §3 Aşama 7 deferred (free-form intent classification).

Sözleşme:
    - `data/approve_cues.json` TR + EN sözcükleri tutar (1.0.0
      kararı: 14 dil → 2 dil).
    - classify(text) → "approve" | "revise" | "cancel" | "ambiguous".
    - Sıralama (Aşama 7 pseudocode kuralı):
        cancel > revise > approve > ambiguous.
        "Approve + revise birlikte" (örn. "güzel ama büyüt") → revise
        kazanır.
    - Match word-boundary (`\b`) — Türkçe morfolojik ekler düzgün
      ayrılır; "değiştirme yok" cümlesi "değiştir" cue'unu **match
      etmez** (false positive korumalı).
    - Cache: ilk yüklemede approve_cues.json process-global cache'lenir.
      Test'lerde explicit `cues=...` parametresi cache'i bypass eder.

API:
    classify(text, cues=None)         → intent string
    is_approve / is_revise / is_cancel → quick predicate
    extract_result_text(result)       → tool_result content → text
    classify_tool_result(result)      → result → intent
    load_cues(path=None)              → JSON yükle (cache)
"""

from __future__ import annotations

import json
import re
from pathlib import Path

INTENT_APPROVE = "approve"
INTENT_REVISE = "revise"
INTENT_CANCEL = "cancel"
INTENT_AMBIGUOUS = "ambiguous"

_DEFAULT_EMPTY_CUES: dict[str, dict[str, list[str]]] = {
    "approve": {"tr": [], "en": []},
    "revise": {"tr": [], "en": []},
    "cancel": {"tr": [], "en": []},
}

# Process-global cache (test'lerde explicit cues=... ile bypass)
_cues_cache: dict | None = None


def _data_dir_candidates() -> list[Path]:
    """approve_cues.json arama yerleri (sırayla):

    1. ~/.claude/data/ — setup.sh kurulumda buraya kopyalar
    2. <repo>/data/ — geliştirme sırasında repo'dan
    """
    return [
        Path.home() / ".claude" / "data",
        Path(__file__).resolve().parent.parent.parent / "data",
    ]


def load_cues(path: str | Path | None = None) -> dict:
    """approve_cues.json yükle. path verilmezse data dizini ara."""
    global _cues_cache
    if path is None and _cues_cache is not None:
        return _cues_cache

    if path is not None:
        p = Path(path)
    else:
        p = None
        for c in _data_dir_candidates():
            cand = c / "approve_cues.json"
            if cand.exists():
                p = cand
                break

    if p is None or not p.exists():
        # Fallback: dosya yok → boş set ile dön (ambiguous her şey).
        return _DEFAULT_EMPTY_CUES

    try:
        with p.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return _DEFAULT_EMPTY_CUES

    if path is None:
        _cues_cache = data
    return data


def reset_cache() -> None:
    """Test/runtime'da cache'i temizler."""
    global _cues_cache
    _cues_cache = None


def _normalize(text: str | None) -> str:
    """Lowercase + trim, Türkçe locale-aware.

    Python varsayılan `str.lower()` Unicode kuralına göre çalışır:
    `"İ".lower()` → `"i̇"` (i + combining dot), düz `i` değil. Bu cue
    listesindeki `"iptal"` ile word-boundary match'i bozuyordu (KK
    bulgusu). Explicit `İ → i` çevirisi Türkçe locale doğrultusunda;
    `I` ASCII korunur (İngilizce context'te `I → ı` yanlış olur).
    """
    if not text:
        return ""
    return text.replace("İ", "i").lower().strip()


def _cue_list(intent: str, cues: dict) -> list[str]:
    bucket = cues.get(intent, {})
    if not isinstance(bucket, dict):
        return []
    out: list[str] = []
    for lang in ("tr", "en"):
        items = bucket.get(lang, [])
        if isinstance(items, list):
            out.extend(items)
    return out


def _matches_intent(text_norm: str, cues: dict, intent: str) -> bool:
    """Word-boundary match — substring false positive'leri engeller."""
    for cue in _cue_list(intent, cues):
        cue_norm = cue.lower().strip() if isinstance(cue, str) else ""
        if not cue_norm:
            continue
        # Multi-word cue veya tek kelime — `\b` Unicode-aware
        pattern = r"\b" + re.escape(cue_norm) + r"\b"
        if re.search(pattern, text_norm, flags=re.UNICODE):
            return True
    return False


def classify(text: str | None, cues: dict | None = None) -> str:
    """Text'i intent'e sınıflandır.

    Sıralama (Aşama 7 pseudocode kuralı):
        cancel > revise > approve > ambiguous.

    Geçersiz/boş input → ambiguous.
    """
    norm = _normalize(text)
    if not norm:
        return INTENT_AMBIGUOUS
    cues = cues if cues is not None else load_cues()

    if _matches_intent(norm, cues, "cancel"):
        return INTENT_CANCEL
    if _matches_intent(norm, cues, "revise"):
        return INTENT_REVISE
    if _matches_intent(norm, cues, "approve"):
        return INTENT_APPROVE
    return INTENT_AMBIGUOUS


def is_approve(text: str | None, cues: dict | None = None) -> bool:
    return classify(text, cues) == INTENT_APPROVE


def is_revise(text: str | None, cues: dict | None = None) -> bool:
    return classify(text, cues) == INTENT_REVISE


def is_cancel(text: str | None, cues: dict | None = None) -> bool:
    return classify(text, cues) == INTENT_CANCEL


# ---------- tool_result entegrasyonu ----------


def extract_result_text(result: dict | None) -> str:
    """tool_result bloğundan text çıkar.

    Claude Code formatları (kabul edilen tüm varyantlar):
        {"content": "Onayla"}
        {"content": [{"type": "text", "text": "User selected: Onayla"}]}
        {"content": [{"text": "..."}]}  # type alanı eksik
        {"content": [{"type": "tool_result", "content": "..."}]}  # nested
        {"answer": "Onayla"}            # bazı eski sürümler
    """
    if not isinstance(result, dict):
        return ""
    # 1. Düz content alanı
    content = result.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, dict):
                t = item.get("text")
                if isinstance(t, str):
                    parts.append(t)
                else:
                    inner = item.get("content")
                    if isinstance(inner, str):
                        parts.append(inner)
            elif isinstance(item, str):
                parts.append(item)
        if parts:
            return "\n".join(parts)
    # 2. answer fallback
    ans = result.get("answer")
    if isinstance(ans, str):
        return ans
    return ""


def classify_tool_result(
    result: dict | None, cues: dict | None = None
) -> str:
    """tool_result bloğunu classify et (extract + classify)."""
    return classify(extract_result_text(result), cues)
