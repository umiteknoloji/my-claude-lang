"""test_phase21_refactor — Aşama 21 Yerelleştirilmiş Rapor (1.0.31).

Subagent (Sonnet 4.6, 10 lens) tespit etti: Aşama 21 mevcut generic
kanallar (complete trigger + extended trigger 1.0.21) ile zaten
çalışıyor; phase-21-spesifik hook kodu gereksiz. Ancak iki belge
tutarsızlığı vardı:

1. `gate_spec.json` `allowed_tools: ["Write"]`, skill dosyası ise
   `Write, Edit, MultiEdit, Bash, AskUserQuestion` listeliyordu — sıkı
   çevirmen rolü için tek Write yeterli. Düzeltme: skill'i gate_spec'e
   hizala.
2. `MyCL_Pseudocode.md` Aşama 21 çıktısı sadece `asama-21-complete`
   yazıyor, `asama-21-skipped reason=already-english` eksik. Düzeltme:
   pseudocode tamamla.

Aşama 22 skill'ine "Aşama 21 skip doğrulama" lens maddesi eklendi
(detection control — CLAUDE.md captured rule gereği).

Bu doc-truth turu; kod değişikliği yok. Testler gate_spec sanity ve
audit-trigger smoke ile sınırlı.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from hooks.lib import audit, gate, state
from hooks.stop import _detect_phase_complete_trigger
from hooks.stop import _detect_phase_extended_trigger


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


def _reload_gate_spec() -> None:
    os.environ["MYCL_DATA_DIR"] = str(
        os.path.join(os.path.dirname(__file__), "..", "data")
    )
    gate._gate_spec_cache = None


def test_gate_spec_phase_21_required_audits():
    """1.0.31: gate_spec Aşama 21 required_audits_any temiz (template
    literal yok) ve complete + skipped içeriyor."""
    _reload_gate_spec()
    spec = gate.load_gate_spec()
    phase21 = spec["phases"]["21"]
    required = phase21["required_audits_any"]
    for audit_name in required:
        assert "{n}" not in audit_name
    assert "asama-21-complete" in required
    assert "asama-21-skipped" in required


def test_gate_spec_phase_21_allowed_tools_minimal():
    """1.0.31: Sıkı çevirmen rolü — sadece Write yeterli. Edit/Bash/
    AskUserQuestion mock cleanup veya inline düzenleme için değil."""
    _reload_gate_spec()
    spec = gate.load_gate_spec()
    phase21 = spec["phases"]["21"]
    tools = phase21["allowed_tools"]
    assert tools == ["Write"]


def test_gate_spec_phase_21_skippable_true():
    """skippable: true, skip_reason: english-session — İngilizce
    oturumda kimlik fonksiyonu olarak atlanır."""
    _reload_gate_spec()
    spec = gate.load_gate_spec()
    phase21 = spec["phases"]["21"]
    assert phase21.get("skippable") is True
    assert phase21.get("skip_reason") == "english-session"


def test_phase_21_complete_trigger_captured_generically(tmp_project):
    """asama-21-complete generic complete trigger ile yakalanır
    (phase-21 spesifik kod gerekmiyor)."""
    state.set_field("current_phase", 21, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("TR çevirisi tamam. asama-21-complete"),
    ])

    _detect_phase_complete_trigger(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-21-complete" in names


def test_phase_21_skipped_trigger_captured_by_extended_regex(tmp_project):
    """asama-21-skipped reason=already-english 1.0.21 extended trigger
    ile yakalanır (`skipped` suffix generic)."""
    state.set_field("current_phase", 21, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "İngilizce oturum tespit edildi.\n"
            "asama-21-skipped reason=already-english\n"
        ),
    ])

    _detect_phase_extended_trigger(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-21-skipped" in names
