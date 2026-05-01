<mcl_constraint name="mcl-finish">

# `mcl-finish` — Cross-Session Finish Mode

Introduced in MCL 5.14.0.

`mcl-finish` is a slash-command that aggregates Phase 4 impact lens impacts
accumulated since the last checkpoint and emits a project-level
finish report. It is orthogonal to the Phase 1 → 5 pipeline — typing
the literal keyword `mcl-finish` bypasses MCL's normal flow (no
Phase 1 gather, no spec, no Phase 4/5) and runs the finish
aggregation directly.

## Why It Exists

Phase 4 impact lens surfaces one impact at a time in an interactive dialog. The
developer replies `skip / apply fix / rule capture` and the session
moves on. But many impacts are genuine "I should verify this next
week" items — they belong to a horizon the developer can't act on
inside a single session.

Before 5.14.0, MCL had no mechanism to carry impacts across sessions.
Each session closed with a Phase 5 Verification Report and the impact
history vanished with the session transcript.

`mcl-finish` is the checkpoint mechanism that closes that gap —
nothing more, nothing less. It does NOT re-execute phases, does NOT
re-check resolved impacts, does NOT commit to git, does NOT push to
remote.

## Directory Layout

```
.mcl/
├── impact/
│   ├── 0001.md   ← one file per Phase 4 impact lens impact (append-only)
│   ├── 0002.md
│   └── …
└── finish/
    ├── 0001-2026-04-22.md   ← one file per mcl-finish run
    └── …
```

Both directories are created on demand (`mkdir -p`). Empty dirs are
treated as "no entries", never an error.

Impact file format is defined in `phase4-impact-lens.md` under
"Impact Persistence".

## Trigger

The developer types the literal message `mcl-finish`. The
UserPromptSubmit hook at `hooks/mcl-activate.sh` checks the
normalized prompt string; on match, the hook emits a dedicated
`<mcl_core>` context that instructs the MCL pipeline to enter finish
mode and skip the normal phases.

Two activation sources:

1. **Explicit:** developer types `mcl-finish` on its own.
2. **Tail reminder prompt:** every Phase 5 Verification Report ends
   with a localized reminder line pointing at `mcl-finish` (see
   `phase5-review.md` → "Tail Reminder").

There is NO automatic execution — the developer is always the trigger.

## What `mcl-finish` Does

1. List all `.mcl/impact/NNNN.md` files whose mtime is newer than the
   most recent `.mcl/finish/NNNN-YYYY-MM-DD.md` checkpoint's mtime.
   If no checkpoint exists yet, list all impact files.

2. Read each listed impact file. Aggregate into a single section in
   the developer's language titled `📊 Accumulated Impacts` (or
   localized equivalent). Render each impact's prose and resolution
   as shown in the file. If the list is empty, OMIT the section
   entirely.

3. Run Semgrep preflight via `bash ~/.claude/hooks/lib/mcl-semgrep.sh
   preflight "$(pwd)"`. Interpret the exit code:
   - Supported stack (rc=0 + `semgrep-ready`/`semgrep-cache-stale`):
     run `semgrep --config p/default --error --json .` bounded to
     the project root. Parse findings; emit a section
     `🔍 SAST Scan` (localized) grouped by severity with
     file:line and a one-line explanation. If Semgrep returns zero
     findings, OMIT this section entirely.
   - Unsupported stack (rc=1) OR binary missing (rc=2): OMIT the
     SAST section entirely. The developer already saw the one-time
     preflight notice at session start.

4. Above the sections, emit a single localized summary line of the
   checkpoint window, e.g., Turkish `Son checkpoint'ten bu yana
   N etki, M SAST bulgusu`.

5. Write a new checkpoint at `.mcl/finish/NNNN-YYYY-MM-DD.md`:
   - `NNNN` is the next 4-digit id from `mcl-finish.sh
     next-checkpoint-id`.
   - `YYYY-MM-DD` is today's local date.
   - File contents: YAML frontmatter (`checkpoint_id`, `written_at`
     ISO8601, `impact_count`, `sast_finding_count`) followed by the
     full report body.

6. End the response. Do NOT emit a Phase 5 Verification Report, a
   must-test list, or a tail reminder — `mcl-finish` is its own
   output, not a wrapped Phase 5.

## What `mcl-finish` Does NOT Do (MVP)

- **Re-check open impacts against current code.** The MVP is pure
  aggregation. Whether an impact is still valid is the developer's
  call. Automated re-check is an explicit non-goal for 5.14.0 and
  may ship in a later iteration.
- **Re-run Phase 4** on current diff. Full-project Semgrep
  rescan is the only re-scanning `mcl-finish` performs — and only
  for SAST, not for the broader Phase 4 risk-gate risk heuristic set.
- **Auto-commit, push, branch, tag, or PR.** `mcl-finish` does not
  touch git. The checkpoint file is local state.
- **External reporting** (Slack, email, issue trackers, CI gates).
- **Multi-developer collaboration.** No locking, no merge semantics.
  Concurrent `mcl-finish` runs on the same project may race; each
  run writes its own checkpoint id, so the outcomes don't corrupt,
  but impact-to-checkpoint assignment becomes ambiguous. MVP leaves
  this to the developer.
- **Risk persistence.** `.mcl/risks/` does NOT exist. Phase 4 risk-gate
  risks are resolved in-session per the captured rule that
  unambiguous ones auto-fix silently and surfaced ones get an
  immediate skip/fix/rule decision.

## Interaction with MCL's Other Self-Commands

`mcl-update` and `mcl-finish` are symmetric in pipeline bypass (both
skip Phase 1–5) and asymmetric in side-effects (update mutates the
install; finish mutates only `.mcl/` state). They never co-run —
the hook's intercept branches on the first-matching literal.

## Related Files

- `hooks/mcl-activate.sh` — the literal-prompt intercept
- `hooks/lib/mcl-finish.sh` — filesystem convention helper
- `skills/my-claude-lang/phase4-impact-lens.md` — impact
  persistence format
- `skills/my-claude-lang/phase5-review.md` — tail reminder line

</mcl_constraint>
