"""hooks/lib/selfcritique.py birim testleri."""

from __future__ import annotations

from hooks.lib import audit, selfcritique


# ---------- prompt ----------


def test_selfcritique_prompt_renders():
    result = selfcritique.selfcritique_prompt(4)
    # Production messages.json'da self_critique_request var
    assert "\n\n" in result or result.startswith("[")


# ---------- record ----------


def test_record_passed(tmp_project):
    selfcritique.record_passed(4)
    ev = audit.latest("selfcritique-passed")
    assert ev is not None
    assert "phase=4" in ev["detail"]


def test_record_gap(tmp_project):
    selfcritique.record_gap(9, "tests eksik, refactor yok")
    ev = audit.latest("selfcritique-gap-found")
    assert ev is not None
    assert "phase=9" in ev["detail"]
    assert "tests eksik" in ev["detail"]


def test_record_gap_truncates(tmp_project):
    selfcritique.record_gap(4, "x" * 500)
    ev = audit.latest("selfcritique-gap-found")
    assert ev is not None
    assert "..." in ev["detail"]


def test_record_gap_strips_pipe(tmp_project):
    selfcritique.record_gap(4, "a | b | c")
    ev = audit.latest("selfcritique-gap-found")
    assert ev is not None
    assert " | " not in ev["detail"]


def test_record_gap_empty_uses_unspecified(tmp_project):
    selfcritique.record_gap(4, "")
    ev = audit.latest("selfcritique-gap-found")
    assert ev is not None
    assert "unspecified" in ev["detail"]


# ---------- latest_for_phase ----------


def test_latest_for_phase_returns_most_recent(tmp_project):
    selfcritique.record_gap(4, "first")
    selfcritique.record_passed(4)
    ev = selfcritique.latest_for_phase(4)
    assert ev is not None
    assert ev["name"] == "selfcritique-passed"


def test_latest_for_phase_filters_by_phase(tmp_project):
    selfcritique.record_passed(4)
    selfcritique.record_gap(9, "tests")
    ev = selfcritique.latest_for_phase(9)
    assert ev is not None
    assert "phase=9" in ev["detail"]


def test_latest_for_phase_none_when_absent(tmp_project):
    assert selfcritique.latest_for_phase(1) is None


def test_latest_for_phase_ignores_other_audits(tmp_project):
    audit.log_event("phase-advance", "gate", "from=4 to=5")
    audit.log_event("rationale-stated", "pre_tool", "tool=Write")
    assert selfcritique.latest_for_phase(4) is None


# ---------- is_passed_for_phase ----------


def test_is_passed_true_when_last_is_passed(tmp_project):
    selfcritique.record_passed(4)
    assert selfcritique.is_passed_for_phase(4) is True


def test_is_passed_false_when_last_is_gap(tmp_project):
    """Önce passed, sonra gap → False (gap son söz)."""
    selfcritique.record_passed(4)
    selfcritique.record_gap(4, "tekrar bak")
    assert selfcritique.is_passed_for_phase(4) is False


def test_is_passed_true_after_gap_then_passed(tmp_project):
    """Gap bulundu → düzeltildi → passed yazıldı → True."""
    selfcritique.record_gap(4, "eksik")
    selfcritique.record_passed(4)
    assert selfcritique.is_passed_for_phase(4) is True


def test_is_passed_false_when_no_audit(tmp_project):
    assert selfcritique.is_passed_for_phase(4) is False


# ---------- isolation ----------


def test_isolated_per_project(tmp_path, monkeypatch):
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir()
    b.mkdir()
    selfcritique.record_passed(4, project_root=str(a))
    selfcritique.record_gap(4, "test eksik", project_root=str(b))
    assert selfcritique.is_passed_for_phase(4, project_root=str(a)) is True
    assert selfcritique.is_passed_for_phase(4, project_root=str(b)) is False
