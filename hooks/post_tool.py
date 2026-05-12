#!/usr/bin/env python3
"""post_tool — PostToolUse hook.

Pseudocode §2 PostToolUse:
    - Tool çıktısını gözle, state'i reaktif güncelle.
    - last_write_ts (Write/Edit/MultiEdit başarılı → şimdiki zaman)
    - ui_flow_active (Aşama 6'da UI dosyası yazıldı → True)
    - regression_block_active (test runner Bash GREEN → False'a düş)
    - AskUserQuestion kullanıcı yanıtı geldi → stop.py manuel tetikle
      (v13.1.1 Bug 2 öğrenimi: Claude Code Stop event askq zincirinde
      tetiklenmez; post_tool subprocess ile yokluğu kapatır)

Self-project guard: aynı recursive friction önleme (activate.py +
pre_tool.py simetrik).

API: stdin'den Claude Code JSON (tool_name + tool_input + tool_response),
stdout'a (varsa) hookSpecificOutput. State/audit yan etkileri.

Yan etki yok ise stdout boş — Claude Code "no-op" olarak kabul eder.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from hooks.lib import activation, audit, plugin, state  # noqa: E402

_WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}

# UI dosyası tespiti (Aşama 6 ui_flow_active için)
_UI_PATH_PATTERNS = [
    re.compile(r"\.(?:tsx|jsx|vue|svelte)$"),
    re.compile(r"(?:^|/)src/(?:components|pages|app|views|features|ui)/"),
    re.compile(r"(?:^|/)(?:components|pages|app|views|ui)/"),
]

# Test runner tespiti (regression_block_active clear)
_TEST_RUNNER_RE = re.compile(
    r"\b(?:"
    r"npm\s+(?:run\s+)?test|"
    r"yarn\s+test|"
    r"pnpm\s+(?:run\s+)?test|"
    r"bun\s+test|"
    r"pytest|python3?\s+-m\s+pytest|"
    r"jest|vitest|mocha|tap|"
    r"go\s+test|"
    r"cargo\s+test|"
    r"rspec|"
    r"phpunit"
    r")\b"
)


def _is_self_project(project_dir: str) -> bool:
    repo_path = os.environ.get("MYCL_REPO_PATH") or str(Path.home() / "my-claude-lang")
    try:
        cwd = Path(project_dir).resolve()
        myc = Path(repo_path).resolve()
    except OSError:
        return False
    return cwd == myc


def _read_input() -> dict:
    try:
        raw = sys.stdin.read()
    except (OSError, ValueError):
        return {}
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def _is_ui_path(path: str) -> bool:
    if not path:
        return False
    return any(p.search(path) for p in _UI_PATH_PATTERNS)


def _tool_succeeded(tool_response) -> bool:
    """tool_response'tan başarı çıkar.

    Claude Code tool_response formatı tool'a göre değişir:
      - Write/Edit: dict, hata yoksa OK
      - Bash: dict {stdout, stderr, exit_code}
    Yokluğu = başarılı varsayımı (Claude Code response'u her zaman
    döndürmez post-hook'ta).
    """
    if tool_response is None:
        return True
    if isinstance(tool_response, dict):
        # Bash exit_code
        if "exit_code" in tool_response:
            try:
                return int(tool_response["exit_code"]) == 0
            except (TypeError, ValueError):
                return False
        # Genel error key kontrolleri
        if tool_response.get("error") or tool_response.get("is_error"):
            return False
    return True


def _update_last_write_ts(tool_name: str, success: bool, project_dir: str) -> None:
    """Write/Edit/MultiEdit başarılı → last_write_ts şimdiki zaman."""
    if tool_name not in _WRITE_TOOLS or not success:
        return
    import time
    state.set_field("last_write_ts", int(time.time()), project_root=project_dir)


def _update_ui_flow_active(
    tool_name: str,
    tool_input: dict,
    success: bool,
    project_dir: str,
) -> None:
    """Aşama 6'da UI dosyası yazılırsa ui_flow_active=True."""
    if tool_name not in _WRITE_TOOLS or not success:
        return
    current_phase = state.get("current_phase", 1, project_root=project_dir)
    if current_phase != 6:
        return
    file_path = tool_input.get("file_path") or tool_input.get("path") or ""
    if _is_ui_path(file_path):
        state.set_field("ui_flow_active", True, project_root=project_dir)


def _maybe_clear_regression_block(
    tool_name: str,
    tool_input: dict,
    success: bool,
    project_dir: str,
) -> None:
    """Test runner Bash sonucuna göre regression_block_active set/clear.

    1.0.24: GREEN clear + FAIL set ikisi de var.
      - Bash test runner + success=True → regression_block_active=False
        + `regression-clear` audit
      - Bash test runner + success=False → regression_block_active=True
        + `regression-fail` audit (Aşama 9 TDD red aşaması veya genel
        test fail tespiti)
    """
    if tool_name != "Bash":
        return
    cmd = str(tool_input.get("command", ""))
    if not _TEST_RUNNER_RE.search(cmd):
        return
    if success:
        if state.get(
            "regression_block_active", False, project_root=project_dir
        ):
            state.update(
                {"regression_block_active": False, "regression_output": ""},
                project_root=project_dir,
            )
            audit.log_event(
                "regression-clear", "post_tool.py",
                f"runner={cmd[:60]}", project_root=project_dir,
            )
    else:
        # 1.0.24: FAIL durumunda regression block aktif et
        if not state.get(
            "regression_block_active", False, project_root=project_dir
        ):
            state.set_field(
                "regression_block_active", True,
                project_root=project_dir,
            )
            audit.log_event(
                "regression-fail", "post_tool.py",
                f"runner={cmd[:60]}", project_root=project_dir,
            )


def _maybe_record_tdd_write(
    tool_name: str,
    tool_input: dict,
    success: bool,
    project_dir: str,
) -> None:
    """1.0.24: Aşama 9 TDD compliance score için Write/Edit kayıt.

    Pseudocode: "test yolu → audit: tdd-test-write" + "üretim yolu →
    audit: tdd-prod-write" + "test'in üretim kodundan önce yazılma
    oranını state.tdd_compliance_score'a yazar."

    Implementation gap (1.0.23 öncesi): tdd.py modülü mevcut + testleri
    var, ama post_tool.py'den hiç çağrılmıyordu — "declared but not
    implemented" pattern (Aşama 5 pattern_summary, Aşama 7 ui_reviewed
    ile aynı).

    Kapsam: sadece cp==9 (Aşama 9 TDD) — diğer fazlardaki Write'lar
    skor saymıyor (orta risk: TDD compliance Aşama 9 davranışına özel).
    """
    if tool_name not in _WRITE_TOOLS or not success:
        return
    cp = state.get("current_phase", 1, project_root=project_dir)
    if cp != 9:
        return
    from hooks.lib import tdd
    file_path = (
        tool_input.get("file_path")
        or tool_input.get("path")
        or ""
    )
    tdd.record_write(file_path, project_root=project_dir)
    tdd.update_compliance_score(project_root=project_dir)


_GIT_INIT_CMD_RE = re.compile(r"^\s*git\s+init\b")


def _maybe_set_git_init_consent(
    tool_name: str, tool_input: dict, success: bool, project_dir: str,
) -> None:
    """`git init` Bash başarılı çalıştırılırsa Plugin Kural A consent'i
    `approved` olarak işaretle.

    1.0.10 öncesi `plugin.set_git_init_consent` hiçbir hook'tan
    çağrılmıyordu → consent hep None kalıyor, activate.py her
    UserPromptSubmit'te consent prompt'u tekrar emit ediyordu. Bu
    helper boşluğu kapatır: bir kez `git init` başarıyla çalışınca
    consent kalıcı `approved` olur, prompt bir daha gösterilmez.
    """
    if tool_name != "Bash" or not success:
        return
    cmd = str(tool_input.get("command", ""))
    if not _GIT_INIT_CMD_RE.match(cmd):
        return
    if plugin.git_init_consent(project_root=project_dir) == "approved":
        return
    plugin.set_git_init_consent("approved", project_root=project_dir)
    audit.log_event(
        "git-init-consent-recorded", "post_tool.py",
        "Plugin Kural A — bash git init success → consent=approved",
        project_root=project_dir,
    )


def _trigger_stop_after_askq(
    tool_name: str, payload: dict, project_dir: str,
) -> None:
    """AskUserQuestion sonrası stop.py'yi manuel tetikle.

    v13.1.1 Bug 2: Claude Code Stop event askq zincirinde tetiklenmediği
    için askq onayı pipeline'ı ilerletmiyor. post_tool burada
    subprocess.run ile stop.py'yi çağırarak boşluğu kapatır.

    Side-effect (state, audit) parent'a geçer; subprocess çıktısı
    yutulur (stop.py kendi JSON output'unu Claude Code'a verecek
    yer yok — bu durum bilinen mimari kısıt). 1.0.0'da: stop.py iç
    state mutasyonu (audit, gate.advance) işin asıl değerini taşır.
    """
    if tool_name != "AskUserQuestion":
        return
    stop_path = _REPO_ROOT / "hooks" / "stop.py"
    if not stop_path.exists():
        # Faz 4 boyunca defansif: stop.py henüz yazılmamış olabilir.
        audit.log_event(
            "stop-trigger-skipped", "post_tool.py",
            "stop.py not yet present", project_root=project_dir,
        )
        return
    # Aynı payload'ı stop.py'ye gönder — transcript_path/cwd/tool_response
    # alanları stop.py'nin işine yarayacak.
    try:
        subprocess.run(
            [sys.executable, str(stop_path)],
            input=json.dumps(payload).encode("utf-8"),
            capture_output=True,
            timeout=15,
            env=os.environ.copy(),
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        audit.log_event(
            "stop-trigger-failed", "post_tool.py",
            f"err={type(exc).__name__}", project_root=project_dir,
        )


def main() -> int:
    payload = _read_input()
    project_dir = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

    if _is_self_project(project_dir):
        return 0

    # 1.0.5: opt-in `/mycl` — aktif değilse hook no-op.
    session_id = str(payload.get("session_id", "") or "")
    if not activation.is_session_active(session_id, project_root=project_dir):
        return 0

    tool_name = str(payload.get("tool_name", ""))
    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        tool_input = {}
    tool_response = payload.get("tool_response")

    success = _tool_succeeded(tool_response)

    # Reactive state updates (her biri kendi koşulunu kontrol eder)
    _update_last_write_ts(tool_name, success, project_dir)
    _update_ui_flow_active(tool_name, tool_input, success, project_dir)
    _maybe_clear_regression_block(tool_name, tool_input, success, project_dir)
    _maybe_record_tdd_write(tool_name, tool_input, success, project_dir)
    _maybe_set_git_init_consent(tool_name, tool_input, success, project_dir)

    # AskUserQuestion sonrası stop.py manuel tetikle (Bug 2)
    _trigger_stop_after_askq(tool_name, payload, project_dir)

    # PostToolUse genelde sessiz — Claude Code "no-op" kabul eder
    return 0


if __name__ == "__main__":
    sys.exit(main())
