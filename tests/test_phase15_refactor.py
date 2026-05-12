"""test_phase15_refactor — Aşama 15-18 Test Boru Hattı text-trigger'ları (1.0.28).

Subagent (Sonnet 4.6, 10 lens) Aşama 15-18'in Aşama 11-14 ile aynı
"declared but not implemented" deseninde olduğunu doğruladı:
- Skill ve audit kontratı tam tasarlı (`scan / test-M-added /
  scenario-M-passed / target-missed / end-green / end-target-met /
  not-applicable`).
- Hook tarafında `scan count=K` ve `test-M-added` Aşama 15-18 için
  yakalanmıyordu (quality helper'ın `_PHASE_QUALITY_PHASES` scope'u
  dışındaydı).
- **`asama-18-scenario-N-passed` ve `asama-18-target-missed`** skill
  dosyasında açıkça belgelenmiş ama hiç implement edilmemiş —
  subagent kritiği bu boşluğu yakaladı.

Yeni helper `_detect_phase_testing_triggers`:
- _PHASE_SCAN_TRIGGER_RE paylaşılır (quality ile), scope filter
  `{15, 16, 17, 18}`
- _PHASE_TEST_ADDED_RE: Aşama 15-17 (test-M-added)
- _PHASE_SCENARIO_PASSED_RE: Aşama 18 (yük senaryo)
- _PHASE_TARGET_MISSED_RE: Aşama 18 (NFR karşılanmadı → reentry; reentry
  model sorumluluğunda)

`end-green` / `end-target-met` / `not-applicable` 1.0.21 extended
trigger'da yakalanıyor — yeni helper onlara dokunmaz.
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, state
from hooks.stop import _detect_phase_testing_triggers


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


def test_phase_15_scan_count_writes_audit(tmp_project):
    """asama-15-scan count=K → audit emit (eksik test sayısı)."""
    state.set_field("current_phase", 15, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("Coverage analizi: asama-15-scan count=4"),
    ])

    _detect_phase_testing_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-15-scan" in names


def test_phase_15_test_added_writes_audit(tmp_project):
    """asama-15-test-M-added → her test için ayrı audit."""
    state.set_field("current_phase", 15, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "Yeni testler eklendi:\n"
            "asama-15-test-1-added\n"
            "asama-15-test-2-added\n"
            "asama-15-test-3-added\n"
        ),
    ])

    _detect_phase_testing_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-15-test-1-added" in names
    assert "asama-15-test-2-added" in names
    assert "asama-15-test-3-added" in names


def test_phase_16_generic_regex_works(tmp_project):
    """Aşama 16 (Entegrasyon) için test-added çalışır."""
    state.set_field("current_phase", 16, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "asama-16-scan count=2\n"
            "asama-16-test-1-added\n"
        ),
    ])

    _detect_phase_testing_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-16-scan" in names
    assert "asama-16-test-1-added" in names


def test_phase_17_generic_regex_works(tmp_project):
    """Aşama 17 (E2E) için test-added çalışır."""
    state.set_field("current_phase", 17, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-17-test-5-added"),
    ])

    _detect_phase_testing_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-17-test-5-added" in names


def test_phase_18_scenario_passed_writes_audit(tmp_project):
    """Aşama 18 (Yük) için `scenario-M-passed` audit'i — yük senaryo
    başarılı; metric/target/actual yan veri model narrative'ı."""
    state.set_field("current_phase", 18, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "k6 sonuçları:\n"
            "asama-18-scan count=2\n"
            "asama-18-scenario-1-passed metric=p99 target=50ms actual=42ms\n"
            "asama-18-scenario-2-passed metric=throughput target=1000rps actual=1240rps\n"
        ),
    ])

    _detect_phase_testing_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-18-scan" in names
    assert "asama-18-scenario-1-passed" in names
    assert "asama-18-scenario-2-passed" in names


def test_phase_18_target_missed_writes_audit(tmp_project):
    """Aşama 18 NFR karşılanmadı → `target-missed` audit. Skill kontratı
    Aşama 13 reentry'i model sorumluluğunda bırakır; hook sadece
    audit yazar."""
    state.set_field("current_phase", 18, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "asama-18-target-missed metric=p99 actual=120ms target=50ms\n"
        ),
    ])

    _detect_phase_testing_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-18-target-missed" in names


def test_phase_18_no_test_added_normal(tmp_project):
    """Aşama 18 `test-M-added` kullanmaz (scenario-M-passed kullanır).
    Helper Aşama 18 metninde test-added görse bile yakalanmaz — Phase
    18 sadece scan + scenario + target-missed alır."""
    state.set_field("current_phase", 18, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "asama-18-scan count=1\n"
            "asama-18-test-1-added\n"  # geçersiz — Aşama 18 test-added kullanmaz
            "asama-18-scenario-1-passed metric=p99 target=50ms actual=42ms\n"
        ),
    ])

    _detect_phase_testing_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-18-scan" in names
    assert "asama-18-scenario-1-passed" in names
    # Aşama 18 için test-added audit YAZILMAZ
    assert "asama-18-test-1-added" not in names


def test_phase_14_test_added_outside_scope(tmp_project):
    """Aşama 14 (kalite scope'u) `test-M-added` text-trigger'ına test
    helper'da audit yazmaz — quality helper'ı kapsam dışı; testing
    helper Aşama 14'ü {15-18} filtresiyle dışlar."""
    state.set_field("current_phase", 14, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-14-test-1-added"),  # geçersiz — Aşama 14
    ])

    _detect_phase_testing_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-14-test-1-added" not in names


def test_phase_11_scenario_passed_outside_scope(tmp_project):
    """Aşama 11 (kalite) için scenario-M-passed yakalanmaz; sadece
    Aşama 18 için geçerli."""
    state.set_field("current_phase", 11, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-11-scenario-1-passed"),
    ])

    _detect_phase_testing_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-11-scenario-1-passed" not in names


def test_phase_target_missed_only_phase_18(tmp_project):
    """target-missed sadece Aşama 18 için. Aşama 13 (performans)
    yazsa bile audit yazılmaz (skill kontratı yok)."""
    state.set_field("current_phase", 13, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-13-target-missed"),
    ])

    _detect_phase_testing_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-13-target-missed" not in names


def test_phase_testing_triggers_idempotent(tmp_project):
    """Aynı transcript 2 kez taranınca duplicate audit yok."""
    state.set_field("current_phase", 15, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "asama-15-scan count=2\n"
            "asama-15-test-1-added\n"
            "asama-15-test-2-added\n"
        ),
    ])

    _detect_phase_testing_triggers(str(transcript_path), str(tmp_project))
    _detect_phase_testing_triggers(str(transcript_path), str(tmp_project))

    events = audit.read_all(project_root=str(tmp_project))
    scans = [ev for ev in events if ev.get("name") == "asama-15-scan"]
    test_1 = [
        ev for ev in events if ev.get("name") == "asama-15-test-1-added"
    ]
    assert len(scans) == 1
    assert len(test_1) == 1


def test_phase_testing_triggers_full_zincir(tmp_project):
    """Aşama 17 (E2E) tam zincir tek turda."""
    state.set_field("current_phase", 17, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "E2E tamamlandı:\n"
            "asama-17-scan count=3\n"
            "asama-17-test-1-added\n"
            "asama-17-test-2-added\n"
            "asama-17-test-3-added\n"
        ),
    ])

    result = _detect_phase_testing_triggers(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-17-scan" in names
    assert "asama-17-test-1-added" in names
    assert "asama-17-test-2-added" in names
    assert "asama-17-test-3-added" in names


def test_phase_testing_triggers_no_text_returns_false(tmp_project):
    """transcript_path boşsa no-op."""
    result = _detect_phase_testing_triggers("", str(tmp_project))
    assert result is False
