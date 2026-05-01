<mcl_phase name="phase4-5-risk-review">

> ⚠️ SYNC NOTE: The active Phase 4.5 rule lives in `mcl-activate.sh` STATIC_CONTEXT
> (the `<mcl_phase name="phase4-5-risk-review">` block). This file is the extended
> reference. When updating Phase 4.5 behavior, BOTH must be updated together.

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

1. MCL presents **one** risk as plain text with a short explanation of
   why it matters (security / data integrity / performance / regression
   / UX / etc.)
2. MCL immediately calls (since 6.0.0):
   ```
   AskUserQuestion({
     question: "MCL 6.0.0 | <localized risk decision prompt>",
     options: [
       "<apply-fix-in-language>",     # MCL implements the fix
       "<skip-in-language>",          # accept the risk as-is
       "<make-rule-in-language>"      # triggers Rule Capture
     ]
   })
   ```
3. MCL STOPS and waits for the tool_result **in the next message**.
4. On tool_result: execute the chosen action, then present the next risk.
5. Repeat until all risks are resolved.

⛔ STOP RULE: After presenting a risk and calling `AskUserQuestion`,
STOP. Do NOT list the next risk in the same response. Do NOT proceed
to Phase 5. Wait for the tool_result.

## Spec Compliance Pre-Check

Before the automated SAST scan and the category-based risk review,
Phase 4.5 first verifies that every MUST and SHOULD requirement from
the approved `📋 Spec:` body was implemented in Phase 4.

How:
1. Retrieve the approved spec from conversation context (the `📋 Spec:`
   block approved in Phase 3). If the spec is unrecoverable from
   context, skip this step silently and proceed to the SAST scan.
2. Walk every MUST requirement, then every SHOULD requirement.
3. For each requirement: inspect the Phase 4 code to determine whether
   it is fully implemented, partially implemented, or absent.
4. **Fully implemented** → silent pass — do NOT list it, do NOT report it.
5. **Partially implemented or absent** → surface as a Phase 4.5 risk
   in the sequential dialog, same format as all other risks:
   - Cite the spec requirement verbatim (one sentence)
   - Explain what is missing or incomplete in the implementation
   - Offer the three standard options (apply fix / skip / make rule)
   - STOP and wait for the developer's reply before continuing.

Spec gaps feed into the **same sequential dialog** as SAST findings
and category-based risks — not a separate section, no block heading.
They appear first so they can be fixed before new implementation
risks are reviewed.

Empty result: if every MUST/SHOULD is fully implemented, skip this
step entirely and proceed silently to the SAST scan.

## Integrated Quality Scan (per-turn, before each risk-dialog turn)

Before each risk-dialog turn, MCL applies five embedded lenses
**simultaneously** — these are continuous practices designed into the
review from the start, not isolated checkpoints bolted on at the end:

| Lens | What to look for |
|------|-----------------|
| **(a) Code Review** | Correctness, logic errors, error handling, dead code, missing validations |
| **(b) Simplify** | Unnecessary complexity, premature abstraction, over-engineering, duplicate logic |
| **(c) Performance** | N+1 queries, unbounded loops, blocking synchronous calls, memory leaks, large allocations |
| **(d) Security** | Injection (SQL, command, XSS), auth bypass, CSRF, sensitive data exposure, insecure defaults |
| **(e) Brief-Phase-1 Scope Drift** (since 8.4.0) | Implementation elements that lack traceability to a Phase 1 confirmed parameter AND lack a `[default: X, changeable]` marker — likely Phase 1.5 upgrade-translator hallucination |

Security and performance are **not separate gate steps** — they are
facets of every risk assessment, surfaced naturally as part of the
same sequential dialog. A finding from any lens is presented as one
risk turn with a label (e.g. `[Security]`, `[Performance]`,
`[Brief-Drift]`).

Semgrep SAST findings (HIGH/MEDIUM with unambiguous autofix) are
applied silently and merged into the lens output. The overall scan is
invisible unless it produces surfaceable risks.

### Lens (e): Brief-Phase-1 Scope Drift (since 8.4.0)

Phase 1.5 became upgrade-translator in 8.4.0 — it transforms vague
verbs ("list", "show", "manage") into surgical English ("render
paginated table", "expose CRUD") and may add `[default: X, changeable]`
markers for verb-implied standard patterns. This lens guards against
**hallucinated scope** — invented features that lack both Phase 1
traceability AND a `[default]` marker.

**When this lens runs:** mandatory when the session's
`engineering-brief` audit shows `upgraded=true`. Skipped silently when
`upgraded=false` (no upgrade happened, no drift possible).

**Procedure per implementation element:**
1. Walk Phase 4 code: each function, route, schema field, dependency
   added in this session.
2. For each element ask:
   - Is it traceable to a Phase 1 confirmed parameter the user said?
   - If not, is it carried by a `[default: X, changeable]` marker in
     the brief or spec?
   - If neither: it is **untraced scope** — surface as a Brief-Drift
     risk.
3. Surface format (one risk per drift):
   ```
   [Brief-Drift] Implementation includes <X> (file:line). User did
   not mention <X> in Phase 1; brief/spec has no [default: X,
   changeable] marker for it. Likely Phase 1.5 upgrade-translator
   hallucination.

   Options:
     (a) Remove from spec + Phase 4 code (revert to user intent)
     (b) Mark as [default: <X>, changeable] in spec (user accepts
         the upgrade-translator addition)
     (c) Rule-capture: developer wants this default for all future
         specs of similar shape (writes to CLAUDE.md / .mcl/project.md)
   ```
4. Wait for developer reply before next risk.

This is the safety net for Phase 1.5's contract relaxation. Without it,
upgrade-translator could silently introduce scope the developer never
asked for.

## Automated SAST Pre-Scan (Semgrep)

Phase 4.5 invokes Semgrep as an automated SAST pre-scan over files MCL
wrote or edited in this session's Phase 4. Semgrep findings either
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

If `mcl-activate.sh` already emitted a `semgrep-missing` notice this
session, skip the SAST step silently (Semgrep is not installed).
A `semgrep-unsupported-stack` notice does NOT skip the scan — it fires
at session start on the project as it exists then; if Phase 4
subsequently created files of a supported type, the scan must still
run on those files. Phase 4.5's category-based review below still runs
normally.

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

## TDD Re-Verify

After every Phase 4.5 risk is resolved (skipped, fixed, or
rule-captured), run a TDD re-verify before handing off to Phase 4.6
— provided `test_command` is configured (`bash ~/.claude/hooks/lib/mcl-config.sh get test_command` returns non-empty).

Skip the re-verify **only** when Phase 4.5 was omitted entirely (no
risks found and the phase was silent). If Phase 4.5 ran — even if
all risks were skipped with no code change — re-verify still runs.
An all-skip re-run costs nothing (tests stay GREEN) and removes any
ambiguity about whether fixes were applied.

How:
1. Run `bash ~/.claude/hooks/lib/mcl-test-runner.sh green-verify`.
2. **GREEN** → proceed to Phase 4.6.
3. **RED** → a Phase 4.5 fix introduced a regression. Surface the
   failing test(s) as a new Phase 4.5 risk in the sequential dialog:
   - Cite the failing test name and error message
   - State which risk-fix likely caused the regression
   - Offer the three standard options (fix the regression / revert
     the risk-fix / make rule)
   - STOP, wait for reply, apply decision, re-run TDD. Repeat until
     GREEN, then proceed to Phase 4.6.
4. **TIMEOUT** → log one audit line (`mcl_audit_log "tdd-rerun-timeout" "phase4-5"`);
   proceed to Phase 4.6 without blocking.

## Comprehensive Test Coverage (STEP-454)

After TDD re-verify passes (or if `test_command` is configured),
MCL checks that Phase 4 code is covered by four test categories.
This step follows the same sequential dialog format as all other
Phase 4.5 risks.

| Category | Applies when |
|----------|-------------|
| **Unit tests** | Any new function, class, or module was created |
| **Integration tests** | New API endpoints, cross-module data flows, DB interactions |
| **E2E tests** | UI stack is active (`ui_flow_active=true`) and new user flows were added |
| **Load/stress tests** | Throughput-sensitive paths (queues, bulk processing, high-concurrency endpoints) |

**Mechanic (when `test_command` is configured):**
For each uncovered category, Claude **writes the missing test file(s)**
as a Phase 4 code action — not a dialog turn. After writing, runs
`mcl-test-runner.sh green-verify`. If RED → surfaces failing test as a
new Phase 4.5 risk in the sequential dialog.

**Mechanic (when `test_command` is NOT configured):**
Documents missing categories in a single Phase 4.5 risk turn so the
developer knows what to add later. They choose: add tests now / skip /
make-rule.

If all applicable categories are adequately covered, omit this step
entirely (empty-section-omission rule).

Skip STEP-454 when:
- Phase 4.5 was entirely omitted (no risks found).
- All four applicable categories are already covered by existing tests.

## Handoff to Phase 4.6

After every risk is resolved (including STEP-454) and TDD re-verify
passes (or is skipped), proceed to Phase 4.6 (Post-Risk Impact Review).
Phase 4.6 and Phase 5 MUST reflect Phase 4.5 decisions — fixes applied,
risks accepted, rules captured.

</mcl_phase>
