"""hooks/lib/trace.py birim testleri."""

from __future__ import annotations

import re

import pytest

from hooks.lib import trace


# ---------- append + read_all ----------


def test_append_creates_file(tmp_project):
    trace.append("session_start", "1.0.0")
    assert trace.trace_path().exists()


def test_append_format(tmp_project):
    trace.append("phase_transition", "1->2")
    line = trace.trace_path().read_text().strip()
    assert re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z \| ", line)
    assert line.count(" | ") == 2  # 3 sütun
    assert "phase_transition" in line
    assert "1->2" in line


def test_append_empty_value_ok(tmp_project):
    trace.append("ui_flow_autodetect", "")
    tr = trace.read_all()[0]
    assert tr["value"] == ""


def test_read_all_parses_lines(tmp_project):
    trace.append("session_start", "1.0.0")
    trace.append("phase_transition", "1->2")
    trace.append("phase_transition", "2->3")
    items = trace.read_all()
    assert len(items) == 3
    assert items[0]["event"] == "session_start"
    assert items[2]["value"] == "2->3"


# ---------- parse_line ----------


def test_parse_line_well_formed():
    line = "2026-05-09T20:30:00Z | spec_approval_block | 1"
    tr = trace.parse_line(line)
    assert tr is not None
    assert tr["ts"] == "2026-05-09T20:30:00Z"
    assert tr["event"] == "spec_approval_block"
    assert tr["value"] == "1"


def test_parse_line_malformed_returns_none():
    assert trace.parse_line("") is None
    assert trace.parse_line("just text") is None
    assert trace.parse_line("only | two") is None


# ---------- has / find / latest ----------


def test_has_event(tmp_project):
    trace.append("spec_approval_block", "1")
    assert trace.has("spec_approval_block") is True
    assert trace.has("nope") is False


def test_find_by_prefix(tmp_project):
    trace.append("spec_approval_block", "1")
    trace.append("spec_approval_block", "2")
    trace.append("asama_2_skip_block", "1")
    matches = trace.find(event_prefix="spec_approval")
    assert len(matches) == 2


def test_latest_returns_most_recent(tmp_project):
    trace.append("strike_counter", "1")
    trace.append("strike_counter", "2")
    trace.append("strike_counter", "3")
    tr = trace.latest("strike_counter")
    assert tr is not None
    assert tr["value"] == "3"


def test_latest_returns_none_when_absent(tmp_project):
    assert trace.latest("nope") is None


# ---------- validation ----------


def test_append_rejects_pipe_in_event(tmp_project):
    with pytest.raises(ValueError):
        trace.append("event | with | pipes", "x")


def test_append_rejects_pipe_in_value(tmp_project):
    with pytest.raises(ValueError):
        trace.append("event", "v1 | v2")


def test_append_rejects_empty_event(tmp_project):
    with pytest.raises(ValueError):
        trace.append("", "value")


# ---------- convenience helpers ----------


def test_session_start_helper(tmp_project):
    trace.session_start("1.0.0")
    tr = trace.latest("session_start")
    assert tr is not None
    assert tr["value"] == "1.0.0"


def test_phase_transition_helper(tmp_project):
    trace.phase_transition(4, 5)
    tr = trace.latest("phase_transition")
    assert tr is not None
    assert tr["value"] == "4->5"


# ---------- isolation ----------


def test_independent_project_dirs(tmp_path, monkeypatch):
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir()
    b.mkdir()
    trace.append("e1", "x", project_root=str(a))
    trace.append("e2", "y", project_root=str(b))
    assert trace.has("e1", project_root=str(a)) is True
    assert trace.has("e1", project_root=str(b)) is False
    assert trace.has("e2", project_root=str(b)) is True
