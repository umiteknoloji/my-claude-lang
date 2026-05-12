"""test_stop_silent_phase — silent_phase auto-emit (1.0.14).

1.0.14 öncesi: `silent_phase: true` flag gate_spec.json'da tanımlıydı
ama hiçbir hook okumuyordu → Aşama 3 (Mühendislik Özeti) SESSİZ faz
`required_audits_any` listesi (`asama-3-complete`, `engineering-brief`)
hiçbir yerden yazılmıyor → completeness loop break → state cp=3'te
stuck → Aşama 4 spec onayı `_spec_approve_flow`'un `cp == 4`
kontrolüne takılıyor → spec_approved=False → Bash deny zinciri.

Fix: `_run_completeness_loop` `silent_phase` flag'i okur, eksik
required audit'i hook kendisi emit eder, sonra completeness check +
advance normal akışla yürür (sentinel atlama YOK — CLAUDE.md
sequential invariant).
"""

from __future__ import annotations

from hooks.lib import audit, gate, state
from hooks.stop import _run_completeness_loop, _silent_phase_auto_emit


def test_silent_phase_auto_emits_required_audit(tmp_project):
    """cp=3 (silent_phase True) → completeness loop required audit
    otomatik emit + advance to cp=4 (gerçek gate_spec.json kullanır)."""
    state.set_field("current_phase", 3, project_root=str(tmp_project))

    advance_count = _run_completeness_loop(str(tmp_project))

    assert advance_count >= 1
    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    # required_audits_any[0] = "asama-3-complete" (gate_spec.json order)
    assert "asama-3-complete" in names
    final_cp = state.get("current_phase", 1, project_root=str(tmp_project))
    assert final_cp == 4  # 3 → 4 advance, 4'te silent_phase False, durur


def test_silent_phase_idempotent_no_duplicate_emit(tmp_project):
    """Zaten emit edilmiş audit varsa silent_phase_auto_emit no-op."""
    state.set_field("current_phase", 3, project_root=str(tmp_project))
    # Manuel olarak engineering-brief audit yaz (alternatif required)
    audit.log_event(
        "engineering-brief", "test",
        "manual-prefill", project_root=str(tmp_project),
    )

    spec = gate.load_gate_spec()
    phase_def = spec["phases"]["3"]
    _silent_phase_auto_emit(3, phase_def, str(tmp_project))

    events = audit.read_all(project_root=str(tmp_project))
    silent_emits = [
        ev for ev in events
        if ev.get("detail", "").startswith("silent-phase-auto-emit")
    ]
    assert silent_emits == []  # idempotent, hiç eklemedi


def test_non_silent_phase_no_auto_emit(tmp_project):
    """silent_phase olmayan fazda completeness loop required audit
    olmadan break eder — `_silent_phase_auto_emit` çağrılmaz.

    Caller invariant: `_run_completeness_loop` sadece silent_phase=True
    fazlar için helper'ı çağırır; helper kendi içinde silent_phase
    kontrolü yapmaz."""
    state.set_field("current_phase", 1, project_root=str(tmp_project))

    advance_count = _run_completeness_loop(str(tmp_project))

    # Aşama 1 silent_phase False + audit log boş → loop ilk
    # iterasyonda break, helper çağrılmadı
    assert advance_count == 0
    events = audit.read_all(project_root=str(tmp_project))
    silent_emits = [
        ev for ev in events
        if "silent-phase-auto-emit" in (ev.get("detail") or "")
    ]
    assert silent_emits == []


def test_silent_phase_empty_required_audits_noop(tmp_project):
    """required_audits_any boşsa silent_phase_auto_emit no-op."""
    fake_phase_def = {
        "silent_phase": True,
        "required_audits_any": [],
    }

    _silent_phase_auto_emit(99, fake_phase_def, str(tmp_project))

    events = audit.read_all(project_root=str(tmp_project))
    assert events == []


def test_silent_phase_required_all_partial_emits_missing(tmp_project):
    """1.0.18: silent_phase + required_audits_all + partial mevcut →
    eksiklerin **hepsini** tek seferde yaz (loop break engelle).

    Önceki davranış (1.0.14-1.0.17): 'for name in required: if name in
    existing: return' — _all için yanlış (biri varsa dur). Düzeltme:
    `_all` için 'hepsi varsa dur', değilse eksikleri yaz.
    """
    fake_phase_def = {
        "silent_phase": True,
        "required_audits_all": ["audit-a", "audit-b", "audit-c"],
    }
    # 'audit-a' önceden mevcut, 'audit-b' ve 'audit-c' eksik
    audit.log_event("audit-a", "test", "pre-existing", project_root=str(tmp_project))

    _silent_phase_auto_emit(99, fake_phase_def, str(tmp_project))

    events = audit.read_all(project_root=str(tmp_project))
    names = [ev.get("name") for ev in events]
    # Hepsi olmalı: audit-a (pre-existing), audit-b + audit-c (yeni emit)
    assert names.count("audit-a") == 1  # duplicate yok
    assert names.count("audit-b") == 1
    assert names.count("audit-c") == 1


def test_silent_phase_required_all_full_existing_noop(tmp_project):
    """1.0.18: silent_phase + required_audits_all + hepsi mevcut → no-op idempotent."""
    fake_phase_def = {
        "silent_phase": True,
        "required_audits_all": ["audit-a", "audit-b"],
    }
    audit.log_event("audit-a", "test", "", project_root=str(tmp_project))
    audit.log_event("audit-b", "test", "", project_root=str(tmp_project))

    _silent_phase_auto_emit(99, fake_phase_def, str(tmp_project))

    events = audit.read_all(project_root=str(tmp_project))
    # Yeni emit yok; sadece 2 mevcut audit
    silent_emits = [
        ev for ev in events
        if "silent-phase-auto-emit" in (ev.get("detail") or "")
    ]
    assert silent_emits == []
