"""hooks/pre_compact.py birim testleri.

PreCompact hook — Anthropic resmi event'i; compaction öncesi tetiklenir.
MyCL state + son audit + spec MUST'larını `.mycl/wip_snapshot.json`'a
serileştirir; hookSpecificOutput.additionalContext ile bilingual
reminder döndürür (drift counter-measure).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


_HOOK_PATH = Path(__file__).resolve().parent.parent / "hooks" / "pre_compact.py"


def _run_hook(payload: dict, env: dict | None = None) -> tuple[int, str]:
    result = subprocess.run(
        [sys.executable, str(_HOOK_PATH)],
        input=json.dumps(payload).encode("utf-8"),
        capture_output=True,
        timeout=10,
        env=env,
    )
    return result.returncode, result.stdout.decode().strip()


def _env_with(project_dir: Path) -> dict:
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(project_dir)
    return env


def _seed_state(project_dir: Path, **fields) -> None:
    mycl_dir = project_dir / ".mycl"
    mycl_dir.mkdir(parents=True, exist_ok=True)
    base = {
        "schema_version": 1,
        "current_phase": 1,
        "spec_approved": False,
        "spec_hash": None,
        "spec_must_list": [],
        "last_phase_output": "none",
    }
    base.update(fields)
    (mycl_dir / "state.json").write_text(json.dumps(base), encoding="utf-8")


def _seed_audit(project_dir: Path, *events: str) -> None:
    mycl_dir = project_dir / ".mycl"
    mycl_dir.mkdir(parents=True, exist_ok=True)
    with (mycl_dir / "audit.log").open("a", encoding="utf-8") as f:
        for name in events:
            f.write(f"2026-05-11T10:00:00Z | {name} | seed | -\n")


# ---------- happy path ----------


def test_hook_emits_precompact_reminder(tmp_path):
    """state + audit varsa snapshot yazılır, additionalContext bilingual."""
    _seed_state(tmp_path, current_phase=4, spec_approved=True)
    _seed_audit(tmp_path, "session_start", "asama-1-complete")

    rc, out = _run_hook(
        {"cwd": str(tmp_path), "matcher": "manual"},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    payload = json.loads(out)
    spec = payload["hookSpecificOutput"]
    assert spec["hookEventName"] == "PreCompact"
    ctx = spec["additionalContext"]
    assert "<mycl_precompact_reminder>" in ctx
    # Bilingual: hem TR hem EN
    assert "Aktif aşama: 4/22" in ctx
    assert "Active phase: 4/22" in ctx
    assert "Spec onaylı: evet" in ctx
    assert "Spec approved: yes" in ctx


def test_snapshot_file_written(tmp_path):
    """wip_snapshot.json doğru içerikle yazılır."""
    _seed_state(
        tmp_path,
        current_phase=9,
        spec_approved=True,
        spec_must_list=[{"id": "MUST_1", "text": "foo"}],
    )
    _seed_audit(tmp_path, "session_start", "spec-hash-stored")

    _run_hook({"cwd": str(tmp_path), "matcher": "auto"}, env=_env_with(tmp_path))

    snapshot_path = tmp_path / ".mycl" / "wip_snapshot.json"
    assert snapshot_path.exists()
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    assert snapshot["current_phase"] == 9
    assert snapshot["spec_approved"] is True
    assert snapshot["compact_matcher"] == "auto"
    assert len(snapshot["spec_must_list"]) == 1
    assert snapshot["spec_must_list"][0]["id"] == "MUST_1"
    # son audit'ler dahil
    audit_names = [ev["name"] for ev in snapshot["recent_audit"]]
    assert "session_start" in audit_names
    assert "spec-hash-stored" in audit_names


def test_audit_log_records_snapshot(tmp_path):
    """precompact-snapshot audit kaydı yazılır."""
    _seed_state(tmp_path, current_phase=2)
    _run_hook({"cwd": str(tmp_path), "matcher": "manual"}, env=_env_with(tmp_path))

    audit_text = (tmp_path / ".mycl" / "audit.log").read_text(encoding="utf-8")
    assert "precompact-snapshot" in audit_text
    assert "matcher=manual" in audit_text
    assert "phase=2" in audit_text


# ---------- matcher kaynakları ----------


def test_matcher_defaults_to_auto_when_missing(tmp_path):
    _seed_state(tmp_path)
    _run_hook({"cwd": str(tmp_path)}, env=_env_with(tmp_path))
    snapshot = json.loads(
        (tmp_path / ".mycl" / "wip_snapshot.json").read_text(encoding="utf-8")
    )
    assert snapshot["compact_matcher"] == "auto"


def test_matcher_accepts_compact_reason_alias(tmp_path):
    """`compact_reason` alanı `matcher` yoksa fallback olarak kullanılır."""
    _seed_state(tmp_path)
    _run_hook(
        {"cwd": str(tmp_path), "compact_reason": "manual"},
        env=_env_with(tmp_path),
    )
    snapshot = json.loads(
        (tmp_path / ".mycl" / "wip_snapshot.json").read_text(encoding="utf-8")
    )
    assert snapshot["compact_matcher"] == "manual"


# ---------- self-project guard ----------


def test_self_project_skips(tmp_path):
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(tmp_path)
    env["MYCL_REPO_PATH"] = str(tmp_path)
    result = subprocess.run(
        [sys.executable, str(_HOOK_PATH)],
        input=json.dumps({"cwd": str(tmp_path)}).encode("utf-8"),
        capture_output=True,
        timeout=10,
        env=env,
    )
    assert result.returncode == 0
    assert result.stdout.decode().strip() == ""
    # snapshot yazılmamış
    assert not (tmp_path / ".mycl" / "wip_snapshot.json").exists()


# ---------- malformed input ----------


def test_hook_handles_empty_input(tmp_path):
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(tmp_path)
    result = subprocess.run(
        [sys.executable, str(_HOOK_PATH)],
        input=b"",
        capture_output=True,
        timeout=10,
        env=env,
    )
    assert result.returncode == 0


def test_hook_handles_invalid_json(tmp_path):
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(tmp_path)
    result = subprocess.run(
        [sys.executable, str(_HOOK_PATH)],
        input=b"{invalid json",
        capture_output=True,
        timeout=10,
        env=env,
    )
    assert result.returncode == 0
