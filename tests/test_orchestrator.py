"""hooks/lib/orchestrator.py birim testleri.

Multi-agent senkron sıralı orkestrasyon utility'leri: skill okuma,
subagent prompt build, output parsing, gate_spec flag kontrolü.
"""

from __future__ import annotations

import os

from hooks.lib import orchestrator


# ---------- parse_phase_output ----------


def test_parse_complete():
    po = orchestrator.parse_phase_output("complete: niyet onayı verildi")
    assert po.outcome == orchestrator.PhaseOutcome.COMPLETE
    assert po.summary == "niyet onayı verildi"


def test_parse_skipped_with_reason_and_detail():
    po = orchestrator.parse_phase_output(
        "skipped reason=greenfield: yeni proje, benzer dosya yok"
    )
    assert po.outcome == orchestrator.PhaseOutcome.SKIPPED
    assert po.reason == "greenfield"
    assert po.detail == "yeni proje, benzer dosya yok"


def test_parse_pending_question():
    po = orchestrator.parse_phase_output("pending: hangi auth method?")
    assert po.outcome == orchestrator.PhaseOutcome.PENDING
    assert po.question == "hangi auth method?"


def test_parse_error_description():
    po = orchestrator.parse_phase_output("error: spec block bulunamadı")
    assert po.outcome == orchestrator.PhaseOutcome.ERROR
    assert po.detail == "spec block bulunamadı"


def test_parse_empty_text_is_error():
    po = orchestrator.parse_phase_output("")
    assert po.outcome == orchestrator.PhaseOutcome.ERROR
    assert "empty" in po.detail


def test_parse_whitespace_only_is_error():
    po = orchestrator.parse_phase_output("   \n  \t  ")
    assert po.outcome == orchestrator.PhaseOutcome.ERROR


def test_parse_unparseable_last_line_is_error():
    po = orchestrator.parse_phase_output(
        "Aşama 1 üzerinde çalıştım.\n\nbu format tanınmıyor"
    )
    assert po.outcome == orchestrator.PhaseOutcome.ERROR
    assert "unparseable" in po.detail


def test_parse_only_last_line_matters():
    """Son anlamlı satır parse edilir; öncesi yok sayılır."""
    po = orchestrator.parse_phase_output(
        "Aşama 1 düşünme aşaması...\n"
        "Çeşitli şeyler düşündüm.\n"
        "complete: niyet net"
    )
    assert po.outcome == orchestrator.PhaseOutcome.COMPLETE
    assert po.summary == "niyet net"


def test_parse_case_insensitive():
    po = orchestrator.parse_phase_output("COMPLETE: Caps test")
    assert po.outcome == orchestrator.PhaseOutcome.COMPLETE


# ---------- read_skill ----------


def test_read_skill_phase_1():
    """Aşama 1 skill dosyası okunabilir ve içerik beklenen."""
    os.environ["MYCL_DATA_DIR"] = str(
        os.path.join(os.path.dirname(__file__), "..", "data")
    )
    content = orchestrator.read_skill(1)
    assert len(content) > 100
    assert "Aşama 1" in content or "Phase 1" in content


def test_read_skill_nonexistent_phase_raises():
    try:
        orchestrator.read_skill(99)
        assert False, "should have raised FileNotFoundError"
    except FileNotFoundError as e:
        assert "asama99" in str(e)


# ---------- build_subagent_prompt ----------


def test_build_prompt_includes_phase_n_and_skill():
    prompt = orchestrator.build_subagent_prompt(
        phase_n=1,
        skill_content="[skill body here]",
        state_snapshot={"current_phase": 1},
        prior_output="none",
    )
    assert "Phase 1" in prompt
    assert "[skill body here]" in prompt
    assert "complete: <summary>" in prompt
    assert "skipped reason=" in prompt
    assert "pending: <question>" in prompt


def test_build_prompt_includes_prior_output():
    prompt = orchestrator.build_subagent_prompt(
        phase_n=2,
        skill_content="x",
        state_snapshot={"current_phase": 2},
        prior_output="niyet özet: todo app",
    )
    assert "niyet özet: todo app" in prompt


def test_build_prompt_includes_state_snapshot_fields():
    prompt = orchestrator.build_subagent_prompt(
        phase_n=9,
        skill_content="x",
        state_snapshot={
            "current_phase": 9,
            "spec_must_list": ["MUST_1: add todo", "MUST_2: delete todo"],
            "pattern_summary": "snake_case, Result type",
        },
        prior_output="none",
    )
    assert "MUST_1: add todo" in prompt
    assert "snake_case" in prompt


# ---------- is_orchestration_enabled ----------


def test_orchestration_enabled_phase_10():
    """Aşama 10 (Risk İncelemesi) — paralel 4 mercek için subagent_orchestration: true.

    1.0.16: Aşama 1'den taşındı; pseudocode §3 Aşama 10 paralel mercek
    (Code Review/Simplify/Performance/Security) için subagent dispatch
    doğal yer.
    """
    os.environ["MYCL_DATA_DIR"] = str(
        os.path.join(os.path.dirname(__file__), "..", "data")
    )
    from hooks.lib import gate
    gate._gate_spec_cache = None
    assert orchestrator.is_orchestration_enabled(10) is True


def test_orchestration_disabled_phase_14():
    """1.0.27: Aşama 14 (Güvenlik) subagent_orchestration bayrağı
    KALDIRILDI. Gerekçe: mycl-phase-runner read-only (Bash yok), bu
    yüzden semgrep/npm audit/secret scanner subagent altında
    çalıştırılamıyordu. 1.0.16'da eklenen bayrak declared-but-not-
    implemented örneğiydi; Aşama 11-13 ile aynı text-trigger kanalı
    kullanılır artık (hooks/stop.py _PHASE_QUALITY_PHASES ⊇ {14})."""
    os.environ["MYCL_DATA_DIR"] = str(
        os.path.join(os.path.dirname(__file__), "..", "data")
    )
    from hooks.lib import gate
    gate._gate_spec_cache = None
    assert orchestrator.is_orchestration_enabled(14) is False


def test_orchestration_disabled_phase_1():
    """1.0.16: Aşama 1 subagent_orchestration kaldırıldı (over-engineering temizliği).

    Pseudocode §3 'POC' notu 1.0.1'de 'zorunlu' diye yanlış yorumlanmıştı;
    niyet toplama küçük scope (kısa askq diyaloğu), bağlam şişmez → ana
    bağlamda Skill + AskUserQuestion yeterli.
    """
    os.environ["MYCL_DATA_DIR"] = str(
        os.path.join(os.path.dirname(__file__), "..", "data")
    )
    from hooks.lib import gate
    gate._gate_spec_cache = None
    assert orchestrator.is_orchestration_enabled(1) is False


def test_orchestration_disabled_phase_2():
    """Aşama 2'de flag yok → False."""
    os.environ["MYCL_DATA_DIR"] = str(
        os.path.join(os.path.dirname(__file__), "..", "data")
    )
    from hooks.lib import gate
    gate._gate_spec_cache = None
    assert orchestrator.is_orchestration_enabled(2) is False


def test_orchestration_disabled_unknown_phase():
    """Bilinmeyen aşama (99) → False."""
    from hooks.lib import gate
    gate._gate_spec_cache = None
    assert orchestrator.is_orchestration_enabled(99) is False
