"""progress — Inline progress + ASCII pipeline + faz sonu notification.

Pseudocode + CLAUDE.md disiplin katmanı #5 (faz sonu inline notification)
+ #6 (ASCII pipeline + son faz mini-özet).

Sözleşme:
    - Stop hook her faz sonunda `phase_done_notification` veya
      `phase_skipped_notification` render eder (TR + EN).
    - ASCII pipeline 22 fazın durumunu glyph'lerle gösterir:
      ✅ done, ⏳ active, ' ' pending, ↷ skipped, ❌ blocked.
    - Glyph'ler `data/phase_meta.json` içinde tanımlı.
    - Auto-timeout askq YOK (Claude Code mimari kısıtı); görünürlük +
      model dikkat etkisi korunur.

API:
    phase_done_notification(phase, phase_name, next_phase) → "TR\\n\\nEN"
    phase_skipped_notification(phase, reason, next_phase) → "TR\\n\\nEN"
    ascii_pipeline(state_dict, audit_log) → str (görsel bar)
    pipeline_block(project_root) → str (header + bar + faz tablosu)
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit, bilingual

_phase_meta_cache: dict | None = None
_DEFAULT_META: dict = {
    "ascii_glyph_done": "✅",
    "ascii_glyph_active": "⏳",
    "ascii_glyph_pending": " ",
    "ascii_glyph_skipped": "↷",
    "ascii_glyph_blocked": "❌",
    "phases": {},
}

_PHASES_TOTAL = 22


def _data_dir_candidates() -> list[Path]:
    return [
        Path.home() / ".claude" / "data",
        Path(__file__).resolve().parent.parent.parent / "data",
    ]


def load_phase_meta(path: str | Path | None = None) -> dict:
    """phase_meta.json yükle (cache)."""
    global _phase_meta_cache
    if path is None and _phase_meta_cache is not None:
        return _phase_meta_cache

    if path is not None:
        p: Path | None = Path(path)
    else:
        p = None
        for c in _data_dir_candidates():
            cand = c / "phase_meta.json"
            if cand.exists():
                p = cand
                break

    if p is None or not p.exists():
        return _DEFAULT_META

    try:
        with p.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return _DEFAULT_META

    if not isinstance(data, dict):
        return _DEFAULT_META

    if path is None:
        _phase_meta_cache = data
    return data


def reset_cache() -> None:
    global _phase_meta_cache
    _phase_meta_cache = None


# ---------- Notifications ----------


def phase_done_notification(
    phase: int,
    phase_name: str = "",
    next_phase: int | None = None,
) -> str:
    """Faz tamamlanma mesajı (TR + EN).

    bilingual.py'den `phase_done_notification` key'i.
    """
    nxt = next_phase if next_phase is not None else min(phase + 1, _PHASES_TOTAL)
    return bilingual.render(
        "phase_done_notification",
        phase=phase,
        phase_name=phase_name,
        next_phase=nxt,
    )


def phase_skipped_notification(
    phase: int,
    reason: str = "",
    next_phase: int | None = None,
) -> str:
    """Faz atlama mesajı (TR + EN)."""
    nxt = next_phase if next_phase is not None else min(phase + 1, _PHASES_TOTAL)
    return bilingual.render(
        "phase_skipped_notification",
        phase=phase,
        reason=reason,
        next_phase=nxt,
    )


# ---------- ASCII pipeline ----------


def _glyph_for_phase(
    phase: int,
    current_phase: int,
    finished_phases: set[int],
    skipped_phases: set[int],
    blocked: bool,
    meta: dict,
) -> str:
    """Tek faz için glyph seç."""
    if phase in skipped_phases:
        return meta.get("ascii_glyph_skipped", "↷")
    if phase in finished_phases:
        return meta.get("ascii_glyph_done", "✅")
    if phase == current_phase:
        if blocked:
            return meta.get("ascii_glyph_blocked", "❌")
        return meta.get("ascii_glyph_active", "⏳")
    return meta.get("ascii_glyph_pending", " ")


def ascii_pipeline(
    current_phase: int,
    finished_phases: set[int] | None = None,
    skipped_phases: set[int] | None = None,
    blocked: bool = False,
    meta: dict | None = None,
) -> str:
    """22 fazın görsel ASCII bar'ı.

    Çıktı örneği:
        [1✅]→[2✅]→[3✅]→[4✅]→[5⏳]→[6 ]→[7 ]→...→[22 ]
    """
    m = meta if meta is not None else load_phase_meta()
    fin = finished_phases or set()
    skp = skipped_phases or set()
    cells: list[str] = []
    for p in range(1, _PHASES_TOTAL + 1):
        glyph = _glyph_for_phase(p, current_phase, fin, skp, blocked, m)
        cells.append(f"[{p}{glyph}]")
    return "→".join(cells)


def derive_phase_states(
    project_root: str | None = None,
) -> tuple[set[int], set[int]]:
    """Audit'lerden tamamlanan + atlanan faz setlerini türet.

    Returns:
        (finished_phases, skipped_phases)
        finished: complete + end audit'i olan fazlar
        skipped:  skipped + not-applicable audit'i olan fazlar
    """
    finished: set[int] = set()
    skipped: set[int] = set()
    for ev in audit.read_all(project_root=project_root):
        n = audit.phase_number(ev["name"])
        if n is None:
            continue
        name = ev["name"]
        if name.endswith("-complete") or name.endswith("-end"):
            finished.add(n)
        elif name.endswith("-skipped") or name.endswith("-not-applicable"):
            skipped.add(n)
    return finished, skipped


def pipeline_block(
    current_phase: int,
    project_root: str | None = None,
    blocked: bool = False,
) -> str:
    """Tam görünür DSI bloğu: header + ASCII bar (çift dil).

    Header bilingual.py 'ascii_pipeline_header' key'ini kullanır.
    """
    finished, skipped = derive_phase_states(project_root=project_root)
    bar = ascii_pipeline(
        current_phase=current_phase,
        finished_phases=finished,
        skipped_phases=skipped,
        blocked=blocked,
    )
    header = bilingual.render("ascii_pipeline_header")
    if header.startswith("["):
        # Eksik key fallback (test fixture'larda) — sadece bar
        return bar
    return f"{header}\n{bar}"
