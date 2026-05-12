"""test_phase5_refactor — Aşama 5 desen eşleştirme mimari fix (1.0.20).

İki boşluk kapatıldı:

1. state.pattern_summary yazımı eksikti — skill "hook yazar" diyordu
   ama mekanizma yoktu. stop.py'a `_extract_pattern_summary` helper
   eklendi: Aşama 5 text-trigger sonrası cevap metninde
   `pattern-summary: <özet>` satırı varsa state'e yazar.

2. Aşama 9 DSI pattern_rules hatırlatması eksikti — skill "her turda
   gösterilir" diyordu ama dsi.py emit etmiyordu. `render_pattern_rules_notice`
   eklendi: phase==9 + state.pattern_summary set ise
   `<mycl_pattern_rules>` block emit.

Plus: gate_spec.json Aşama 5'e `side_audits: ["pattern-summary-stored"]`
eklendi — Aşama 2 pattern'i ile yan audit hook'tan otomatik emit.
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, dsi, gate, state
from hooks.stop import (
    _detect_phase_complete_trigger,
    _extract_pattern_summary,
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


def test_extract_pattern_summary_writes_state(tmp_project):
    """`pattern-summary: <özet>` satırı varsa state.pattern_summary'e yaz."""
    text = (
        "Aşama 5 desen taraması tamam.\n"
        "pattern-summary: snake_case dosya, try/except Result, pytest fixtures\n"
        "asama-5-complete"
    )

    result = _extract_pattern_summary(text, str(tmp_project))

    assert result is True
    summary = state.get("pattern_summary", None, project_root=str(tmp_project))
    assert "snake_case" in summary
    assert "Result" in summary


def test_extract_pattern_summary_no_line_no_write(tmp_project):
    """`pattern-summary:` satırı yoksa state'e yazma."""
    text = "Aşama 5 greenfield, atlandı.\nasama-5-skipped reason=greenfield"

    result = _extract_pattern_summary(text, str(tmp_project))

    assert result is False
    summary = state.get("pattern_summary", None, project_root=str(tmp_project))
    assert summary is None


def test_extract_pattern_summary_empty_value_no_write(tmp_project):
    """`pattern-summary: ` boş değer → state'e yazma."""
    text = "pattern-summary:    \nasama-5-complete"

    result = _extract_pattern_summary(text, str(tmp_project))

    assert result is False


def test_phase_5_trigger_emits_side_audit_and_writes_summary(tmp_project):
    """Aşama 5 text-trigger: side_audits emit + pattern_summary state yazımı."""
    state.set_field("current_phase", 5, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "pattern-summary: camelCase, custom Error class, jest\n"
            "asama-5-complete"
        ),
    ])

    result = _detect_phase_complete_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    # asama-5-complete + pattern-summary-stored (side_audits)
    assert "asama-5-complete" in names
    assert "pattern-summary-stored" in names
    # state.pattern_summary yazılmış
    summary = state.get("pattern_summary", None, project_root=str(tmp_project))
    assert summary is not None
    assert "camelCase" in summary


def test_gate_spec_phase_5_side_audits():
    """gate_spec Aşama 5: side_audits listesinde pattern-summary-stored var."""
    spec = gate.load_gate_spec()
    phase5 = spec["phases"]["5"]
    assert "side_audits" in phase5
    assert "pattern-summary-stored" in phase5["side_audits"]


def test_dsi_pattern_rules_phase_9_with_summary(tmp_project):
    """phase==9 + state.pattern_summary set → <mycl_pattern_rules> emit."""
    state.set_field(
        "pattern_summary",
        "snake_case, try/except Result, pytest",
        project_root=str(tmp_project),
    )

    block = dsi.render_pattern_rules_notice(9, project_root=str(tmp_project))

    assert "<mycl_pattern_rules>" in block
    assert "snake_case" in block
    assert "Aşama 5" in block or "Phase 5" in block


def test_dsi_pattern_rules_phase_9_no_summary_empty(tmp_project):
    """phase==9 + pattern_summary yok → empty block (gürültü emit etme)."""
    # state.pattern_summary default None
    block = dsi.render_pattern_rules_notice(9, project_root=str(tmp_project))

    assert block == ""


def test_dsi_pattern_rules_phase_5_no_emit(tmp_project):
    """phase != 9 → emit YOK (Aşama 9 dışında gösterilmez)."""
    state.set_field(
        "pattern_summary", "test", project_root=str(tmp_project),
    )

    block = dsi.render_pattern_rules_notice(5, project_root=str(tmp_project))

    assert block == ""
