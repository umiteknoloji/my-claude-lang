"""trace — `.mycl/trace.log` session-level transition kaydı.

Pseudocode referansı: MyCL_Pseudocode.md §2 (kancalar arası iletişim
trace log üzerinden) + §3 Aşama 20 (Process Trace bölümü trace.log'dan).

audit.log vs trace.log:
    - audit.log: kalıcı event kaydı — faz tamamlama, askq onayı,
      block kararları (her satır gözden geçirilebilir delil).
    - trace.log: session-level geçiş kaydı — session_start,
      phase_transition, strike counter'ları, hook tarafından üretilen
      özet sinyaller (Aşama 20 raporunun ham veri kaynağı).

Sözleşme:
    - trace.log proje köküne `.mycl/trace.log`. Tek dosya, append-only.
    - Format: `<UTC ISO8601> | <event> | <value>` (her satır 3 sütun).
    - Append atomik (POSIX 'a' mode + tek write).
    - parse_line malformed satır None döner.
"""

from __future__ import annotations

import os
import time
from pathlib import Path
from typing import Optional

_TIMESTAMP_FMT = "%Y-%m-%dT%H:%M:%SZ"
_LINE_SEP = " | "


def _trace_dir(project_root: str | None = None) -> Path:
    root = Path(project_root or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    return root / ".mycl"


def trace_path(project_root: str | None = None) -> Path:
    return _trace_dir(project_root) / "trace.log"


def _now_utc() -> str:
    return time.strftime(_TIMESTAMP_FMT, time.gmtime())


def append(
    event: str,
    value: str = "",
    project_root: str | None = None,
) -> None:
    """trace.log'a tek satır ekle. Format: `<UTC> | event | value`."""
    if not event or _LINE_SEP in event:
        raise ValueError(f"event geçersiz: {event!r}")
    if _LINE_SEP in value:
        raise ValueError(f"value içinde ' | ' yasak: {value!r}")
    p = trace_path(project_root)
    p.parent.mkdir(parents=True, exist_ok=True)
    line = f"{_now_utc()}{_LINE_SEP}{event}{_LINE_SEP}{value}\n"
    with p.open("a", encoding="utf-8") as f:
        f.write(line)


def parse_line(line: str) -> Optional[dict[str, str]]:
    """Tek satır → dict; format dışı satır → None."""
    line = line.rstrip("\n")
    if not line:
        return None
    parts = line.split(_LINE_SEP, 2)
    if len(parts) != 3:
        return None
    return {"ts": parts[0], "event": parts[1], "value": parts[2]}


def read_all(project_root: str | None = None) -> list[dict[str, str]]:
    p = trace_path(project_root)
    if not p.exists():
        return []
    out: list[dict[str, str]] = []
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        tr = parse_line(line)
        if tr is not None:
            out.append(tr)
    return out


def has(event: str, project_root: str | None = None) -> bool:
    for tr in read_all(project_root):
        if tr["event"] == event:
            return True
    return False


def find(
    event: str | None = None,
    event_prefix: str | None = None,
    project_root: str | None = None,
) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for tr in read_all(project_root):
        if event is not None and tr["event"] != event:
            continue
        if event_prefix is not None and not tr["event"].startswith(event_prefix):
            continue
        out.append(tr)
    return out


def latest(event: str, project_root: str | None = None) -> Optional[dict[str, str]]:
    matches = find(event=event, project_root=project_root)
    return matches[-1] if matches else None


# ---------- Convenience yardımcıları ----------


def session_start(version: str, project_root: str | None = None) -> None:
    """Session başlangıç kaydı; activate hook her ilk turda çağırır."""
    append("session_start", version, project_root=project_root)


def phase_transition(
    from_phase: int,
    to_phase: int,
    project_root: str | None = None,
) -> None:
    """Faz geçiş kaydı; gate.advance çağırır.

    Sıralılık invariantı: to_phase = from_phase + 1 olmalı (CLAUDE.md
    captured-rule). Bu kontrol burada değil, gate.py'de yapılır —
    trace.append çağrısı geldiyse zaten gate kontrolünden geçmiştir.
    """
    append(
        "phase_transition",
        f"{from_phase}->{to_phase}",
        project_root=project_root,
    )
