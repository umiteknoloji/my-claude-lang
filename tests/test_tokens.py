"""hooks/lib/tokens.py birim testleri."""

from __future__ import annotations

from hooks.lib import audit, state, tokens


# ---------- record_turn ----------


def test_record_turn_writes_audit(tmp_project):
    tokens.record_turn(1500)
    ev = audit.latest("tokens-turn")
    assert ev is not None
    assert "count=1500" in ev["detail"]
    assert "total=1500" in ev["detail"]


def test_record_turn_accumulates(tmp_project):
    tokens.record_turn(1000)
    tokens.record_turn(500)
    tokens.record_turn(200)
    assert tokens.total_tokens() == 1700


def test_record_turn_state_persists(tmp_project):
    tokens.record_turn(800)
    assert state.get("total_tokens") == 800
    tokens.record_turn(100)
    assert state.get("total_tokens") == 900


def test_record_turn_invalid_count_skipped(tmp_project):
    """Geçersiz count → kayıt atlanır, total değişmez."""
    tokens.record_turn(500)
    tokens.record_turn("not a number")  # type: ignore[arg-type]
    tokens.record_turn(None)  # type: ignore[arg-type]
    tokens.record_turn(-100)
    assert tokens.total_tokens() == 500


def test_record_turn_returns_new_total(tmp_project):
    assert tokens.record_turn(1000) == 1000
    assert tokens.record_turn(500) == 1500


# ---------- total_tokens ----------


def test_total_tokens_default_zero(tmp_project):
    assert tokens.total_tokens() == 0


def test_total_tokens_from_state(tmp_project):
    state.set_field("total_tokens", 5000)
    assert tokens.total_tokens() == 5000


# ---------- format_visibility (Disiplin #7: para YOK) ----------


def test_format_visibility_renders_double_block():
    result = tokens.format_visibility(1200, total_tokens_val=80000)
    assert "1200" in result
    assert "80000" in result
    assert "\n\n" in result


def test_format_visibility_no_currency():
    """CLAUDE.md kuralı: USD/$ tutarı GÖSTERİLMEZ."""
    result = tokens.format_visibility(1500, total_tokens_val=50000)
    assert "$" not in result
    assert "USD" not in result
    assert "$0" not in result


def test_format_visibility_uses_state_when_no_arg(tmp_project):
    state.set_field("total_tokens", 12345)
    result = tokens.format_visibility(100)
    assert "12345" in result


def test_format_visibility_token_word_present():
    result = tokens.format_visibility(100, total_tokens_val=200)
    # bilingual: "token" (TR) + "tokens" (EN)
    assert "token" in result.lower()


# ---------- isolation ----------


def test_isolated_per_project(tmp_path, monkeypatch):
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir()
    b.mkdir()
    tokens.record_turn(1000, project_root=str(a))
    tokens.record_turn(2000, project_root=str(b))
    assert tokens.total_tokens(project_root=str(a)) == 1000
    assert tokens.total_tokens(project_root=str(b)) == 2000
