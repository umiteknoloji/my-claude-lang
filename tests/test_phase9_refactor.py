"""test_phase9_refactor — Aşama 9 TDD Yürütme 6 implementation gap (1.0.24).

Subagent (Sonnet 4.6, 10 lens) Aşama 9 için "declared but not
implemented" pattern'inin en derin örneğini buldu:

1. tdd.py modülü mevcut + testleri var, ama post_tool.py'den hiç
   çağrılmıyordu → tdd_compliance_score hep None.
2. asama-9-ac-{i}-(red|green|refactor) audit trigger mekanizması
   yoktu (mevcut regex sadece complete + extended suffix'ler).
3. gate_spec required_audits_any'de `{i}` literal template — gate.py
   çözmüyordu, sadece asama-9-complete kapıyı geçiriyor.
4. regression_block_active=True hiç set edilmiyordu (sadece clear).
5. tdd_last_green state alanı hiçbir yerde yazılmıyordu.
6. spec_must_list → AC sayısı bağlantısı kırık (Aşama 22 dinamik
   sayım yapacak; bu turda implement edilmedi).

Düzeltmeler (4 bağlantı kurma):
- stop.py::_detect_phase_9_ac_trigger + _PHASE_9_AC_TRIGGER_RE
- post_tool.py::_maybe_record_tdd_write (cp==9 + Write/Edit)
- post_tool.py::_maybe_clear_regression_block (FAIL → True set)
- gate_spec.json Aşama 9: {i} template'leri kaldır, subagent_rubber_duck
  kaldır (Aşama 1-8 tutarlı)
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, gate, state
from hooks.stop import _detect_phase_9_ac_trigger


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


def test_phase9_ac_trigger_red_emits_audit(tmp_project):
    """asama-9-ac-1-red trigger → audit emit."""
    state.set_field("current_phase", 9, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("Test fail görüldü. asama-9-ac-1-red"),
    ])

    result = _detect_phase_9_ac_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-9-ac-1-red" in names


def test_phase9_ac_trigger_green_updates_tdd_last_green(tmp_project):
    """asama-9-ac-2-green trigger → audit emit + state.tdd_last_green set."""
    state.set_field("current_phase", 9, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-9-ac-2-green"),
    ])

    _detect_phase_9_ac_trigger(str(transcript_path), str(tmp_project))

    tlg = state.get(
        "tdd_last_green", None, project_root=str(tmp_project),
    )
    assert tlg == "asama-9-ac-2-green"


def test_phase9_ac_trigger_full_cycle(tmp_project):
    """red → green → refactor 3 audit aynı turda emit."""
    state.set_field("current_phase", 9, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "TDD cycle complete.\n"
            "asama-9-ac-1-red\n"
            "asama-9-ac-1-green\n"
            "asama-9-ac-1-refactor"
        ),
    ])

    result = _detect_phase_9_ac_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-9-ac-1-red" in names
    assert "asama-9-ac-1-green" in names
    assert "asama-9-ac-1-refactor" in names


def test_phase9_ac_trigger_idempotent(tmp_project):
    """Aynı audit zaten varsa duplicate yazılmaz."""
    state.set_field("current_phase", 9, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-9-ac-1-red"),
    ])

    _detect_phase_9_ac_trigger(str(transcript_path), str(tmp_project))
    _detect_phase_9_ac_trigger(str(transcript_path), str(tmp_project))

    events = audit.read_all(project_root=str(tmp_project))
    reds = [ev for ev in events if ev.get("name") == "asama-9-ac-1-red"]
    assert len(reds) == 1


def test_phase9_ac_trigger_no_text_returns_false(tmp_project):
    """transcript_path boşsa no-op."""
    result = _detect_phase_9_ac_trigger("", str(tmp_project))
    assert result is False


def test_post_tool_tdd_record_write_phase_9(tmp_project):
    """cp==9'da Write success → tdd-prod-write veya tdd-test-write audit."""
    from hooks.post_tool import _maybe_record_tdd_write
    state.set_field("current_phase", 9, project_root=str(tmp_project))

    _maybe_record_tdd_write(
        "Write",
        {"file_path": "src/foo.py"},
        success=True,
        project_dir=str(tmp_project),
    )

    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    assert "tdd-prod-write" in names


def test_post_tool_tdd_record_skipped_non_phase_9(tmp_project):
    """cp != 9'da TDD record yapılmaz (sadece Aşama 9 davranışına özel)."""
    from hooks.post_tool import _maybe_record_tdd_write
    state.set_field("current_phase", 5, project_root=str(tmp_project))

    _maybe_record_tdd_write(
        "Write",
        {"file_path": "src/foo.py"},
        success=True,
        project_dir=str(tmp_project),
    )

    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    assert "tdd-prod-write" not in names
    assert "tdd-test-write" not in names


def test_post_tool_tdd_record_test_path(tmp_project):
    """Test path Write → tdd-test-write audit."""
    from hooks.post_tool import _maybe_record_tdd_write
    state.set_field("current_phase", 9, project_root=str(tmp_project))

    _maybe_record_tdd_write(
        "Write",
        {"file_path": "tests/test_foo.py"},
        success=True,
        project_dir=str(tmp_project),
    )

    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    assert "tdd-test-write" in names


def test_post_tool_regression_fail_sets_block(tmp_project):
    """Test runner Bash FAIL → regression_block_active=True + regression-fail audit."""
    from hooks.post_tool import _maybe_clear_regression_block
    state.set_field("regression_block_active", False, project_root=str(tmp_project))

    _maybe_clear_regression_block(
        "Bash",
        {"command": "npm test"},
        success=False,
        project_dir=str(tmp_project),
    )

    assert state.get(
        "regression_block_active", None, project_root=str(tmp_project)
    ) is True
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    assert "regression-fail" in names


def test_post_tool_regression_clear_on_green(tmp_project):
    """Test runner Bash GREEN → regression_block_active=False + regression-clear."""
    from hooks.post_tool import _maybe_clear_regression_block
    state.set_field("regression_block_active", True, project_root=str(tmp_project))

    _maybe_clear_regression_block(
        "Bash",
        {"command": "pytest tests/"},
        success=True,
        project_dir=str(tmp_project),
    )

    assert state.get(
        "regression_block_active", None, project_root=str(tmp_project)
    ) is False
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    assert "regression-clear" in names


def test_gate_spec_phase_9_no_template_literals():
    """1.0.24: gate_spec Aşama 9 required_audits_any'de `{i}` template yok."""
    spec = gate.load_gate_spec()
    phase9 = spec["phases"]["9"]
    required = phase9["required_audits_any"]
    for audit_name in required:
        assert "{i}" not in audit_name
        assert "{n}" not in audit_name
    # Sadece asama-9-complete kalıyor (template'siz)
    assert "asama-9-complete" in required


def test_gate_spec_phase_9_subagent_rubber_duck_removed():
    """1.0.24: Aşama 9 subagent_rubber_duck kaldırıldı (Aşama 1-8 tutarlı)."""
    spec = gate.load_gate_spec()
    phase9 = spec["phases"]["9"]
    assert "subagent_rubber_duck" not in phase9
