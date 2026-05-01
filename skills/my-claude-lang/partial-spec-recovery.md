<mcl_constraint name="partial-spec-recovery">

# Partial Spec Recovery — Rate-Limit Interruption Defense

Introduced in MCL 5.15.0; adapted to AskUserQuestion in 6.0.0.

A Phase 3 `📋 Spec:` documentation emission can be cut off
mid-stream by a rate-limit, a network drop, or a process kill.
Before this constraint, a truncated spec could be saved as
documentation under `.mcl/specs/`, and downstream phases (Phase 4
risk gate, Phase 6 promise-vs-delivery) would read an incomplete
artifact. In MCL 10.0.0 the spec is documentation only — there is
no spec-approval state transition to worry about — but a
truncated spec is still a documentation defect and must be
re-emitted in full.

This constraint closes that hole by detecting structural
truncation at the Stop-hook layer, raising a state flag, and
instructing Claude to re-emit the full spec inline.

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

After the Stop hook extracts `SPEC_HASH`, it calls the
partial-spec helper:

| helper rc | state transition                                    |
| --------- | --------------------------------------------------- |
| 0 (partial) | write `partial_spec=true`, `partial_spec_body_sha=<prefix>`; emit `spec-format-warn` audit |
| 1 (complete) | if `partial_spec=true` → clear both fields        |
| 2 (no spec) | leave any existing flag alone                     |

Spec-save is suppressed while `partial_spec=true` — the truncated
body is not written to `.mcl/specs/` until the structural-
completeness check passes on a later turn.

## Activate-Hook Recovery Audit

When `mcl-activate` reads `partial_spec=true` from state, it
injects an `<mcl_audit name="partial-spec-recovery">` block into
`additionalContext` telling Claude to:

1. Open with ONE localized line acknowledging the interruption.
2. Re-emit the FULL `📋 Spec:` block from Phase 1 context —
   every required section present.
3. Continue Phase 3 implementation in the same response. No askq
   is involved — the spec is documentation, not a state gate.
4. The flag clears on the same turn if and only if the re-emitted
   spec passes the structural-completeness check.

The audit repeats every turn until a structurally-complete spec
clears the flag — this is a deliberate exception to the
**warn-once-then-execute** rule. Until the developer sees a fully
recovered spec, every turn must carry the recovery instruction.

## Anti-Patterns

- **Auto-retry / auto-re-emit** without developer approval. Recovery
  is a supervised replay, not a silent retry loop.
- **Content validation** inside section bodies. Presence is
  sufficient; let the developer judge the content.
- **Applying to non-spec turns**. The helper exits 2 when no
  `📋 Spec:` marker is present — there is nothing to check.
- **Broadening to Phase 1 summaries**. This rule covers Phase 3
  spec documentation emissions only; Phase 1 truncation is handled
  by MCL's normal "ask one question at a time" loop.

</mcl_constraint>
