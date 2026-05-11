"""orchestrator — MyCL multi-agent pipeline orkestrasyon yardımcıları.

Mimari (Plan onayı: senkron sıralı multi-agent):
    - Hook (deterministic): state/audit/gate sahibi; DSI directive ile
      model'i yönlendirir ("şimdi Aşama N için mycl-phase-runner çağır").
    - Model (cooperative): directive'i izler, Task tool ile subagent
      çağırır, subagent text döner.
    - Hook subagent output'unu transcript'ten okur (tool_result),
      parse eder, state'i ilerletir.

Bu modül utility'ler sağlar — gerçek subagent çağrısı Task tool
üzerinden model tarafında yapılır (hook'tan değil).

API:
    read_skill(phase_n) → str
    build_subagent_prompt(phase_n, skill_content, state, prior_output) → str
    parse_phase_output(text) → ParsedOutput
    is_orchestration_enabled(phase_n) → bool
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any

from hooks.lib import gate

_SKILL_DIR = Path(__file__).resolve().parent.parent.parent / "skills" / "mycl"


class PhaseOutcome(Enum):
    COMPLETE = "complete"
    SKIPPED = "skipped"
    PENDING = "pending"
    ERROR = "error"


@dataclass
class ParsedOutput:
    """Subagent çıktısının parse sonucu."""
    outcome: PhaseOutcome
    summary: str = ""
    reason: str = ""
    detail: str = ""
    question: str = ""
    raw: str = ""


_OUTPUT_RE = {
    PhaseOutcome.COMPLETE: re.compile(r"^complete:\s*(.+)$", re.IGNORECASE),
    PhaseOutcome.SKIPPED: re.compile(
        r"^skipped\s+reason=(\S+):\s*(.+)$", re.IGNORECASE,
    ),
    PhaseOutcome.PENDING: re.compile(r"^pending:\s*(.+)$", re.IGNORECASE),
    PhaseOutcome.ERROR: re.compile(r"^error:\s*(.+)$", re.IGNORECASE),
}


def read_skill(phase_n: int) -> str:
    """skills/mycl/asama{N:02d}-*.md içeriği (frontmatter hariç).

    Returns: skill body (TR + EN). Bulunamazsa FileNotFoundError.
    """
    pattern = f"asama{phase_n:02d}-*.md"
    candidates = list(_SKILL_DIR.glob(pattern))
    if not candidates:
        raise FileNotFoundError(f"skill bulunamadı: {pattern}")
    text = candidates[0].read_text(encoding="utf-8")
    parts = text.split("---", 2)
    return parts[2].strip() if len(parts) >= 3 else text


def build_subagent_prompt(
    phase_n: int,
    skill_content: str,
    state_snapshot: dict[str, Any],
    prior_output: str = "none",
) -> str:
    """mycl-phase-runner subagent'ı için tam prompt."""
    cp = state_snapshot.get("current_phase", phase_n)
    must_list = state_snapshot.get("spec_must_list", [])
    pattern = state_snapshot.get("pattern_summary", "n/a")
    return (
        f"You are executing MyCL Phase {phase_n}.\n\n"
        f"=== Phase skill (TR + EN) ===\n\n"
        f"{skill_content}\n\n"
        f"=== Prior phase output ===\n\n"
        f"{prior_output}\n\n"
        f"=== State snapshot ===\n\n"
        f"current_phase: {cp}\n"
        f"spec_must_list: {must_list}\n"
        f"pattern_summary: {pattern}\n\n"
        f"=== Output contract ===\n\n"
        f"Return exactly one final line:\n"
        f"- complete: <summary>\n"
        f"- skipped reason=<token>: <detail>\n"
        f"- pending: <question>\n"
        f"- error: <description>\n\n"
        f"Tools allowed: Read, Glob, Grep, AskUserQuestion. "
        f"No Write/Edit/Bash.\n"
    )


def parse_phase_output(text: str) -> ParsedOutput:
    """Subagent çıktısının son anlamlı satırını parse et.

    Beklenen format:
        complete: <summary>
        skipped reason=<token>: <detail>
        pending: <question>
        error: <description>

    Non-conforming çıktı → outcome=ERROR (orchestrator STRICT block).
    """
    if not text or not text.strip():
        return ParsedOutput(
            outcome=PhaseOutcome.ERROR, detail="empty output", raw=text,
        )
    lines = [ln.strip() for ln in text.strip().splitlines() if ln.strip()]
    if not lines:
        return ParsedOutput(
            outcome=PhaseOutcome.ERROR, detail="no non-empty lines", raw=text,
        )
    last = lines[-1]

    for outcome, pattern in _OUTPUT_RE.items():
        m = pattern.match(last)
        if not m:
            continue
        if outcome == PhaseOutcome.COMPLETE:
            return ParsedOutput(
                outcome=outcome, summary=m.group(1).strip(), raw=text,
            )
        if outcome == PhaseOutcome.SKIPPED:
            return ParsedOutput(
                outcome=outcome,
                reason=m.group(1).strip(),
                detail=m.group(2).strip(),
                raw=text,
            )
        if outcome == PhaseOutcome.PENDING:
            return ParsedOutput(
                outcome=outcome, question=m.group(1).strip(), raw=text,
            )
        if outcome == PhaseOutcome.ERROR:
            return ParsedOutput(
                outcome=outcome, detail=m.group(1).strip(), raw=text,
            )

    return ParsedOutput(
        outcome=PhaseOutcome.ERROR,
        detail=f"unparseable line: {last[:80]}",
        raw=text,
    )


def is_orchestration_enabled(phase_n: int) -> bool:
    """Aşama N'de subagent_orchestration flag açık mı (gate_spec)."""
    spec = gate.load_gate_spec()
    phase_def = spec.get("phases", {}).get(str(phase_n), {})
    return bool(phase_def.get("subagent_orchestration"))
