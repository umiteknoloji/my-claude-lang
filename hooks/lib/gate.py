"""gate — Layer B: aktif faz türetimi + allowed_tools/denied_paths kontrol.

Pseudocode referansı: MyCL_Pseudocode.md §2 PreToolUse + §5 Layer B
fail-closed allowlist + Disiplin #12 (cooldown after deny).

Layer B sözleşmesi (CLAUDE.md "MyCL design principles"):
    - Her tool çağrısı önce `_global_always_allowed_tools` listesi
      (Read/Glob/Grep/LS/WebFetch/WebSearch/Task/Skill/TodoWrite) ile
      karşılaştırılır — bunlar her fazda izinli (araştırma valve).
    - Mutating tool (Write/Edit/Bash/...) için aktif fazın
      `allowed_tools` listesi okunur. Yoksa: deny (fail-closed).
    - file_path verilmişse fazın `denied_paths` glob'larıyla
      karşılaştırılır.
    - STRICT mode: hiçbir gate otomatik açılmaz. 5 strike sonra
      `*-escalation-needed` audit yazılır (visible signal); block
      KALMAZ.

Aktif faz türetimi (1.0.0):
    Yeni proje (clean slate) → state.current_phase güvenilir.
    Eski v13.x'te legacy 7 sentinel vardı; 1.0.0'da yok. Audit-driven
    resolver defense-in-depth olarak 1.0.x'te eklenebilir.

Advance sözleşmesi:
    `current_phase` tam olarak +1 ilerletilir (CLAUDE.md sequence
    invariantı). 22'de durur. audit + trace yan-etkileri.

API:
    load_gate_spec(path=None)        — JSON yükle (cache)
    active_phase(project_root)       — aktif faz int
    evaluate(tool, file_path, ...)   → (allowed: bool, reason: str)
    advance(project_root)            — N → N+1
    deny_count_in_session(event)     — strike sayımı (Disiplin #12 helper)
    path_matches_glob(path, pattern) — glob match utility
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from hooks.lib import audit, state, trace

# Process-global cache (test'lerde explicit gate_spec=... ile bypass)
_gate_spec_cache: dict | None = None

_DEFAULT_EMPTY_SPEC: dict = {
    "_global_always_allowed_tools": [],
    "phases": {},
}


def _data_dir_candidates() -> list[Path]:
    return [
        Path.home() / ".claude" / "data",
        Path(__file__).resolve().parent.parent.parent / "data",
    ]


def load_gate_spec(path: str | Path | None = None) -> dict:
    """gate_spec.json yükle. path verilmezse data dizini ara."""
    global _gate_spec_cache
    if path is None and _gate_spec_cache is not None:
        return _gate_spec_cache

    if path is not None:
        p: Path | None = Path(path)
    else:
        p = None
        for c in _data_dir_candidates():
            cand = c / "gate_spec.json"
            if cand.exists():
                p = cand
                break

    if p is None or not p.exists():
        return _DEFAULT_EMPTY_SPEC

    try:
        with p.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return _DEFAULT_EMPTY_SPEC

    if path is None:
        _gate_spec_cache = data
    return data


def reset_cache() -> None:
    global _gate_spec_cache
    _gate_spec_cache = None


# ---------- aktif faz ----------


def active_phase(project_root: str | None = None) -> int:
    """state.current_phase'den aktif faz int. 1-22 aralığı; geçersiz → 1.

    1.0.0'da audit-driven derivation yok (clean slate). Gerek olursa
    1.0.x'te eklenir (state legacy değer tutarsa audit chain'den
    türet — pseudocode §5 audit-driven resolver).
    """
    cp = state.get("current_phase", 1, project_root=project_root)
    try:
        n = int(cp)
        return n if 1 <= n <= 22 else 1
    except (TypeError, ValueError):
        return 1


def next_phase(current: int) -> int:
    """N → N+1 (22'de durur)."""
    if current >= 22:
        return 22
    return current + 1


# ---------- glob match ----------


def _glob_to_regex(pattern: str) -> str:
    """`src/api/**` → recursive regex; `*` → tek seviye."""
    re_pat = ""
    i = 0
    while i < len(pattern):
        if pattern[i:i + 2] == "**":
            re_pat += ".*"
            i += 2
        elif pattern[i] == "*":
            re_pat += "[^/]*"
            i += 1
        elif pattern[i] == "?":
            re_pat += "."
            i += 1
        else:
            re_pat += re.escape(pattern[i])
            i += 1
    return re_pat


def path_matches_glob(path: str, pattern: str) -> bool:
    """path glob pattern'e uyuyor mu? Tam eşleşme (re.fullmatch)."""
    if not path or not pattern:
        return False
    return re.fullmatch(_glob_to_regex(pattern), path) is not None


# ---------- evaluate ----------


def evaluate(
    tool: str,
    file_path: str | None = None,
    project_root: str | None = None,
    gate_spec: dict | None = None,
) -> tuple[bool, str]:
    """Bir tool çağrısı Layer B'ye göre izinli mi?

    Returns:
        (allowed, reason). reason boş string ise allowed=True.
    """
    if not tool:
        return False, "tool ismi boş"

    spec = gate_spec if gate_spec is not None else load_gate_spec()

    # 1. Global always-allowed (read-only valve)
    global_tools = spec.get("_global_always_allowed_tools", [])
    if isinstance(global_tools, list) and tool in global_tools:
        return True, ""

    # 2. Aktif faz allowed_tools
    phase = active_phase(project_root=project_root)
    phase_def = spec.get("phases", {}).get(str(phase), {})
    if not phase_def:
        # gate_spec'te faz tanımı yok — fail-closed (mutating deny).
        return False, f"Aşama {phase} için gate tanımı yok (fail-closed)"

    allowed = phase_def.get("allowed_tools", [])
    if not isinstance(allowed, list) or tool not in allowed:
        phase_name = phase_def.get("name", "")
        return False, f"Aşama {phase} ({phase_name})'de `{tool}` izinli değil"

    # 3. denied_paths kontrol (file_path verildiyse)
    if file_path:
        denied = phase_def.get("denied_paths", [])
        if isinstance(denied, list):
            for pattern in denied:
                if isinstance(pattern, str) and path_matches_glob(file_path, pattern):
                    phase_name = phase_def.get("name", "")
                    return (
                        False,
                        f"Aşama {phase} ({phase_name})'de yol yasak: `{file_path}` ↔ `{pattern}`",
                    )

    return True, ""


# ---------- advance ----------


def advance(
    project_root: str | None = None,
    caller: str = "gate",
) -> int:
    """Aktif fazı +1 ilerlet. Sequential invariant.

    Yan etkiler:
        - state.current_phase = N+1 (state.set_field)
        - audit: `phase-advance` (caller=`gate`, detail=`from=N to=N+1`)
        - trace: `phase_transition` (`N->N+1`)

    Returns:
        Yeni current_phase (22'de aynı kalır, no-op).
    """
    cp = active_phase(project_root=project_root)
    if cp >= 22:
        # Son fazda; pipeline tamamlanmış, no-op.
        return 22
    nxt = cp + 1
    state.set_field("current_phase", nxt, project_root=project_root)
    # phase_name'i de güncelle (pseudocode'a uyumlu, basit string).
    state.set_field("phase_name", _phase_name_for(nxt), project_root=project_root)
    audit.log_event(
        "phase-advance",
        caller,
        f"from={cp} to={nxt}",
        project_root=project_root,
    )
    trace.phase_transition(cp, nxt, project_root=project_root)
    return nxt


def _phase_name_for(phase: int) -> str:
    """gate_spec'ten faz adı (geriye dönük uyum için string'leştirilmiş)."""
    spec = load_gate_spec()
    phase_def = spec.get("phases", {}).get(str(phase), {})
    name = phase_def.get("name_en") or phase_def.get("name") or "PHASE"
    # Sade ID-friendly form (uppercase + underscore)
    return re.sub(r"[^A-Z0-9_]+", "_", name.upper()).strip("_") or "PHASE"


# ---------- cooldown / strike helper (Disiplin #12) ----------


def deny_count_in_session(
    event_kind: str,
    project_root: str | None = None,
) -> int:
    """Bu session'da belirli bir block audit kaç kez yazılmış?

    Pre_tool.py 5-strike escalation eşiği için kullanır:
        count = gate.deny_count_in_session("spec-approval-block")
        if count + 1 >= 5:
            audit.log_event("spec-approval-block-escalation-needed", ...)

    1.0.0'da "session" basit anlamda — `phase-advance` veya
    `session_start` event'inden sonra (varsa). Şimdi tüm audit'leri
    sayar; session boundary refinement 1.0.x'te eklenir.
    """
    if not event_kind:
        return 0
    matches = audit.find(name=event_kind, project_root=project_root)
    return len(matches)


def has_recent_deny(
    event_kind: str,
    within: int = 1,
    project_root: str | None = None,
) -> bool:
    """Son `within` audit'i içinde aynı `event_kind` deny var mı?

    Cooldown after deny (Disiplin #12) basit form: önceki tool çağrısı
    aynı sebeple deny edildiyse, aynı çağrıyı tekrar deniyorsa cooldown'da.
    Pre_tool bu helper'ı çağırıp tekrar denyleri bilinçli bypass olarak
    yorumlar.
    """
    if not event_kind or within < 1:
        return False
    all_audits = audit.read_all(project_root=project_root)
    if not all_audits:
        return False
    tail = all_audits[-within:]
    return any(ev["name"] == event_kind for ev in tail)
