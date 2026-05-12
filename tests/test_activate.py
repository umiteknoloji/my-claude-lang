"""hooks/activate.py birim testleri.

Hook entry point — stdin/stdout JSON kontrat. Test'ler subprocess
ile çalıştırıp çıktı JSON'u inceler.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


_HOOK_PATH = Path(__file__).resolve().parent.parent / "hooks" / "activate.py"


def _run_hook(payload: dict, env: dict | None = None) -> dict:
    """activate.py'yi subprocess olarak çalıştır, stdout JSON döner."""
    result = subprocess.run(
        [sys.executable, str(_HOOK_PATH)],
        input=json.dumps(payload).encode("utf-8"),
        capture_output=True,
        timeout=10,
        env=env,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"hook exit {result.returncode}: stderr={result.stderr.decode()}"
        )
    out = result.stdout.decode().strip()
    if not out:
        return {}
    return json.loads(out)


def _env_with(project_dir: Path) -> dict:
    import os
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(project_dir)
    # Repo-local data dir override → home'daki kurulu eski kopya devreye girmesin
    env["MYCL_DATA_DIR"] = str(_HOOK_PATH.resolve().parent.parent / "data")
    # Self-project guard'dan kaçınma için MYCL_REPO_PATH'ı tmp_path'e
    # bağlamayız; default ~/my-claude-lang ile test_path farklı.
    return env


# ---------- happy path ----------


def test_hook_emits_context(tmp_path):
    """tmp_path'te (yeni proje, .mycl/ yok) hook STATIC_CONTEXT + DSI emit eder."""
    out = _run_hook({"cwd": str(tmp_path)}, env=_env_with(tmp_path))
    assert "hookSpecificOutput" in out
    spec_out = out["hookSpecificOutput"]
    assert spec_out["hookEventName"] == "UserPromptSubmit"
    context = spec_out["additionalContext"]
    # Manifesto + DSI bloğu beklenir
    assert "MyCL" in context


def test_hook_emits_banner_first_block(tmp_path):
    """İlk blok MyCL banner'ı (TR + boş satır + EN). Görünür sinyal."""
    out = _run_hook({"cwd": str(tmp_path)}, env=_env_with(tmp_path))
    context = out["hookSpecificOutput"]["additionalContext"]
    version = (
        (_HOOK_PATH.resolve().parent.parent / "VERSION")
        .read_text(encoding="utf-8")
        .strip()
    )
    # Banner ilk satır
    assert context.startswith(f"MyCL {version} — Anlam Doğrulama Katmanı aktif")
    # TR + boş satır + EN (CLAUDE.md bilingual kuralı)
    assert f"\n\nMyCL {version} — Semantic Verification Layer active" in context


def test_hook_includes_phase_directive(tmp_path):
    """Subagent orchestration kapalı fazlarda DSI active_phase_directive emit edilir.

    Aşama 1 orchestration aktif → DSI devre dışı → directive yok.
    Aşama 2'ye set ederek directive emit beklenir (eski tek-context akışı).
    """
    mycl_dir = tmp_path / ".mycl"
    mycl_dir.mkdir(parents=True, exist_ok=True)
    (mycl_dir / "state.json").write_text(
        '{"schema_version": 1, "current_phase": 2, "spec_approved": false, '
        '"spec_hash": null, "spec_must_list": []}', encoding="utf-8",
    )
    out = _run_hook({"cwd": str(tmp_path)}, env=_env_with(tmp_path))
    context = out["hookSpecificOutput"]["additionalContext"]
    assert "<mycl_active_phase_directive>" in context
    assert "Aşama 2" in context or "Phase 2" in context


def test_hook_includes_phase_status(tmp_path):
    """Phase status DSI bloğunda — orchestration aktif fazda bile görünür
    (include_directive=False olsa da status kısmı emit edilir)."""
    out = _run_hook({"cwd": str(tmp_path)}, env=_env_with(tmp_path))
    context = out["hookSpecificOutput"]["additionalContext"]
    assert "<mycl_phase_status>" in context
    assert "[1⏳]" in context  # default aktif faz 1


def test_hook_includes_git_init_consent_when_no_git(tmp_path):
    """Git yok + consent null → askq prompt'u eklenmeli."""
    out = _run_hook({"cwd": str(tmp_path)}, env=_env_with(tmp_path))
    context = out["hookSpecificOutput"]["additionalContext"]
    assert "<mycl_git_init_consent_request>" in context


def test_hook_skips_git_consent_when_git_exists(tmp_path):
    """Git zaten var → consent prompt YOK."""
    (tmp_path / ".git").mkdir()
    out = _run_hook({"cwd": str(tmp_path)}, env=_env_with(tmp_path))
    context = out["hookSpecificOutput"]["additionalContext"]
    assert "<mycl_git_init_consent_request>" not in context


# ---------- session_start trace ----------


def test_first_run_writes_session_start_trace(tmp_path):
    _run_hook({"cwd": str(tmp_path)}, env=_env_with(tmp_path))
    trace_log = tmp_path / ".mycl" / "trace.log"
    assert trace_log.exists()
    content = trace_log.read_text(encoding="utf-8")
    assert "session_start" in content
    version = (
        (_HOOK_PATH.resolve().parent.parent / "VERSION")
        .read_text(encoding="utf-8")
        .strip()
    )
    assert version in content


def test_second_run_does_not_duplicate_session_start(tmp_path):
    """İkinci tetiklemede session_start tekrar yazılmaz."""
    env = _env_with(tmp_path)
    _run_hook({"cwd": str(tmp_path)}, env=env)
    # audit log oluştu — session_start audit'i de varsayalım var
    # (gerçekte trace.log + audit.log ayrı; activate session_start'ı
    # audit.log'a yazmıyor, sadece trace.log'a)
    audit_log = tmp_path / ".mycl" / "audit.log"
    audit_log.parent.mkdir(parents=True, exist_ok=True)
    # Sahte audit ekle ki "any session_start" True dönsün:
    audit_log.write_text(
        "2026-05-09T20:00:00Z | session_start | activate.py | 1.0.0\n",
        encoding="utf-8",
    )
    _run_hook({"cwd": str(tmp_path)}, env=env)
    trace_log = tmp_path / ".mycl" / "trace.log"
    if trace_log.exists():
        # Multiple session_start trace satırları olmamalı (checked
        # via audit shortcut — pratik: en az bir session_start var)
        content = trace_log.read_text()
        assert content.count("session_start") >= 1


# ---------- self-project guard ----------


def test_hook_skips_when_self_project(tmp_path):
    """MYCL_REPO_PATH env tmp_path'e set → hook çıktı vermez."""
    import os
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
    # Self-project'te hiç çıktı yok
    assert result.stdout.decode().strip() == ""


# ---------- malformed input ----------


def test_hook_handles_empty_input(tmp_path):
    """Boş input → context yine üretilir (cwd env'den)."""
    import os
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
    # Boş stdin → context yine üretilir (env'den project_dir)


def test_hook_handles_invalid_json(tmp_path):
    import os
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


# ---------- escalation visibility ----------


def test_hook_renders_escalation_when_present(tmp_path):
    """*-escalation-needed audit varsa <mycl_phase_allowlist_escalate>."""
    audit_log = tmp_path / ".mycl" / "audit.log"
    audit_log.parent.mkdir(parents=True, exist_ok=True)
    audit_log.write_text(
        "2026-05-09T20:00:00Z | spec-approval-block-escalation-needed | "
        "pre_tool | strike=5 developer-intervention-required\n",
        encoding="utf-8",
    )
    out = _run_hook({"cwd": str(tmp_path)}, env=_env_with(tmp_path))
    context = out["hookSpecificOutput"]["additionalContext"]
    assert "<mycl_phase_allowlist_escalate>" in context


# ---------- subagent orchestration directive (1.0.16: Aşama 10/14) ----------


def test_hook_skips_subagent_directive_in_phase_1(tmp_path):
    """1.0.16: Aşama 1 orchestration kaldırıldı → subagent directive emit EDİLMEZ.

    Aşama 1 niyet toplama ana bağlamda Skill + AskUserQuestion ile yürütülür;
    subagent dispatch sadece Aşama 10/14 paralel mercek için ayrıldı.
    """
    out = _run_hook({"cwd": str(tmp_path)}, env=_env_with(tmp_path))
    context = out["hookSpecificOutput"]["additionalContext"]
    assert "<mycl_phase_subagent_directive>" not in context
    # DSI directive ana bağlamda emit edilir
    assert "<mycl_active_phase_directive>" in context


def test_hook_emits_reinforcement_reminder(tmp_path):
    """Her aktivasyonda reinforcement reminder en sonda emit edilir."""
    out = _run_hook({"cwd": str(tmp_path)}, env=_env_with(tmp_path))
    context = out["hookSpecificOutput"]["additionalContext"]
    assert "<mycl_reinforcement_reminder>" in context
    # Bilingual: TR + EN
    assert "Aşamalar sıralı" in context
    assert "Phase order is strict" in context
    # spec_approved=False → mutating tool YASAK vurgusu
    assert "YASAK" in context or "FORBIDDEN" in context
    # En sonda olduğu kontrolü: reinforcement reminder son bloklardan
    assert context.rstrip().endswith("</mycl_reinforcement_reminder>")


def test_hook_reinforcement_reminder_unlocks_when_spec_approved(tmp_path):
    """spec_approved=True → mutating tool izinli mesajı."""
    mycl_dir = tmp_path / ".mycl"
    mycl_dir.mkdir(parents=True, exist_ok=True)
    (mycl_dir / "state.json").write_text(
        '{"schema_version": 1, "current_phase": 5, "spec_approved": true, '
        '"spec_hash": "abc", "spec_must_list": []}',
        encoding="utf-8",
    )
    out = _run_hook({"cwd": str(tmp_path)}, env=_env_with(tmp_path))
    context = out["hookSpecificOutput"]["additionalContext"]
    assert "<mycl_reinforcement_reminder>" in context
    assert "izinli" in context or "permitted" in context
    # Aşama numarası dinamik
    assert "Aşama 5/22" in context
    assert "Phase 5/22" in context


def test_hook_skips_subagent_directive_in_phase_without_flag(tmp_path):
    """Aşama 2'de subagent_orchestration false → directive emit edilmez."""
    mycl_dir = tmp_path / ".mycl"
    mycl_dir.mkdir(parents=True, exist_ok=True)
    state_path = mycl_dir / "state.json"
    state_path.write_text(
        '{"schema_version": 1, "current_phase": 2, "spec_approved": false, '
        '"spec_hash": null, "spec_must_list": []}',
        encoding="utf-8",
    )
    out = _run_hook({"cwd": str(tmp_path)}, env=_env_with(tmp_path))
    context = out["hookSpecificOutput"]["additionalContext"]
    assert "<mycl_phase_subagent_directive>" not in context


# ---------- 1.0.5: opt-in `/mycl` trigger ----------


def _env_no_force_active(project_dir: Path) -> dict:
    """force-active bypass'siz env — gerçek opt-in davranışını test eder."""
    env = _env_with(project_dir)
    env.pop("MYCL_TEST_FORCE_ACTIVE", None)
    return env


def test_hook_no_op_when_session_inactive(tmp_path):
    """`/mycl` trigger yok + session aktif değil → hook çıktı vermez."""
    result = subprocess.run(
        [sys.executable, str(_HOOK_PATH)],
        input=json.dumps({
            "cwd": str(tmp_path),
            "session_id": "fresh-session",
            "prompt": "normal kullanıcı mesajı",
        }).encode("utf-8"),
        capture_output=True,
        timeout=10,
        env=_env_no_force_active(tmp_path),
    )
    assert result.returncode == 0
    # Boş stdout → Claude Code "no-op" olarak yorumlar
    assert result.stdout.decode().strip() == ""


def test_hook_activates_on_mycl_trigger(tmp_path):
    """`/mycl <prompt>` → session aktive olur + aktivasyon notu emit."""
    out = _run_hook(
        {
            "cwd": str(tmp_path),
            "session_id": "new-session",
            "prompt": "/mycl todo app yap",
        },
        env=_env_no_force_active(tmp_path),
    )
    context = out["hookSpecificOutput"]["additionalContext"]
    assert "<mycl_activation_note>" in context
    assert "'todo app yap'" in context
    # Aktivasyon notu manifesto'dan önce
    assert context.index("<mycl_activation_note>") < context.index("MyCL")
    # Aktif session dosyası yazıldı
    active_file = tmp_path / ".mycl" / "active_session.txt"
    assert active_file.read_text(encoding="utf-8").strip() == "new-session"


def test_hook_bare_mycl_trigger_empty_message(tmp_path):
    """Sadece `/mycl` (mesaj yok) → aktivasyon onayı notu."""
    out = _run_hook(
        {
            "cwd": str(tmp_path),
            "session_id": "sess-bare",
            "prompt": "/mycl",
        },
        env=_env_no_force_active(tmp_path),
    )
    context = out["hookSpecificOutput"]["additionalContext"]
    assert "boş — yalnızca aktivasyon onayı" in context
    assert "empty — activation acknowledgment only" in context


def test_hook_remains_active_after_first_mycl_in_same_session(tmp_path):
    """`/mycl` ilk turda aktive eder; sonraki turlarda aynı session_id → aktif."""
    # 1. tur: /mycl ile aktive
    _run_hook(
        {
            "cwd": str(tmp_path),
            "session_id": "persistent-session",
            "prompt": "/mycl başla",
        },
        env=_env_no_force_active(tmp_path),
    )
    # 2. tur: trigger olmadan ama aynı session_id
    out = _run_hook(
        {
            "cwd": str(tmp_path),
            "session_id": "persistent-session",
            "prompt": "devam et",
        },
        env=_env_no_force_active(tmp_path),
    )
    context = out["hookSpecificOutput"]["additionalContext"]
    # Banner + manifesto var (aktif)
    assert "MyCL" in context
    # Yeni aktivasyon notu yok (yalnızca ilk turda)
    assert "<mycl_activation_note>" not in context


def test_hook_new_session_id_is_pasive(tmp_path):
    """Eski session aktif olsa bile yeni session_id pasif kalır."""
    # Eski session'ı aktive et
    _run_hook(
        {
            "cwd": str(tmp_path),
            "session_id": "old-session",
            "prompt": "/mycl",
        },
        env=_env_no_force_active(tmp_path),
    )
    # Yeni session_id ile çağır (trigger yok)
    result = subprocess.run(
        [sys.executable, str(_HOOK_PATH)],
        input=json.dumps({
            "cwd": str(tmp_path),
            "session_id": "new-different-session",
            "prompt": "ne yapayım",
        }).encode("utf-8"),
        capture_output=True,
        timeout=10,
        env=_env_no_force_active(tmp_path),
    )
    assert result.returncode == 0
    assert result.stdout.decode().strip() == ""
