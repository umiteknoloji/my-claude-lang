"""hooks/lib/spec_must.py birim testleri."""

from __future__ import annotations

from hooks.lib import audit, spec_must, state


_SAMPLE_SPEC = """📋 Spec:
Objective: foo

MUST Requirements:
- Auth via session
- RBAC three roles

SHOULD Requirements:
- Pagination

Acceptance Criteria:
- AC1
"""


# ---------- extract_and_save ----------


def test_extract_and_save_writes_state(tmp_project):
    items = spec_must.extract_and_save_must_list(_SAMPLE_SPEC)
    assert len(items) == 3
    ids = [i["id"] for i in items]
    assert ids == ["MUST_1", "MUST_2", "SHOULD_1"]
    # state'e yazıldı mı?
    saved = state.get("spec_must_list")
    assert saved == items


def test_extract_and_save_writes_audit(tmp_project):
    spec_must.extract_and_save_must_list(_SAMPLE_SPEC)
    ev = audit.latest("spec-must-extracted")
    assert ev is not None
    assert "count=3" in ev["detail"]


def test_extract_and_save_empty_spec(tmp_project):
    items = spec_must.extract_and_save_must_list("")
    assert items == []
    assert state.get("spec_must_list") == []


# ---------- must_list / must_ids ----------


def test_must_list_from_state(tmp_project):
    items = [{"id": "MUST_1", "text": "x"}, {"id": "SHOULD_1", "text": "y"}]
    state.set_field("spec_must_list", items)
    assert spec_must.must_list() == items


def test_must_list_filters_invalid(tmp_project):
    state.set_field(
        "spec_must_list",
        [
            {"id": "MUST_1", "text": "ok"},
            "garbage",
            {"no_id": "x"},
            {"id": "MUST_2", "text": "ok"},
        ],
    )
    items = spec_must.must_list()
    assert len(items) == 2
    assert items[0]["id"] == "MUST_1"
    assert items[1]["id"] == "MUST_2"


def test_must_ids_returns_id_only(tmp_project):
    state.set_field(
        "spec_must_list",
        [{"id": "MUST_1", "text": "x"}, {"id": "MUST_2", "text": "y"}],
    )
    assert spec_must.must_ids() == ["MUST_1", "MUST_2"]


# ---------- record_coverage ----------


def test_record_coverage_writes_covers(tmp_project):
    spec_must.record_coverage(
        "asama-9-ac-1-green",
        "stop.py",
        must_ids_covered=["MUST_2", "MUST_3"],
    )
    ev = audit.latest("asama-9-ac-1-green")
    assert ev is not None
    assert "covers=MUST_2,MUST_3" in ev["detail"]


def test_record_coverage_with_extra_detail(tmp_project):
    spec_must.record_coverage(
        "asama-11-issue-1-fixed",
        "stop.py",
        must_ids_covered=["MUST_4"],
        extra_detail="severity=medium",
    )
    ev = audit.latest("asama-11-issue-1-fixed")
    assert ev is not None
    assert "covers=MUST_4" in ev["detail"]
    assert "severity=medium" in ev["detail"]


def test_record_coverage_no_must_ids(tmp_project):
    """must_ids boş ise covers= eklenmez ama audit yazılır."""
    spec_must.record_coverage(
        "asama-11-scan", "stop.py", extra_detail="count=5"
    )
    ev = audit.latest("asama-11-scan")
    assert ev is not None
    assert "covers=" not in ev["detail"]
    assert "count=5" in ev["detail"]


def test_record_coverage_replaces_pipe_in_extra(tmp_project):
    spec_must.record_coverage(
        "x", "stop.py", extra_detail="a | b"
    )
    ev = audit.latest("x")
    assert ev is not None
    assert " | " not in ev["detail"].split(" ", 1)[-1]


def test_record_coverage_empty_audit_name_skipped(tmp_project):
    spec_must.record_coverage("", "stop.py", must_ids_covered=["MUST_1"])
    assert audit.read_all() == []


# ---------- coverage_for_must ----------


def test_coverage_for_must_returns_matching(tmp_project):
    spec_must.record_coverage("a-1", "stop", must_ids_covered=["MUST_1"])
    spec_must.record_coverage("a-2", "stop", must_ids_covered=["MUST_2"])
    spec_must.record_coverage("a-3", "stop", must_ids_covered=["MUST_1", "MUST_3"])
    matches = spec_must.coverage_for_must("MUST_1")
    names = [ev["name"] for ev in matches]
    assert "a-1" in names
    assert "a-3" in names
    assert "a-2" not in names


def test_coverage_for_must_none_when_absent(tmp_project):
    assert spec_must.coverage_for_must("MUST_99") == []


# ---------- uncovered_musts ----------


def test_uncovered_musts_finds_missing(tmp_project):
    state.set_field(
        "spec_must_list",
        [
            {"id": "MUST_1", "text": "a"},
            {"id": "MUST_2", "text": "b"},
            {"id": "MUST_3", "text": "c"},
            {"id": "SHOULD_1", "text": "d"},
        ],
    )
    spec_must.record_coverage("ev1", "stop", must_ids_covered=["MUST_1"])
    spec_must.record_coverage("ev2", "stop", must_ids_covered=["MUST_3"])
    uncovered = spec_must.uncovered_musts()
    assert "MUST_2" in uncovered
    assert "SHOULD_1" in uncovered
    assert "MUST_1" not in uncovered
    assert "MUST_3" not in uncovered


def test_uncovered_musts_empty_when_no_state(tmp_project):
    assert spec_must.uncovered_musts() == []


def test_uncovered_musts_preserves_order(tmp_project):
    state.set_field(
        "spec_must_list",
        [
            {"id": "MUST_1", "text": "a"},
            {"id": "MUST_2", "text": "b"},
            {"id": "MUST_3", "text": "c"},
        ],
    )
    spec_must.record_coverage("ev1", "stop", must_ids_covered=["MUST_2"])
    uncovered = spec_must.uncovered_musts()
    assert uncovered == ["MUST_1", "MUST_3"]


# ---------- linked_graph ----------


def test_linked_graph_returns_chains(tmp_project):
    state.set_field(
        "spec_must_list",
        [{"id": "MUST_1", "text": "a"}, {"id": "MUST_2", "text": "b"}],
    )
    spec_must.record_coverage("test-write", "stop", must_ids_covered=["MUST_1"])
    spec_must.record_coverage("review", "stop", must_ids_covered=["MUST_1", "MUST_2"])
    spec_must.record_coverage("verify", "stop", must_ids_covered=["MUST_2"])
    graph = spec_must.linked_graph()
    assert "MUST_1" in graph
    assert "MUST_2" in graph
    assert "test-write" in graph["MUST_1"]
    assert "review" in graph["MUST_1"]
    assert "review" in graph["MUST_2"]
    assert "verify" in graph["MUST_2"]


def test_linked_graph_uncovered_empty_lists(tmp_project):
    state.set_field(
        "spec_must_list",
        [{"id": "MUST_1", "text": "a"}, {"id": "MUST_2", "text": "b"}],
    )
    graph = spec_must.linked_graph()
    assert graph["MUST_1"] == []
    assert graph["MUST_2"] == []


# ---------- isolation ----------


def test_isolated_per_project(tmp_path, monkeypatch):
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir()
    b.mkdir()
    state.set_field("spec_must_list", [{"id": "MUST_1", "text": "x"}], project_root=str(a))
    state.set_field("spec_must_list", [{"id": "MUST_99", "text": "y"}], project_root=str(b))
    assert spec_must.must_ids(project_root=str(a)) == ["MUST_1"]
    assert spec_must.must_ids(project_root=str(b)) == ["MUST_99"]
