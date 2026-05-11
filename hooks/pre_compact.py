#!/usr/bin/env python3
"""pre_compact — context compaction öncesi MyCL state snapshot + reminder.

Anthropic resmi rehberi (code.claude.com/docs/en/hooks-guide): PreCompact
event compaction tetiklendiğinde çalışır; matcher = manual | auto. Hook
stdin'den JSON alır, isteğe bağlı stdout JSON döndürür (hookSpecificOutput.
additionalContext compaction sonrası context'te korunur).

MyCL kullanımı (drift counter-measure):
    1. `.mycl/state.json` + son 10 audit + spec MUST listesi
       `.mycl/wip_snapshot.json`'a serileştirilir.
    2. Bilingual reminder (TR + EN) hookSpecificOutput.additionalContext
       ile döndürülür → compact edilmiş context'e kritik kurallar yeniden
       enjekte edilir.
    3. `precompact-snapshot` audit kaydı yazılır (görünür sinyal).

Anthropic Issue #53223 referansı: "CLAUDE.md instruction compliance is
architecturally unenforced" — PreCompact hook bu boşluğa karşı resmi
deterministik araç. MyCL'in faz disiplinini compact sonrası ayakta tutar.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from hooks.lib import audit, state  # noqa: E402


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


def _capture_snapshot(project_dir: str, matcher: str) -> dict:
    """state + son 10 audit + spec MUST listesi → `.mycl/wip_snapshot.json`."""
    cp = state.get("current_phase", 1, project_root=project_dir)
    spec_approved = bool(state.get("spec_approved", False, project_root=project_dir))
    spec_must_list = state.get("spec_must_list", [], project_root=project_dir)
    last_phase_output = state.get(
        "last_phase_output", "none", project_root=project_dir,
    )

    all_events = audit.read_all(project_root=project_dir)
    recent = [
        {
            "name": ev.get("name", ""),
            "detail": str(ev.get("detail", ""))[:80],
        }
        for ev in all_events[-10:]
    ]

    snapshot = {
        "schema_version": 1,
        "compact_matcher": matcher,
        "current_phase": cp,
        "spec_approved": spec_approved,
        "spec_must_list": spec_must_list,
        "last_phase_output": last_phase_output,
        "recent_audit": recent,
    }

    snapshot_dir = Path(project_dir) / ".mycl"
    snapshot_dir.mkdir(parents=True, exist_ok=True)
    (snapshot_dir / "wip_snapshot.json").write_text(
        json.dumps(snapshot, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    audit.log_event(
        "precompact-snapshot", "pre_compact.py",
        f"matcher={matcher} phase={cp} must_count={len(spec_must_list)}",
        project_root=project_dir,
    )

    return snapshot


def _build_reminder(snapshot: dict) -> str:
    """Bilingual reinforcement reminder (TR + EN, boş satır ayraçlı)."""
    cp = snapshot["current_phase"]
    spec_approved = snapshot["spec_approved"]
    must_count = len(snapshot.get("spec_must_list") or [])

    tr = (
        f"MyCL compaction öncesi snapshot kaydedildi. "
        f"Aktif aşama: {cp}/22. "
        f"Spec onaylı: {'evet' if spec_approved else 'hayır'}. "
        f"Spec MUST sayısı: {must_count}. "
        f"Kritik kural: faz sırası bozulamaz; "
        f"mutating tool yalnız spec_approved=true ile izinlidir."
    )
    en = (
        f"MyCL snapshot saved before compaction. "
        f"Active phase: {cp}/22. "
        f"Spec approved: {'yes' if spec_approved else 'no'}. "
        f"Spec MUST count: {must_count}. "
        f"Critical rule: phase sequence is immutable; "
        f"mutating tools only permitted when spec_approved=true."
    )
    return f"{tr}\n\n{en}"


def main() -> int:
    payload = _read_input()
    project_dir = (
        payload.get("cwd")
        or os.environ.get("CLAUDE_PROJECT_DIR")
        or os.getcwd()
    )

    if _is_self_project(project_dir):
        return 0

    matcher = str(
        payload.get("matcher") or payload.get("compact_reason") or "auto"
    )

    snapshot = _capture_snapshot(project_dir, matcher)
    reminder = _build_reminder(snapshot)

    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreCompact",
            "additionalContext": (
                "<mycl_precompact_reminder>\n"
                f"{reminder}\n"
                "</mycl_precompact_reminder>"
            ),
        }
    }
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
