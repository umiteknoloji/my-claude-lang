<mcl_phase name="phase4-impact-lens">

# Phase 4 — Impact Lens

The impact lens is **part of Phase 4**, not a separate phase. It
runs AFTER the risk-gate dialog (`phase4-risk-gate.md`) is fully
resolved and BEFORE Phase 5 (Verification Report). It is a
**mandatory, sequential, interactive dialog** focused on real
downstream effects on OTHER files / consumers / contracts.

## Why the Impact Lens Exists

Earlier MCL versions surfaced "Impact Analysis" as a static
paragraph in the Phase 5 Verification Report. In practice this
led to two failures:

1. The model padded Impact Analysis with meta-changelog ("we
   updated file X, next session will use behavior Y") instead of
   real downstream effects on OTHER parts of the project.
2. The developer had no chance to act on an impact — even when a
   real consumer was about to break, the report was already
   emitted and the session effectively closed.

The impact lens fixes both: the impact scan is *narrowed* to real
downstream effects only (no meta-changelog), and each impact is
presented in an interactive loop identical to the risk-gate
dialog, letting the developer patch consumers before Phase 5.

## When the Impact Lens Runs

Immediately after the Phase 4 risk gate is fully resolved — i.e.
every risk surfaced in the risk gate has been answered (skip /
apply fix / override / capture rule) or the scan produced no
risks.

Phase 4 risk gate → Phase 4 impact lens → Phase 5.

## What Counts as an Impact

An impact is a downstream, in-project effect of the newly-written
code on something **other than the code itself**:

- Files that **import** the changed module and may now behave
  differently
- **Shared utilities** whose internal behavior shifted and whose
  other callers could regress
- **API / contract** changes that break callers (HTTP route,
  function signature, event payload shape, exported type)
- **Shared state / cache** invalidation — code that reads the same
  key/store and may now see stale or missing data
- **Schema / migration** effects on existing rows, existing
  fixtures, existing test data
- **Configuration** changes affecting unrelated components that
  read the same config key
- **Build / toolchain / dependency** changes that affect other
  packages in the repo

## What Is NOT an Impact

The following are NOT impacts and MUST NOT be surfaced:

- A restatement of the files just edited ("we changed X and Y")
- Meta-changelog ("from next session, this behavior is active")
- Self-reference to the task's own deliverables
- Version / setup / install notes
- Generic reminders ("remember to run tests") — those belong in
  the must-test section (Phase 5)
- Anything already surfaced and resolved in the Phase 4 risk gate

If after an honest scan the only candidates you have are
meta-changelog or self-reference, the impact list is empty — and
the impact lens is omitted entirely (see "When There Are No
Impacts").

## The Dialog Structure

The impact lens is NOT a one-shot list. It is a **sequential,
one-impact-per-turn conversation**. For each impact MCL surfaces:

1. MCL presents **one** impact as plain text with a short
   explanation:
   - **What** is affected (concrete artifact: file path, function,
     consumer component, route)
   - **Why** this change affects it (import, shared state, contract
     break, etc.)
2. MCL immediately calls:
   ```
   AskUserQuestion({
     question: "MCL {{MCL_VERSION}} | <localized impact decision prompt>",
     options: [
       "<apply-fix-in-language>",    # MCL patches the consumer in-place
       "<skip-in-language>",         # accept the impact as-is
       "<make-rule-in-language>"     # triggers Rule Capture
     ]
   })
   ```
3. MCL STOPS and waits for the tool_result **in the next message**.
4. On tool_result: execute the chosen action, then present the next
   impact.
   - **"Apply fix"** means MCL edits the affected downstream file
     directly within the impact lens — not a return to Phase 3.
     The spec is already approved at Phase 1; `scope_paths` and
     `phase_review_state=running` remain active throughout. There
     is no "go back to Phase 3" mechanism. If the required fix is
     too large for an in-place patch (e.g. requires architectural
     changes to the original Phase 3 deliverable), surface it as a
     new task for the next session instead of attempting it here.
5. Repeat until all impacts are resolved.

⛔ STOP RULE: After presenting an impact and calling
`AskUserQuestion`, STOP. Do NOT list the next impact in the same
response. Do NOT proceed to Phase 5. Wait for the tool_result.

## When There Are No Impacts

If after an honest scan MCL finds no real downstream impacts, OMIT
the impact lens entirely from the response — no header, no
placeholder sentence, no whitespace filler — and proceed silently
to Phase 5. The scan still *happens*; only its output is
suppressed when clean. "No news = good news" is the user-facing
contract.

Never fabricate impacts to fill the section. Never surface
self-referential changelog items. Never re-surface items already
handled in the Phase 4 risk gate.

## Impact Persistence — `.mcl/impact/NNNN.md`

After the developer responds to an impact (skip / fix-applied /
rule-captured), MCL writes a single file to `.mcl/impact/`
capturing the impact prose as presented and the resolution. One
file per impact. File naming is a monotonic 4-digit id
(`0001.md`, `0002.md`, …) computed by scanning existing filenames
in the directory.

File format:

```
---
impact_id: NNNN
presented_at: <ISO8601 local time>
branch: <git branch or null>
head_at_presentation: <short sha or null>
resolution: skip | fix-applied | rule-captured | open
---

[exact impact prose as shown to the developer, one line or
several lines — include the cited artifact (file path / function /
consumer) and the one-sentence "why affected"]
```

Writing rules:

- Write once per impact, at the turn the developer resolves it.
- `resolution: open` is only legal for a session that ended before
  the developer replied — do NOT pre-write `open` and hope to
  update later; write on resolution.
- Do NOT write the file for impacts the scan surfaced internally
  but decided not to present (false positives / self-reference
  filter).
- Do NOT rewrite or delete existing `.mcl/impact/` files. The
  `mcl-finish` checkpoint model treats the dir as append-only.
- Create the `.mcl/impact/` dir on demand (`mkdir -p`); never fail
  an impact-lens resolution because the dir was missing.

The impact dir is NOT the risks dir. Phase 4 risk-gate items are
resolved in-session and are NOT persisted — per the captured rule
that unambiguous risks auto-fix silently and surfaced ones get an
immediate skip/fix/rule decision. Only impacts cross the session
boundary, because downstream effects can be genuine "I'll check
this next week" items.

## Anti-Patterns

For impact-lens anti-patterns, see
`my-claude-lang/anti-patterns.md` — anti-patterns live in a single
file to avoid drift.

</mcl_phase>
