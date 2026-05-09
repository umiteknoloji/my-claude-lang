"""hooks/lib/rationale.py birim testleri."""

from __future__ import annotations

from hooks.lib import audit, rationale


# ---------- rationale_prompt ----------


def test_rationale_prompt_double_block():
    """bilingual.py'den çift dil render."""
    rationale  # type: ignore[unused-ignore]
    result = rationale.rationale_prompt()
    # Production messages.json'da rationale_request key var
    assert "\n\n" in result or result.startswith("[")


# ---------- record_rationale ----------


def test_record_rationale_writes_audit(tmp_project):
    rationale.record_rationale(
        "MUST_3 (auth) için login.py'a session kontrolü",
        tool="Write",
        file_path="src/login.py",
        must="MUST_3",
    )
    ev = audit.latest("rationale-stated")
    assert ev is not None
    assert "tool=Write" in ev["detail"]
    assert "file=src/login.py" in ev["detail"]
    assert "must=MUST_3" in ev["detail"]
    assert 'reason="' in ev["detail"]


def test_record_rationale_without_optional_fields(tmp_project):
    rationale.record_rationale(
        "Refactor utility",
        tool="Edit",
    )
    ev = audit.latest("rationale-stated")
    assert ev is not None
    assert "tool=Edit" in ev["detail"]
    assert "file=" not in ev["detail"]
    assert "must=" not in ev["detail"]


def test_record_rationale_truncates_long_text(tmp_project):
    rationale.record_rationale(
        "x" * 500,
        tool="Write",
    )
    ev = audit.latest("rationale-stated")
    assert ev is not None
    assert "..." in ev["detail"]


def test_record_rationale_replaces_pipe(tmp_project):
    rationale.record_rationale(
        "Sebep | a | b",
        tool="Write",
    )
    ev = audit.latest("rationale-stated")
    assert ev is not None
    assert " | " not in ev["detail"]


def test_record_rationale_strips_newlines(tmp_project):
    rationale.record_rationale(
        "Birinci\nİkinci",
        tool="Write",
    )
    ev = audit.latest("rationale-stated")
    assert ev is not None
    assert "\n" not in ev["detail"]


def test_record_rationale_empty_skipped(tmp_project):
    rationale.record_rationale("", tool="Write")
    rationale.record_rationale("a reason", tool="")
    assert audit.latest("rationale-stated") is None


# ---------- latest_for_tool ----------


def test_latest_for_tool_returns_most_recent(tmp_project):
    rationale.record_rationale("eski", tool="Write")
    rationale.record_rationale("yeni", tool="Write")
    ev = rationale.latest_for_tool("Write")
    assert ev is not None
    assert "yeni" in ev["detail"]


def test_latest_for_tool_filtered_by_tool(tmp_project):
    rationale.record_rationale("a", tool="Write")
    rationale.record_rationale("b", tool="Bash")
    ev = rationale.latest_for_tool("Bash")
    assert ev is not None
    assert "tool=Bash" in ev["detail"]
    assert '"b"' in ev["detail"]


def test_latest_for_tool_none_when_absent(tmp_project):
    assert rationale.latest_for_tool("Write") is None


def test_latest_for_tool_empty_input(tmp_project):
    assert rationale.latest_for_tool("") is None


# ---------- has_rationale_for_call ----------


def test_has_rationale_tool_only(tmp_project):
    rationale.record_rationale("rationale text", tool="Write")
    assert rationale.has_rationale_for_call("Write") is True
    assert rationale.has_rationale_for_call("Edit") is False


def test_has_rationale_with_file_path(tmp_project):
    rationale.record_rationale(
        "rationale", tool="Write", file_path="src/a.py"
    )
    assert rationale.has_rationale_for_call("Write", file_path="src/a.py") is True
    assert rationale.has_rationale_for_call("Write", file_path="src/b.py") is False


def test_has_rationale_for_call_empty_tool(tmp_project):
    rationale.record_rationale("r", tool="Write")
    assert rationale.has_rationale_for_call("") is False


# ---------- isolation ----------


def test_isolated_per_project(tmp_path, monkeypatch):
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir()
    b.mkdir()
    rationale.record_rationale("a", tool="Write", project_root=str(a))
    rationale.record_rationale("b", tool="Write", project_root=str(b))
    ev_a = rationale.latest_for_tool("Write", project_root=str(a))
    ev_b = rationale.latest_for_tool("Write", project_root=str(b))
    assert ev_a is not None and '"a"' in ev_a["detail"]
    assert ev_b is not None and '"b"' in ev_b["detail"]
