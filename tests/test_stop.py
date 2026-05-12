"""hooks/stop.py birim testleri.

Stop hook — sessiz (stdout boş, "continue" default). State/audit yan
etkileri test edilir: spec hash detect, askq intent → spec-approve
flow, universal completeness loop.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


_HOOK_PATH = Path(__file__).resolve().parent.parent / "hooks" / "stop.py"


def _run_hook(payload: dict, env: dict | None = None) -> int:
    result = subprocess.run(
        [sys.executable, str(_HOOK_PATH)],
        input=json.dumps(payload).encode("utf-8"),
        capture_output=True,
        timeout=10,
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


def _seed_audit(project_dir: Path, *event_names: str) -> None:
    """audit.log'a olayları append et (idempotent state seed)."""
    mycl_dir = project_dir / ".mycl"
    mycl_dir.mkdir(parents=True, exist_ok=True)
    audit_log = mycl_dir / "audit.log"
    with audit_log.open("a", encoding="utf-8") as f:
        for name in event_names:
            f.write(f"2026-05-09T20:00:00Z | {name} | seed | -\n")


def _write_transcript(
    project_dir: Path,
    *,
    spec_text: str | None = None,
    askq_response: str | None = None,
) -> Path:
    """JSONL transcript oluştur. Sırayla:
       - spec_text varsa assistant text mesajı
       - askq_response varsa AskUserQuestion tool_use + tool_result çifti
    """
    transcript_path = project_dir / "transcript.jsonl"
    lines = []
    if spec_text:
        lines.append(json.dumps({
            "type": "assistant",
            "message": {
                "role": "assistant",
                "content": [{"type": "text", "text": spec_text}],
            },
        }))
    if askq_response is not None:
        lines.append(json.dumps({
            "type": "assistant",
            "message": {
                "role": "assistant",
                "content": [{
                    "type": "tool_use", "id": "askq-1",
                    "name": "AskUserQuestion", "input": {},
                }],
            },
        }))
        lines.append(json.dumps({
            "type": "user",
            "message": {
                "role": "user",
                "content": [{
                    "type": "tool_result", "tool_use_id": "askq-1",
                    "content": askq_response,
                }],
            },
        }))
    transcript_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return transcript_path


# ---------- self-project guard ----------


def test_self_project_skips(tmp_path):
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(tmp_path)
    env["MYCL_REPO_PATH"] = str(tmp_path)
    rc = _run_hook(
        {"cwd": str(tmp_path), "transcript_path": ""},
        env=env,
    )
    assert rc == 0
    assert not (tmp_path / ".mycl" / "state.json").exists()


# ---------- spec hash detect ----------


def test_spec_in_transcript_stored(tmp_path):
    """Son assistant text'inde Spec block → spec_hash + must_list yazılır.

    extract_must_list section header'lı format bekliyor (## MUST veya
    Zorunlu:); section'lı spec ile MUST sayılır.
    """
    _write_state(tmp_path)
    spec_text = (
        "📋 Spec:\n"
        "MUST:\n"
        "- kullanıcı todo ekleyebilmeli\n"
        "- liste persist edilmeli\n"
    )
    tp = _write_transcript(tmp_path, spec_text=spec_text)
    rc = _run_hook(
        {"cwd": str(tmp_path), "transcript_path": str(tp)},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    s = _read_state(tmp_path)
    assert s["spec_hash"] is not None
    assert len(s["spec_hash"]) == 64  # SHA256 hex
    assert len(s["spec_must_list"]) >= 1
    assert "spec-hash-stored" in _read_audit(tmp_path)


def test_spec_without_must_section_still_stores_hash(tmp_path):
    """Inline MUST_N: formatı section header değil → must_list boş kalır
    ama spec_hash yine yazılır (Aşama 4 onayı için yeterli)."""
    _write_state(tmp_path)
    spec_text = "📋 Spec:\n- MUST_1: x\n- MUST_2: y"
    tp = _write_transcript(tmp_path, spec_text=spec_text)
    _run_hook({"cwd": str(tmp_path), "transcript_path": str(tp)}, env=_env_with(tmp_path))
    s = _read_state(tmp_path)
    assert s["spec_hash"] is not None
    # MUST section header yoksa must_list boş; davranış belgeli
    assert s["spec_must_list"] == []


def test_no_spec_in_transcript_no_op(tmp_path):
    _write_state(tmp_path)
    tp = _write_transcript(tmp_path, spec_text="just plain prose, no spec block")
    rc = _run_hook(
        {"cwd": str(tmp_path), "transcript_path": str(tp)},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["spec_hash"] is None


def test_same_spec_idempotent(tmp_path):
    """Aynı spec hash ikinci çalıştırmada audit yazılmaz."""
    _write_state(tmp_path)
    spec_text = "📋 Spec:\n- MUST_1: x"
    tp = _write_transcript(tmp_path, spec_text=spec_text)
    _run_hook({"cwd": str(tmp_path), "transcript_path": str(tp)}, env=_env_with(tmp_path))
    audit_after_first = _read_audit(tmp_path)
    _run_hook({"cwd": str(tmp_path), "transcript_path": str(tp)}, env=_env_with(tmp_path))
    audit_after_second = _read_audit(tmp_path)
    assert audit_after_first.count("spec-hash-stored") == audit_after_second.count("spec-hash-stored")


def test_spec_without_emoji_detected(tmp_path):
    """v13.1.2 öğrenimi: emoji opsiyonel."""
    _write_state(tmp_path)
    spec_text = "Spec:\n- MUST_1: foo"
    tp = _write_transcript(tmp_path, spec_text=spec_text)
    _run_hook({"cwd": str(tmp_path), "transcript_path": str(tp)}, env=_env_with(tmp_path))
    assert _read_state(tmp_path)["spec_hash"] is not None


# ---------- Aşama 4 spec-approve flow ----------


def test_phase_4_approve_with_spec_marks_approved(tmp_path):
    """Aşama 4 + spec_hash + askq approve → spec_approved=True + audit chain."""
    _write_state(tmp_path, current_phase=4)
    spec_text = "📋 Spec:\n- MUST_1: x"
    tp = _write_transcript(tmp_path, spec_text=spec_text, askq_response="evet onayla")
    rc = _run_hook(
        {"cwd": str(tmp_path), "transcript_path": str(tp)},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    s = _read_state(tmp_path)
    assert s["spec_approved"] is True
    audit = _read_audit(tmp_path)
    # Audit chain auto-fill: 1, 2, 3, 4 hepsi
    for n in (1, 2, 3, 4):
        assert f"asama-{n}-complete" in audit


def test_phase_4_approve_without_spec_no_op(tmp_path):
    """Aşama 4 + spec_hash YOK + askq approve → no-op (spec yok)."""
    _write_state(tmp_path, current_phase=4)
    tp = _write_transcript(tmp_path, askq_response="evet")
    rc = _run_hook(
        {"cwd": str(tmp_path), "transcript_path": str(tp)},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["spec_approved"] is False


def test_phase_5_approve_does_not_set_spec_approved(tmp_path):
    """Faz dışı (Aşama 5) askq approve → spec_approve flow tetiklenmez."""
    _write_state(tmp_path, current_phase=5, spec_hash="a" * 64)
    tp = _write_transcript(tmp_path, askq_response="evet onayla")
    _run_hook(
        {"cwd": str(tmp_path), "transcript_path": str(tp)},
        env=_env_with(tmp_path),
    )
    assert _read_state(tmp_path)["spec_approved"] is False


def test_phase_4_revise_does_not_approve(tmp_path):
    _write_state(tmp_path, current_phase=4)
    spec_text = "📋 Spec:\n- MUST_1: x"
    tp = _write_transcript(tmp_path, spec_text=spec_text, askq_response="hayır revize et")
    _run_hook(
        {"cwd": str(tmp_path), "transcript_path": str(tp)},
        env=_env_with(tmp_path),
    )
    assert _read_state(tmp_path)["spec_approved"] is False


def test_already_approved_idempotent(tmp_path):
    """spec_approved=True iken approve tekrarı no-op (audit chain çoğalmaz)."""
    _write_state(tmp_path, current_phase=4, spec_approved=True, spec_hash="b" * 64)
    _seed_audit(tmp_path, "asama-1-complete", "asama-2-complete",
                "asama-3-complete", "asama-4-complete")
    tp = _write_transcript(tmp_path, askq_response="evet onayla")
    _run_hook(
        {"cwd": str(tmp_path), "transcript_path": str(tp)},
        env=_env_with(tmp_path),
    )
    audit = _read_audit(tmp_path)
    # Her asama-N-complete sadece bir kez (seed'den) — yeni eklenmedi
    for n in (1, 2, 3, 4):
        assert audit.count(f"asama-{n}-complete") == 1


# ---------- universal completeness loop ----------


def test_completeness_advances_when_audit_present(tmp_path):
    """Aşama 1 + asama-1-complete audit → Aşama 2'ye advance."""
    _write_state(tmp_path, current_phase=1)
    _seed_audit(tmp_path, "asama-1-complete")
    rc = _run_hook(
        {"cwd": str(tmp_path), "transcript_path": ""},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["current_phase"] == 2
    assert "phase-advance" in _read_audit(tmp_path)


def test_completeness_no_advance_without_audit(tmp_path):
    _write_state(tmp_path, current_phase=1)
    rc = _run_hook(
        {"cwd": str(tmp_path), "transcript_path": ""},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["current_phase"] == 1


def test_completeness_chain_advances_multiple_phases(tmp_path):
    """Birden fazla phase audit zinciri → ardışık advance.

    1.0.17: Aşama 2 `required_audits_all` (AND) — `asama-2-complete`
    + `precision-audit` ikisi de zorunlu. Hook normal akışta side_audits
    ile otomatik yazar; bu test seed audit kullandığı için ikisini de
    açıkça yerleştirir.
    """
    _write_state(tmp_path, current_phase=1)
    _seed_audit(
        tmp_path,
        "asama-1-complete",
        "asama-2-complete",
        "precision-audit",  # Aşama 2 AND zorunluluğu (1.0.17)
        "asama-3-complete",
    )
    rc = _run_hook(
        {"cwd": str(tmp_path), "transcript_path": ""},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["current_phase"] == 4


def test_completeness_does_not_skip_missing_audit(tmp_path):
    """Aşama 1 ✓, Aşama 2 ✗, Aşama 3 ✓ → sadece 1 advance (Aşama 2'de durur)."""
    _write_state(tmp_path, current_phase=1)
    _seed_audit(tmp_path, "asama-1-complete", "asama-3-complete")
    _run_hook(
        {"cwd": str(tmp_path), "transcript_path": ""},
        env=_env_with(tmp_path),
    )
    assert _read_state(tmp_path)["current_phase"] == 2


def test_completeness_terminal_phase_22_no_op(tmp_path):
    _write_state(tmp_path, current_phase=22)
    _seed_audit(tmp_path, "asama-22-complete")
    rc = _run_hook(
        {"cwd": str(tmp_path), "transcript_path": ""},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["current_phase"] == 22


# ---------- spec-approve + completeness combined ----------


def test_full_phase_4_approval_walks_to_phase_5(tmp_path):
    """Aşama 4 + spec_text + approve → spec_approved=True + audit chain
    + completeness loop Aşama 5'e advance."""
    _write_state(tmp_path, current_phase=4)
    spec_text = "📋 Spec:\n- MUST_1: x"
    tp = _write_transcript(tmp_path, spec_text=spec_text, askq_response="onaylıyorum")
    _run_hook(
        {"cwd": str(tmp_path), "transcript_path": str(tp)},
        env=_env_with(tmp_path),
    )
    s = _read_state(tmp_path)
    assert s["spec_approved"] is True
    assert s["current_phase"] == 5  # 4 → 5


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


def test_no_transcript_path_no_op(tmp_path):
    """transcript_path yoksa spec/askq detect skip; completeness loop yine çalışır."""
    _write_state(tmp_path, current_phase=1)
    _seed_audit(tmp_path, "asama-1-complete")
    rc = _run_hook(
        {"cwd": str(tmp_path)},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    # transcript yok ama audit driven advance yine çalışır
    assert _read_state(tmp_path)["current_phase"] == 2


def test_nonexistent_transcript_path_no_op(tmp_path):
    _write_state(tmp_path)
    rc = _run_hook(
        {"cwd": str(tmp_path), "transcript_path": "/nonexistent/path.jsonl"},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    assert _read_state(tmp_path)["spec_hash"] is None


# ---------- text trigger phase complete ----------


def test_text_trigger_emits_audit_when_phase_matches(tmp_path):
    """cp=1 + transcript 'asama-1-complete' → audit emit edilir."""
    _write_state(tmp_path, current_phase=1)
    tp = _write_transcript(
        tmp_path,
        spec_text="Aşama 1 tamamlandı.\n\nasama-1-complete",
    )
    rc = _run_hook(
        {"cwd": str(tmp_path), "transcript_path": str(tp)},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    audit_text = _read_audit(tmp_path)
    assert "asama-1-complete" in audit_text
    assert "phase-skip-attempt" not in audit_text
    # Completeness loop tetik audit'i görüp Aşama 2'ye ilerletmeli
    assert _read_state(tmp_path)["current_phase"] == 2


def test_text_trigger_rejects_skip_attempt(tmp_path):
    """cp=1 + transcript 'asama-9-complete' → reject + phase-skip-attempt audit."""
    _write_state(tmp_path, current_phase=1)
    tp = _write_transcript(
        tmp_path,
        spec_text="atlama denemem.\n\nasama-9-complete",
    )
    rc = _run_hook(
        {"cwd": str(tmp_path), "transcript_path": str(tp)},
        env=_env_with(tmp_path),
    )
    assert rc == 0
    audit_text = _read_audit(tmp_path)
    assert "asama-9-complete" not in audit_text
    assert "phase-skip-attempt" in audit_text
    # Atlama reddedildi, faz 1'de kalır
    assert _read_state(tmp_path)["current_phase"] == 1


def test_text_trigger_idempotent(tmp_path):
    """Aynı tetik tekrar yazılırsa duplicate audit yok."""
    _write_state(tmp_path, current_phase=1)
    _seed_audit(tmp_path, "asama-1-complete")
    tp = _write_transcript(tmp_path, spec_text="asama-1-complete")
    _run_hook(
        {"cwd": str(tmp_path), "transcript_path": str(tp)},
        env=_env_with(tmp_path),
    )
    audit_text = _read_audit(tmp_path)
    assert audit_text.count("asama-1-complete") == 1


def test_text_trigger_no_match_no_op(tmp_path):
    """Tetik kelimesi yoksa audit eklenmez."""
    _write_state(tmp_path, current_phase=1)
    tp = _write_transcript(tmp_path, spec_text="merhaba dünya")
    _run_hook(
        {"cwd": str(tmp_path), "transcript_path": str(tp)},
        env=_env_with(tmp_path),
    )
    audit_text = _read_audit(tmp_path)
    assert "asama-1-complete" not in audit_text
    assert "phase-skip-attempt" not in audit_text
    assert _read_state(tmp_path)["current_phase"] == 1


def test_text_trigger_stale_emit_silent(tmp_path):
    """cp=2 + transcript 'asama-1-complete' (geçmiş faz) → sessiz no-op.

    Faz zaten ilerlemiş; model özet veya tekrar amaçlı eski etiketi
    yazmış. Bu sıralılık ihlali DEĞİL — gürültü olmasın diye
    `phase-skip-attempt` yazılmaz.
    """
    _write_state(tmp_path, current_phase=2)
    _seed_audit(tmp_path, "asama-1-complete")  # faz 1 zaten emit'li
    tp = _write_transcript(tmp_path, spec_text="asama-1-complete")
    _run_hook(
        {"cwd": str(tmp_path), "transcript_path": str(tp)},
        env=_env_with(tmp_path),
    )
    audit_text = _read_audit(tmp_path)
    # Stale-emit sessiz: phase-skip-attempt YAZILMAMALI
    assert "phase-skip-attempt" not in audit_text
    # asama-1-complete tekrar yazılmamış (sadece seed'den var)
    assert audit_text.count("asama-1-complete") == 1
    # Faz ilerlemedi
    assert _read_state(tmp_path)["current_phase"] == 2
