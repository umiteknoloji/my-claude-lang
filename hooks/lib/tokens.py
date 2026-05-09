"""tokens — Token visibility (Disiplin #7, para YOK).

Pseudocode + CLAUDE.md disiplin katmanı #7 + design principle
"para tutarı görünür yapılmaz; token sayısı OK".

Sözleşme:
    - Stop hook her tur sonu turn-token sayısını record_turn(count)
      ile audit'e + state'e yazar.
    - state.total_tokens cumulative sayım tutar.
    - format_visibility(turn, total) bilingual TR + EN render.
    - USD/cost YOK — caller cost.json okumaz veya $/token hesaplamaz.

Audit: `tokens-turn count=N total=M`

API:
    record_turn(count) — audit + state cumulative
    total_tokens() → int
    format_visibility(turn_tokens, total_tokens) → "TR\\n\\nEN"
"""

from __future__ import annotations

from hooks.lib import audit, bilingual, state

_AUDIT_NAME = "tokens-turn"


def record_turn(
    count: int,
    caller: str = "stop.py",
    project_root: str | None = None,
) -> int:
    """Turn token sayısını audit + state cumulative.

    Geçersiz count (str/None/negatif) → 0 olarak yorumla, kayıt atlanır.

    Returns:
        Yeni cumulative total.
    """
    try:
        n = int(count)
    except (TypeError, ValueError):
        return total_tokens(project_root=project_root)
    if n < 0:
        return total_tokens(project_root=project_root)

    current_total = total_tokens(project_root=project_root)
    new_total = current_total + n
    state.set_field("total_tokens", new_total, project_root=project_root)
    audit.log_event(
        _AUDIT_NAME,
        caller,
        f"count={n} total={new_total}",
        project_root=project_root,
    )
    return new_total


def total_tokens(project_root: str | None = None) -> int:
    """state'ten cumulative total."""
    val = state.get("total_tokens", 0, project_root=project_root)
    try:
        return int(val)
    except (TypeError, ValueError):
        return 0


def format_visibility(
    turn_tokens: int,
    total_tokens_val: int | None = None,
    project_root: str | None = None,
) -> str:
    """Token visibility mesajı (TR + EN, para YOK).

    bilingual.py 'token_visibility' key'i:
        TR: "Bu tur ~{turn_tokens} token, oturum toplamı ~{total_tokens} token."
        EN: "This turn ~{turn_tokens} tokens, session total ~{total_tokens} tokens."
    """
    total = total_tokens_val if total_tokens_val is not None else total_tokens(
        project_root=project_root
    )
    return bilingual.render(
        "token_visibility",
        turn_tokens=turn_tokens,
        total_tokens=total,
    )
