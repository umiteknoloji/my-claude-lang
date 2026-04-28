<mcl_phase name="phase1-5-engineering-brief">

# Phase 1.5: Engineering Brief

Called automatically after Phase 1 parameters are confirmed and before Phase 2 spec generation.

## Purpose

Phase 1 gathers parameters in the developer's language. Phase 1.5 produces
a clean English-language Engineering Brief — a structured restatement of
those parameters as an English-native engineer would formulate them.

This is NOT a spec. The spec (Phase 2) is the authoritative deliverable.
The brief is the internal translation artifact that Phase 2 builds on —
ensuring Claude Code processes the request from an English-native framing,
not a machine-translated one.

## When Phase 1.5 Runs

Immediately after the developer approves the Phase 1 summary (AskUserQuestion
returns approve-family). Before Phase 2 spec generation begins.

Skipped when: the developer's detected language is English. In that case
Phase 1 parameters are already in English — the brief is a no-op and
Phase 2 starts directly.

## Output Format

The brief is INTERNAL — not shown to the developer unless `/mcl-self-q`
is active. It is passed as context to Phase 2 spec generation.

Structure:
```
[ENGINEERING BRIEF — INTERNAL]
Goal: <one sentence, English, precise verb>
Actor: <who performs / initiates the action>
Constraints: <enumerated, English>
Success criteria: <observable outcomes, English>
Out of scope: <explicitly excluded, English>
Assumed defaults: <[assumed: X] items from Phase 1>
```

## Rules

1. Translate intent faithfully — do NOT add scope, do NOT subtract scope.
   The brief must be a precise English restatement, not a paraphrase.
2. Preserve all `[assumed: X]` and `[default: X, changeable]` markers
   from Phase 1 — carry them into the brief verbatim.
3. If a Phase 1 parameter used idiomatic or culturally-specific phrasing,
   translate the semantic intent, not the literal words.
4. The brief is not shown as a separate step to the developer. The
   developer sees the Phase 1 summary (their language) → approves →
   MCL announces "Generating the specification..." → Phase 2 begins.
   The brief is the invisible bridge between the two.

## Failure Path

If the brief contradicts Phase 1 confirmed parameters (adds scope not
present in Phase 1, or drops a confirmed constraint), silent fallback
is FORBIDDEN.

Retry with maximum effort, changing the approach each attempt — a retry
that uses the same formulation as the previous attempt does not count.
If the root cause is missing information, ask the developer one clarifying
question in their language, then retry with the clarified input. Continue
until a consistent brief is produced.

A consistent brief is one where:
- Every goal and actor maps to a confirmed Phase 1 parameter
- No constraint from Phase 1 is absent
- No new scope appears that was not in Phase 1

Once consistent, continue to Phase 2.

## Audit

Every Phase 1.5 execution emits an audit entry:
```
engineering-brief | phase1-5 | lang=<detected> skipped=<true|false> retries=<N> clarification=<true|false>
```

If skipped (English source), `skipped=true` and `retries=0`. If produced
without contradiction, `retries=0`. `clarification=true` when the developer
was asked a question during the failure path.
This entry is the detection control required by the behavioral→dedicated rule:
even when Phase 1.5 is a no-op, the audit confirms it was evaluated.

</mcl_phase>
