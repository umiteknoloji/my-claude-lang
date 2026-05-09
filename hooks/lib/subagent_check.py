"""subagent_check — Rubber-duck subagent pair-check (Disiplin #17).

Pseudocode + CLAUDE.md disiplin katmanı #17.

Sözleşme:
    - Stop hook kritik faz sonrası (4 spec, 9 TDD, 10 risk, 22 tamlık)
      gate_spec.json `subagent_rubber_duck: true` olan fazlar için
      ucuz Haiku subagent'ı çağırıp "bu faz mantıklı tamamlandı mı?"
      sorgular.
    - Subagent çağrısı **hook process** seviyesinde yapılır
      (Claude Code `Task` tool veya CLI subprocess); bu modül **prompt
      tasarımı + audit kayıt** sunar.
    - 1.0.0'da subagent çağrısı opsiyonel; gate_spec.json hangi fazda
      tetiklenmesi gerektiğini söyler, asıl çağrı stop.py'da olur.
    - Cost'u kullanıcı görsün — subagent çağrıları audit'e açıkça
      kaydedilir.

API:
    should_trigger(phase, gate_spec) → bool
    rubber_duck_prompt(phase, phase_summary) → str (subagent'a istek)
    record_check(phase, verdict, summary) — audit
    latest_for_phase(phase) → audit | None
"""

from __future__ import annotations

from hooks.lib import audit, gate

_AUDIT_NAME = "subagent-rubber-duck"
_VALID_VERDICTS = {"passed", "concerned", "failed"}


def should_trigger(
    phase: int,
    gate_spec: dict | None = None,
) -> bool:
    """Bu fazda subagent rubber-duck tetiklensin mi?

    gate_spec.json'da `subagent_rubber_duck: true` olan fazlar için
    True. Plan kararı: 4 / 9 / 10 / 22.
    """
    spec = gate_spec if gate_spec is not None else gate.load_gate_spec()
    phase_def = spec.get("phases", {}).get(str(phase), {})
    return bool(phase_def.get("subagent_rubber_duck", False))


def rubber_duck_prompt(
    phase: int,
    phase_summary: str = "",
) -> str:
    """Haiku subagent'a istek metni.

    Subagent küçük, hızlı, ucuz. "Bu faz mantıklı tamamlandı mı?"
    sorgusu + faz özeti ile çağrılır. Dönüş: 1 cümle "passed" |
    "concerned" | "failed" + sebep.

    Returns:
        Subagent prompt (English — model işlem dili).
    """
    return (
        f"Pair-check for MyCL Phase {phase}.\n\n"
        f"Summary of what happened in this phase:\n{phase_summary or '(no summary)'}\n\n"
        f"Question: did this phase complete coherently? Look for:\n"
        f"- missing required outputs\n"
        f"- contradictions with the spec\n"
        f"- skipped sub-steps\n\n"
        f"Respond with ONE LINE in this format:\n"
        f"  verdict=<passed|concerned|failed> reason=<one short sentence>"
    )


def record_check(
    phase: int,
    verdict: str,
    summary: str = "",
    caller: str = "stop.py",
    project_root: str | None = None,
) -> None:
    """Subagent rubber-duck sonucunu audit'e yaz.

    detail format: `phase=N verdict=X summary="..."`.
    Geçersiz verdict → reject (bilinen 3 değer dışında).
    """
    if verdict not in _VALID_VERDICTS:
        return
    truncated = summary.strip().replace("\n", " ").replace(" | ", " / ")
    if len(truncated) > 200:
        truncated = truncated[:197] + "..."
    audit.log_event(
        _AUDIT_NAME,
        caller,
        f'phase={phase} verdict={verdict} summary="{truncated}"',
        project_root=project_root,
    )


def latest_for_phase(
    phase: int,
    project_root: str | None = None,
) -> dict | None:
    """Belirli fazın son rubber-duck audit'i."""
    target = f"phase={phase}"
    matches = audit.find(name=_AUDIT_NAME, project_root=project_root)
    for ev in reversed(matches):
        if target in ev.get("detail", ""):
            return ev
    return None
