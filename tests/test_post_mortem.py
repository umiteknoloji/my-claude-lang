"""hooks/lib/post_mortem.py birim testleri."""

from __future__ import annotations

from hooks.lib import audit, post_mortem


def test_post_mortem_prompt_renders():
    result = post_mortem.post_mortem_prompt("spec-approval-block")
    assert "\n\n" in result or result.startswith("[")


def test_record_writes_audit(tmp_project):
    post_mortem.record(
        "spec-approval-block",
        "Spec yazmaya çalıştım ama AskUserQuestion sırasını anlamadım.",
    )
    ev = audit.latest("post-mortem-recorded")
    assert ev is not None
    assert "block_kind=spec-approval-block" in ev["detail"]
    assert "AskUserQuestion" in ev["detail"]


def test_record_truncates_long_content(tmp_project):
    post_mortem.record("x", "y" * 500)
    ev = audit.latest("post-mortem-recorded")
    assert ev is not None
    assert "..." in ev["detail"]


def test_record_replaces_pipe(tmp_project):
    post_mortem.record("x", "a | b | c")
    ev = audit.latest("post-mortem-recorded")
    assert ev is not None
    assert " | " not in ev["detail"]


def test_record_strips_newlines(tmp_project):
    post_mortem.record("x", "satır1\nsatır2")
    ev = audit.latest("post-mortem-recorded")
    assert ev is not None
    assert "\n" not in ev["detail"]


def test_record_empty_skipped(tmp_project):
    post_mortem.record("", "content")
    post_mortem.record("kind", "")
    assert audit.latest("post-mortem-recorded") is None


def test_latest_for_block_filtered(tmp_project):
    post_mortem.record("spec-approval-block", "first")
    post_mortem.record("asama-2-skip-block", "second")
    post_mortem.record("spec-approval-block", "third")
    ev = post_mortem.latest_for_block("spec-approval-block")
    assert ev is not None
    assert "third" in ev["detail"]


def test_latest_for_block_none_when_absent(tmp_project):
    assert post_mortem.latest_for_block("anything") is None


def test_latest_for_block_empty_input(tmp_project):
    post_mortem.record("kind", "content")
    assert post_mortem.latest_for_block("") is None


def test_isolated_per_project(tmp_path, monkeypatch):
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir()
    b.mkdir()
    post_mortem.record("k", "a-content", project_root=str(a))
    ev_a = post_mortem.latest_for_block("k", project_root=str(a))
    ev_b = post_mortem.latest_for_block("k", project_root=str(b))
    assert ev_a is not None
    assert ev_b is None
