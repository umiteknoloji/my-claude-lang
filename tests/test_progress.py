"""hooks/lib/progress.py birim testleri."""

from __future__ import annotations

from hooks.lib import audit, progress


# ---------- notifications ----------


def test_phase_done_notification_double_block():
    result = progress.phase_done_notification(
        phase=4, phase_name="Spec", next_phase=5
    )
    assert "Aşama 4" in result
    assert "Phase 4" in result
    assert "\n\n" in result


def test_phase_done_notification_default_next():
    result = progress.phase_done_notification(phase=4, phase_name="Spec")
    assert "5" in result  # default next = phase+1


def test_phase_done_notification_at_22_caps_at_22():
    result = progress.phase_done_notification(phase=22, phase_name="Done")
    # next_phase = min(23, 22) = 22
    # 22 → 22 mantıken garip ama overflow yok
    assert "22" in result


def test_phase_skipped_notification():
    result = progress.phase_skipped_notification(
        phase=5, reason="greenfield", next_phase=6
    )
    assert "5" in result and "6" in result
    assert "greenfield" in result
    assert "\n\n" in result


# ---------- ascii_pipeline ----------


def test_ascii_pipeline_22_phases():
    bar = progress.ascii_pipeline(current_phase=1)
    # 22 cell
    assert bar.count("[") == 22
    assert "[1" in bar
    assert "[22" in bar


def test_ascii_pipeline_active_glyph():
    bar = progress.ascii_pipeline(current_phase=5)
    assert "[5⏳]" in bar


def test_ascii_pipeline_finished_phases():
    bar = progress.ascii_pipeline(
        current_phase=4, finished_phases={1, 2, 3}
    )
    assert "[1✅]" in bar
    assert "[2✅]" in bar
    assert "[3✅]" in bar
    assert "[4⏳]" in bar


def test_ascii_pipeline_skipped_phases():
    bar = progress.ascii_pipeline(
        current_phase=8, finished_phases={1, 2, 3, 4}, skipped_phases={5, 7}
    )
    assert "[5↷]" in bar
    assert "[7↷]" in bar
    assert "[8⏳]" in bar


def test_ascii_pipeline_blocked():
    bar = progress.ascii_pipeline(
        current_phase=4, blocked=True
    )
    assert "[4❌]" in bar


def test_ascii_pipeline_pending_phases():
    """Aktif/finished/skipped olmayan faz pending."""
    bar = progress.ascii_pipeline(current_phase=1)
    # 2-22 pending
    assert "[2 ]" in bar
    assert "[22 ]" in bar


def test_ascii_pipeline_arrow_separator():
    bar = progress.ascii_pipeline(current_phase=1)
    # 21 arrow (22 cell arası)
    assert bar.count("→") == 21


# ---------- derive_phase_states ----------


def test_derive_finished_from_audit(tmp_project):
    audit.log_event("asama-1-complete", "stop")
    audit.log_event("asama-2-complete", "stop")
    audit.log_event("asama-6-end", "stop")
    finished, skipped = progress.derive_phase_states()
    assert finished == {1, 2, 6}
    assert skipped == set()


def test_derive_skipped_from_audit(tmp_project):
    audit.log_event("asama-5-skipped", "stop", "reason=greenfield")
    audit.log_event("asama-8-not-applicable", "stop")
    finished, skipped = progress.derive_phase_states()
    assert finished == set()
    assert skipped == {5, 8}


def test_derive_mixed(tmp_project):
    audit.log_event("asama-1-complete", "stop")
    audit.log_event("asama-5-skipped", "stop")
    audit.log_event("asama-6-end", "stop")
    audit.log_event("asama-8-not-applicable", "stop")
    finished, skipped = progress.derive_phase_states()
    assert finished == {1, 6}
    assert skipped == {5, 8}


def test_derive_ignores_non_phase_audits(tmp_project):
    audit.log_event("phase-advance", "gate", "from=4 to=5")
    audit.log_event("rationale-stated", "pre_tool")
    audit.log_event("asama-9-ac-1-red", "stop")
    finished, skipped = progress.derive_phase_states()
    # asama-9-ac-1-red faz tamamlanma değil → finished'da değil
    assert finished == set()
    assert skipped == set()


# ---------- pipeline_block ----------


def test_pipeline_block_with_audits(tmp_project):
    audit.log_event("asama-1-complete", "stop")
    audit.log_event("asama-2-complete", "stop")
    block = progress.pipeline_block(current_phase=3)
    assert "[1✅]" in block
    assert "[2✅]" in block
    assert "[3⏳]" in block


def test_pipeline_block_blocked_state(tmp_project):
    block = progress.pipeline_block(current_phase=4, blocked=True)
    assert "[4❌]" in block


# ---------- load_phase_meta ----------


def test_real_repo_phase_meta_loads():
    progress.reset_cache()
    meta = progress.load_phase_meta()
    assert meta.get("ascii_glyph_done") == "✅"
    assert meta.get("ascii_glyph_active") == "⏳"


# ---------- isolation ----------


def test_pipeline_isolated_per_project(tmp_path, monkeypatch):
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir()
    b.mkdir()
    audit.log_event("asama-1-complete", "stop", project_root=str(a))
    fin_a, _ = progress.derive_phase_states(project_root=str(a))
    fin_b, _ = progress.derive_phase_states(project_root=str(b))
    assert fin_a == {1}
    assert fin_b == set()
