"""hooks/lib/dsi.py birim testleri."""

from __future__ import annotations

from hooks.lib import audit, dsi, gate, state


# ---------- render_active_phase_directive ----------


def test_directive_renders_for_real_phase(tmp_project):
    """phase_meta.json'dan TR + EN directive."""
    state.set_field("current_phase", 4)
    result = dsi.render_active_phase_directive(4)
    assert "<mycl_active_phase_directive>" in result
    assert "</mycl_active_phase_directive>" in result
    # phase_meta.json'da Aşama 4 directive
    assert "Aşama 4" in result or "Phase 4" in result


def test_directive_empty_for_unknown_phase():
    result = dsi.render_active_phase_directive(99)
    # phase_meta.json'da 99 yok → boş string
    assert result == ""


# ---------- render_phase_status ----------


def test_phase_status_includes_pipeline(tmp_project):
    state.set_field("current_phase", 5)
    audit.log_event("asama-1-complete", "stop")
    audit.log_event("asama-2-complete", "stop")
    result = dsi.render_phase_status()
    assert "<mycl_phase_status>" in result
    assert "[1✅]" in result
    assert "[2✅]" in result
    assert "[5⏳]" in result


def test_phase_status_default_phase_1(tmp_project):
    result = dsi.render_phase_status()
    assert "[1⏳]" in result


# ---------- render_phase_allowlist_escalate ----------


def test_escalate_empty_when_no_audit(tmp_project):
    """Escalation audit yoksa tag emit edilmez."""
    assert dsi.render_phase_allowlist_escalate() == ""


def test_escalate_renders_when_audit_present(tmp_project):
    audit.log_event(
        "spec-approval-block-escalation-needed", "pre_tool",
        "strike=5 developer-intervention-required",
    )
    result = dsi.render_phase_allowlist_escalate()
    assert "<mycl_phase_allowlist_escalate>" in result
    assert "Escalation" in result
    assert "intervention" in result.lower()


def test_escalate_uses_latest_audit(tmp_project):
    audit.log_event("spec-approval-block-escalation-needed", "pre_tool", "first")
    audit.log_event("ui-review-escalation-needed", "stop", "second")
    result = dsi.render_phase_allowlist_escalate()
    # Son audit ui-review escalation
    assert "ui-review-escalation-needed" in result


# ---------- render_token_visibility ----------


def test_token_visibility_zero_skipped(tmp_project):
    """0 turn token → tag emit edilmez."""
    assert dsi.render_token_visibility(0) == ""


def test_token_visibility_renders(tmp_project):
    result = dsi.render_token_visibility(turn_tokens=1500)
    assert "<mycl_token_visibility>" in result
    assert "1500" in result


def test_token_visibility_no_currency(tmp_project):
    """Disiplin #7: USD/$ YOK."""
    result = dsi.render_token_visibility(turn_tokens=10000)
    assert "$" not in result
    assert "USD" not in result


# ---------- render_full_dsi ----------


def test_full_dsi_combines_blocks(tmp_project):
    state.set_field("current_phase", 4)
    audit.log_event("asama-1-complete", "stop")
    result = dsi.render_full_dsi(turn_tokens=2000)
    assert "<mycl_active_phase_directive>" in result
    assert "<mycl_phase_status>" in result
    assert "<mycl_token_visibility>" in result
    assert "[1✅]" in result


def test_full_dsi_skips_empty_blocks(tmp_project):
    """Escalation yoksa tag emit edilmez."""
    state.set_field("current_phase", 1)
    result = dsi.render_full_dsi(turn_tokens=0)
    assert "<mycl_phase_allowlist_escalate>" not in result
    assert "<mycl_token_visibility>" not in result  # 0 token → skip


def test_full_dsi_with_escalation(tmp_project):
    state.set_field("current_phase", 4)
    audit.log_event(
        "spec-approval-block-escalation-needed", "pre_tool",
        "strike=5",
    )
    result = dsi.render_full_dsi()
    assert "<mycl_phase_allowlist_escalate>" in result


def test_full_dsi_separator_blank_line(tmp_project):
    """Bloklar arası boş satır ayraç."""
    state.set_field("current_phase", 4)
    result = dsi.render_full_dsi()
    parts = result.split("\n\n")
    # En az 2 blok (directive + status)
    assert len(parts) >= 2


# ---------- isolation ----------


def test_dsi_isolated_per_project(tmp_path, monkeypatch):
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir()
    b.mkdir()
    state.set_field("current_phase", 5, project_root=str(a))
    audit.log_event("asama-1-complete", "stop", project_root=str(a))
    state.set_field("current_phase", 1, project_root=str(b))
    res_a = dsi.render_full_dsi(project_root=str(a))
    res_b = dsi.render_full_dsi(project_root=str(b))
    assert "[1✅]" in res_a
    assert "[5⏳]" in res_a
    assert "[1⏳]" in res_b
    assert "[5✅]" not in res_b


# ---------- gate cache reset (cross-test cleanliness) ----------


def test_real_repo_phase_meta_directive_4():
    """Production phase_meta.json Aşama 4 directive yüklenir."""
    gate.reset_cache()
    result = dsi.render_active_phase_directive(4)
    assert "📋 Spec" in result or "Spec" in result
