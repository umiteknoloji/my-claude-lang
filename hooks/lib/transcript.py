"""transcript — Claude Code JSONL parser.

Pseudocode referansı: MyCL_Pseudocode.md §2 Stop hook adım 1
(Spec bloğu son assistant text'inden çıkarılır) + adım 2 (askq onay
intent classification için tool_use + tool_result eşleştirme).

Claude Code transcript formatı:
    Her satır JSON-encoded bir event. Tip alanları:
    - "user": kullanıcı mesajı veya tool_result
    - "assistant": modelin cevabı (text + tool_use blokları)
    - "system": meta event'ler

    Assistant mesajları içerik bloklarına bölünür:
    - {"type": "text", "text": "..."}
    - {"type": "tool_use", "id": "<uuid>", "name": "AskUserQuestion", "input": {...}}

    User mesajlarında AskUserQuestion sonrası şu tipte tool_result:
    - {"type": "tool_result", "tool_use_id": "<uuid>", "content": "..."}

Sözleşme:
    - Bozuk JSON satırı atla (forward-compat).
    - Var olmayan dosya / okunamayan dosya → boş yield.
    - Sadece "type" alanı varsa ve assistant ise text çıkar (forward-compat
      için "message.content" da kontrol edilir).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Iterator, Optional


def iter_messages(transcript_path: str | Path) -> Iterator[dict]:
    """JSONL transcript'i satır satır yield le; bozuk satırları atla."""
    p = Path(transcript_path)
    if not p.exists() or not p.is_file():
        return
    try:
        with p.open("r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue
    except OSError:
        return


def _content_blocks(msg: dict) -> list:
    """Mesajın content listesini güvenle döner."""
    inner = msg.get("message") if isinstance(msg.get("message"), dict) else msg
    content = inner.get("content") if isinstance(inner, dict) else None
    if isinstance(content, list):
        return content
    return []


def _is_assistant(msg: dict) -> bool:
    if msg.get("type") == "assistant":
        return True
    inner = msg.get("message")
    if isinstance(inner, dict) and inner.get("role") == "assistant":
        return True
    return False


def _is_user(msg: dict) -> bool:
    if msg.get("type") == "user":
        return True
    inner = msg.get("message")
    if isinstance(inner, dict) and inner.get("role") == "user":
        return True
    return False


def _extract_text(msg: dict) -> Optional[str]:
    """Assistant mesajının birleştirilmiş text'ini döner."""
    if not _is_assistant(msg):
        return None
    blocks = _content_blocks(msg)
    parts: list[str] = []
    for item in blocks:
        if isinstance(item, dict) and item.get("type") == "text":
            t = item.get("text")
            if isinstance(t, str):
                parts.append(t)
    if not parts:
        # content string olabilir (eski format)
        inner = msg.get("message") if isinstance(msg.get("message"), dict) else msg
        c = inner.get("content") if isinstance(inner, dict) else None
        if isinstance(c, str):
            return c
    return "\n".join(parts) if parts else None


def last_assistant_text(transcript_path: str | Path) -> Optional[str]:
    """Son assistant turn'ünün birleştirilmiş text'i (yoksa None)."""
    last: Optional[str] = None
    for msg in iter_messages(transcript_path):
        text = _extract_text(msg)
        if text:
            last = text
    return last


def find_last_assistant_text_matching(
    predicate, transcript_path: str | Path
) -> Optional[str]:
    """predicate(text) True olan en son assistant text'i.

    Stop hook spec_detect.find() bunu kullanır: spec block içeren en son
    turn (trailing prose ile gizlenmemiş) döner.
    """
    last: Optional[str] = None
    for msg in iter_messages(transcript_path):
        text = _extract_text(msg)
        if text and predicate(text):
            last = text
    return last


# ---------- AskUserQuestion eşleştirme ----------


def iter_askq_uses(transcript_path: str | Path) -> Iterator[dict]:
    """AskUserQuestion tool_use bloklarını sırayla yield le."""
    for msg in iter_messages(transcript_path):
        if not _is_assistant(msg):
            continue
        for item in _content_blocks(msg):
            if (
                isinstance(item, dict)
                and item.get("type") == "tool_use"
                and item.get("name") == "AskUserQuestion"
            ):
                yield item


def iter_tool_results(transcript_path: str | Path) -> Iterator[dict]:
    """User mesajlarındaki tool_result bloklarını yield le."""
    for msg in iter_messages(transcript_path):
        if not _is_user(msg):
            continue
        for item in _content_blocks(msg):
            if isinstance(item, dict) and item.get("type") == "tool_result":
                yield item


def latest_askq_pair(
    transcript_path: str | Path,
) -> tuple[Optional[dict], Optional[dict]]:
    """En son AskUserQuestion tool_use + ona ait tool_result çifti.

    Returns:
        (use_block, result_block) — biri yoksa None.
        Eşleştirme `id` ↔ `tool_use_id` üzerinden.
    """
    uses = list(iter_askq_uses(transcript_path))
    if not uses:
        return None, None
    last_use = uses[-1]
    use_id = last_use.get("id")
    if not use_id:
        return last_use, None
    for r in iter_tool_results(transcript_path):
        if r.get("tool_use_id") == use_id:
            return last_use, r
    return last_use, None


def last_user_text(transcript_path: str | Path) -> Optional[str]:
    """Son user turn'ünün düz text içeriği (tool_result hariç).

    H-2 fix: AskUserQuestion kullanılmadan gönderilen onay text'lerini
    stop hook'a taşımak için. Sadece string content veya type=text
    blokları alınır; tool_result ve diğer structured content atlanır.
    """
    last: Optional[str] = None
    for msg in iter_messages(transcript_path):
        if not _is_user(msg):
            continue
        blocks = _content_blocks(msg)
        # tool_result içeren user turn'leri atla (bunlar AskQ cevabı)
        has_tool_result = any(
            isinstance(b, dict) and b.get("type") == "tool_result"
            for b in blocks
        )
        if has_tool_result:
            continue
        parts: list[str] = []
        for b in blocks:
            if isinstance(b, dict) and b.get("type") == "text":
                t = b.get("text")
                if isinstance(t, str):
                    parts.append(t)
            elif isinstance(b, str):
                parts.append(b)
        # Düz string content (eski format)
        if not parts:
            inner = msg.get("message") if isinstance(msg.get("message"), dict) else msg
            c = inner.get("content") if isinstance(inner, dict) else None
            if isinstance(c, str):
                parts.append(c)
        if parts:
            last = "\n".join(parts)
    return last
