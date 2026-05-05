<mcl_phase name="asama19-impact-review">

# Aşama 19: Post-Risk Impact Review (was Aşama 10 in v10)

Aşama 10 is a **mandatory, sequential, interactive dialog** that runs
AFTER Aşama 8 (risk review is resolved) and BEFORE Aşama 11
(Verification Report). Introduced in MCL 5.4.0.

## Why Aşama 10 Exists

Before 5.4.0, "Impact Analysis" was Section 2 of the Aşama 11
Verification Report — a static, one-shot paragraph the developer read
passively. In practice this led to two failures:

1. MCL padded Impact Analysis with meta-changelog ("we updated file X,
   next session will use behavior Y") instead of real downstream
   effects on OTHER parts of the project.
2. The developer had no chance to act on an impact — even when a real
   consumer was about to break, the report was already emitted and the
   session effectively closed.

Aşama 10 fixes both: the impact scan is *narrowed* to real downstream
effects only (no meta-changelog), and each impact is presented in an
interactive loop identical to Aşama 8, letting the developer patch
consumers before Aşama 11.

## When Aşama 10 Runs

Immediately after Aşama 8 is fully resolved — i.e. every risk
surfaced in Aşama 8 has been answered (skip / apply fix / capture
rule) or the scan produced no risks.

Aşama 8 → Aşama 10 → Aşama 11.

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
  the must-test section (Aşama 11)
- Anything already surfaced and resolved in Aşama 8

If after an honest scan the only candidates you have are
meta-changelog or self-reference, the impact list is empty — and
Aşama 10 is omitted entirely (see "When There Are No Impacts").

## The Dialog Structure

Aşama 10 is NOT a one-shot list. It is a **sequential,
one-impact-per-turn conversation**. For each impact MCL surfaces:

1. MCL presents **one** impact as plain text with a short explanation:
   - **What** is affected (concrete artifact: file path, function,
     consumer component, route)
   - **Why** this change affects it (import, shared state, contract
     break, etc.)
2. MCL immediately calls (since 6.0.0):
   ```
   AskUserQuestion({
     question: "MCL 6.0.0 | <localized impact decision prompt>",
     options: [
       "<apply-fix-in-language>",    # MCL patches the consumer in-place (see below)
       "<skip-in-language>",         # accept the impact as-is
       "<make-rule-in-language>"     # triggers Rule Capture
     ]
   })
   ```
3. MCL STOPS and waits for the tool_result **in the next message**.
4. On tool_result: execute the chosen action, then present the next
   impact.
   - **"Apply fix"** means MCL edits the affected downstream file directly
     within Aşama 10 — not a return to Aşama 7. The spec is already
     approved; `scope_paths` and `phase_review_state=running` remain active
     throughout. There is no "go back to Aşama 7" mechanism. If the required
     fix is too large for an in-place patch (e.g. requires architectural
     changes to the original Aşama 7 deliverable), surface it as a new task
     for the next session instead of attempting it here.
5. Repeat until all impacts are resolved.

⛔ STOP RULE: After presenting an impact and calling `AskUserQuestion`,
STOP. Do NOT list the next impact in the same response. Do NOT proceed
to Aşama 11. Wait for the tool_result.

## When There Are No Impacts

If after an honest scan MCL finds no real downstream impacts, OMIT
Aşama 10 entirely from the response — no header, no placeholder
sentence, no whitespace filler — and proceed silently to Aşama 11.
The scan still *happens*; only its output is suppressed when clean.
"No news = good news" is the user-facing contract.

Never fabricate impacts to fill the section. Never surface
self-referential changelog items. Never re-surface items already
handled in Aşama 8.

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
  Aşama 10 resolution because the dir was missing.

The impact dir is NOT the risks dir. Aşama 8 risks are resolved
in-session and are NOT persisted — per the captured rule that
unambiguous risks auto-fix silently and surfaced ones get an
immediate skip/fix/rule decision. Only impacts cross the
session boundary, because downstream effects can be genuine "I'll
check this next week" items. Risks cannot.

## Anti-Patterns

For Aşama 10 anti-patterns, see `my-claude-lang/anti-patterns.md` —
anti-patterns live in a single file to avoid drift.

## Audit Emit on Completion (since v10.1.6; dual-emit since v10.1.22)

When all impacts are resolved (or Aşama 18 is omitted because no real
impacts surfaced), BEFORE handing off to Aşama 19 (Verification),
emit BOTH the v11 audit name AND the v10 alias:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log asama-19-complete mcl-stop "impacts=N resolved=R"'
```

Where N is the count of impacts surfaced (0 when omitted) and R is
the count of resolved decisions (apply / skip / rule-capture).

The v10 alias `asama-10-complete` keeps existing v10 enforcement at
mcl-stop.sh:1034+ (progression-from-emit transition) operating during
the bridge. R8 cutover removes the alias line.

Aşama 18 is a TRANSIENT phase (no persisted state field). The emit
serves trace.log completeness so the developer can prove the impact
review ran end-to-end. Stop hook scans audit.log and writes
`phase_transition 10 11` (v10 numbering — will become 18 19 in R8) to
trace.log.

</mcl_phase>
