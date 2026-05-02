<mcl_phase name="asama4-spec">

# Aşama 4: Generate English Spec

Called automatically when Aşama 1 parameters are complete and confirmed.

## Purpose

This is the MOST CRITICAL phase of MCL. Without this phase, the developer
is not getting the benefit of English-native Claude Code. The spec transforms
a non-English request into a precise English engineering document — as if
a senior English-speaking engineer wrote the requirements themselves.

## Rules

1. Announce: "All points are clear. Generating the specification..."
2. Write the spec in a visible `📋 Spec:` block in the response — NOT internally
3. The spec MUST be visible to the developer in the conversation output
4. After the spec, explain in the developer's language what it says
5. Call `AskUserQuestion({question: "MCL 6.0.0 | <localized spec-approval
   prompt>", options: ["<approve-family>", "<edit>", "<cancel>"]})` —
   since 6.0.0 this REPLACES the text-based "yes / no" prompt. Do NOT
   emit the legacy `✅ MCL APPROVED` marker; it is dead.
6. Do NOT proceed to Aşama 7 until the tool_result returns an
   approve-family option (Stop hook audit: `approve-via-askuserquestion`).

## Spec Quality Standard

Write specs like a senior engineer with 15+ years of experience who:
- Thinks about edge cases before being asked
- Considers error states and failure modes
- Identifies implicit requirements the developer didn't mention but would expect
- Specifies behavior precisely — no ambiguous language
- Separates what the system MUST do vs SHOULD do vs MUST NOT do
- Considers the existing codebase architecture and patterns

## Spec Template

```
📋 Spec:

## [Feature/Change Title]

### Objective
[One precise sentence: what this change accomplishes and why it matters]

### Requirements
MUST:
- [Non-negotiable requirements — the feature fails without these]

SHOULD:
- [Expected behavior — standard engineering practice]

SHOULD NOT:
- [Anti-patterns to avoid]

### Acceptance Criteria
- [ ] [Observable, testable criterion — not vague]
- [ ] [Each criterion answers: "how do I verify this works?"]

### Edge Cases & Error Handling
- [What happens when input is empty/null/invalid?]
- [What happens at boundary conditions?]
- [What happens when the operation fails?]

### Technical Approach
- [Which files to modify and why]
- [Architecture pattern to follow — match existing codebase]
- [Dependencies or utilities to use]

### Out of Scope
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
All code in Aşama 7 must satisfy the spec. If implementation reveals
the spec is incomplete, return to Aşama 4 and update — do not improvise.

</mcl_phase>
