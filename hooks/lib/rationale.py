"""rationale — Tool öncesi 1 satır niyet beyanı (Disiplin #2).

Pseudocode + CLAUDE.md disiplin katmanı #2.

Sözleşme:
    - Mutating tool çağrısı öncesi (Write/Edit/Bash mutating) model'in
      1 satır gerekçe yazması istenir: "hangi MUST karşılanıyor, hangi
      dosya, neden".
    - `record_rationale(text, tool, file_path)` audit'e yazar:
      `rationale-stated tool=X file=Y must=Z reason="..."`.
    - Stop hook turn sonu rationale-stated audit'lerini gözden geçirip
      orphan tool çağrılarını ortaya çıkarır (rationale'sız mutating
      tool — opsiyonel uyarı).
    - Goodhart riski düşük: söz puansız, kestirme atmayı zorlaştırır.

Audit-driven: state'te alan yok.

API:
    rationale_prompt() → "TR\\n\\nEN" (bilingual'dan)
    record_rationale(text, tool, file_path, must=None, ...)
    latest_for_tool(tool) → audit dict | None
    has_rationale_for_call(tool, file_path, ...) → bool
"""

from __future__ import annotations

from hooks.lib import audit, bilingual

_RATIONALE_KEY = "rationale_request"
_AUDIT_NAME = "rationale-stated"


def rationale_prompt() -> str:
    """Model'e "1 satır gerekçe" istemi (TR + EN, bilingual.py'den)."""
    return bilingual.render(_RATIONALE_KEY)


def record_rationale(
    text: str,
    tool: str,
    file_path: str | None = None,
    must: str | None = None,
    caller: str = "pre_tool.py",
    project_root: str | None = None,
) -> None:
    """Rationale audit'e yaz.

    detail format: `tool=X file=Y must=MUST_N reason="..."`.
    text 200 char truncate, pipe ' | ' → ' / '.
    """
    if not text or not tool:
        return
    truncated = text.strip().replace("\n", " ").replace(" | ", " / ")
    if len(truncated) > 200:
        truncated = truncated[:197] + "..."
    parts = [f"tool={tool}"]
    if file_path:
        parts.append(f"file={file_path}")
    if must:
        parts.append(f"must={must}")
    parts.append(f'reason="{truncated}"')
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
    """Belirli tool için son rationale audit'i."""
    if not tool:
        return None
    matches = audit.find(name=_AUDIT_NAME, project_root=project_root)
    target = f"tool={tool}"
    for ev in reversed(matches):
        if target in ev.get("detail", ""):
            return ev
    return None


def has_rationale_for_call(
    tool: str,
    file_path: str | None = None,
    project_root: str | None = None,
) -> bool:
    """Bu tool+file için rationale audit'i var mı?

    file_path None ise sadece tool eşleşmesi yeterli.
    """
    if not tool:
        return False
    matches = audit.find(name=_AUDIT_NAME, project_root=project_root)
    tool_key = f"tool={tool}"
    file_key = f"file={file_path}" if file_path else None
    for ev in matches:
        detail = ev.get("detail", "")
        if tool_key not in detail:
            continue
        if file_key is None or file_key in detail:
            return True
    return False
