"""hooks/post_tool.py birim testleri.

PostToolUse hook — sessiz (genelde stdout boş). State/audit yan
etkileri test edilir: last_write_ts, ui_flow_active, regression-clear,
AskUserQuestion sonrası stop.py manuel trigger.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path


_HOOK_PATH = Path(__file__).resolve().parent.parent / "hooks" / "post_tool.py"


def _run_hook(payload: dict, env: dict | None = None) -> int:
    result = subprocess.run(
        [sys.executable, str(_HOOK_PATH)],
        input=json.dumps(payload).encode("utf-8"),
        capture_output=True,
        timeout=15,
        env=env,
    )
    return result.returncode


def _env_with(project_dir: Path) -> dict:
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(project_dir)
    return env


def _write_state(project_dir: Path, **fields) -> None:
    mycl_dir = project_dir / ".mycl"
    mycl_dir.mkdir(parents=True, exist_ok=True)
    state_path = mycl_dir / "state.json"
    base = {
        "schema_version": 1,
        "current_phase": 1,
        "spec_approved": False,
        "spec_hash": None,
        "spec_must_list": [],
        "ui_flow_active": False,
        "regression_block_active": False,
        "regression_output": "",
        "last_write_ts": None,
    }
    base.update(fields)
    state_path.write_text(json.dumps(base), encoding="utf-8")


def _read_state(project_dir: Path) -> dict:
    return json.loads((project_dir / ".mycl" / "state.json").read_text())


def _read_audit(project_dir: Path) -> str:
    audit_log = project_dir / ".mycl" / "audit.log"
    if not audit_log.exists():
        return ""
    return audit_log.read_text(encoding="utf-8")


# ---------- self-project guard ----------


def test_self_project_skips(tmp_path):
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(tmp_path)
    env["MYCL_REPO_PATH"] = str(tmp_path)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Write",
         "tool_input": {"file_path": str(tmp_path / "x.txt")}},
        env=env,
    )
    assert rc == 0
    # State dosyası bile oluşmamalı (self-project guard early return)
    assert not (tmp_path / ".mycl" / "state.json").exists()


# ---------- last_write_ts ----------


def test_write_success_updates_last_write_ts(tmp_path):
    _write_state(tmp_path)
    before = int(time.time())
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Write",
         "tool_input": {"file_path": str(tmp_path / "x.txt"), "content": "x"},
         "tool_response": {}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    s = _read_state(tmp_path)
    assert s["last_write_ts"] is not None
    assert s["last_write_ts"] >= before


def test_edit_success_updates_last_write_ts(tmp_path):
    _write_state(tmp_path)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Edit",
         "tool_input": {"file_path": str(tmp_path / "x.txt")},
         "tool_response": {}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["last_write_ts"] is not None


def test_failed_write_does_not_update_ts(tmp_path):
    """tool_response.is_error → last_write_ts güncellenmez."""
    _write_state(tmp_path)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Write",
         "tool_input": {"file_path": str(tmp_path / "x.txt")},
         "tool_response": {"is_error": True, "error": "permission denied"}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["last_write_ts"] is None


def test_read_does_not_update_ts(tmp_path):
    _write_state(tmp_path)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Read",
         "tool_input": {"file_path": "/foo"}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["last_write_ts"] is None


# ---------- ui_flow_active ----------


def test_phase_6_ui_write_activates_ui_flow(tmp_path):
    _write_state(tmp_path, current_phase=6)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Write",
         "tool_input": {"file_path": "src/components/Button.tsx", "content": "x"},
         "tool_response": {}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["ui_flow_active"] is True


def test_phase_6_non_ui_write_does_not_activate(tmp_path):
    """Aşama 6'da non-UI dosyası (örn. config.json) → ui_flow_active false kalır."""
    _write_state(tmp_path, current_phase=6, ui_flow_active=False)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Write",
         "tool_input": {"file_path": "config.json", "content": "{}"},
         "tool_response": {}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["ui_flow_active"] is False


def test_phase_5_ui_write_does_not_activate(tmp_path):
    """Faz dışında (Aşama 5) UI dosyası yazımı ui_flow_active'i değiştirmez."""
    _write_state(tmp_path, current_phase=5)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Write",
         "tool_input": {"file_path": "src/components/Button.tsx"},
         "tool_response": {}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["ui_flow_active"] is False


def test_phase_6_jsx_path_activates(tmp_path):
    _write_state(tmp_path, current_phase=6)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Write",
         "tool_input": {"file_path": "src/pages/Home.jsx"},
         "tool_response": {}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["ui_flow_active"] is True


# ---------- regression-clear ----------


def test_test_runner_pass_clears_regression_block(tmp_path):
    _write_state(tmp_path, regression_block_active=True, regression_output="prev fail")
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Bash",
         "tool_input": {"command": "npm test"},
         "tool_response": {"exit_code": 0, "stdout": "all green"}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    s = _read_state(tmp_path)
    assert s["regression_block_active"] is False
    assert s["regression_output"] == ""
    assert "regression-clear" in _read_audit(tmp_path)


def test_pytest_pass_clears_regression(tmp_path):
    _write_state(tmp_path, regression_block_active=True)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Bash",
         "tool_input": {"command": "python3 -m pytest tests/"},
         "tool_response": {"exit_code": 0}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["regression_block_active"] is False


def test_test_runner_fail_does_not_clear(tmp_path):
    _write_state(tmp_path, regression_block_active=True)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Bash",
         "tool_input": {"command": "npm test"},
         "tool_response": {"exit_code": 1, "stderr": "1 failing"}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["regression_block_active"] is True


def test_non_test_bash_does_not_clear(tmp_path):
    """ls / cat / build komutları test runner değil → regression unchanged."""
    _write_state(tmp_path, regression_block_active=True)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Bash",
         "tool_input": {"command": "ls -la"},
         "tool_response": {"exit_code": 0}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["regression_block_active"] is True


def test_test_runner_when_no_block_active_no_op(tmp_path):
    """regression_block_active=False zaten → audit yazılmaz."""
    _write_state(tmp_path, regression_block_active=False)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Bash",
         "tool_input": {"command": "npm test"},
         "tool_response": {"exit_code": 0}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert "regression-clear" not in _read_audit(tmp_path)


# ---------- AskUserQuestion → stop trigger ----------


def test_askq_with_stop_present_invokes_subprocess(tmp_path):
    """stop.py varsa subprocess olarak çağrılır.

    Faz 4.3'te stop.py henüz yazılmadı; bu test stop.py yazılınca
    PASS olacak. Şimdilik fallback path (stop-trigger-skipped) test
    edilir.
    """
    _write_state(tmp_path)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "AskUserQuestion",
         "tool_input": {}, "tool_response": {}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    audit = _read_audit(tmp_path)
    # stop.py henüz yok → skip audit yazılmalı.
    # stop.py yazılınca: bu test güncellenir, çağrının yapıldığı doğrulanır.
    stop_exists = (Path(__file__).resolve().parent.parent / "hooks" / "stop.py").exists()
    if stop_exists:
        # subprocess başarılı olduysa audit'te skip yok
        assert "stop-trigger-skipped" not in audit
    else:
        assert "stop-trigger-skipped" in audit


def test_non_askq_does_not_trigger_stop(tmp_path):
    _write_state(tmp_path)
    rc = _run_hook(
        {"cwd": str(tmp_path), "tool_name": "Read",
         "tool_input": {"file_path": "/foo"}},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    audit = _read_audit(tmp_path)
    assert "stop-trigger" not in audit


# ---------- malformed input ----------


def test_empty_stdin_no_op(tmp_path):
    env = _env_with(tmp_path)
    result = subprocess.run(
        [sys.executable, str(_HOOK_PATH)],
        input=b"",
        capture_output=True,
        timeout=10,
        env=env,
    )
    assert result.returncode == 0


def test_invalid_json_no_op(tmp_path):
    env = _env_with(tmp_path)
    result = subprocess.run(
        [sys.executable, str(_HOOK_PATH)],
        input=b"{invalid",
        capture_output=True,
        timeout=10,
        env=env,
    )
    assert result.returncode == 0
