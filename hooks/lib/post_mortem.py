"""post_mortem — 5 strike escalation template (Disiplin #18).

CLAUDE.md captured-rule: 5 strike sonrası `*-escalation-needed` audit
yazılır + post-mortem template açılır. Model "neden tıkandım?"
yazılı raporlar; bir sonraki turn DSI'ya bilgi sinyali.

Sözleşme:
    - Pre_tool veya stop hook 5 strike eşiği aşıldığında
      `post_mortem_prompt(block_kind)` ile model'e template gösterir.
    - Model 1 paragraf yazar; `record(block_kind, content)` audit'e gömülür.
    - Audit: `post-mortem-recorded block_kind=X content="..."`.

API:
    post_mortem_prompt(block_kind) → "TR\\n\\nEN"
    record(block_kind, content) — audit + truncate
    latest_for_block(block_kind) → audit | None
"""

from __future__ import annotations

from hooks.lib import audit, bilingual

_PROMPT_KEY = "post_mortem_template"
_AUDIT_NAME = "post-mortem-recorded"


def post_mortem_prompt(block_kind: str) -> str:
    """5 strike escalation sonrası post-mortem template (TR + EN).

    bilingual.py 'post_mortem_template' key'ini kullanır.
    """
    return bilingual.render(_PROMPT_KEY, block_kind=block_kind)


def record(
    block_kind: str,
    content: str,
    caller: str = "stop.py",
    project_root: str | None = None,
) -> None:
    """Post-mortem içeriğini audit'e yaz.

    detail format: `block_kind=X content="..."` (300 char truncate).
    """
    if not block_kind or not content:
        return
    truncated = content.strip().replace("\n", " ").replace(" | ", " / ")
    if len(truncated) > 300:
        truncated = truncated[:297] + "..."
    audit.log_event(
        _AUDIT_NAME,
        caller,
        f'block_kind={block_kind} content="{truncated}"',
        project_root=project_root,
    )


def latest_for_block(
    block_kind: str,
    project_root: str | None = None,
) -> dict | None:
    """Belirli block_kind için son post-mortem audit'i."""
    if not block_kind:
        return None
    matches = audit.find(name=_AUDIT_NAME, project_root=project_root)
    target = f"block_kind={block_kind}"
    for ev in reversed(matches):
        if target in ev.get("detail", ""):
            return ev
    return None
