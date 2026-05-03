<mcl_phase name="asama4-spec">

# Aşama 4: Generate English Spec

Called automatically when Aşama 1 parameters are complete and confirmed.

## NO FAST-PATH RULE (since v10.0.3, audit-enforced since v10.0.4)

Every Edit / Write / MultiEdit / NotebookEdit tool call requires a
visible English 📋 Spec: block emitted in the same assistant turn,
BEFORE the tool call. There is no "too small" exception. Even
follow-up tweaks ("change button text", "remove this prop") need a
brief spec describing the change.

**Enforcement is post-turn audit, not pre-tool block.** v10.0.3 tried
hard-blocking in `mcl-pre-tool.sh` but Claude Code's transcript
file does not flush in-progress assistant text before tool calls
fire — pre-tool can't reliably see whether the model just emitted a
spec. v10.0.4 moves the check to `mcl-stop.sh`'s
`_mcl_spec_presence_audit`: at end of turn (transcript fully
flushed), the helper scans the latest assistant message; if any
Edit/Write tool_use block appears without a preceding 📋 Spec:
text block, it writes `spec-required-warn` to audit.log. Visible
via `/mcl-checkup`.

The model is expected to comply with the rule based on
STATIC_CONTEXT and this skill file alone. Audit-warn surfaces
non-compliance retrospectively so the developer can correct.

For brief follow-up specs, this minimal shape is accepted:

```
📋 Spec:
Changes:
- file:path — what changes and why
Behavioral contract:
- the observable invariant the change preserves or introduces
Out of scope:
- explicitly excluded behaviors
```

The original full-form spec template (Objective / MUST / SHOULD /
Acceptance / Edge Cases / Technical Approach / Out of Scope) still
applies for the FIRST spec of each new task. Follow-up turns may
emit the brief shape above.

## Purpose

This is the MOST CRITICAL phase of MCL. Without this phase, the developer
is not getting the benefit of English-native Claude Code. The spec transforms
a non-English request into a precise English engineering document — as if
a senior English-speaking engineer wrote the requirements themselves.

## Rules

1. Announce: "All points are clear. Generating the specification..."
2. Write the spec in a visible `📋 Spec:` block in the response — NOT internally
3. The spec MUST be visible to the developer in the conversation output
4. **SPEC BODY IS ENGLISH — non-negotiable (since 10.1.15).** Every section's body content (Objective, MUST/SHOULD, Acceptance Criteria, Edge Cases, Technical Approach, Out of Scope, conditional sections) is written in English, derived from the Aşama 3 Engineering Brief — NOT from Aşama 1's dev-language summary. If the spec body is in dev's language, Aşama 3 was skipped — go back and run Aşama 3 first. Section section *labels* (e.g. "Objective", "MUST/SHOULD") stay English; the *content under each label* is also English. This is what enables Claude Code to consume the spec as if a native English engineer wrote it.
5. After the spec, write a 3-5 sentence summary paragraph in dev's language (plain text, BEFORE the AskUserQuestion call). This is the developer-facing TLDR.
6. Call `AskUserQuestion` with question prefix EXACTLY (parsed by `mcl-askq-scanner.py` — deviating breaks classification):
   - TR: `MCL <ver> | Faz 4 — Spec onayı: <localized spec-approval prompt>`
   - EN: `MCL <ver> | Phase 4 — Spec approval: <body>`
   - Other: `MCL <ver> | <translated phase label> — Spec approval: <body>` (translate the body, keep `Spec` as a fixed MCL technical token)
   Options: approve-family / edit / cancel in dev's language. Do NOT emit the legacy `✅ MCL APPROVED` marker; it is dead.
7. Do NOT proceed to Aşama 7 until the tool_result returns an approve-family option (Stop hook audit: `approve-via-askuserquestion` AND `spec-approve` AND `asama-2-complete` must all be present).

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

## Audit Emit on Approval (since v10.1.6)

After AskUserQuestion returns an approve-family tool_result for the
spec approval (selected option matches the approve label in the
developer's detected language), AND BEFORE writing any Aşama 7 code,
emit the completion audit via Bash:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log asama-4-complete mcl-stop "spec_hash=<H> approver=user"'
```

Where `<H>` is the first 12 chars of the SHA256 of the approved spec
body (same value already stored as `spec_hash` in state.json — useful
for the audit trail to correlate emit-time with approval-time).

**Why mandatory:** The Stop hook's askq classifier can miss the
approval intent (off-language wording, dropped prefix, free-form text
instead of an AskUserQuestion option choice). When that happens,
`spec_approved` stays `false` and `current_phase` stays `4` even
though the model proceeds to Aşama 7 behaviorally — this is the
herta-type freeze (v10.1.4 deployment, May 2026). An explicit audit
emit is classifier-independent: Stop hook scans audit.log and
force-progresses `spec_approved=true`, `current_phase=7`,
`phase_name=EXECUTE`. Audit + trace gain a
`asama-4-progression-from-emit` record so the bypass is visible.

Fires ONCE per spec approval. If the developer later requests a
revision (revise option), the model re-emits the spec; on re-approval,
emit `asama-4-complete` again — Stop hook treats the second emit as a
no-op when current_phase is already 7.

</mcl_phase>
