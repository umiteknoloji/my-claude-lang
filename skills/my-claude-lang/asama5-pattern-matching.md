<mcl_phase name="asama5-pattern-matching">

# Aşama 5: Pattern Matching

Aşama 5 runs AFTER Aşama 4 (spec approved) and BEFORE Aşama 6 (UI
flow) / Aşama 7 (code execution). Goal: extract three project-wide
conventions so Aşama 7 code is consistent with the existing codebase.

## What gets extracted

| Convention | Examples |
|------------|----------|
| **Naming Convention** | camelCase functions, PascalCase types, kebab-case files |
| **Error Handling Pattern** | `Result<T,E>` type vs throw + catch; log at boundary; wrap external calls |
| **Test Pattern** | `describe/it` vs `unittest`; Arrange-Act-Assert; `jest.mock` for external deps |

These three rules become **enforced conventions** for Aşama 7 code
and are checked again as part of Aşama 8 spec compliance.

## 3-Level Fallback (since v9.0.0)

**Level 1 — Real sibling files:** files exist in the same directory
as the planned Aşama 7 writes. Read those, extract patterns directly.

**Level 2 — Project-wide samples:** no siblings, but the project has
existing source files elsewhere. Read project-wide samples, extract
patterns.

**Level 3 — Empty project + stack detected:** no source files yet,
but `mcl-stack-detect.sh` reports a stack tag (typescript, python,
go, etc.). Apply ecosystem standard:

| Stack | Ecosystem standard |
|-------|---------------------|
| typescript | strict (noImplicitAny, strict: true), ESLint recommended, no semicolons optional |
| javascript | Standard (ESLint recommended) |
| python | PEP 8, black formatter, type hints, pytest |
| go | gofmt, errors as values, table-driven tests |
| rust | clippy clean, `Result<T,E>`, `#[cfg(test)]` |
| java | checkstyle, Optional over null, JUnit 5 |
| ruby | rubocop, frozen_string_literal, RSpec |
| php | PSR-12, PHPStan level 5+, PHPUnit |
| csharp | nullable enabled, xUnit, StyleCop |
| kotlin | ktlint, coroutines, JUnit 5 |
| swift | SwiftLint, XCTest, value types preferred |

**Skip path — Empty project + no stack:** Aşama 5 is **skipped
entirely**. Audit entry: `asama-5-skipped | mcl-activate.sh |
reason=empty-project-no-stack`. Aşama 7 proceeds without enforced
patterns; the developer can rule-capture conventions later.

## PATTERN SUMMARY format

After extraction, MCL writes the summary in exactly this format:

```
**PATTERN SUMMARY**
**Naming Convention:** <one concrete rule>
**Error Handling Pattern:** <one concrete rule>
**Test Pattern:** <one concrete rule>
```

Each rule is ONE concrete sentence, no list, no alternatives. If a
pattern is absent or inconsistent in the codebase, write
`[not established]` — do NOT invent.

## State machine

- `pattern_scan_due=true` is set at Aşama 4 exit (spec approved) when
  Aşama 5 should run.
- The first turn after Aşama 4 is **read-only** — Claude reads the
  files specified in PATTERN_MATCHING_NOTICE and writes the PATTERN
  SUMMARY. No file writes allowed (pre-tool block fires on Write/Edit).
- After PATTERN SUMMARY is emitted, Stop hook captures `pattern_summary`
  field with the three rules + sets `pattern_scan_due=false`.
- From the next turn onward, writes unblock and the three rules are
  injected into every Aşama 7 turn via PATTERN_RULES_NOTICE.

## Skip behavior

Aşama 5 is skipped when:
- Project is empty AND no stack detected (Level 4 skip path above).
- The session pre-state already has `pattern_summary` set (carry-over
  from a prior session in the same project — no need to re-scan).

When skipped, `pattern_scan_due` is NOT set, writes are NOT blocked,
and Aşama 6/7 proceed without pattern rules in context.

## Aşama 8 compliance check

Aşama 8 (Risk Review) reads `pattern_summary` from state and verifies
Aşama 7 code follows each of the three rules. Violations become
Aşama 8 risk-dialog turns — developer can apply fix, skip, or
rule-capture (overriding the pattern).

## Anti-patterns

- Inventing patterns not actually present in the codebase. Write
  `[not established]` when uncertain.
- Reading files outside the target directory's siblings unless
  Level 1 found nothing (escalate to Level 2 only).
- Asking the developer "what style?" — the v9.0.0 plan removed the
  ask path. Skip silently or use ecosystem standard.

</mcl_phase>
