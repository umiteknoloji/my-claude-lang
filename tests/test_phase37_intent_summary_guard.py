"""test_phase37_intent_summary_guard — Aşama 1 niyet özeti format guard (1.0.37).

Canlı kullanıcı raporu: Aşama 1'de model kullanıcının iki sorusunu
cevapladıktan sonra "Yanıtlar netleşti. Şimdi özet hazırlayıp onay
alıyorum." dedi ama özeti yazmadan doğrudan askq açtı. Skill kontratı
"özet ~3-5 cümle + askq onay" diyor; ihlal.

Çözüm: Aşama 4 spec format guard'ı (1.0.19) pattern'inin aynısı Aşama
1 için. Marker tanımla, line-anchored regex ile yakala, PreToolUse
deny.

İmplementasyon:
- `spec_detect.INTENT_SUMMARY_LINE_RE`: line-anchored regex
  (`🎯 Niyet özeti:` / `Niyet özeti:` / `Intent summary:`, emoji
  opsiyonel, başında whitespace / liste işareti / heading marker OK).
- `spec_detect.contains_intent_summary(text)`: prose-safe detection.
- `pre_tool.py` cp == 1 + AskUserQuestion: marker yoksa DENY +
  `intent-summary-format-missing` audit.
- `bilingual_messages.json::intent_summary_missing_block`: TR + EN.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from hooks.lib import audit, spec_detect, state


_REPO_ROOT = Path(__file__).resolve().parent.parent


def test_contains_intent_summary_finds_emoji_tr_marker():
    """`🎯 Niyet özeti:` satırı line-anchored yakalanır."""
    text = (
        "Niyet netleşti.\n\n"
        "🎯 Niyet özeti: Full-stack TODO uygulaması. React (Vite) "
        "frontend, Node.js/Express.js backend, MySQL veritabanı. "
        "Kullanıcı kayıt ve oturum gerekli; basit CRUD akışı.\n"
    )
    assert spec_detect.contains_intent_summary(text) is True


def test_contains_intent_summary_finds_plain_tr_marker():
    """`Niyet özeti:` (emoji yok) da yakalanır."""
    text = "Niyet özeti: Full-stack TODO uygulaması.\n"
    assert spec_detect.contains_intent_summary(text) is True


def test_contains_intent_summary_finds_en_marker():
    """`Intent summary:` (EN) yakalanır."""
    text = "Intent summary: Build a full-stack TODO app.\n"
    assert spec_detect.contains_intent_summary(text) is True


def test_contains_intent_summary_case_insensitive():
    """Case-insensitive — `intent summary:` ve `niyet özeti:`."""
    assert spec_detect.contains_intent_summary("intent summary: x") is True
    assert spec_detect.contains_intent_summary("NİYET ÖZETİ: x") is True


def test_contains_intent_summary_with_heading_marker():
    """`## 🎯 Niyet özeti:` heading + marker da yakalanır."""
    text = "## 🎯 Niyet özeti: TODO app.\n"
    assert spec_detect.contains_intent_summary(text) is True


def test_contains_intent_summary_with_list_marker():
    """`- 🎯 Niyet özeti:` list item olarak da yakalanır."""
    text = "- 🎯 Niyet özeti: TODO app.\n"
    assert spec_detect.contains_intent_summary(text) is True


def test_contains_intent_summary_prose_embedded_not_caught():
    """Prose içinde gömülü `Niyet özeti:` kelimeleri yakalanmamalı —
    line-anchored regex (CLAUDE.md captured rule)."""
    text = (
        "Aşama 1'de niyet özeti hazırlanır ve onaylanır; bu, sonraki "
        "fazların temelidir. Şimdi soru soruyorum."
    )
    assert spec_detect.contains_intent_summary(text) is False


def test_contains_intent_summary_empty_text():
    """Boş text → False."""
    assert spec_detect.contains_intent_summary("") is False
    assert spec_detect.contains_intent_summary(None) is False  # type: ignore[arg-type]


def test_contains_intent_summary_only_question_no_summary():
    """Model özeti atlamış, sadece "şimdi özet hazırlayıp onay alıyorum"
    diyor — gerçek canlı bug senaryosu (kullanıcı ekran görüntüsü)."""
    text = (
        "Yanıtlar netleşti. Şimdi özet hazırlayıp onay alıyorum.\n"
    )
    assert spec_detect.contains_intent_summary(text) is False


def _run_pre_tool_subprocess(payload: dict, project_dir: Path) -> tuple[int, str, str]:
    """pre_tool.py subprocess; hook'un gerçek davranışını test eder."""
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(project_dir)
    env["MYCL_TEST_FORCE_ACTIVE"] = "1"
    proc = subprocess.run(
        [sys.executable, str(_REPO_ROOT / "hooks" / "pre_tool.py")],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        env=env,
        timeout=10,
    )
    return proc.returncode, proc.stdout, proc.stderr


def _write_transcript(path: Path, last_assistant_text: str) -> None:
    """Test transcript'i: tek bir assistant mesajı içeren JSONL."""
    event = {
        "type": "assistant",
        "message": {
            "role": "assistant",
            "content": [{"type": "text", "text": last_assistant_text}],
        },
    }
    with path.open("w", encoding="utf-8") as f:
        f.write(json.dumps(event) + "\n")


def test_pre_tool_phase_1_askq_denied_without_marker(tmp_path):
    """Aşama 1'de AskUserQuestion çağrısı + marker yok → DENY."""
    state.set_field("current_phase", 1, project_root=str(tmp_path))
    transcript_path = tmp_path / "transcript.jsonl"
    _write_transcript(
        transcript_path,
        "Yanıtlar netleşti. Şimdi özet hazırlayıp onay alıyorum.",
    )
    payload = {
        "tool_name": "AskUserQuestion",
        "tool_input": {
            "questions": [{
                "question": "Onaylıyor musun?",
                "header": "Onay",
                "options": [
                    {"label": "Evet", "description": "Devam et"},
                    {"label": "Hayır", "description": "Değiştir"},
                ],
                "multiSelect": False,
            }]
        },
        "cwd": str(tmp_path),
        "transcript_path": str(transcript_path),
        "session_id": "test-session",
    }

    rc, stdout, _ = _run_pre_tool_subprocess(payload, tmp_path)

    # PreToolUse deny: stdout JSON `decision: "deny"` + reason
    assert rc == 0
    parsed = json.loads(stdout) if stdout.strip() else {}
    # Hook deny semantic: `decision: deny` veya `hookSpecificOutput.permissionDecision`
    assert (
        parsed.get("decision") == "deny"
        or parsed.get("hookSpecificOutput", {}).get(
            "permissionDecision"
        ) == "deny"
    ), f"Beklenen deny; alınan: {parsed}"
    # Audit yazıldı mı?
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_path))
    ]
    assert "intent-summary-format-missing" in names


def test_pre_tool_phase_1_askq_allowed_with_marker(tmp_path):
    """Aşama 1'de marker'lı özet varsa AskUserQuestion ALLOW."""
    state.set_field("current_phase", 1, project_root=str(tmp_path))
    transcript_path = tmp_path / "transcript.jsonl"
    _write_transcript(
        transcript_path,
        "🎯 Niyet özeti: Full-stack TODO app. React/Vite + Node.js/Express "
        "+ MySQL. Auth + CRUD. ~3 hafta.\n",
    )
    payload = {
        "tool_name": "AskUserQuestion",
        "tool_input": {
            "questions": [{
                "question": "Onaylıyor musun?",
                "header": "Onay",
                "options": [
                    {"label": "Evet", "description": "Devam"},
                    {"label": "Hayır", "description": "Değiştir"},
                ],
                "multiSelect": False,
            }]
        },
        "cwd": str(tmp_path),
        "transcript_path": str(transcript_path),
        "session_id": "test-session",
    }

    rc, stdout, _ = _run_pre_tool_subprocess(payload, tmp_path)

    # ALLOW: deny olmaması yeterli (boş stdout veya allow decision)
    parsed = json.loads(stdout) if stdout.strip() else {}
    assert parsed.get("decision") != "deny"
    decision = parsed.get("hookSpecificOutput", {}).get("permissionDecision")
    assert decision != "deny"
    # Marker'lı durum için intent-summary-format-missing audit YOK
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_path))
    ]
    assert "intent-summary-format-missing" not in names


def test_pre_tool_phase_2_askq_not_guarded(tmp_path):
    """Aşama 1 dışı (örn. Aşama 2) AskUserQuestion guard'tan etkilenmez."""
    state.set_field("current_phase", 2, project_root=str(tmp_path))
    transcript_path = tmp_path / "transcript.jsonl"
    _write_transcript(transcript_path, "Aşama 2'de askq açıyorum.")
    payload = {
        "tool_name": "AskUserQuestion",
        "tool_input": {
            "questions": [{
                "question": "x?",
                "header": "x",
                "options": [
                    {"label": "a", "description": "a"},
                    {"label": "b", "description": "b"},
                ],
                "multiSelect": False,
            }]
        },
        "cwd": str(tmp_path),
        "transcript_path": str(transcript_path),
        "session_id": "test-session",
    }

    rc, stdout, _ = _run_pre_tool_subprocess(payload, tmp_path)

    parsed = json.loads(stdout) if stdout.strip() else {}
    # Aşama 2 askq özgür — intent guard tetiklenmez
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_path))
    ]
    assert "intent-summary-format-missing" not in names


def test_pre_tool_phase_1_other_tool_not_guarded(tmp_path):
    """Aşama 1'de AskUserQuestion dışı tool (Read gibi) guard tetiklenmez."""
    state.set_field("current_phase", 1, project_root=str(tmp_path))
    transcript_path = tmp_path / "transcript.jsonl"
    _write_transcript(transcript_path, "Henüz özet hazırlamadım.")
    payload = {
        "tool_name": "Read",
        "tool_input": {"file_path": "/tmp/x"},
        "cwd": str(tmp_path),
        "transcript_path": str(transcript_path),
        "session_id": "test-session",
    }

    rc, stdout, _ = _run_pre_tool_subprocess(payload, tmp_path)

    # Aşama 1'de Read global allowlist — intent guard sadece askq'ya özel
    names = [
        ev.get("name") for ev in audit.read_all(project_root=str(tmp_path))
    ]
    assert "intent-summary-format-missing" not in names
