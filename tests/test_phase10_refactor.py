"""test_phase10_refactor — Aşama 10 + 19 item trigger handler (1.0.25).

Subagent (Sonnet 4.6, 10 lens) 4 boşluk tespit etti:
1. asama-10-items-declared count=K parse yok → state.open_severity_count
   hiç yazılmıyor.
2. asama-10-item-{m}-resolved decision=apply|skip|rule trigger yok.
3. Rule Capture (decision=rule) implement edilmemiş.
4. gate_spec required_audits_any'de `{n}` template literal → gate
   bypass riski (asama-10-complete tek başına geçiyor, item kontrolü
   yok).

Generic regex (Aşama 19 ile aynı pattern):
- _PHASE_ITEMS_DECLARED_RE: asama-(\\d+)-items-declared count=(\\d+)
- _PHASE_ITEM_RESOLVED_RE: asama-(\\d+)-item-(\\d+)-resolved decision=(apply|skip|rule)
- decision=rule → ek audit asama-N-rule-capture-M (CLAUDE.md captured-rules zemini)
- Aşama 10 için state.open_severity_count = count (Aşama 22 tamlık denetimi okuyacak)
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, gate, state
from hooks.stop import _detect_phase_items_triggers


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


def test_phase_10_items_declared_writes_audit_and_count(tmp_project):
    """asama-10-items-declared count=5 → audit + state.open_severity_count=5."""
    state.set_field("current_phase", 10, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("4 mercek tarama bitti. asama-10-items-declared count=5"),
    ])

    result = _detect_phase_items_triggers(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-10-items-declared" in names
    assert state.get(
        "open_severity_count", None, project_root=str(tmp_project)
    ) == 5


def test_phase_10_item_resolved_decision_apply(tmp_project):
    """asama-10-item-3-resolved decision=apply → audit emit, rule-capture yok."""
    state.set_field("current_phase", 10, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("Risk 3 düzeltildi. asama-10-item-3-resolved decision=apply"),
    ])

    _detect_phase_items_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-10-item-3-resolved" in names
    # decision=apply → rule-capture YOK
    assert not any(n.startswith("asama-10-rule-capture-") for n in names)


def test_phase_10_item_resolved_decision_rule_captures(tmp_project):
    """asama-10-item-2-resolved decision=rule → audit + ek rule-capture audit."""
    state.set_field("current_phase", 10, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-10-item-2-resolved decision=rule"),
    ])

    _detect_phase_items_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-10-item-2-resolved" in names
    assert "asama-10-rule-capture-2" in names


def test_phase_10_item_resolved_decision_skip(tmp_project):
    """decision=skip → audit emit, rule-capture yok."""
    state.set_field("current_phase", 10, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-10-item-7-resolved decision=skip"),
    ])

    _detect_phase_items_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-10-item-7-resolved" in names
    assert "asama-10-rule-capture-7" not in names


def test_phase_19_item_resolved_generic(tmp_project):
    """Aşama 19 item trigger aynı generic regex ile yakalanır."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-19-item-1-resolved decision=apply"),
    ])

    _detect_phase_items_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-19-item-1-resolved" in names


def test_phase_19_items_declared_no_state_write(tmp_project):
    """Aşama 19 items-declared → audit emit; state.open_severity_count
    DEĞİL (Aşama 10'a özel — Aşama 19 için Aşama 19 turunda ayrı state)."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-19-items-declared count=3"),
    ])

    _detect_phase_items_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-19-items-declared" in names
    # Aşama 19 için state.open_severity_count yazılmaz
    assert state.get(
        "open_severity_count", 0, project_root=str(tmp_project)
    ) == 0


def test_phase_items_triggers_idempotent(tmp_project):
    """Aynı transcript 2 kez taranınca duplicate audit yok."""
    state.set_field("current_phase", 10, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "asama-10-items-declared count=2\n"
            "asama-10-item-1-resolved decision=rule\n"
        ),
    ])

    _detect_phase_items_triggers(str(transcript_path), str(tmp_project))
    _detect_phase_items_triggers(str(transcript_path), str(tmp_project))

    events = audit.read_all(project_root=str(tmp_project))
    items_declared = [
        ev for ev in events if ev.get("name") == "asama-10-items-declared"
    ]
    item_1_resolved = [
        ev for ev in events if ev.get("name") == "asama-10-item-1-resolved"
    ]
    rule_capture_1 = [
        ev for ev in events if ev.get("name") == "asama-10-rule-capture-1"
    ]
    assert len(items_declared) == 1
    assert len(item_1_resolved) == 1
    assert len(rule_capture_1) == 1


def test_phase_items_triggers_full_zincir(tmp_project):
    """items-declared count=3 + 3 item-resolved (apply/skip/rule) tek turda."""
    state.set_field("current_phase", 10, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "Risk taraması tamamlandı:\n"
            "asama-10-items-declared count=3\n"
            "asama-10-item-1-resolved decision=apply\n"
            "asama-10-item-2-resolved decision=skip\n"
            "asama-10-item-3-resolved decision=rule\n"
        ),
    ])

    result = _detect_phase_items_triggers(
        str(transcript_path), str(tmp_project)
    )

    assert result is True
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-10-items-declared" in names
    assert "asama-10-item-1-resolved" in names
    assert "asama-10-item-2-resolved" in names
    assert "asama-10-item-3-resolved" in names
    assert "asama-10-rule-capture-3" in names  # sadece decision=rule
    assert state.get(
        "open_severity_count", None, project_root=str(tmp_project)
    ) == 3


def test_gate_spec_phase_10_no_template_literals():
    """1.0.25: Aşama 10 required_audits_any'de `{n}` template yok."""
    spec = gate.load_gate_spec()
    phase10 = spec["phases"]["10"]
    required = phase10["required_audits_any"]
    for audit_name in required:
        assert "{n}" not in audit_name
        assert "{i}" not in audit_name
    assert "asama-10-complete" in required


def test_gate_spec_phase_19_no_template_literals():
    """1.0.25: Aşama 19 required_audits_any'de `{n}` template yok."""
    spec = gate.load_gate_spec()
    phase19 = spec["phases"]["19"]
    required = phase19["required_audits_any"]
    for audit_name in required:
        assert "{n}" not in audit_name
    assert "asama-19-complete" in required


def test_phase_items_triggers_no_text_returns_false(tmp_project):
    """transcript_path boşsa no-op."""
    result = _detect_phase_items_triggers("", str(tmp_project))
    assert result is False
