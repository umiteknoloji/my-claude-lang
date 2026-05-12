"""test_phase6_refactor — Aşama 6 UI Yapımı mimari fix (1.0.21).

İki başlık:

1. Generic extended trigger: `_PHASE_EXTENDED_TRIGGER_RE` ile complete
   dışındaki suffix'ler (skipped/end/end-green/end-target-met/
   not-applicable) yakalanır. Mevcut `_PHASE_COMPLETE_TRIGGER_RE`
   sadece 'complete' suffix yakalıyordu → `asama-6-end`,
   `asama-5-skipped`, `asama-15-end-green` audit'leri hook'a hiç
   ulaşmıyordu (text-trigger kanalı kayıp). Generic fix.

2. Aşama 6 spesifik: `asama-6-end` detail parse — `browser_opened=false`
   varsa `asama-6-no-browser-warn` soft audit emit (KATI mod gözetimi).

Plus state.py'dan dead field'lar (ui_sub_phase, ui_build_hash) kaldırıldı.
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, gate, state
from hooks.stop import (
    _check_phase6_browser,
    _detect_phase_extended_trigger,
)


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


def test_extended_trigger_phase_6_end_with_certificate(tmp_project):
    """`asama-6-end server_started=true browser_opened=true` → audit emit."""
    state.set_field("current_phase", 6, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "UI hazır. asama-6-end server_started=true browser_opened=true"
        ),
    ])

    result = _detect_phase_extended_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    assert "asama-6-end" in names
    # browser_opened=true → no warn
    assert "asama-6-no-browser-warn" not in names


def test_extended_trigger_phase_6_end_browser_false_warn(tmp_project):
    """`asama-6-end server_started=true browser_opened=false` → warn audit."""
    state.set_field("current_phase", 6, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "asama-6-end server_started=true browser_opened=false"
        ),
    ])

    result = _detect_phase_extended_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    assert "asama-6-end" in names
    assert "asama-6-no-browser-warn" in names


def test_extended_trigger_phase_6_skipped(tmp_project):
    """`asama-6-skipped reason=no-ui-flow` → audit emit."""
    state.set_field("current_phase", 6, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-6-skipped reason=no-ui-flow"),
    ])

    result = _detect_phase_extended_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    assert "asama-6-skipped" in names


def test_extended_trigger_phase_5_skipped_now_caught(tmp_project):
    """1.0.21 generic fix: Aşama 5 skipped artık yakalanır
    (önceki regex sadece complete suffix yakalıyordu)."""
    state.set_field("current_phase", 5, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-5-skipped reason=greenfield"),
    ])

    result = _detect_phase_extended_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    assert "asama-5-skipped" in names


def test_extended_trigger_phase_15_end_green_longest_match(tmp_project):
    """`asama-15-end-green` — end-green ÖNCE end (longest match)."""
    state.set_field("current_phase", 15, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("Unit tests passed. asama-15-end-green"),
    ])

    result = _detect_phase_extended_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    # "end-green" suffix ile audit name "asama-15-end-green"
    # "asama-15-end" değil
    assert "asama-15-end-green" in names
    assert "asama-15-end" not in names


def test_extended_trigger_phase_18_end_target_met(tmp_project):
    """`asama-18-end-target-met` — Aşama 18 (Yük Testleri) target sertifikası."""
    state.set_field("current_phase", 18, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("Load test p99 < 100ms. asama-18-end-target-met"),
    ])

    result = _detect_phase_extended_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    assert "asama-18-end-target-met" in names


def test_extended_trigger_phase_8_not_applicable(tmp_project):
    """`asama-8-not-applicable reason=no-db-in-scope` — Aşama 8 atlama."""
    state.set_field("current_phase", 8, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-8-not-applicable reason=no-db-in-scope"),
    ])

    result = _detect_phase_extended_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    assert "asama-8-not-applicable" in names


def test_extended_trigger_idempotent(tmp_project):
    """Aynı extended trigger 2 kez taranınca tek audit."""
    state.set_field("current_phase", 6, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-6-skipped reason=no-ui-flow"),
    ])

    _detect_phase_extended_trigger(str(transcript_path), str(tmp_project))
    _detect_phase_extended_trigger(str(transcript_path), str(tmp_project))

    events = audit.read_all(project_root=str(tmp_project))
    skipped = [
        ev for ev in events if ev.get("name") == "asama-6-skipped"
    ]
    assert len(skipped) == 1


def test_extended_trigger_n_neq_cp_silent_skip(tmp_project):
    """Extended trigger sıralılık zorunlu değil — n != cp sessiz geç (skip-attempt YOK)."""
    state.set_field("current_phase", 4, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-6-skipped reason=no-ui-flow"),
    ])

    result = _detect_phase_extended_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is False
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    # Audit emit yok
    assert "asama-6-skipped" not in names
    # phase-skip-attempt da yazılmaz (complete trigger değil, sıralılık opsiyonel)
    assert "phase-skip-attempt" not in names


def test_check_phase6_browser_helper_true_no_warn(tmp_project):
    """_check_phase6_browser helper: browser_opened=true → warn yok."""
    _check_phase6_browser(
        "server_started=true browser_opened=true", str(tmp_project)
    )
    events = audit.read_all(project_root=str(tmp_project))
    assert events == []


def test_check_phase6_browser_helper_false_emit_warn(tmp_project):
    """_check_phase6_browser helper: browser_opened=false → warn emit."""
    _check_phase6_browser(
        "server_started=true browser_opened=false", str(tmp_project)
    )
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    assert "asama-6-no-browser-warn" in names


def test_state_default_no_ui_sub_phase(tmp_project):
    """1.0.21: ui_sub_phase field _DEFAULT_STATE'ten kaldırıldı."""
    # state.get default None döner (field yoksa)
    val = state.get(
        "ui_sub_phase", "NOT_FOUND",
        project_root=str(tmp_project),
    )
    # Field yok → default "NOT_FOUND" döner
    assert val == "NOT_FOUND"


def test_state_default_no_ui_build_hash(tmp_project):
    """1.0.21: ui_build_hash field _DEFAULT_STATE'ten kaldırıldı."""
    val = state.get(
        "ui_build_hash", "NOT_FOUND",
        project_root=str(tmp_project),
    )
    assert val == "NOT_FOUND"
