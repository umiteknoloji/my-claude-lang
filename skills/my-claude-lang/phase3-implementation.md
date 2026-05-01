<mcl_phase name="phase3-implementation">

# Phase 3 — Implementation

> **The `📋 Spec:` block is a living documentation artifact emitted
> at Phase 3 entry, NOT a hard gate. Developer control is enforced
> at Phase 1 summary-confirm and Phase 2 design approval (UI), not
> via spec approval.**

Phase 3 produces working code. The opening artifact is the
`📋 Spec:` documentation block — written into the response so the
developer (and the model) read the same English engineering
interpretation. Format violations are advisory warnings, not
blocks; Write/Edit stay unlocked even when the spec is malformed.

## Entry Condition

- `current_phase = 3`
- One of two paths:
  - **Non-UI path**: Phase 1 summary-confirm approved AND
    `is_ui_project = false` → state transitioned 1 → 3 directly.
  - **UI path**: Phase 2 design approved → state transitioned
    2 → 3 with `design_approved = true`.

Never start Phase 3 from spec emission alone — the spec is
documentation, not a gate.

## Purpose

The `📋 Spec:` block serves three roles:

- **Audit trail**: written to `.mcl/specs/NNNN-slug.md` by
  spec-save for `/mcl-finish` and Phase 6 promise-vs-delivery
  checks.
- **Scope guard input**: file paths in the Technical Approach
  section become `state.scope_paths`; Phase 4 risk gate uses these
  to detect architectural drift on writes outside scope.
- **English semantic bridge**: the developer (and the model) read
  the same engineering artifact — non-English prompts get
  senior-engineer English documentation as a side effect.

## Spec Format Requirement (advisory)

The spec block MUST follow this format. Format violations are
**advisory** — they emit a `spec-format-warn` audit entry, surface
in `/mcl-finish` and Phase 6, and accumulate into a LOW soft fail
on repeated violations. Writes stay unlocked regardless.

Required structure:

1. First non-blank line: literal `📋 Spec:` (clipboard emoji +
   space + `Spec` + colon) on its own line.
2. The spec MUST be raw markdown — NEVER inside triple-backticks.
   A code-block-wrapped spec is invisible to the audit scanner.
3. Seven H2 headers verbatim, in this order:
   - `## Objective`
   - `## MUST`
   - `## SHOULD`
   - `## Acceptance Criteria`
   - `## Edge Cases`
   - `## Technical Approach`
   - `## Out of Scope`
4. Genuinely empty section: write the header followed by
   `- (none)`. Never omit a header.

### Advisory warning behavior

When the Stop hook detects a format violation:

- Audit entry: `spec-format-warn | stop | reason=<missing-header|wrapped-in-code-block|prefix-typo>`.
- No `decision:block` — Phase 3 implementation continues.
- Counter incremented in `state.spec_format_warn_count`.
- On the third format violation in a single session, Phase 6
  surfaces a LOW soft fail: "Spec format violations accumulated
  (N). Documentation drift risk."

### Forbidden formats (each → advisory warning, NOT a block)

```
## Faz 2 — Spec        ← H2 heading instead of 📋 prefix
                         → warn: missing 📋 Spec:

Spec:                  ← bare "Spec:" without 📋
  Project: ...           → warn: missing 📋 Spec:

```                    ← spec wrapped in triple-backticks
📋 Spec:               → warn: code-block hides the marker
## Objective
...
```

## Phase 3 Procedure

1. Announce in the developer's language: "All points are clear.
   Writing the implementation specification..."
2. Emit a visible `📋 Spec:` block (raw markdown, NOT inside
   triple-backticks). Use the template below verbatim.
3. After the spec, explain in the developer's language what it
   says — short summary, not a re-translation.
4. **Do NOT call `AskUserQuestion` for spec approval.** State is
   already at `current_phase = 3`. The spec is documentation.
5. Continue with implementation (`Write` / `Edit` / `MultiEdit` /
   `Bash`) in the SAME response. The spec is the opening prose of
   Phase 3 work, not a separate turn.
6. UI project path: swap Phase 2 fixtures for real `fetch` /
   `axios` / DB calls, wire data layer, error / loading / empty
   states. See `my-claude-lang/phase3-backend.md` for the
   UI-after-design backend procedure.
7. Non-UI path: write code directly per the Technical Approach
   section. See `my-claude-lang/phase3-execute.md` for the
   single-path execution rules and `my-claude-lang/phase3-tdd.md`
   for the incremental red-green-refactor overlay.

To reject the direction after Phase 1 / Phase 2 approval:
`/mcl-restart`. To stop: `/mcl-finish`.

## Spec Quality Standard

Write specs like a senior engineer with 15+ years of experience
who:
- Thinks about edge cases before being asked
- Considers error states and failure modes
- Identifies implicit requirements the developer didn't mention
  but would expect
- Specifies behavior precisely — no ambiguous language
- Separates what the system MUST do vs SHOULD do vs MUST NOT do
- Considers the existing codebase architecture and patterns

## Spec Template (copy verbatim, do NOT paraphrase)

**Copy the block below VERBATIM into the response.** Do not wrap
in code blocks. Do not change `📋 Spec:` to `Spec:` or `## Spec`.

```
📋 Spec:

## Objective
[One precise sentence: what this change accomplishes and why it matters]

## MUST
- [Non-negotiable requirement — the feature fails without this]
- [Add SHOULD NOT items here too as `- NOT: <anti-pattern>` if needed]

## SHOULD
- [Expected behavior — standard engineering practice]

## Acceptance Criteria
- [ ] [Observable, testable criterion — not vague]
- [ ] [Each criterion answers: "how do I verify this works?"]

## Edge Cases
- [What happens when input is empty/null/invalid?]
- [What happens at boundary conditions?]
- [What happens when the operation fails?]

## Technical Approach
- [Which files to modify and why]
- [Architecture pattern to follow — match existing codebase]
- [Dependencies or utilities to use]

## Out of Scope
- [Explicitly state what this task does NOT include]
- [Prevents scope creep during implementation]

<!-- CONDITIONAL SECTIONS — include only when triggered, omit entirely otherwise -->

### Non-functional Requirements
<!-- TRIGGER: performance/scale/resource constraints mentioned or implied -->
- Latency: [p95 target, e.g. <200ms]
- Throughput: [requests/sec or records/sec target]
- Memory budget: [max RSS or heap allocation]
- Concurrency: [max parallel operations]

### Failure Modes & Degradation
<!-- TRIGGER: external dependencies, async operations, distributed concerns -->
- [Dependency X down]: [degraded behavior — e.g. return cached data, return 503]
- [Timeout scenario]: [fallback behavior and user-visible error]
- [Partial failure]: [which parts continue, which abort]
- Circuit breaker / retry policy: [yes/no, thresholds]

### Observability
<!-- TRIGGER: critical production path, security audit trail, user behavior tracking -->
- Log events: [which operations emit log entries and at what level]
- Metrics: [which counters/gauges/histograms to emit]
- Alerts: [what conditions should page or notify]
- Trace spans: [which operations need distributed tracing]

### Reversibility / Rollback
<!-- TRIGGER: DB schema changes, data migrations, destructive operations, feature flags -->
- Rollback procedure: [step-by-step how to revert this change]
- Data safety: [is data loss possible? what backups are needed?]
- Feature flag: [can this be toggled off without a deploy?]
- Migration: [is the migration reversible? down-migration provided?]

### Data Contract
<!-- TRIGGER: API surface changes, shared schemas, cross-service boundaries -->
- Request schema: [fields, types, validation rules]
- Response schema: [fields, types, nullability]
- Breaking changes: [yes/no — if yes, versioning strategy]
- Migration: [how existing data/callers are handled]
```

## Why the Spec Must Be Visible

When the spec is internal/hidden:
- Claude skips it (proven by testing — it happens every time)
- The developer cannot verify the English interpretation is
  correct
- There is no audit trail of what Claude understood

When the spec is visible:
- Claude MUST write it — it's part of the response
- The developer sees the English interpretation even if they don't
  read English
- Senior engineers reviewing the conversation can verify accuracy
- It becomes the contract between developer intent and code output

## Implementation Proceeds Regardless of Spec Status

Phase 3 implementation does NOT pause for spec approval. The
developer-control gates are upstream:
- Phase 1 summary-confirm captured intent
- Phase 2 design approval (UI) captured visual intent

If the spec format is wrong, the warn fires and the model
continues. If the spec is missing entirely (unrecoverable
context), Phase 3 still runs against the Phase 1 brief — Phase 4
risk gate will surface any drift between brief and code as a
risk.

The spec is **the source of truth for documentation**, not a
state gate. All code SHOULD satisfy the spec; if implementation
reveals the spec is incomplete, update the spec inline and
continue. Do not improvise away from the brief, but do not pause
the response for re-approval either.

</mcl_phase>
