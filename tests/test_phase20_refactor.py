"""test_phase20_refactor — Aşama 20 Doğrulama Raporu hook enforcement (1.0.30).

Subagent (Sonnet 4.6, 10 lens) Aşama 20'de 4 boşluk tespit etti:
1. `asama-20-spec-coverage-rendered must_total=N must_green=M` audit'i
   skill kontratında var ama hiçbir yerde üretilmiyor; üstelik
   `spec_must.must_ids()` + `uncovered_musts()` API'leri zaten mevcut.
2. `gate_spec.json` `required_audits_any` (OR) — sadece
   `mock-cleanup-resolved` audit'i kapıyı geçiyordu, spec coverage
   hiç üretilmeden faz ilerleyebilir (gate bypass riski).
3. `asama-20-mock-cleanup-resolved` text-trigger yakalanmıyor — Aşama
   11/14'le aynı declared-but-not-implemented deseni.
4. Skill `subagent_rubber_duck: true (gate_spec.json)` diyor ama
   gate_spec'te bu flag yok (doc yanılgısı; 1.0.30'da düzeltildi).

İmplementasyon:
- Hook `_maybe_emit_phase_20_spec_coverage`: spec_must API'siyle
  deterministik sayım, side_audit emit. Idempotent. cp==20 guard.
- Hook `_detect_phase_20_mock_cleanup`: model text-trigger yakalama,
  audit emit. Idempotent.
- gate_spec `required_audits_all` (AND) + `side_audits` ekle.
"""

from __future__ import annotations

import json
from pathlib import Path

import os

from hooks.lib import audit, gate, spec_must, state


def _reload_gate_spec() -> None:
    """gate cache temizle ve data dir env'i sabitle."""
    os.environ["MYCL_DATA_DIR"] = str(
        os.path.join(os.path.dirname(__file__), "..", "data")
    )
    gate._gate_spec_cache = None
from hooks.stop import (
    _detect_phase_20_mock_cleanup,
    _maybe_emit_phase_20_spec_coverage,
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


def test_spec_coverage_audit_emitted_with_must_total_and_green(tmp_project):
    """3 MUST tanımlı, 2'si AC ile kapsanmış (covers=MUST_X audit detail)
    → must_total=3, must_green=2."""
    state.set_field("current_phase", 20, project_root=str(tmp_project))
    state.set_field(
        "spec_must_list",
        [
            {"id": "MUST_1", "text": "auth"},
            {"id": "MUST_2", "text": "audit"},
            {"id": "MUST_3", "text": "idempotency"},
        ],
        project_root=str(tmp_project),
    )
    # MUST_1 ve MUST_2 audit detail'ında "covers=MUST_X" zinciri var
    audit.log_event(
        "asama-9-ac-1-green", "test",
        "covers=MUST_1 stage=green",
        project_root=str(tmp_project),
    )
    audit.log_event(
        "asama-9-ac-2-green", "test",
        "covers=MUST_2 stage=green",
        project_root=str(tmp_project),
    )

    wrote = _maybe_emit_phase_20_spec_coverage(str(tmp_project))

    assert wrote is True
    events = audit.read_all(project_root=str(tmp_project))
    coverage = next(
        ev for ev in events
        if ev.get("name") == "asama-20-spec-coverage-rendered"
    )
    assert "must_total=3" in coverage["detail"]
    assert "must_green=2" in coverage["detail"]


def test_spec_coverage_audit_idempotent(tmp_project):
    """Aynı state üzerinde 2 kez çağrı → tek audit."""
    state.set_field("current_phase", 20, project_root=str(tmp_project))
    state.set_field(
        "spec_must_list", [{"id": "MUST_1", "text": "x"}],
        project_root=str(tmp_project),
    )

    _maybe_emit_phase_20_spec_coverage(str(tmp_project))
    _maybe_emit_phase_20_spec_coverage(str(tmp_project))

    events = [
        ev for ev in audit.read_all(project_root=str(tmp_project))
        if ev.get("name") == "asama-20-spec-coverage-rendered"
    ]
    assert len(events) == 1


def test_spec_coverage_not_emitted_outside_phase_20(tmp_project):
    """current_phase != 20 → no-op."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))
    state.set_field(
        "spec_must_list", [{"id": "MUST_1", "text": "x"}],
        project_root=str(tmp_project),
    )

    wrote = _maybe_emit_phase_20_spec_coverage(str(tmp_project))

    assert wrote is False
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-20-spec-coverage-rendered" not in names


def test_spec_coverage_empty_must_list(tmp_project):
    """spec_must_list boş → must_total=0, must_green=0; audit hâlâ
    yazılır (görünürlük)."""
    state.set_field("current_phase", 20, project_root=str(tmp_project))
    # spec_must_list default boş

    wrote = _maybe_emit_phase_20_spec_coverage(str(tmp_project))

    assert wrote is True
    events = audit.read_all(project_root=str(tmp_project))
    coverage = next(
        ev for ev in events
        if ev.get("name") == "asama-20-spec-coverage-rendered"
    )
    assert "must_total=0" in coverage["detail"]
    assert "must_green=0" in coverage["detail"]


def test_spec_coverage_all_covered(tmp_project):
    """Tüm MUST'lar kapsanmış → must_total = must_green."""
    state.set_field("current_phase", 20, project_root=str(tmp_project))
    state.set_field(
        "spec_must_list",
        [
            {"id": "MUST_1", "text": "x"},
            {"id": "MUST_2", "text": "y"},
        ],
        project_root=str(tmp_project),
    )
    audit.log_event(
        "asama-9-ac-1-green", "test", "covers=MUST_1",
        project_root=str(tmp_project),
    )
    audit.log_event(
        "asama-9-ac-2-green", "test", "covers=MUST_2",
        project_root=str(tmp_project),
    )

    _maybe_emit_phase_20_spec_coverage(str(tmp_project))

    coverage = next(
        ev for ev in audit.read_all(project_root=str(tmp_project))
        if ev.get("name") == "asama-20-spec-coverage-rendered"
    )
    assert "must_total=2" in coverage["detail"]
    assert "must_green=2" in coverage["detail"]


def test_mock_cleanup_text_trigger_captured(tmp_project):
    """Model `asama-20-mock-cleanup-resolved` yazınca hook yakalar."""
    state.set_field("current_phase", 20, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "Mock temizliği tamamlandı.\n"
            "asama-20-mock-cleanup-resolved\n"
        ),
    ])

    wrote = _detect_phase_20_mock_cleanup(
        str(transcript_path), str(tmp_project)
    )

    assert wrote is True
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-20-mock-cleanup-resolved" in names


def test_mock_cleanup_idempotent(tmp_project):
    """Aynı transcript 2 kez taranınca duplicate yok."""
    state.set_field("current_phase", 20, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-20-mock-cleanup-resolved"),
    ])

    _detect_phase_20_mock_cleanup(str(transcript_path), str(tmp_project))
    _detect_phase_20_mock_cleanup(str(transcript_path), str(tmp_project))

    cleanups = [
        ev for ev in audit.read_all(project_root=str(tmp_project))
        if ev.get("name") == "asama-20-mock-cleanup-resolved"
    ]
    assert len(cleanups) == 1


def test_mock_cleanup_no_text_returns_false(tmp_project):
    """transcript_path boşsa no-op."""
    result = _detect_phase_20_mock_cleanup("", str(tmp_project))
    assert result is False


def test_gate_spec_phase_20_required_audits_all_and_semantics(tmp_project):
    """1.0.30: gate_spec Aşama 20 `required_audits_all` (AND) — eski
    `required_audits_any` (OR) bypass riski kapandı. Üç audit de
    listede olmalı."""
    _reload_gate_spec()
    spec = gate.load_gate_spec()
    phase20 = spec["phases"]["20"]
    # OR semantiği artık olmamalı
    assert "required_audits_any" not in phase20 or not phase20.get(
        "required_audits_any"
    )
    assert "required_audits_all" in phase20
    required = phase20["required_audits_all"]
    assert "asama-20-complete" in required
    assert "asama-20-spec-coverage-rendered" in required
    assert "asama-20-mock-cleanup-resolved" in required


def test_gate_spec_phase_20_side_audits_includes_spec_coverage():
    """side_audits hook auto-emit semantiği — spec-coverage burada
    olmalı (hook yazıyor, model değil)."""
    _reload_gate_spec()
    spec = gate.load_gate_spec()
    phase20 = spec["phases"]["20"]
    side_audits = phase20.get("side_audits", [])
    assert "asama-20-spec-coverage-rendered" in side_audits


def test_gate_spec_phase_20_no_subagent_rubber_duck_flag():
    """1.0.30: doc-truth — skill iddia ediyordu ama gate_spec'te
    böyle bir flag yoktu; kafa karışıklığı önleme için yokluğu
    doğrulanır."""
    _reload_gate_spec()
    spec = gate.load_gate_spec()
    phase20 = spec["phases"]["20"]
    assert "subagent_rubber_duck" not in phase20


def test_gate_spec_phase_20_allowed_tools_includes_edit_and_askq():
    """1.0.30: allowed_tools genişletildi. Mock cleanup için Edit ve
    geliştirici onayı için AskUserQuestion eklendi (skill ile tutarlı)."""
    _reload_gate_spec()
    spec = gate.load_gate_spec()
    phase20 = spec["phases"]["20"]
    tools = phase20["allowed_tools"]
    assert "Edit" in tools
    assert "AskUserQuestion" in tools
    assert "Bash" in tools
    assert "Write" in tools
