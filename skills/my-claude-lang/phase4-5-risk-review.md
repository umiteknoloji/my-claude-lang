<mcl_phase name="phase4-5-risk-review">

# Phase 4.5: Post-Code Risk Review

**`superpowers` (tier-A, ambient):** active throughout this phase — no explicit dispatch point; its methodology layer applies as a behavioral prior.

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

## Automated SAST Pre-Scan (Semgrep)

Before running the human-judgment category review below, Phase 4.5
invokes Semgrep as an automated SAST pre-scan over files MCL wrote
or edited in this session's Phase 4. Semgrep findings either
**auto-fix silently** (HIGH / MEDIUM with unambiguous autofix) or
**seed the Phase 4.5 dialog as regular risks** (HIGH / MEDIUM without
autofix or where multiple valid options exist). Semgrep never
produces a standalone section — its output is merged into the
existing risk-dialog flow.

### Invocation

```
bash ~/.claude/hooks/lib/mcl-semgrep.sh scan <file1> <file2> ...
```

Pass the deduplicated list of files edited or created during Phase 4
of this session. Relative or absolute paths both work. Empty list →
skip the scan. Do NOT scan files that were not touched this session
(delta scope invariant — protects against noisy legacy findings).

### Preflight gate

If `mcl-activate.sh` already emitted a `semgrep-missing` or
`semgrep-unsupported-stack` notice this session, skip the SAST step
silently. The developer has already been told once; Phase 4.5's
category-based review below still runs normally.

### Findings handling

Helper emits JSON:
`{"findings":[{"severity","rule_id","file","line","message","autofix"}, ...],
 "scanned_files":N, "errors":[...]}`.

For each finding:

- **`severity=LOW`** → suppress entirely. Do not surface. Do not log
  to the dialog. (LOW packs too many false positives to be useful
  at this level.)
- **`severity=HIGH` or `MEDIUM`** with a non-null `autofix` AND an
  unambiguous application point → apply the autofix silently via
  `Edit` / `MultiEdit` (per the global captured rule: "auto-fix
  unambiguous Phase 4.5 risks silently"). Record via
  `mcl_audit_log "semgrep-autofix" "phase4-5" "rule=<rule_id> file=<file>:<line>"`.
- **`severity=HIGH` or `MEDIUM`** where `autofix` is null, ambiguous,
  or requires a trade-off → surface as a normal Phase 4.5 risk in
  the sequential dialog. Render the `message` in the developer's
  language, cite `file:line`, offer the three standard options
  (skip / specific fix / general rule).

`errors` entries are logged but do NOT block the Phase 4.5 dialog —
SAST is advisory, not blocking. Scan timeout or helper failure → one
audit-log line, then proceed to the category-based review below.

### Output discipline

The SAST step is invisible unless it surfaces risks. Never announce
"running Semgrep…", "Semgrep found N issues", or "SAST scan complete".
The developer sees only the risk-dialog turns seeded by Semgrep,
blended with the category-based risks MCL itself identifies.

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

If after an honest scan MCL finds no risks worth surfacing, OMIT
Phase 4.5 entirely from the response — no header, no placeholder
sentence, no whitespace filler — and proceed silently to Phase 5.
The scan still *happens*; only its output is suppressed when clean.
"No news = good news" is the user-facing contract.

Never fabricate risks to fill the section. Never present risks already
handled in Phase 1–3. Never emit a "No risks identified." sentence —
silence is the correct signal.

## Anti-Patterns

For Phase 4.5 anti-patterns, see `my-claude-lang/anti-patterns.md` —
anti-patterns live in a single file to avoid drift.

## Handoff to Phase 5

After every risk is resolved (skipped, fixed, or captured as a rule),
Phase 5 emits the Verification Report. The report's Impact Analysis and
must-test sections MUST reflect Phase 4.5 decisions — fixes applied,
risks accepted, rules captured.

</mcl_phase>
