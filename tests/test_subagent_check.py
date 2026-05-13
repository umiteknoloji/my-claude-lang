"""hooks/lib/subagent_check.py birim testleri."""

from __future__ import annotations

from hooks.lib import audit, subagent_check


def _spec_with_rubber_duck(phases_with: list[int]) -> dict:
    return {
        "_global_always_allowed_tools": [],
        "phases": {
            str(p): {"subagent_rubber_duck": p in phases_with}
            for p in range(1, 23)
        },
    }


# ---------- should_trigger ----------


def test_should_trigger_rubber_duck_phase():
    spec = _spec_with_rubber_duck([4, 9, 10, 22])
    assert subagent_check.should_trigger(4, gate_spec=spec) is True
    assert subagent_check.should_trigger(9, gate_spec=spec) is True
    assert subagent_check.should_trigger(22, gate_spec=spec) is True


def test_should_not_trigger_other_phases():
    spec = _spec_with_rubber_duck([4, 9, 10, 22])
    assert subagent_check.should_trigger(5, gate_spec=spec) is False
    assert subagent_check.should_trigger(11, gate_spec=spec) is False


def test_should_trigger_unknown_phase_returns_false():
    spec = _spec_with_rubber_duck([4])
    assert subagent_check.should_trigger(99, gate_spec=spec) is False


def test_should_trigger_real_gate_spec():
    """Production gate_spec.json: 1.0.36'da subagent_rubber_duck flag'i
    Aşama 10 ve 22'den de KALDIRILDI (tüm fazlardan kaldırılma
    sürecinin son adımı).

    Tarihsel kaldırma:
    1.0.19: Aşama 4 — Aşama 1/2/3 tutarlı politika.
    1.0.24: Aşama 9 — Aşama 1-8 ile tutarlı (TDD red/green/refactor
    ana bağlamda yürür, subagent dispatch gereksiz).
    1.0.36: Aşama 10 + 22 — selfcritique (1.0.33) Aşama 10'da zaten
    "model kendi çıktısını eleştiriyor" işlevini görüyor (redundant);
    Aşama 22 raporu 7 invariant doğrulamasıyla kapsamlı ikinci-göz
    sağlıyor; ek Haiku dispatch self-loop sorunu + cost artırıcı.
    `subagent_check.py` modülü mevcut ama hiçbir hook'tan
    çağrılmıyor (declared-but-not-implemented kapatması — Plugin Kural
    B / 1.0.35 deseniyle aynı).
    """
    import hooks.lib.gate as gate
    gate.reset_cache()
    assert subagent_check.should_trigger(1) is False
    assert subagent_check.should_trigger(4) is False
    assert subagent_check.should_trigger(9) is False
    assert subagent_check.should_trigger(10) is False  # 1.0.36 kaldırıldı
    assert subagent_check.should_trigger(22) is False  # 1.0.36 kaldırıldı


# ---------- rubber_duck_prompt ----------


def test_prompt_includes_phase_number():
    p = subagent_check.rubber_duck_prompt(phase=9, phase_summary="TDD cycles done")
    assert "Phase 9" in p
    assert "TDD cycles done" in p


def test_prompt_includes_response_format():
    p = subagent_check.rubber_duck_prompt(phase=4)
    assert "verdict=" in p
    assert "passed" in p
    assert "concerned" in p
    assert "failed" in p


def test_prompt_no_summary_uses_placeholder():
    p = subagent_check.rubber_duck_prompt(phase=4)
    assert "(no summary)" in p


# ---------- record_check ----------


def test_record_passed(tmp_project):
    subagent_check.record_check(4, "passed", "spec is coherent")
    ev = audit.latest("subagent-rubber-duck")
    assert ev is not None
    assert "phase=4" in ev["detail"]
    assert "verdict=passed" in ev["detail"]
    assert "spec is coherent" in ev["detail"]


def test_record_concerned(tmp_project):
    subagent_check.record_check(9, "concerned", "edge case missed")
    ev = audit.latest("subagent-rubber-duck")
    assert ev is not None
    assert "verdict=concerned" in ev["detail"]


def test_record_failed(tmp_project):
    subagent_check.record_check(22, "failed", "tdd skipped")
    ev = audit.latest("subagent-rubber-duck")
    assert ev is not None
    assert "verdict=failed" in ev["detail"]


def test_record_invalid_verdict_skipped(tmp_project):
    subagent_check.record_check(4, "approved", "x")
    subagent_check.record_check(4, "yes", "x")
    subagent_check.record_check(4, "", "x")
    assert audit.latest("subagent-rubber-duck") is None


def test_record_truncates_long_summary(tmp_project):
    subagent_check.record_check(4, "passed", "x" * 500)
    ev = audit.latest("subagent-rubber-duck")
    assert ev is not None
    assert "..." in ev["detail"]


def test_record_replaces_pipe(tmp_project):
    subagent_check.record_check(4, "passed", "a | b")
    ev = audit.latest("subagent-rubber-duck")
    assert ev is not None
    assert " | " not in ev["detail"]


# ---------- latest_for_phase ----------


def test_latest_for_phase_filtered(tmp_project):
    subagent_check.record_check(4, "passed", "")
    subagent_check.record_check(9, "concerned", "")
    ev = subagent_check.latest_for_phase(9)
    assert ev is not None
    assert "phase=9" in ev["detail"]


def test_latest_for_phase_none_when_absent(tmp_project):
    assert subagent_check.latest_for_phase(4) is None


# ---------- isolation ----------


def test_isolated_per_project(tmp_path, monkeypatch):
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir()
    b.mkdir()
    subagent_check.record_check(4, "passed", "ok", project_root=str(a))
    ev_a = subagent_check.latest_for_phase(4, project_root=str(a))
    ev_b = subagent_check.latest_for_phase(4, project_root=str(b))
    assert ev_a is not None
    assert ev_b is None
