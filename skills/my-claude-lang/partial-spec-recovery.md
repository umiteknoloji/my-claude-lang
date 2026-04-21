<mcl_constraint name="partial-spec-recovery">

# Partial Spec Recovery — Rate-Limit Interruption Defense

Introduced in MCL 5.15.0; adapted to AskUserQuestion in 6.0.0.

A Phase 2 `📋 Spec:` emission can be cut off mid-stream by a
rate-limit, a network drop, or a process kill. Before 5.15.0, a
follow-up `yes` from the developer would transition the MCL state
machine to Phase 4 (EXECUTE) anyway — because the Stop hook's only
input was a text marker, not the structural completeness of the
spec body. A truncated spec could therefore be silently promoted to
an approved spec, and the developer had no recourse short of a
manual `rm .mcl/state.json`.

This constraint closes that hole by detecting structural
truncation at the Stop-hook layer, raising a state flag, and
instructing Claude to re-emit the full spec before any approval
can take effect.

## Detection: Structural Completeness

A spec is considered **partial** when the last assistant turn
contains a `📋 Spec:` block but is missing one or more of the seven
required section headers:

- `Objective`
- `MUST`
- `SHOULD`
- `Acceptance Criteria`
- `Edge Cases`
- `Technical Approach`
- `Out of Scope`

Detection is **header presence only** — an empty body under a
legitimate header (e.g., truly nothing is out of scope) passes the
check. The detection helper lives in
`hooks/lib/mcl-partial-spec.sh` and exposes one subcommand:

```
bash hooks/lib/mcl-partial-spec.sh check <transcript_path>
```

Exit codes:

| rc | meaning                                                     |
| -- | ----------------------------------------------------------- |
| 0  | partial — missing headers printed newline-separated on stdout |
| 1  | structurally complete                                       |
| 2  | no `📋 Spec:` marker in last assistant turn                 |

The header-match regex tolerates markdown heading prefixes (`##`,
`###`), list markers (`-`, `*`), bold/italic wrappers (`**`, `_`),
and trailing colons — so all the canonical spec rendering styles
pass.

## State Fields

| field                   | type   | purpose                                  |
| ----------------------- | ------ | ---------------------------------------- |
| `partial_spec`          | bool   | `true` while recovery is pending         |
| `partial_spec_body_sha` | string | sha256 prefix of the truncated body (audit) |

Both fields use the generic `mcl_state_set` / `mcl_state_get` path
in `hooks/lib/mcl-state.sh` — no custom helpers.

## Stop-Hook Transitions

After the Stop hook extracts `SPEC_HASH`, and **before** the
AskUserQuestion approval branch, it calls the partial-spec helper:

| helper rc | state transition                                    |
| --------- | --------------------------------------------------- |
| 0 (partial) | write `partial_spec=true`, `partial_spec_body_sha=<prefix>` |
| 1 (complete) | if `partial_spec=true` → clear both fields        |
| 2 (no spec) | leave any existing flag alone                     |

The AskUserQuestion approval branch early-returns (no phase
transition, emits `askq-ignored-partial-spec` audit) when
`partial_spec=true`, even if the developer picked an approve-family
option. This is defense-in-depth alongside Claude's own recovery
guidance.

## Activate-Hook Recovery Audit

When `mcl-activate` reads `partial_spec=true` from state, it injects
an `<mcl_audit name="partial-spec-recovery">` block into
`additionalContext` telling Claude to:

1. Open with ONE localized line acknowledging the interruption.
2. Re-emit the FULL `📋 Spec:` block from Phase 1 context —
   every required section present.
3. NOT emit the legacy `✅ MCL APPROVED` text (dead in 6.0.0).
4. End with a Phase 3 `AskUserQuestion` call (prefix
   `MCL 6.0.0 | `) asking for fresh spec approval, then STOP.
   Note: the Stop hook IGNORES the tool_result while
   `partial_spec=true` (emits `askq-ignored-partial-spec`). The
   flag clears on the same turn if and only if the re-emitted
   spec passes the structural-completeness check. The DEVELOPER
   must approve again in the FOLLOWING turn, once the flag is
   clear.

The audit repeats every turn until a structurally-complete spec
clears the flag — this is a deliberate exception to the
**warn-once-then-execute** rule. Until the developer sees a fully
recovered spec, every turn must carry the recovery instruction.

## Interaction With Drift-Reapproval

Partial-spec recovery and drift-reapproval are **distinct flows**:

- **Drift**: `spec_hash` mismatch AFTER approval — a new divergent
  spec needs re-approval.
- **Partial**: spec body structurally truncated BEFORE approval —
  the spec itself was never fully emitted.

They do not compose. The Stop-hook order is: extract
SPEC_HASH → partial-spec check → spec-hash transitions →
AskUserQuestion approval transition. A turn that is simultaneously
partial AND drifted is treated as partial first (the flag blocks
the approval transition); the drift state stays raised and clears
only after the developer approves a structurally-complete
re-emitted spec via AskUserQuestion in a later turn.

## Anti-Patterns

- **Auto-retry / auto-re-emit** without developer approval. Recovery
  is a supervised replay, not a silent retry loop.
- **Content validation** inside section bodies. Presence is
  sufficient; let the developer judge the content.
- **Applying to non-spec turns**. The helper exits 2 when no
  `📋 Spec:` marker is present — there is nothing to check.
- **Broadening to Phase 1 summaries**. This rule covers Phase 2
  spec emissions only; Phase 1 truncation is handled by MCL's
  normal "ask one question at a time" loop.

</mcl_constraint>
