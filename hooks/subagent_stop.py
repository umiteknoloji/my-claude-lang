#!/usr/bin/env python3
"""subagent_stop — SubagentStop hook (mycl-phase-runner native dispatch).

1.0.8: `orchestrator.py` + `stop.py`'daki transcript-scan kanalına
paralel native SubagentStop event'i. Subagent (`Task` tool →
`mycl-phase-runner`) bittiğinde Claude Code AGENTIC LOOP içinden fire
eder; tool_result transcript_path üzerinden okunur (mevcut
`_find_phase_runner_output` mantığı ile birebir).

Open/Closed: `stop.py`'daki kanal **silinmedi** — bu hook **ek path**.
İki kanal da aynı audit'i yazmaya çalışır; idempotent guard
(`existing audits` set check) çift emit'i önler. İlk fire eden kazanır,
ikincisi `audit_name in existing` ile no-op döner.

Sözleşme:
    - stdin: Claude Code JSON payload (session_id, transcript_path, cwd)
    - stdout: boş (Stop semantiği — yan etkiler asıl değer)
    - Side effects: audit.log + state.last_phase_output
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from hooks.lib import (  # noqa: E402
    activation, audit, orchestrator, state, transcript,
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


def _find_phase_runner_output(transcript_path: str) -> str | None:
    """Transcript'te son `mycl-phase-runner` Task çağrısının tool_result text'i.

    `stop.py::_find_phase_runner_output` ile özdeş — Open/Closed gereği
    iki kanal aynı kodu paylaşır. 1.0.9'da ortak yardımcıya taşınması
    değerlendirilebilir; şimdilik duplikasyon kabul (kanal mantıksal
    ayrı, bağımlılık eklemiyoruz).
    """
    if not transcript_path:
        return None
    use_id: str | None = None
    last_result: str | None = None
    for msg in transcript.iter_messages(transcript_path):
        for content in msg.get("message", {}).get("content", []):
            if not isinstance(content, dict):
                continue
            ctype = content.get("type")
            if ctype == "tool_use" and content.get("name") == "Task":
                inp = content.get("input") or {}
                if isinstance(inp, dict) and inp.get("subagent_type") == "mycl-phase-runner":
                    use_id = content.get("id")
            elif ctype == "tool_result" and use_id is not None:
                if content.get("tool_use_id") == use_id:
                    raw = content.get("content")
                    if isinstance(raw, list):
                        parts = [
                            blk.get("text", "")
                            for blk in raw
                            if isinstance(blk, dict) and blk.get("type") == "text"
                        ]
                        last_result = "\n".join(p for p in parts if p)
                    elif isinstance(raw, str):
                        last_result = raw
    return last_result


def _detect_subagent_phase_output(
    transcript_path: str, project_dir: str,
) -> bool:
    """SubagentStop kanalı: subagent çıktısını parse + audit emit.

    Aşama N'de `subagent_orchestration: true` ise:
      - complete → `asama-N-complete` audit
      - skipped  → `asama-N-skipped` audit
      - pending  → `asama-N-pending` audit (advance YOK)
      - error    → `asama-N-subagent-error` audit (advance YOK)

    Returns: yeni audit yazıldıysa True.
    """
    if not transcript_path:
        return False
    cp = state.get("current_phase", 1, project_root=project_dir)
    if not orchestrator.is_orchestration_enabled(cp):
        return False

    output_text = _find_phase_runner_output(transcript_path)
    if not output_text:
        return False

    parsed = orchestrator.parse_phase_output(output_text)
    existing = {ev.get("name") for ev in audit.read_all(project_root=project_dir)}

    if parsed.outcome == orchestrator.PhaseOutcome.COMPLETE:
        audit_name = f"asama-{cp}-complete"
        if audit_name in existing:
            return False
        audit.log_event(
            audit_name, "subagent_stop.py",
            f"subagent-emit summary={parsed.summary[:80]}",
            project_root=project_dir,
        )
        state.set_field(
            "last_phase_output", parsed.summary,
            project_root=project_dir,
        )
        return True

    if parsed.outcome == orchestrator.PhaseOutcome.SKIPPED:
        audit_name = f"asama-{cp}-skipped"
        if audit_name in existing:
            return False
        audit.log_event(
            audit_name, "subagent_stop.py",
            f"reason={parsed.reason} detail={parsed.detail[:80]}",
            project_root=project_dir,
        )
        state.set_field(
            "last_phase_output", f"skipped reason={parsed.reason}",
            project_root=project_dir,
        )
        return True

    if parsed.outcome == orchestrator.PhaseOutcome.PENDING:
        audit.log_event(
            f"asama-{cp}-pending", "subagent_stop.py",
            f"question={parsed.question[:120]}",
            project_root=project_dir,
        )
        return False

    # ERROR
    audit.log_event(
        f"asama-{cp}-subagent-error", "subagent_stop.py",
        f"detail={parsed.detail[:120]}",
        project_root=project_dir,
    )
    return False


def main() -> int:
    payload = _read_input()
    project_dir = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

    if _is_self_project(project_dir):
        return 0

    # 1.0.5: opt-in /mycl — aktif değilse no-op
    session_id = str(payload.get("session_id", "") or "")
    if not activation.is_session_active(session_id, project_root=project_dir):
        return 0

    transcript_path = str(payload.get("transcript_path") or "")
    _detect_subagent_phase_output(transcript_path, project_dir)

    # 1.0.15 — multi-subagent akışta `asama-N-complete` text-trigger
    # kayıp sorunu: model bir turda hem trigger emit ediyor hem Task
    # tool çağırıyor → Claude Code Stop event fire etmez (tool var) →
    # trigger kanalı kayıp. SubagentStop her subagent dönüşünde fire
    # ediyor; burada Stop hook'un text-trigger detect + completeness
    # loop mantığını paralel ek path olarak çalıştırıyoruz.
    #
    # Idempotent: Stop ve SubagentStop ikisi de aynı turda fire
    # ederse `existing audits` set check çift emit'i engeller; ilki
    # yazar, ikincisi no-op. stop.py'daki private fonksiyonların
    # public re-export'una gerek yok — aynı modül çatısı altında
    # private erişim Python'da legal.
    from hooks.stop import (  # noqa: E402
        _detect_phase_complete_trigger,
        _run_completeness_loop,
    )
    _detect_phase_complete_trigger(transcript_path, project_dir)
    _run_completeness_loop(project_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
