"""test_phase22_refactor — Aşama 22 Tamlık Denetimi hook implementation (1.0.32).

Subagent (Sonnet 4.6, 10 lens) Aşama 22 için 5 kritik sorun tespit etti:
1. `_run_completeness_loop` `cp >= 22: break` ile Aşama 22'ye HİÇ
   girmiyordu — plan implementasyon otomatik çağrılmazdı.
2. Model `asama-22-complete` cevap metnine yazınca generic
   `_detect_phase_complete_trigger` onu audit'e yazar → hook devre
   dışı kalır → skill kontratı ihlali.
3. `regression-clear` semantiği: test failure hiç olmadıysa hiç
   yazılmaz; OR mantığıyla son `asama-9-ac-N-green` audit'i de GREEN
   sinyali sayılır.
4. `spec_must_list` boşsa rapor crash etmemeli; soft uyarı.
5. Aşama 11-18 not_applicable dalı belirsizliği (complete/not-applicable/
   end-green/end-target-met/rescan — bunlardan biri varsa kapalı).

İmplementasyon (1.0.32):
- `_run_completeness_loop` Aşama 22 dalı eklendi; hook rapor üretir.
- `_detect_phase_complete_trigger` Aşama 22 guard'ı eklendi;
  `phase-22-illegal-emit-attempt` audit (görünür sinyal).
- `_emit_phase_22_completeness_report` ana fonksiyon: 5 invariant,
  bilingual rapor, idempotent.
- Rapor `.mycl/completeness_report.md` dosyasına yazılır.
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, state
from hooks.stop import (
    _detect_phase_complete_trigger,
    _emit_phase_22_completeness_report,
    _phase_22_check_audit_chain,
    _phase_22_check_tdd_depth,
    _phase_22_check_quality_testing_depth,
    _phase_22_check_must_coverage,
    _phase_22_check_phase_21_skip,
    _run_completeness_loop,
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


def _seed_full_pipeline_audits(project_root: str) -> None:
    """Aşama 1-21 audit zincirini doldur (her faz için minimum bir
    required audit). Test setup helper."""
    audits = [
        ("asama-1-complete", "intent gathered"),
        ("asama-2-complete", "precision audit passed"),
        ("precision-audit", "side"),
        ("asama-3-complete", "engineering brief"),
        ("asama-4-complete", "spec approved"),
        ("pattern-summary-stored", "phase=5 side_audit"),
        ("pattern-summary-stored", "side"),
        ("asama-6-end", "ui not applicable"),
        ("asama-7-skipped", "no ui"),
        ("asama-8-end", "no db"),
        ("asama-9-complete", "tdd done"),
        ("asama-10-complete", "risks resolved"),
        ("asama-11-complete", "code review"),
        ("asama-12-complete", "simplify"),
        ("asama-13-complete", "performance"),
        ("asama-14-complete", "security"),
        ("asama-15-not-applicable", "no testable code"),
        ("asama-16-not-applicable", "no integration"),
        ("asama-17-not-applicable", "no ui"),
        ("asama-18-not-applicable", "no nfr"),
        ("asama-19-complete", "impact reviewed"),
        ("asama-20-complete", "verification rendered"),
        ("asama-20-spec-coverage-rendered", "must_total=0 must_green=0"),
        ("asama-20-mock-cleanup-resolved", "mock cleanup"),
        ("asama-21-skipped", "reason=already-english"),
    ]
    # 1.0.33: self_critique_required disiplin gerekleri için 7 faz —
    # fixture'a `selfcritique-passed phase=N` audit'leri eklenmedikçe
    # Aşama 22 raporu invariant 6 open issue üretir.
    for n in (2, 4, 8, 9, 10, 14, 19):
        audits.append((f"selfcritique-passed", f"phase={n}"))
    # 1.0.34: public_commitment_required için 6 faz — fixture'a
    # `pre-commitment-stated phase=N text="..."` audit'leri.
    for n in (4, 6, 8, 9, 10, 19):
        audits.append((
            "pre-commitment-stated",
            f'phase={n} text="Aşama {n} sözü"',
        ))
    for name, detail in audits:
        audit.log_event(name, "test", detail, project_root=project_root)


def test_completeness_loop_enters_phase_22_and_emits_report(tmp_project):
    """1.0.32: `_run_completeness_loop` cp == 22 dalına girer ve
    `asama-22-complete` audit + rapor dosyasını üretir."""
    state.set_field("current_phase", 22, project_root=str(tmp_project))
    _seed_full_pipeline_audits(str(tmp_project))

    _run_completeness_loop(str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-22-complete" in names
    report_path = Path(tmp_project) / ".mycl" / "completeness_report.md"
    assert report_path.exists()


def test_phase_22_report_is_bilingual(tmp_project):
    """Rapor TR + EN bloklarını içerir (boş satır ayrılı kontrat)."""
    state.set_field("current_phase", 22, project_root=str(tmp_project))
    _seed_full_pipeline_audits(str(tmp_project))

    _emit_phase_22_completeness_report(str(tmp_project))

    report = (Path(tmp_project) / ".mycl" / "completeness_report.md").read_text(
        encoding="utf-8"
    )
    # bilingual header yarısı (TR), diğer yarısı (EN)
    assert "Aşama 22" in report
    assert "Phase 22" in report
    # bilingual section labels
    assert "Açık Konular" in report
    assert "Open Issues" in report
    assert "Process Trace özeti" in report
    assert "Process Trace summary" in report


def test_phase_22_idempotent(tmp_project):
    """`asama-22-complete` zaten varsa loop no-op."""
    state.set_field("current_phase", 22, project_root=str(tmp_project))
    _seed_full_pipeline_audits(str(tmp_project))

    _run_completeness_loop(str(tmp_project))
    _run_completeness_loop(str(tmp_project))

    completes = [
        ev for ev in audit.read_all(project_root=str(tmp_project))
        if ev.get("name") == "asama-22-complete"
    ]
    assert len(completes) == 1


def test_phase_22_model_emit_attempt_blocked(tmp_project):
    """1.0.32: Model `asama-22-complete` cevap metnine yazsa bile
    `_detect_phase_complete_trigger` onu audit'e YAZMAZ; bunun yerine
    `phase-22-illegal-emit-attempt` audit (görünür sinyal)."""
    state.set_field("current_phase", 22, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("Tamamlandı. asama-22-complete"),
    ])

    _detect_phase_complete_trigger(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-22-complete" not in names
    assert "phase-22-illegal-emit-attempt" in names


def test_phase_22_illegal_emit_idempotent(tmp_project):
    """Aynı model denemesi 2 kez taranınca duplicate illegal audit yok."""
    state.set_field("current_phase", 22, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-22-complete"),
    ])

    _detect_phase_complete_trigger(str(transcript_path), str(tmp_project))
    _detect_phase_complete_trigger(str(transcript_path), str(tmp_project))

    illegals = [
        ev for ev in audit.read_all(project_root=str(tmp_project))
        if ev.get("name") == "phase-22-illegal-emit-attempt"
    ]
    assert len(illegals) == 1


def test_phase_22_open_issue_missing_audit_chain(tmp_project):
    """Eksik faz audit'i Açık Konular'da yüzeye çıkar."""
    state.set_field("current_phase", 22, project_root=str(tmp_project))
    # Sadece Faz 1-5 audit'leri; Faz 6-21 eksik
    for n in range(1, 6):
        audit.log_event(
            f"asama-{n}-complete", "test",
            f"phase {n} done", project_root=str(tmp_project),
        )

    _emit_phase_22_completeness_report(str(tmp_project))

    report = (Path(tmp_project) / ".mycl" / "completeness_report.md").read_text(
        encoding="utf-8"
    )
    assert "Eksik audit zinciri" in report


def test_phase_22_open_issue_empty_must_list(tmp_project):
    """1.0.32: Boş spec_must_list crash etmez; soft uyarı."""
    state.set_field("current_phase", 22, project_root=str(tmp_project))
    # spec_must_list default boş

    _emit_phase_22_completeness_report(str(tmp_project))

    report = (Path(tmp_project) / ".mycl" / "completeness_report.md").read_text(
        encoding="utf-8"
    )
    assert "Spec MUST listesi boş" in report


def test_phase_22_open_issue_uncovered_must(tmp_project):
    """Kapsanmamış MUST Açık Konular'da yüzeye çıkar."""
    state.set_field("current_phase", 22, project_root=str(tmp_project))
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
    # MUST_2 kapsanmamış

    _emit_phase_22_completeness_report(str(tmp_project))

    report = (Path(tmp_project) / ".mycl" / "completeness_report.md").read_text(
        encoding="utf-8"
    )
    assert "Spec MUST kapsanma: 1/2" in report
    assert "MUST_2" in report


def test_phase_22_open_issue_phase_21_silent_skip(tmp_project):
    """Aşama 21 ne complete ne skipped → silent skip Açık Konular."""
    state.set_field("current_phase", 22, project_root=str(tmp_project))
    # Aşama 21 audit'i yok (kasıtlı)

    _emit_phase_22_completeness_report(str(tmp_project))

    report = (Path(tmp_project) / ".mycl" / "completeness_report.md").read_text(
        encoding="utf-8"
    )
    assert "Aşama 21 silent skip" in report


def test_phase_22_tdd_depth_green_via_regression_clear(tmp_project):
    """regression-clear audit'i varsa final GREEN sinyali kabul."""
    state.set_field(
        "spec_must_list", [{"id": "MUST_1", "text": "x"}],
        project_root=str(tmp_project),
    )
    audit.log_event("asama-9-ac-1-red", "test", "",
                    project_root=str(tmp_project))
    audit.log_event("asama-9-ac-1-green", "test", "",
                    project_root=str(tmp_project))
    audit.log_event("asama-9-ac-1-refactor", "test", "",
                    project_root=str(tmp_project))
    audit.log_event("regression-clear", "test", "",
                    project_root=str(tmp_project))

    events = audit.read_all(project_root=str(tmp_project))
    ac_complete, ac_total, has_final_green = _phase_22_check_tdd_depth(
        events, str(tmp_project),
    )

    assert ac_complete == 1
    assert ac_total == 1
    assert has_final_green is True


def test_phase_22_tdd_depth_green_via_ac_green_or(tmp_project):
    """1.0.32: regression-clear olmasa bile son asama-9-ac-N-green OR
    sinyali kabul (test failure hiç olmadıysa regression-clear yazılmaz —
    subagent kritiği gereği yanlış pozitif önleme)."""
    state.set_field(
        "spec_must_list", [{"id": "MUST_1", "text": "x"}],
        project_root=str(tmp_project),
    )
    audit.log_event("asama-9-ac-1-red", "test", "",
                    project_root=str(tmp_project))
    audit.log_event("asama-9-ac-1-green", "test", "",
                    project_root=str(tmp_project))
    audit.log_event("asama-9-ac-1-refactor", "test", "",
                    project_root=str(tmp_project))
    # regression-clear YOK

    events = audit.read_all(project_root=str(tmp_project))
    _, _, has_final_green = _phase_22_check_tdd_depth(
        events, str(tmp_project),
    )

    assert has_final_green is True  # OR mantığı ile yine GREEN


def test_phase_22_quality_testing_open_issue_when_no_close_signal(tmp_project):
    """Aşama 11 için hiçbir kapanış sinyali yoksa Açık Konular'da."""
    audit.log_event("asama-11-scan", "test", "count=3",
                    project_root=str(tmp_project))
    # rescan / complete / not-applicable / end-* hiçbiri yok

    events = audit.read_all(project_root=str(tmp_project))
    open_issues = _phase_22_check_quality_testing_depth(events)

    assert 11 in open_issues


def test_phase_22_quality_testing_passes_with_complete(tmp_project):
    """Aşama 11 complete varsa Açık Konular değil."""
    for n in range(11, 19):
        audit.log_event(
            f"asama-{n}-complete", "test", "", project_root=str(tmp_project),
        )

    events = audit.read_all(project_root=str(tmp_project))
    open_issues = _phase_22_check_quality_testing_depth(events)

    assert open_issues == []


def test_phase_22_phase_21_skip_verification(tmp_project):
    """asama-21-skipped audit'i varsa doğrulanmış sayılır."""
    audit.log_event(
        "asama-21-skipped", "test", "reason=already-english",
        project_root=str(tmp_project),
    )

    events = audit.read_all(project_root=str(tmp_project))
    assert _phase_22_check_phase_21_skip(events) is True


def test_phase_22_phase_21_complete_also_verifies(tmp_project):
    """asama-21-complete da doğrulanmış sayılır (skip değil, normal)."""
    audit.log_event(
        "asama-21-complete", "test", "TR translation",
        project_root=str(tmp_project),
    )

    events = audit.read_all(project_root=str(tmp_project))
    assert _phase_22_check_phase_21_skip(events) is True


def test_phase_22_phase_21_neither_is_silent_skip(tmp_project):
    """Aşama 21 için ne complete ne skipped → silent skip (False)."""
    events: list[dict] = []
    assert _phase_22_check_phase_21_skip(events) is False


def test_phase_22_must_coverage_returns_uncovered_ids(tmp_project):
    """MUST kapsanma sayımı + kapsanmamış ID listesi."""
    state.set_field(
        "spec_must_list",
        [
            {"id": "MUST_1", "text": "x"},
            {"id": "MUST_2", "text": "y"},
            {"id": "MUST_3", "text": "z"},
        ],
        project_root=str(tmp_project),
    )
    audit.log_event(
        "asama-9-ac-1-green", "test", "covers=MUST_1",
        project_root=str(tmp_project),
    )

    total, green, uncovered = _phase_22_check_must_coverage(str(tmp_project))

    assert total == 3
    assert green == 1
    assert "MUST_2" in uncovered
    assert "MUST_3" in uncovered


def test_phase_22_emit_writes_last_phase_output(tmp_project):
    """`state.last_phase_output` raporun özeti ile yazılır."""
    state.set_field("current_phase", 22, project_root=str(tmp_project))
    _seed_full_pipeline_audits(str(tmp_project))

    _emit_phase_22_completeness_report(str(tmp_project))

    output = state.get(
        "last_phase_output", "", project_root=str(tmp_project),
    )
    assert "Aşama 22 tamlık raporu" in output


def test_completeness_loop_stops_at_cp_gt_22(tmp_project):
    """cp > 22 (geçersiz) → no-op, hiçbir audit yazılmaz."""
    # cp validation 1-22 sınırlandığı için doğrudan 23 set edilemez;
    # bu test loop'un cp >= 22 dalında break ettiğini doğrular.
    state.set_field("current_phase", 22, project_root=str(tmp_project))
    audit.log_event(
        "asama-22-complete", "test", "already-done",
        project_root=str(tmp_project),
    )

    advance = _run_completeness_loop(str(tmp_project))

    assert advance == 0  # no-op: 22 ve complete zaten var
