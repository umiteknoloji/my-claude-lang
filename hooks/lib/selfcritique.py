"""selfcritique — Faz sonu zorunlu self-critique (Disiplin #8).

Pseudocode + CLAUDE.md disiplin katmanı #8.

Sözleşme:
    - Faz tamamlanma audit'inden ÖNCE model "bu fazda eksik bıraktığım
      var mı?" sorgulasın.
    - Cevap "yok" ise audit emit izin (faz advance gate'inde).
    - Cevap "var" ise eksiği gidermeden audit emit edilemez.
    - gate_spec.json `self_critique_required: true` olan fazlar için
      hook bu kontrol yapacak.

Audit:
    selfcritique-passed phase=N
    selfcritique-gap-found phase=N items="..."

API:
    selfcritique_prompt(phase) → "TR\\n\\nEN" (bilingual'dan)
    record_passed(phase) — audit
    record_gap(phase, items) — audit
    latest_for_phase(phase) → dict | None
    is_passed_for_phase(phase) → bool
"""

from __future__ import annotations

from hooks.lib import audit, bilingual

_PROMPT_KEY = "self_critique_request"
_AUDIT_PASSED = "selfcritique-passed"
_AUDIT_GAP = "selfcritique-gap-found"


def selfcritique_prompt(phase: int) -> str:
    """Model'e self-critique istemi (TR + EN, bilingual.py)."""
    return bilingual.render(_PROMPT_KEY, phase=phase)


def record_passed(
    phase: int,
    caller: str = "stop.py",
    project_root: str | None = None,
) -> None:
    """Self-critique geçti — eksik yok."""
    audit.log_event(
        _AUDIT_PASSED,
        caller,
        f"phase={phase}",
        project_root=project_root,
    )


def record_gap(
    phase: int,
    items: str,
    caller: str = "stop.py",
    project_root: str | None = None,
) -> None:
    """Self-critique eksik tespit etti."""
    if not items:
        items = "unspecified"
    truncated = items.strip().replace("\n", " ").replace(" | ", " / ")
    if len(truncated) > 200:
        truncated = truncated[:197] + "..."
    audit.log_event(
        _AUDIT_GAP,
        caller,
        f'phase={phase} items="{truncated}"',
        project_root=project_root,
    )


def latest_for_phase(
    phase: int,
    project_root: str | None = None,
) -> dict | None:
    """Bu fazın son self-critique audit'i (passed veya gap)."""
    target = f"phase={phase}"
    all_audits = audit.read_all(project_root=project_root)
    for ev in reversed(all_audits):
        name = ev.get("name", "")
        if name not in (_AUDIT_PASSED, _AUDIT_GAP):
            continue
        if target in ev.get("detail", ""):
            return ev
    return None


def is_passed_for_phase(
    phase: int,
    project_root: str | None = None,
) -> bool:
    """Bu fazda self-critique geçti mi?

    Mantık: en son audit `selfcritique-passed` ise True.
    `selfcritique-gap-found` veya hiç audit yoksa False.
    """
    ev = latest_for_phase(phase, project_root=project_root)
    if ev is None:
        return False
    return ev.get("name") == _AUDIT_PASSED
