<mcl_phase name="all-mcl-reference">

# MCL Step Catalog

Machine-readable reference of every MCL step in execution order.
Used by `mcl check-up` to evaluate session health.
Each step has a stable STEP-NN ID, a signal (what to look for in logs),
a Pass condition, and a Skip condition.

**Log sources:**
- `trace.log` — `<ISO-UTC> | <event> | <args>` (deterministic hook events)
- `audit.log` — `<datetime> | <event> | <source> | <key=val ...>` (operational events)
- `state.json` — JSON phase state machine
- `log/TIMESTAMP.md` — session diary (all tool calls with AskUserQuestion entries)
- `specs/*.md` — approved spec files
- `impact/*.md` — Phase 4.6 impact files

---

## PRE-SESSION STEPS

### STEP-01: session-boundary
**Phase:** Pre-Session | **Description:** mcl-activate.sh detects a new session_id and resets task-scoped state flags (partial_spec, phase_review_state) so stale prior-task state cannot bleed into the new session.
**Signal:** audit.log contains `set | mcl-activate.sh | field=phase_review_state value=null` near the session_start timestamp. state.json `plugin_gate_session` equals the current session_id.
**Pass:** audit.log has at least one session-boundary reset write (partial_spec or phase_review_state reset to false/null). state.json `last_update` timestamp is close to session_start in trace.log.
**Skip:** Never skipped — fires on every distinct session_id.

---

### STEP-02: version-banner
**Phase:** Pre-Session | **Description:** Claude emits the `🌐 MCL X.Y.Z` banner as the first token of every developer-facing response, every turn, no exceptions.
**Signal:** trace.log first event is `session_start | X.Y.Z`. Session diary first bullet contains the MCL version string.
**Pass:** trace.log has `session_start` event. Version string appears in the session diary.
**Skip:** Never skipped — STATIC_CONTEXT rule 1 is absolute.

---

### STEP-03: stack-detection
**Phase:** Pre-Session | **Description:** mcl-activate.sh calls mcl-stack-detect.sh; result is logged as `stack_detected` event with detected language tags. `ui_flow_active` is set based on whether a UI-capable stack was found.
**Signal:** trace.log contains `stack_detected | <tags>` on the session's first turn. state.json `ui_flow_active` is `true` or `false` (not null). audit.log contains `ui-flow-autodetect | mcl-activate.sh | ui_capable=<bool>`.
**Pass:** trace.log has `stack_detected` event AND state.json `ui_flow_active` is explicitly set.
**Skip:** When the project has no source files OR no recognizable stack tags at session start — `STACK_TAGS` is empty, so `mcl_trace_append stack_detected` is NOT called (guarded by `[ -n "$STACK_TAGS" ]`). Correct skip when: trace.log has no `stack_detected` line for this session AND audit.log has `ui-flow-autodetect | ui_capable=false`. Do NOT mark as WARN if detection ran but found nothing — that is a legitimate skip.

---

### STEP-04: plugin-gate
**Phase:** Pre-Session | **Description:** mcl-activate.sh checks required plugins and binaries. If any are missing, `plugin_gate_active=true` is set in state.json and a HARD-GATED notice blocks mutating tools for the session.
**Signal:** audit.log line `plugin-gate-activated | mcl-activate.sh | missing=...` on session start if plugins are absent. state.json `plugin_gate_active` is `true` or `false`.
**Pass:** state.json `plugin_gate_active` is explicitly set (not absent). audit.log records the check outcome.
**Skip:** Never skipped — check always runs on the first prompt of each session_id.

---

### STEP-05: semgrep-preflight
**Phase:** Pre-Session | **Description:** mcl-activate.sh calls `mcl-semgrep.sh preflight`; result is one of: `semgrep-ready`, `semgrep-cache-stale`, `semgrep-unsupported-stack`, `semgrep-missing`, or `semgrep-empty-project`. Result is injected as an `mcl_audit` block.
**Signal:** audit.log line `semgrep-preflight | mcl-activate | <status>` (or the mcl_audit block appears in the session diary's first turn context).
**Pass:** audit.log has a `semgrep-preflight` entry for this session. OR the `semgrep-unsupported-stack` / `semgrep-missing` mcl_audit block fired (visible in session context — acceptable outcomes).
**Skip:** Only when `mcl-semgrep.sh` is not present in `hooks/lib/` (incomplete installation).

---

## PHASE 1 STEPS

### STEP-10: intent-gathering
**Phase:** 1 | **Description:** Claude applies disambiguation triage before asking any question. SILENT path: trivial defaults and reversible choices are assumed and marked in the spec (`[assumed: X]` / `[default: X, changeable]`) without asking. GATE path: only schema/migration decisions, auth/permission model, public API breaking changes, irreversible data consequences, and security boundary decisions trigger a question — one at a time. Parameters that do not require a gate are resolved silently.
**Signal:** Session diary shows plain-text question turns ONLY for gate-category ambiguities before the summary AskUserQuestion. No `📋 Spec:` block appears before `summary_confirmed` in trace.log.
**Pass:** `summary_confirmed` event in trace.log. Gate questions are only for irreversible decisions. Trivial/reversible assumptions appear as `[assumed: X]` or `[default: X, changeable]` markers in the spec.
**Skip:** When the developer's first message already contains all parameters with no ambiguity — summary appears immediately. Still passes if `summary_confirmed` is present.

---

### STEP-11: plugin-suggestions
**Phase:** 1 | **Description:** On the first developer message, if stack-matched plugins are missing, MCL presents AskUserQuestion suggestions (one per plugin) before Phase 1 gathering starts.
**Signal:** Session diary first substantive turn references missing plugin names. audit.log may contain `plugin-gate-activated` entries.
**Pass:** If `plugin_gate_active=true` in state.json, the session diary shows an AskUserQuestion referencing plugin install commands on the first turn.
**Skip:** When all stack-matched plugins are already installed (`plugin_gate_active=false`), or the project is empty. Correct and expected skip.

---

### STEP-12: summary-confirmation
**Phase:** 1 | **Description:** Claude presents the Phase 1 summary as plain text, then immediately calls AskUserQuestion with prefix `MCL X.Y.Z | ` and options Approve/Edit/Cancel. State transitions to Phase 2 on approval.
**Signal:** trace.log contains `summary_confirmed | approved`. audit.log contains `summary-confirm-approve | stop`.
**Pass:** trace.log has `summary_confirmed` event followed by `phase_transition | 1 | 2`.
**Skip:** Never skipped — mandatory before Phase 2.

---

## PHASE 2/3 STEPS

### STEP-20: spec-emission
**Phase:** 2 | **Description:** Claude emits the visible `📋 Spec:` block. Six base sections always present: Objective, MUST/SHOULD, Acceptance Criteria, Edge Cases, Technical Approach, Out of Scope. Up to five conditional sections appear only when triggered: Non-functional Requirements (perf/scale constraints), Failure Modes & Degradation (external deps/async/distributed), Observability (critical path/audit/tracking), Reversibility/Rollback (migrations/destructive ops/feature flags), Data Contract (API/schema changes/cross-service).
**Signal:** mcl-stop.sh computes `SPEC_HASH` and writes it to state.json. state.json `current_phase` transitions to 2.
**Pass:** state.json `spec_hash` is non-null and `current_phase` is 2 or higher. Conditional sections present iff their trigger applies.
**Skip:** Never skipped — the spec is the MCL pipeline's core deliverable.

---

### STEP-20b: partial-spec-recovery
**Phase:** 2 | **Description:** When a spec was truncated mid-emission (rate-limit or network drop), state.json `partial_spec=true` is set. The activate hook injects a recovery audit block on the next turn forcing a full re-emission.
**Signal:** state.json `partial_spec=true`. audit.log contains `partial-spec | stop | missing=<sections>`.
**Pass:** `partial_spec` cleared back to `false` after a complete spec was re-emitted. audit.log shows `partial-spec-cleared`.
**Skip:** When no truncation occurred (`partial_spec=false` or absent throughout). Correct and expected skip.

---

### STEP-21: phase-1-to-2-transition
**Phase:** 2 | **Description:** mcl-stop.sh detects the spec block in the assistant turn and transitions `current_phase` from 1 to 2 (`SPEC_REVIEW`).
**Signal:** trace.log contains `phase_transition | 1 | 2` AFTER the current-session's `session_start` line. state.json `current_phase=2`. audit.log contains a `set | mcl-stop.sh | field=current_phase value=2` (or equivalent state write) near the spec emission time.
**Pass:** trace.log has `phase_transition | 1 | 2` in the current-session segment (after the last `session_start`). When evaluating check-up: if audit.log confirms the transition but trace.log is missing the event, report as ⚠️ WARN (intermittent trace write failure) rather than ❌ FAIL — the state machine did advance correctly.
**Skip:** Never skipped when a spec was emitted in Phase 1 context.

---

### STEP-22: spec-approval
**Phase:** 3 | **Description:** After presenting the translated spec summary, Claude runs a Technical Challenge Pass: silently checks for concrete technical problems (scale issues, race conditions, N+1, missing auth, cascading failures). If a concrete problem is found, one localized `⚠️ Teknik not:` line is added BEFORE the AskUserQuestion call — not a gate, but visible to the developer. Then Claude calls AskUserQuestion with prefix `MCL X.Y.Z | ` and options Approve/Edit/Cancel. On approval, mcl-stop.sh transitions to Phase 4: `spec_approved=true`, `current_phase=4`.
**Signal:** trace.log contains `spec_approved | <hash12>` and `phase_transition | 2 | 4` (or `3 | 4`). audit.log contains `approve-via-askuserquestion | stop`. state.json `spec_approved=true`, `current_phase=4`.
**Pass:** trace.log has both `spec_approved` and `phase_transition` to 4. state.json `spec_approved=true`. Technical Challenge Pass ran (silently if no issues found).
**Skip:** Never skipped — explicit approval is mandatory before Phase 4.

---

### STEP-23: spec-saved
**Phase:** 3→4 | **Description:** mcl-spec-save.sh writes the approved spec body to `.mcl/specs/NNNN-slug.md` with YAML frontmatter (spec_id, approved_at, spec_hash, branch, head_at_approval).
**Signal:** `.mcl/specs/` directory contains at least one `*.md` file. audit.log contains `spec-saved | mcl-spec-save.sh`.
**Pass:** `.mcl/specs/` contains at least one spec file per approved spec in this session.
**Skip:** Never skipped — spec save is automatic on every AskUserQuestion approval transition.

---

### STEP-24: test-command-resolution
**Phase:** 3→4 | **Description:** After spec approval and spec-save, MCL resolves the test command via four priority steps: (1) `.mcl/config.json`, (2) auto-detect from manifests, (3) infer from the approved spec's Technical Approach section (e.g. "pytest" for Python+pytest, "go test ./..." for Go), (4) one-off developer question only if still unresolved. Positioned after spec approval so the spec's stack information can inform the inference.
**Signal:** `.mcl/config.json` contains `test_command` if the developer set it. Session diary shows test command resolution (question or silent inference) after `spec_approved` trace event and before first Phase 4 code write.
**Pass:** Either `test_command` is resolved (config / auto-detect / spec inference), OR the developer explicitly declined (TDD flow skipped for session). The question was NOT asked before spec approval.
**Skip:** When `test_command` was already in config, auto-detected from manifests, or confidently inferred from spec — no developer question needed.

---

## PHASE 4 STEPS

### STEP-40a: ui-build-phase
**Phase:** 4a | **Description:** When `ui_flow_active=true`, Claude writes frontend-only code with dummy data, no backend writes. Dev server is started and browser opened. Stops and waits for developer feedback before Phase 4b. UI phases run first so visual scaffolding is reviewed before backend logic is written.
**Signal:** state.json `ui_sub_phase="BUILD_UI"`. audit.log `ui-flow-enter-build | stop`. trace.log `ui_flow_enabled`.
**Pass:** trace.log contains `ui_flow_enabled`. state.json `ui_sub_phase` progressed past `BUILD_UI`.
**Skip:** When `ui_flow_active=false` (no UI stack detected). Standard Phase 4 runs instead. Correct and expected skip.

---

### STEP-40b: ui-review-phase
**Phase:** 4b | **Description:** Developer provides free-form visual feedback. MCL calls AskUserQuestion with options approve-backend/revise/see-yourself/cancel. Only Approve exits to Phase 4c.
**Signal:** audit.log `approve-ui-review-via-askuserquestion | stop`. trace.log `ui_review_approved`. state.json `ui_reviewed=true`, `ui_sub_phase="BACKEND"`.
**Pass:** trace.log contains `ui_review_approved`. state.json `ui_reviewed=true`.
**Skip:** When `ui_flow_active=false`. Correct and expected skip.

---

### STEP-40c: ui-backend-phase
**Phase:** 4c | **Description:** Backend path lock lifts after `ui_reviewed=true`. Claude replaces dummy fixtures with real API routes, data layer, async state, error/loading/empty states.
**Signal:** state.json `ui_sub_phase="BACKEND"`. Session diary shows backend file writes after `ui_review_approved` trace event.
**Pass:** Session diary contains Write/Edit entries for backend files after `ui_review_approved`.
**Skip:** When `ui_flow_active=false`. Correct and expected skip.

---

### STEP-41: code-writing
**Phase:** 4 | **Description:** Claude writes code using Write/Edit/MultiEdit tools, all code in English, all communication in the developer's language. Writes stay within the approved spec's scope. For UI stacks, general code-writing runs after the UI sub-phases (40a/b/c) complete.
**Signal:** Session diary shows Write/Edit tool call entries. mcl-stop.sh sets `phase_review_state` via mcl-phase-review-guard.py on code-written turns. state.json `current_phase=4`.
**Pass:** Session diary contains Write or Edit tool entries after spec approval. state.json `current_phase=4`.
**Skip:** Never skipped when spec is approved — Phase 4 always writes code.

---

### STEP-42: phase-review-enforcement
**Phase:** 4→4.5 | **Description:** When code is written without Phase 4.5 dialog starting in the same turn, mcl-stop.sh sets `phase_review_state="pending"` and returns `decision:block`. "pending" is STICKY: the BLOCK re-fires on every subsequent turn (including Bash-only and text-only turns) until AskUserQuestion is called, transitioning state to "running".
**Signal:** audit.log `phase-review-pending | stop | prev=... phase=4 code=...`. trace.log `phase_review_pending | ...`. state.json `phase_review_state="pending"`.
**Pass:** `phase_review_state` transitions from `pending` to `running` when Phase 4.5 starts. The `pending` state persists until cleared by `askuq=true` — multiple audit.log `phase-review-pending` entries in a row are expected and correct (sticky re-block).
**Skip:** When Phase 4.5 starts in the same turn as the last code write (AskUserQuestion called immediately). In this case state goes directly to `running` without `pending`.

---

### STEP-42b: phase-review-recovery
**Phase:** 4.5 (interrupted session resume) | **Description:** When `phase_review_state="running"` fires on a new `UserPromptSubmit`, the session was interrupted mid-Phase 4.5. MCL injects a `phase-review-recovery` audit block. Claude reads `.mcl/risk-session.md`, compares `phase4_head` to current HEAD, and resumes from the first unreviewed risk without telling the developer the session was interrupted.
**Signal:** state.json `phase_review_state="running"` at session start (i.e., no AskUserQuestion in-flight). audit.log `phase-review-recovery | activate | head-match=true` (HEAD matched) or `phase-review-recovery | activate | head-match=false` (HEAD changed, fresh run).
**Pass:** Claude resumes the risk dialog seamlessly: HEAD-matched risks already in `.mcl/risk-session.md` Reviewed list are skipped silently; remaining risks are presented via AskUserQuestion. Developer sees no interruption marker.
**Recovery:** When HEAD differs from `phase4_head` in the file (new commits since interruption), Claude deletes/resets the file and runs Phase 4.5 fresh — correct because code changed.

---

## PHASE 4.5 STEPS

### STEP-450: spec-compliance-precheck
**Phase:** 4.5 | **Description:** Before the quality scan, Phase 4.5 walks every MUST and SHOULD in the approved spec and surfaces any missing or partial implementations as risks in the sequential dialog.
**Signal:** AskUserQuestion calls in session diary reference spec MUST/SHOULD requirement text. state.json `phase_review_state="running"`. audit.log `phase-review-running | stop`.
**Pass:** Either no spec gaps (silent pass — no marker needed), OR AskUserQuestion was called for each gap found. `phase_review_state` progressed to `running`.
**Skip:** When every MUST/SHOULD was fully implemented in Phase 4 (silent skip — correct behavior). Indistinguishable from STEP-452 skip; both are silent if Phase 4.5 was entirely omitted.

---

### STEP-451: integrated-quality-scan
**Phase:** 4.5 | **Description:** Before each risk-dialog turn, MCL applies four embedded lenses simultaneously as continuous practices (not sequential steps): (a) CODE REVIEW — correctness, logic errors, error handling, dead code; (b) SIMPLIFY — unnecessary complexity, premature abstraction, over-engineering; (c) PERFORMANCE — N+1 queries, unbounded loops, blocking ops, memory leaks (embedded practice, not a gate); (d) SECURITY — injection, auth bypass, XSS, CSRF, data exposure (embedded practice, not a gate). Semgrep SAST auto-fixes (HIGH/MEDIUM with unambiguous autofix) are applied silently and merged into the lens findings.
**Signal:** audit.log `semgrep-autofix | phase4-5 | rule=<id> file=<path:line>` for auto-applied fixes. Risk dialog AskUserQuestion entries reference category labels (code-review / simplify / performance / security). state.json `phase_review_state="running"`.
**Pass:** Each risk-dialog turn is preceded by a multi-lens scan. audit.log has `semgrep-autofix` entries for any auto-fixed findings. If scan is clean across all lenses, no marker needed — acceptable silent pass.
**Skip:** When Phase 4.5 found zero risks across all lenses (entire phase omitted silently — correct). Semgrep scan step skipped when `semgrep-missing` notice fired at session start.

---

### STEP-452: risk-dialog
**Phase:** 4.5 | **Description:** Sequential one-risk-per-turn dialog. Each risk (sourced from spec gaps, any of the four quality lenses, or Semgrep findings) is presented via AskUserQuestion with options apply-fix/skip/make-rule. Developer resolves all risks before Phase 4.6.
**Signal:** audit.log `phase-review-running | stop`. AskUserQuestion entries in session diary with `MCL X.Y.Z | ` prefix and risk-decision options.
**Pass:** state.json `phase_review_state="running"` appears. Session diary shows at least one risk-decision AskUserQuestion entry.
**Skip:** When Phase 4.5 found zero risks after honest review (entire phase silently omitted — correct behavior). Detectable by: `phase_review_state` never becomes `"running"` AND `current_phase` advanced to 5.

---

### STEP-453: tdd-re-verify
**Phase:** 4.5 | **Description:** After all risks are resolved (if Phase 4.5 ran), `mcl-test-runner.sh green-verify` is called if `test_command` is configured. This is a post-risk full-suite run — separate from the per-criterion GREEN verifies in Phase 4.
**Signal:** Session diary shows a GREEN verify block after risk resolution. audit.log `tdd-rerun-timeout | phase4-5` only on timeout. trace.log may contain a `test-run` event.
**Pass:** Session diary shows GREEN test runner output before Phase 4.6 begins, OR `test_command` is not configured (no runner invoked — acceptable), OR Phase 4.5 was entirely omitted.
**Skip:** When Phase 4.5 was entirely omitted (no risks found), OR `test_command` is not configured in `.mcl/config.json`.

---

### STEP-454: comprehensive-testing
**Phase:** 4.5 | **Description:** After TDD re-verify passes, MCL checks that Phase 4 code is covered by four test categories: unit tests (individual functions/components), integration tests (cross-module interactions, API contracts), E2E tests (user flows — if UI stack active), load/stress tests (throughput-sensitive paths — if applicable). When `test_command` is configured, Claude **writes** missing test files directly as Phase 4 code actions (not AskUserQuestion turns), then runs green-verify; RED surfaces as a new risk. When `test_command` is NOT configured, missing categories are documented in a single risk-dialog turn (add now / skip / make-rule).
**Signal:** When test_command configured: session diary shows Write/Edit entries for test files after TDD re-verify, followed by a green-verify run. When test_command not configured: session diary shows a single AskUserQuestion citing missing test categories.
**Pass:** All applicable test categories are covered, OR missing categories were either written (test_command present) or surfaced as a risk turn (test_command absent) and developer decided skip/fix/rule. Silently omitted when all categories are already covered.
**Skip:** When Phase 4.5 was entirely omitted (no risks found), OR all four test categories are already covered by existing tests.

---

## PHASE 4.6 STEPS

### STEP-460: impact-detection
**Phase:** 4.6 | **Description:** Sequential one-impact-per-turn dialog. Each real downstream effect on other project files presented via AskUserQuestion. Developer resolves all impacts.
**Signal:** AskUserQuestion entries in session diary cite file paths, functions, or API consumers affected by Phase 4 changes. `.mcl/impact/` directory grows by one file per resolved impact.
**Pass:** `.mcl/impact/` contains `*.md` files written during this session. Session diary shows impact-decision AskUserQuestion entries.
**Skip:** When Phase 4.6 found zero real downstream impacts (entire phase silently omitted — correct behavior). Detectable by: no `*.md` files in `.mcl/impact/` from this session AND `current_phase=5`.

---

### STEP-461: impact-persistence
**Phase:** 4.6 | **Description:** After each developer reply, MCL writes a `.mcl/impact/NNNN.md` file with YAML frontmatter: `impact_id`, `presented_at`, `branch`, `head_at_presentation`, `resolution` (skip/fix-applied/rule-captured/open).
**Signal:** `.mcl/impact/NNNN.md` files exist with valid YAML frontmatter. File mtimes match the session timestamp.
**Pass:** Each resolved impact has a corresponding `.mcl/impact/` file. YAML frontmatter has `resolution` field set.
**Skip:** When Phase 4.6 found no impacts (no files written). Correct and expected skip — not a failure.

---

## PHASE 5 STEPS

### STEP-50: spec-compliance-section
**Phase:** 5 | **Description:** Phase 5 emits Section 1 as a markdown table `| Requirement | Status | Evidence |`. One row per MUST/SHOULD from the approved spec; only ⚠️ (partial) and ❌ (missing) rows are shown — ✅ rows are omitted. If every MUST/SHOULD was satisfied, Section 1 is entirely omitted (no header, no placeholder).
**Signal:** Session diary either contains a localized "Spec Uyumluluğu" / "Spec Compliance" table with only ⚠️/❌ rows, OR Section 1 is absent (all compliant — correct behavior).
**Pass:** Section 1 is absent (all compliant) OR contains a table with only ⚠️/❌ rows. No ✅ rows appear. Each row has a Requirement, Status, and Evidence (file:line or "not found").
**Skip:** When every MUST/SHOULD was satisfied (correct, expected omission — not a failure).

---

### STEP-51: must-test-section
**Phase:** 5 | **Description:** Phase 5 emits Section 2 wrapped in `!!! <LOCALIZED-MUST-TEST-PHRASE> !!!` with specific items the developer must verify in a running environment.
**Signal:** Session diary contains the `!!! ... !!!` wrapped localized must-test header with at least one test item.
**Pass:** Session diary contains `!!!` markers wrapping the must-test header. At least one test item is listed beneath it.
**Skip:** Never skipped — Section 2 cannot be empty by definition: if Phase 4 wrote code, there is always something to test.

---

### STEP-52: process-trace-section
**Phase:** 5 | **Description:** Phase 5 reads `.mcl/trace.log` via the Read tool and renders Section 3 as a localized bullet list of hook-emitted events in chronological order.
**Signal:** Session diary contains localized "Süreç İzlemesi" / "Process Trace" / equivalent section. `.mcl/trace.log` exists and is non-empty.
**Pass:** Section 3 is present in session diary if trace.log is non-empty. Events appear in chronological order.
**Skip:** When `.mcl/trace.log` is missing or empty. Correct and expected skip.

---

### STEP-53: static-context-skill-sync
**Phase:** 0 (setup validation) | **Description:** Every `<mcl_phase>` block in `STATIC_CONTEXT` (inside `mcl-activate.sh`) has an extended reference skill file under `skills/my-claude-lang/`. During check-up, Claude reads the STATIC_CONTEXT Phase 4.5 block and `skills/my-claude-lang/phase4-5-risk-review.md` and checks for structural divergence: different step counts, different rule headings, missing sections, or the sync note missing from the skill file. Divergence means the active behavior (STATIC_CONTEXT) and the extended documentation no longer match — the next developer touching that phase has no reliable reference.
**Signal:** check-up Step 9 divergence report (PASS / WARN / SKIP).
**Pass:** No structural divergence detected between STATIC_CONTEXT Phase 4.5 block and `phase4-5-risk-review.md`. Sync note is present in the skill file.
**Skip:** When `skills/my-claude-lang/phase4-5-risk-review.md` does not exist (fresh clone before `bash setup.sh`). Expected skip — not a failure.

---

### STEP-54: project-memory-read
**Phase:** 0 (session start) | **Description:** `mcl-activate.sh` checks for `.mcl/project.md` at every session turn. If found, injects content as `<mcl_project_memory>` and any open `[ ]` items as `<mcl_audit name="proactive-items">` into FULL_CONTEXT. Claude uses the memory to skip Phase 1 questions about already-known facts and surfaces the top open item proactively (after the user's task, or before Phase 1 if the user has no task).
**Signal:** Hook's `additionalContext` contains `<mcl_project_memory>` when `.mcl/project.md` exists and is non-empty.
**Pass:** Memory content and open items appear in `additionalContext`. Stack/architecture facts are referenced during Phase 1 without re-asking.
**Skip:** When `.mcl/project.md` does not exist (new project — no completed task yet). Expected skip.

---

### STEP-55: project-memory-write
**Phase:** 5 | **Description:** After Phase 5 Verification Report, MCL writes or updates `.mcl/project.md` with: architectural decisions from this session's spec, new `[ ]` items for unresolved Phase 4.5 risks, and `[x] (YYYY-MM-DD)` for items resolved this session. File stays under 50 lines. If the file does not exist, MCL creates it with the detected stack and current session's decisions.
**Signal:** `.mcl/project.md` exists and is updated after the first completed Phase 4+5 task.
**Pass:** File contains current session's architectural decisions. Resolved items are marked `[x]`. New debt from Phase 4.5 appears as `[ ]`.
**Skip:** Never skipped when Phase 4 ran. If Phase 4 was skipped (check-up, mcl-finish, mcl-restart turns), project.md update is also skipped.

---

### STEP-56: tdd-refactor-step
**Phase:** 4 | **Description:** After each per-criterion GREEN verify in the incremental TDD loop, MCL runs a refactor pass before moving to the next Acceptance Criterion. Refactor removes duplication, improves naming, and extracts functions for clarity — without adding behavior. Test runner is re-run after refactor to confirm tests stay GREEN. If any test turns RED during refactor, the change is reverted.
**Signal:** Session diary shows code-quality edits between a GREEN verify and the next test write, followed by a runner confirm (no label).
**Pass:** Code improved without behavior change; tests stay GREEN after refactor. If no refactor opportunity exists, step is skipped silently.
**Skip:** When no duplication or clarity improvement is warranted (code is already clean). Expected skip for trivial implementations.

</mcl_phase>
