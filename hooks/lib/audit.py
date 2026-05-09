"""audit — `.mycl/audit.log` append-only event kaydı.

Pseudocode referansı: MyCL_Pseudocode.md §2 (kancalar arası iletişim
audit log üzerinden) + §5 (audit-driven active phase resolver).

Sözleşme:
    - audit.log proje köküne `.mycl/audit.log`. Tek dosya, append-only.
    - Format: `<UTC ISO8601> | <name> | <caller> | <detail>` (her satır).
    - Append atomik (`open("a")` + tek `write()` POSIX'te thread-safe
      kabul edilir; race condition için flock yok — Claude Code hook'ları
      sıralı tetikleniyor, paralel hook yazımı yok).
    - read_all() bütün dosyayı okur — büyüyen log için Faz 6'da
      streaming versiyonu eklenebilir.
    - Idempotency caller'ın sorumluluğu (gate.advance bunu yönetir);
      lib seviyesinde tekil "log_unique_session" helper'ı opsiyoneldir.

Disiplin #4 — audit signature:
    `asama-N-complete` (ve `-end`) audit'leri detail'inde
    `signature=<hex8> summary=<1 cümle>` taşır. has_signature() bunu
    doğrular; stop.py imza eksikse `audit-signature-missing` warn yazar.
"""

from __future__ import annotations

import os
import re
import time
from pathlib import Path
from typing import Optional

_TIMESTAMP_FMT = "%Y-%m-%dT%H:%M:%SZ"
_LINE_SEP = " | "
_PHASE_COMPLETE_RE = re.compile(r"^asama-\d+-(complete|end)$")
_PHASE_FINISHED_RE = re.compile(
    r"^asama-\d+-(complete|end|skipped|not-applicable)$"
)
_PHASE_AUDIT_RE = re.compile(r"^asama-(\d+)-")


def _audit_dir(project_root: str | None = None) -> Path:
    root = Path(project_root or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    return root / ".mycl"


def audit_path(project_root: str | None = None) -> Path:
    return _audit_dir(project_root) / "audit.log"


def _now_utc() -> str:
    return time.strftime(_TIMESTAMP_FMT, time.gmtime())


def log_event(
    name: str,
    caller: str,
    detail: str = "",
    project_root: str | None = None,
) -> None:
    """audit.log'a tek satır append.

    Format: `<UTC> | <name> | <caller> | <detail>`. Boş detail boş kalır.
    """
    if not name or _LINE_SEP in name:
        raise ValueError(f"event name geçersiz: {name!r}")
    if not caller or _LINE_SEP in caller:
        raise ValueError(f"caller geçersiz: {caller!r}")
    # detail içinde " | " geçebilir mi? Geçerse parse() yanılır.
    # 1.0.0'da detail içinde pipe karakteri yasak — caller temiz tutsun.
    if _LINE_SEP in detail:
        raise ValueError(f"detail içinde ' | ' yasak: {detail!r}")
    p = audit_path(project_root)
    p.parent.mkdir(parents=True, exist_ok=True)
    line = f"{_now_utc()}{_LINE_SEP}{name}{_LINE_SEP}{caller}{_LINE_SEP}{detail}\n"
    with p.open("a", encoding="utf-8") as f:
        f.write(line)


def parse_line(line: str) -> Optional[dict[str, str]]:
    """Tek satır → dict; format dışı satır → None.

    Trailing newline temizlenir; boş satır None döner.
    """
    line = line.rstrip("\n")
    if not line:
        return None
    parts = line.split(_LINE_SEP, 3)
    if len(parts) != 4:
        return None
    return {
        "ts": parts[0],
        "name": parts[1],
        "caller": parts[2],
        "detail": parts[3],
    }


def read_all(project_root: str | None = None) -> list[dict[str, str]]:
    """Tüm audit'leri parse edip döndür. Bozuk satırlar atlanır."""
    p = audit_path(project_root)
    if not p.exists():
        return []
    out: list[dict[str, str]] = []
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        ev = parse_line(line)
        if ev is not None:
            out.append(ev)
    return out


def has(name: str, project_root: str | None = None) -> bool:
    """Belirli event tam isimle var mı?"""
    for ev in read_all(project_root):
        if ev["name"] == name:
            return True
    return False


def find(
    name: str | None = None,
    name_prefix: str | None = None,
    caller: str | None = None,
    project_root: str | None = None,
) -> list[dict[str, str]]:
    """Filtreli kayıt listesi (kronolojik sıralı)."""
    out: list[dict[str, str]] = []
    for ev in read_all(project_root):
        if name is not None and ev["name"] != name:
            continue
        if name_prefix is not None and not ev["name"].startswith(name_prefix):
            continue
        if caller is not None and ev["caller"] != caller:
            continue
        out.append(ev)
    return out


def latest(name: str, project_root: str | None = None) -> Optional[dict[str, str]]:
    """En son `name` event'i (yoksa None)."""
    matches = find(name=name, project_root=project_root)
    return matches[-1] if matches else None


# ---------- Disiplin #4: audit signature ----------


def is_phase_complete(name: str) -> bool:
    """Audit ismi *kesin* faz-tamamlama mı (complete veya end)?

    Disiplin #4 imza zorunluluğu BU iki forma uygulanır.
    Skip / not-applicable bu fonksiyonda False döner.
    """
    return _PHASE_COMPLETE_RE.match(name) is not None


def is_phase_finished(name: str) -> bool:
    """Audit ismi *herhangi bir* faz-bitiş formu mu?

    `gate.advance()` bunu kullanır — pseudocode'da bir faz şu 4 durumda
    sona erebilir: complete, end, skipped, not-applicable. Hepsi
    "sıradaki faza geç" sinyali.

    Örnek:
        asama-5-skipped reason=greenfield → True (gate ilerler)
        asama-8-not-applicable             → True (gate ilerler)
        asama-9-ac-1-red                   → False (TDD ara adımı)
        precision-audit                    → False (faz-bitiş değil)
    """
    return _PHASE_FINISHED_RE.match(name) is not None


def phase_number(name: str) -> Optional[int]:
    """Audit'ten faz numarası çıkar (asama-N-... → N)."""
    m = _PHASE_AUDIT_RE.match(name)
    return int(m.group(1)) if m else None


def has_signature(detail: str) -> bool:
    """detail içinde `signature=<hex>` ve `summary=<...>` ikisi de var mı?

    Disiplin #4: `asama-N-complete` audit'leri imza + 1 cümle özet
    taşımalı. Stop hook imzasız audit'i tespit edip
    `audit-signature-missing` warn yazar.
    """
    return "signature=" in detail and "summary=" in detail


def log_event_signed(
    name: str,
    caller: str,
    signature: str,
    summary: str,
    extra_detail: str = "",
    project_root: str | None = None,
) -> None:
    """Faz-tamamlama audit'leri için imzalı yazım yardımcısı.

    Format: `signature=<sig> summary=<summary>` (+ opsiyonel extra_detail).
    summary içinde " | " yasak (parse() bozulur).
    """
    if "summary=" in summary or "signature=" in summary:
        raise ValueError("summary key fragment'i içeremez")
    parts = [f"signature={signature}", f'summary="{summary}"']
    if extra_detail:
        parts.append(extra_detail)
    detail = " ".join(parts)
    log_event(name, caller, detail, project_root=project_root)
