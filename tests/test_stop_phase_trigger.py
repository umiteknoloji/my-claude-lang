"""test_stop_phase_trigger — `_detect_phase_complete_trigger` gölgelenme regresyonu.

Bug bağlamı: model phase-runner sonrası turn1'de `asama-N-complete`
emit ediyor, kullanıcı "devam et" deyince turn2'de prose üretiyor.
Eski kod `transcript.last_assistant_text` ile yalnızca kronolojik son
turn'e (turn2) bakıyordu → trigger gölgeleniyordu → audit yazılmıyordu
→ universal completeness loop ilerlemiyordu.

Fix: `find_last_assistant_text_matching` predicate-based scan trigger
içeren en son turn'ü bulur; sonraki prose turn'leri gölgelyemez.
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, state
from hooks.stop import _detect_phase_complete_trigger


def _assistant_text(text: str) -> dict:
    return {
        "type": "assistant",
        "message": {
            "role": "assistant",
            "content": [{"type": "text", "text": text}],
        },
    }


def _write_jsonl(path: Path, events: list[dict]) -> None:
    with path.open("w", encoding="utf-8") as f:
        for ev in events:
            f.write(json.dumps(ev) + "\n")


def test_detects_trigger_when_shadowed_by_later_prose(tmp_project):
    """turn1 trigger + turn2 prose → predicate scan turn1'i bulur, audit yazılır."""
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-1-complete ok"),
        _assistant_text("Devam edebiliriz, hazırım."),
    ])
    state.set_field("current_phase", 1, project_root=str(tmp_project))

    result = _detect_phase_complete_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    names = [
        ev.get("name")
        for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-1-complete" in names


def test_no_trigger_returns_false_no_audit(tmp_project):
    """Hiçbir turn trigger içermiyorsa False döner, audit yazılmaz."""
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("Birinci prose mesajı."),
        _assistant_text("İkinci prose mesajı."),
    ])
    state.set_field("current_phase", 1, project_root=str(tmp_project))

    result = _detect_phase_complete_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is False
    assert audit.read_all(project_root=str(tmp_project)) == []


def test_skip_attempt_when_n_gt_cp(tmp_project):
    """N > cp → False döner + `phase-skip-attempt` audit yazılır."""
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-3-complete"),
    ])
    state.set_field("current_phase", 1, project_root=str(tmp_project))

    result = _detect_phase_complete_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is False
    events = audit.read_all(project_root=str(tmp_project))
    skip_attempts = [
        ev for ev in events if ev.get("name") == "phase-skip-attempt"
    ]
    assert len(skip_attempts) == 1
    detail = skip_attempts[0].get("detail", "")
    assert "emit_phase=3" in detail
    assert "current_phase=1" in detail


def test_idempotent_no_duplicate_emit(tmp_project):
    """Aynı transcript 2 kez taranınca tek `asama-N-complete` audit kalır."""
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-1-complete"),
    ])
    state.set_field("current_phase", 1, project_root=str(tmp_project))

    _detect_phase_complete_trigger(
        str(transcript_path), str(tmp_project)
    )
    _detect_phase_complete_trigger(
        str(transcript_path), str(tmp_project)
    )

    events = audit.read_all(project_root=str(tmp_project))
    completes = [
        ev for ev in events if ev.get("name") == "asama-1-complete"
    ]
    assert len(completes) == 1
