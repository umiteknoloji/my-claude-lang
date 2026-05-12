"""test_phase7_refactor — Aşama 7 UI İncelemesi DEFERRED mode (1.0.22).

4 boşluk kapatıldı:

1. Intent classification stop hook'ta cp==7 için çalışmıyordu.
   `_phase7_ui_review_flow` eklendi: approve→complete+ui_reviewed,
   cancel→cancelled, revise→no-op (1.0.23 ertelendi).

2. `ui_reviewed` state yazılmıyordu. Şimdi approve intent ile True.

3. Aşama 6 skipped → Aşama 7 auto-skip yoktu. `_check_phase7_auto_skip`
   eklendi: cp==7 + asama-6-skipped audit + asama-7-* yok → otomatik
   asama-7-skipped emit.

4. `progress.py` deferred narration yok. `_glyph_for_phase` +
   `_derive_deferred_phases` eklendi. gate_spec phase 7'ye
   `deferred: true` flag. ASCII pipeline'da Aşama 7 ⏸ glyph görünür.
"""

from __future__ import annotations

from hooks.lib import askq, audit, gate, progress, state
from hooks.stop import (
    _check_phase7_auto_skip,
    _phase7_ui_review_flow,
)


def test_phase7_approve_writes_complete_and_ui_reviewed(tmp_project):
    """cp==7 + intent approve → asama-7-complete + ui_reviewed=True."""
    state.set_field("current_phase", 7, project_root=str(tmp_project))

    result = _phase7_ui_review_flow(askq.INTENT_APPROVE, str(tmp_project))

    assert result is True
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-7-complete" in names
    assert state.get("ui_reviewed", False, project_root=str(tmp_project)) is True


def test_phase7_cancel_writes_cancelled(tmp_project):
    """cp==7 + intent cancel → asama-7-cancelled audit."""
    state.set_field("current_phase", 7, project_root=str(tmp_project))

    result = _phase7_ui_review_flow(askq.INTENT_CANCEL, str(tmp_project))

    assert result is True
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-7-cancelled" in names
    # ui_reviewed False kalır
    assert state.get("ui_reviewed", False, project_root=str(tmp_project)) is False


def test_phase7_revise_no_op_deferred_to_next_release(tmp_project):
    """revise akışı 1.0.23'e ertelendi — şimdilik no-op."""
    state.set_field("current_phase", 7, project_root=str(tmp_project))

    result = _phase7_ui_review_flow(askq.INTENT_REVISE, str(tmp_project))

    assert result is False
    events = audit.read_all(project_root=str(tmp_project))
    assert events == []


def test_phase7_ambiguous_no_op(tmp_project):
    """ambiguous intent → no-op (model fallback askq açabilir)."""
    state.set_field("current_phase", 7, project_root=str(tmp_project))

    result = _phase7_ui_review_flow(askq.INTENT_AMBIGUOUS, str(tmp_project))

    assert result is False


def test_phase7_flow_not_cp_7_no_op(tmp_project):
    """cp != 7'de approve gelse bile Aşama 7 flow tetiklenmez."""
    state.set_field("current_phase", 5, project_root=str(tmp_project))

    result = _phase7_ui_review_flow(askq.INTENT_APPROVE, str(tmp_project))

    assert result is False
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-7-complete" not in names


def test_phase7_approve_idempotent(tmp_project):
    """Aynı approve intent 2 kez çağrılırsa tek audit."""
    state.set_field("current_phase", 7, project_root=str(tmp_project))

    _phase7_ui_review_flow(askq.INTENT_APPROVE, str(tmp_project))
    _phase7_ui_review_flow(askq.INTENT_APPROVE, str(tmp_project))

    events = audit.read_all(project_root=str(tmp_project))
    completes = [
        ev for ev in events if ev.get("name") == "asama-7-complete"
    ]
    assert len(completes) == 1


def test_phase7_auto_skip_when_phase_6_skipped(tmp_project):
    """cp==7 + asama-6-skipped audit + Aşama 7 audit yok →
    otomatik asama-7-skipped emit (Aşama 6 atlandığında zincir)."""
    state.set_field("current_phase", 7, project_root=str(tmp_project))
    audit.log_event(
        "asama-6-skipped", "test", "reason=no-ui-flow",
        project_root=str(tmp_project),
    )

    result = _check_phase7_auto_skip(str(tmp_project))

    assert result is True
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-7-skipped" in names


def test_phase7_no_auto_skip_when_already_resolved(tmp_project):
    """Aşama 7 zaten bir karar audit'i yazmışsa auto-skip tetiklenmez."""
    state.set_field("current_phase", 7, project_root=str(tmp_project))
    audit.log_event(
        "asama-6-skipped", "test", "", project_root=str(tmp_project),
    )
    audit.log_event(
        "asama-7-complete", "test", "previous-approve",
        project_root=str(tmp_project),
    )

    result = _check_phase7_auto_skip(str(tmp_project))

    assert result is False
    # asama-7-skipped yazılmadı
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-7-skipped" not in names


def test_phase7_auto_skip_only_when_cp_7(tmp_project):
    """cp != 7'de auto-skip tetiklenmez."""
    state.set_field("current_phase", 5, project_root=str(tmp_project))
    audit.log_event(
        "asama-6-skipped", "test", "", project_root=str(tmp_project),
    )

    result = _check_phase7_auto_skip(str(tmp_project))

    assert result is False


def test_gate_spec_phase_7_deferred_flag():
    """gate_spec Aşama 7: deferred: true flag eklendi (1.0.22)."""
    spec = gate.load_gate_spec()
    phase7 = spec["phases"]["7"]
    assert phase7.get("deferred") is True


def test_progress_deferred_glyph_phase_7():
    """ascii_pipeline cp=1'de Aşama 7 ⏸ glyph (deferred görünür kalır)."""
    bar = progress.ascii_pipeline(current_phase=1)
    # Aşama 7 deferred (gate_spec'te deferred: true)
    assert "[7⏸]" in bar


def test_progress_active_phase_overrides_deferred():
    """cp=7'de Aşama 7 active glyph (⏳) — deferred glyph değil."""
    bar = progress.ascii_pipeline(current_phase=7)
    assert "[7⏳]" in bar
    assert "[7⏸]" not in bar


def test_progress_skipped_overrides_deferred():
    """Aşama 7 skipped set'te ise ↷ glyph (skipped öncelikli)."""
    bar = progress.ascii_pipeline(
        current_phase=8, finished_phases={1, 2, 3, 4, 5, 6}, skipped_phases={7}
    )
    assert "[7↷]" in bar
    assert "[7⏸]" not in bar
