"""hooks/lib/audit.py birim testleri.

Kapsama:
    - log_event append-only, format
    - parse_line + read_all
    - has / find / latest
    - validation (geçersiz isim, pipe içeren detail)
    - is_phase_complete + phase_number
    - has_signature + log_event_signed
"""

from __future__ import annotations

import re
import time

import pytest

from hooks.lib import audit


# ---------- log_event + read_all ----------


def test_log_event_creates_file(tmp_project):
    audit.log_event("asama-1-complete", "stop.py", "details=foo")
    p = audit.audit_path()
    assert p.exists()


def test_log_event_appends_lines(tmp_project):
    audit.log_event("asama-1-complete", "stop.py", "first")
    audit.log_event("asama-2-complete", "stop.py", "second")
    events = audit.read_all()
    assert len(events) == 2
    assert events[0]["name"] == "asama-1-complete"
    assert events[1]["name"] == "asama-2-complete"


def test_log_event_format(tmp_project):
    audit.log_event("test-event", "test.py", "k=v")
    line = audit.audit_path().read_text().strip()
    # ISO 8601 UTC + 3 pipe ayraç
    assert re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z \| ", line)
    assert line.count(" | ") == 3
    assert "test-event" in line
    assert "k=v" in line


def test_log_event_empty_detail_ok(tmp_project):
    audit.log_event("asama-3-complete", "stop.py")
    ev = audit.read_all()[0]
    assert ev["detail"] == ""


# ---------- parse_line ----------


def test_parse_line_well_formed():
    line = "2026-05-09T20:00:00Z | asama-4-complete | stop.py | covers=MUST_1"
    ev = audit.parse_line(line)
    assert ev is not None
    assert ev["ts"] == "2026-05-09T20:00:00Z"
    assert ev["name"] == "asama-4-complete"
    assert ev["caller"] == "stop.py"
    assert ev["detail"] == "covers=MUST_1"


def test_parse_line_with_pipe_in_detail():
    """detail içinde " | " yasak ama yine de parse'ı bozmaz —
    log_event yazımda reddeder, eski log dosyalarında olabilir."""
    line = "2026-05-09T20:00:00Z | name | caller | k=a | b"
    ev = audit.parse_line(line)
    # split limit=3 sayesinde sondan değil baştan ayrılır
    assert ev is not None
    assert ev["detail"] == "k=a | b"


def test_parse_line_malformed_returns_none():
    assert audit.parse_line("") is None
    assert audit.parse_line("just text") is None
    assert audit.parse_line("a | b") is None


# ---------- has / find / latest ----------


def test_has_event(tmp_project):
    audit.log_event("asama-1-complete", "stop.py")
    audit.log_event("asama-2-complete", "stop.py")
    assert audit.has("asama-1-complete") is True
    assert audit.has("asama-99-complete") is False


def test_find_by_prefix(tmp_project):
    audit.log_event("asama-9-ac-1-red", "stop.py")
    audit.log_event("asama-9-ac-1-green", "stop.py")
    audit.log_event("asama-10-complete", "stop.py")
    matches = audit.find(name_prefix="asama-9-")
    assert len(matches) == 2


def test_find_by_caller(tmp_project):
    audit.log_event("a", "stop.py")
    audit.log_event("b", "pre_tool.py")
    audit.log_event("c", "stop.py")
    matches = audit.find(caller="stop.py")
    assert len(matches) == 2
    assert {ev["name"] for ev in matches} == {"a", "c"}


def test_latest_returns_most_recent(tmp_project):
    audit.log_event("recur", "stop.py", "first")
    audit.log_event("other", "stop.py")
    audit.log_event("recur", "stop.py", "second")
    ev = audit.latest("recur")
    assert ev is not None
    assert ev["detail"] == "second"


def test_latest_returns_none_when_absent(tmp_project):
    assert audit.latest("nope") is None


# ---------- validation ----------


def test_log_event_rejects_pipe_in_name(tmp_project):
    with pytest.raises(ValueError):
        audit.log_event("name | with | pipes", "stop.py")


def test_log_event_rejects_pipe_in_detail(tmp_project):
    """detail içinde " | " yasak — parse() ayraç olarak görür."""
    with pytest.raises(ValueError):
        audit.log_event("ev", "stop.py", "k1=v1 | k2=v2")


def test_log_event_rejects_empty_name(tmp_project):
    with pytest.raises(ValueError):
        audit.log_event("", "stop.py")


# ---------- phase helpers ----------


def test_is_phase_complete():
    """is_phase_complete = sadece complete veya end (Disiplin #4 imza için)."""
    assert audit.is_phase_complete("asama-4-complete") is True
    assert audit.is_phase_complete("asama-22-complete") is True
    assert audit.is_phase_complete("asama-6-end") is True
    assert audit.is_phase_complete("asama-5-skipped") is False
    assert audit.is_phase_complete("asama-8-not-applicable") is False
    assert audit.is_phase_complete("precision-audit") is False
    assert audit.is_phase_complete("asama-9-ac-1-red") is False


def test_is_phase_finished():
    """is_phase_finished = herhangi bir bitiş (complete/end/skipped/not-applicable).

    gate.advance() bunu kullanır — pseudocode'da bir fazın 'bitmesi'
    bu 4 durumdan herhangi biri.
    """
    # 4 bitiş formu hepsi True
    assert audit.is_phase_finished("asama-4-complete") is True
    assert audit.is_phase_finished("asama-6-end") is True
    assert audit.is_phase_finished("asama-5-skipped") is True
    assert audit.is_phase_finished("asama-8-not-applicable") is True
    # Bitiş olmayan audit'ler False
    assert audit.is_phase_finished("asama-9-ac-1-red") is False
    assert audit.is_phase_finished("asama-9-ac-1-green") is False
    assert audit.is_phase_finished("asama-10-items-declared") is False
    assert audit.is_phase_finished("precision-audit") is False
    assert audit.is_phase_finished("engineering-brief") is False
    # Faz prefix'i olmayan audit'ler de False
    assert audit.is_phase_finished("pattern-summary-stored") is False


def test_phase_number():
    assert audit.phase_number("asama-4-complete") == 4
    assert audit.phase_number("asama-22-end") == 22
    assert audit.phase_number("asama-9-ac-1-red") == 9
    assert audit.phase_number("precision-audit") is None


# ---------- audit signature (disiplin #4) ----------


def test_has_signature_present():
    assert audit.has_signature('signature=ab12cd34 summary="spec yazıldı"') is True


def test_has_signature_missing():
    assert audit.has_signature("") is False
    assert audit.has_signature("just=plain") is False
    assert audit.has_signature("signature=ab12cd34") is False  # summary yok
    assert audit.has_signature('summary="x"') is False  # signature yok


def test_log_event_signed(tmp_project):
    audit.log_event_signed(
        "asama-4-complete",
        "stop.py",
        signature="ab12cd34",
        summary="spec onaylandı",
        extra_detail="ac_count=5",
    )
    ev = audit.latest("asama-4-complete")
    assert ev is not None
    assert audit.has_signature(ev["detail"]) is True
    assert "signature=ab12cd34" in ev["detail"]
    assert 'summary="spec onaylandı"' in ev["detail"]
    assert "ac_count=5" in ev["detail"]


def test_log_event_signed_rejects_summary_with_keys(tmp_project):
    with pytest.raises(ValueError):
        audit.log_event_signed(
            "asama-4-complete",
            "stop.py",
            signature="ab",
            summary="bu summary= içeriyor",
        )


# ---------- isolation ----------


def test_independent_project_dirs(tmp_path, monkeypatch):
    a = tmp_path / "proj_a"
    b = tmp_path / "proj_b"
    a.mkdir()
    b.mkdir()
    audit.log_event("e1", "stop.py", project_root=str(a))
    audit.log_event("e2", "stop.py", project_root=str(b))
    assert audit.has("e1", project_root=str(a)) is True
    assert audit.has("e1", project_root=str(b)) is False
    assert audit.has("e2", project_root=str(b)) is True
    assert audit.has("e2", project_root=str(a)) is False


# ---------- ordering ----------


def test_chronological_order(tmp_project):
    """Append-only invariant: sıra korunur."""
    for i in range(5):
        audit.log_event(f"event-{i}", "stop.py")
        time.sleep(0.001)  # timestamp ayrımı için
    events = audit.read_all()
    names = [ev["name"] for ev in events]
    assert names == [f"event-{i}" for i in range(5)]
