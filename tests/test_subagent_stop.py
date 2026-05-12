"""test_subagent_stop — SubagentStop hook (mycl-phase-runner native).

1.0.8: native SubagentStop event'i Stop hook'taki transcript-scan
kanalına paralel. Test'ler `_detect_subagent_phase_output` fonksiyonunu
direkt çağırır (subprocess'siz, hızlı). Idempotent guard ve orchestration
gating doğrulanır.
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, orchestrator, state
from hooks.subagent_stop import _detect_subagent_phase_output


def _task_use(task_id: str) -> dict:
    return {
        "type": "assistant",
        "message": {
            "role": "assistant",
            "content": [{
                "type": "tool_use",
                "name": "Task",
                "id": task_id,
                "input": {"subagent_type": "mycl-phase-runner"},
            }],
        },
    }


def _tool_result(task_id: str, text: str) -> dict:
    return {
        "type": "user",
        "message": {
            "role": "user",
            "content": [{
                "type": "tool_result",
                "tool_use_id": task_id,
                "content": [{"type": "text", "text": text}],
            }],
        },
    }


def _write_jsonl(path: Path, events: list[dict]) -> None:
    with path.open("w", encoding="utf-8") as f:
        for ev in events:
            f.write(json.dumps(ev) + "\n")


def _orchestration_phase() -> int:
    """gate_spec.json'da `subagent_orchestration: true` olan ilk fazı bul."""
    for n in range(1, 23):
        if orchestrator.is_orchestration_enabled(n):
            return n
    raise RuntimeError("hiçbir fazda subagent_orchestration enabled değil")


def test_complete_outcome_writes_audit_and_sets_output(tmp_project):
    """complete: <özet> → asama-N-complete audit + last_phase_output set."""
    phase_n = _orchestration_phase()
    state.set_field("current_phase", phase_n, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _task_use("t1"),
        _tool_result("t1", "complete: niyet derlendi"),
    ])

    result = _detect_subagent_phase_output(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    names = [
        ev.get("name")
        for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert f"asama-{phase_n}-complete" in names
    assert state.get("last_phase_output", project_root=str(tmp_project)) == "niyet derlendi"


def test_skipped_outcome_writes_audit(tmp_project):
    """skipped reason=X: detail → asama-N-skipped audit."""
    phase_n = _orchestration_phase()
    state.set_field("current_phase", phase_n, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _task_use("t1"),
        _tool_result("t1", "skipped reason=trivial: tek-satır değişiklik"),
    ])

    result = _detect_subagent_phase_output(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    names = [
        ev.get("name")
        for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert f"asama-{phase_n}-skipped" in names


def test_pending_outcome_writes_audit_no_advance(tmp_project):
    """pending: <soru> → asama-N-pending audit, last_phase_output set EDİLMEZ."""
    phase_n = _orchestration_phase()
    state.set_field("current_phase", phase_n, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _task_use("t1"),
        _tool_result("t1", "pending: kullanıcıya tek soru gerekli"),
    ])

    result = _detect_subagent_phase_output(
        str(transcript_path), str(tmp_project)
    )

    assert result is False
    names = [
        ev.get("name")
        for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert f"asama-{phase_n}-pending" in names
    # PENDING last_phase_output set etmez
    assert state.get("last_phase_output", project_root=str(tmp_project)) in (None, "none")


def test_error_outcome_writes_audit(tmp_project):
    """error: <detay> → asama-N-subagent-error audit (advance YOK)."""
    phase_n = _orchestration_phase()
    state.set_field("current_phase", phase_n, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _task_use("t1"),
        _tool_result("t1", "error: parse fail unknown outcome"),
    ])

    result = _detect_subagent_phase_output(
        str(transcript_path), str(tmp_project)
    )

    assert result is False
    names = [
        ev.get("name")
        for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert f"asama-{phase_n}-subagent-error" in names


def test_idempotent_no_duplicate_complete_audit(tmp_project):
    """Aynı transcript 2 kez taranınca tek `asama-N-complete` audit kalır."""
    phase_n = _orchestration_phase()
    state.set_field("current_phase", phase_n, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _task_use("t1"),
        _tool_result("t1", "complete: ok"),
    ])

    _detect_subagent_phase_output(
        str(transcript_path), str(tmp_project)
    )
    _detect_subagent_phase_output(
        str(transcript_path), str(tmp_project)
    )

    events = audit.read_all(project_root=str(tmp_project))
    completes = [
        ev for ev in events
        if ev.get("name") == f"asama-{phase_n}-complete"
    ]
    assert len(completes) == 1


def test_no_orchestration_phase_returns_false_no_audit(tmp_project):
    """orchestration enabled olmayan fazda no-op + audit yok."""
    # Aşama 22 için orchestration enabled olmamalı (POC Aşama 1'de)
    state.set_field("current_phase", 22, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _task_use("t1"),
        _tool_result("t1", "complete: x"),
    ])

    if orchestrator.is_orchestration_enabled(22):
        # Eğer 22 enabled olursa test geçerli değil; başka non-enabled faz dene
        for n in range(2, 23):
            if not orchestrator.is_orchestration_enabled(n):
                state.set_field("current_phase", n, project_root=str(tmp_project))
                break

    result = _detect_subagent_phase_output(
        str(transcript_path), str(tmp_project)
    )

    assert result is False
    events = audit.read_all(project_root=str(tmp_project))
    # mycl-phase-runner audit'i yok (orchestration disabled)
    phase_audits = [
        ev for ev in events
        if "subagent-emit" in (ev.get("detail") or "")
    ]
    assert phase_audits == []


def test_no_transcript_path_returns_false(tmp_project):
    """transcript_path boşsa erken no-op."""
    phase_n = _orchestration_phase()
    state.set_field("current_phase", phase_n, project_root=str(tmp_project))

    result = _detect_subagent_phase_output("", str(tmp_project))

    assert result is False
    assert audit.read_all(project_root=str(tmp_project)) == []


def test_no_subagent_output_returns_false(tmp_project):
    """Transcript'te mycl-phase-runner tool_result yoksa no-op."""
    phase_n = _orchestration_phase()
    state.set_field("current_phase", phase_n, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    # Sadece prose, Task yok
    _write_jsonl(transcript_path, [{
        "type": "assistant",
        "message": {
            "role": "assistant",
            "content": [{"type": "text", "text": "prose"}],
        },
    }])

    result = _detect_subagent_phase_output(
        str(transcript_path), str(tmp_project)
    )

    assert result is False
