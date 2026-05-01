<mcl_phase name="phase-spec-doc">

# Phase 4 Entry: 📋 Spec Documentation Artifact

> **The spec is a living documentation artifact, not a hard gate.**
> Developer control is enforced primarily at Phase 1 summary
> confirmation (the askq) and Phase 1.7 precision audit (GATE
> questions). Spec format is enforced by **advisory warning only**
> in 9.3.0 — Write/Edit stays unlocked even when the spec block is
> malformed. Audit log records `spec-format-warn` for diagnostic
> visibility; `/mcl-finish` and Phase 6 surface accumulated warnings.

Called as the FIRST output of Phase 4 (EXECUTE), immediately after the
Phase 1 summary-confirm askq is approved (state already at
`current_phase=4`).

## Purpose (since 9.3.0)

The spec is **documentation**, not a state gate. State already advanced
to Phase 4 via Phase 1 summary-confirm; the spec block records the
English engineering interpretation MCL is operating against. Three
roles:

- **Audit trail**: written to `.mcl/specs/NNNN-slug.md` by spec-save
  for `/mcl-finish` and Phase 6 promise-vs-delivery checks.
- **Scope guard input**: file paths in Technical Approach become
  `state.scope_paths`; pre-tool blocks Phase 4 writes outside scope.
- **English semantic bridge**: the developer (and the model) read the
  same engineering artifact — non-English prompts get senior-engineer
  English documentation as a side effect.

## Rules

1. Announce: "All points are clear. Generating the specification..."
2. Write the spec in a visible `📋 Spec:` block in the response — NOT internally
3. The spec MUST be visible to the developer in the conversation output
4. **⛔ SPEC BLOCK — PINNED VERBATIM (since 9.2.1, MANDATORY).** Copy
   the template below EXACTLY. The Stop hook scanner matches the
   literal `📋 Spec:` line-anchored prefix; ANY deviation produces
   `decision:block` and forces re-emit (spec re-emit, NOT Write block):
   - First non-blank line MUST be `📋 Spec:` (clipboard emoji + space +
     `Spec` + colon). Plain `Spec:`, `## Spec`, `## Faz N — Spec` are
     FORBIDDEN.
   - The spec MUST be raw markdown — NEVER inside triple-backticks.
     A code-block-wrapped spec is invisible to the hook scanner.
   - Seven H2 headers verbatim, in this order:
     `## [Title]` → `## Objective` → `## MUST` → `## SHOULD` →
     `## Acceptance Criteria` → `## Edge Cases` → `## Technical Approach`
     → `## Out of Scope`. Missing any → `decision:block`.
   - Genuinely empty section: write header followed by `- (none)`.
     Never omit a header.

   ### ⛔ Forbidden formats (each → hook decision:block)

   ```
   ## Faz 2 — Spec        ← H2 heading instead of 📋 prefix
                            → block: missing 📋 Spec:

   Spec:                  ← bare "Spec:" without 📋
     Project: ...           → block: missing 📋 Spec:

   ```                    ← spec wrapped in triple-backticks
   📋 Spec:               → block: code-block hides the marker
   ## Objective
   ...
   ```
   ```
5. After the spec, explain in the developer's language what it says.
6. **Spec is documentation, not a gate (since 9.3.0).** State is already
   at `current_phase=4` when this spec emits — Phase 1 summary-confirm
   askq drove the transition. The spec block:
   - Records `spec_hash` for reference
   - Triggers `mcl-spec-save.sh` (writes `.mcl/specs/NNNN.md`)
   - Populates `state.scope_paths` from Technical Approach paths
   - Format-invalid → `decision:block` for SPEC RE-EMIT only (writes
     stay unlocked because phase=4 is independent of spec format)
7. Do NOT call `AskUserQuestion` for spec approval — that step was
   removed in 9.2.1. State changes are summary-confirm-driven, not
   spec-driven.
8. Proceed to Phase 4 code writing (Write/Edit/MultiEdit) in the
   SAME response after the spec block. No need for a separate turn —
   the spec is the opening prose of the Phase 4 work.

## Spec Quality Standard

Write specs like a senior engineer with 15+ years of experience who:
- Thinks about edge cases before being asked
- Considers error states and failure modes
- Identifies implicit requirements the developer didn't mention but would expect
- Specifies behavior precisely — no ambiguous language
- Separates what the system MUST do vs SHOULD do vs MUST NOT do
- Considers the existing codebase architecture and patterns

## Spec Template (PINNED — copy verbatim, do NOT paraphrase)

**Copy the block below VERBATIM into the response.** Do not wrap in
code blocks. Do not change `📋 Spec:` to `Spec:` or `## Spec`. Hook
enforces this format — deviation = `decision:block` + forced re-emit.

```
📋 Spec:

## [Feature/Change Title]

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
- The developer cannot verify the English interpretation is correct
- There is no audit trail of what Claude understood

When the spec is visible:
- Claude MUST write it — it's part of the response
- The developer sees the English interpretation even if they don't read English
- Senior engineers reviewing the conversation can verify accuracy
- It becomes the contract between developer intent and code output

## This spec is the SINGLE SOURCE OF TRUTH for all subsequent work.
All code in Phase 4 must satisfy the spec. If implementation reveals
the spec is incomplete, return to Phase 2 and update — do not improvise.

</mcl_phase>
