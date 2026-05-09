"""commitment — Pre-commitment beyanı + Public commitment list.

Pseudocode + CLAUDE.md disiplin katmanı #1 (pre-commitment) + #3
(public commitment list).

Sözleşme:
    - Tur başında activate.py model'den `pre_commitment_prompt(phase)`
      ile söz alır (1 satır + 2-3 cümle plan).
    - `record_pre_commitment(text, phase)` audit'e yazar
      (`pre-commitment-stated phase=N text="..."`).
    - Faz başında `public_commitment_open(phase)` model'in bullet
      list ile söz vermesi için prompt verir.
    - Faz sonunda `public_commitment_close(phase, count)` söz/sonuç
      eşleşme prompt'u.
    - Stop hook tur sonunda söz tutuldu mu denetler →
      `record_commitment_kept(phase, kept)`.

Audit-driven: state'te ekstra alan yok; tüm tracking audit log'da.

Format şablonları `data/commitment_template.json` okur (askq.py /
bilingual.py pattern). Faza özel prompt'lar
`phase_specific_templates[<phase>]` altında.

API:
    pre_commitment_prompt(phase, **kwargs)        → "TR\\n\\nEN"
    public_commitment_open(phase, **kwargs)       → "TR\\n\\nEN"
    public_commitment_close(phase, count, **kw)   → "TR\\n\\nEN"
    phase_specific_items(phase) → [{tr_items, en_items}] | None
    record_pre_commitment(text, phase, ...)
    record_commitment_kept(phase, kept, ...)
    latest_pre_commitment(phase, ...) → text | None
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import audit

_template_cache: dict | None = None
_DEFAULT_EMPTY: dict = {
    "pre_commitment": {"tr": "", "en": ""},
    "public_commitment_list_open": {"tr": "", "en": ""},
    "public_commitment_list_close": {"tr": "", "en": ""},
    "phase_specific_templates": {},
}


def _data_dir_candidates() -> list[Path]:
    return [
        Path.home() / ".claude" / "data",
        Path(__file__).resolve().parent.parent.parent / "data",
    ]


def load_template(path: str | Path | None = None) -> dict:
    """commitment_template.json yükle (cache)."""
    global _template_cache
    if path is None and _template_cache is not None:
        return _template_cache

    if path is not None:
        p: Path | None = Path(path)
    else:
        p = None
        for c in _data_dir_candidates():
            cand = c / "commitment_template.json"
            if cand.exists():
                p = cand
                break

    if p is None or not p.exists():
        return _DEFAULT_EMPTY

    try:
        with p.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return _DEFAULT_EMPTY

    if not isinstance(data, dict):
        return _DEFAULT_EMPTY

    if path is None:
        _template_cache = data
    return data


def reset_cache() -> None:
    global _template_cache
    _template_cache = None


def _render_block(entry: dict, **kwargs) -> str:
    """{tr, en} sözlüğü → 'TR\\n\\nEN' (eksik dil → mevcut)."""
    tr = entry.get("tr", "") or ""
    en = entry.get("en", "") or ""
    try:
        tr = tr.format(**kwargs)
    except (KeyError, IndexError, ValueError):
        pass
    try:
        en = en.format(**kwargs)
    except (KeyError, IndexError, ValueError):
        pass
    if tr and en:
        return f"{tr}\n\n{en}"
    return tr or en


# ---------- promptlar ----------


def pre_commitment_prompt(
    phase: int,
    phase_name: str = "",
    template: dict | None = None,
) -> str:
    """Tur başı pre-commitment isteği (TR + EN)."""
    tpl = template if template is not None else load_template()
    entry = tpl.get("pre_commitment", {})
    if not isinstance(entry, dict):
        return ""
    return _render_block(entry, phase=phase, phase_name=phase_name)


def public_commitment_open(
    phase: int,
    phase_name: str = "",
    template: dict | None = None,
) -> str:
    """Faz başı public commitment list açma."""
    tpl = template if template is not None else load_template()
    entry = tpl.get("public_commitment_list_open", {})
    if not isinstance(entry, dict):
        return ""
    return _render_block(entry, phase=phase, phase_name=phase_name)


def public_commitment_close(
    phase: int,
    count: int,
    phase_name: str = "",
    template: dict | None = None,
) -> str:
    """Faz sonu public commitment kapatma (söz/sonuç eşleşme)."""
    tpl = template if template is not None else load_template()
    entry = tpl.get("public_commitment_list_close", {})
    if not isinstance(entry, dict):
        return ""
    return _render_block(
        entry, phase=phase, phase_name=phase_name, count=count
    )


def phase_specific_items(
    phase: int,
    template: dict | None = None,
) -> dict | None:
    """Faza özel `tr_items` + `en_items` listesi (yoksa None)."""
    tpl = template if template is not None else load_template()
    pst = tpl.get("phase_specific_templates", {})
    if not isinstance(pst, dict):
        return None
    entry = pst.get(str(phase))
    if not isinstance(entry, dict):
        return None
    return {
        "tr_items": entry.get("tr_items", []) if isinstance(entry.get("tr_items"), list) else [],
        "en_items": entry.get("en_items", []) if isinstance(entry.get("en_items"), list) else [],
    }


# ---------- audit kayıtları ----------


def record_pre_commitment(
    text: str,
    phase: int,
    caller: str = "activate.py",
    project_root: str | None = None,
) -> None:
    """Model'in pre-commitment söz metnini audit'e yaz.

    detail format: `phase=N text="<truncated>"` (200 char max).
    """
    if not text:
        return
    truncated = text.strip().replace("\n", " ")
    if len(truncated) > 200:
        truncated = truncated[:197] + "..."
    # Audit detail içinde " | " yasak; ek koruma
    truncated = truncated.replace(" | ", " / ")
    audit.log_event(
        "pre-commitment-stated",
        caller,
        f'phase={phase} text="{truncated}"',
        project_root=project_root,
    )


def record_commitment_kept(
    phase: int,
    kept: bool,
    caller: str = "stop.py",
    project_root: str | None = None,
) -> None:
    """Faz sonunda söz tutuldu mu denetimi audit'e yaz."""
    audit.log_event(
        "commitment-tracked",
        caller,
        f"phase={phase} kept={'true' if kept else 'false'}",
        project_root=project_root,
    )


def latest_pre_commitment(
    phase: int,
    project_root: str | None = None,
) -> str | None:
    """Bu fazın son pre-commitment audit text'i (yoksa None)."""
    matches = audit.find(
        name="pre-commitment-stated",
        project_root=project_root,
    )
    target = f"phase={phase}"
    for ev in reversed(matches):
        if target in ev.get("detail", ""):
            return ev["detail"]
    return None
