"""state — `.mycl/state.json` okuma/yazma, format auth.

Pseudocode referansı: MyCL_Pseudocode.md §2 (kancalar arası iletişim
state üzerinden) + §5 (Layer B aktif faz state'ten türetilir).

Sözleşme:
    - state.json proje köküne `.mycl/state.json` yolunda durur.
    - Read/write atomik (tmp + rename).
    - Format auth: `current_phase ∈ [1, 22]`, `spec_hash` ya `None`
      ya 64-char hex SHA256, `spec_approved` bool, `spec_must_list`
      list, `schema_version` int.
    - Format dışı değer reject — hook iç çağrılarında bile yanlış
      yazım engellenir.
    - Bash kanalından mutate yasak — bu yasak `pre_tool.py`'de
      enforce edilir (Bash'ten `state.set_field` / `state.update` /
      `state.reset` çağrıları DENY).

İnvariant:
    `current_phase` sıralı ilerletilir; her transition tam bir artış.
    Doğrudan setter'lar (1→4 atlama) yasak (CLAUDE.md kuralı).
"""

from __future__ import annotations

import json
import os
import re
import tempfile
import time
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 3

_DEFAULT_STATE: dict[str, Any] = {
    "schema_version": SCHEMA_VERSION,
    "current_phase": 1,
    "phase_name": "GATHER",
    "spec_approved": False,
    "spec_hash": None,
    "spec_must_list": [],
    "plugin_gate_active": False,
    "plugin_gate_missing": [],
    "ui_flow_active": False,
    "ui_sub_phase": None,
    "ui_build_hash": None,
    "ui_reviewed": False,
    "scope_paths": [],
    "pattern_scan_due": False,
    "pattern_files": [],
    "pattern_summary": None,
    "pattern_level": None,
    "pattern_ask_pending": False,
    "precision_audit_done": False,
    "risk_review_state": None,
    "quality_review_state": None,
    "open_severity_count": 0,
    "tdd_compliance_score": None,
    "rollback_sha": None,
    "rollback_notice_shown": False,
    "tdd_last_green": None,
    "last_write_ts": None,
    "plan_critique_done": False,
    "restart_turn_ts": None,
    "git_init_consent": None,
    "partial_spec": False,
    "partial_spec_body_sha": None,
    "regression_block_active": False,
    "regression_output": "",
    "last_update": 0,
}

_VALID_PHASES = set(range(1, 23))
_HEX64_RE = re.compile(r"^[0-9a-f]{64}$")


class StateValidationError(ValueError):
    """state.json formatı bozuk — yazma reject."""


def _state_dir(project_root: str | None = None) -> Path:
    """`.mycl/` dizini, proje kökünde."""
    root = Path(project_root or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    return root / ".mycl"


def state_path(project_root: str | None = None) -> Path:
    """state.json tam yolu."""
    return _state_dir(project_root) / "state.json"


def _validate(data: dict[str, Any]) -> None:
    """Format auth — yazmadan önce çağrılır.

    Plan kararı (v1.0.0): geçersiz değer yazılmaz. Bash kanalından
    sahte değerler (örn. `state.set_field("spec_hash", "backoffice-v1")`
    benzeri çağrı) hook iç çağrılarında bile reject edilir (defense
    in depth — v13.1.3 öğrenimi).
    """
    cp = data.get("current_phase")
    if cp not in _VALID_PHASES:
        raise StateValidationError(
            f"current_phase {cp!r} geçersiz; 1-22 aralığı olmalı"
        )

    sh = data.get("spec_hash")
    if sh is not None and not (isinstance(sh, str) and _HEX64_RE.match(sh)):
        raise StateValidationError(
            f"spec_hash {sh!r} geçersiz; None veya 64-char hex SHA256 olmalı"
        )

    sa = data.get("spec_approved")
    if not isinstance(sa, bool):
        raise StateValidationError(
            f"spec_approved {sa!r} geçersiz; bool olmalı"
        )

    smust = data.get("spec_must_list")
    if not isinstance(smust, list):
        raise StateValidationError(
            f"spec_must_list {smust!r} geçersiz; list olmalı"
        )

    sv = data.get("schema_version")
    if not isinstance(sv, int) or sv < 1:
        raise StateValidationError(
            f"schema_version {sv!r} geçersiz; pozitif int olmalı"
        )


def read(project_root: str | None = None) -> dict[str, Any]:
    """state.json oku; yoksa default ile init et."""
    p = state_path(project_root)
    if not p.exists():
        return dict(_DEFAULT_STATE)
    try:
        with p.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        # Bozuk dosya — default'a dön. Eski sürüm corruption'ı silmemek
        # için yeni default yazılmaz; hook çağıranı karar verir.
        return dict(_DEFAULT_STATE)
    if not isinstance(data, dict):
        return dict(_DEFAULT_STATE)
    # Eksik alanları default ile doldur (forward-compat).
    merged = dict(_DEFAULT_STATE)
    merged.update(data)
    return merged


def get(field: str, default: Any = None, project_root: str | None = None) -> Any:
    """Tek alan oku."""
    return read(project_root).get(field, default)


def _write_atomic(data: dict[str, Any], project_root: str | None = None) -> None:
    """Tmp + os.replace ile atomik yazım."""
    p = state_path(project_root)
    p.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".state.", suffix=".tmp", dir=str(p.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, p)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def set_field(
    field: str, value: Any, project_root: str | None = None
) -> dict[str, Any]:
    """Tek alanı güncelle.

    İnvariant: format auth her yazımda; sıralılık enforce **edilmez**
    (gate.advance() bu yazımı düzgün sıralı yapar; düşük seviye state
    sadece field-level format'ı doğrular).
    """
    data = read(project_root)
    data[field] = value
    data["last_update"] = int(time.time())
    _validate(data)
    _write_atomic(data, project_root)
    return data


def update(patch: dict[str, Any], project_root: str | None = None) -> dict[str, Any]:
    """Birden fazla alanı tek yazımla güncelle.

    Atomik — ya hepsi yazılır ya hiçbiri.
    """
    data = read(project_root)
    data.update(patch)
    data["last_update"] = int(time.time())
    _validate(data)
    _write_atomic(data, project_root)
    return data


def reset(project_root: str | None = None) -> dict[str, Any]:
    """state.json'u default'a döndür.

    Yalnızca `/mycl-restart` benzeri kullanıcı-tetikli reset'ler için.
    Bash kanalından çağrı pre_tool.py'de zaten yasak.
    """
    data = dict(_DEFAULT_STATE)
    data["last_update"] = int(time.time())
    _validate(data)
    _write_atomic(data, project_root)
    return data
