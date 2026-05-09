"""skill_loader — Stack-aware skill loading (Disiplin #16).

Pseudocode + CLAUDE.md disiplin katmanı #16.

Sözleşme:
    - 22 skill dosyası her zaman yüklü değil — token tasarrufu için
      sadece **aktif faz + sıradaki 2 faz** + stack-relevant olanlar.
    - Skill dosyaları `~/.claude/skills/mycl/` altında (production)
      veya `<repo>/skills/mycl/` (dev).
    - Skill dosya adı `asama<NN>-<slug>.md` formatında.
    - Stack relevance heuristic'i: dosya adında stack token (örn.
      `python`, `react`, `node`) varsa o stack'te relevant. Stack
      ipucusuz dosyalar her stack için relevant kabul edilir.

API:
    skills_dir() → Path
    list_all_skills() → list[Path]
    next_phases_window(current_phase, window=2) → list[int]
    skills_for_phases(phase_list) → list[Path]
    relevant_for(current_phase, stack=None) → list[Path]
    load_content(path) → str (md text)
"""

from __future__ import annotations

import re
from pathlib import Path

_SKILL_NAME_RE = re.compile(r"^asama(\d+)-(.+)\.md$", re.IGNORECASE)


def _skills_dir_candidates() -> list[Path]:
    """Skill dizini arama yerleri (sırayla)."""
    return [
        Path.home() / ".claude" / "skills" / "mycl",
        Path(__file__).resolve().parent.parent.parent / "skills" / "mycl",
    ]


def skills_dir() -> Path | None:
    """İlk var olan skill dizini (yoksa None)."""
    for d in _skills_dir_candidates():
        if d.exists() and d.is_dir():
            return d
    return None


def list_all_skills() -> list[Path]:
    """skills/mycl/ altındaki tüm asamaNN-*.md dosyaları."""
    d = skills_dir()
    if d is None:
        return []
    return sorted([p for p in d.glob("asama*.md") if p.is_file()])


def next_phases_window(
    current_phase: int,
    window: int = 2,
) -> list[int]:
    """Aktif faz + sıradaki `window` fazın listesi (1-22 cap).

    Örnek: current=5, window=2 → [5, 6, 7].
    """
    if current_phase < 1:
        current_phase = 1
    if current_phase > 22:
        current_phase = 22
    end = min(current_phase + window, 22)
    return list(range(current_phase, end + 1))


def _phase_from_path(path: Path) -> int | None:
    """asamaNN-*.md → N (yoksa None)."""
    m = _SKILL_NAME_RE.match(path.name)
    if not m:
        return None
    try:
        return int(m.group(1))
    except ValueError:
        return None


def skills_for_phases(phase_list: list[int]) -> list[Path]:
    """Belirli faz numaralarına ait skill dosyaları."""
    if not phase_list:
        return []
    target = set(phase_list)
    out: list[Path] = []
    for p in list_all_skills():
        n = _phase_from_path(p)
        if n is not None and n in target:
            out.append(p)
    return out


def relevant_for(
    current_phase: int,
    stack: str | None = None,
    window: int = 2,
) -> list[Path]:
    """Aktif + sıradaki `window` faz + stack-relevant skill'ler.

    Stack relevance heuristic:
        - stack=None → faz pencerisindeki TÜM skill'ler
        - stack="python" → dosya adında 'python' geçen + stack ipucusuz
          dosyalar (ortak skill'ler)
        - dosya adında BAŞKA stack token (örn. 'react') varsa elenir

    Stack ipucusu yoksa skill ortak kabul edilir.
    """
    phases = next_phases_window(current_phase, window=window)
    candidates = skills_for_phases(phases)
    if not stack:
        return candidates

    stack_lc = stack.lower()
    # Bilinen stack token'ları (genişletilebilir)
    known_stacks = {"python", "node", "react", "vue", "go", "rust", "java", "ruby"}
    other_stacks = known_stacks - {stack_lc}

    out: list[Path] = []
    for p in candidates:
        name_lc = p.name.lower()
        # Bu dosya başka stack'e ait mi?
        if any(s in name_lc for s in other_stacks):
            continue
        out.append(p)
    return out


def load_content(path: str | Path) -> str:
    """Skill dosyası içeriğini oku (UTF-8). Hata → boş string."""
    p = Path(path)
    if not p.exists() or not p.is_file():
        return ""
    try:
        return p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
