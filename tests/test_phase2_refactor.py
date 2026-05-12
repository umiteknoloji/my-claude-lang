"""test_phase2_refactor — Aşama 2 hassasiyet denetimi mimari fix (1.0.17).

İki değişiklik:
1. `required_audits_all` (AND mantığı) — `_any` yerine. Aşama 2'de
   `asama-2-complete` + `precision-audit` ikisi de zorunlu. Eski OR
   bypass riski (model sadece `asama-2-complete` yazıp Aşama 2'yi
   "tamamlanmış" göstermesi) kapatıldı.
2. `side_audits` generic feature — fazın yan audit'leri text-trigger
   sonrası hook tarafından paralel emit edilir. Aşama 2 için
   `precision-audit` yan audit; model yazmaz, hook yazar.
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, gate, state
from hooks.stop import (
    _detect_phase_complete_trigger,
    _is_phase_complete,
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


def test_phase2_gate_spec_required_audits_all():
    """gate_spec Aşama 2: required_audits_all (AND), required_audits_any YOK."""
    spec = gate.load_gate_spec()
    phase2 = spec["phases"]["2"]
    assert "required_audits_all" in phase2
    assert "asama-2-complete" in phase2["required_audits_all"]
    assert "precision-audit" in phase2["required_audits_all"]
    assert "required_audits_any" not in phase2


def test_phase2_gate_spec_side_audits():
    """gate_spec Aşama 2: side_audits listesinde precision-audit var."""
    spec = gate.load_gate_spec()
    phase2 = spec["phases"]["2"]
    assert "side_audits" in phase2
    assert "precision-audit" in phase2["side_audits"]


def test_is_phase_complete_all_semantics_pass(tmp_project):
    """`required_audits_all` listesindeki hepsi audit'te varsa True."""
    state.set_field("current_phase", 2, project_root=str(tmp_project))
    audit.log_event("asama-2-complete", "test", "", project_root=str(tmp_project))
    audit.log_event("precision-audit", "test", "", project_root=str(tmp_project))

    assert _is_phase_complete(2, str(tmp_project)) is True


def test_is_phase_complete_all_semantics_fail_partial(tmp_project):
    """`required_audits_all` listesindeki birisi eksikse False (AND)."""
    state.set_field("current_phase", 2, project_root=str(tmp_project))
    # Sadece asama-2-complete var, precision-audit yok
    audit.log_event("asama-2-complete", "test", "", project_root=str(tmp_project))

    assert _is_phase_complete(2, str(tmp_project)) is False


def test_is_phase_complete_any_fallback(tmp_project):
    """`required_audits_all` yoksa `_any` fallback. Aşama 1 örnek."""
    state.set_field("current_phase", 1, project_root=str(tmp_project))
    # Aşama 1'de `required_audits_any` mevcut: summary-confirm-approve veya asama-1-complete
    audit.log_event(
        "asama-1-complete", "test", "", project_root=str(tmp_project)
    )

    assert _is_phase_complete(1, str(tmp_project)) is True


def test_side_audit_emit_on_phase_complete_trigger(tmp_project):
    """Aşama 2 text-trigger: hook hem `asama-2-complete` hem yan
    `precision-audit` audit'i emit eder."""
    state.set_field("current_phase", 2, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("Aşama 2 tamamlandı: asama-2-complete"),
    ])

    result = _detect_phase_complete_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    assert "asama-2-complete" in names
    assert "precision-audit" in names  # yan audit hook tarafından emit


def test_side_audit_idempotent_no_duplicate(tmp_project):
    """Yan audit zaten varsa duplicate yazılmaz."""
    state.set_field("current_phase", 2, project_root=str(tmp_project))
    # Önceden precision-audit varsa (manuel)
    audit.log_event(
        "precision-audit", "test-pre", "manual",
        project_root=str(tmp_project),
    )
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-2-complete"),
    ])

    _detect_phase_complete_trigger(
        str(transcript_path), str(tmp_project)
    )

    events = audit.read_all(project_root=str(tmp_project))
    precision_audits = [
        ev for ev in events if ev.get("name") == "precision-audit"
    ]
    assert len(precision_audits) == 1  # idempotent
