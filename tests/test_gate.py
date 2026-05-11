"""hooks/lib/gate.py birim testleri.

Layer B kritik invariantları:
    - Global always-allowed tools (Read/Glob/...) her fazda izinli
    - Mutating tool aktif fazın allowed_tools listesinde değilse deny
    - denied_paths glob match (recursive **)
    - advance: sequential +1, audit + trace yan etkileri
    - STRICT: gate tanımı yoksa fail-closed
"""

from __future__ import annotations

import json

from hooks.lib import audit, gate, state, trace


# ---------- Test fixture gate_spec ----------


def _test_spec() -> dict:
    """Mini test gate_spec — gerçek prod spec'i taklit ama küçük."""
    return {
        "_global_always_allowed_tools": [
            "Read", "Glob", "Grep", "LS", "WebFetch", "WebSearch",
            "Task", "Skill", "TodoWrite",
        ],
        "phases": {
            "1": {
                "name": "Niyet Toplama",
                "name_en": "Intent Gathering",
                "allowed_tools": ["AskUserQuestion"],
                "denied_paths": [],
                "fail_open": False,
            },
            "4": {
                "name": "Spec Yazımı + Onay",
                "name_en": "Spec Writing",
                "allowed_tools": ["AskUserQuestion"],
                "denied_paths": [],
                "fail_open": False,
            },
            "6": {
                "name": "UI Yapımı",
                "name_en": "UI Build",
                "allowed_tools": ["Write", "Edit", "Bash", "AskUserQuestion"],
                "denied_paths": [
                    "src/api/**", "prisma/**", "models/**",
                ],
                "fail_open": False,
            },
            "9": {
                "name": "TDD Yürütme",
                "name_en": "TDD Execution",
                "allowed_tools": ["Write", "Edit", "Bash", "AskUserQuestion"],
                "denied_paths": [],
                "fail_open": False,
            },
        },
    }


# ---------- glob match ----------


def test_glob_simple_star():
    assert gate.path_matches_glob("src/foo.ts", "src/*.ts") is True
    assert gate.path_matches_glob("src/sub/foo.ts", "src/*.ts") is False


def test_glob_recursive_double_star():
    assert gate.path_matches_glob("src/api/users.ts", "src/api/**") is True
    assert gate.path_matches_glob("src/api/sub/deep/file.ts", "src/api/**") is True
    assert gate.path_matches_glob("src/api/users.ts", "src/components/**") is False


def test_glob_question_mark():
    assert gate.path_matches_glob("test.a", "test.?") is True
    assert gate.path_matches_glob("test.ab", "test.?") is False


def test_glob_empty_inputs():
    assert gate.path_matches_glob("", "src/**") is False
    assert gate.path_matches_glob("src/foo.ts", "") is False


def test_glob_special_chars_escaped():
    """`.` literal regex karakteri olmamalı (escape edilmeli)."""
    assert gate.path_matches_glob("config.json", "config.json") is True
    # `config.json` literal — `configXjson` match etmemeli
    assert gate.path_matches_glob("configXjson", "config.json") is False


# ---------- evaluate: global always-allowed ----------


def test_evaluate_read_always_allowed_phase_1(tmp_project):
    spec = _test_spec()
    allowed, reason = gate.evaluate("Read", gate_spec=spec)
    assert allowed is True
    assert reason == ""


def test_evaluate_grep_always_allowed_any_phase(tmp_project):
    """Read-only tools her fazda izinli — global valve."""
    spec = _test_spec()
    state.set_field("current_phase", 9)
    allowed, _ = gate.evaluate("Grep", gate_spec=spec)
    assert allowed is True


# ---------- evaluate: phase allowed_tools ----------


def test_evaluate_askq_allowed_phase_1(tmp_project):
    spec = _test_spec()
    allowed, _ = gate.evaluate("AskUserQuestion", gate_spec=spec)
    assert allowed is True


def test_evaluate_write_denied_phase_1(tmp_project):
    """Aşama 1: sadece AskUserQuestion. Write deny."""
    spec = _test_spec()
    allowed, reason = gate.evaluate("Write", gate_spec=spec)
    assert allowed is False
    assert "Aşama 1" in reason
    assert "Write" in reason


def test_evaluate_write_allowed_phase_6(tmp_project):
    """Aşama 6 UI Build: Write izinli."""
    spec = _test_spec()
    state.set_field("current_phase", 6)
    allowed, _ = gate.evaluate("Write", gate_spec=spec)
    assert allowed is True


def test_evaluate_write_allowed_phase_9_tdd(tmp_project):
    spec = _test_spec()
    state.set_field("current_phase", 9)
    allowed, _ = gate.evaluate("Write", gate_spec=spec)
    assert allowed is True


# ---------- evaluate: denied_paths (Aşama 6 backend yasağı) ----------


def test_evaluate_phase_6_denies_backend_path(tmp_project):
    """Pseudocode §3 Aşama 6: src/api/**, prisma/**, ... yasak."""
    spec = _test_spec()
    state.set_field("current_phase", 6)
    allowed, reason = gate.evaluate("Write", file_path="src/api/users.ts", gate_spec=spec)
    assert allowed is False
    assert "yol yasak" in reason


def test_evaluate_phase_6_allows_frontend_path(tmp_project):
    spec = _test_spec()
    state.set_field("current_phase", 6)
    allowed, _ = gate.evaluate(
        "Write", file_path="src/components/Login.tsx", gate_spec=spec
    )
    assert allowed is True


def test_evaluate_phase_6_denies_prisma_recursive(tmp_project):
    spec = _test_spec()
    state.set_field("current_phase", 6)
    allowed, _ = gate.evaluate(
        "Write", file_path="prisma/migrations/001_init.sql", gate_spec=spec
    )
    assert allowed is False


# ---------- evaluate: STRICT fail-closed ----------


def test_evaluate_unknown_phase_fail_closed(tmp_project):
    """gate_spec'te faz tanımı yok → fail-closed deny."""
    spec = {"_global_always_allowed_tools": [], "phases": {}}
    allowed, reason = gate.evaluate("Write", gate_spec=spec)
    assert allowed is False
    assert "fail-closed" in reason or "izinli değil" in reason


def test_evaluate_empty_tool(tmp_project):
    spec = _test_spec()
    allowed, reason = gate.evaluate("", gate_spec=spec)
    assert allowed is False


# ---------- active_phase ----------


def test_active_phase_default(tmp_project):
    assert gate.active_phase() == 1


def test_active_phase_reads_state(tmp_project):
    state.set_field("current_phase", 7)
    assert gate.active_phase() == 7


def test_next_phase():
    assert gate.next_phase(1) == 2
    assert gate.next_phase(21) == 22
    assert gate.next_phase(22) == 22  # son faz, durur


# ---------- advance ----------


def test_advance_increments_state(tmp_project):
    state.set_field("current_phase", 4)
    new_phase = gate.advance()
    assert new_phase == 5
    assert state.get("current_phase") == 5


def test_advance_writes_audit(tmp_project):
    state.set_field("current_phase", 4)
    gate.advance(caller="stop.py")
    ev = audit.latest("phase-advance")
    assert ev is not None
    assert ev["caller"] == "stop.py"
    assert "from=4" in ev["detail"]
    assert "to=5" in ev["detail"]


def test_advance_writes_trace(tmp_project):
    state.set_field("current_phase", 4)
    gate.advance()
    tr = trace.latest("phase_transition")
    assert tr is not None
    assert tr["value"] == "4->5"


def test_advance_updates_phase_name(tmp_project):
    """Pseudocode'da state.phase_name de güncellenir."""
    state.set_field("current_phase", 4)
    gate.advance()
    pn = state.get("phase_name")
    assert pn is not None
    assert isinstance(pn, str)
    assert len(pn) > 0


def test_advance_at_22_is_noop(tmp_project):
    """Son fazda advance no-op."""
    state.set_field("current_phase", 22)
    new_phase = gate.advance()
    assert new_phase == 22
    assert state.get("current_phase") == 22


# ---------- deny_count_in_session ----------


def test_deny_count_zero_when_no_audits(tmp_project):
    assert gate.deny_count_in_session("spec-approval-block") == 0


def test_deny_count_counts_matching_audits(tmp_project):
    audit.log_event("spec-approval-block", "pre_tool", "tool=Write strike=1")
    audit.log_event("spec-approval-block", "pre_tool", "tool=Write strike=2")
    audit.log_event("spec-approval-block", "pre_tool", "tool=Bash strike=3")
    audit.log_event("phase-allowlist-block", "pre_tool", "tool=Write")
    assert gate.deny_count_in_session("spec-approval-block") == 3
    assert gate.deny_count_in_session("phase-allowlist-block") == 1


def test_deny_count_empty_event_returns_zero(tmp_project):
    audit.log_event("e1", "stop")
    assert gate.deny_count_in_session("") == 0


# ---------- has_recent_deny (Disiplin #12 cooldown) ----------


def test_has_recent_deny_within_1(tmp_project):
    audit.log_event("spec-approval-block", "pre_tool", "tool=Write")
    assert gate.has_recent_deny("spec-approval-block", within=1) is True


def test_has_recent_deny_pushed_out_of_window(tmp_project):
    audit.log_event("spec-approval-block", "pre_tool")
    audit.log_event("other-event", "stop")
    audit.log_event("phase-advance", "gate")
    # window=1 → son 1 audit phase-advance, deny değil
    assert gate.has_recent_deny("spec-approval-block", within=1) is False
    # window=3 → son 3 içinde spec-approval-block var
    assert gate.has_recent_deny("spec-approval-block", within=3) is True


def test_has_recent_deny_zero_when_no_audits(tmp_project):
    assert gate.has_recent_deny("anything") is False


# ---------- load_gate_spec ----------


def test_load_gate_spec_from_real_file(tmp_path):
    p = tmp_path / "gate_spec.json"
    p.write_text(
        json.dumps({
            "_global_always_allowed_tools": ["Read"],
            "phases": {"1": {"allowed_tools": ["AskUserQuestion"], "denied_paths": []}},
        }),
        encoding="utf-8",
    )
    spec = gate.load_gate_spec(p)
    assert "Read" in spec["_global_always_allowed_tools"]


def test_load_gate_spec_missing_returns_empty(tmp_path):
    spec = gate.load_gate_spec(tmp_path / "no.json")
    assert spec["phases"] == {}


def test_load_gate_spec_corrupt_returns_empty(tmp_path):
    p = tmp_path / "bad.json"
    p.write_text("{not valid", encoding="utf-8")
    spec = gate.load_gate_spec(p)
    assert spec["phases"] == {}


def test_real_repo_gate_spec_loads():
    """Repo data/gate_spec.json gerçekten yükleniyor mu?"""
    gate.reset_cache()
    spec = gate.load_gate_spec()
    assert "Read" in spec["_global_always_allowed_tools"]
    # 22 faz tam
    assert len(spec["phases"]) == 22


def test_real_repo_gate_spec_agent_globally_allowed():
    """Agent tool (host subagent dispatch) globally allowed list'te.

    /zeka self-critique system + diğer subagent-dispatch akışları
    Aşama 1 dahil her fazda Agent tool kullanabilsin diye eklendi.
    Subagent state'e dokunmaz; tek yazıcı parent context.
    """
    gate.reset_cache()
    spec = gate.load_gate_spec()
    assert "Agent" in spec["_global_always_allowed_tools"]


# ---------- isolation ----------


def test_evaluate_isolated_per_project(tmp_path, monkeypatch):
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir()
    b.mkdir()
    spec = _test_spec()
    state.set_field("current_phase", 1, project_root=str(a))
    state.set_field("current_phase", 6, project_root=str(b))
    # a'da Aşama 1 → Write deny
    allowed_a, _ = gate.evaluate("Write", project_root=str(a), gate_spec=spec)
    # b'de Aşama 6 → Write allow (frontend path verilmedi)
    allowed_b, _ = gate.evaluate("Write", project_root=str(b), gate_spec=spec)
    assert allowed_a is False
    assert allowed_b is True
