"""confidence — Per-tool confidence skoru (Disiplin #9).

Pseudocode + CLAUDE.md disiplin katmanı #9.

Sözleşme:
    - Mutating tool çağrısı öncesi model 0-100 confidence skoru yazar.
    - <60: model kendisi AskUserQuestion açar (low confidence warning).
    - 60-80: nötr; tool çağrısı geçer (audit kayıt).
    - >80: yüksek confidence, geçer.
    - Self-awareness mecburiyeti — Goodhart riski düşük (skor caller'a
      bilgi, hard gate değil).

Audit: `confidence-stated tool=X score=N file=Y`

Eşikler veri olarak (gate_spec.json'a değil, bu modül sabit):
    LOW_THRESHOLD = 60   — altı ise askq tetikle
    HIGH_THRESHOLD = 80  — üstü ise sessiz geç

API:
    confidence_prompt(score) → "TR\\n\\nEN" warning (low ise)
    record_confidence(score, tool, file_path)
    is_low(score) / is_high(score)
    latest_for_tool(tool) → audit | None
    score_from_audit(audit_dict) → int | None
"""

from __future__ import annotations

import re

from hooks.lib import audit, bilingual

LOW_THRESHOLD = 60
HIGH_THRESHOLD = 80
_AUDIT_NAME = "confidence-stated"
_PROMPT_KEY = "confidence_low_warning"
_SCORE_RE = re.compile(r"score=(\d+)")


def is_low(score: int) -> bool:
    """score LOW_THRESHOLD'un altında mı?"""
    return score < LOW_THRESHOLD


def is_high(score: int) -> bool:
    """score HIGH_THRESHOLD'un üstünde mi?"""
    return score > HIGH_THRESHOLD


def low_confidence_warning(score: int) -> str:
    """Düşük confidence durumu için TR+EN warning."""
    return bilingual.render(_PROMPT_KEY, score=score)


def record_confidence(
    score: int,
    tool: str,
    file_path: str | None = None,
    caller: str = "pre_tool.py",
    project_root: str | None = None,
) -> None:
    """Confidence skorunu audit'e yaz.

    detail format: `tool=X score=N file=Y`.
    Score 0-100 dışı → 0/100'e clamp.
    """
    if not tool:
        return
    try:
        s = int(score)
    except (TypeError, ValueError):
        return
    s = max(0, min(100, s))
    parts = [f"tool={tool}", f"score={s}"]
    if file_path:
        parts.append(f"file={file_path}")
    audit.log_event(
        _AUDIT_NAME,
        caller,
        " ".join(parts),
        project_root=project_root,
    )


def latest_for_tool(
    tool: str,
    project_root: str | None = None,
) -> dict | None:
    """Belirli tool için son confidence audit'i."""
    if not tool:
        return None
    target = f"tool={tool}"
    matches = audit.find(name=_AUDIT_NAME, project_root=project_root)
    for ev in reversed(matches):
        if target in ev.get("detail", ""):
            return ev
    return None


def score_from_audit(audit_dict: dict | None) -> int | None:
    """Audit detail'inden score değerini çıkar."""
    if not isinstance(audit_dict, dict):
        return None
    detail = audit_dict.get("detail", "")
    m = _SCORE_RE.search(detail)
    if not m:
        return None
    try:
        return int(m.group(1))
    except ValueError:
        return None
