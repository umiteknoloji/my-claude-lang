"""hooks/lib/confidence.py birim testleri."""

from __future__ import annotations

from hooks.lib import audit, confidence


# ---------- threshold helpers ----------


def test_is_low_below_60():
    assert confidence.is_low(0) is True
    assert confidence.is_low(59) is True
    assert confidence.is_low(60) is False  # eşit DEĞİL low


def test_is_high_above_80():
    assert confidence.is_high(80) is False  # eşit DEĞİL high
    assert confidence.is_high(81) is True
    assert confidence.is_high(100) is True


def test_neutral_zone_60_to_80():
    """60-80 arası nötr (ne düşük ne yüksek)."""
    for score in [60, 70, 80]:
        assert confidence.is_low(score) is False
        assert confidence.is_high(score) is False


# ---------- low_confidence_warning ----------


def test_low_confidence_warning_renders():
    result = confidence.low_confidence_warning(45)
    assert "\n\n" in result or result.startswith("[")


# ---------- record_confidence ----------


def test_record_confidence_basic(tmp_project):
    confidence.record_confidence(85, "Write", file_path="src/a.py")
    ev = audit.latest("confidence-stated")
    assert ev is not None
    assert "tool=Write" in ev["detail"]
    assert "score=85" in ev["detail"]
    assert "file=src/a.py" in ev["detail"]


def test_record_confidence_clamps_high(tmp_project):
    confidence.record_confidence(150, "Write")
    ev = audit.latest("confidence-stated")
    assert ev is not None
    assert "score=100" in ev["detail"]


def test_record_confidence_clamps_low(tmp_project):
    confidence.record_confidence(-50, "Write")
    ev = audit.latest("confidence-stated")
    assert ev is not None
    assert "score=0" in ev["detail"]


def test_record_confidence_invalid_score_skipped(tmp_project):
    confidence.record_confidence("not a number", "Write")  # type: ignore[arg-type]
    confidence.record_confidence(None, "Write")  # type: ignore[arg-type]
    assert audit.latest("confidence-stated") is None


def test_record_confidence_empty_tool_skipped(tmp_project):
    confidence.record_confidence(50, "")
    assert audit.latest("confidence-stated") is None


# ---------- latest_for_tool ----------


def test_latest_for_tool_returns_recent(tmp_project):
    confidence.record_confidence(50, "Write")
    confidence.record_confidence(90, "Write")
    ev = confidence.latest_for_tool("Write")
    assert ev is not None
    assert "score=90" in ev["detail"]


def test_latest_for_tool_filtered(tmp_project):
    confidence.record_confidence(50, "Write")
    confidence.record_confidence(70, "Bash")
    ev = confidence.latest_for_tool("Bash")
    assert ev is not None
    assert "tool=Bash" in ev["detail"]


def test_latest_for_tool_none_when_absent(tmp_project):
    assert confidence.latest_for_tool("Write") is None


# ---------- score_from_audit ----------


def test_score_from_audit_extracts():
    audit_dict = {"name": "confidence-stated", "detail": "tool=Write score=85 file=x"}
    assert confidence.score_from_audit(audit_dict) == 85


def test_score_from_audit_no_score_field():
    audit_dict = {"name": "x", "detail": "no score here"}
    assert confidence.score_from_audit(audit_dict) is None


def test_score_from_audit_invalid_input():
    assert confidence.score_from_audit(None) is None
    assert confidence.score_from_audit({}) is None
    assert confidence.score_from_audit("not a dict") is None  # type: ignore[arg-type]


# ---------- isolation ----------


def test_isolated_per_project(tmp_path, monkeypatch):
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir()
    b.mkdir()
    confidence.record_confidence(85, "Write", project_root=str(a))
    confidence.record_confidence(40, "Write", project_root=str(b))
    score_a = confidence.score_from_audit(
        confidence.latest_for_tool("Write", project_root=str(a))
    )
    score_b = confidence.score_from_audit(
        confidence.latest_for_tool("Write", project_root=str(b))
    )
    assert score_a == 85
    assert score_b == 40
