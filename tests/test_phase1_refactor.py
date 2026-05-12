"""test_phase1_refactor — Aşama 1 over-engineering temizliği (1.0.16).

Subagent dispatch (`mycl-phase-runner`) Aşama 1'den kaldırıldı —
pseudocode §3 "POC" notu yanlış yorumla "zorunlu" sayılmıştı. Ana
bağlamda Skill + AskUserQuestion + (global) Read/Glob/Grep yeterli.
Plus iki yeni guard: multi-askq audit (pre_tool.py) + stuck state
soft warning (activate.py).
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, gate, state


def test_phase1_allowed_tools_excludes_task():
    """gate_spec.json Aşama 1 allowed_tools = ['AskUserQuestion'] (Task yok)."""
    spec = gate.load_gate_spec()
    phase1 = spec["phases"]["1"]
    assert "AskUserQuestion" in phase1["allowed_tools"]
    assert "Task" not in phase1["allowed_tools"]


def test_phase1_subagent_orchestration_removed():
    """Aşama 1 entry'sinde subagent_orchestration field yok (kaldırıldı)."""
    spec = gate.load_gate_spec()
    phase1 = spec["phases"]["1"]
    assert "subagent_orchestration" not in phase1


def test_count_askq_in_last_assistant_turn_single(tmp_project):
    """Son assistant message'da 1 askq → count=1."""
    from hooks.pre_tool import _count_askq_in_last_assistant_turn
    transcript_path = tmp_project / "transcript.jsonl"
    with transcript_path.open("w", encoding="utf-8") as f:
        f.write(json.dumps({
            "type": "assistant",
            "message": {
                "role": "assistant",
                "content": [
                    {"type": "text", "text": "Soruyu açıyorum"},
                    {"type": "tool_use", "name": "AskUserQuestion",
                     "id": "q1", "input": {}},
                ],
            },
        }) + "\n")

    count = _count_askq_in_last_assistant_turn(str(transcript_path))
    assert count == 1


def test_count_askq_in_last_assistant_turn_multi(tmp_project):
    """Son assistant message'da 2 askq → count=2 (paralel açma)."""
    from hooks.pre_tool import _count_askq_in_last_assistant_turn
    transcript_path = tmp_project / "transcript.jsonl"
    with transcript_path.open("w", encoding="utf-8") as f:
        f.write(json.dumps({
            "type": "assistant",
            "message": {
                "role": "assistant",
                "content": [
                    {"type": "tool_use", "name": "AskUserQuestion",
                     "id": "q1", "input": {}},
                    {"type": "tool_use", "name": "AskUserQuestion",
                     "id": "q2", "input": {}},
                ],
            },
        }) + "\n")

    count = _count_askq_in_last_assistant_turn(str(transcript_path))
    assert count == 2


def test_count_askq_in_last_assistant_turn_only_last_message(tmp_project):
    """Önceki turdaki askq'lar sayılmaz, sadece son assistant message."""
    from hooks.pre_tool import _count_askq_in_last_assistant_turn
    transcript_path = tmp_project / "transcript.jsonl"
    with transcript_path.open("w", encoding="utf-8") as f:
        # turn 1: 1 askq
        f.write(json.dumps({
            "type": "assistant",
            "message": {
                "role": "assistant",
                "content": [
                    {"type": "tool_use", "name": "AskUserQuestion",
                     "id": "q1", "input": {}},
                ],
            },
        }) + "\n")
        # turn 2: 1 askq (son assistant message)
        f.write(json.dumps({
            "type": "assistant",
            "message": {
                "role": "assistant",
                "content": [
                    {"type": "tool_use", "name": "AskUserQuestion",
                     "id": "q2", "input": {}},
                ],
            },
        }) + "\n")

    count = _count_askq_in_last_assistant_turn(str(transcript_path))
    assert count == 1  # sadece son turn sayılır


def test_check_stuck_state_phase_above_4_no_spec_approval(tmp_project):
    """cp >= 4 + spec_approved=False → warning üretir."""
    from hooks.activate import _check_stuck_state
    state.set_field("current_phase", 5, project_root=str(tmp_project))
    state.set_field("spec_approved", False, project_root=str(tmp_project))

    msg = _check_stuck_state(str(tmp_project))

    assert msg is not None
    assert "stuck" in msg.lower()
    assert "current_phase=5" in msg


def test_check_stuck_state_phase_1_no_warning(tmp_project):
    """cp < 4 → warning yok (henüz spec aşamasına gelmedi)."""
    from hooks.activate import _check_stuck_state
    state.set_field("current_phase", 1, project_root=str(tmp_project))
    state.set_field("spec_approved", False, project_root=str(tmp_project))

    msg = _check_stuck_state(str(tmp_project))

    assert msg is None


def test_check_stuck_state_spec_approved_no_warning(tmp_project):
    """spec_approved=True → warning yok (sağlıklı state)."""
    from hooks.activate import _check_stuck_state
    state.set_field("current_phase", 5, project_root=str(tmp_project))
    state.set_field("spec_approved", True, project_root=str(tmp_project))

    msg = _check_stuck_state(str(tmp_project))

    assert msg is None
