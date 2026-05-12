"""test_phase11_refactor — Aşama 11-13 Kalite Boru Hattı text-trigger'ları (1.0.26).

Subagent (Sonnet 4.6, 10 lens) Aşama 11 boşluğunu tespit etti:
- Skill ve audit kontratı tam tasarlı (scan / issue-fixed / rescan /
  escalation-needed) ama hook'larda HİÇ text-trigger yakalanmıyordu.
- Aşama 9 ile aynı "declared but not implemented" deseni.

Generic regex (Aşama 11, 12, 13 ortak — Aşama 14 subagent kanalı için
scope dışı):
- _PHASE_SCAN_TRIGGER_RE: asama-(\\d+)-scan count=(\\d+)
- _PHASE_ISSUE_FIXED_TRIGGER_RE: asama-(\\d+)-issue-(\\d+)-fixed
- _PHASE_RESCAN_TRIGGER_RE: asama-(\\d+)-rescan count=(\\d+)
- _PHASE_ESCALATION_TRIGGER_RE: asama-(\\d+)-escalation-needed

Cerrahi sınır: hook auto-emit YAPMAZ — `asama-N-complete` ve
`escalation-needed`'ı model yazar; STRICT mode bypass ödülünü önlemek
için savunmacı auto-emit eklenmedi.
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, gate, state
from hooks.stop import _detect_phase_quality_triggers


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


def test_phase_11_scan_count_writes_audit(tmp_project):
    """asama-11-scan count=5 → audit emit."""
    state.set_field("current_phase", 11, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("Tarama bitti. asama-11-scan count=5"),
    ])

    result = _detect_phase_quality_triggers(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-11-scan" in names


def test_phase_11_issue_fixed_writes_audit(tmp_project):
    """asama-11-issue-3-fixed → audit emit (her issue ayrı audit)."""
    state.set_field("current_phase", 11, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "Düzeltmeler:\n"
            "asama-11-issue-1-fixed\n"
            "asama-11-issue-2-fixed\n"
            "asama-11-issue-3-fixed\n"
        ),
    ])

    _detect_phase_quality_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-11-issue-1-fixed" in names
    assert "asama-11-issue-2-fixed" in names
    assert "asama-11-issue-3-fixed" in names


def test_phase_11_rescan_count_writes_audit(tmp_project):
    """asama-11-rescan count=0 → audit emit; hook complete AUTO-EMIT ETMEZ."""
    state.set_field("current_phase", 11, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-11-rescan count=0"),
    ])

    _detect_phase_quality_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-11-rescan" in names
    # Sorumluluk sınırı: hook complete auto-emit etmez (model yazar)
    assert "asama-11-complete" not in names


def test_phase_11_escalation_writes_audit_no_auto_emit(tmp_project):
    """Model asama-11-escalation-needed yazarsa hook yakalar; hook
    kendiliğinden auto-emit etmez (STRICT mode bypass ödülünü önler)."""
    state.set_field("current_phase", 11, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("5 rescan aşıldı. asama-11-escalation-needed"),
    ])

    _detect_phase_quality_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-11-escalation-needed" in names


def test_phase_12_generic_regex_works(tmp_project):
    """Generic regex Aşama 12 (Sadeleştirme) için de çalışır."""
    state.set_field("current_phase", 12, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "asama-12-scan count=2\n"
            "asama-12-issue-1-fixed\n"
            "asama-12-rescan count=0\n"
        ),
    ])

    _detect_phase_quality_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-12-scan" in names
    assert "asama-12-issue-1-fixed" in names
    assert "asama-12-rescan" in names


def test_phase_13_generic_regex_works(tmp_project):
    """Generic regex Aşama 13 (Performans) için de çalışır."""
    state.set_field("current_phase", 13, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-13-scan count=1"),
    ])

    _detect_phase_quality_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-13-scan" in names


def test_phase_14_inside_quality_scope(tmp_project):
    """1.0.27: Aşama 14 (Güvenlik) generic helper scope'una alındı.
    Eski subagent_orchestration bayrağı mycl-phase-runner'ın no-Bash
    kısıtı yüzünden fiilen çalışmıyordu (declared but not implemented);
    şimdi Aşama 11-13 ile aynı text-trigger kanalı kullanılır."""
    state.set_field("current_phase", 14, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "Güvenlik taraması bitti:\n"
            "asama-14-scan count=2\n"
            "asama-14-issue-1-fixed\n"
            "asama-14-issue-2-fixed\n"
            "asama-14-rescan count=0\n"
        ),
    ])

    _detect_phase_quality_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-14-scan" in names
    assert "asama-14-issue-1-fixed" in names
    assert "asama-14-issue-2-fixed" in names
    assert "asama-14-rescan" in names


def test_phase_quality_triggers_idempotent(tmp_project):
    """Aynı transcript 2 kez taranınca duplicate audit yok."""
    state.set_field("current_phase", 11, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "asama-11-scan count=3\n"
            "asama-11-issue-1-fixed\n"
            "asama-11-issue-2-fixed\n"
            "asama-11-rescan count=0\n"
        ),
    ])

    _detect_phase_quality_triggers(str(transcript_path), str(tmp_project))
    _detect_phase_quality_triggers(str(transcript_path), str(tmp_project))

    events = audit.read_all(project_root=str(tmp_project))
    scans = [ev for ev in events if ev.get("name") == "asama-11-scan"]
    issue_1 = [
        ev for ev in events if ev.get("name") == "asama-11-issue-1-fixed"
    ]
    rescans = [ev for ev in events if ev.get("name") == "asama-11-rescan"]
    assert len(scans) == 1
    assert len(issue_1) == 1
    assert len(rescans) == 1


def test_phase_quality_triggers_full_zincir(tmp_project):
    """scan count=3 + 3 issue-fixed + rescan count=0 tek turda."""
    state.set_field("current_phase", 11, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "Kod incelemesi tamamlandı:\n"
            "asama-11-scan count=3\n"
            "asama-11-issue-1-fixed\n"
            "asama-11-issue-2-fixed\n"
            "asama-11-issue-3-fixed\n"
            "asama-11-rescan count=0\n"
        ),
    ])

    result = _detect_phase_quality_triggers(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-11-scan" in names
    assert "asama-11-issue-1-fixed" in names
    assert "asama-11-issue-2-fixed" in names
    assert "asama-11-issue-3-fixed" in names
    assert "asama-11-rescan" in names


def test_phase_quality_triggers_no_state_mutation(tmp_project):
    """1.0.26: Bu helper state alanı yazmaz (duplikasyon kaçınma —
    pseudocode quality_review_state alanı zaten tanımlı, dead alan;
    yeni alan tanıtmıyoruz)."""
    state.set_field("current_phase", 11, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "asama-11-scan count=2\n"
            "asama-11-rescan count=0\n"
        ),
    ])

    _detect_phase_quality_triggers(str(transcript_path), str(tmp_project))

    snap = state.read(project_root=str(tmp_project))
    # 1.0.26 prensibi: helper yeni state alanı eklemiyor
    assert "quality_phase_11_green" not in snap
    assert "quality_rescan_count_phase_11" not in snap


def test_phase_quality_triggers_no_text_returns_false(tmp_project):
    """transcript_path boşsa no-op."""
    result = _detect_phase_quality_triggers("", str(tmp_project))
    assert result is False


def test_gate_spec_phase_11_no_template_literals():
    """1.0.26: Aşama 11 required_audits_any temiz — `{n}` placeholder yok."""
    spec = gate.load_gate_spec()
    phase11 = spec["phases"]["11"]
    for audit_name in phase11["required_audits_any"]:
        assert "{n}" not in audit_name
        assert "{i}" not in audit_name


def test_gate_spec_phase_12_13_no_template_literals():
    """Aşama 12 + 13 için de aynı temizlik."""
    spec = gate.load_gate_spec()
    for n in ("12", "13"):
        phase = spec["phases"][n]
        for audit_name in phase["required_audits_any"]:
            assert "{n}" not in audit_name
            assert "{i}" not in audit_name
