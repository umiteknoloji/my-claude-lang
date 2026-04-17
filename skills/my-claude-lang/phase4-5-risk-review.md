# Phase 4.5: Post-Code Risk Review

Phase 4.5 is a **mandatory, sequential, interactive dialog** that runs
AFTER Phase 4 (code is written) and BEFORE Phase 5 (Verification Report).
Introduced in MCL 5.3.0.

## Why Phase 4.5 Exists

In MCL 5.2.0 and earlier, Missed Risks was the last section of the
Phase 5 Verification Report — which meant the report was emitted BEFORE
the developer had a chance to act on the risks. If the developer then
asked for a fix, the report's Impact Analysis and must-test list were
already stale.

Phase 4.5 fixes this: risks are reviewed **first**, the developer's
decisions (skip / apply fix / make general rule) are applied, and only
THEN does Phase 5 emit a report that reflects reality.

## When Phase 4.5 Runs

Immediately after Phase 4 finishes writing code. Phase 4 does NOT end
with "done" or a changes summary — it hands off to Phase 4.5.

## The Dialog Structure

Phase 4.5 is NOT a one-shot list. It is a **sequential, one-risk-per-turn
conversation**. For each risk MCL surfaces:

1. MCL presents **one** risk with a short explanation of why it matters
   (security / data integrity / performance / regression / UX / etc.)
2. MCL presents the developer's options:
   - Skip — accept the risk as-is
   - Apply a specific fix — MCL implements the fix before moving on
   - Make this a general rule — triggers Rule Capture (see `rule-capture.md`)
3. MCL STOPS and waits for the developer's reply **in the next message**
4. On reply: execute the chosen action, then present the next risk
5. Repeat until all risks are resolved

⛔ STOP RULE: After presenting a risk, STOP. Do NOT list the next risk
in the same response. Do NOT proceed to Phase 5. Wait for the developer.

## Risk Categories to Review

When scanning code for Phase 4.5 risks, consider:

- **Security**: input validation, auth bypass, secret exposure, injection
- **Data integrity**: race conditions, stale cache, transaction boundaries
- **Performance**: N+1 queries, large DOM renders, unbounded loops
- **Error handling**: unhandled rejections, missing try/catch where needed,
  swallowed errors
- **Regression**: imports of modified files, shared utilities changed,
  API contract shifts
- **UX**: accessibility, loading states, error states, edge-case UI breaks
- **Concurrency**: shared mutable state, event-listener leaks
- **Observability**: missing logs/metrics for new code paths

## When There Are No Risks

If after an honest scan MCL finds no risks worth surfacing, emit a single
sentence in the developer's language and proceed to Phase 5:

- Turkish: `Ek risk tespit edilmedi.`
- English: `No additional risks identified.`
- Spanish: `No se identificaron riesgos adicionales.`

Never fabricate risks to fill the section. Never present risks already
handled in Phase 1–3.

## Anti-Patterns

For Phase 4.5 anti-patterns, see `my-claude-lang/anti-patterns.md` —
anti-patterns live in a single file to avoid drift.

## Handoff to Phase 5

After every risk is resolved (skipped, fixed, or captured as a rule),
Phase 5 emits the Verification Report. The report's Impact Analysis and
must-test sections MUST reflect Phase 4.5 decisions — fixes applied,
risks accepted, rules captured.
