"""test_phase19_refactor — Aşama 19 mid-pipeline reconfirmation + open_impact_count (1.0.29).

Subagent (Sonnet 4.6, 10 lens) Aşama 19'da 3 boşluk tespit etti:
1. `mid_pipeline_reconfirm: true` gate_spec'te ama hiçbir hook okumuyor;
   skill "etki listesi >10 ise hook askq açar" diyor ama hook bunu
   tetiklemiyordu.
2. `state.open_impact_count` alanı yoktu — Aşama 22 tamlık denetimi
   Aşama 19 etki sayısını okuyacak ama veri yazılmıyordu.
3. `public_commitment_required: true` ve `self_critique_required: true`
   hâlâ aspirational — bu turda kapsam dışı, doc-truth Aşama 14
   yaklaşımıyla aynı (gelecek tur).

İmplement:
- `_maybe_emit_mid_reconfirm`: audit log'da 10+ `asama-19-item-M-resolved`
  → `asama-19-mid-reconfirm-needed` audit (idempotent).
- `_detect_mid_reconfirm_acked`: model `asama-19-mid-reconfirm-acked`
  text-trigger yazınca yakala (idempotent).
- `dsi.render_mid_reconfirm_notice`: needed AND NOT acked → soft direktif.
- `state.open_impact_count` Aşama 19 items-declared'tan yazılır.
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, dsi, state
from hooks.stop import (
    _detect_mid_reconfirm_acked,
    _detect_phase_items_triggers,
    _maybe_emit_mid_reconfirm,
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


def _seed_resolved_items(project_root: str, count: int) -> None:
    """count tane `asama-19-item-N-resolved` audit yaz (idempotency hariç)."""
    for i in range(1, count + 1):
        audit.log_event(
            f"asama-19-item-{i}-resolved", "test",
            f"phase=19 item={i} decision=apply",
            project_root=project_root,
        )


def test_phase_19_items_declared_writes_open_impact_count(tmp_project):
    """asama-19-items-declared count=K → audit + state.open_impact_count=K."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("Etki taraması: asama-19-items-declared count=7"),
    ])

    _detect_phase_items_triggers(str(transcript_path), str(tmp_project))

    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-19-items-declared" in names
    assert state.get(
        "open_impact_count", None, project_root=str(tmp_project)
    ) == 7


def test_phase_10_items_declared_does_not_write_open_impact_count(tmp_project):
    """Boundary: Aşama 10 → open_severity_count (sadece), open_impact_count
    Aşama 10 için yazılmaz."""
    state.set_field("current_phase", 10, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-10-items-declared count=5"),
    ])

    _detect_phase_items_triggers(str(transcript_path), str(tmp_project))

    assert state.get(
        "open_severity_count", 0, project_root=str(tmp_project)
    ) == 5
    # Aşama 10 turunda open_impact_count default kalmalı
    assert state.get(
        "open_impact_count", 0, project_root=str(tmp_project)
    ) == 0


def test_mid_reconfirm_emit_at_threshold(tmp_project):
    """10. resolved item-resolved audit'inden sonra hook
    `asama-19-mid-reconfirm-needed` emit eder."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))
    _seed_resolved_items(str(tmp_project), 10)

    wrote = _maybe_emit_mid_reconfirm(str(tmp_project))

    assert wrote is True
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-19-mid-reconfirm-needed" in names


def test_mid_reconfirm_no_emit_below_threshold(tmp_project):
    """9 resolved item → mid-reconfirm-needed YAZILMAZ."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))
    _seed_resolved_items(str(tmp_project), 9)

    wrote = _maybe_emit_mid_reconfirm(str(tmp_project))

    assert wrote is False
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-19-mid-reconfirm-needed" not in names


def test_mid_reconfirm_idempotent(tmp_project):
    """Aynı audit log'da 2 kez `_maybe_emit_mid_reconfirm` çağrısı →
    tek `asama-19-mid-reconfirm-needed` audit."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))
    _seed_resolved_items(str(tmp_project), 12)

    _maybe_emit_mid_reconfirm(str(tmp_project))
    _maybe_emit_mid_reconfirm(str(tmp_project))

    needs = [
        ev for ev in audit.read_all(project_root=str(tmp_project))
        if ev.get("name") == "asama-19-mid-reconfirm-needed"
    ]
    assert len(needs) == 1


def test_mid_reconfirm_only_phase_19(tmp_project):
    """Aşama 10'da 10+ item-resolved olsa bile mid-reconfirm-needed
    YAZILMAZ — mid_pipeline_reconfirm flag'i sadece Aşama 19'da."""
    state.set_field("current_phase", 10, project_root=str(tmp_project))
    for i in range(1, 12):
        audit.log_event(
            f"asama-10-item-{i}-resolved", "test",
            f"phase=10 item={i}", project_root=str(tmp_project),
        )

    wrote = _maybe_emit_mid_reconfirm(str(tmp_project))

    assert wrote is False
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-19-mid-reconfirm-needed" not in names
    # Aşama 10'a özel "asama-10-mid-reconfirm-needed" gibi bir audit de
    # YAZILMAZ — flag Aşama 19'a özel
    assert not any(
        n and n.startswith("asama-10-mid-reconfirm") for n in names
    )


def test_mid_reconfirm_acked_text_trigger(tmp_project):
    """Model `asama-19-mid-reconfirm-acked` yazarsa hook yakalar +
    audit emit."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text(
            "Geliştiri 'devam et' dedi. asama-19-mid-reconfirm-acked\n"
        ),
    ])

    wrote = _detect_mid_reconfirm_acked(
        str(transcript_path), str(tmp_project)
    )

    assert wrote is True
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_project))
    ]
    assert "asama-19-mid-reconfirm-acked" in names


def test_mid_reconfirm_acked_idempotent(tmp_project):
    """Aynı transcript 2 kez taranınca duplicate acked audit yok."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))
    transcript_path = tmp_project / "transcript.jsonl"
    _write_jsonl(transcript_path, [
        _assistant_text("asama-19-mid-reconfirm-acked"),
    ])

    _detect_mid_reconfirm_acked(str(transcript_path), str(tmp_project))
    _detect_mid_reconfirm_acked(str(transcript_path), str(tmp_project))

    ackeds = [
        ev for ev in audit.read_all(project_root=str(tmp_project))
        if ev.get("name") == "asama-19-mid-reconfirm-acked"
    ]
    assert len(ackeds) == 1


def test_dsi_mid_reconfirm_notice_emitted_when_needed_not_acked(tmp_project):
    """DSI direktifi: needed audit var, acked yok → notice emit."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))
    audit.log_event(
        "asama-19-mid-reconfirm-needed", "test",
        "phase=19 resolved_items=10 threshold=10",
        project_root=str(tmp_project),
    )

    notice = dsi.render_mid_reconfirm_notice(project_root=str(tmp_project))

    assert notice != ""
    assert "<mycl_mid_reconfirm_notice>" in notice
    assert "Aşama 19" in notice
    assert "Phase 19" in notice
    assert "mid-reconfirm-acked" in notice


def test_dsi_mid_reconfirm_notice_silent_after_acked(tmp_project):
    """DSI direktifi: acked audit varsa direktif susar."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))
    audit.log_event(
        "asama-19-mid-reconfirm-needed", "test",
        "phase=19 resolved_items=10",
        project_root=str(tmp_project),
    )
    audit.log_event(
        "asama-19-mid-reconfirm-acked", "test",
        "phase=19 acked",
        project_root=str(tmp_project),
    )

    notice = dsi.render_mid_reconfirm_notice(project_root=str(tmp_project))

    assert notice == ""


def test_dsi_mid_reconfirm_notice_silent_when_no_needed(tmp_project):
    """DSI direktifi: needed audit yoksa direktif emit edilmez."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))

    notice = dsi.render_mid_reconfirm_notice(project_root=str(tmp_project))

    assert notice == ""


def test_dsi_full_dsi_includes_mid_reconfirm_when_needed(tmp_project):
    """render_full_dsi → mid_reconfirm_notice de paketin parçası
    (Aşama 19 ortası askq direktifi tetik yolu)."""
    state.set_field("current_phase", 19, project_root=str(tmp_project))
    audit.log_event(
        "asama-19-mid-reconfirm-needed", "test",
        "phase=19 resolved_items=10",
        project_root=str(tmp_project),
    )

    full = dsi.render_full_dsi(project_root=str(tmp_project))

    assert "<mycl_mid_reconfirm_notice>" in full


def test_maybe_emit_mid_reconfirm_no_phase_19_no_op(tmp_project):
    """Aşama 19 dışı bir fazda çağrılırsa no-op."""
    state.set_field("current_phase", 5, project_root=str(tmp_project))
    _seed_resolved_items(str(tmp_project), 15)

    wrote = _maybe_emit_mid_reconfirm(str(tmp_project))

    assert wrote is False
