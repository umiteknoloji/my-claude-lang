"""test_phase4_refactor — Aşama 4 spec format hook enforcement (1.0.19).

Bug zinciri: model `📋 Spec —` formatı yerine "Teknik Spec — ..." veya
"Proje: ..." gibi özel başlık kullanıyordu; ayrıca spec body'sini
AskUserQuestion prompt'una gömüyordu (assistant text'inde değil).
Sonuç: `spec_detect.contains` regex matchlemiyor → `spec_hash=null` →
`_spec_approve_flow` no-op → `spec_approved=False` → Bash deny zinciri.

Fix: `pre_tool.py` AskUserQuestion + cp==4 + son assistant text'te
`📋 Spec —` yoksa PreToolUse deny + retry mesajı. Model'i doğru
akışa zorlar.

Plus: state şemasına `precision_audit_decisions` field eklendi
(Aşama 2'den ertelenmişti). Spec yazımında `[assumed: X]` etiketleri
için zemin.
"""

from __future__ import annotations

from hooks.lib import gate, state


def test_state_default_precision_audit_decisions_empty_list(tmp_project):
    """1.0.19: precision_audit_decisions default boş liste."""
    decisions = state.get(
        "precision_audit_decisions", None,
        project_root=str(tmp_project),
    )
    assert decisions == []


def test_state_can_set_precision_audit_decisions(tmp_project):
    """1.0.19: precision_audit_decisions yazılıp okunabilir."""
    sample = [
        {"dim": 1, "decision": "SILENT-ASSUME", "note": "HTTPS"},
        {"dim": 6, "decision": "GATE", "note": "p99 latency"},
    ]
    state.set_field(
        "precision_audit_decisions", sample,
        project_root=str(tmp_project),
    )
    decisions = state.get(
        "precision_audit_decisions", None,
        project_root=str(tmp_project),
    )
    assert decisions == sample


def test_gate_spec_phase_4_subagent_rubber_duck_removed():
    """1.0.19: Aşama 4'ten subagent_rubber_duck kaldırıldı (Aşama 1/2/3 tutarlı)."""
    spec = gate.load_gate_spec()
    phase4 = spec["phases"]["4"]
    assert "subagent_rubber_duck" not in phase4
    # spec_block_required korunur
    assert phase4.get("spec_block_required") is True
