# MCL 10.0.0 — Major Restructure Release Report

**Release date:** 2026-05-01
**Branch:** main
**Test posture:** unit + e2e green in default and `MCL_MINIMAL_CORE=1` modes.

## Summary

10.0.0 is a major-version bump because the phase model is renumbered and
several state fields are removed. State files are auto-migrated on first
activate; users do not need to take manual action.

| Phase | Name | Approval gate | Applies |
|---|---|---|---|
| 1 | INTENT | summary-confirm askq | All |
| 2 | DESIGN_REVIEW | design askq | UI projects only |
| 3 | IMPLEMENTATION | none (📋 Spec advisory) | All |
| 4 | RISK_GATE | auto-block on HIGH | All |
| 5 | VERIFICATION | none | All |
| 6 | FINAL_REVIEW | none | All |

## Test results

### Default mode
- Unit: **209 passed / 0 failed / 4 skipped**
- e2e: **53 passed / 0 failed / 0 skipped**

### MCL_MINIMAL_CORE=1 mode
- Unit: **156 passed / 0 failed / 2 skipped**
- e2e: **53 passed / 0 failed / 0 skipped**

### Total: 471 passing assertions, 0 failures across both modes.

## Code changes

### State machine (hooks/lib/mcl-state.sh)
- Schema bumped to v3.
- Default state replaces `spec_approved` with `is_ui_project` + `design_approved`.
- v1/v2 → v3 migration helper `_mcl_state_migrate_to_v3` rewrites
  `current_phase` (old 4 → new 3, old 4.5 → new 4), renames
  `phase4_5_*` → `phase4_*`, drops `spec_approved`, `phase_review_state`,
  `precision_audit_block_count`, `precision_audit_skipped`. Backup at
  `.mcl/state.json.backup.pre-v3`. Audit event: `state-migrated-10.0.0`.
- `mcl_get_active_phase` simplified to a single integer 1–6.

### Activate hook (hooks/mcl-activate.sh)
- Triggers `mcl_state_init` at top of every UserPromptSubmit so
  migration runs for old projects on first prompt.
- `is_ui_project` self-heal: when stack-detect determines UI capable but
  the field is still false, set it true silently.
- `/mcl-restart` text updated to reference new schema fields.
- Scope discipline notice now fires on `current_phase=3` (IMPLEMENTATION).
- Removed cross-session `phase_review_state` reset (transient field, no
  longer in canonical schema).

### Stop hook (hooks/mcl-stop.sh)
- Phase 1 summary-confirm askq → `is_ui_project=true` advances to
  Phase 2 (DESIGN_REVIEW + ui_sub_phase=BUILD_UI legacy alias);
  `is_ui_project=false` advances to Phase 3 directly. Audit events:
  `phase-transition-to-design-review` (1→2) or
  `phase-transition-to-implementation` (1→3).
- Phase 2 design askq approve → Phase 3 IMPLEMENTATION. Accepts both
  `design-review` and `ui-review` askq intents (latter for legacy
  transcripts). Audit: `design-approve-via-askuserquestion`.
- Phase 2 DESIGN_REVIEW gate: when `current_phase=2` + `design_approved=false`
  + frontend skeleton files written + no design askq → decision:block
  with mandated askq body. Audit: `design-review-gate-block`.
- Spec emission moved to `case "$CURRENT_PHASE" in 3|4|5|6`. Spec block
  recorded as documentation; `_SPEC_FRESHLY_EMITTED=1` triggers
  `scope_paths` extraction + pattern-scan cascade.
- Spec format violations remain advisory (`spec-format-warn` audit) and
  now increment `spec_format_warn_count` for Phase 6 LOW soft-fail
  detection.
- Phase 6 trigger broadened — fires when `current_phase=4` even if
  `phase_review_state` is absent (the v3 schema does not require it).
- Old "Phase 4a → 4b auto-advance + UI_REVIEW gate" replaced by the
  Phase 2 DESIGN_REVIEW gate.

### Pre-tool hook (hooks/mcl-pre-tool.sh)
- Phase guard simplified:
  - `current_phase < 2` → all mutating tools blocked (Phase 1 INTENT).
  - `current_phase = 2` → frontend paths only; backend paths (`src/api/`,
    `app/api/`, `src/server/`, `prisma/`, `migrations/`, `server/`,
    `backend/`, `api/`, `routes/`) deny with DESIGN_REVIEW reason.
  - `current_phase >= 3` → all unlocked.
- New intent-violation check: scans `phase1_intent` + `phase1_constraints`
  for negation phrases (`frontend only / no backend`, `no DB`, `no auth`)
  and matches Write paths against rule-pack regexes. HIGH severity
  blocks Write with `intent-violation-block` audit. Stack-agnostic.
- Reads state via `MCL_STATE_DIR` env var (was relying on `os.getcwd()`).
- Pattern + scope guards run on `current_phase=3` (was `=4`).
- Phase 4 incremental security/db/ui scans run on `current_phase=3` OR
  `=4` (covers both the active-write phase and the risk-gate phase).
- `SPEC_APPROVED` references replaced with `DESIGN_APPROVED` /
  `IS_UI_PROJECT` reads.

### Supporting libs
- `hooks/lib/mcl-askq-scanner.py` adds Turkish/English design-review
  tokens (`tasarımı onayl`, `approve this design`, etc.) so the Phase 2
  askq classifier matches the new pinned body.
- `hooks/lib/mcl-trace.sh` field-name docstring updated.
- All `phase4_5_*` audit + state references renamed to `phase4_*`.

## Skill prose (15+ files updated by parallel agent)
- Renamed:
  - `phase-spec-doc.md` → `phase3-implementation.md`
  - `phase4-5-risk-review.md` → `phase4-risk-gate.md`
  - `phase4-6-impact-review.md` → `phase4-impact-lens.md`
  - `phase4-execute.md` → `phase3-execute.md`
  - `phase4c-backend.md` → `phase3-backend.md`
  - `phase4-tdd.md` → `phase3-tdd.md`
  - `phase4a-ui-build.md` + `phase4b-ui-review.md` → MERGED into
    `phase2-design-review.md`
  - `phase4a-ui-build/`, `phase4b-ui-review/` directories →
    `phase2-design-review/`
- Deleted: `phase3-verify.md`, `phase4a-ui-build.md`, `phase4b-ui-review.md`
- Top-level `skills/my-claude-lang.md` flow diagram rewritten for new
  6-phase model (UI fork at Phase 2).
- `all-mcl.md` STEP catalog rewritten — STEP-22 spec-auto-approve removed,
  new STEPs for is_ui_project detection, Phase 2 build/dev-server/askq
  transition, spec-format advisory, drift / intent violation.
- `askuserquestion-protocol.md` canonical askq moments reduced to 3 (UI:
  Phase 1 clarifying + Phase 1 summary-confirm + Phase 2 design) or
  2 (non-UI).
- `phase1-rules.md` updated for `is_ui_project` detection rules and
  primary developer-control gate.
- Cross-references in 9 additional skill files patched to the new names.

## Documentation
- README.md / README.tr.md rewritten with new phase model, flow diagram,
  example transcript, migration note.
- FEATURES.md updated for new + removed features and schema migration.
- docs/state-schema.md replaced with v3 canonical example, field table,
  phase transition diagram, v2→v3 migration table.
- CHANGELOG.md prepended with `## 10.0.0 — 2026-05-01` Breaking
  changes / Added / Removed / Migration guide entry.

## Tests
- Deleted (mechanism removed): `test-spec-format-enforcement.sh`,
  `test-partial-spec-post-approval.sh`, `test-phase1-to-phase4.sh`,
  `test-sticky-pending.sh`.
- Renamed: `test-phase4-5-gates.sh` → `test-phase4-gates.sh`,
  `test-phase4-5-to-6-cycle.sh` → `test-phase4-to-6-cycle.sh`.
- Created (10 new synthetic tests):
  - `test-phase1-to-phase3.sh`
  - `test-phase1-to-phase2-ui.sh`
  - `test-design-review-askq-trigger.sh`
  - `test-design-review-bypass-block.sh`
  - `test-design-approve.sh`
  - `test-spec-advisory.sh`
  - `test-architectural-drift.sh`
  - `test-intent-violation.sh`
  - `test-state-migration-v3.sh`
  - `test-spec-format-repeated-violations.sh`
  - `test-design-server-detection.sh`
- Existing tests updated for v3 schema, renamed audit events, renamed
  state fields.
- `tests/lib/build-transcript.py` adds three new fixture kinds:
  `summary-confirm-askq-onayla`, `design-askq-onayla`,
  `design-skeleton-emit`.

## Migration guide for users
1. Pull the new release: `cd ~/my-claude-lang && git pull && bash install.sh`.
2. On the first prompt in any existing project, the activate hook
   detects `schema_version<3` in `.mcl/state.json`, rewrites it to v3,
   and writes a backup at `.mcl/state.json.backup.pre-v3`.
3. The migration sets `is_ui_project=true` and `design_approved=true`
   for existing projects so the design askq does not retrigger on
   already-completed work. For brand-new projects after migration, the
   default is `is_ui_project=false` (overridden when stack-detect sees a
   UI signal).
4. No state.json edits required.

## Known limitations
- `test-spec-format-repeated-violations.sh` probes two candidate Phase
  6 function names. If neither is found in `mcl-phase6.py`, it skips
  rather than fails. The phase6 lib does not yet expose a public hook
  for this counter — wired via `spec_format_warn_count` audit only.
- The legacy `ui_sub_phase` field is still set during Phase 2 for
  backward compatibility with code paths that consult it; the canonical
  v3 reader is `current_phase=2` + `design_approved`.
- The 14-language scaffolding remains in code but project policy
  restricts active testing to TR.

## Iteration history (test-fix loops)
1. Loop 1: 187/21 → fixed migration test contract (move v3 default to
   strip `phase_review_state` / `precision_audit_*`).
2. Loop 2: 196/12 → routed `phase_review_state` removal through migration
   only (no default reset on session start).
3. Loop 3: 203/5 → added Phase 2 early-exit short-circuit so Stop reaches
   the design-askq trigger gate even when no spec/askq is present.
4. Loop 4: 204/4 → fixed askq scanner Turkish design-review tokens.
5. Loop 5: 207/1 → added intent-violation check + state path env-var
   read; Phase 6 trigger broadened to `current_phase=4`.
6. Loop 6: 209/0 → e2e Phase 25 scan-incremental gate widened to
   `current_phase ∈ {3,4}`.

## Files touched (high level)
- 5 hook scripts (state, activate, stop, pre-tool, supporting libs)
- 1 askq scanner Python lib
- 25+ skill prose files (renames, rewrites, cross-reference patches)
- 4 documentation files (README × 2, FEATURES, state-schema)
- CHANGELOG.md
- 23 test files (deletes, renames, rewrites, new fixtures)
- VERSION → 10.0.0
