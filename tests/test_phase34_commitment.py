"""test_phase34_commitment — public_commitment_required disiplin (1.0.34).

Aspirational kapanış 2/4. Subagent (Sonnet 4.6, 10 lens) kritiği:
- `commitment.py` modülü tam hazır (record_pre_commitment 200 char
  truncation built-in); hook bağlantısı eksikti.
- Subagent yeni `commitment-recorded` audit kanalı icat etme uyarısı
  verdi — mevcut `pre-commitment-stated` audit kanalı kullanılmalı.
- 6 faz `public_commitment_required: true` (4, 6, 8, 9, 10, 19).
- Soft guidance (Option B) — hard gate yok; Aşama 22 invariant 7.

İmplementasyon:
- `stop.py::_maybe_emit_commitment_needed`: cp ∈ required_set + faz
  için pre-commitment-stated yok + complete yok → needed audit emit.
- `stop.py::_detect_commitment_trigger`: `commitment-recorded phase=N
  text="..."` text-trigger → `commitment.record_pre_commitment` çağır
  (mevcut audit kanalı).
- `dsi.py::render_commitment_notice`: needed var, pre-commitment-
  stated yok → bilingual direktif (`pre_commitment_request` key).
- `stop.py::_phase_22_check_commitment_required`: invariant 7.
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, commitment, dsi, state
from hooks.stop import (
    _detect_commitment_trigger,
    _maybe_emit_commitment_needed,
    _phase_22_check_commitment_required,
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


def test_commitment_needed_emitted_in_required_phase(tmp_project):
    """Aşama 4 (Spec) için commitment-needed audit emit."""
    state.set_field("current_phase", 4, project_root=str(tmp_project))

    wrote = _maybe_emit_commitment_needed(str(tmp_project))

    assert wrote is True
    needed = [
        ev for ev in audit.read_all(project_root=str(tmp_project))
        if ev.get("name") == "commitment-needed"
        and "phase=4" in ev.get("detail", "")
    ]
    assert len(needed) == 1


def test_commitment_needed_idempotent(tmp_project):
    """Aynı faz için 2 kez çağrılırsa tek needed audit."""
    state.set_field("current_phase", 9, project_root=str(tmp_project))

    _maybe_emit_commitment_needed(str(tmp_project))
    _maybe_emit_commitment_needed(str(tmp_project))

    needed = [
        ev for ev in audit.read_all(project_root=str(tmp_project))
        if ev.get("name") == "commitment-needed"
        and "phase=9" in ev.get("detail", "")
    ]
    assert len(needed) == 1


def test_commitment_needed_skipped_outside_required_set(tmp_project):
    """Aşama 5 (required değil) için needed audit yazılmaz."""
    state.set_field("current_phase", 5, project_root=str(tmp_project))

    wrote = _maybe_emit_commitment_needed(str(tmp_project))

    assert wrote is False


def test_commitment_needed_skipped_if_already_recorded(tmp_project):
    """Faz için pre-commitment-stated zaten varsa needed yazılmaz."""
    state.set_field("current_phase", 10, project_root=str(tmp_project))
    commitment.record_pre_commitment(
        "Aşama 10 riskleri kapatacağım çünkü pipeline güveni gerekli.",
        10, project_root=str(tmp_project),
    )

    wrote = _maybe_emit_commitment_needed(str(tmp_project))

    assert wrote is False


def test_commitment_needed_skipped_if_complete(tmp_project):
    """Faz complete edilmişse needed yazılmaz."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))
    audit.log_event(
        "asama-19-complete", "test", "done",
        project_root=str(tmp_project),
    )

    wrote = _maybe_emit_commitment_needed(str(tmp_project))

    assert wrote is False


def test_commitment_text_trigger_captured(tmp_project):
    """Model `commitment-recorded phase=N text="..."` yazınca hook
    `commitment.record_pre_commitment` çağırır; mevcut
    `pre-commitment-stated` audit kanalı kullanılır."""
    state.set_field("current_phase", 6, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            'commitment-recorded phase=6 text="Aşama 6 UI yapacağım çünkü '
            'spec frontend gerektiriyor."\n'
        ),
    ])

    wrote = _detect_commitment_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert wrote is True
    latest = commitment.latest_pre_commitment(
        6, project_root=str(tmp_project),
    )
    assert latest is not None
    assert "Aşama 6 UI yapacağım" in latest


def test_commitment_trigger_idempotent(tmp_project):
    """Aynı transcript 2 kez taranınca duplicate pre-commitment yok."""
    state.set_field("current_phase", 8, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            'commitment-recorded phase=8 text="DB tasarımı çünkü çoklu kaynak."\n'
        ),
    ])

    _detect_commitment_trigger(str(transcript_path), str(tmp_project))
    _detect_commitment_trigger(str(transcript_path), str(tmp_project))

    stated = [
        ev for ev in audit.read_all(project_root=str(tmp_project))
        if ev.get("name") == "pre-commitment-stated"
        and "phase=8" in ev.get("detail", "")
    ]
    assert len(stated) == 1


def test_commitment_text_truncation_via_commitment_module(tmp_project):
    """commitment.py 200 char truncation kuralı korunmalı (yeni kod
    yazılmadı, mevcut modül çağrıldı)."""
    long_text = "x" * 300
    state.set_field("current_phase", 4, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            f'commitment-recorded phase=4 text="{long_text}"\n'
        ),
    ])

    _detect_commitment_trigger(str(transcript_path), str(tmp_project))

    latest = commitment.latest_pre_commitment(
        4, project_root=str(tmp_project),
    )
    assert latest is not None
    # 200 char + "..." truncation
    assert len(latest) <= 230  # detail = `phase=4 text="..."`; truncated icinde


def test_commitment_regex_line_anchored(tmp_project):
    """Prose içinde gömülü `commitment-recorded` yakalanmamalı."""
    state.set_field("current_phase", 4, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            'Şöyle açıkladım: commitment-recorded phase=4 text="boş" '
            "bu prose içinde, gerçek söz değil."
        ),
    ])

    wrote = _detect_commitment_trigger(
        str(transcript_path), str(tmp_project)
    )

    assert wrote is False


def test_dsi_commitment_notice_emitted_when_needed(tmp_project):
    """DSI direktifi: needed var, pre-commitment yok → notice emit."""
    audit.log_event(
        "commitment-needed", "test", "phase=4 public_commitment_required",
        project_root=str(tmp_project),
    )

    notice = dsi.render_commitment_notice(project_root=str(tmp_project))

    assert notice != ""
    assert "<mycl_commitment_notice>" in notice
    assert "4" in notice  # bekleyen faz
    assert "commitment-recorded" in notice  # format yönlendirmesi


def test_dsi_commitment_notice_silent_after_recorded(tmp_project):
    """pre-commitment-stated audit varsa direktif susar."""
    audit.log_event(
        "commitment-needed", "test", "phase=10",
        project_root=str(tmp_project),
    )
    commitment.record_pre_commitment(
        "Aşama 10 riskleri çözeceğim çünkü kalite.",
        10, project_root=str(tmp_project),
    )

    notice = dsi.render_commitment_notice(project_root=str(tmp_project))

    assert notice == ""


def test_dsi_commitment_notice_silent_when_no_needed(tmp_project):
    """Hiç needed audit yoksa direktif yok."""
    notice = dsi.render_commitment_notice(project_root=str(tmp_project))
    assert notice == ""


def test_dsi_full_dsi_includes_commitment_notice(tmp_project):
    """render_full_dsi → commitment notice paketin parçası."""
    state.set_field("current_phase", 4, project_root=str(tmp_project))
    audit.log_event(
        "commitment-needed", "test", "phase=4",
        project_root=str(tmp_project),
    )

    full = dsi.render_full_dsi(project_root=str(tmp_project))

    assert "<mycl_commitment_notice>" in full


def test_phase_22_invariant_7_lists_missing_phases(tmp_project):
    """Aşama 22 invariant 7: pre-commitment-stated olmayan faz(lar)."""
    commitment.record_pre_commitment(
        "Aşama 4 sözü", 4, project_root=str(tmp_project),
    )

    events = audit.read_all(project_root=str(tmp_project))
    missing = _phase_22_check_commitment_required(events)

    assert 6 in missing
    assert 8 in missing
    assert 9 in missing
    assert 10 in missing
    assert 19 in missing
    assert 4 not in missing


def test_phase_22_invariant_7_all_recorded(tmp_project):
    """Tüm 6 faz için söz yazılmışsa missing boş."""
    for n in (4, 6, 8, 9, 10, 19):
        commitment.record_pre_commitment(
            f"Aşama {n} sözü", n, project_root=str(tmp_project),
        )

    events = audit.read_all(project_root=str(tmp_project))
    missing = _phase_22_check_commitment_required(events)

    assert missing == []


def test_phase_22_report_includes_commitment_section(tmp_project):
    """Aşama 22 raporunda commitment Disiplin satırı."""
    from hooks.stop import _emit_phase_22_completeness_report
    state.set_field("current_phase", 22, project_root=str(tmp_project))
    # Sadece 3 faz söz; 3 eksik (4 var ama 6/8/9 var; 10/19 eksik)
    for n in (4, 6, 8, 9):
        commitment.record_pre_commitment(
            f"Aşama {n} sözü", n, project_root=str(tmp_project),
        )

    _emit_phase_22_completeness_report(str(tmp_project))

    report = (Path(tmp_project) / ".mycl" / "completeness_report.md").read_text(
        encoding="utf-8"
    )
    assert "Disiplin (public_commitment_required)" in report
    assert "4/6" in report  # 4 yazıldı, 2 eksik (10, 19)
