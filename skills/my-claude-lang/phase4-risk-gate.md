<mcl_phase name="phase4-risk-gate">

> ⚠️ SYNC NOTE: The active Phase 4 risk-gate rule lives in
> `mcl-activate.sh` STATIC_CONTEXT (the
> `<mcl_phase name="phase4-risk-gate">` block). This file is the
> extended reference. When updating Phase 4 behavior, BOTH must be
> updated together.

# Phase 4: Risk Gate

Phase 4 is a **mandatory, sequential, interactive dialog** that runs
AFTER Phase 3 (code is written) and BEFORE Phase 5 (Verification
Report).

Scope: security, DB, UI/a11y, architectural drift, intent violation,
plus the embedded code-review / simplify / performance / observability
lenses. HIGH severity findings auto-block writes; the impact lens is
described in `my-claude-lang/phase4-impact-lens.md`.

## Why Phase 4 Exists

In MCL 9.x and earlier, the Phase 5 Verification Report mixed risks
and report content. The risk decisions changed the report's
must-test list and impact analysis — meaning the report was
emitted before the developer had a chance to act on the risks. If
the developer then asked for a fix, the report's Impact Analysis
and must-test list were already stale.

Phase 4 fixes this: risks are reviewed **first**, the developer's
decisions (skip / apply fix / make general rule / override) are
applied, and only THEN does Phase 5 emit a report that reflects
reality.

## When Phase 4 Runs

Immediately after Phase 3 finishes writing code. Phase 3 does NOT
end with "done" or a changes summary — it hands off to Phase 4.

## Batch Decision

When the **total risk count for this Phase 4 turn ≥ 3**, MCL emits
ONE batch question BEFORE entering the per-risk sequential dialog:

```
AskUserQuestion({
  question: "MCL {{MCL_VERSION}} | <localized prompt: N risk listelendi — toplu karar ver, yoksa tek tek bak>",
  options: [
    "<accept-all-in-language>",   # all risks accepted (auto-fix where fixable, others noted)
    "<reject-all-in-language>",   # all risks dismissed (developer takes responsibility)
    "<one-by-one-in-language>"    # fall through to existing sequential dialog
  ]
})
```

On `accept-all`: MCL records `phase4_batch_decision="accept_all"`,
applies fix-where-fixable for every risk, emits ONE summary line per
risk in the response, then closes the Phase 4 dialog in this single
turn.

On `reject-all`: MCL records `phase4_batch_decision="reject_all"`,
notes each risk as "developer-accepted" in the audit, closes dialog.
Phase 6 (b) regression scan still re-runs and re-surfaces any HIGH
that materialized after the dismiss — there is no escape value, just
a UX ergonomy.

On `one-by-one`: records `phase4_batch_decision="one_by_one"` and
proceeds to the sequential dialog below.

**Threshold:** 1 or 2 risks → skip the batch question, ask one by one
directly (batching overhead for 2 risks is illogical — already 2
turns).

State write (skill prose Bash):

```bash
bash -c '
[ -n "${MCL_STATE_DIR:-}" ] && [ -f "$MCL_STATE_DIR/skill-token" ] \
  && export MCL_SKILL_TOKEN="$(cat "$MCL_STATE_DIR/skill-token")"
for lib in "$MCL_HOME/lib/hooks/lib/mcl-state.sh" \
           "$HOME/.mcl/lib/hooks/lib/mcl-state.sh" \
           "$HOME/.claude/hooks/lib/mcl-state.sh"; do
  [ -f "$lib" ] && source "$lib" && break
done
mcl_state_set phase4_batch_decision "accept_all" >/dev/null 2>&1
mcl_audit_log "phase4_batch_decision" "phase4" "accept_all (count=N)" 2>/dev/null || true
'
```

(Replace `accept_all` with `reject_all` or `one_by_one` per developer
choice; `count=N` is the total risk count surfaced this turn.)

## The Dialog Structure

Phase 4 is NOT a one-shot list. It is a **sequential, one-risk-per-turn
conversation**. For each risk MCL surfaces:

1. MCL presents **one** risk as plain text with a short explanation of
   why it matters (security / data integrity / performance / regression
   / UX / drift / intent-violation / etc.)
2. MCL immediately calls `AskUserQuestion`. The OPTIONS depend on the
   risk's severity AND category.

   ### Risk Decision Options (severity-aware)

   | Severity | Category | Options |
   |---|---|---|
   | **HIGH** | any | apply-fix / **override** (reason mandatory; logged) |
   | **MEDIUM** | Security / DB / IntentViolation | apply-fix / **override** (reason mandatory) |
   | **MEDIUM** | UI / Perf / Ops / Code-Review / Simplify / Test / Drift | apply-fix / skip / make-rule |
   | **LOW** | any | apply-fix / skip / make-rule |

   ```
   AskUserQuestion({
     question: "MCL {{MCL_VERSION}} | <localized risk decision prompt>",
     options: [
       "<apply-fix-in-language>",
       // For HIGH or MEDIUM-sec/db/intent: replace skip+make-rule with:
       "<override-in-language>",
       // For other rows: keep:
       "<skip-in-language>",
       "<make-rule-in-language>"
     ]
   })
   ```

   ### Override Path (HIGH + MEDIUM-security/db/intent only)

   When `override` is selected, IMMEDIATELY call a second
   `AskUserQuestion` with question prefix `MCL {{MCL_VERSION}} |` and
   the localized prompt "Override reason (one sentence, will be
   logged):" — `multiSelect: false`, options `["devam", "iptal"]` plus
   a free-text answer requested via the question body. Capture the
   reason and emit BOTH:

   - **Marker emission (preferred):**
     ```
     <mcl_state_emit kind="phase4-override">{"rule_id":"<RULE_ID>","severity":"<HIGH|MEDIUM>","category":"<sec|db|intent|...>","reason":"<one-sentence reason>"}</mcl_state_emit>
     ```
   - **Bash alternative (fallback, audit caller=skill-prose):**
     ```bash
     mcl_audit_log "phase4_override" "phase4" "rule=<RULE_ID> severity=<HIGH|MEDIUM> category=<sec|db|intent|...> reason=<text>"
     ```

   The override reason flows into the Phase 5 Verification Report
   (rendered as `[Override: <reason>]` next to the requirement) and
   the audit log. Phase 6 (a) cross-references skipped HIGH/MEDIUM-
   sec/db/intent findings against `phase4_override` events;
   mismatches surface as LOW soft fail.

3. MCL STOPS and waits for the tool_result **in the next message**.
4. On tool_result: execute the chosen action (apply-fix / override-
   with-reason / skip / make-rule), then present the next risk.
5. Repeat until all risks are resolved.

⛔ STOP RULE: After presenting a risk and calling `AskUserQuestion`,
STOP. Do NOT list the next risk in the same response. Do NOT proceed
to Phase 5. Wait for the tool_result.

## Spec Compliance Pre-Check

Before the automated SAST scan and the category-based risk review,
Phase 4 first verifies that every MUST and SHOULD requirement from
the `📋 Spec:` body emitted at Phase 3 entry was implemented in
Phase 3.

How:
1. Retrieve the Phase 3 spec from conversation context (the
   `📋 Spec:` block emitted at Phase 3 entry). If the spec is
   unrecoverable from context, skip this step silently and proceed
   to the SAST scan.
2. Walk every MUST requirement, then every SHOULD requirement.
3. For each requirement: inspect the Phase 3 code to determine
   whether it is fully implemented, partially implemented, or
   absent.
4. **Fully implemented** → silent pass — do NOT list it, do NOT
   report it.
5. **Partially implemented or absent** → surface as a Phase 4 risk
   in the sequential dialog, same format as all other risks:
   - Cite the spec requirement verbatim (one sentence)
   - Explain what is missing or incomplete in the implementation
   - Offer the appropriate options (apply fix / skip / make rule)
   - STOP and wait for the developer's reply before continuing.

Spec gaps feed into the **same sequential dialog** as SAST findings
and category-based risks — not a separate section, no block heading.
They appear first so they can be fixed before new implementation
risks are reviewed.

Empty result: if every MUST/SHOULD is fully implemented, skip this
step entirely and proceed silently to the SAST scan.

## Architectural Drift Detection (NEW in 10.0.0)

Phase 4 verifies that every file written in Phase 3 lives within
`state.scope_paths` (populated from the spec's Technical Approach
section at Phase 3 entry). Writes outside `scope_paths` are **drift
events** and are surfaced as risks in the sequential dialog with
severity computed by relationship to declared scope:

| Condition                                                                 | Severity | Default options          |
| ------------------------------------------------------------------------- | -------- | ------------------------ |
| `scope_paths` is empty (no spec, or spec lacked file paths)              | **LOW**  | apply-fix / skip / rule  |
| Path is sibling/parallel to declared scope (same directory tree, different leaf — e.g. `src/components/Foo.tsx` written when scope was `src/components/Bar.tsx`) | **MEDIUM** | apply-fix / skip / rule |
| Path crosses to a different layer than declared scope (e.g. spec said frontend `src/pages/`, write touched `src/api/` or `src/lib/db/`) | **HIGH** | apply-fix / **override** (reason mandatory) |

HIGH drift findings auto-block any further writes from completing
their batch — the dialog turn must resolve the drift before more
code is allowed. The Phase 4 hook enforces this with
`decision:block` on the next pre-tool call until the drift item is
resolved.

Risk surface format (one drift event = one risk turn):

```
[Drift] Phase 3 wrote `<path>` but declared scope_paths did not
include this layer. Declared scope: `<list>`. Likely architectural
drift from the approved direction.

Options:
  (a) Move the implementation back into the declared scope
  (b) Update spec scope_paths to include this layer (re-emit spec
      addendum) — only valid for sibling/MEDIUM cases
  (c) Override with reason — only for HIGH cross-layer drift,
      reason logged for Phase 6
```

Empty `scope_paths` is the "spec wrote no Technical Approach paths"
case — the LOW severity item asks the developer once whether to
backfill scope, then closes.

## Intent Violation Check (NEW in 10.0.0)

Phase 4 scans `state.phase1_intent` for **negation phrases** and
cross-references them against the Phase 3 writes. The match table:

| Negation phrase pattern (any language)         | Forbidden write signal                                                  |
| ---------------------------------------------- | ----------------------------------------------------------------------- |
| "no auth", "auth yok", "no authentication"     | Imports of `passport`, `next-auth`, `bcrypt`, JWT libs, session middleware |
| "no DB", "veritabanı yok", "no database"       | Imports of `prisma`, `drizzle`, `mongoose`, `sequelize`, raw `pg`, `mysql2`, `sqlite3`; new schema/migration files |
| "no backend", "backend yok"                    | Files written under backend allowlist paths (`src/api/**`, `src/server/**`, `server.{js,ts}`, route handlers) |
| "without `<X>`", "`<X>` olmadan"               | Imports or APIs matching `<X>` (extracted as keyword)                   |

Severity is **HIGH** for every intent-violation match. The dialog
turn cites:
1. The negation phrase from `phase1_intent` (verbatim, in the
   developer's language).
2. The matching write (file:line + import statement).
3. The implication: "Phase 1 said `<phrase>` but Phase 3 wrote
   `<violation>`."

HIGH severity blocks Write/Edit/MultiEdit for the rest of the
session until either:
- The violating import / file is removed (apply-fix), OR
- The developer overrides with a reason (logged to audit and
  surfaced in Phase 5 verification report and Phase 6 final
  review).

The block is enforced by `mcl-pre-tool.sh` — pending intent
violations set `state.phase4_intent_block=true`, which causes
pre-tool to deny mutations with the message:

> MCL INTENT BLOCK — Phase 1 intent contained a negation phrase
> that conflicts with this write. Resolve the Phase 4 intent
> violation risk first.

## Integrated Quality Scan (per-turn, before each risk-dialog turn)

Before each risk-dialog turn, MCL applies six embedded lenses
**simultaneously** — these are continuous practices designed into
the review from the start, not isolated checkpoints bolted on at
the end:

| Lens | What to look for |
|------|-----------------|
| **(a) Code Review** | Correctness, logic errors, error handling, dead code, missing validations |
| **(b) Simplify** | Unnecessary complexity, premature abstraction, over-engineering, duplicate logic |
| **(c) Performance** | N+1 queries, unbounded loops, blocking synchronous calls, memory leaks, large allocations |
| **(d) Security / DB / UI-A11y** | OWASP Top 10 + ASVS L1 subset; SQL/schema/migration safety; UI design tokens, a11y, responsive (orchestrator scans below) |
| **(e) Brief-Phase-1 Scope Drift** | Implementation elements lacking traceability to a Phase 1 confirmed parameter AND lacking a `[default: X, changeable]` marker — likely Phase 1.5 upgrade-translator hallucination |
| **(f) Architectural drift / Intent violation** | Writes outside `scope_paths`; imports contradicting `phase1_intent` negation phrases (see sections above) |

Security / DB / UI-A11y / drift / intent are **not separate gate
steps** — they are facets of every risk assessment, surfaced
naturally as part of the same sequential dialog. A finding from any
lens is presented as one risk turn with a label (e.g. `[Security]`,
`[Performance]`, `[Brief-Drift]`, `[Drift]`,
`[IntentViolation]`).

Semgrep SAST findings (HIGH/MEDIUM with unambiguous autofix) are
applied silently and merged into the lens output. The overall scan
is invisible unless it produces surfaceable risks.

### Lens (e): Brief-Phase-1 Scope Drift

Phase 1.5 upgrade-translator transforms vague verbs ("list",
"show", "manage") into surgical English ("render paginated table",
"expose CRUD") and may add `[default: X, changeable]` markers for
verb-implied standard patterns. This lens guards against
**hallucinated scope** — invented features that lack both Phase 1
traceability AND a `[default]` marker.

**When this lens runs:** mandatory when the session's
`engineering-brief` audit shows `upgraded=true`. Skipped silently
when `upgraded=false` (no upgrade happened, no drift possible).

**Procedure per implementation element:**
1. Walk Phase 3 code: each function, route, schema field,
   dependency added in this session.
2. For each element ask:
   - Is it traceable to a Phase 1 confirmed parameter the user
     said?
   - If not, is it carried by a `[default: X, changeable]` marker
     in the brief or spec?
   - If neither: it is **untraced scope** — surface as a
     Brief-Drift risk.
3. Surface format (one risk per drift):
   ```
   [Brief-Drift] Implementation includes <X> (file:line). User did
   not mention <X> in Phase 1; brief/spec has no [default: X,
   changeable] marker for it. Likely Phase 1.5 upgrade-translator
   hallucination.

   Options:
     (a) Remove from spec + Phase 3 code (revert to user intent)
     (b) Mark as [default: <X>, changeable] in spec (user accepts
         the upgrade-translator addition)
     (c) Rule-capture: developer wants this default for all future
         specs of similar shape (writes to CLAUDE.md / .mcl/project.md)
   ```
4. Wait for developer reply before next risk.

## Automated SAST Pre-Scan (Semgrep)

Phase 4 invokes Semgrep as an automated SAST pre-scan over files
MCL wrote or edited in this session's Phase 3. Semgrep findings
either **auto-fix silently** (HIGH / MEDIUM with unambiguous
autofix) or **seed the Phase 4 dialog as regular risks** (HIGH /
MEDIUM without autofix or where multiple valid options exist).
Semgrep never produces a standalone section — its output is merged
into the existing risk-dialog flow.

### Invocation

```
bash ~/.claude/hooks/lib/mcl-semgrep.sh scan <file1> <file2> ...
```

Pass the deduplicated list of files edited or created during Phase 3
of this session. Relative or absolute paths both work. Empty list →
skip the scan. Do NOT scan files that were not touched this session
(delta scope invariant — protects against noisy legacy findings).

### Preflight gate

If `mcl-activate.sh` already emitted a `semgrep-missing` notice this
session, skip the SAST step silently (Semgrep is not installed).
A `semgrep-unsupported-stack` notice does NOT skip the scan — it
fires at session start on the project as it exists then; if Phase 3
subsequently created files of a supported type, the scan must still
run on those files. Phase 4's category-based review below still
runs normally.

### Findings handling

Helper emits JSON:
`{"findings":[{"severity","rule_id","file","line","message","autofix"}, ...],
 "scanned_files":N, "errors":[...]}`.

For each finding:

- **`severity=LOW`** → suppress entirely. Do not surface. Do not log
  to the dialog. (LOW packs too many false positives to be useful
  at this level.)
- **`severity=HIGH` or `MEDIUM`** with a non-null `autofix` AND an
  unambiguous application point → apply the autofix silently via
  `Edit` / `MultiEdit` (per the global captured rule: "auto-fix
  unambiguous Phase 4 risks silently"). Record via
  `mcl_audit_log "semgrep-autofix" "phase4" "rule=<rule_id> file=<file>:<line>"`.
- **`severity=HIGH` or `MEDIUM`** where `autofix` is null, ambiguous,
  or requires a trade-off → surface as a normal Phase 4 risk in
  the sequential dialog. Render the `message` in the developer's
  language, cite `file:line`, offer the appropriate options
  (skip / specific fix / general rule / override).

`errors` entries are logged but do NOT block the Phase 4 dialog —
SAST is advisory, not blocking. Scan timeout or helper failure → one
audit-log line, then proceed to the category-based review below.

### Output discipline

The SAST step is invisible unless it surfaces risks. Never announce
"running Semgrep…", "Semgrep found N issues", or "SAST scan complete".
The developer sees only the risk-dialog turns seeded by Semgrep,
blended with the category-based risks MCL itself identifies.

## Risk Categories to Review

When scanning code for Phase 4 risks, consider:

- **Security**: input validation, auth bypass, secret exposure, injection
- **Data integrity**: race conditions, stale cache, transaction boundaries
- **Performance**: N+1 queries, large DOM renders, unbounded loops
- **Error handling**: unhandled rejections, missing try/catch where needed,
  swallowed errors
- **Regression**: imports of modified files, shared utilities changed,
  API contract shifts
- **UX / a11y**: accessibility, loading states, error states, edge-case UI breaks
- **Concurrency**: shared mutable state, event-listener leaks
- **Observability**: missing logs/metrics for new code paths
- **Drift**: writes outside `scope_paths` (NEW)
- **Intent violation**: imports/files contradicting Phase 1 negation phrases (NEW)

## When There Are No Risks

If after an honest scan MCL finds no risks worth surfacing, OMIT
Phase 4 entirely from the response — no header, no placeholder
sentence, no whitespace filler — and proceed silently to Phase 5.
The scan still *happens*; only its output is suppressed when clean.
"No news = good news" is the user-facing contract.

Never fabricate risks to fill the section. Never present risks
already handled in Phase 1. Never emit a "No risks identified."
sentence — silence is the correct signal.

## Anti-Patterns

For Phase 4 anti-patterns, see `my-claude-lang/anti-patterns.md`
— anti-patterns live in a single file to avoid drift.

## TDD Re-Verify

After every Phase 4 risk is resolved (skipped, fixed, overridden,
or rule-captured), run a TDD re-verify before handing off to the
impact lens — provided `test_command` is configured (`bash
~/.claude/hooks/lib/mcl-config.sh get test_command` returns
non-empty).

Skip the re-verify **only** when Phase 4 was omitted entirely (no
risks found and the phase was silent). If Phase 4 ran — even if
all risks were skipped with no code change — re-verify still runs.
An all-skip re-run costs nothing (tests stay GREEN) and removes any
ambiguity about whether fixes were applied.

How:
1. Run `bash ~/.claude/hooks/lib/mcl-test-runner.sh green-verify`.
2. **GREEN** → proceed to the impact lens, then Phase 5.
3. **RED** → a Phase 4 fix introduced a regression. Surface the
   failing test(s) as a new Phase 4 risk in the sequential dialog:
   - Cite the failing test name and error message
   - State which risk-fix likely caused the regression
   - Offer the appropriate options (fix the regression / revert
     the risk-fix / make rule)
   - STOP, wait for reply, apply decision, re-run TDD. Repeat until
     GREEN, then proceed to the impact lens.
4. **TIMEOUT** → log one audit line (`mcl_audit_log "tdd-rerun-timeout" "phase4"`);
   proceed to impact lens without blocking.

## Comprehensive Test Coverage

After TDD re-verify passes (or if `test_command` is configured),
MCL checks that Phase 3 code is covered by four test categories.
This step follows the same sequential dialog format as all other
Phase 4 risks.

| Category | Applies when |
|----------|-------------|
| **Unit tests** | Any new function, class, or module was created |
| **Integration tests** | New API endpoints, cross-module data flows, DB interactions |
| **E2E tests** | UI stack is active (`is_ui_project=true`) and new user flows were added |
| **Load/stress tests** | Throughput-sensitive paths (queues, bulk processing, high-concurrency endpoints) |

**Mechanic (when `test_command` is configured):**
For each uncovered category, Claude **writes the missing test
file(s)** as a Phase 3 code action — not a dialog turn. After
writing, runs `mcl-test-runner.sh green-verify`. If RED → surfaces
failing test as a new Phase 4 risk in the sequential dialog.

**Mechanic (when `test_command` is NOT configured):**
Documents missing categories in a single Phase 4 risk turn so the
developer knows what to add later. They choose: add tests now /
skip / make-rule.

If all applicable categories are adequately covered, omit this step
entirely (empty-section-omission rule).

Skip this when:
- Phase 4 was entirely omitted (no risks found).
- All four applicable categories are already covered by existing
  tests.

## Lens (d) expanded — UI Design & A11y

When a FE stack-tag (`react-frontend|vue-frontend|svelte-frontend|html-static`) is detected, Phase 4 START runs the UI orchestrator **after** the security gate and DB gate. Mechanism:

**UI design & a11y scan (mandatory at Phase 4 START when FE stack-tag present):**
1. Run via Bash tool: `python3 ${MCL_LIB:-$HOME/.mcl/lib}/hooks/lib/mcl-ui-scan.py --mode=full --state-dir "$MCL_STATE_DIR" --project-dir "${CLAUDE_PROJECT_DIR:-$PWD}" --lang <user_lang>`
2. Parse JSON. If `no_fe_stack=true`: skip; mark `phase4_ui_scan_done=true` and continue.
3. Severity routing (a11y-critical-only block):
   - **HIGH (only `category=ui-a11y`) → Phase 4 START gate.** UI-G01 img-no-alt, UI-G02 button-no-name, UI-G03 link-no-href, UI-G04 input-no-label, UI-G05 div-onClick-no-keyboard, UI-RX-controlled-without-onChange, UI-VU-v-html-untrusted, UI-SV-on-click-no-keyboard, UI-HT-no-html-lang. Do NOT START the Phase 4 dialog — apply Edit/Write fixes for each HIGH first.
   - **MEDIUM (token / reuse / responsive / non-critical a11y / naming) → enters the Phase 4 sequential dialog.** Each MEDIUM is discussed one at a time with `[UI-Design]` or `[UI-A11y]` labels.
   - **LOW → audit-only**, does not enter the dialog. Recorded in `ui-findings.jsonl`; the developer can view via `/mcl-ui-report`.
4. Auto-fix policy: ESLint `--fix` safe categories (formatting, import order, JSX whitespace) silent OK. **a11y / token / reuse / naming** categories are **never silent**.
5. Coverage: Design tokens (UI-G07-G10 + `mcl-ui-tokens.py` C3 hybrid: project tokens or MCL default fallback) / Component reuse (AST fingerprint heuristic) / A11y (UI-G01-G06 + framework add-on + `mcl-ui-eslint.sh` D1 delegate + `/mcl-ui-axe` D2 opt-in) / Responsive (UI-G10 + UI-HT-no-meta-viewport) / Naming (framework prop conventions).

**Audit signal:** `ui-scan-full | mcl-stop | high=N med=N low=N duration_ms=N sources=...`

**Non-overlap with Security / DB lenses:** React unsafe-html-setter XSS / target=_blank rel stay in Security; SQL/schema stay in DB; UI scan does not repeat. `category=ui-*` field provides separation.

If `mcl-ui-scan.py` is unavailable this step is skipped silently.

## Lens (d) expanded — DB Design

When a `db-*` stack tag is detected, Phase 4 START runs the DB orchestrator **after** the security gate has cleared. Mechanism:

**DB design scan (mandatory at Phase 4 START when DB stack-tag present):**
1. Run via Bash tool, in ONE call:
   ```
   python3 ${MCL_LIB:-$HOME/.mcl/lib}/hooks/lib/mcl-db-scan.py \
     --mode=full --state-dir "$MCL_STATE_DIR" \
     --project-dir "${CLAUDE_PROJECT_DIR:-$PWD}" --lang <user_lang>
   ```
2. Parse the JSON output. If `no_db_stack=true`: skip; mark `phase4_db_scan_done=true` and continue.
3. Severity routing:
   - **HIGH finding → Phase 4 START gate.** Do NOT start the Phase 4 dialog. HIGH examples: data-loss migration (DROP COLUMN, TRUNCATE), missing PRIMARY KEY, UPDATE/DELETE without WHERE, ON DELETE CASCADE on user-data without explicit confirmation. Apply Edit/Write fix for each HIGH before moving to the next finding. Schema/migration/index fixes are **NEVER silent** — every fix is presented to the developer with a one-sentence explanation (data-loss risk).
   - **MEDIUM finding → enters the Phase 4 sequential dialog as an item.** Each MEDIUM is discussed one at a time with `[DB-Design]` label. MEDIUM examples: SELECT *, missing FK index, missing eager-load (N+1 static heuristic), TIMESTAMP without timezone, missing migration `down`, ALTER TABLE non-CONCURRENTLY (Postgres lock).
   - **LOW finding → audit-only**, does not enter the dialog. Recorded in `db-findings.jsonl`; the developer can view via `/mcl-db-report`.
4. Auto-fix policy: naming/style fix (CONST_CASE rename, table alias) silent OK. **Schema / migration / index** categories are **never silent** — ask the developer.
5. Coverage: Schema design / Index strategy / N+1 detection / Migration safety (squawk + alembic-check delegate) / Connection pooling (Phase 1.7) / Multi-tenancy (Phase 1.7). EXPLAIN-based query plan analysis `/mcl-db-explain` opt-in (`MCL_DB_URL` env).

**Audit signal:** `db-scan-full | mcl-stop | high=N med=N low=N duration_ms=N sources=...`

**Non-overlap with Security:** SQL injection / hardcoded credential / mass-assignment stay in Security — DB scan does not repeat. `category=db-*` field provides separation.

If `mcl-db-scan.py` is unavailable this step is skipped silently.

## Lens (d) expanded — Backend Security

Phase 4 START runs the security orchestrator BEFORE any other lens. Mechanism:

**Security scan (mandatory at Phase 4 START):**
1. Run via Bash tool, in ONE call:
   ```
   python3 ${MCL_LIB:-$HOME/.mcl/lib}/hooks/lib/mcl-security-scan.py \
     --mode=full --state-dir "$MCL_STATE_DIR" \
     --project-dir "${CLAUDE_PROJECT_DIR:-$PWD}" --lang <user_lang>
   ```
2. Parse the JSON output. Severity routing:
   - **HIGH finding → Phase 4 START gate.** Do NOT start the Phase 4 dialog. Fix HIGH findings sequentially: apply Edit/Write for each HIGH and move to the next finding. The Phase 4 sequential dialog (Lens a-f) does NOT START until every HIGH is fixed. Bare skip is forbidden — HIGH findings cannot be skipped without explicit `--skip-security <rule_id>` developer consent.
   - **MEDIUM finding → enters the Phase 4 sequential dialog as an item.** Each MEDIUM is discussed one at a time with the `[Security]` label (existing sequential dialog mechanic).
   - **LOW finding → audit-only**, does not enter the dialog. Recorded in `security-findings.jsonl`; the developer can view via `/mcl-security-report`.
3. Auto-fix policy: For Semgrep `autofix` field-populated **safe categories** (formatting, deprecated rename, import order) silent apply. In **auth / crypto / secret / authz** categories silent apply is forbidden — always surface in the dialog and require developer approval.
4. Coverage: A01-A03, A05-A08, A10 OWASP Top 10 + ASVS L1 V2/V3/V4/V5/V6/V7/V8 subset. A04 (Insecure Design) and A09 (Logging) are handled at Phase 1.7 design time — no runtime detection in Phase 4.

**Audit signal:** `security-scan-full | mcl-stop | high=N med=N low=N duration_ms=N sources=...`

If `mcl-security-scan.py` is unavailable this step is skipped silently; Lens (d) falls back to model-behavioral checklist behavior (heuristic injection / auth / CSRF scan).

## Handoff to the Impact Lens, then Phase 5

After every risk is resolved (including drift, intent violation,
test coverage, and any HIGH security/DB items) and TDD re-verify
passes (or is skipped), proceed to the impact lens
(`my-claude-lang/phase4-impact-lens.md`) which is part of Phase 4,
not a separate phase. After the impact lens completes, hand off to
Phase 5 (Verification Report). Phase 5 MUST reflect Phase 4
decisions — fixes applied, risks accepted, overrides recorded,
rules captured, impacts patched.

</mcl_phase>
