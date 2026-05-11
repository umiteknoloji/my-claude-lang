"""Smoke matrix integration tests — pseudocode invariantları uçtan uca.

Plan'daki integration test ihtiyaçları:
  - state=N × tool=X → expected verdict matrisi (gate_spec.json'a göre)
  - STRICT no-fail-open: 5 strike spec-approval-block hepsi deny + escalation
  - State lock: Bash kanalından state.set deneme → DENY
  - Production simulation: empty proje + intent → Aşama 1 askq

Birim testler her hook'u izole test ederken bu suite **uçtan uca akış**
test eder: hooks zinciri (activate → pre_tool → post_tool → stop) bir
gerçek senaryoda doğru çalışıyor mu?
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


_HOOKS_DIR = Path(__file__).resolve().parent.parent / "hooks"
_ACTIVATE = _HOOKS_DIR / "activate.py"
_PRE_TOOL = _HOOKS_DIR / "pre_tool.py"
_POST_TOOL = _HOOKS_DIR / "post_tool.py"
_STOP = _HOOKS_DIR / "stop.py"


def _run(hook_path: Path, payload: dict, env: dict) -> str:
    """Hook'u subprocess olarak çalıştır → stdout (rc != 0 ise raise)."""
    result = subprocess.run(
        [sys.executable, str(hook_path)],
        input=json.dumps(payload).encode("utf-8"),
        capture_output=True,
        timeout=15,
        env=env,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"hook {hook_path.name} exit {result.returncode}: "
            f"stderr={result.stderr.decode()}"
        )
    return result.stdout.decode().strip()


def _env_with(project_dir: Path) -> dict:
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(project_dir)
    return env


def _write_state(project_dir: Path, **fields) -> None:
    mycl_dir = project_dir / ".mycl"
    mycl_dir.mkdir(parents=True, exist_ok=True)
    base = {
        "schema_version": 1, "current_phase": 1, "spec_approved": False,
        "spec_hash": None, "spec_must_list": [],
    }
    base.update(fields)
    (mycl_dir / "state.json").write_text(json.dumps(base), encoding="utf-8")


def _read_state(project_dir: Path) -> dict:
    return json.loads((project_dir / ".mycl" / "state.json").read_text())


def _read_audit(project_dir: Path) -> str:
    p = project_dir / ".mycl" / "audit.log"
    return p.read_text(encoding="utf-8") if p.exists() else ""


def _decision(stdout: str) -> str:
    if not stdout:
        return ""
    return json.loads(stdout).get("hookSpecificOutput", {}).get(
        "permissionDecision", "")


# ---------- Smoke matrix: state × tool ----------


def test_smoke_phase_1_write_denied(tmp_path):
    """state=1 + Write → spec onaysız + Layer B → DENY."""
    _write_state(tmp_path, current_phase=1)
    out = _run(_PRE_TOOL, {
        "cwd": str(tmp_path), "tool_name": "Write",
        "tool_input": {"file_path": str(tmp_path / "x.txt"), "content": "x"},
    }, _env_with(tmp_path))
    assert _decision(out) == "deny"


def test_smoke_phase_2_askq_allowed(tmp_path):
    """state=2 + AskUserQuestion → Aşama 2'de izinli → ALLOW.

    Aşama 1 POC'la birlikte allowed_tools=["Task"] oldu (askq subagent
    içine taşındı); askq izni Aşama 2'den itibaren tek-context fazlarda.
    """
    _write_state(tmp_path, current_phase=2, spec_approved=True)
    out = _run(_PRE_TOOL, {
        "cwd": str(tmp_path), "tool_name": "AskUserQuestion",
        "tool_input": {"questions": []},
    }, _env_with(tmp_path))
    assert _decision(out) == "allow"


def test_smoke_phase_4_approval_chain(tmp_path):
    """state=4 + Spec block + askq approve → spec_approved=True +
    audit chain auto-fill → state.current_phase ilerler."""
    _write_state(tmp_path, current_phase=4)

    # Stop hook için JSONL transcript: assistant text (Spec) + askq pair
    transcript = tmp_path / "transcript.jsonl"
    spec_text = "📋 Spec:\nMUST:\n- foo"
    transcript.write_text(
        json.dumps({"type": "assistant", "message": {
            "role": "assistant",
            "content": [{"type": "text", "text": spec_text}]}}) + "\n" +
        json.dumps({"type": "assistant", "message": {
            "role": "assistant",
            "content": [{"type": "tool_use", "id": "askq-1",
                         "name": "AskUserQuestion", "input": {}}]}}) + "\n" +
        json.dumps({"type": "user", "message": {
            "role": "user",
            "content": [{"type": "tool_result", "tool_use_id": "askq-1",
                         "content": "evet onaylıyorum"}]}}) + "\n",
        encoding="utf-8",
    )

    _run(_STOP, {
        "cwd": str(tmp_path), "transcript_path": str(transcript),
    }, _env_with(tmp_path))

    s = _read_state(tmp_path)
    assert s["spec_approved"] is True
    assert s["current_phase"] == 5  # 4 → 5 universal completeness loop
    audit = _read_audit(tmp_path)
    for n in (1, 2, 3, 4):
        assert f"asama-{n}-complete" in audit


def test_smoke_phase_6_ui_path_allowed(tmp_path):
    """state=6 + Write to UI path → ALLOW + ui_flow_active=True."""
    _write_state(tmp_path, current_phase=6, spec_approved=True)
    out = _run(_PRE_TOOL, {
        "cwd": str(tmp_path), "tool_name": "Write",
        "tool_input": {"file_path": "src/components/Foo.tsx", "content": "x"},
    }, _env_with(tmp_path))
    assert _decision(out) == "allow"

    # post_tool reaktif
    _run(_POST_TOOL, {
        "cwd": str(tmp_path), "tool_name": "Write",
        "tool_input": {"file_path": "src/components/Foo.tsx"},
        "tool_response": {},
    }, _env_with(tmp_path))
    assert _read_state(tmp_path)["ui_flow_active"] is True


def test_smoke_phase_6_backend_path_denied(tmp_path):
    """state=6 + Write to backend path → DENY (denied_paths)."""
    _write_state(tmp_path, current_phase=6, spec_approved=True)
    # Write için file_path Layer B path matching çalışıyor
    out = _run(_PRE_TOOL, {
        "cwd": str(tmp_path), "tool_name": "Write",
        "tool_input": {"file_path": "src/api/users.ts", "content": "x"},
    }, _env_with(tmp_path))
    assert _decision(out) == "deny"


# ---------- STRICT no-fail-open ----------


def test_strict_five_strikes_escalation(tmp_path):
    """5 ardışık spec-approval-block hepsi DENY + 5. tetikte escalation."""
    _write_state(tmp_path, spec_approved=False)
    payload = {
        "cwd": str(tmp_path), "tool_name": "Write",
        "tool_input": {"file_path": str(tmp_path / "x.txt"), "content": "x"},
    }
    env = _env_with(tmp_path)
    for i in range(5):
        out = _run(_PRE_TOOL, payload, env)
        assert _decision(out) == "deny", f"strike {i+1} should deny"

    audit = _read_audit(tmp_path)
    assert "spec-approval-block-escalation-needed" in audit


def test_strict_no_fail_open_after_escalation(tmp_path):
    """Escalation audit yazıldıktan sonra 6. tetik HÂLÂ deny — fail-open YOK."""
    _write_state(tmp_path, spec_approved=False)
    payload = {
        "cwd": str(tmp_path), "tool_name": "Write",
        "tool_input": {"file_path": str(tmp_path / "x.txt"), "content": "x"},
    }
    env = _env_with(tmp_path)
    for _ in range(6):
        out = _run(_PRE_TOOL, payload, env)
        assert _decision(out) == "deny"


# ---------- State lock ----------


def test_state_lock_bash_set_field_denied(tmp_path):
    """Bash kanalından `state.set_field` → DENY (state lock)."""
    _write_state(tmp_path, spec_approved=True)
    out = _run(_PRE_TOOL, {
        "cwd": str(tmp_path), "tool_name": "Bash",
        "tool_input": {"command": "python3 -c \"from hooks.lib import state; state.set_field('current_phase', 22)\""},
    }, _env_with(tmp_path))
    assert _decision(out) == "deny"
    reason = json.loads(out)["hookSpecificOutput"].get("permissionDecisionReason", "")
    assert "STATE LOCK" in reason or "state" in reason.lower()


def test_state_lock_bash_update_denied(tmp_path):
    _write_state(tmp_path, spec_approved=True)
    out = _run(_PRE_TOOL, {
        "cwd": str(tmp_path), "tool_name": "Bash",
        "tool_input": {"command": "python -c 'state.update({\"current_phase\": 22})'"},
    }, _env_with(tmp_path))
    assert _decision(out) == "deny"


# ---------- Phase transition emit denylist ----------


def test_phase_transition_bash_denied(tmp_path):
    """Bash kanalından `phase_transition N M` → DENY."""
    _write_state(tmp_path, spec_approved=True)
    out = _run(_PRE_TOOL, {
        "cwd": str(tmp_path), "tool_name": "Bash",
        "tool_input": {"command": "echo phase_transition 1 22"},
    }, _env_with(tmp_path))
    assert _decision(out) == "deny"


# ---------- Universal completeness loop ----------


def test_completeness_loop_advances_through_audit_chain(tmp_path):
    """state=1 + 1, 2, 3 audit'leri → universal loop 4'e advance."""
    _write_state(tmp_path, current_phase=1)
    audit_log = tmp_path / ".mycl" / "audit.log"
    audit_log.parent.mkdir(parents=True, exist_ok=True)
    audit_log.write_text(
        "2026-05-09T20:00:00Z | asama-1-complete | seed | -\n"
        "2026-05-09T20:00:01Z | asama-2-complete | seed | -\n"
        "2026-05-09T20:00:02Z | asama-3-complete | seed | -\n",
        encoding="utf-8",
    )

    _run(_STOP, {"cwd": str(tmp_path), "transcript_path": ""},
                 _env_with(tmp_path))
    assert _read_state(tmp_path)["current_phase"] == 4


def test_completeness_loop_stops_at_missing_audit(tmp_path):
    """state=1 + 1, 3 audit'leri (2 eksik) → loop 2'de durur."""
    _write_state(tmp_path, current_phase=1)
    audit_log = tmp_path / ".mycl" / "audit.log"
    audit_log.parent.mkdir(parents=True, exist_ok=True)
    audit_log.write_text(
        "2026-05-09T20:00:00Z | asama-1-complete | seed | -\n"
        "2026-05-09T20:00:01Z | asama-3-complete | seed | -\n",
        encoding="utf-8",
    )

    _run(_STOP, {"cwd": str(tmp_path), "transcript_path": ""},
                 _env_with(tmp_path))
    assert _read_state(tmp_path)["current_phase"] == 2


# ---------- Activate DSI integration ----------


def test_activate_dsi_full_chain(tmp_path):
    """activate → DSI: directive + status + git_init_consent (Aşama 2).

    Aşama 1 POC orchestration aktif olduğu için active_phase_directive
    devre dışı (çakışan yönlendirme önlemi). Tam DSI zincirini Aşama
    2'den itibaren bekleriz (orchestration kapalı, eski tek-context).
    """
    _write_state(tmp_path, current_phase=2)
    out = _run(_ACTIVATE, {"cwd": str(tmp_path)}, _env_with(tmp_path))
    payload = json.loads(out)
    ctx = payload["hookSpecificOutput"]["additionalContext"]
    # Directive (Aşama 2)
    assert "<mycl_active_phase_directive>" in ctx
    # Pipeline status
    assert "<mycl_phase_status>" in ctx
    assert "[2⏳]" in ctx
    # Git yok → consent prompt
    assert "<mycl_git_init_consent_request>" in ctx


def test_activate_skips_consent_when_git_exists(tmp_path):
    (tmp_path / ".git").mkdir()
    _write_state(tmp_path, current_phase=1)
    out = _run(_ACTIVATE, {"cwd": str(tmp_path)}, _env_with(tmp_path))
    payload = json.loads(out)
    ctx = payload["hookSpecificOutput"]["additionalContext"]
    assert "<mycl_git_init_consent_request>" not in ctx


# ---------- Production simulation ----------


def test_production_sim_empty_project_phase_1_intent(tmp_path):
    """Boş proje + activate → Aşama 1 POC subagent directive + phase status.

    Aşama 1 orchestration aktif → DSI directive yerine
    mycl_phase_subagent_directive emit edilir; phase_status hâlâ DSI
    bloğunda görünür (bilgi katmanı).
    """
    out = _run(_ACTIVATE, {"cwd": str(tmp_path)}, _env_with(tmp_path))
    payload = json.loads(out)
    ctx = payload["hookSpecificOutput"]["additionalContext"]
    # Subagent directive (Aşama 1 POC) — DSI directive yerine
    assert "<mycl_phase_subagent_directive>" in ctx
    assert "mycl-phase-runner" in ctx
    # Phase status hâlâ görünür
    assert "[1⏳]" in ctx
