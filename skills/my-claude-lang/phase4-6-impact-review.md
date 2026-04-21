<mcl_phase name="phase4-6-impact-review">

# Phase 4.6: Post-Risk Impact Review

**`superpowers` (tier-A, ambient):** active throughout this phase — no explicit dispatch point; its methodology layer applies as a behavioral prior.

Phase 4.6 is a **mandatory, sequential, interactive dialog** that runs
AFTER Phase 4.5 (risk review is resolved) and BEFORE Phase 5
(Verification Report). Introduced in MCL 5.4.0.

## Why Phase 4.6 Exists

Before 5.4.0, "Impact Analysis" was Section 2 of the Phase 5
Verification Report — a static, one-shot paragraph the developer read
passively. In practice this led to two failures:

1. MCL padded Impact Analysis with meta-changelog ("we updated file X,
   next session will use behavior Y") instead of real downstream
   effects on OTHER parts of the project.
2. The developer had no chance to act on an impact — even when a real
   consumer was about to break, the report was already emitted and the
   session effectively closed.

Phase 4.6 fixes both: the impact scan is *narrowed* to real downstream
effects only (no meta-changelog), and each impact is presented in an
interactive loop identical to Phase 4.5, letting the developer patch
consumers before Phase 5.

## When Phase 4.6 Runs

Immediately after Phase 4.5 is fully resolved — i.e. every risk
surfaced in Phase 4.5 has been answered (skip / apply fix / capture
rule) or the scan produced no risks.

Phase 4.5 → Phase 4.6 → Phase 5.

## What Counts as an Impact

An impact is a downstream, in-project effect of the newly-written
code on something **other than the code itself**:

- Files that **import** the changed module and may now behave
  differently
- **Shared utilities** whose internal behavior shifted and whose
  other callers could regress
- **API / contract** changes that break callers (HTTP route, function
  signature, event payload shape, exported type)
- **Shared state / cache** invalidation — code that reads the same
  key/store and may now see stale or missing data
- **Schema / migration** effects on existing rows, existing fixtures,
  existing test data
- **Configuration** changes affecting unrelated components that read
  the same config key
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
- Anything already surfaced and resolved in Phase 4.5

If after an honest scan the only candidates you have are
meta-changelog or self-reference, the impact list is empty — and
Phase 4.6 is omitted entirely (see "When There Are No Impacts").

## The Dialog Structure

Phase 4.6 is NOT a one-shot list. It is a **sequential,
one-impact-per-turn conversation**. For each impact MCL surfaces:

1. MCL presents **one** impact with a short explanation:
   - **What** is affected (concrete artifact: file path, function,
     consumer component, route)
   - **Why** this change affects it (import, shared state, contract
     break, etc.)
2. MCL presents the developer's options:
   - **Skip** — accept the impact as-is, the developer will handle it
     later (or considers it non-breaking)
   - **Apply a specific fix** — MCL patches the consumer before
     moving on
   - **Make this a general rule** — triggers Rule Capture (see
     `rule-capture.md`)
3. MCL STOPS and waits for the developer's reply **in the next
   message**
4. On reply: execute the chosen action, then present the next impact
5. Repeat until all impacts are resolved

⛔ STOP RULE: After presenting an impact, STOP. Do NOT list the next
impact in the same response. Do NOT proceed to Phase 5. Wait for the
developer's reply in the next message.

## When There Are No Impacts

If after an honest scan MCL finds no real downstream impacts, OMIT
Phase 4.6 entirely from the response — no header, no placeholder
sentence, no whitespace filler — and proceed silently to Phase 5.
The scan still *happens*; only its output is suppressed when clean.
"No news = good news" is the user-facing contract.

Never fabricate impacts to fill the section. Never surface
self-referential changelog items. Never re-surface items already
handled in Phase 4.5.

## Impact Persistence — `.mcl/impact/NNNN.md`

Introduced in MCL 5.14.0 as the persistence layer behind the
`mcl-finish` slash-command.

After the developer responds to an impact (skip / fix-applied /
rule-captured), MCL writes a single file to `.mcl/impact/` capturing
the impact prose as presented and the resolution. One file per impact.
File naming is a monotonic 4-digit id (`0001.md`, `0002.md`, …)
computed by scanning existing filenames in the directory.

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
  the developer replied — do NOT pre-write `open` and hope to update
  later; write on resolution.
- Do NOT write the file for impacts the scan surfaced internally but
  decided not to present (false positives / self-reference filter).
- Do NOT rewrite or delete existing `.mcl/impact/` files. The
  `mcl-finish` checkpoint model treats the dir as append-only.
- Create the `.mcl/impact/` dir on demand (`mkdir -p`); never fail a
  Phase 4.6 resolution because the dir was missing.

The impact dir is NOT the risks dir. Phase 4.5 risks are resolved
in-session and are NOT persisted — per the captured rule that
unambiguous risks auto-fix silently and surfaced ones get an
immediate skip/fix/rule decision. Only impacts cross the
session boundary, because downstream effects can be genuine "I'll
check this next week" items. Risks cannot.

## Anti-Patterns

For Phase 4.6 anti-patterns, see `my-claude-lang/anti-patterns.md` —
anti-patterns live in a single file to avoid drift.

</mcl_phase>
