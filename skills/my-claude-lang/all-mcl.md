<mcl_phase name="all-mcl-reference">

# MCL Step Catalog (MCL 10.0.0)

Machine-readable reference of every MCL step in execution order.
Used by `mcl check-up` to evaluate session health.
Each step has a stable STEP-NN ID, a signal (what to look for in logs),
a Pass condition, and a Skip condition.

**Log sources:**
- `trace.log` — `<ISO-UTC> | <event> | <args>` (deterministic hook events)
- `audit.log` — `<datetime> | <event> | <source> | <key=val ...>` (operational events)
- `state.json` — JSON phase state machine
- `log/TIMESTAMP.md` — session diary (all tool calls with AskUserQuestion entries)
- `specs/*.md` — Phase 3 spec documentation files
- `impact/*.md` — Phase 4 impact-lens files

---

## PRE-SESSION STEPS

### STEP-01: session-boundary
**Phase:** Pre-Session | **Description:** mcl-activate.sh detects a new session_id and resets task-scoped state flags (partial_spec, phase_review_state, design_approved, is_ui_project) so stale prior-task state cannot bleed into the new session.
**Signal:** audit.log contains `set | mcl-activate.sh | field=phase_review_state value=null` near the session_start timestamp. state.json `plugin_gate_session` equals the current session_id.
**Pass:** audit.log has at least one session-boundary reset write. state.json `last_update` timestamp is close to session_start in trace.log.
**Skip:** Never skipped — fires on every distinct session_id.

---

### STEP-02: version-banner
**Phase:** Pre-Session | **Description:** Claude emits the `🌐 MCL X.Y.Z` banner as the first token of every developer-facing response, every turn, no exceptions.
**Signal:** trace.log first event is `session_start | X.Y.Z`. Session diary first bullet contains the MCL version string.
**Pass:** trace.log has `session_start` event. Version string appears in the session diary.
**Skip:** Never skipped — STATIC_CONTEXT rule 1 is absolute.

---

### STEP-03: stack-detection
**Phase:** Pre-Session | **Description:** mcl-activate.sh calls mcl-stack-detect.sh; result is logged as `stack_detected` event with detected language tags. Stack tags inform Phase 1 brief parse and Phase 4 risk-gate orchestrators.
**Signal:** trace.log contains `stack_detected | <tags>` on the session's first turn. audit.log contains `stack-detected | mcl-activate.sh | tags=<list>`.
**Pass:** trace.log has `stack_detected` event.
**Skip:** When the project has no source files OR no recognizable stack tags at session start — `STACK_TAGS` is empty, so `mcl_trace_append stack_detected` is NOT called (guarded by `[ -n "$STACK_TAGS" ]`). Correct skip when: trace.log has no `stack_detected` line for this session.

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
**Phase:** 1 | **Description:** Claude applies disambiguation triage before asking any question. SILENT path: trivial defaults and reversible choices are assumed and marked in the brief (`[assumed: X]` / `[default: X, changeable]`) without asking. GATE path: only schema/migration decisions, auth/permission model, public API breaking changes, irreversible data consequences, and security boundary decisions trigger a question — one at a time. Parameters that do not require a gate are resolved silently.
**Signal:** Session diary shows plain-text question turns ONLY for gate-category ambiguities before the summary AskUserQuestion. No `📋 Spec:` block appears before `summary_confirmed` in trace.log.
**Pass:** `summary_confirmed` event in trace.log. Gate questions are only for irreversible decisions. Trivial/reversible assumptions appear as `[assumed: X]` or `[default: X, changeable]` markers in the brief.
**Skip:** When the developer's first message already contains all parameters with no ambiguity — summary appears immediately. Still passes if `summary_confirmed` is present.

---

### STEP-11: plugin-suggestions
**Phase:** 1 | **Description:** On the first developer message, if stack-matched plugins are missing, MCL presents AskUserQuestion suggestions (one per plugin) before Phase 1 gathering starts.
**Signal:** Session diary first substantive turn references missing plugin names. audit.log may contain `plugin-gate-activated` entries.
**Pass:** If `plugin_gate_active=true` in state.json, the session diary shows an AskUserQuestion referencing plugin install commands on the first turn.
**Skip:** When all stack-matched plugins are already installed (`plugin_gate_active=false`), or the project is empty. Correct and expected skip.

---

### STEP-12: summary-confirmation
**Phase:** 1 | **Description:** Claude presents the Phase 1 summary as plain text, then immediately calls AskUserQuestion with prefix `MCL X.Y.Z | ` and options Approve/Edit/Cancel. This is the PRIMARY developer-control gate. On approval the Stop hook reads `is_ui_project` (set by Phase 1 brief parse) and routes the transition: UI projects go to Phase 2; non-UI projects go to Phase 3. State writes also populate `phase1_intent`, `phase1_constraints`, `phase1_stack_declared` for Phase 1.7 stack add-ons (greenfield fallback) and Phase 6 promise-vs-delivery.
**Signal:** trace.log contains `summary_confirmed | approved`. audit.log contains `summary-confirm-approve | stop`. State has non-null `phase1_intent`, `phase1_constraints`, `phase1_stack_declared`, `is_ui_project`.
**Pass:** trace.log has `summary_confirmed` event followed by either `phase_transition | 1 | 2` (UI) or `phase_transition | 1 | 3` (non-UI).
**Skip:** Never skipped — mandatory before Phase 2 / Phase 3.

---

### STEP-13: is-ui-project-detection
**Phase:** 1 | **Description:** During Phase 1 brief parse and AT summary-confirm approval, MCL determines `is_ui_project` from three signal classes: (1) intent keywords in the brief (`panel`, `dashboard`, `frontend`, `web`, `site`, `ui`, `form`, `page`, `admin`, `interface`, `backoffice` and language equivalents); (2) `mcl-stack-detect.sh` tags (`react-frontend`, `vue-frontend`, `next`, `nuxt`, `svelte`, `angular`, `html`, `vite`); (3) project file hints (`index.html` at root, `package.json` with frontend deps). If ambiguous, defaults to `true` (false-negative cost > false-positive cost). The flag drives the next gate: `true` → Phase 2; `false` → Phase 3.
**Signal:** state.json `is_ui_project` is explicitly `true` or `false` after summary-confirm. audit.log has `is_ui_project_detected | phase1 | value=<bool> source=<signal>`.
**Pass:** state.json `is_ui_project` is non-null after summary-confirm. The transition target (Phase 2 or Phase 3) matches the flag.
**Skip:** Never skipped — every Phase 1 summary-confirm approval triggers detection.

---

### STEP-14: precision-audit
**Phase:** 1.7 (between Phase 1 summary approval and Phase 1.5 brief) | **Description:** After Phase 1 `AskUserQuestion` returns approve-family, Claude runs a precision audit against confirmed parameters. The audit walks 7 core dimensions (permission/access, algorithmic failure modes, out-of-scope boundaries, PII handling, audit/observability, performance SLA, idempotency/retry) plus any stack-specific add-on dimensions matched by `mcl-stack-detect.sh` tags. Each dimension is classified SILENT-ASSUME (industry default exists, mark `[assumed: X]`), SKIP-MARK (no safe default; mark `[unspecified: X]`), or GATE (architectural impact, ask one question via the existing one-question-at-a-time rule). When all dimensions resolve, an audit entry is emitted, then Phase 1.5 brief follows. Skipped silently when developer's detected language is English (audit emitted with `skipped=true`).
**Signal:** `audit.log` contains `precision-audit | phase1-7 | core_gates=N stack_gates=M assumes=K skipmarks=L stack_tags=<comma> skipped=<true|false>` between the session's `session_start` and the next phase transition.
**Pass:** `precision-audit` entry exists for the current session. For non-English sessions all 7 core dimensions are classified. For English sessions, one entry with `skipped=true` is sufficient.
**Skip:** When detected language is English. The audit entry is still required (`skipped=true`).

---

### STEP-15: engineering-brief
**Phase:** 1.5 (between Phase 1.7 precision audit and Phase 2 / Phase 3 transition) | **Description:** Two-duty pass: (1) translate Phase 1 confirmed parameters from the developer's language to English (faithful translation, identity for English source); (2) **upgrade vague verbs** to surgical English verbs that imply standard technical patterns (`list` → `render a paginated table`, `manage` → `expose CRUD operations`, `build` → `implement`). Verb-implied standard defaults are annotated `[default: X, changeable]`. Hallucination guards: Phase 4 risk-gate Lens (e) Brief-Phase-1 Scope Drift verifies implementation traceability against the user's original Phase 1 parameters and surfaces any untraced scope as a risk.
**Signal:** `audit.log` contains `engineering-brief | phase1-5 | lang=<detected> skipped=<true|false> retries=<N> upgraded=<true|false> verbs_upgraded=<count>`.
**Pass:** `audit.log` has `engineering-brief` entry for this session. When `upgraded=true`, Phase 4 Lens (e) runs.
**Skip:** When developer language is English AND no vague verbs were detected (`skipped=true`, `upgraded=false`). Audit entry still required.

---

## PHASE 2 STEPS (UI projects only)

### STEP-20: phase2-design-review-build
**Phase:** 2 | **Description:** When `is_ui_project=true` after Phase 1 summary-confirm, Claude writes a UI skeleton with mock data only. Minimum 3 files (entry, base layout, 1-2 placeholder pages); build-tool config (Vite / Tailwind / package.json) configured; no `fetch` / `axios` / DB / `.env` writes. Backend paths blocked by `mcl-pre-tool.sh` while `current_phase=2`. Recharts / lucide-react and similar UI libs allowed.
**Signal:** state.json `current_phase=2`. Session diary shows ≥3 Write entries for frontend paths. audit.log `phase2-design-build | stop` after first frontend Write.
**Pass:** state.json `current_phase=2` for the build phase. ≥3 frontend files written. No backend file writes during the build.
**Skip:** When `is_ui_project=false`. Phase 2 is bypassed entirely; state transitions Phase 1 → Phase 3 directly.

---

### STEP-21: dev-server-started
**Phase:** 2 | **Description:** After ≥3 UI files are written and build-tool config is in place, MCL runs the dev server in the background (`Bash` with `run_in_background:true`), allocates a port, derives the URL from the framework, opens the browser (macOS `open` / Linux `xdg-open`), and emits the localized "UI ready" prose with the URL in chat. The audit fires only after the server actually binds.
**Signal:** audit.log `dev-server-started | mcl-stop | url=<url> port=<port>`. trace.log `dev_server_started`. state.json `dev_server.active=true`.
**Pass:** audit has `dev-server-started`. The localized "UI ready" prose appears in the assistant text containing a `localhost:` URL.
**Skip:** When the UI files cannot be served (no resolvable run command after fallback chain). MCL emits a snippet-only path and STOPS for manual launch — counts as skip with audit `dev-server-skip-manual`.

---

### STEP-22: design-askq-emission
**Phase:** 2 | **Description:** After dev server is up AND ≥3 files written AND URL printed in chat, MCL calls AskUserQuestion with the pinned design-approval body. Question prefix `MCL X.Y.Z | `; localized labels Approve/Revise/Cancel. Approve label match (case-insensitive contains): onayla, evet, approve, yes, confirm, ok, proceed. Hook ENFORCES — without the askq, Stop emits `decision:block` and Phase 2 cannot transition.
**Signal:** Session diary contains `AskUserQuestion` tool_use with `MCL X.Y.Z | <design-prompt>`. audit.log `design-askq-emitted | mcl-stop`.
**Pass:** Design askq is present in transcript. Stop hook does not emit `phase2-no-design-askq-block`.
**Skip:** When `is_ui_project=false`. Phase 2 is bypassed.

---

### STEP-23: phase-2-to-3-transition
**Phase:** 2→3 | **Description:** On developer Approve in the design askq, Stop hook writes `design_approved=true`, `current_phase=3`, lifts the path lock, and emits `design-approved` audit. On Revise, no state change — Phase 2 re-enters with feedback. On Cancel, UI flags reset and task aborts.
**Signal:** audit.log `design-approved | mcl-stop`. trace.log `phase_transition | 2 | 3`. state.json `design_approved=true`, `current_phase=3`.
**Pass:** trace.log has `phase_transition | 2 | 3` and audit has `design-approved`.
**Skip:** When `is_ui_project=false`. Phase 2 is bypassed.

---

## PHASE 3 STEPS

### STEP-30: spec-emission
**Phase:** 3 | **Description:** At Phase 3 entry (first turn), Claude emits the visible `📋 Spec:` block — 7 H2 headers (Objective, MUST, SHOULD, Acceptance Criteria, Edge Cases, Technical Approach, Out of Scope). Up to five conditional sections appear when triggered (Non-functional Requirements, Failure Modes & Degradation, Observability, Reversibility/Rollback, Data Contract). Format violations are ADVISORY — they emit `spec-format-warn` but never block writes. Repeated violations (≥3) accumulate as a Phase 6 LOW soft fail.
**Signal:** Stop hook computes `SPEC_HASH` and writes it to state.json. state.json `current_phase=3`.
**Pass:** state.json `spec_hash` is non-null. `current_phase=3`. Either `spec-format-warn` is absent (clean format) or present but counter < 3.
**Skip:** Never skipped — the spec is the documentation artifact at Phase 3 entry.

---

### STEP-31: spec-format-warn
**Phase:** 3 | **Description:** When the Stop hook detects a spec format violation (missing 📋 prefix, missing H2 header, spec wrapped in triple-backticks), it emits `spec-format-warn` audit. Writes stay UNLOCKED — the spec is documentation, not a state gate. Counter accumulates in `state.spec_format_warn_count`. On the third violation, Phase 6 surfaces a LOW soft fail.
**Signal:** audit.log `spec-format-warn | stop | reason=<missing-header|wrapped-in-code-block|prefix-typo>` for each violation.
**Pass:** No `spec-format-warn` entries in this session, OR `spec_format_warn_count < 3`.
**Skip:** When the spec is format-clean (no violation to log). Expected default.

---

### STEP-32: spec-saved
**Phase:** 3 | **Description:** mcl-spec-save.sh writes the Phase 3 spec body to `.mcl/specs/NNNN-slug.md` with YAML frontmatter (spec_id, approved_at, spec_hash, branch, head_at_approval). Triggered by spec emission detection in mcl-stop.sh.
**Signal:** `.mcl/specs/` directory contains at least one `*.md` file. audit.log contains `spec-saved | mcl-spec-save.sh`.
**Pass:** `.mcl/specs/` contains at least one spec file per Phase 3 entry in this session.
**Skip:** Never skipped — spec save is automatic on every Phase 3 entry.

---

### STEP-33: partial-spec-recovery
**Phase:** 3 | **Description:** When a spec was truncated mid-emission (rate-limit or network drop), state.json `partial_spec=true` is set. The activate hook injects a recovery audit block on the next turn forcing a full re-emission inline. No askq is involved — the spec is documentation only.
**Signal:** state.json `partial_spec=true`. audit.log contains `partial-spec | stop | missing=<sections>`.
**Pass:** `partial_spec` cleared back to `false` after a complete spec was re-emitted. audit.log shows `partial-spec-cleared`.
**Skip:** When no truncation occurred (`partial_spec=false` or absent throughout). Correct and expected skip.

---

### STEP-34: test-command-resolution
**Phase:** 3 | **Description:** Before any Phase 3 production code is written, MCL resolves the test command via four priority steps: (1) `.mcl/config.json`, (2) auto-detect from manifests, (3) infer from the spec's Technical Approach section, (4) one-off developer question only if still unresolved.
**Signal:** `.mcl/config.json` contains `test_command` if the developer set it. Session diary shows test command resolution (question or silent inference) before first Phase 3 production code write.
**Pass:** Either `test_command` is resolved (config / auto-detect / spec inference), OR the developer explicitly declined (TDD flow skipped for session).
**Skip:** When `test_command` was already in config, auto-detected from manifests, or confidently inferred from spec — no developer question needed.

---

### STEP-35: code-writing
**Phase:** 3 | **Description:** Claude writes code using Write/Edit/MultiEdit tools, all code in English, all communication in the developer's language. Writes stay within `state.scope_paths` derived from the spec's Technical Approach. For UI projects (`is_ui_project=true`, `design_approved=true`), Phase 3 starts by swapping Phase 2 fixtures for real `fetch` / `axios` / DB calls.
**Signal:** Session diary shows Write/Edit tool call entries. mcl-stop.sh sets `phase_review_state` via mcl-phase-review-guard on code-written turns. state.json `current_phase=3`.
**Pass:** Session diary contains Write or Edit tool entries with `current_phase=3`.
**Skip:** Never skipped — Phase 3 always writes code.

---

### STEP-36: tdd-refactor-step
**Phase:** 3 | **Description:** After each per-criterion GREEN verify in the incremental TDD loop, MCL runs a refactor pass before moving to the next Acceptance Criterion. Refactor removes duplication, improves naming, and extracts functions for clarity — without adding behavior. Test runner is re-run after refactor to confirm tests stay GREEN. If any test turns RED during refactor, the change is reverted.
**Signal:** Session diary shows code-quality edits between a GREEN verify and the next test write, followed by a runner confirm (no label).
**Pass:** Code improved without behavior change; tests stay GREEN after refactor. If no refactor opportunity exists, step is skipped silently.
**Skip:** When no duplication or clarity improvement is warranted. Expected skip for trivial implementations.

---

### STEP-37: phase-review-enforcement
**Phase:** 3→4 | **Description:** When code is written without the Phase 4 risk-gate dialog starting in the same turn, mcl-stop.sh sets `phase_review_state="pending"` and returns `decision:block`. "pending" is STICKY: the BLOCK re-fires on every subsequent turn until AskUserQuestion is called for a risk, transitioning state to "running".
**Signal:** audit.log `phase-review-pending | stop | prev=... phase=3 code=...`. trace.log `phase_review_pending | ...`. state.json `phase_review_state="pending"`.
**Pass:** `phase_review_state` transitions from `pending` to `running` when Phase 4 starts.
**Skip:** When Phase 4 starts in the same turn as the last code write. State goes directly to `running` without `pending`.

---

## PHASE 4 STEPS

### STEP-40: spec-compliance-precheck
**Phase:** 4 | **Description:** Before the automated quality scan, Phase 4 walks every MUST and SHOULD in the Phase 3 spec and surfaces any missing or partial implementations as risks in the sequential dialog.
**Signal:** AskUserQuestion calls in session diary reference spec MUST/SHOULD requirement text. state.json `phase_review_state="running"`. audit.log `phase-review-running | stop`.
**Pass:** Either no spec gaps (silent pass — no marker needed), OR AskUserQuestion was called for each gap found. `phase_review_state` progressed to `running`.
**Skip:** When every MUST/SHOULD was fully implemented in Phase 3 (silent skip — correct behavior).

---

### STEP-41: architectural-drift-detection
**Phase:** 4 | **Description:** Phase 4 verifies every file written in Phase 3 lives within `state.scope_paths`. Drift severity: empty `scope_paths` → LOW; sibling/parallel path → MEDIUM; cross-layer (frontend→backend) → HIGH. HIGH drift auto-blocks further writes until resolved via apply-fix or override-with-reason.
**Signal:** audit.log `phase4-drift | mcl-stop | path=<p> severity=<HIGH|MEDIUM|LOW>` for each drift event. AskUserQuestion entries in session diary cite `[Drift]` label.
**Pass:** No drift events, OR every drift event was resolved (apply-fix / override) in the dialog.
**Skip:** When all Phase 3 writes fall inside `scope_paths`. Expected default for clean implementations.

---

### STEP-42: intent-violation-check
**Phase:** 4 | **Description:** Phase 4 scans `state.phase1_intent` for negation phrases ("no auth", "no DB", "no backend", "without X") and cross-references with Phase 3 writes. Match = HIGH severity risk that auto-blocks Write/Edit until resolved (apply-fix / override-with-reason). The block is enforced by `mcl-pre-tool.sh` via `state.phase4_intent_block=true`.
**Signal:** audit.log `phase4-intent-violation | mcl-stop | phrase=<p> file=<f>:<line>`. AskUserQuestion entries cite `[IntentViolation]` label.
**Pass:** No intent-violation events, OR every event was resolved.
**Skip:** When `phase1_intent` contains no negation phrases, OR all writes pass the cross-reference. Expected default.

---

### STEP-43: integrated-quality-scan
**Phase:** 4 | **Description:** Before each risk-dialog turn, MCL applies six embedded lenses simultaneously as continuous practices: (a) CODE REVIEW, (b) SIMPLIFY, (c) PERFORMANCE, (d) SECURITY/DB/UI-A11y, (e) BRIEF-PHASE-1 SCOPE DRIFT, (f) ARCHITECTURAL DRIFT / INTENT VIOLATION. Semgrep SAST auto-fixes (HIGH/MEDIUM with unambiguous autofix) are applied silently and merged into the lens findings.
**Signal:** audit.log `semgrep-autofix | phase4 | rule=<id> file=<path:line>` for auto-applied fixes. Risk dialog AskUserQuestion entries reference category labels. state.json `phase_review_state="running"`.
**Pass:** Each risk-dialog turn is preceded by a multi-lens scan. audit.log has `semgrep-autofix` entries for any auto-fixed findings. If scan is clean, no marker — acceptable silent pass.
**Skip:** When Phase 4 found zero risks across all lenses (entire phase omitted silently).

---

### STEP-44: risk-dialog
**Phase:** 4 | **Description:** Sequential one-risk-per-turn dialog. Each risk is presented via AskUserQuestion with options apply-fix/skip/make-rule (or apply-fix/override for HIGH and MEDIUM-sec/db/intent). Developer resolves all risks before the impact lens.
**Signal:** audit.log `phase-review-running | stop`. AskUserQuestion entries in session diary with `MCL X.Y.Z | ` prefix and risk-decision options.
**Pass:** state.json `phase_review_state="running"` appears. Session diary shows at least one risk-decision AskUserQuestion entry.
**Skip:** When Phase 4 found zero risks (entire phase silently omitted).

---

### STEP-45: tdd-re-verify
**Phase:** 4 | **Description:** After all risks are resolved, `mcl-test-runner.sh green-verify` is called if `test_command` is configured. Post-risk full-suite run separate from the per-criterion GREEN verifies in Phase 3.
**Signal:** Session diary shows a GREEN verify block after risk resolution. audit.log `tdd-rerun-timeout | phase4` only on timeout.
**Pass:** Session diary shows GREEN test runner output before the impact lens, OR `test_command` is not configured (no runner invoked).
**Skip:** When Phase 4 was entirely omitted, OR `test_command` is not configured.

---

### STEP-46: comprehensive-testing
**Phase:** 4 | **Description:** After TDD re-verify passes, MCL checks Phase 3 code is covered by four test categories: unit, integration, E2E (when `is_ui_project=true`), load/stress (throughput-sensitive paths). When `test_command` configured, Claude **writes** missing test files directly as Phase 3-style code actions, then runs green-verify; RED surfaces as a new risk. When `test_command` NOT configured, missing categories surface as a single risk-dialog turn.
**Signal:** When test_command configured: session diary shows Write/Edit entries for test files after TDD re-verify, followed by a green-verify run. When test_command not configured: session diary shows a single AskUserQuestion citing missing test categories.
**Pass:** All applicable test categories are covered, OR missing categories were either written or surfaced as a risk turn and resolved.
**Skip:** When Phase 4 was entirely omitted, OR all four test categories are already covered.

---

### STEP-47: impact-detection
**Phase:** 4 (impact lens) | **Description:** Sequential one-impact-per-turn dialog. Each real downstream effect on other project files presented via AskUserQuestion. Developer resolves all impacts before Phase 5.
**Signal:** AskUserQuestion entries in session diary cite file paths, functions, or API consumers affected by Phase 3 changes. `.mcl/impact/` directory grows by one file per resolved impact.
**Pass:** `.mcl/impact/` contains `*.md` files written during this session. Session diary shows impact-decision AskUserQuestion entries.
**Skip:** When the impact lens found zero real downstream impacts (silently omitted). Detectable by: no `*.md` files in `.mcl/impact/` from this session AND `current_phase=5`.

---

### STEP-48: impact-persistence
**Phase:** 4 (impact lens) | **Description:** After each developer reply, MCL writes a `.mcl/impact/NNNN.md` file with YAML frontmatter: `impact_id`, `presented_at`, `branch`, `head_at_presentation`, `resolution` (skip/fix-applied/rule-captured/open).
**Signal:** `.mcl/impact/NNNN.md` files exist with valid YAML frontmatter.
**Pass:** Each resolved impact has a corresponding `.mcl/impact/` file.
**Skip:** When the impact lens found no impacts. Correct skip.

---

### STEP-49: plugin-dispatch-audit
**Phase:** Post-4 (fires on each turn during Phase 4) | **Description:** `mcl-activate.sh` checks `trace.log` for required Phase 4 dispatches (code-review sub-agent, semgrep) whenever `phase_review_state=running`. If any required dispatch is absent after the last `phase_review_pending`, `PLUGIN_MISS_NOTICE` is injected, blocking progression to Phase 5.
**Signal:** `audit.log` contains `plugin-dispatch-gap | mcl-activate.sh | missing=<list>`.
**Pass:** After gap notice, session diary shows dispatches for all listed plugins.
**Skip:** When all Phase 4 required plugins are dispatched before this check runs. Common case.

---

## PHASE 5 STEPS

### STEP-50: spec-coverage-section
**Phase:** 5 | **Description:** Phase 5 emits Section 1 as a Spec Compliance traceability table — mismatches only (⚠️/❌). If every MUST/SHOULD is met, OMIT Section 1 entirely. Skill prose emits `mcl_audit_log "phase5-verify" "phase5" "report-emitted"` after all sections — this is the deterministic signal Phase 6 audit-trail check uses.
**Signal:** Session diary contains a localized "Spec Kapsama" / "Spec Coverage" section with mismatches only. audit.log contains `phase5-verify | phase5 | report-emitted`.
**Pass:** All MUST/SHOULD mismatches present. `phase5-verify` audit emitted.
**Skip:** When every MUST/SHOULD is satisfied (Section 1 omitted entirely — correct).

---

### STEP-51: automation-barriers-section
**Phase:** 5 | **Description:** Phase 5 emits Section 2 wrapped in `!!! <LOCALIZED-MUST-TEST-PHRASE> !!!` ONLY for items where automation is structurally impossible. Detection is call-graph-based — NOT spec keyword-based.
**Signal:** Session diary contains `!!!` markers wrapping the must-test header, with each item citing a specific file:line and automation-barrier reason.
**Pass:** Each item in Section 2 maps to a concrete call pattern in Phase 3 code with a file:line citation.
**Skip:** When no automation barriers are found. A fully in-memory, no-external-call feature with complete test coverage produces NO Section 2.

---

### STEP-52: process-trace-section
**Phase:** 5 | **Description:** Phase 5 reads `.mcl/trace.log` via the Read tool and renders Section 3 as a localized bullet list of hook-emitted events in chronological order.
**Signal:** Session diary contains localized "Süreç İzlemesi" / "Process Trace" / equivalent section. `.mcl/trace.log` exists and is non-empty.
**Pass:** Section 3 is present in session diary if trace.log is non-empty.
**Skip:** When `.mcl/trace.log` is missing or empty.

---

### STEP-53: localize-report
**Phase:** 5.5 (after Phase 5 content is generated, before emission) | **Description:** After Phase 5 Verification Report is produced, Phase 5.5 localizes all developer-facing text into the developer's detected language before the response is emitted. File paths, code identifiers, CLI commands, and `📋 Spec:` block content stay in English. Skipped silently when developer language is English. A `localize-report` audit entry is always emitted.
**Signal:** `audit.log` contains `localize-report | phase5-5 | lang=<detected> skipped=<true|false>`.
**Pass:** `audit.log` has `localize-report` entry. `skipped=false` for non-English sessions.
**Skip:** When developer language is English (`skipped=true`). Audit entry still required.

---

### STEP-54: phase5-skip-detection
**Phase:** Stop (post-Phase 4) | **Description:** `mcl-stop.sh` checks `phase_review_state` at every stop. If state is `running` AND `ASKQ_INTENT` is empty (no MCL-prefixed AskUserQuestion ran this turn), Phase 4 dialog has ended but Phase 5 Verification Report did not clear the state — Phase 5 was skipped. Audit-only (non-blocking); next turn injects warn instructing Claude to run Phase 5.
**Signal:** `audit.log` contains `phase5-skipped-warn | mcl-stop.sh | phase_review_state=running`.
**Pass:** When the Phase 4 → 5 sequence runs to completion. No `phase5-skipped-warn` audit entry is written.
**Skip:** When `phase_review_state` is `null` or `pending` at stop (no Phase 4 dialog has begun). Expected skip.

---

## PHASE 6 STEPS

### STEP-60: final-review-forensic
**Phase:** 6 | **Description:** After Phase 5 emits, Phase 6 runs a forensic audit pass: cross-references all Phase 4 risk overrides with `phase4_override` events; verifies all spec MUST items have at least one corresponding Phase 5 must-test entry or are flagged as `[Override: <reason>]`; confirms `phase5-verify` audit emit. Mismatches surface as LOW soft fails. Phase 6 is the final integrity check, not a developer-facing dialog.
**Signal:** `audit.log` contains `phase6-final-review | mcl-stop | passes=<N> warns=<N>`.
**Pass:** Phase 6 audit emitted. No HIGH soft fails.
**Skip:** Never skipped when Phase 5 ran. If Phase 5 was skipped (mcl-finish, mcl-restart, mcl-checkup turns), Phase 6 also skips.

---

### STEP-61: project-memory-read
**Phase:** Pre-session | **Description:** `mcl-activate.sh` checks for `.mcl/project.md` at every session turn. If found, injects content as `<mcl_project_memory>` block. Open `[ ]` items are surfaced as `<mcl_audit name="proactive-items">`.
**Signal:** Hook's `additionalContext` contains `<mcl_project_memory>` when `.mcl/project.md` exists and is non-empty.
**Pass:** Memory content and open items appear in `additionalContext`.
**Skip:** When `.mcl/project.md` does not exist (new project). Expected skip.

---

### STEP-62: project-memory-write
**Phase:** 5 | **Description:** After Phase 5 Verification Report, MCL writes or updates `.mcl/project.md` with: architectural decisions from this session's spec, new `[ ]` items for unresolved Phase 4 risks, and `[x] (YYYY-MM-DD)` for items resolved this session. File stays under 50 lines.
**Signal:** `.mcl/project.md` exists and is updated after the first completed Phase 3+5 task.
**Pass:** File contains current session's architectural decisions. Resolved items are marked `[x]`. New debt from Phase 4 appears as `[ ]`.
**Skip:** Never skipped when Phase 3 ran.

---

### STEP-63: static-context-skill-sync
**Phase:** 0 (setup validation) | **Description:** Every `<mcl_phase>` block in `STATIC_CONTEXT` (inside `mcl-activate.sh`) has an extended reference skill file under `skills/my-claude-lang/`. During check-up, Claude reads the STATIC_CONTEXT Phase 4 block and `skills/my-claude-lang/phase4-risk-gate.md` and checks for structural divergence.
**Signal:** check-up Step 9 divergence report (PASS / WARN / SKIP).
**Pass:** No structural divergence detected between STATIC_CONTEXT Phase 4 block and `phase4-risk-gate.md`. Sync note is present in the skill file.
**Skip:** When `skills/my-claude-lang/phase4-risk-gate.md` does not exist (fresh clone before `bash setup.sh`).

---

### STEP-64: hook-health-check
**Phase:** Pre-session / `mcl check-up` | **Description:** Each MCL hook (`mcl-stop.sh`, `mcl-activate.sh`, `mcl-pre-tool.sh`, `mcl-post-tool.sh`) writes its last successful invocation epoch timestamp to `.mcl/hook-health.json`. `mcl check-up` reports WARN when any field is missing OR older than 24 hours.
**Signal:** `.mcl/hook-health.json` exists and has the four keys. Each value is a recent epoch timestamp.
**Pass:** All four hook timestamps present and within 24h of `mcl check-up` run time.
**Skip:** When `.mcl/hook-health.json` is absent on the very first session before any hook has fired.

---

### STEP-65: session-context-bridge
**Phase:** Stop (write) + Session boundary (read) | **Description:** `mcl-stop.sh` writes a 4–6 line markdown summary to `.mcl/session-context.md` on every Stop: active phase + spec hash, last commit short SHA + subject, next step (resolved from a state-driven rule table), and any half-finished work. The next session's `mcl-activate.sh` reads that file at session boundary and injects it into `additionalContext`.
**Signal:** `.mcl/session-context.md` exists and contains the markdown summary after at least one Stop. `audit.log` records `session-context-injected | mcl-activate.sh | shown` on the first turn of each new session.
**Pass:** File is regenerated each Stop reflecting current state. New sessions inject the prior context exactly once at the boundary turn.
**Skip:** When `.mcl/session-context.md` does not exist on session boundary. Expected skip.

---

### STEP-66: root-cause-chain-discipline
**Phase:** Plan-mode (devtime) + Any turn (user-message trigger) | **Description:** Two trigger paths inject `ROOT_CAUSE_DISCIPLINE_NOTICE` — both tell Claude the response must show three checks: visible process, removal test, falsification. `mcl-stop.sh` scans the last assistant turn for the three keyword pairs and writes `root-cause-chain-skipped-warn` if any are missing.
**Signal:** `audit.log` contains `root-cause-discipline-notice | mcl-activate.sh | shown` on active turns; `root-cause-chain-skipped-warn | mcl-stop.sh | missing=<list>` after a non-compliant turn.
**Pass:** Plan-mode turns and user-message-triggered turns both include all three chain checks.
**Skip:** When no `.claude/plans/*.md` file has been modified this session AND the user prompt contains no trigger keyword.

---

### STEP-67: plan-critique-substance-validation
**Phase:** Pre-tool (Task call gate) | **Description:** When pre-tool detects a Task call with `subagent_type=*general-purpose*` AND `model=*sonnet*` (the plan-critique shape), it scans the transcript for the most recent `Task(subagent_type=*mcl-intent-validator*)` invocation and reads its tool_result. The validator returns `{"verdict": "yes"|"no", "reason": "..."}`. Pre-tool parses the verdict: `yes` allows the Task and sets `plan_critique_done=true`; `no` returns `decision:block` with the validator's reason; missing validator returns `decision:block`.
**Signal:** `audit.log` contains `plan-critique-done | pre-tool | subagent=<sub> model=<mdl> intent_validated reason=<...>` on pass.
**Pass:** Every `plan-critique-done` audit emit was preceded by a successfully-parsed validator verdict=yes.
**Skip:** Never skipped — runs on every Task call matching the plan-critique shape.

</mcl_phase>
