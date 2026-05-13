"""test_phase33_selfcritique — self_critique_required disiplin bayrağı (1.0.33).

Aspirational halletme turu — kullanıcı "aspirational olanları da hallet"
dedi. Subagent (Sonnet 4.6, 10 lens) kritiği:

1. `selfcritique.py` modülü tam hazır ama hiçbir hook çağırmıyordu.
2. 7 faz `self_critique_required: true` (2, 4, 8, 9, 10, 14, 19).
3. Soft guidance (Option B): hook needed audit yazar, DSI direktif
   enjekte eder, model passed/gap text-trigger yazar, hook yakalar.
   Hard gate YOK — CLAUDE.md "soft guidance over fail-fast" kuralı.
4. Aşama 22 invariant 6 olarak yüzeye çıkarır (open issue).

İmplementasyon:
- `stop.py::_maybe_emit_selfcritique_needed`: cp ∈ required_set, cp
  için passed/gap audit yok, complete yok → needed audit emit.
- `stop.py::_detect_selfcritique_triggers`: passed/gap text-trigger
  yakala → `selfcritique.record_passed/gap` çağır.
- `dsi.py::render_selfcritique_notice`: needed audit var, henüz cevap
  yok → bilingual direktif enjekte.
- `stop.py::_phase_22_check_selfcritique_required`: Aşama 22
  invariant 6 — passed audit'i olmayan fazları listele.
- Regex: MULTILINE + line-anchored (`^[ \\t]*selfcritique-passed
  phase=N`) — prose gömülü eşleşmeleri önler.
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, dsi, selfcritique, state
from hooks.stop import (
    _detect_selfcritique_triggers,
    _maybe_emit_selfcritique_needed,
    _phase_22_check_selfcritique_required,
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


def test_selfcritique_needed_emitted_in_required_phase(tmp_project):
    """Aşama 9 (TDD) için selfcritique-needed audit emit edilir."""
    state.set_field("current_phase", 9, project_root=str(tmp_project))

    wrote = _maybe_emit_selfcritique_needed(str(tmp_project))

    assert wrote is True
    events = audit.read_all(project_root=str(tmp_project))
    needed = [
        ev for ev in events
        if ev.get("name") == "selfcritique-needed"
        and "phase=9" in ev.get("detail", "")
    ]
    assert len(needed) == 1


def test_selfcritique_needed_idempotent(tmp_project):
    """Aynı faz için 2 kez çağrılırsa tek needed audit yazılır."""
    state.set_field("current_phase", 4, project_root=str(tmp_project))

    _maybe_emit_selfcritique_needed(str(tmp_project))
    _maybe_emit_selfcritique_needed(str(tmp_project))

    needed = [
        ev for ev in audit.read_all(project_root=str(tmp_project))
        if ev.get("name") == "selfcritique-needed"
        and "phase=4" in ev.get("detail", "")
    ]
    assert len(needed) == 1


def test_selfcritique_needed_not_emitted_outside_required_set(tmp_project):
    """Aşama 5 (required değil) için needed audit yazılmaz."""
    state.set_field("current_phase", 5, project_root=str(tmp_project))

    wrote = _maybe_emit_selfcritique_needed(str(tmp_project))

    assert wrote is False
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "selfcritique-needed" not in names


def test_selfcritique_needed_skipped_if_already_responded(tmp_project):
    """Faz için passed audit zaten varsa needed yazılmaz (cevap gelmiş)."""
    state.set_field("current_phase", 10, project_root=str(tmp_project))
    selfcritique.record_passed(10, project_root=str(tmp_project))

    wrote = _maybe_emit_selfcritique_needed(str(tmp_project))

    assert wrote is False


def test_selfcritique_needed_skipped_if_complete(tmp_project):
    """Faz complete edilmişse needed yazılmaz."""
    state.set_field("current_phase", 14, project_root=str(tmp_project))
    audit.log_event(
        "asama-14-complete", "test", "done",
        project_root=str(tmp_project),
    )

    wrote = _maybe_emit_selfcritique_needed(str(tmp_project))

    assert wrote is False


def test_passed_text_trigger_captured(tmp_project):
    """Model `selfcritique-passed phase=N` yazınca hook
    selfcritique.record_passed çağırır."""
    state.set_field("current_phase", 9, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "Aşama 9 eksiklik kontrolü tamam.\n"
            "selfcritique-passed phase=9\n"
        ),
    ])

    wrote = _detect_selfcritique_triggers(
        str(transcript_path), str(tmp_project)
    )

    assert wrote is True
    assert selfcritique.is_passed_for_phase(
        9, project_root=str(tmp_project)
    ) is True


def test_gap_text_trigger_captured_with_items(tmp_project):
    """Model gap-found trigger yazınca items detay'a aktarılır."""
    state.set_field("current_phase", 10, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            'selfcritique-gap-found phase=10 items="eksik: validasyon, retry"\n'
        ),
    ])

    _detect_selfcritique_triggers(str(transcript_path), str(tmp_project))

    ev = selfcritique.latest_for_phase(10, project_root=str(tmp_project))
    assert ev is not None
    assert ev.get("name") == "selfcritique-gap-found"
    assert "eksik: validasyon, retry" in ev.get("detail", "")


def test_selfcritique_trigger_idempotent(tmp_project):
    """Aynı transcript 2 kez taranınca duplicate passed audit yok."""
    state.set_field("current_phase", 2, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("selfcritique-passed phase=2"),
    ])

    _detect_selfcritique_triggers(str(transcript_path), str(tmp_project))
    _detect_selfcritique_triggers(str(transcript_path), str(tmp_project))

    passed = [
        ev for ev in audit.read_all(project_root=str(tmp_project))
        if ev.get("name") == "selfcritique-passed"
        and "phase=2" in ev.get("detail", "")
    ]
    assert len(passed) == 1


def test_selfcritique_regex_line_anchored(tmp_project):
    """Regex satır-başı ankrajlı: prose içinde gömülü ham metin
    yakalanmaz (örn. `bahsediyorum: selfcritique-passed phase=4`).

    Subagent kritiği gereği — \\b word boundary yetmez."""
    state.set_field("current_phase", 4, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "Açıklama: bahsediyorum selfcritique-passed phase=4 "
            "konusundan, ama bu kelimeyi prose içinde geçirdim."
        ),
    ])

    wrote = _detect_selfcritique_triggers(
        str(transcript_path), str(tmp_project)
    )

    # Satır içi gömülü — yakalanmamalı
    assert wrote is False
    assert selfcritique.is_passed_for_phase(
        4, project_root=str(tmp_project)
    ) is False


def test_selfcritique_regex_caught_at_line_start(tmp_project):
    """Satır başında yazılırsa yakalanır (leading whitespace OK)."""
    state.set_field("current_phase", 8, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "DB tasarımı bitti.\n"
            "  selfcritique-passed phase=8\n"
        ),
    ])

    _detect_selfcritique_triggers(str(transcript_path), str(tmp_project))

    assert selfcritique.is_passed_for_phase(
        8, project_root=str(tmp_project)
    ) is True


def test_dsi_selfcritique_notice_emitted_when_needed_no_response(tmp_project):
    """DSI direktifi: needed var, henüz passed/gap yok → notice emit."""
    audit.log_event(
        "selfcritique-needed", "test", "phase=9 self_critique_required",
        project_root=str(tmp_project),
    )

    notice = dsi.render_selfcritique_notice(project_root=str(tmp_project))

    assert notice != ""
    assert "<mycl_selfcritique_notice>" in notice
    assert "9" in notice  # bekleyen faz listesi
    assert "selfcritique-passed" in notice  # format yönlendirmesi


def test_dsi_selfcritique_notice_silent_after_passed(tmp_project):
    """passed audit varsa direktif susar."""
    audit.log_event(
        "selfcritique-needed", "test", "phase=10",
        project_root=str(tmp_project),
    )
    selfcritique.record_passed(10, project_root=str(tmp_project))

    notice = dsi.render_selfcritique_notice(project_root=str(tmp_project))

    assert notice == ""


def test_dsi_selfcritique_notice_silent_after_gap(tmp_project):
    """gap-found audit varsa da direktif susar (cevap geldi)."""
    audit.log_event(
        "selfcritique-needed", "test", "phase=19",
        project_root=str(tmp_project),
    )
    selfcritique.record_gap(
        19, items="eksik", project_root=str(tmp_project),
    )

    notice = dsi.render_selfcritique_notice(project_root=str(tmp_project))

    assert notice == ""


def test_dsi_selfcritique_notice_silent_when_no_needed(tmp_project):
    """Hiç needed audit yoksa direktif emit edilmez."""
    notice = dsi.render_selfcritique_notice(project_root=str(tmp_project))
    assert notice == ""


def test_dsi_full_dsi_includes_selfcritique_when_needed(tmp_project):
    """render_full_dsi → selfcritique notice paketin parçası."""
    state.set_field("current_phase", 9, project_root=str(tmp_project))
    audit.log_event(
        "selfcritique-needed", "test", "phase=9",
        project_root=str(tmp_project),
    )

    full = dsi.render_full_dsi(project_root=str(tmp_project))

    assert "<mycl_selfcritique_notice>" in full


def test_phase_22_invariant_6_lists_missing_phases(tmp_project):
    """Aşama 22 invariant 6: selfcritique-passed olmayan faz(lar)
    raporda open issue olarak yer alır."""
    # Sadece Aşama 4 için passed; 2/8/9/10/14/19 eksik
    selfcritique.record_passed(4, project_root=str(tmp_project))

    events = audit.read_all(project_root=str(tmp_project))
    missing = _phase_22_check_selfcritique_required(events)

    assert 2 in missing
    assert 8 in missing
    assert 9 in missing
    assert 10 in missing
    assert 14 in missing
    assert 19 in missing
    assert 4 not in missing


def test_phase_22_invariant_6_all_passed(tmp_project):
    """Tüm 7 faz için passed audit varsa missing boş."""
    for n in (2, 4, 8, 9, 10, 14, 19):
        selfcritique.record_passed(n, project_root=str(tmp_project))

    events = audit.read_all(project_root=str(tmp_project))
    missing = _phase_22_check_selfcritique_required(events)

    assert missing == []


def test_phase_22_report_includes_selfcritique_section(tmp_project):
    """Aşama 22 raporunda Disiplin satırı görünür."""
    from hooks.stop import _emit_phase_22_completeness_report
    state.set_field("current_phase", 22, project_root=str(tmp_project))
    # Sadece kısmi passed audit'i — rapor "5/7" göstermeli
    for n in (2, 4, 8, 9, 10):
        selfcritique.record_passed(n, project_root=str(tmp_project))

    _emit_phase_22_completeness_report(str(tmp_project))

    report = (Path(tmp_project) / ".mycl" / "completeness_report.md").read_text(
        encoding="utf-8"
    )
    assert "Disiplin (self_critique_required)" in report
    assert "5/7" in report  # 5 faz passed, 2 eksik (14, 19)
