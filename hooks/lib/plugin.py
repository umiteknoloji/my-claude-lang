"""plugin — Plugin Kural A/B/C orkestrasyonu.

Pseudocode referansı: MyCL_Pseudocode.md §5 Plugin Orkestrasyon
+ CLAUDE.md captured-rules (Kural A/B/C).

**Kural A — Yerel git deposu güvencesi:**
    Her MyCL-yönetimli projede `.git/` olmalı. İlk aktivasyonda git
    deposu yoksa, geliştiriciye dilinde tek kez "MyCL `git init`
    çalıştırsın mı?" sorulur. Onay `.mycl/config.json`'a kalıcı yazılır.
    Aynı projede tekrar sorulmaz.

**Kural B — Curated plugin dispatch:**
    Curated plugin set (feature-dev, code-review, pr-review-toolkit,
    security-guidance) MyCL fazıyla örtüşse bile sessizce çağrılır.
    Çatışma → Aşama 10 risk maddesi (provenance + her iki gerekçe +
    AskUserQuestion). Otomatik tiebreaker yok.

**Kural C — MCP-server plugin yasağı:**
    Kaynak ağacında `.mcp.json` bulunan plugin curated setten elenir.
    Binary CLI araçları (semgrep, linters, formatters) MCP değildir
    ve izinlidir.

Sözleşme:
    - config.json `.mycl/config.json` — kalıcı project-level konfig
      (state.json'dan farklı: state session-level, config kalıcı).
    - state.py'den `git_init_consent` kaldırıldı; plugin.py kanonik.
    - Atomik write (tmp + os.replace).
"""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

# Kural B: curated plugin set (sabit, 1.0.0 çekirdek)
CURATED_PLUGINS: tuple[str, ...] = (
    "feature-dev",
    "code-review",
    "pr-review-toolkit",
    "security-guidance",
)

# Geçerli git_init_consent değerleri
_VALID_CONSENT = {"approved", "declined"}


_DEFAULT_CONFIG: dict[str, Any] = {
    "git_init_consent": None,  # None | "approved" | "declined"
    "plugin_choices": {},
}


# ---------- config.json read/write ----------


def _config_dir(project_root: str | None = None) -> Path:
    root = Path(project_root or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    return root / ".mycl"


def config_path(project_root: str | None = None) -> Path:
    return _config_dir(project_root) / "config.json"


def read_config(project_root: str | None = None) -> dict[str, Any]:
    """config.json oku; yoksa default."""
    p = config_path(project_root)
    if not p.exists():
        return dict(_DEFAULT_CONFIG)
    try:
        with p.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return dict(_DEFAULT_CONFIG)
    if not isinstance(data, dict):
        return dict(_DEFAULT_CONFIG)
    merged = dict(_DEFAULT_CONFIG)
    merged.update(data)
    return merged


def _write_config_atomic(
    data: dict[str, Any], project_root: str | None = None
) -> None:
    p = config_path(project_root)
    p.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".config.", suffix=".tmp", dir=str(p.parent))
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


def set_config_field(
    field: str, value: Any, project_root: str | None = None
) -> dict[str, Any]:
    """config.json'a tek alan yaz. Atomik."""
    data = read_config(project_root)
    data[field] = value
    _write_config_atomic(data, project_root)
    return data


# ---------- Kural A: git init consent ----------


def is_git_repo(project_root: str | None = None) -> bool:
    """Project root'ta `.git/` dizini var mı?"""
    root = Path(project_root or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    return (root / ".git").is_dir()


def git_init_consent(project_root: str | None = None) -> str | None:
    """Kaydedilmiş consent kararı: None / 'approved' / 'declined'."""
    return read_config(project_root).get("git_init_consent")


def set_git_init_consent(
    decision: str, project_root: str | None = None
) -> dict[str, Any]:
    """Consent kararı kalıcı yaz."""
    if decision not in _VALID_CONSENT:
        raise ValueError(
            f"Geçersiz git_init_consent: {decision!r}; "
            f"izinli: {sorted(_VALID_CONSENT)}"
        )
    return set_config_field("git_init_consent", decision, project_root=project_root)


def should_ask_git_init_consent(project_root: str | None = None) -> bool:
    """Activate hook bunu sorar: askq açılmalı mı?

    CLAUDE.md Kural A: "tek bir kez sor, kararı kalıcı yaz, asla
    tekrar sorma". Git zaten varsa veya consent zaten kayıtlı ise
    sormaz.
    """
    if is_git_repo(project_root):
        return False
    return git_init_consent(project_root) is None


# ---------- Kural B: curated plugin dispatch ----------


def curated_plugins() -> list[str]:
    """1.0.0 kanonik curated plugin listesi (kopyası)."""
    return list(CURATED_PLUGINS)


def is_plugin_curated(plugin_name: str) -> bool:
    """plugin_name curated set'te mi?"""
    return plugin_name in CURATED_PLUGINS


# ---------- Kural C: MCP-server filter ----------


def is_mcp_plugin(plugin_root: str | Path) -> bool:
    """Plugin source ağacında `.mcp.json` var mı?

    Kaynak ağacında bulunursa plugin MCP-server tabanlı kabul edilir
    → curated set'ten elenir (CLAUDE.md Kural C).
    """
    p = Path(plugin_root)
    return (p / ".mcp.json").exists()


def filter_mcp(plugin_paths: list[str | Path]) -> list[Path]:
    """plugin_paths listesinden MCP-tabanlı olanları çıkar.

    Returns:
        Sadece MCP-OLMAYAN plugin path'lerinin listesi (Path objeleri).
    """
    return [Path(p) for p in plugin_paths if not is_mcp_plugin(p)]
