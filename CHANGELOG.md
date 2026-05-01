# Değişiklik Günlüğü

[Keep a Changelog](https://keepachangelog.com) formatı. Her yeni sürümde
`[Unreleased]` bölümü `[X.Y.Z] - YYYY-MM-DD`'ye dönüştürülür.

---

## [Unreleased]

## 10.0.0 — 2026-05-01

### Breaking changes
- Phase model restructured. Old Phase 4 (EXECUTE) is now Phase 3 (IMPLEMENTATION); old Phase 4.5 is now Phase 4 (RISK_GATE). Old Phase 2 (SPEC_REVIEW) and Phase 3 (USER_VERIFY) are deleted entirely. New Phase 2 (DESIGN_REVIEW) added for UI projects.
- State schema bumped to v3. `spec_approved`, `precision_audit_block_count`, `precision_audit_skipped`, `phase_review_state` fields removed. New: `is_ui_project`, `design_approved`. State files auto-migrated on first activate.
- All `phase4_5_*` state fields renamed to `phase4_*` (e.g. `phase4_5_security_scan_done` → `phase4_security_scan_done`).
- Skill files renamed: `phase-spec-doc.md` → `phase3-implementation.md`; `phase4-5-risk-review.md` → `phase4-risk-gate.md`; `phase4a-ui-build.md` + `phase4b-ui-review.md` merged into `phase2-design-review.md`. Deleted: `phase3-verify.md`.
- Audit event names renamed: `phase-transition-to-execute` → `phase-transition-to-implementation`; `phase4_5_*` → `phase4_*`; `auto-approve-spec` removed.

### Added
- `is_ui_project` auto-detection in Phase 1 brief parse from intent keywords, stack tags, and project file hints. Default true if ambiguous.
- Phase 2 DESIGN_REVIEW: UI projects build a clickable skeleton + dev server, then call AskUserQuestion with pinned body "Tasarımı onaylıyor musun?" / "Approve this design?". Approve advances state.design_approved=true and current_phase=3.
- Phase 4 architectural drift detection: scope_paths vs Phase 3 writes; LOW if scope empty, MEDIUM if sibling layer, HIGH if different layer (frontend→backend).
- Phase 4 intent violation check: phase1_intent negations ("no auth", "no DB", "frontend only") matched against import / path patterns; HIGH violations block Write.
- Spec format advisory mechanism: format violations emit `spec-format-warn` audit (no block); 3+ violations across turns → Phase 6 LOW soft fail.
- State migration audit event: `state-migrated-10.0.0` with backup at `.mcl/state.json.backup.pre-v3`.

### Removed
- Spec approval mechanism (askq-driven and auto-approve). Phase 1 summary-confirm IS the approval gate.
- `spec_approved` state field, `auto-approve-spec` audit, `askq-incomplete-spec` block, `transition-1-to-2`/`transition-2-to-4` audits.
- `phase3-verify.md` skill (no longer applicable).
- Tests: `test-spec-format-enforcement.sh` (replaced by `test-spec-advisory.sh`), `test-askq-incomplete-spec-block.sh` (mechanism removed), `test-partial-spec-post-approval.sh` (no approval mechanism).

### Migration guide
Existing projects: state.json is automatically migrated on first activate after install. A backup is kept at `.mcl/state.json.backup.pre-v3`. No manual action required. The migration sets `is_ui_project=true` and `design_approved=true` on existing projects so the UI review askq does not re-trigger on already-completed work.

---

## [9.3.0] - 2026-05-01 — BREAKING: phase model simplified

### Breaking change

The MCL phase model is restructured. Phase 2 (SPEC_REVIEW) and Phase 3
(USER_VERIFY) are removed. The flow is now:

```
Phase 1 (questions + summary-confirm askq) ──approve──▶ Phase 4 (EXECUTE)
                                                          │
                                                          ├─ 📋 Spec: doc emit (entry artifact)
                                                          ├─ Code writes (Write/Edit/MultiEdit)
                                                          ├─ Phase 4.5 risk review
                                                          ├─ Phase 4.6 impact review
                                                          ├─ Phase 5 verification report
                                                          └─ Phase 6 double-check
```

**State transition driver:** Phase 1 summary-confirm askq approval.
The askq is the only gate; on approval, `current_phase` advances
directly from 1 to 4, `phase_name` becomes `EXECUTE`. Spec emission
no longer drives state — it is documentation.

### Spec is documentation, not a gate

The `📋 Spec:` block emitted at Phase 4 entry serves three roles:
- Audit artifact (`.mcl/specs/NNNN.md` via `mcl-spec-save.sh`)
- Scope guard input (Technical Approach paths populate
  `state.scope_paths`)
- English semantic bridge for non-English prompts

Spec format violations (missing 7 H2 sections, no `📋` prefix) are
**advisory** in 9.3.0. The hook emits `spec-format-warn` audit; no
`decision:block`, no Write tool block. Models can correct format
without losing forward progress on the actual code task.

### Removed

- `spec_approved` field as a state gate. Field still written for
  legacy compatibility (auto-set true on Phase 1→4 transition) but
  hooks no longer read it for transition decisions.
- `auto-approve-spec` audit (was: spec emit auto-advanced state).
- `block-askq-incomplete-spec` PreToolUse block (askq is no longer
  used for spec approval, so guard is moot).
- `MCL SPEC RECOVERY` and `MCL SPEC FORMAT` decision:block paths.
  These now emit `spec-format-warn` audit only.
- Phase 2 (SPEC_REVIEW) and Phase 3 (USER_VERIFY) phase logic from
  `mcl-stop.sh` case-on-current_phase.
- `phase2-spec.md` skill file → renamed to `phase-spec-doc.md` and
  rewritten as documentation artifact spec, not state-gating.

### Added (Phase 4.5 advisory checks)

**Architectural drift detection** (`hooks/lib/mcl-drift-scan.py`).
Compares Phase 4 Write tool calls against `state.scope_paths`. Writes
outside declared scope → `phase4-5-drift` audit (advisory).

**Intent violation detection.** Compares Phase 4 writes against
`state.phase1_intent` + `state.phase1_constraints`. Anti-pattern
matrix:
- Phase 1 says "no auth / no backend" + writes import `next-auth`
  / create `src/api/` → `IV-no-auth-or-backend` finding
- Phase 1 says "no DB / in-memory" + writes import Prisma / create
  `prisma/` → `IV-no-db` finding
- Phase 1 says "offline / local only" + writes import `axios` /
  `node-fetch` → `IV-offline-only` finding

Both checks emit `phase4-5-intent-violation` audit when matched.
Advisory only in 9.3.0; can be promoted to hard blocks in 9.4+.

### Pre-tool Write guard simplified

`mcl-pre-tool.sh` Write/Edit/MultiEdit gate now checks
`current_phase < 4` only. The `spec_approved != true` check and the
JIT auto-advance branch are removed (no longer needed since
phase=4 is set on summary-confirm before any Phase 4 turn starts).

### Test coverage (5 new/updated scenarios)

- `test-phase1-to-phase4.sh` (new): summary-confirm approve →
  state=4; non-approve → state stays at 1; idempotency on already-4.
- `test-canonical-flow.sh` (rewritten): summary-confirm transcript +
  spec-emit fixture; verifies state advance, Write unlock, spec-hash
  recording.
- `test-spec-format-enforcement.sh` (rewritten): bare `Spec:` /
  missing sections → `spec-format-warn` audit + NO `decision:block`;
  Phase 4 Write with bad spec → STILL ALLOWED.
- `test-drift-intent-violations.sh` (new): scope drift fixture
  (`src/api/users.ts` outside `src/components`) → `phase4-5-drift`
  audit; intent violation fixture (`no auth` + `import NextAuth`)
  → `phase4-5-intent-violation` audit; clean writes → 0 findings.
- `test-multi-spec-latest-wins.sh` (updated): no auto-advance on
  Phase 1 spec emit (state stays at 1).
- `test-partial-spec-post-approval.sh` (updated): partial-spec
  detector emits `spec-format-warn` audit, no hard block.
- `test-askq-incomplete-spec-block.sh` (deleted — feature removed).

### Test results

- Default mode: unit **172/0/4**, e2e **54/0/0**
- MCL_MINIMAL_CORE=1: unit **126/0/3**, e2e **54/0/0**

**Total: 406 passing assertions across both modes, both suites. Zero failures.**

### Internal: `mcl_get_active_phase` updated

`hooks/lib/mcl-state.sh:mcl_get_active_phase` no longer requires
`spec_approved=True` to return Phase 4+ values. Phase determination
is `current_phase`-driven (the source of truth in 9.3.0). Legacy
state files with `spec_approved=False` and `current_phase=4` now
return correct Phase 4 instead of `?`.

### Skill prose updates

- `phase2-spec.md` → renamed `phase-spec-doc.md`. Top-of-file
  declaration: "Spec is a living documentation artifact, not a hard
  gate. Developer control is enforced primarily at Phase 1 summary
  confirmation and Phase 1.7 precision audit. Spec format is
  enforced by advisory warning only."
- `phase1-rules.md` rule 6: "On approve (since 9.3.0). Stop hook
  transitions state directly to current_phase=4 (EXECUTE) on
  summary-confirm approve. Phase 2/3 are removed — summary-confirm
  IS the gate."
- `my-claude-lang.md`: phase model diagram + Phase 2/3 paragraphs
  removed; replaced with "📋 Spec Documentation" section describing
  the documentation artifact role.
- `all-mcl.md` STEP-22 already updated in 9.2.2.

## [9.2.3] - 2026-05-01 — UI_REVIEW gate restored as core enforcement

Real-session 9.2.2 ship worked end-to-end (spec auto-approve + Phase 4
build) but vaad #2 broke: model finished without UI review gate. Said
"Onay beklemiyorum, uygulamayı kullanabilirsin" and ended the turn,
silently bypassing Phase 4b entirely.

### Two interlocked root causes

1. **Phase 4.5 enforcement fired on Phase 4a code-write turns.** The
   Phase 4.5 START gate's active-phase regex `^(4|4a|4b|4c|3\.5)$`
   matched `4a` (BUILD_UI sub-phase). Result: the model wrote one UI
   file, the Phase 4.5 reminder block fired with `decision:block`,
   the model interpreted "Phase 4.5 Risk Review IMMEDIATELY" as the
   primary mandate, skipped Phase 4b/4c entirely, and went straight
   to risk dialog. UI never reviewed.

2. **No hard enforcement of Phase 4a → 4b transition.** 9.2.0 deleted
   the silent auto-advance fallback. The replacement was supposed to
   be skill prose mandating `mcl_state_set ui_sub_phase UI_REVIEW`,
   but the model didn't execute that Bash. Without state advancement,
   the dev-server auto-start never fired (it gates on
   `ui_sub_phase=UI_REVIEW`), and the AskUserQuestion was never
   issued.

### Fix (9.2.3)

**(a) Phase 4.5 START scope tightened** (`hooks/mcl-stop.sh:571`).
Active-phase regex changed `^(4|4a|4b|4c|3\.5)$` → `^(4|4c|3\.5)$`.
Phase 4.5 risk review now fires AFTER UI review approval (Phase 4c
backend) — not during 4a/4b. UI flow has its own gate; risk review
runs once on the final integrated codebase.

**(b) New UI_REVIEW gate** (`hooks/mcl-stop.sh:1797`, ~95 lines).
Hard enforcement, not silent fallback:

- When `ui_flow_active=true` AND `ui_reviewed != true` AND
  `ui_sub_phase ∈ {BUILD_UI, UI_REVIEW}` AND the transcript shows
  Write/Edit/MultiEdit calls to frontend paths
  (`src/components`, `src/pages`, `src/styles`, `*.tsx`, `*.vue`,
  `*.svelte`, `package.json`, `vite.config*`, etc.):
  1. Auto-advance `ui_sub_phase: BUILD_UI → UI_REVIEW` so dev-server
     auto-start fires (audit: `ui-sub-phase-auto-advance`).
  2. Scan transcript for any AskUserQuestion with a UI-review prompt
     (regex matches `tasarım.*onayl`, `approve.*(design|ui)`,
     `(onayla|approve).*backend`, etc.).
  3. If askq is missing → emit `decision:block` with reason:
     `MCL: UI hazır. Phase 4b zorunlu — dev server URL'sini paylaş ve AskUserQuestion ile onay iste. Soru body: 'Tasarımı onaylıyor musun?'. Options: Onayla / Değiştir / İptal. Detay: phase4b-ui-review.md.`
     Audit: `ui-review-gate-block`.

   Gate skips entirely when `MCL_MINIMAL_CORE=1` (consistent with
   Phase 4.5 etc).

**(c) Skill prose mandates askq** (`phase4a-ui-build.md`,
`phase4b-ui-review.md`). Removed the "STOP. Do not call
AskUserQuestion" instruction from Phase 4a step 6. Replaced with
"MANDATORY: Call AskUserQuestion (since 9.2.3)" + verbatim template:

```
AskUserQuestion({
  question: "MCL X.Y.Z | Tasarımı onaylıyor musun?",
  options: [
    { label: "Onayla",   description: "Tasarım uygun, backend'e geç" },
    { label: "Değiştir", description: "Şu değişikliği yap: [açıkla]" },
    { label: "İptal",    description: "UI flow'unu durdur" }
  ]
})
```

Phase 4b's free-form prose detection demoted from "primary path" to
fallback; askq is canonical.

### New synthetic test

`tests/cases/test-ui-review-gate.sh`:
1. BUILD_UI + frontend file write + no askq → `decision:block` +
   `ui_sub_phase` auto-advances to UI_REVIEW + both audits captured.
2. UI_REVIEW + askq present → no block (gate satisfied).
3. `ui_flow_active=false` → gate skipped (non-UI project).
4. `ui_reviewed=true` → gate skipped (Phase 4c open, gate done).

### Test results

- Default mode: unit **176/0/4**, e2e **54/0/0**
- MCL_MINIMAL_CORE=1: unit **131/0/3**, e2e **54/0/0**

**Total: 415 passing assertions across both modes, both suites. Zero failures.**

## [9.2.2] - 2026-05-01 — UX hardening: prose cleanup + minimal hook messages

Real-session UX feedback after 9.2.1 ship surfaced three issues:

### 1. Skill prose still instructed model to ask for spec approval

`askuserquestion-protocol.md` listed "Phase 3 spec approval" as moment
#2 with a full Onayla/Approve label table. `all-mcl.md` STEP-22
described the canonical flow as `AskUserQuestion → approve-via-askuserquestion`.
Main `my-claude-lang.md` listed "spec approval" as a closed-ended
askq interaction.

The model — reading skill prose at session start — saw both the new
auto-approve flow AND the old askq flow. It picked the more familiar
askq path and asked "Bu spec doğru mu? Onaylarsak Faz 4'e geçiyorum",
hung waiting for a tool_result that the user didn't see.

**Fix (9.2.2):**
- `askuserquestion-protocol.md`: removed "Phase 3 spec approval" from
  the canonical 11-moment list. Added explicit REMOVED section
  documenting which two askq moments are gone (spec approval, partial-
  spec recovery askq). Renumbered remaining moments 1-12.
- `all-mcl.md` STEP-22: rewritten as `spec-auto-approve` with explicit
  "do NOT ask Onayla / Doğru mu / Faz 4'e geçelim mi" prohibition.
  Audit signal updated: `auto-approve-spec` (not `approve-via-askuserquestion`).
- `my-claude-lang.md`: rewrote the "every closed-ended interaction"
  paragraph with a hard-banned **SPEC APPROVAL DOES NOT USE AskUserQuestion**
  block listing forbidden phrases.

### 2. Hook block reasons too verbose for user-facing display

When `decision:block` fires, the `reason` text appears as a wall of
text in the user's chat. The 9.2.1 messages contained the entire
canonical 7-section template, recovery instructions, and "do NOT debug
hook files" warnings — all useful for the model, but visually
overwhelming for the developer.

**Fix (9.2.2):** message-shape redesign — single line, points to skill
prose for full template:
- `MCL: Spec eksik bölüm — <missing>. Re-emit per phase2-spec.md template.`
- `MCL: Spec format invalid (<offender>) — needs literal '📋 Spec:' prefix + 7 H2 sections per phase2-spec.md. Re-emit.`
- `MCL: Spec eksik bölüm — <missing>. Re-emit complete spec; auto-approve fires on next Stop (no askq needed since 9.2.1).`
- `MCL: <ToolName> blocked. phase=<N> spec_approved=false. Emit format-valid 📋 Spec: block first — auto-approves on next Stop.`
- `MCL: Direct state.json writes forbidden. Transitions are hook-owned. To advance phase, emit a format-valid 📋 Spec: block — auto-approve fires on next Stop.`

The model already has the full template in skill prose; the brief
reason directs it back without re-stating. User sees a single line
instead of a paragraph.

### 3. Phase 1 questions verified to use AskUserQuestion (not regressed)

Confirmed `phase1-rules.md` rule 4 still mandates `AskUserQuestion` for
the Phase 1 summary-confirm and rule 41 for clarifying multi-choice
questions. `askuserquestion-protocol.md` table now lists Phase 1
clarifying + summary-confirm + Phase 1.7 GATE as canonical askq moments.
Phase 1 UX (clickable options) is preserved.

### Test updates

Tests that asserted on the verbose 9.2.1 reason text now match the
9.2.2 minimal format (`format invalid`, `phase2-spec.md` reference,
`Spec eksik` / `decision:block` etc).

### Test results

- Default mode: unit **167/0/4**, e2e **54/0/0**
- MCL_MINIMAL_CORE=1: unit **131/0/3**, e2e **54/0/0**

**Total: 406 passing assertions across both modes, both suites. Zero failures.**

## [9.2.1] - 2026-05-01 — Spec auto-approve, AskUserQuestion approval removed

### Breaking: AskUserQuestion-based spec approval is GONE

Phase 1 (clarifying questions) and Phase 1.7 (precision-audit GATE
questions) already give the developer fine-grained control over spec
content. The AskUserQuestion approval step duplicated that control,
introduced a model-deviation failure mode (paraphrased question bodies
silently failed), and was the dominant source of pipeline-stall bugs.

**New flow:**
1. Phase 1: clarifying questions (existing).
2. Phase 2: model emits `📋 Spec:` block with 7 H2 sections.
3. Stop hook validates spec format → auto-transitions to
   `current_phase=4`, `spec_approved=true` in the same turn. Audit:
   `auto-approve-spec`.
4. Phase 4: Write/Edit unlocked. To reject a spec, developer types
   `/mcl-restart`.

Pre-tool hook also runs the same auto-approve in JIT mode for
same-turn spec + Write sequences. Audit: `auto-approve-spec-jit`.

### Hard-pinned spec format enforcement

Skill prose (`phase2-spec.md`, `phase3-verify.md`, `my-claude-lang.md`)
now mandates the literal `📋 Spec:` line-anchored prefix and 7 H2
sections in exact order:
- `## [Title]` → `## Objective` → `## MUST` → `## SHOULD` →
  `## Acceptance Criteria` → `## Edge Cases` → `## Technical Approach`
  → `## Out of Scope`

Hook-level enforcement: `mcl-partial-spec.sh` returns rc=3 when the
model emits spec-LIKE text without the `📋` prefix (bare `Spec:`,
`## Spec`, `## Faz N — Spec`). Stop hook handles rc=3 with
`spec-no-emoji-block` audit and a `decision:block` carrying the exact
canonical template — model retries with the verbatim format.

### Pre-tool Write guard simplified

Single condition: `spec_approved != true` → block. Phase value moved
to error-message context only. Eliminates stale-phase-read deny bugs
(e.g., "phase=1" when state actually shows phase=2).

### Comprehensive synthetic test coverage (16 failure modes)

New tests in `tests/cases/`:
- `test-spec-format-enforcement.sh` — bare `Spec:`, `## Spec`,
  `## Faz N — Spec`, missing H2 sections, canonical complete
- `test-canonical-flow.sh` — full happy path: spec emit → auto Phase 4
  → Write allowed; same-turn JIT advance
- `test-multi-spec-latest-wins.sh` — re-emit recovery, latest spec wins
- `test-phase4-5-gates.sh` — Phase 4.5 START fires sec/db/ui/ops/perf
- `test-state-path-isolation.sh` — state lives at MCL_STATE_DIR, never
  in CLAUDE_PROJECT_DIR/.mcl
- `test-severity-blocks-write.sh` — HIGH-severity per-write block
- `test-minimal-core-skips.sh` — MCL_MINIMAL_CORE=1 skip semantics

New helper: `tests/lib/build-transcript.py` — synthesizes realistic
Claude Code JSONL transcripts with named fixture kinds.

### Critical fix — macOS `timeout` binary missing silently disabled all Phase 4.5 scans

`mcl-stop.sh` used `timeout 120 python3 mcl-security-scan.py ...` for
all five Phase 4.5 scans + Phase 6 helper. macOS doesn't ship `timeout`
by default; the command failed silently → empty JSON → scanner findings
discarded → HIGH issues never blocked. This was a pre-existing
months-long silent disablement on every macOS install.

Added portable `_mcl_timeout` shim that prefers `timeout`, falls back
to `gtimeout`, then runs the command directly when neither is present.
Each Python helper has its own internal subprocess timeouts as a
fallback safety.

### Additional 9.2.1 test coverage

- `test-security-full-scan-blocks.sh` — Express+SQL HIGH fixture exercises
  the full scan-to-block path through `mcl-security-scan.py` (G01 rule),
  asserts Stop hook emits `MCL SECURITY` block + `security-scan-block`
  audit, then verifies recovery (parameterized query → gate clears).
- `test-phase4-5-to-6-cycle.sh` — multi-turn fixture: iteration-1
  baseline (HIGH=0) + iteration-2 regression (1 new HIGH from sort
  parameter concat) + Phase 5 verification report → Phase 6 (b) detects
  the regression and emits `phase6-block`. Verifies
  `phase4_5_high_baseline.security` stays at 0 (not silently raised).
- `test-ui-synthetic-pass.sh` — UI sub-phase state machine (BUILD_UI →
  REVIEW → BACKEND), frontend/backend path-exception. **Vaad #2
  (browser-rendered UI vs spec match) marked synthetic-pass — requires
  real-session confirmation in production.**

### Test results

- Default mode: unit **166/0/4**, e2e **54/0/0**
- MCL_MINIMAL_CORE=1: unit **131/0/3**, e2e **54/0/0**

**Total: 405 passing assertions across both modes, both suites. Zero failures.**

### Removed

- `mcl-stop.sh`: askq-driven spec-approve transition branch (~200 lines)
- `mcl-pre-tool.sh`: askq-spec-approve JIT advance + summary-confirm
  JIT advance (replaced with spec-format JIT advance)
- Skill prose: AskUserQuestion call instructions in phase2-spec.md,
  phase3-verify.md, my-claude-lang.md
- `tests/cases/test-askq-non-pinned-body.sh`: test of removed feature

## [9.2.0] - 2026-04-30 — Minimal Core: fallback removal + canonical path fixes

### Breaking: hook fallbacks permanently deleted

All hook-level fallbacks that masked model behavior deviations are permanently removed from `mcl-stop.sh` (no flag, no recovery):
- **9.1.1** spec-approve reclassify (intent=other → spec-approve via state context)
- **8.19.0** brief-parse state population (phase1_intent/ops/perf/ui_sub_phase from transcript)
- **9.1.0** precision-audit auto-emit + ops/perf default-fill
- **9.1.0** ui_sub_phase auto-advance (hook-first fallback)
- **9.1.0** phase5-verify auto-emit (hook-first fallback)

Phase 1→2 transition is now a direct 5-line block with no guards.

### Feature-flag-off: MCL_MINIMAL_CORE=1

Non-essential enforcement systems skipped when `MCL_MINIMAL_CORE=1` (code kept):
- Partial-spec recovery (mcl-stop.sh)
- Phase 4.5 Ops + Perf gates (mcl-stop.sh)
- Phase 4.5 test-coverage lens (mcl-stop.sh)
- Phase 6 double-check (mcl-stop.sh)
- Hook-debug Bash + Read/Grep/Glob blocks (mcl-pre-tool.sh)
- Severity per-write enforcement — sec/db/ui scan blocks (mcl-pre-tool.sh)

### Skill prose: pinned question body

`phase3-verify.md`, `my-claude-lang.md`, `phase2-spec.md`: AskUserQuestion question body for spec approval pinned to exact scanner token. TR: `Spec'i onaylıyor musun?` / EN: `Approve this spec?`. Label table trimmed to TR + EN only. Any paraphrase → intent="other" → visible failure.

### Bug fixes

**(1) Write guard: spec_approved is now sole gate** (`mcl-pre-tool.sh`). Previously `CURRENT_PHASE -lt 4` was checked first — stale phase reads caused spurious "phase=1" denies even when state had phase=2. Now: `SPEC_APPROVED != "true"` is the only condition; phase value included in error message as diagnostic context only.

**(2) Scanner visibility: unconditional audit per Stop turn** (`mcl-stop.sh`). `askq-scanner-result | mcl-stop | intent=... selected=... has_record=...` emitted after every scanner run. `has_record=false` → PREFIX_RE miss or no tool_result; `intent=other` → body not tokenized; `intent=spec-approve` but no transition → guard bug downstream.

### Tests removed

- `test-spec-approve-reclassify.sh` — covered deleted reclassify
- `test-precision-audit-fallback.sh` — covered deleted auto-emit
- `test-precision-audit-escape.sh` — covered deleted block counter
- `test-phase-detect.sh` — covered deleted mcl-phase-detect.py fallback

e2e: phase_5 / phase_5b state-population assertions removed.

Result: unit 102/0/2, e2e 54/0/0.

## [9.1.4] - 2026-04-30 — AskQ-Level Spec Enforcement + Reclassify Diagnostics

Real-session bug raporu (9.1.3 sonrası): "spec_approved=true STILL not set after approval" — 9.1.1 reclassify-fallback fire etmedi. **Investigated root cause first.** Synthetic transcript ile reproduce ettim:

### Root cause chain
1. Model kısa spec emit ediyor (Project + Pages + Stack notları, no 7-section).
2. Stop-hook partial-spec block fire ediyor (`decision:block` + `exit 0`).
3. Phase 1→2 transition **hiç çalışmıyor** → `state.spec_hash=null`.
4. Ama askq tool_use **aynı turn'de** zaten emit edilmiş (Stop hook'undan ÖNCE) → kullanıcıya ulaşıyor.
5. Kullanıcı "Evet, oluştur" tıklıyor → tool_result.
6. Sonraki Stop'ta 9.1.1 reclassify-fallback'ı: `_SCFB_HASH=null` (state hash yok) → guard fail → reclassify SKIP.
7. Write attempt → mcl-pre-tool.sh `current_phase=1` lock.

### Fix — Three layers

**(A) Diagnostic audits at each reclassify gate.** 9.1.1 fallback yolunda her gate (`phase`, `spec-hash`, `approve-family`) skip edilirse explicit audit emit ediyor. Forensic analiz için:
```
askq-reclassify-skipped | mcl-stop | gate=phase phase=1 selected=Evet, oluştur
askq-reclassify-skipped | mcl-stop | gate=spec-hash phase=2 hash_source=state
askq-reclassify-skipped | mcl-stop | gate=approve-family selected=Düzenle
```

**(B) PreToolUse-level askq deny on incomplete spec.** Yeni branch `mcl-pre-tool.sh`'da: `current_phase ∈ {1,2,3}` AND last assistant text incomplete `📋 Spec:` block içeriyorsa AskUserQuestion **PreToolUse'da deny ediliyor**. askq tool_use bile gerçekleşmiyor; kullanıcı yarım-spec'i onaylamak zorunda kalmıyor. Phase 4+ askq pass-through (Phase 4.5 risk dialog vb. farklı intent). Block reason'da 7-header template + "complete spec FIRST, askq AFTER" talimatı.

**(C) Reclassify-fallback uses local SPEC_HASH (transcript-derived) when state.spec_hash null.** mcl-stop.sh'ın local `SPEC_HASH` var'ı transcript taramasından populate olur (state'ten bağımsız). Fallback önce state'i sorar, null ise local'a düşer. Audit'te `hash_source=state` veya `hash_source=transcript` etiketleniyor.

### Approve-family ek dilbilgisi
9.1.1 listesi `*evet*`, `*onayla*`, `*başla*` içeriyordu. 9.1.4 ek: `*oluştur*` (TR — "Evet, oluştur"), `*create*` (EN — "Create it / Approve and create"). Real-session bulgular dilbilgisini genişletiyor.

### Yeni audit events
- `block-askq-incomplete-spec | pre-tool | phase=N missing=<csv>`
- `askq-reclassify-skipped | mcl-stop | gate=<phase|spec-hash|approve-family> ...`
- `askq-reclassified-spec-approve | mcl-stop | ... hash_source=<state|transcript>`

### Yeni test
`tests/cases/test-askq-incomplete-spec-block.sh` — 5 case:
1. Phase 1 + short spec → askq deny + missing list + 7-header template.
2. Phase 1 + complete 7-section spec → allow.
3. Phase 4 + short spec → allow (gate phase-scoped).
4. Phase 1 + no spec block → allow (Phase 1 summary-confirm path).
5. Audit captures `block-askq-incomplete-spec`.

### Bilinen sınırlar
- (B) askq-deny `📋 Spec:` line'ı arıyor; model spec emit ediyor ama farklı marker (örn. yalnızca `# Spec`) kullanırsa miss eder. Mevcut MCL skill prose'u canonical marker'ı zorunlu kılıyor; model uymuyorsa diğer hooklar yine yakalar.
- Diagnostic audit'leri Phase 6 (a) raporunda görünmez (sadece audit log forensic). 9.2'de `/mcl-doctor` raporuna bağlanabilir.

### Tests
- Unit: **161/0/2** (önce 154 → +7: askq-incomplete-spec-block 5-case + audit assertions)
- E2E: **65/0/0** — regresyonsuz

## [9.1.3] - 2026-04-30 — Project Isolation Enforcement

Real-session bug: kullanıcı `/Users/umitduman/ABCD` projesinde session başlattı, model `cd /Users/umitduman && npx create-next-app ...` çalıştırdı, ardından `/Users/umitduman/backoffice/` (kardeş proje) dosyalarını okudu. **Vaad #1 (proje izolasyonu) ihlal edildi.**

MCL'in temel taahhüdü: per-project state dizini + per-project hook scope = "bu MCL sadece bu projeyi tanır". `MCL_STATE_DIR` envelope'u doğru kullanılıyordu ama **tool çağrılarının file system kapsamı enforce edilmiyordu** — model `CLAUDE_PROJECT_DIR` dışına çıkabiliyordu.

### Fix

`hooks/mcl-pre-tool.sh` yeni isolation branch — tüm phase'lerde fire eder:

**Bash:**
- `cd ..`, `cd ../foo`, `pushd ..` → deny (lexical escape)
- `cd ~`, `cd ~/x`, `cd $HOME` → deny
- `cd /Users/other`, `cat /Users/other/file` → deny (absolute outside whitelist)
- `cat ../sibling/file.ts` → deny (`../` argv token in any command)
- `node ./bin/cli.js`, `cd src && ls`, `npm install`, `git status` → allow
- `cd /tmp/build` → allow (whitelist)

**Read / Write / Edit / MultiEdit / Glob / Grep / NotebookEdit:**
- `file_path` / `path` / `notebook_path` absolute resolve → outside project + whitelist → deny
- `pattern` if absolute / tilde / contains `../` → resolve + check
- Project-relative globs (`src/**/*.ts`) → allow

### Whitelist (read/exec from any phase)

| Path | Reason |
|---|---|
| `$CLAUDE_PROJECT_DIR` | Project root |
| `/tmp`, `/private/tmp`, `/var/tmp`, `/var/folders` | Build scratch (npm/vite cache) |
| `~/.npm`, `~/.cache`, `~/.yarn`, `~/.pnpm-store` | Package manager caches |
| `~/.cargo`, `~/.rustup`, `~/.gradle`, `~/.m2`, `~/.bun` | Stack-specific caches |
| `~/.claude/skills/my-claude-lang*` | MCL skill files (legitimate Phase 1-3 read) |
| `~/.claude/hooks/lib/mcl-stack-detect.sh` | Phase 1.7 stack detection helper |
| `~/.mcl` | MCL state dir |
| `/usr` | System binaries (`/usr/bin/git`, `/usr/local/bin/node`) |

### Order with existing hook-debug branches

İzolasyon **AFTER** Phase 1-3 hook-debug branches (Bash + Read/Grep/Glob, 8.19.3 / 9.0.0). Hook-debug `~/.mcl/lib/...` ve `~/.claude/hooks/...` reads'lerini Phase 1-3'te narrow "trust the pipeline" reason'ıyla denies; isolation broader cross-project boundary kontrolü ekler. Order kritik: isolation önce gitse `~/.mcl` whitelist hook-debug'ı maskelerdi.

### Block reason

```
MCL ISOLATION — operations outside project directory ($CLAUDE_PROJECT_DIR)
are blocked. Stay in the current project. Allowed system paths: build
scratch (/tmp, /var/folders), package caches (~/.npm, ~/.cache, ~/.yarn,
~/.pnpm-store, ~/.cargo, ~/.gradle, ~/.m2, ~/.bun), MCL skill files
(~/.claude/skills/my-claude-lang), Phase 1.7 stack-detect
(~/.claude/hooks/lib/mcl-stack-detect.sh), MCL state (~/.mcl), system
bins (/usr). For sibling project access, exit and re-enter MCL inside
that project.
```

### Yeni audit event
- `block-isolation | pre-tool | tool=<X> detail=<reason>:<token>`

### Yeni test
`tests/cases/test-project-isolation.sh` — 28 case:
- Bash escape patterns (cd .., cd ../foo, cd ~, cd $HOME, pushd ..)
- Bash absolute outside (cd /Users/other, cat /etc/passwd, cat ../escape)
- Bash in-project + whitelist (cd /tmp/build, npm install, git status, node ./bin)
- Read/Write/Edit cross-boundary deny + whitelist allow
- Glob/Grep pattern handling (project-relative allow, ../ deny, absolute outside deny)
- Phase-agnostic check (Phase 1 + cd .. → deny aynı şekilde)
- Audit log captures block-isolation events

### Bilinen sınırlar
- Pattern-based (syntactic), realpath resolution değil. `eval $(echo cd ..)` gibi obfuscated escape'leri kaçar; legitimate model davranışı obfuscation kullanmaz.
- Whitelist sabit: yeni package manager (`~/.deno`, vb.) için update gerek.
- Symlink resolve: Python `os.path.normpath` kullanılır; `os.path.realpath` değil. Aynı project'e symlink ile ulaşan yollar normalize edilmeyebilir. 9.2'de değerlendir.

### Tests
- Unit: **154/0/2** (önce 126 → +28: project-isolation 28-case regression)
- E2E: **65/0/0** — regresyonsuz

## [9.1.2] - 2026-04-30 — Partial-Spec Post-Approval Guard

Real-session bug: model emit kısa ad-hoc spec (Project + Pages + Stack notu) **Phase 4 prose'unda**, **AslolanSpec onaylanmıştı VE Phase 4 işi tamamlanmıştı**. mcl-stop.sh partial-spec detector bu kısa prose'u yakaladı, eksik 7 zorunlu section tespit etti, "MCL SPEC RECOVERY" decision:block emit etti → kullanıcı session sonunda hata bloğu gördü.

### Root cause

`hooks/mcl-stop.sh:283` partial-spec branch'ı `spec_approved` durumuna bakmadan her Stop turn'ünde fire ediyordu. Recovery path'i pre-approval window için tasarlanmıştı (rate-limit interruption defense), ama post-approval'da kısa spec-stili Phase 4 prose'larını yanlışlıkla "truncated spec" olarak yorumluyor.

### Fix

`mcl-stop.sh:283-310` partial-spec branch'ı `spec_approved=false` guard'ı ile sarıldı. Onay verildikten sonra retroactive recovery devre dışı; hangi prose görünürse görünsün, partial-spec detector susar.

```bash
_PS_APPROVED="$(mcl_state_get spec_approved 2>/dev/null)"
if [ "$_PS_APPROVED" = "true" ]; then
  : # spec already approved — partial-spec detection retired
else
  ... existing detection ...
fi
```

Pre-approval davranışı korundu: spec_approved=false iken detector yine fire eder; legitimate truncation defense intakt.

### Skill prose strengthening

`skills/my-claude-lang/phase2-spec.md` Rule 4 olarak yeni mandate eklendi: spec block 7 zorunlu section header'ı içermeli. Kısa / freeform / "Project + Pages + Stack" notları kabul edilmiyor — partial-spec hook eksik header'ları tespit edip transition'ı rewind ediyor. Headers (kanonik):
```
## Objective
## MUST
## SHOULD
## Acceptance Criteria
## Edge Cases
## Technical Approach
## Out of Scope
```

Genuinely empty section → header altında `- (none)`. Heading levels: `##` (h2) standart; partial-spec scanner h2/h3/inline-bold varyantlarını kabul eder ama `##` forward-compatibility için kanonik.

### Yeni test

`tests/cases/test-partial-spec-post-approval.sh` — 4 case:
1. spec_approved=true + kısa spec prose → SPEC RECOVERY block emit edilmemeli.
2. spec_approved=true → partial-spec audit count büyümemeli (detector skip).
3. spec_approved durumu post-Stop'ta değişmemeli.
4. spec_approved=false (regression guard) → detector hâlâ legitimate fire eder.

### Tests
- Unit: **126/0/2** (önce 122 → +4: post-approval guard 4-case regression)
- E2E: **65/0/0** — regresyonsuz

## [9.1.1] - 2026-04-30 — Spec-Approve Reclassification Fix

Real-session bug raporu: AskUserQuestion onayı tespit edilmedi → `spec_approved=false` kaldı → Phase 4 transition block'landı → mcl-pre-tool.sh Write tool'u deny etti → kullanıcı "MCL LOCK Phase 1" döngüsü gördü.

### Root cause

`hooks/lib/mcl-askq-scanner.py:174-184` AskUserQuestion intent'ini **question body token'ları** ile sınıflıyor. SPEC_APPROVE_TOKENS listesinde "spec'i onayla", "is this correct" gibi sabit fragmanlar var. Model, spec onay sorusunu listede olmayan farklı şekillerde sorduğunda (örn. "Bu plan uygun mu?", "Devam edelim mi?") body match etmiyor → `intent="other"` → `mcl-stop.sh:1690` `if [ "$ASKQ_INTENT" = "spec-approve" ]` gate'i geçilemiyor → spec_approved transition fire etmiyor.

Token tabanlı sınıflandırma kırılgan. Doğru sinyal: state context.

### Fix

`hooks/mcl-stop.sh:436` (askq-scanner sonrasında) state-aware reclassification fallback eklendi. Mantık:
- `intent == "other"` AND
- `current_phase ∈ {2, 3}` AND
- `spec_hash` set AND
- `selected option` approve-family pattern'inden birine match (14 dil)

→ intent yeniden `"spec-approve"` olarak set edilir; mevcut spec-approve transition path'i fire eder. Audit `askq-reclassified-spec-approve | mcl-stop | source=state-context-fallback`.

### Tasarım gerekçesi

**State context > question body tokens.** Token listesi sürdürülemez (model phrasing varyasyonları sonsuz). State, MCL'in pipeline pozisyonunu kesin olarak bilir. Phase 2/3 + spec_hash present = "spec emit edildi, onay bekliyor" demek. Bu pencerede MCL-prefixed AskUserQuestion + approve-family selected = onay anlamına gelir, soru gövdesinden bağımsız.

### Phase 1 false-positive guard

`current_phase ∈ {2, 3} + spec_hash` zorunluluğu kritik. Phase 1 summary-confirm + Phase 1.7 GATE soruları da MCL prefix + approve-family options kullanıyor. Bu rule olmadan, "Bu özet doğru mu?" sorusunda "Onayla, başla" seçimi Phase 1'i Phase 4'e fırlatırdı (spec yokken). `phase=1` durumunda `spec_hash=null` → reclassification fire etmez.

### 9.1.0 hook fallbacks korundu

User'ın istediği "drop unnecessary fallbacks" değerlendirildi: 9.1.0 hook fallbacks (precision-audit, phase1_ops/perf default-fill, ui_sub_phase auto-advance, phase5-verify auto-emit) farklı state field'larını ele alıyor — spec_approved bug'ı ile orthogonal. Kaldırılmaları 9.0.x bug'larını geri getirir. Dokunulmadı.

### Yeni audit event

- `askq-reclassified-spec-approve | mcl-stop | phase=N selected=X source=state-context-fallback`

### Yeni test

`tests/cases/test-spec-approve-reclassify.sh` — 4 case:
1. Untokenized soru ("Bu plan uygun mu?") + "Onayla, başla" → reclassify + Phase 4 transition.
2. Tokenized soru ("Spec'i onayla?") → original path; reclassify fire etmez.
3. Untokenized soru + "Düzenle" (non-approve) → no transition; selected option authoritative.
4. Phase=1 + approve-family → guard tutuyor; reclassify fire etmez (spec yok).

### Tests
- Unit: **122/0/2** (önce 113 → +9: spec-approve-reclassify 4 senaryo)
- E2E: **65/0/0** — regresyonsuz

## [9.1.0] - 2026-04-30 — Hook-First Architecture

Real-session bulgusu: model 4 kez precision-audit-block aldı. Asıl soru iyiydi: Phase 1.7 audit MCL'in iç bookkeeping'i; spec başarılı emit edilmiş + summary onaylanmışsa kullanıcının bu mesajları görmemesi gerek. 9.1.0 mimari değişiklik: tüm "model Bash zorunlu" path'leri "hook fallback" path'lerine taşır. Skill prose Bash opt-in optimization olarak kalır (caller=skill-prose audit provenance, synchronous-write); yokluğunda hook her şeyi sessizce halleder.

### Mimari değişiklik

**Önce (9.0.x):** Skill prose Bash MUST → Hook bekler → Yoksa block + reminder + escape.
**Sonra (9.1.0):** Hook fallback PRIMARY → Skill prose Bash opt-in.

5 path tek mimari pattern altında (4'ü 9.1.0'da yeni, biri 8.18.2'de yapılmıştı):

| Path | 9.1.0 davranış |
|---|---|
| `phase1_intent / constraints / stack_declared` | Engineering Brief parse (8.18.2) — değişmedi |
| **`precision-audit` audit** | Spec body'de `[assumed:]` + `[unspecified:]` count + stack-detect → hook auto-emit |
| **`phase1_ops` / `phase1_perf`** | Hook industry-default'larla auto-fill (`docker-compose / basic / pragmatic / internal / pragmatic`) |
| **`ui_sub_phase=UI_REVIEW`** | `dev-server-started` audit + last-assistant turn'de localhost URL + localized "browser opened" cue → hook auto-set |
| **`phase5-verify` audit** | Last assistant turn'de localized "Verification Report" header (14 dil) + post-Phase-4 → hook auto-emit |

Sonuç: kullanıcı sadece "Phase 1 sorusu → spec onayı → çalışan proje" akışını görür. "precision-audit", "skip-precision-audit", "block fired", "transition rewind" mesajları kullanıcı UX'inden çıkar; hook hepsini sessizce halleder.

### Değişen dosyalar

#### `hooks/lib/mcl-phase-detect.py` — 3 yeni mode
- `--mode=spec-markers` → `[assumed:]` ve `[unspecified:]` count'larını döndürür (`{"assumed_count": N, "unspecified_count": M}`).
- `--mode=ui-review-signal` → last assistant turn'de localhost URL **VE** localized "browser opened" cue eşzamanlı varsa `true`. Conservative — yalnızca URL veya yalnızca prose tek başına yetmez (false positive'i önler).
- `--mode=phase5-verify-detected` → 14-dil Verification Report header'larından biri last assistant turn'de varsa `true` + matched header. mcl-stop.sh:1769 fallback regex'i ile aynı set.
- Default mode (`--mode=full`) backward-compat — pre-9.1.0 davranış.

#### `hooks/mcl-stop.sh` — 4 yeni fallback section
1. **precision-audit auto-emit** — Phase 1→2 transition'da `_PA_HIT != "hit"` ise spec-markers helper çağrılır, audit `caller=mcl-stop, source=hook-fallback` ile emit edilir, `_PA_HIT="hit"` set edilir → block hiç fire etmez.
2. **phase1_ops/perf default-fill** — Aynı turn'de idempotent (state field zaten doluysa skip). Industry-default JSON object'leri.
3. **ui_sub_phase auto-advance** — Stop sonu, Phase 4a → 4b transition. Trigger: `ui_flow_active=true` + `ui_sub_phase ∈ {null, BUILD_UI}` + `dev-server-started` audit + ui-review-signal positive.
4. **phase5-verify auto-emit** — Stop sonu, post-Phase-4. Trigger: phase5-verify audit eksik + `current_phase >= 4` + phase5-verify-detected positive.

#### Audit-file existence check fix
- `mcl-stop.sh:1527` — Phase 1.7 precision-audit gate önceden `[ -f audit.log ]` ile gated'di; missing file = whole gate skipped (yeni session'da fallback hiç fire etmiyordu). 9.1.0 file check kaldırıldı; Python scanner missing file'ı zaten graceful handle ediyor.

#### Skill prose updates (3 dosya — opt-in optimization notes)
- `skills/my-claude-lang/phase1-7-precision-audit.md` — "Hook-first audit emission" bölümü; skill prose Bash hâlâ valid + preferred (caller=skill-prose provenance), ama no longer required.
- `skills/my-claude-lang/phase4a-ui-build.md` — "Hook-first auto-advance" bölümü; UI_REVIEW transition trigger conditions açıklaması.
- `skills/my-claude-lang/phase5-review.md` — "Hook-first audit emission" bölümü; 14-dil header detection.

### Yeni testler
- `tests/cases/test-phase-detect.sh` — 7 yeni case (spec-markers count, ui-review-signal positive/negative, phase5-verify-detected TR/EN/no-header, spec-markers no-spec graceful).
- `tests/cases/test-precision-audit-fallback.sh` — 8 case (transition smoothness, audit emit, count parsing, ops/perf defaults, idempotency).

### Audit log değişiklikleri
- `precision-audit | mcl-stop | source=hook-fallback ...` (yeni — fallback path'i izi)
- `phase1_ops_populated | mcl-stop | source=hook-default` (yeni — default-fill izi)
- `phase1_perf_populated | mcl-stop | source=hook-default` (yeni)
- `ui_sub_phase_set | mcl-stop | source=hook-detection` (yeni)
- `phase5-verify | mcl-stop | source=hook-detection header=...` (yeni)

`source=skill-prose` ve `source=hook-*` etiketleri her zaman audit'te coexist. Phase 6 (a) check ikisini de "present" sayar; provenance forensic.

### Bilinen sınırlar
- `[assumed:]` / `[unspecified:]` count parsing skill prose'a güveniyor. Model spec'te marker'ları doğru yazmazsa count yanlış olur (worst case: 0/0). `phase1_ops` / `phase1_perf` field'ları count'tan değil, kendi default'larından okunur — downstream etkilenmez.
- `phase1_ops` / `phase1_perf` default'ları sabit (`docker-compose / basic / pragmatic / internal / pragmatic`). Stack-aware default'lar 9.2'ye bırakıldı.
- UI_REVIEW heuristic conservative — model dev-server'ı asla başlatmazsa miss; o senaryoda zaten UI build done değil. False-negative kabul edilebilir.
- 14-dil Verification Report header set sabit (`mcl-phase-detect.py` + `mcl-stop.sh:1769` + `phase5-5-localize-report.md` üç yerde duplicate). Tek-yer constants module 9.2'ye bırakıldı.
- Skill prose Bash kaldırılmadı — `caller=skill-prose` ile `caller=mcl-stop` audit'te coexist; forensic provenance kaybı yok.
- Hook-fallback modeli kullanıcıya görünmez → debug hard. Audit log'daki `source=hook-fallback` / `source=hook-default` / `source=hook-detection` etiketleri `/mcl-self-q` veya `mcl-doctor` ile yüzeye çıkar; default UX'te görünmez.

### Tests
- Unit: **113/0/2** (önce 96 → +17: phase-detect 7 yeni mode case + precision-audit-fallback 8 yeni e2e case + 2 ek)
- E2E: **65/0/0** — regresyonsuz

## [9.0.0] - 2026-04-30 — Standalone Maturation

Real-session log (1+ saat Phase 1'de takılı, kullanıcı session'ı abort etti) 6 ayrı failure mode'u ortaya koydu. 9.0.0 tek konsolide release ile hepsini kapatır + 8.19.2 superpowers-removal'ın breaking-change boyutunu semver'e taşır.

### Breaking changes
- **Phase 4.5 code-review dispatch** — `superpowers:code-reviewer` artık kabul edilen prefix listesinde değil (8.19.2). `pr-review-toolkit:code-reviewer` veya `code-review:*` zorunlu. `install-claude-plugins.sh` zaten her ikisini install eder; ek aksiyon gerekmiyor.
- **Phase 1-3 dosya erişim kapsamı** — `~/.mcl/lib/`, `~/.claude/hooks/`, `~/.mcl/projects/<key>/state/` ve mcl-* skript dosyaları Phase 1-3'te `Bash`, `Read`, `Grep`, `Glob` tool'ları ile okunamaz (hook-debug block). Phase 4+ pass-through; whitelist: `bash mcl-stack-detect.sh detect`, skill-prose `source mcl-state.sh; mcl_state_set`.

### Düzeltildi — 6 failure mode

#### (A) Partial spec recovery (model loop fix)
- **`hooks/mcl-stop.sh:283-310`** — Partial-spec detect'inde audit-only path artık `decision:block` JSON emit ediyor. Block reason'da: spesifik missing-section listesi + tam markdown header template (`## Objective\n## MUST\n## SHOULD\n## Acceptance Criteria\n## Edge Cases\n## Technical Approach\n## Out of Scope`) + "tek bütün spec block — delta yazma" + "hook file debugging yasak". Model aynı turn'de complete spec emit etmek zorunda.
- **`skills/my-claude-lang/phase2-spec.md`** — Spec template explicit + flat (`## H2` headers, nested olmayan). Genuinely empty section → `- (none)` placeholder; header asla atlanmaz.
- **`hooks/mcl-activate.sh`** — `PARTIAL_SPEC_NOTICE` (8.19.3'te yapıldı) audit log'tan en son `partial-spec | ... missing=...` listesini parse edip notice'a inject ediyor. Generic 7-section listesi yerine SPESİFİK eksik isimler.

#### (B) Phase 1.7 escape
- **`hooks/mcl-stop.sh:1539-1565`** — precision-audit-block her fire'da `precision_audit_block_count++`. Block reason'a `>= 3` olduğunda hint: "bir sonraki turn'de AskUserQuestion ile 3 seçenek".
- **`hooks/mcl-activate.sh`** — `precision_audit_block_count >= 3` ise `PRECISION_ESCAPE_NOTICE` inject: model'e talimat AskUserQuestion 3-option (devam / `/mcl-skip-precision-audit` / `/mcl-restart`) sunması için.
- **`hooks/mcl-activate.sh`** — Yeni `/mcl-skip-precision-audit` keyword branch:
  - `count < 3` ise reject + audit `precision-audit-skip-attempt-too-early`.
  - `count >= 3` ise accept + counter reset + `precision_audit_skipped=true` + skill talimatı (spec'teki dimension'lara `[hook-default: industry]` marker'ı, Phase 3'te developer revize eder).
- **Counter reset** — Phase 1→2 transition'da otomatik sıfırlanır (`mcl-stop.sh` spec-emit branch'inde).

#### (C) Hook debugging block — kapsam genişletme
- **`hooks/mcl-pre-tool.sh:204-242`** (8.19.3'te yapıldı) — Bash tool'da MCL hook/lib/state path'leri Phase 1-3'te deny.
- **9.0.0 ek** — `Read`, `Grep`, `Glob` tool'ları için aynı path-deny. Whitelist yok (Phase 1-3'te bu tool'larla hook path okumanın legitimate sebebi yok). Audit format: `block-hook-debug | pre-tool | tool=<Read|Grep|Glob|Bash> phase=<N> ...`.

#### (D) State hack severity bump
- **`hooks/lib/mcl-phase6.py`** — Yeni `check_state_hack_attempts(audit_log)`. `deny-write | <caller> | unauthorized` audit count > 0 → **HIGH** soft fail (`P6-A-state-hack-attempt`). Phase 6 (a) chain'e eklendi (`high.extend(...)`). Auth-check zaten reject ediyor; bu sadece forensic surface.

#### (E) Phase 1 stuck escape
- **`hooks/mcl-stop.sh`** end-of-Stop — `current_phase=1` ise `phase1_turn_count++`. Phase 1→2 transition'da reset.
- **`hooks/mcl-activate.sh`** — Yeni `PHASE1_STUCK_NOTICE`:
  - `count >= 10 && < 20`: advisory ("`/mcl-restart` ile yeniden başlayabilirsin").
  - `count >= 20`: forced AskUserQuestion talimatı (continue / `/mcl-restart` / `/mcl-finish`).
- **Counter reset** — spec-approve, summary-confirm, 1→2 transition.

#### (F) Plugin uninstall otomasyonu
- **`install.sh`** (8.19.3'te yapıldı) — Idempotent best-effort 3 syntax form ile superpowers uninstall:
  ```
  claude plugin uninstall superpowers || true
  claude plugin uninstall superpowers@superpowers-marketplace || true
  claude plugin marketplace remove obra/superpowers-marketplace || true
  ```
  Manual fallback: `claude plugin uninstall superpowers`.

### Yeni state field'lar (`hooks/lib/mcl-state.sh` default schema)
- `phase1_turn_count: 0` — Phase 1 turn counter (escape mechanism).
- `precision_audit_block_count: 0` — Precision-audit block fire counter (escape).
- `precision_audit_skipped: false` — `/mcl-skip-precision-audit` flag.

### Yeni audit event'leri
- `block-hook-debug` (genişletildi: tool=Read/Grep/Glob/Bash)
- `precision-audit-skip-attempt-too-early`
- `precision-audit-skip-accepted`
- `phase1-stuck-advisory` (mcl_audit name içinde)
- `phase1-stuck-forced-askuq` (mcl_audit name içinde)
- `precision-audit-escape` (mcl_audit name içinde)

### Yeni testler
- `tests/cases/test-hook-debug-readers.sh` — Read/Grep/Glob block + Phase 4 pass-through.
- `tests/cases/test-state-hack-soft-fail.sh` — `check_state_hack_attempts` 5 case (boş, 1 deny, 3 deny, irrelevant, missing-qualifier).
- `tests/cases/test-precision-audit-escape.sh` — 4 case (count=0/2 reject, count=3/5 accept, audit forensic).
- `tests/cases/test-phase1-stuck.sh` — 5 case (5/10/15/20 thresholds, phase=2 skip).

### Bilinen sınırlar
- 3-retry budget kullanıcı sabırına bağlı; sabırsız kullanıcı için yine takılma riski. 9.0.x'te `MCL_PRECISION_AUDIT_RETRY_BUDGET=N` env override eklenebilir.
- AskUserQuestion-bağımlı escape — model AskUserQuestion'ı çağırmazsa stuck devam. Hook-level forced exit yok.
- Plugin uninstall syntax versiyon-bağımlı (Claude Code 1.x vs 2.x). 3 form best-effort + manuel fallback.
- E2E Phase 8 (1+ saat stuck simulation) deferred — unit tests stuck threshold'larını kapsıyor; e2e ileri sürümde.

### Tests
- Unit: **96/0/2** (önce 59 → +37: 4 yeni 9.0.0 test dosyası)
- E2E: **65/0/0** — regresyonsuz

## [8.19.2] - 2026-04-30

### Kaldırıldı — `superpowers` plugin curated set'ten çıkarıldı

8.19.1 modern permission-decision UI ile brainstorming engelinin "kırmızı Error" görünümünü kapattı; ama temel sorun devam ediyordu: `superpowers` plugin install'lı oldukça `using-superpowers` SKILL.md her session'da otomatik yüklenip "ABSOLUTELY MUST invoke brainstorming" instruction'ını modele enjekte ediyor → her session'ın ilk turn'ünde brainstorming çağrısı denenip block ediliyor → noise.

Repo taraması: MCL'in superpowers'a **fonksiyonel kod-path bağımlılığı yok**. 11 skill dosyasındaki "tier-A ambient" satırı pure documentation; hiçbir kod akışı bu satıra göre branch yapmıyor. `superpowers:code-reviewer` Phase 4.5 code-review prefix listesinin 3 alternatifinden biriydi (`pr-review-toolkit`, `code-review` zaten mevcut). Plugin'i kaldırmak hiçbir MCL pipeline adımını kırmaz.

#### Değişen dosyalar
- **`install-claude-plugins.sh`** — `obra/superpowers-marketplace` ve `superpowers@superpowers-marketplace` install satırları kaldırıldı. Curated set artık 5 plugin: feature-dev, frontend-design, code-simplifier, hookify, security-guidance, commit-commands, pr-review-toolkit, code-review, ralph-loop + LSP'ler.
- **`hooks/lib/mcl-plugin-gate.sh:90-93`** — `mcl_plugin_gate_required_plugins()` listesinden `superpowers` çıkarıldı. Artık tek tier-A required: `security-guidance`. Plugin gate notice eski "superpowers eksik" uyarısı vermez.
- **`hooks/mcl-pre-tool.sh:204-242`** — superpowers:brainstorming hook block tamamen silindi (kaynak kesildi → using-superpowers SKILL.md hiç yüklenmiyor → brainstorming çağrısı modelden hiç gelmiyor → hook engellemeye gerek yok). TodoWrite block mesajındaki "superpowers:brainstorming interference" ifadesi nötr "parallel workflow" olarak yeniden yazıldı.
- **`hooks/lib/mcl-dispatch-audit.sh:60`** — Phase 4.5 code-review prefix listesinden `superpowers:code-reviewer` çıkarıldı. Geçerli prefix'ler: `pr-review-toolkit`, `code-review`.
- **11 phase skill dosyası** — Boilerplate satırı `**superpowers (tier-A, ambient):** active throughout this phase — no explicit dispatch point...` silindi. Etkilenen dosyalar: `phase1-rules.md`, `phase2-spec.md`, `phase3-verify.md`, `phase4-execute.md`, `phase4-tdd.md`, `phase4-5-risk-review.md`, `phase4-6-impact-review.md`, `phase4a-ui-build.md`, `phase4b-ui-review.md`, `phase4c-backend.md`, `phase5-review.md`. Bu satır pure documentation idi; hiçbir kod akışı bu satıra göre branch yapmıyordu.
- **`skills/my-claude-lang/plugin-orchestration.md`** — "The curated set" tablosundan `superpowers` row'u silindi. "Phase dispatch map" tablosundan `superpowers (tier-A)` ambient sütun değerleri temizlendi. "Phase 4.5 manifest" tablosundan `superpowers:code-reviewer` prefix kaldırıldı. Plugin install hint listesinden ve "ambient by design" kuralından çıkarıldı.
- **`skills/my-claude-lang/plugin-suggestions.md` + `plugin-gate.md`** — Curated set listesinden `superpowers` çıkarıldı.
- **`skills/my-claude-lang.md`** — "Curated orchestration plugins" + "MCL silently auto-dispatches" listelerinden `superpowers` çıkarıldı; "always-on ambient methodology layer" paragrafı silindi.
- **`hooks/mcl-activate.sh` STATIC_CONTEXT** — `<mcl_constraint name="superpowers-scope">` → `name="hook-enforcement-scope"` olarak yeniden adlandırıldı; brainstorming block bahsi düşürüldü. "SUB-AGENT PHASE DISCIPLINE" paragrafı superpowers örneğini kaldırdı. Phase 4.5 dispatch audit "superpowers:code-reviewer" alternatifini düşürdü.
- **`FEATURES.md`** — Hook Dominance tablo + bullet listesinden `Skill: superpowers:brainstorming` satırı silindi. Curated plugin listesi 4 plugin.
- **`CLAUDE.md`** — Devtime Plan Critique parantezindeki `superpowers:code-reviewer` örneği `pr-review-toolkit:code-reviewer` ile değiştirildi.

#### Korunan
- 7. legacy `decision:block` site (state.json direct write) — security boundary, kasıtlı.
- TodoWrite Phase 1-3 block — MCL phase state korunuyor (mesaj nötr hale getirildi).
- Task → Phase 4.5/4.6/5 dispatch block — sub-agent discipline.

Tests: 59/0/2 unit, 65/0/0 e2e — sıfır regresyon.

## [8.19.1] - 2026-04-30

### Düzeltildi — Hook output UX: legacy `decision:block` → modern `permissionDecision:deny`

Real session bulgusu: superpowers:brainstorming Skill çağrısı kullanıcıya **kırmızı `Error: blocking` bloğu** olarak render ediliyordu. MCL'in doğru kararı (suppression — Phase 1-3 zaten brainstorming rolünü oynuyor) hata gibi görünüyor → kullanıcı paniğe düşüyor.

Kök sebep: `mcl-pre-tool.sh` 7 site'ta legacy `{"decision":"block","reason":"..."}` JSON şeması kullanıyordu; Claude Code bu eski formu "blocking error" olarak etiketleyip kırmızı render ediyor. Modern `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}` şeması permission-decision UI'ı kullanır — daha sakin.

#### Doğrulama: Claude Code docs'a göre 3 alternatif değerlendirildi
- **Pre-emptive disable** (SessionStart skill unregister): ❌ MÜMKÜN DEĞİL — Claude Code'da skill registration aşamasını bypass edebilen hook event yok.
- **`permissionDecision:allow + updatedInput=null`**: ❌ Skill tool null input ile başka error path'e düşer.
- **Modern output schema**: ✅ TEK GEÇERLİ YOL.

#### Modernize edilen 6 site (`hooks/mcl-pre-tool.sh`)
1. **Line 224**: `superpowers:brainstorming` Skill block (en sık tetiklenen — kullanıcı şikâyetinin kaynağı).
2. **Line 252**: TodoWrite Phase 1-3 block (model brainstorming-style todo kullanırsa).
3. **Line 295**: Task → Phase 4.5/4.6/5 sub-agent dispatch block.
4. **Line 448**: Plan critique intent validator "no" verdict (devtime).
5. **Line 460**: Plan critique intent validator missing (devtime).
6. **Line 494**: ExitPlanMode without plan_critique_done (devtime).

#### Kasıtlı dokunulmadı
- **Line 530**: Direct `state.json` write block — security boundary; kırmızı alarmist render bilinçli (kullanıcı bunun arızi engelleme değil ciddi uyarı olduğunu görmeli).

#### Korunan davranış
- Tool yine block edilir (functional değişiklik yok).
- Mesaj metni dokunulmadı (model davranış prior'ları korunur — rule capture, retry önleme).
- Audit log entries (`block-skill`, `block-todowrite`, `block-task-phase-dispatch`, `plan-critique-block`) değişmedi.

Tests: 59/0/2 unit, 65/0/0 e2e — regresyonsuz.

## [8.19.0] - 2026-04-30

### Eklendi — Hook-level State Population Fallback + Severity-Aware Phase 4.5 + Test Layer Coverage

Üç bağımsız iyileştirme tek sürümde. Üçü de gerçek-kullanım telemetrisinden (`/Users/umitduman/adm_pnl` 264-satır audit'i) ortaya çıkan bulgulara cevap.

#### Hook-level state population fallback

**Sorun:** 8.10.0-8.17.0 boyunca `phase1_intent / constraints / stack_declared / ops / perf / ui_sub_phase` skill prose Bash'e bağımlıydı. Real session telemetri'sinde `set | skill-prose=0`, `deny-write | bash=0` (skill prose Bash sıfır deneme — model davranışı). 8.16.0 LOW soft fail guard durumu görünür kıldı ama state hâlâ null → Phase 6 (c) keyword extract silently skip.

**Çözüm:** `hooks/lib/mcl-phase-detect.py` (yeni) — Engineering Brief parse (English-canonical, structured `Task: / Requirements: / Context:` field'ları) + `<mcl_state_emit kind="...">PAYLOAD</mcl_state_emit>` marker scanner. mcl-stop.sh her Stop turn'ünde idempotent çalıştırır:
- Brief'ten `phase1_intent`, `phase1_constraints` extract; Context body'sinden stack tag inference (16 keyword pattern → `react-frontend / python / db-postgres / orm-prisma / ...`).
- Marker'dan `phase1_ops`, `phase1_perf` (JSON object), `ui_sub_phase=UI_REVIEW`.
- Idempotent: state.json'da zaten dolu olan field overwrite edilmez (skill prose Bash veya önceki turn'ün fallback'i tarafından yazılmış olabilir).
- Audit: `phase1_state_populated | mcl-stop | source=brief-parse` veya `source=marker-emit` → fallback path explicit traceable.

Skill prose Bash hâlâ desteklenir; marker-emit alternative section'ları `phase1-7-precision-audit.md` ve `phase4a-ui-build.md` içinde dokümante edilir. Dual path: Bash preferred (caller=skill-prose, immediate write), marker fallback (caller=mcl-stop, next-Stop write).

#### Severity-aware Phase 4.5 skip enforcement + askuq-path gates fall-through

**Sorun:** Phase 4.5 dialog mevcut 3 seçenek (apply / skip / make-rule) HIGH security finding'i bile skip etmeye izin veriyordu. Ayrıca real session'da `phase-review-pending` audit count=0 (greenfield), çünkü askuq=true path'i 5 START gate'i tamamen atlatıyordu (mcl-stop.sh:518-525 design intent — ama HIGH/MEDIUM finding senaryosunda yetersiz koruma).

**Çözüm:**
- `phase4-5-risk-review.md` severity-aware option matrix:
  - **HIGH** (any): `apply-fix / override` — skip kaldırıldı.
  - **MEDIUM Security/DB**: `apply-fix / override`.
  - **MEDIUM other categories** (UI/Perf/Ops/Code-Review/Simplify/Test): mevcut 3 seçenek.
  - **LOW**: mevcut 3 seçenek.
- Override path: ikinci AskUserQuestion ile reason zorunlu. Marker `<mcl_state_emit kind="phase4-5-override">{...}</mcl_state_emit>` (preferred) veya Bash `mcl_audit_log phase4_5_override`. Reason Phase 5 raporuna ve audit'e akar.
- `mcl-stop.sh:625-1136` refactor: askuq=true ve code_written/pending iki path da artık 5 START gate'i çağırır (idempotent via `phase4_5_*_scan_done` flags). Standart Phase 4.5 reminder block'u SADECE askuq=false path'inde fire eder (askuq=true zaten dialog içinde — hostile UX değil).
- `hooks/lib/mcl-phase6.py` Phase 6 (a) `check_severity_skip_violations`: dialog'da `action=skip` + HIGH veya MEDIUM-sec/db finding + matching `phase4_5_override` event yoksa LOW soft fail (`P6-A-severity-skip-without-override`).

#### Test layer coverage + TST-T04 load-test rule

**Sorun:** Phase 1.7 TST dim test policy soruyor ama actual coverage gap (unit configured, integration/E2E/load eksik) Phase 4.5 dialog'da finding olarak inmiyor. Production-bound backend'lerde load testi yokluğu hiç yakalanmıyor.

**Çözüm:** `hooks/lib/mcl-test-coverage.py` (yeni) — 8 manifest'e bakar (`package.json / requirements.txt / Gemfile / composer.json / pom.xml / go.mod / Cargo.toml / build.gradle`) + 4 framework kategorisi:
- **TST-T01 HIGH**: source code mevcut + unit framework yok → tüm test eksik.
- **TST-T02 MEDIUM**: integration framework yok (supertest/testcontainers/pytest-asyncio).
- **TST-T03 MEDIUM**: `ui_flow_active=true` + e2e yok (playwright/cypress).
- **TST-T04 MEDIUM (yeni)**: backend stack tag (`python/java/go/...`) + `phase1_ops.deployment_target ∈ {prod, public, multi-tenant, scale, cloud}` + load tool yok (k6/locust/artillery/jmeter).

mcl-stop.sh Phase 4.5 lens orchestration'a entegre: 5 mevcut gate (security/db/ui/ops/perf) yanına 6. lens olarak test-coverage. Findings sequential dialog'a `[Test]` etiketli `MEDIUM` finding olarak inject edilir; severity-aware option matrix kategoriye göre uygulanır (TST-T0X → "MEDIUM other category" → apply/skip/make-rule).

#### Trace.log expansion (kısmi)

8.10-8.17 dersi: trace.log gerçek session'da çok dar. `mcl_trace_append spec_emit / ui_build_done / backend_start` eklendi. Phase 5 Process Trace section'ı genişler.

### Yeni dosyalar
- `hooks/lib/mcl-phase-detect.py` — brief + marker parser
- `hooks/lib/mcl-test-coverage.py` — manifest scan + finding rules
- `tests/cases/test-phase-detect.sh` — 21 unit assertion
- `tests/cases/test-test-coverage.sh` — 11 unit assertion
- `tests/cases/e2e-full-pipeline.sh` Phase 5 + 5b — gerçek end-to-end state-pop + idempotency

### Bilinen sınırlar
- **Brief stack inference heuristic** — keyword scan; brief'te stack açıkça geçmezse miss. Fallback olarak `mcl-stack-detect.sh` çalıştırılır. İkisi de boş → 8.16.0 LOW soft fail tetiklenir.
- **`<mcl_state_emit>` model davranışına bağlı** — Bash'ten daha az fragile (tool invocation değil, text emission), ama yine atlanabilir. Brief-parse `phase1_intent/constraints` için neredeyse-deterministik (brief mandatory); marker `phase1_ops/perf/ui_sub_phase` için yarı-fragile.
- **Severity enforcement skill-prose-only** — Phase 6 (a) audit assertion ile detect (LOW soft fail), real-time block YOK. Override reason yazmadan skip edilirse audit'e yansır ama dialog tamamlanmış olur. Hard hook-enforce 8.20+.
- **askuq=true L3 gates** — security gate ~11s. Greenfield her Stop'ta tekrar çalışır mı? Hayır — `phase4_5_security_scan_done=true` flag idempotent; ilk fire'dan sonra skip. Sadece ilk askuq=true turn'ünde 11s overhead.
- **TST-T04 deployment_target conditional** — `phase1_ops.deployment_target` null'sa rule fire etmez (false-negative). 8.19.0 hook-fallback ile çoğunlukla dolu olacak ama her senaryoda değil.
- **`mcl-test-coverage.py` heuristic** — manifest var ama framework yoksa miss eder. AST-level test file scan 8.20+.

Tests: 59/0/2 unit (önce 27 → +32: phase-detect 21, test-coverage 11). E2E 65/0/0 (önce 54 → +11: Phase 5 + 5b).

## [8.18.1] - 2026-04-30

### Düzeltildi — Phase 4a path redirect (UI-BUILD LOCK preempt)

Phase 4a (BUILD_UI) sırasında model "API mock" mental model'iyle `src/api/mock.ts` gibi backend-paterni yollara yazmaya çalışıyordu. PreToolUse hook bu yolları reddediyor (`src/api/`, `src/services/`, `src/lib/db/`, vb.) ve developer turn kaybediyordu. Hook davranışı doğru — eksik olan, model'in ilk yazımda doğru yolu seçmesini sağlayacak proaktif yönlendirmeydi.

- **`skills/my-claude-lang/phase4a-ui-build.md`** — "Path Discipline" altına 7-satır redirect tablosu eklendi (X→Y eşleştirme): `src/api/<name>.ts` → `src/mocks/<name>.mock.ts`, `src/services/<name>.ts` → `src/components/__fixtures__/<name>.fixture.ts`, `pages/api/...` → inline constant, vb. Model ana skill'i her Phase 4a turn'ünde okuyor; sub-skill'e (fixtures.md) inmesine gerek kalmıyor.
- **`skills/my-claude-lang/phase4c-backend.md`** — "Remove Dev-Only Bits" Delete listesine `src/mocks/` cleanup bullet'ı eklendi. Grep-verified (3 alias varyantı: `src/mocks/`, `../mocks/`, `@/mocks/`); test/spec dosyalarındaki referanslar korunur. Boş ise `rm -rf src/mocks/` Phase 4 Execution Plan kuralı altında.
- **`skills/my-claude-lang/phase4a-ui-build/fixtures.md`** — Trailing prohibition bullet'ı ana skill'deki tabloya pointer'a dönüştürüldü (drift önleme; tek hakikat kaynağı).

Tests: 27/0/2 unit, 54/0/0 e2e — regresyonsuz.

## [8.17.0] - 2026-04-30

### Düzeltildi — Skill prose state plumbing nihayet gerçekten çalışıyor

8.10.0'dan beri eklenen skill prose Bash plumbing'i (`phase1_intent`, `phase1_constraints`, `phase1_stack_declared`, `phase1_ops`, `phase1_perf`, `ui_sub_phase=UI_REVIEW` transition) **production'da hiç çalışmamış**. Sebep: `mcl_state_set` auth-check `$0`'a bakıyor; skill prose `bash -c '...'` invocation'ında `$0=bash` → whitelist match etmiyor → `deny-write` audit + write reject. `mcl_audit_log` auth-check'i bypass ettiği için audit event'leri başarılı görünüyordu (Phase 6 (a) yanıltıcı clean rapor verdi) ama `state.json` field'ları null kalıyordu. E2E test bu davranışı uçtan uca kanıtladı (`tests/cases/e2e-full-pipeline.sh:1.B`).

#### MCL_SKILL_TOKEN auth path
- **`hooks/lib/mcl-state.sh`** — `_mcl_state_auth_check` extension: hook entry whitelist (existing) + skill-token path (new). Hem `MCL_SKILL_TOKEN` env var hem `$MCL_STATE_DIR/skill-token` dosyası varsa ve içerikleri eşleşiyorsa write authorize edilir, audit'e `caller=skill-prose` yazılır. Yeni helper `mcl_state_skill_token_rotate` (32-hex token, `openssl rand` veya `/dev/urandom` fallback, mode 0600).
- **`hooks/mcl-activate.sh`** — Her UserPromptSubmit'te `mcl_state_skill_token_rotate` çağrısı. Önceki turn'ün token'ı overwrite edilir; replay attack window tek turn ile sınırlı.
- **`mcl_state_set` audit caller field** — `MCL_AUTH_CALLER` env var ile thread edilir. Hook entry path → `caller=mcl-stop.sh` vb.; skill-token path → `caller=skill-prose`. Audit log forensik analizi için provenance net.

#### 4 skill prose dosyası token-aware Bash prefix
Her skill prose Bash bloğunun başında:
```bash
[ -n "${MCL_STATE_DIR:-}" ] && [ -f "$MCL_STATE_DIR/skill-token" ] \
  && export MCL_SKILL_TOKEN="$(cat "$MCL_STATE_DIR/skill-token")"
```
- `skills/my-claude-lang/phase1-rules.md` (Phase 1 → 1.7 handoff)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (Phase 1.7 → 1.5 audit emission)
- `skills/my-claude-lang/phase4a-ui-build.md` (UI_REVIEW transition)
- `skills/my-claude-lang/phase5-review.md` — değişmedi (yalnızca `mcl_audit_log` çağrısı, auth-check'siz path)

#### Phase 4.5 Dialog Batch-Action
- **`skills/my-claude-lang/phase4-5-risk-review.md`** — Risk count ≥ 3 ise sequential dialog ÖNCESİ tek `AskUserQuestion` (multiSelect false, 3 seçenek): "Hepsi kabul / Hepsi reddet / Tek tek bak". Accept-all path'inde tüm risk'ler tek turn'de auto-fix + summary; reject-all path'inde dismiss audit; one-by-one path'inde mevcut sequential dialog. Eşik 3 (1-2 risk için batching overhead mantıksız). State field: `phase4_5_batch_decision` (null|accept_all|reject_all|one_by_one).
- **`hooks/lib/mcl-state.sh`** — Default schema'ya `phase4_5_batch_decision: null` eklendi.

#### Side-effect bug fix (8.7.1'den beri açık)
- **`hooks/mcl-stop.sh:532`** — `${_PR_PHASE}` undefined variable referansı `set -u` altında script'i öldürüyordu. Sonuç: Phase 4.5 START enforcement bloğunda `phase_review_state="pending"` atandıktan hemen sonra hata → 5 sequential gate (security/db/ui/ops/perf) **production'da hiç çalışmamış**. Tek karakter düzeltme: `_PR_PHASE` → `_PR_ACTIVE_PHASE`. E2E `tests/cases/e2e-full-pipeline.sh:14.C` ile yakalandı.

#### E2E test infrastructure
- **`tests/cases/e2e-full-pipeline.sh`** — Hibrit e2e: bash test + manual checklist. Mevcut coverage: Phase 1 (3 test, auth-check baseline + token path inversion + rotation), Phase 14 (3 test, sticky-pause + 5 gate baseline + sequential ordering), Phase 25 (1 test, pause-on-error trigger via stub helper). 54/0/0 pass.
- **`tests/e2e/manual-checklist.md`** — 33 satırlık coverage tablosu, model-bağımlı adımlar (AskUserQuestion turn'leri, npm-driven dev server, gerçek Claude session) için.

### Bilinen sınırlar
- Skill-token mekanizması cryptographic değil — local plumbing trust boundary (accidental misuse engelleme amaçlı). Token dosyası mode 0600, session-scoped, her UserPromptSubmit rotate. Yeterli güvenlik MCL'in lokal yürütme modeli için.
- Batch-action reverse path 8.18.0'a kadar model-behavioral. Geliştirici batched seçimde hata yapıp sonraki turn'de düzeltme istemezse hata sessiz kalır.
- Phase 4.5 batch-action `mcl-stop.sh`'a hook-level shortcut entegre etmedi — skill prose state'i set ediyor ama hook tarafı şu an sequential path ile aynı yolu izliyor. Hook integration 8.18.0+.
- E2E coverage manual-checklist'te 33 satırın 7'si ✅. Geri kalanı sonraki turn'lerde adım adım eklenecek.

## [8.16.0] - 2026-04-30

### Eklendi — GATE Batching + Hook State-Population Guard

8.15.0 skill prose sprint state plumbing'i model davranışına bıraktı: 4 ayrı transition'da (Phase 1 handoff, Phase 1.7 audit, Phase 4a→4b, Phase 5→5.5) model `mcl_state_set` + `mcl_audit_log` Bash çağırmazsa state set edilmez ve hook seviyesinde detect yoktu. Ek olarak 8.15.0'ın ops (DEP/MON/TST/DOC) + perf (PERF) dimension'ları greenfield'da da fired olduğu için Phase 1.7 turn sayısı 12 → 14-16'ya çıkmıştı. 8.16.0 bu iki yan etkiyi kapatır + GATE patlamasını yarıya indirir.

#### GATE Batching (Phase 1.7 turn sayısı yarıya iner)
- **`skills/my-claude-lang/phase1-7-precision-audit.md`** — Aynı kategoride birden fazla GATE dimension fire ettiğinde tek `AskUserQuestion` (`multiSelect: true`) ile sorulur. Kategoriler: Security / Database / UI / Operations / Performance. Maksimum 5 turn (mevcut 14-16 turn yerine).
  - Tek-dimension fire'lar yine tek-soru formuyla sorulur — batching sadece ≥ 2 dimension aynı kategoride fire ettiğinde uygulanır.
  - **Reverse path (model-behavioral, 8.17.0'a kadar):** Geliştirici sonraki turn'de batched dimension'a explicit feedback verirse model batched answer'ı discard edip tek-soru formuyla yeniden sorar. Hook-level rollback yok; structured batch-revise feature 8.17.0'da.

#### Hook State-Population Guard (skill prose Bash unutulursa LOW soft fail)
- **`hooks/lib/mcl-phase6.py`** — Phase 6 (a) audit-trail check'e 4 yeni LOW soft fail event eklendi: `phase1_state_populated`, `phase1_ops_populated`, `phase1_perf_populated`, `ui_sub_phase_set`. HIGH değil — skill prose model behavior; hook execution'ı block etmez. Eksik event = developer'a görünür uyarı, downstream'in default state ile çalıştığını ortaya çıkarır.

#### `mcl_state_set` String Auto-Coerce Dokümantasyonu
- **`skills/my-claude-lang/phase4a-ui-build.md`** — `mcl_state_set` Python `json.loads` fallback davranışı explicit dokümante edildi: bare scalar (`UI_REVIEW`, `BACKEND`) string olarak auto-quote edilir; integer (`3`, `42`), JSON literal (`true`, `false`, `null`) ve JSON object/array parsed type olarak korunur. Mevcut state'teki integer field'lar (`current_phase`, `schema_version`, `last_update`, `phase4_5_high_baseline.*`) auto-coerce davranışından etkilenmez — JSON int olarak parse edilir, int kalır. 8.15.0'daki "outer-single + inner-double" quoting nüansı artık opsiyonel (kod değişmedi, sadece kullanım sadeleşti).

#### Stack Tag Validation
- **`hooks/lib/mcl-state.sh`** — `_mcl_validate_stack_tags` helper. `phase1_stack_declared` CSV'sindeki her token kanonik stack-tag set'ine karşı validate edilir. Bilinmeyen token (`react-frontnd` typo, `db-postgresql` non-canonical alias) stderr'e WARN üretir + `stack-tag-unknown` audit kaydı atılır. Set write block edilmez — uyarı advisory.
- **`skills/my-claude-lang/phase1-rules.md`** — handoff Bash'i `_mcl_validate_stack_tags` çağrısı içerir.

#### Audit emissions (skill prose, since 8.16.0)
- `phase1-rules.md` — `mcl_audit_log "phase1_state_populated" ...` handoff sonrası
- `phase1-7-precision-audit.md` — `mcl_audit_log "phase1_ops_populated" ...` + `phase1_perf_populated`
- `phase4a-ui-build.md` — `mcl_audit_log "ui_sub_phase_set" ...` UI_REVIEW transition sonrası

### Bilinen sınırlar
- GATE batching reverse path 8.17.0'a kadar model-behavioral. Geliştirici batched seçimde hata yapıp sonraki turn'de düzeltme istemezse hata sessiz kalır.
- State-population events LOW soft fail; HIGH'a yükseltme 8.18.0'da değerlendirilir (false-positive risk: hook geç başlayan project'lerde).
- Known stack tag listesi `mcl-state.sh` içinde statik. Yeni stack eklendiğinde manual güncelleme.

## [8.15.0] - 2026-04-30

### Eklendi — Skill Prose Sprint (rule freshening)

8.10.0-8.14.0 sürümleri state plumbing'i ekledi (`phase4_5_*_scan_done`, `phase4_5_high_baseline.{security,db,ui,ops,perf}`, `phase1_ops`, `phase1_perf`, `phase1_intent`, `phase1_constraints`, `paused_on_error`, `dev_server`, `phase6_double_check_done`); hook ve orchestrator tarafı bu field'ları **okuyor** ama skill prose'lar **set etmiyordu**. Real-use simülasyonu sonucu (54 turn senaryo) tespit edilen 4 blocker'ın hepsi bu yüzdendi:
- `phase1_*` state field'ları skill prose'unda set edilmiyor → Phase 6 (c) promise-vs-delivery hep LOW skip; Phase 1.7 ops/perf dimension'ları audit etmiyor.
- `ui_sub_phase=UI_REVIEW` transition explicit değil → 8.12.0 dev server otomatik başlamıyor; design loop tetiklenmiyor.
- `phase5-verify` audit event emit edilmiyor → Phase 6 (a) audit-trail transcript fallback'a düşüyor.
- Greenfield'da `mcl-stack-detect.sh` boş döner → Phase 1.7 stack add-on'ları (DB/UI/ops/perf) hiç tetiklenmez.

8.15.0 **rule freshening** sürümüdür. Yeni kod yok, yeni feature yok. Mevcut state plumbing'in pratikte çalışmasını garanti altına alan toplu skill prose update'i — 6 skill dosyası + 1 hook regex extension'ı.

#### Skill prose updates (6 dosya)

- **`skills/my-claude-lang/phase1-rules.md`** — Phase 1 → 1.7 handoff section eklendi. Phase 1 summary onayından sonra skill 3 `mcl_state_set` Bash çağrısı yapar:
  - `mcl_state_set phase1_intent "<intent>"` — Phase 6 (c) için
  - `mcl_state_set phase1_constraints "<constraints>"` — Phase 6 (c) için
  - `mcl_state_set phase1_stack_declared "<csv>"` — `mcl-stack-detect.sh` greenfield fallback
- **`skills/my-claude-lang/phase1-7-precision-audit.md`** — (a) "DB Design Dimensions" sonrası 5 yeni dimension eklendi: 20. Deployment Strategy (DEP), 21. Observability Tier (MON), 22. Test Policy (TST), 23. Documentation Level (DOC), 24. Performance Budget (PERF). Her birinin trigger condition'ı 8.13.0/8.14.0 ile uyumlu. (b) Phase 1.7 → 1.5 handoff Bash: `mcl_state_set phase1_ops '{deployment_target,observability_tier,test_policy,doc_level}'` + `mcl_state_set phase1_perf '{budget_tier}'`.
- **`skills/my-claude-lang/phase4a-ui-build.md`** — Phase 4a → 4b transition section. UI dosyaları + `npm install` tamamlanınca `mcl_state_set ui_sub_phase '"UI_REVIEW"'` (JSON-quoted string). Bu olmadan `mcl-stop.sh` 8.12.0 dev_server auto-start tetiklenmez. Quoting nüansı CHANGELOG + skill prose'da explicit.
- **`skills/my-claude-lang/phase5-review.md`** — Phase 5 → 5.5 audit emission. 3 section (Spec Compliance, MUST TEST, Process Trace) tamamlandıktan sonra `mcl_audit_log "phase5-verify" "phase5" "report-emitted"`. Phase 6 (a) için deterministik signal — transcript header fallback secondary'ye düştü.
- **`skills/my-claude-lang/phase5-5-localize-report.md`** — 14 dilden lokalize Verification Report header tablosu eklendi. Model 14 dilden seçer; 14-set dışı ise EN fallback. Phase 6 transcript fallback regex'i ile birebir eşleşir.
- **`skills/my-claude-lang/all-mcl.md`** — STEP-12 (Phase 1 summary), STEP-40a (Phase 4a UI build), STEP-50 (Phase 5 spec coverage), STEP-64 (Phase 1.7 precision audit) description satırlarına `(since 8.15.0)` referansları eklendi. Yeni STEP yok.

#### Hook regex extension (1 dosya)
- **`hooks/mcl-stop.sh:1769`** — Phase 6 trigger transcript fallback regex'i 2 dilden (TR + EN) 14 dile genişletildi:
  - EN: Verification Report
  - TR: Doğrulama Raporu
  - FR: Rapport de Vérification
  - DE: Verifizierungsbericht
  - ES: Informe de Verificación
  - JA: 検証レポート
  - KO: 검증 보고서
  - ZH: 验证报告
  - AR: تقرير التحقق
  - HE: דוח אימות
  - HI: सत्यापन रिपोर्ट
  - ID: Laporan Verifikasi
  - PT: Relatório de Verificação
  - RU: Отчёт о проверке

  Çeviri kalitesi 12 fallback dil için heuristic; native speaker review 8.15.x'te. Birebir audit event (`phase5-verify`) skill prose'da emit edildiğinden bu fallback artık yalnızca eski projeler için.

#### State plumbing (yeni state field yok)
8.15.0 mevcut state field'larının pratikte çalışmasını sağlar. Yeni schema bump yok. Yeni keyword yok. Yeni env var yok.

#### Karar matrisi (kabul edilen varsayılanlar)
- Çeviri kalitesi 14 dil için heuristic; native speaker review 8.15.x
- Skill prose vs hook enforcement: Bash talimatları model-behavioral; hook seviyesinde detect 8.16.0+
- `phase1_stack_declared` parsing: comma-separated string; JSON array conversion 8.16.x
- JSON quoting (`mcl_state_set ui_sub_phase '"UI_REVIEW"'`): outer single-quote shell escape, inner double-quote JSON string

### Test sonuçları
- T1 phase1-rules.md handoff section eklendi PASS
- T2 phase1-7 5 yeni dimension + state-set Bash eklendi (3 occurrences of `8.15.0` in skill) PASS
- T3 phase4a-ui-build.md UI_REVIEW transition section eklendi PASS
- T4 phase5-review.md audit emission section eklendi PASS
- T5 phase5-5-localize-report.md 14-dil header tablosu eklendi (2 occurrences) PASS
- T6 all-mcl.md STEP-12/40a/50/64 description footnotes eklendi (4 occurrences) PASS
- T7 mcl-stop.sh:1769 regex 14 dile genişletildi PASS
- T8 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `skills/my-claude-lang/phase1-rules.md` (Phase 1 → 1.7 handoff)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (5 yeni dimension + state-set)
- `skills/my-claude-lang/phase4a-ui-build.md` (UI_REVIEW transition)
- `skills/my-claude-lang/phase5-review.md` (phase5-verify audit)
- `skills/my-claude-lang/phase5-5-localize-report.md` (14-dil header)
- `skills/my-claude-lang/all-mcl.md` (STEP description footnotes)
- `hooks/mcl-stop.sh` (Phase 6 trigger 14-dil regex)
- `VERSION` (8.14.0 → 8.15.0)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.15.x patch'lerine ertelendi)

- **README.md / README.tr.md güncellenmedi** — 8.15.0'da yeni feature / keyword / env var / state field yok; CLAUDE.md release rule'u "yeni özellik varsa README" diyor — bu sürümde hiçbiri yok. CHANGELOG yeterli.
- **Çeviri kalitesi 14 dil**: 12 fallback dil için header çevirileri makine-translation kalitesinde; native speaker review 8.15.x.
- **Skill prose model-behavioral**: Bash talimatları model'in çağırmasına bağlı. Model unutursa state set edilmez. Hook seviyesinde detect mekanizması yok (8.10.0 NL-ack ile aynı sınır). 8.16.0+ Phase 6 (a) "phase1_intent state'te yoksa block" eklenebilir.
- **`phase1_stack_declared` parse format**: comma-separated string; orchestrator'lar `set(t for t in tags.split(','))` ile parse eder. JSON array conversion 8.16.x.
- **JSON quoting nüansı**: `mcl_state_set ui_sub_phase '"UI_REVIEW"'` — outer single-quote shell escape, inner double-quote JSON string. Skill prose'da explicit example var; yanlış quoting `mcl-state` validation rejection üretir.
- **Real-use turn sayısı azalmaz**: 8.15.0 UX değil, rule freshening — Phase 1.7 GATE patlaması (real-use rapor #1) hâlâ var. UX iyileştirmesi 8.16.0+.

## [8.14.0] - 2026-04-30

### Eklendi — Performance Budget (İŞ 5, son iş)

8.7-8.13 product / DB / UI / ops disiplini tamamlandı; **runtime performans** boştu — 4MB JS bundle production'a gidebilir, LCP 6 saniye, hero image 2MB PNG. 8.14.0 üç performans ekseninde FE-only enforcement ekler (8.9.0/8.13.0 mirror 3-tier).

#### Yeni dosyalar
- **`hooks/lib/mcl-perf-rules.py`** — 3 rule pack, 11 rule, `category=perf-*` field:
  - **Bundle** (4): PRF-B01 over-budget-critical (>2× budget HIGH), B02 over-budget (100-200% MEDIUM), B03 no-build-output (LOW advisory), B04 large-chunk (>50KB tek chunk LOW).
  - **CWV** (4): PRF-C01 LCP-poor (>4s HIGH), C02 LCP-needs-improvement (2.5-4s MEDIUM), C03 CLS-poor (>0.25 MEDIUM), C04 TBT-poor (>600ms MEDIUM).
  - **Image** (3): PRF-I01 image-huge (>500KB HIGH), I02 image-large (100-500KB MEDIUM), I03 png-no-webp-fallback (LOW).
- **`hooks/lib/mcl-perf-bundle.sh`** — build output walker: `dist/`, `build/`, `.next/static/chunks/`, `out/` taranır; `*.js` dosyaları `gzip.compress` ile aggregate edilir. **Build invoke etmez** — kullanıcı `npm run build` çalıştırmamışsa PRF-B03 advisory.
- **`hooks/lib/mcl-perf-lighthouse.sh`** — `MCL_UI_URL` env reuse (8.9.0 axe ile aynı env — kullanıcı tek URL set eder, hem axe hem lighthouse çalışır). Yoksa lokalize advisory; varsa `npx lighthouse --output=json --only-categories=performance`; LCP/CLS/TBT/TTI/FCP extract. `--json` flag orchestrator dispatch için.
- **`hooks/lib/mcl-perf-scan.py`** — orchestrator: bundle delegate + image walk (5 standart asset dir) + (optional) lighthouse delegate; lokalize markdown render (TR/EN).

#### State şeması
- `phase4_5_perf_scan_done: false` — idempotency flag
- `phase4_5_high_baseline.perf: 0` — Phase 6 (b) regression baseline (8.11.0/8.13.0 schema extend)
- `phase1_perf: {budget_tier}` — Phase 1.7 dimension state

#### Hook entegrasyonu
- **`hooks/mcl-stop.sh`** — Ops gate sonrası: Phase 4.5 START Perf gate. Sıra: sticky-pause → security → db → ui → ops → **perf** → standart Phase 4.5 reminder → Phase 6 gate. HIGH ≥ 1 → state `pending`'de + `decision:block` (kategori listesi); HIGH = 0 → done=true + baseline.perf=0; MEDIUM listesi standart reminder reason'a `[Perf-<sub>]` etiketli inject. **Lighthouse L3'te çalışmaz** (60s overhead); sadece `/mcl-perf-report` keyword'ünde.
- **`hooks/mcl-activate.sh`** — `/mcl-perf-report` + `/mcl-perf-lighthouse` keyword block'ları.

#### Konfigürasyon
- `$MCL_STATE_DIR/perf-config.json` (8.5.0 isolation):
  ```json
  {"perf": {"bundle_budget_kb": 200, "bundle_critical_multiplier": 2,
            "image_high_kb": 500, "image_medium_kb": 100,
            "lcp_high_ms": 4000, "lcp_medium_ms": 2500,
            "cls_high": 0.25, "tbt_high_ms": 600}}
  ```
- Defaults: bundle 200KB JS gzip, image 100/500KB, LCP 2.5/4s, CLS 0.25, TBT 600ms.

#### Karar matrisi (kabul edilen + kullanıcı değişikliği)
- Bundle: **walker-only** (build invoke etme)
- CWV env: **`MCL_UI_URL` reuse** (8.9.0 axe ile shared — kullanıcı isteği)
- Image scope: **5 standart dir** (`public`, `static`, `assets`, `src/assets`, `app/static`)
- Bundle threshold: **200KB JS gzip**, configurable
- Image format: **WebP only** suggestion (AVIF 8.14.x)
- Lighthouse: **desktop profile** + 90s timeout
- Phase 1 keyword (fast/scale/mobile/low-latency): **GATE**
- Build output: **4 standart dir** (dist / build / .next/static/chunks / out)

#### Trigger condition
**FE stack-tag tespit edildiğinde** (`react-frontend|vue-frontend|svelte-frontend|html-static`). Backend-only / lib / CLI / data-pipeline projelerinde tüm perf pipeline skip; audit `perf-scan-skipped reason=no-fe-stack-tag`.

#### Audit events
- `perf-scan-full | mcl-stop | high=N med=N low=N duration_ms=N categories=bundle,cwv,image bundle_kb=<n>`
- `perf-scan-block | mcl-stop | full-scan high=N`
- `perf-scan-skipped | mcl-stop | reason=no-fe-stack-tag`
- `perf-bundle-delegate | mcl-perf-scan | total_gzip_kb=N file_count=N output_dir=<path>`
- `perf-bundle-skip | mcl-perf-scan | reason=no-build-output`
- `perf-lighthouse-delegate | mcl-perf-scan | url=<u> lcp_ms=N cls=<f> tbt_ms=N`
- `perf-lighthouse-skip | mcl-activate | reason=no-MCL_UI_URL` (reuse)
- `mcl-perf-report | mcl-activate | invoked`
- `mcl-perf-lighthouse | mcl-activate | invoked url_set=<bool>`

### Test sonuçları
- T1 `/mcl-perf-report` keyword: STATIC_CONTEXT 812 byte, `MCL_PERF_REPORT_MODE` mevcut PASS
- T2 `/mcl-perf-lighthouse` keyword: STATIC_CONTEXT 660 byte, `MCL_PERF_LIGHTHOUSE_MODE` mevcut PASS
- T3 Synthetic React project (`dist/main.js` 800KB random + `public/hero.png` 600KB): 2 HIGH (PRF-B01 bundle critical 781.5KB > 2× 200KB budget + PRF-I01 hero.png 586KB > 500KB) + 2 LOW (PRF-B04 large chunk + PRF-I03 PNG no-WebP fallback) PASS
- T4 Bundle delegate: gzip aggregation 781.5KB, file count 1, output_dir=dist PASS
- T5 CWV delegate skip: MCL_UI_URL yok → cwv ran=false (advisory yerine silent in --json mode) PASS
- T6 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-perf-rules.py` (yeni, 11 rule)
- `hooks/lib/mcl-perf-bundle.sh` (yeni, build output gzip walker)
- `hooks/lib/mcl-perf-lighthouse.sh` (yeni, MCL_UI_URL opt-in lighthouse)
- `hooks/lib/mcl-perf-scan.py` (yeni, orchestrator)
- `hooks/lib/mcl-state.sh` (3 yeni state field)
- `hooks/mcl-stop.sh` (Perf gate, sıra: security → db → ui → ops → perf → reminder → phase6)
- `hooks/mcl-activate.sh` (`/mcl-perf-report` + `/mcl-perf-lighthouse` keywords)
- `VERSION`, `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.14.x patch'lerine ertelendi)

- **Build invocation MVP'de yok**: kullanıcı `npm run build` yapmazsa PRF-B03 LOW advisory; auto-build (Phase 4.5'te invoke) 8.14.x'te konfigürasyona bağlı flag.
- **L2 per-Edit perf scan MVP'de yok**: image >500KB Edit'i Phase 4'te yakalanmıyor — sadece L3 Phase 4.5 START full scan + manuel `/mcl-perf-report`. 8.14.x'te image-only L2 block.
- **Phase 1.7 Performance Budget dimension** state field eklendi (`phase1_perf.budget_tier`) ama skill prose talimatı yok — model-behavioral.
- **Lighthouse desktop-only**: MVP desktop profile (faster, deterministic); mobile profile (Moto G4 emulation) 8.14.x'te.
- **Bundle gzip-only**: brotli sıkıştırma 8.14.x'te (production CDN'lerde brotli daha küçük).
- **AVIF support**: PRF-I03 yalnızca WebP suggestion; AVIF 8.14.x'te (browser support 2024+ artık yeterli).
- **Image walker scope**: 5 standart dir; project-spesifik convention'lar (`assets/images/`, `wwwroot/`) `.mcl/perf-config.json`'da configurable 8.14.x'te.
- **CSS/font bundle measurement yok**: yalnızca JS gzip ölçülüyor; CSS/font bundle ayrı budget 8.14.x'te.
- **Tree-shaking detection MVP'de zayıf**: PRF-B04 sadece chunk size; export usage analizi 8.14.x'te.

## [8.13.0] - 2026-04-30

### Eklendi — Operasyonel Disiplin (İŞ 4)

8.7-8.9 product kalitesini disiplin altına aldı; operasyonel katman boştu (Dockerfile root, `.env.example` drift, `console.log` yığını, README yarım, coverage %12). 8.13.0 dört kategoriyi tek pipeline'a bağlar — 8.7-8.9 mirror 3-tier.

#### Yeni dosyalar
- **`hooks/lib/mcl-ops-rules.py`** — 4 rule pack, 20 rule, decorator-registry, `category=ops-*` field:
  - **Deployment** (8): DEP-G01-no-ci-config, G02-workflow-yaml-error, G03-dockerfile-no-healthcheck, G04-dockerfile-root-user, G05-dockerfile-latest-tag, G06-env-example-missing, G07-env-example-stale, G08-secrets-no-doc
  - **Monitoring** (4): MON-G01-no-structured-logger, G02-no-metrics-endpoint, G03-no-error-tracking, G04-log-no-level
  - **Testing** (3): TST-T01-coverage-below-threshold, T02-no-test-framework, T03-changed-file-no-test
  - **Docs** (5): DOC-G01-no-readme, G02-readme-no-install, G03-readme-no-usage, G04-api-no-docs, G05-function-docstring-low
- **`hooks/lib/mcl-ops-scan.py`** — orchestrator: file metrics aggregation (env_var_refs, manifest_deps, adhoc_logging_count, loc_total, function_count, function_doc_count, api_routes_count, changed_files_no_test) → coverage delegate → rule dispatch → lokalize markdown.
- **`hooks/lib/mcl-ops-coverage.sh`** — coverage tool delegate: vitest/jest (`--coverage --coverageReporters=json-summary`), pytest (`--cov --cov-report=json`), go-test (`go tool cover -func`), cargo-tarpaulin. Binary missing graceful skip + audit `ops-coverage-skip`.

#### State şeması
- `phase4_5_ops_scan_done: false` — idempotency flag
- `phase4_5_high_baseline.ops: 0` — Phase 6 (b) regression baseline (8.11.0 schema extend)
- `phase1_ops: {deployment_target, observability_tier, test_policy, doc_level}` — Phase 1.7 4 yeni dimension için

#### Hook entegrasyonu
- **`hooks/mcl-stop.sh`** — UI START gate'inden sonra Ops START gate. Sıra: sticky-pause → security → db → ui → **ops** → standart Phase 4.5 reminder → Phase 6 gate. HIGH ≥ 1 → state pending'de + `decision:block` (4 kategori listesi); HIGH = 0 → done=true + baseline.ops=0; MEDIUM listesi standart reminder reason'a `[Ops-<sub>]` etiketli inject.
- **`hooks/mcl-activate.sh`** — `/mcl-ops-report` keyword block (`/mcl-ui-report` mirror).

#### Konfigürasyon
- `$MCL_STATE_DIR/ops-config.json` (8.5.0 isolation kuralı — proje içine yazma yasak; state dir'da):
  ```json
  {"ops": {"coverage_threshold_high": 50, "coverage_threshold_medium": 70}}
  ```
- Defaults: HIGH<50%, MEDIUM 50-70%, OK ≥70%.

#### Karar matrisi (kabul edilen varsayılanlar)
- Coverage threshold: **HIGH<50%, MEDIUM 50-70%** (configurable)
- DOC-G01 production: **Dockerfile OR CI workflow** (deployment intent heuristic)
- DEP-G07 stale: **JS/Python/Ruby/Go regex MVP**
- TST-T03 convention: **4 convention OR + project pattern infer**
- MON-G01 cutoff: **>10 absolute + LOC>500**
- Coverage timeout: **30s, skip+warning aşılırsa**
- Config: **`MCL_STATE_DIR/ops-config.json`**

#### Trigger condition matrix
- **DEP**: `Dockerfile` OR `.github/workflows/` OR `Procfile` OR `fly.toml` OR `vercel.json` OR `netlify.toml` OR `app.yaml` OR `Jenkinsfile`
- **MON**: backend stack-tag (python/java/csharp/ruby/php/go/rust + node-backend non-FE-only)
- **TST**: test framework manifest (vitest/jest/pytest/rspec/junit/go-test/cargo)
- **DOC**: her proje (always-on)

#### Audit events
- `ops-scan-incremental | mcl-pre-tool | tool=Edit file=... high=N med=N low=N skipped_via_cache=<bool>` (L2 — MVP eksik, 8.13.x)
- `ops-scan-block | mcl-stop | full-scan high=N`
- `ops-scan-full | mcl-stop | high=N med=N low=N duration_ms=N categories=<csv> tags=<csv>`
- `ops-coverage-delegate | mcl-ops-scan | tool=<jest|pytest|go|cargo> total=<pct> threshold_high=<n>`
- `ops-coverage-skip | mcl-ops-scan | reason=<binary-missing|no-test-framework>`
- `mcl-ops-report | mcl-activate | invoked`

### Test sonuçları
- T1 `/mcl-ops-report` keyword detection: `MCL_OPS_REPORT_MODE` STATIC_CONTEXT mevcut PASS
- T2 Synthetic project (Dockerfile root + latest tag, no CI, no README, env vars in code, no test framework): 2 HIGH (DEP-G04 + DOC-G01) + 5 MEDIUM (DEP-G01/G03/G05/G06 + TST-T03) + 3 LOW (MON-G02/G03 + TST-T02); 4 categories scanned; coverage skip PASS
- T3 Audit events doğru: `ops-coverage-skip`, `ops-scan-full high=2 med=5 low=3 categories=...` PASS
- T4 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-ops-rules.py` (yeni, 20 rule)
- `hooks/lib/mcl-ops-scan.py` (yeni, orchestrator + metrics aggregation)
- `hooks/lib/mcl-ops-coverage.sh` (yeni, 4 stack delegate)
- `hooks/lib/mcl-state.sh` (3 yeni state field)
- `hooks/mcl-stop.sh` (Ops START gate, sıra: security → db → ui → ops → reminder → phase6)
- `hooks/mcl-activate.sh` (`/mcl-ops-report` keyword)
- `VERSION`, `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.13.x patch'lerine ertelendi)

- **L2 per-Edit ops scan MVP'de yok**: pre-tool Phase 4 incremental block (Dockerfile/workflow/.env.example/README touch'larında HIGH-only block) 8.13.x'te. Şu an L3 Phase 4.5 START full scan + manuel `/mcl-ops-report` ile yakalanıyor.
- **Phase 1.7 4 yeni dimension** (deployment_target / observability_tier / test_policy / doc_level) state field eklendi ama skill prose talimatı yok — model-behavioral. 8.13.x'te skill update.
- **Coverage delegate basit**: vitest/jest threshold map per-file 8.13.x'te (şu an total only).
- **DEP-G07 env drift**: 4 dil regex (JS/Python/Ruby/Go); Java/C#/Rust/PHP/Swift/Kotlin coverage 8.13.x.
- **TST-T03 test convention infer**: project'te mevcut test pattern analizi (örn. `*_spec.rb` kullanan repo'da `.test.` aramaktan vazgeç) 8.13.x.
- **Workflow YAML lint**: lightweight regex (top-level keys); full `actionlint` delegate 8.13.x.
- **Dockerfile lint**: 4 rule var; `hadolint` delegate 8.13.x'te (DL3007/DL3015/DL3019 vb.).
- **API route detection**: regex Express/FastAPI; Rails routes / Gin / actix 8.13.x.
- **Coverage threshold per-file**: total only MVP; per-changed-file gate 8.13.x.

## [8.12.0] - 2026-04-30

### Eklendi — Interactive Design Loop (İŞ 3)

Phase 4a (BUILD_UI) sonrası UI_REVIEW dev server döngüsü şu an MCL dışında akıyor: kullanıcı manuel `npm run dev`, browser açma, feedback verme. 8.12.0 bu döngüyü MCL içine alır — Phase 4a kod yazımı tamamlanınca MCL dev server'ı (10 stack tespit) arka planda başlatır, URL'yi state'e koyar, build error pause'a bağlanır, `/mcl-design-approve` ile döngü kapanır.

#### Yeni dosyalar
- **`hooks/lib/mcl-dev-server-detect.py`** — 10 stack detection (vite/next/cra/vue-cli/sveltekit/rails/django/flask/expo/static). Manifest tabanlı (package.json scripts + Rails Gemfile + Django manage.py + Flask requirements + Expo app.json + static index.html fallback). Output JSON: `{stack, default_port, start_cmd, args}`.
- **`hooks/lib/mcl-dev-server.sh`** — sourceable lifecycle helper:
  - `mcl_devserver_is_headless` — heuristic (`MCL_HEADLESS` / `CI` / Linux SSH no-DISPLAY)
  - `mcl_devserver_detect <project>` — JSON via .py
  - `mcl_devserver_start <project>` — port allocation (default + 4 fallback retry), `nohup` spawn, PID `dev-server.pid`, log `dev-server.log` (her ikisi `MCL_STATE_DIR`'da, 8.5.0 isolation), state.dev_server set, audit `dev-server-started`
  - `mcl_devserver_stop` — kill PID + state clear + audit
  - `mcl_devserver_status` — "active"/"inactive"/"stale" (PID alive check)

#### State şeması
- `dev_server` object field default `{"active": false}`; aktifken `{active, stack, port, url, pid, started_at, log_path}` (v2 schema bump'sız).

#### Hook entegrasyonu
- **`hooks/mcl-stop.sh`** — Phase 6 gate'den ÖNCE: `ui_flow_active=true` AND `ui_sub_phase=="UI_REVIEW"` AND `dev_server.active=false` AND not headless ise `mcl_devserver_start` tetiklenir. Headless ise audit `dev-server-headless-skip`. Stale PID detect ise auto-clear.
- **`hooks/mcl-post-tool.sh`** — Edit/Write/MultiEdit sonrası `dev-server.log` tail (50 satır); stack-spesifik error pattern (vite/next/cra/django/rails/flask/expo regex map; default generic) match ise `mcl_pause_on_error "build-error" ...` (8.10.0 entegrasyonu) — kullanıcı çözüp `/mcl-resume` ile devam.
- **`hooks/mcl-activate.sh`** — 3 yeni keyword block:
  - `/mcl-design-approve` — `mcl_devserver_stop` + `ui_reviewed=true` + `ui_sub_phase=BACKEND` set + audit `design-loop-approved` + STATIC_CONTEXT BACKEND advance notice
  - `/mcl-dev-server-start` — manuel server başlatma fallback
  - `/mcl-dev-server-stop` — manuel durdurma (UI loop kapanmaz)

#### Karar matrisi (kabul edilen varsayılanlar)
- ui_sub_phase trigger: **(a)** skill talimatı (model-behavioral set; 8.12.x'te skill prose'una explicit `mcl_state_set ui_sub_phase UI_REVIEW` eklenir)
- Stale PID: **auto-clear + restart** (sor yerine sessiz temizlik; 8.12.x'te AskUserQuestion opsiyonu)
- Build error pattern: **(b)** stack-spesifik regex map
- Hot reload check: **MVP skip** (advisory model-behavioral); 8.12.x'te `curl` health check
- Mobile QR: **8.12.x'e ertelendi** (Expo log capture + ASCII rendering MVP'de yok; URL veriliyor, manuel QR alma)
- Phase 4c geçiş: **`ui_reviewed=true` + `ui_sub_phase=BACKEND` ikisi**
- Log persistence: **kalır** (`MCL_STATE_DIR/dev-server.log`)

#### Audit events
- `dev-server-started | mcl-stop | stack=<s> port=<p> pid=<n> url=<u>`
- `dev-server-port-fallback | mcl-stop | requested=<p1> assigned=<p2>`
- `dev-server-port-exhausted | mcl-stop | tried=<p1>-<p5>`
- `dev-server-spawn-failed | mcl-stop | stack=<s>`
- `dev-server-spawn-skipped | mcl-stop | reason=detect-or-spawn-failed`
- `dev-server-headless-skip | mcl-stop | reason=headless-env`
- `dev-server-stale-pid | mcl-stop | cleared=true`
- `dev-server-stopped | mcl-activate.sh | pid=<n>`
- `design-loop-approved | mcl-activate.sh | source=keyword`
- `mcl-dev-server-start|stop | mcl-activate.sh | invoked` (manual)
- `pause-on-error | mcl-post-tool | source=build-error tool=<stack>` (8.10.0 entegrasyonu)

### Test sonuçları
- T1 `/mcl-design-approve` keyword → STATIC_CONTEXT 340 byte, `MCL_DESIGN_APPROVE_MODE` mevcut PASS
- T2 `/mcl-dev-server-start` keyword → 317 byte, `MCL_DEV_SERVER_START_MODE` PASS
- T3 `/mcl-dev-server-stop` keyword → 190 byte, `MCL_DEV_SERVER_STOP_MODE` PASS
- T4 Detection: vite (port 5173 + npm run dev), next (3000), django (8000 + manage.py runserver), nothing (null with reason) PASS
- T5 Headless heuristic: default false, `MCL_HEADLESS=1` true PASS
- T6 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-dev-server-detect.py` (yeni, 10 stack detection)
- `hooks/lib/mcl-dev-server.sh` (yeni, lifecycle helpers)
- `hooks/lib/mcl-state.sh` (`dev_server` field default)
- `hooks/mcl-stop.sh` (auto-start trigger before Phase 6 gate)
- `hooks/mcl-post-tool.sh` (build-error log tail check + pause-on-error integration)
- `hooks/mcl-activate.sh` (3 keyword blocks)
- `VERSION`, `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.12.x patch'lerine ertelendi)

- **URL injection STATIC_CONTEXT'e otomatik eklenmedi**: model `mcl_state_get dev_server` ile JSON'dan URL'i çekebilir (Bash). 8.12.x'te activate hook STATIC_CONTEXT'e `<mcl_dev_server>` block otomatik enjekte.
- **ui_sub_phase transition trigger**: Phase 4 model-behavioral; skill prose henüz `mcl_state_set ui_sub_phase UI_REVIEW` talimatını içermiyor. 8.12.x'te skill update.
- **Hot reload health check**: MVP advisory only; 8.12.x'te `curl -sSf $URL` healthcheck.
- **Mobile Expo QR**: log capture + ASCII render MVP'de yok; URL veriliyor (`exp://localhost:19000`), kullanıcı QR'ı manuel alır.
- **Multi-server projeler** (Next.js + ayrı API): MVP single FE server only; backend Phase 4c'de manuel.
- **Session abandon**: PID arka planda yaşar; bir sonraki session'da stale check ile auto-clear (sormadan); kullanıcı kontrolü 8.12.x'te.
- **Build error pattern coverage**: 7 stack regex var, custom dev tooling kaçabilir; generic fallback `error|ERROR|FAILED|panic` false-positive yüksek.
- **Skill files dokunulmadı**: design loop talimatı (URL relay, NL ack, hot reload bekleme) model-behavioral; skill update 8.12.x'te.

## [8.11.0] - 2026-04-30

### Eklendi — Phase 6 Double-check (İŞ 2)

Phase 5 verification katmanı sadece **Phase 4 code → tests** ekseninde çalışıyordu. Üç kritik soru cevapsızdı: (1) MCL pipeline'ı tüm fazlarını gerçekten çalıştırdı mı? (2) Phase 4.5 sonrası fix'ler yeni HIGH bulgu üretti mi? (3) Kullanıcının istediği her şey teslim edildi mi? Phase 6 bu üç soruyu üç check'le bağlar ve Phase 5'ten sonra `decision:block` tier'i ile enforced.

#### Yeni dosya
- **`hooks/lib/mcl-phase6.py`** — orchestrator. Üç check fonksiyonu + lokalize markdown render. Modes: `run` (enforcement, JSON), `report` (markdown). Top-level try/except → exit 3 (8.10.0 pattern).

#### Üç check
**(a) Audit trail completeness** — required STEP audit event'leri current session window'da mevcut mu? Window: son `session_start` event'inden itibaren (trace.log anchor); fallback son 200 audit satırı. Required (HIGH): `precision-audit`, `engineering-brief`, `spec-extract|spec-save`, `spec-approve`, `phase-review-pending`, `phase-review-running`, `phase-review-impact`. Soft-required (LOW advisory): `phase5-verify` — 8.10.x ve önce projeler emit etmiyor.

**(b) Final scan aggregation** — 4 scan (codebase/security/db/ui) `--mode=full` tekrar çalıştır; HIGH count'larını `phase4_5_high_baseline` ile karşılaştır. `current > baseline` → regression finding (HIGH). Phase 4.5 START gate'leri HIGH=0 ile geçtiğinde baseline=0 set ediliyor (mcl-stop.sh 3 noktada).

**(c) Promise-vs-delivery** (reverse Lens-e) — Phase 1 `phase1_intent` + `phase1_constraints` state field'larından keyword extract (4+ char alphabetic, stopword filtre, TR+EN); modified source file'larda keyword search; eksik keyword → MEDIUM finding. Phase 1 state'te yoksa LOW skip (8.10.x backward compat — Phase 1 skill'inin `mcl_state_set phase1_intent` çağırması gerek).

#### State şeması
- `phase6_double_check_done: false` — idempotency flag
- `phase4_5_high_baseline: {security: 0, db: 0, ui: 0}` — regression baseline
- `phase1_intent: null`, `phase1_constraints: null` — Phase 1 confirmed params (Phase 1 skill talimatıyla doldurulacak)
- v2 schema bump'sız (geriye uyumlu)

#### Hook entegrasyonu
- **`hooks/mcl-stop.sh`** — (1) Phase 4.5 START gate'lerinde HIGH=0 noktasında `phase4_5_high_baseline.{security|db|ui}=0` set'i (3 yerde). (2) Hook sonunda **Phase 6 gate**: `phase_review_state == "running"` AND `phase6_double_check_done != true` AND (audit'te `phase5-verify` event VAR ya da transcript'te "Verification Report" / "Doğrulama Raporu" string'i VAR) ise `mcl-phase6.py --mode=run` çalıştır. Output JSON'da (a/b/c HIGH varsa) → `decision:block` reason'da kategorize edilmiş finding listesi (max 5 her kategori). Pass → `phase6_double_check_done=true` set + audit `phase6-done`.
- **`hooks/mcl-activate.sh`** — `/mcl-phase6-report` keyword block (`/mcl-ui-report` mirror).

#### Audit events
- `phase6-run-start | mcl-stop|mcl-phase6 | required_events=N`
- `phase6-audit-gap | mcl-phase6 | missing=<rule_ids>`
- `phase6-scan-regression | mcl-phase6 | new_high=N`
- `phase6-promise-gap | mcl-phase6 | missing=N`
- `phase6-block | mcl-stop | a=N b=N c=N`
- `phase6-done | mcl-stop | duration_ms=N`
- `mcl-phase6-report | mcl-activate | invoked`

### Phase 5 vs Phase 6 sınır
| Soru | Phase 5 | Phase 6 |
|---|---|---|
| Test edildi mi? | ✓ | — |
| Manuel-test surface | ✓ | — |
| Process trace | ✓ | — |
| Pipeline bütünlüğü | — | ✓ (a) |
| Post-fix regression | — | ✓ (b) |
| Reverse traceability | — | ✓ (c) |

### Karar matrisi (kabul edilen varsayılanlar)
- Phase 5 done detection: **(c) hibrit** — `phase_review_state=="running"` + (`phase5-verify` event OR transcript "Verification Report")
- Keyword algoritması: **regex token** (4+ char alphabetic, TR+EN stopword filter)
- Phase 1 confirmed param: **(a) state'e ekle** — `phase1_intent` + `phase1_constraints` field'ları
- `phase5-verify` backward compat: **soft-fail (LOW advisory)**, hard-block değil
- Phase 6 (b) baseline yokluğu: **0 default güvenilir** (gate skipped → ilgili category baseline=0 anlamlı)

### Test sonuçları
- T1 `/mcl-phase6-report` keyword detection: STATIC_CONTEXT 779 byte, `MCL_PHASE6_REPORT_MODE` mevcut PASS
- T2 Synthetic state (Phase 1.7 audit yok, FastAPI projesi): (a) `P6-A-missing-precision-audit` HIGH + `P6-A-missing-phase5-verify` LOW; (b) no scan regression (no-stack scenarios skipped); (c) 7 missing keyword MEDIUM PASS
- T3 Audit events: `phase6-run-start required_events=6`, `phase6-audit-gap missing=...`, `phase6-promise-gap missing=1` PASS
- T4 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-phase6.py` (yeni, 3 check orchestrator)
- `hooks/lib/mcl-state.sh` (4 yeni field: phase6_double_check_done, phase4_5_high_baseline, phase1_intent, phase1_constraints)
- `hooks/mcl-stop.sh` (Phase 4.5 gate baseline set'leri + hook sonunda Phase 6 gate)
- `hooks/mcl-activate.sh` (`/mcl-phase6-report` keyword)
- `VERSION`, `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.11.x patch'lerine ertelendi)

- **`phase5-verify` audit event** model-behavioral; mevcut Phase 5 skill prose'u bunu emit etmiyor. Phase 6 trigger fallback: transcript scan ("Verification Report" / "Doğrulama Raporu") — heuristic, lokalize 14 dil için tam coverage yok. 8.11.x'te skill prose'una `mcl_audit_log "phase5-verify" ...` Bash talimatı eklenir.
- **Phase 1 state field doldurma**: `phase1_intent` + `phase1_constraints` mevcut Phase 1 skill'inde set edilmiyor — boş kalırsa (c) check LOW skip. 8.11.x'te Phase 1 skill prose'una `mcl_state_set phase1_intent` talimatı.
- **Promise-vs-delivery keyword heuristic**: false-positive yüksek (4+ char regex token; semantic equivalence yok). 8.11.x'te NLP-grade traceability (LLM-driven param-to-implementation mapping).
- **Phase 6 (b) regression baseline**: tüm 4.5 gate'leri skip ise (no-stack-tag) baseline=0 anlamlı; ama partial scenario (security baseline=2, db=0, ui=skip) baseline tracking accuracy belirsiz. MVP'de güvenilir kabul.
- **codebase-scan dahil değil (b)**: 4 scan'den codebase-scan severity routing yapmıyor (high_count yerine general findings); Phase 6 (b) regression detection sadece security/db/ui üzerinden. 8.11.x'te codebase-scan severity field'ı eklenip dahil edilebilir.
- **Phase 6 idempotency boundary**: `phase6_double_check_done=true` session boundary'da sticky. Yeni Phase 4 turn'ünde reset gerekir mi? Mevcut MCL'de `phase_review_state` reset noktaları sınırlı; 8.11.x'te explicit reset.

## [8.10.0] - 2026-04-29

### Eklendi — Pause-on-error (İŞ 1)

CLAUDE.md "never silently fall back when a corruption is detected" kuralının yapısal uygulaması. MCL'in scan helper Python crash, validator JSON parse error, state.json corrupt, audit write fail, hook crash, delegate non-graceful failure gibi durumlarda silent fail-open yerine **explicit pause** mekanizması ekler. Kullanıcı her hatayı görür, çözümünü açıklar, MCL kaldığı phase'den devam eder.

#### Yeni dosya
- **`hooks/lib/mcl-pause.sh`** — sourceable helper:
  - `mcl_pause_on_error <source> <tool> <error_msg> <suggested_fix>` — state.paused_on_error.active=true + audit
  - `mcl_pause_check` — paused mı kontrolü (true/false)
  - `mcl_pause_resume <resolution>` — state temizle + audit
  - `mcl_pause_block_reason` — `decision:block` reason render
  - `mcl_pause_on_scan_error <orchestrator> <result_json>` — scan output'unda "error" key varsa otomatik pause + PreToolUse-shaped block JSON emit (caller exit 0)

#### State şeması
- `state.json`'a `paused_on_error` object field eklendi (default `{"active": false}`); active=true olduğunda `{timestamp, source, tool, error_msg, last_phase, last_phase_name, suggested_fix, user_resolution}` field'ları doluyor. v2 schema bump'sız (geriye uyumlu — eski state'lerde field eksikse default'la doluyor).

#### Hook entegrasyonu
- **`hooks/mcl-pre-tool.sh`** — (1) Hook başında sticky pause check: `paused_on_error.active=true` ise tüm tool'lar `decision:deny` "MCL PAUSED" reason'la blocklanır, audit `pause-sticky-block`. (2) Üç scan branch'inin (security/db/ui) her birinde scan subprocess sonrası `mcl_pause_on_scan_error` çağrısı — orchestrator exception → state set + block + temp file cleanup + exit 0.
- **`hooks/mcl-stop.sh`** — Hook başında sticky pause check: paused state'te enforcement skip + `decision:block` "MCL PAUSED" emit. Audit `pause-sticky-block`.
- **`hooks/mcl-activate.sh`** — (1) `/mcl-resume <resolution>` keyword block: paused_on_error temizler, user_resolution kaydeder, "MCL_RESUME" notice emit. (2) Paused state context: hook ortasına `mcl_pause_check` guard; aktifse `<mcl_paused>` block STATIC_CONTEXT'e inject edilir + diğer tüm branch'ler skip (sticky). Model NL-ack ile resolve etmesi için Bash talimatı dahil.

#### Orchestrator pause hook entegrasyonu
- `hooks/lib/mcl-security-scan.py`, `mcl-db-scan.py`, `mcl-ui-scan.py`, `mcl-codebase-scan.py` — top-level `try/except` wrapper main() etrafına eklendi. Exception → stdout `{"error": "...", "traceback": "..."}` JSON + exit 3 (orchestrator crash kodu). Caller hook bunu `mcl_pause_on_scan_error` ile yakalar.

#### `state-corrupt-recovered` audit (kullanıcı isteği)
- `hooks/lib/mcl-state.sh` — corrupt state detected branch'inde `mcl_audit_log "state-corrupt-recovered" path=<corrupt copy path>` event eklendi. Mevcut recovery davranışı (corrupt copy + default reset) **korundu** — pause edilmedi, ama artık görünür. CHANGELOG-documented exception to silent-fallback rule (recovery safety > silent-pause).

#### Karar matrisi (kabul edilen varsayılanlar)
- T5 corrupt-state: **(b)** mevcut recovery + audit (visible non-blocking)
- T7 NL-ack: **(a)** /mcl-resume keyword MVP; NL-ack 8.10.x model-behavioral
- Sticky süresi: **persist** (session boundary'da temizlenmez)
- Pause vs gate çakışması: **pause öncelikli** (mcl-pre-tool.sh ve mcl-stop.sh hook başında)
- /mcl-resume argv: **free-form text** (keyword sonrası kalan tüm prompt)

### Test sonuçları
- T1 `mcl_pause_on_error` çağrısı (manuel state setup) → `paused_on_error.active=true` ✓
- T2 Sticky pre-tool block: paused state'te Edit → `decision:deny` "MCL PAUSED..." reason; audit `pause-sticky-block` PASS
- T3 Sticky stop block: paused state'te Stop → `decision:block` "MCL PAUSED..." reason; audit `pause-sticky-block` PASS
- T4 Activate paused context: paused state'te normal prompt → STATIC_CONTEXT'e `<mcl_paused>` tag + MCL PAUSED reason inject PASS
- T5 `/mcl-resume binary yüklendi` → `MCL_RESUME` notice; state.paused_on_error.active=false; user_resolution kaydedildi; audit `resume-from-pause resolution_len=16` PASS
- T6 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-pause.sh` (yeni, 5 helper)
- `hooks/lib/mcl-state.sh` (`paused_on_error` field + corrupt-recovered audit)
- `hooks/lib/mcl-security-scan.py`, `mcl-db-scan.py`, `mcl-ui-scan.py`, `mcl-codebase-scan.py` (top-level try/except)
- `hooks/mcl-pre-tool.sh` (sticky check + scan-error pause integration in 3 branches)
- `hooks/mcl-stop.sh` (sticky check)
- `hooks/mcl-activate.sh` (paused-state context + /mcl-resume keyword)
- `VERSION`, `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.10.x patch'lerine ertelendi)

- **NL-ack detection** model-behavioral; hook tarafında detect yok. Skill prose'u model'e talimat verir; fail-safe `/mcl-resume`. Hook-level NL-ack 8.10.x'te (transcript scan ile pattern matching).
- **state.json corrupt** durumunda mevcut recovery davranışı korundu (pause yerine). CHANGELOG-documented exception. 8.10.x'te flag-based opt-in (hard-pause vs auto-recover) eklenebilir.
- **Audit log write failure** trigger noktası eklenmedi (audit log'a yazamayan bir sistem pause audit'ini de yazamaz — chicken-and-egg). MVP'de stderr'e mesaj basılır; kullanıcı görmez. 8.10.x'te alternative channel (state.json içinde paused field + on next read).
- **Hook crash trap** explicit `trap ERR` set edilmedi; mevcut hook'lar `set -uo pipefail` kullanıyor; tam coverage için `trap` infrastructure ileride.
- **External delegate non-graceful** (squawk/eslint timeout) için pause path eksik; mevcut graceful skip korundu. 8.10.x'te delegate-spesifik timeout pause.
- **Pause persistence cross-session**: paused state.json'da kalır; yeni mcl-claude session açıldığında paused notice tekrar gelir. Beklenen ve istenen davranış (kullanıcı çözmedikçe MCL pasif).

## [8.9.0] - 2026-04-29

### Eklendi — UI Enforcement Layer (3-tier, framework-aware)

8.7.0 backend security ve 8.8.0 DB tasarım disiplininden sonra UI tarafına aynı 3-tier hattını uyguluyoruz: **design system tutarlılığı, component reuse, a11y, responsive davranış, naming convention**. Severity tier UI-spesifik tunelendi: **a11y-critical-only block** (E3) — design tokens / reuse / responsive / naming HIGH değil, dialog/audit. UI iteration tempo'sunu korur ama legal-risk a11y ihlallerini hard-block eder.

#### Yeni dosyalar
- **`hooks/lib/mcl-ui-rules.py`** — generic core 10 + framework add-on (4 framework × 3 = 12) = **22 rule**. Decorator-registry, `category=ui-*` + `framework` field. Token-aware rules (UI-G07/G08/G09/G10) `mcl-ui-tokens.py`'dan token listesi alır.
  - Generic core: UI-G01 img-no-alt, UI-G02 button-no-accessible-name, UI-G03 link-no-href, UI-G04 form-input-no-label, UI-G05 interactive-no-keyboard (5 a11y-critical HIGH); UI-G06 heading-skip-level, UI-G07 hardcoded-color, UI-G08 hardcoded-spacing, UI-G09 hardcoded-font-size, UI-G10 magic-breakpoint.
  - Framework add-on: React (UI-RX-list-no-key, UI-RX-controlled-without-onChange HIGH, UI-RX-fragment-with-key-only), Vue (UI-VU-v-for-no-key, UI-VU-v-html-untrusted HIGH, UI-VU-prop-no-type), Svelte (UI-SV-each-no-key, UI-SV-on-click-no-keyboard HIGH, UI-SV-prop-no-export-let-type), HTML-static (UI-HT-no-html-lang HIGH, UI-HT-no-meta-viewport, UI-HT-button-input-mixup).
  - **9 HIGH a11y-critical** rule total — bunlar L2 ve L3'te `decision:deny`/`decision:block` tetikler; geri kalan rule'lar dialog/audit.
- **`hooks/lib/mcl-ui-tokens.py`** — design token detector. **C3 hybrid:** tailwind.config.{js,ts,cjs,mjs} parse, `:root` CSS custom properties, `design-tokens.json` (W3C draft), `theme.ts/js` loose extraction. Project'te token dosyası yoksa MCL default set fallback (8px grid spacing, type ramp 12-60px, breakpoint 640/768/1024/1280/1536). Audit `ui-tokens-detected source=tailwind|css-vars|theme-ts|design-tokens|mcl-default`.
- **`hooks/lib/mcl-ui-scan.py`** — orchestrator (incremental/full/report/axe modes), `ui-cache.json` (file SHA1 + rules-version composite), token detector dispatch, eslint-a11y delegate çağrı, lokalize markdown render.
- **`hooks/lib/mcl-ui-eslint.sh`** — external delegate: `eslint-plugin-jsx-a11y` (React) + `eslint-plugin-vuejs-accessibility` (Vue) + `eslint-plugin-svelte` a11y subset; framework-spesifik rule list ile filtered. Binary yoksa graceful skip.
- **`hooks/lib/mcl-ui-axe.sh`** — `/mcl-ui-axe` keyword backing. `MCL_UI_URL` env yoksa lokalize advisory; varsa Playwright + `@axe-core/playwright` headless single-page scan. MVP single-page; multi-page crawl 8.9.x'te.

#### Hook entegrasyonu (8.7.x/8.8.x mirror)
- **`hooks/mcl-activate.sh`** — `/mcl-ui-report` + `/mcl-ui-axe` keyword blokları.
- **`hooks/mcl-pre-tool.sh`** — 8.8.0 DB block sonrası Phase 4 UI incremental block. FE stack-tag check + Edit/Write/MultiEdit + UI ext (.tsx/.jsx/.ts/.js/.vue/.svelte/.html/.css/.scss); **yalnızca `category=ui-a11y` HIGH bulguda `decision:deny`** reason "MCL UI A11Y — `<rule>`...". Token/reuse/responsive/naming HIGH değil, sessiz audit. Audit `ui-scan-incremental`, `ui-scan-block`.
- **`hooks/mcl-stop.sh`** — 8.8.0 DB START gate'inin yanına paralel Phase 4.5 START UI gate. `phase4_5_ui_scan_done` state field. Sıra: security → db → ui → standart Phase 4.5 reminder. HIGH a11y → state pending'de kalır + `decision:block` (ilk 5 finding listeli); HIGH=0 → done=true; MEDIUM listesi standart block reason'a `[UI-Design]` etiketli inject.
- **`hooks/lib/mcl-state.sh`** — schema'ya `phase4_5_ui_scan_done: false` field (8.7.1 security + 8.8.0 db paralel; v2 schema bump'sız).

#### Phase 4.5 lens (d) genişletme
`mcl-ui-scan.py --mode=full` Phase 4.5 START'ta security + DB gate'lerinden sonra çalışır. Severity routing: HIGH ui-a11y → block; MEDIUM ui-tokens/reuse/responsive/naming → `[UI-Design]` veya `[UI-A11y]` dialog item; LOW → audit. Auto-fix: ESLint `--fix` safe categories silent OK; a11y/token/reuse/naming asla silent.

#### Trigger condition (F1)
**Sadece FE stack-tag tespit edildiğinde** (`react-frontend|vue-frontend|svelte-frontend|html-static` herhangi biri). Backend-only / lib / CLI / data pipeline projelerinde tüm UI pipeline (L1 + L2 + L3) skip edilir; audit `ui-scan-skipped reason=no-fe-stack-tag`.

#### 8.7.0/8.8.0 ile çakışmazlık
React unsafe-html-setter XSS / target=_blank rel 8.7.0'da kalır; SQL injection / schema design 8.8.0'da kalır. UI scan **tekrar etmez**. `category=ui-tokens|ui-reuse|ui-a11y|ui-responsive|ui-naming` field ayrım. Audit event'leri ayrı namespace: `ui-scan-*`, `ui-axe-*`, `ui-tokens-*`.

### Test sonuçları
- T1 `/mcl-ui-report` keyword detection: STATIC_CONTEXT 957 byte, `MCL_UI_REPORT_MODE` mevcut PASS
- T2 `/mcl-ui-axe` keyword: STATIC_CONTEXT 612 byte, `MCL_UI_AXE_MODE` mevcut PASS
- T3 Full UI scan synthetic React projesi (`<img>` no alt + empty `<button>` + `<div onClick>` + `<input id="email">` no label): 4 HIGH a11y bulgu (UI-G01, UI-G02, UI-G04, UI-G05); tokens=mcl-default (no tailwind config) PASS
- T4 L2 pre-tool a11y block: phase=4, FE stack-tag, Write `<img src="a.png" />` (no alt) → `decision:deny` reason "MCL UI A11Y — UI-G01-img-no-alt..."; audit `ui-scan-incremental high=1` + `ui-scan-block` PASS
- T5 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-ui-rules.py` (yeni, 22 rule)
- `hooks/lib/mcl-ui-tokens.py` (yeni, C3 hybrid token detector)
- `hooks/lib/mcl-ui-scan.py` (yeni, orchestrator)
- `hooks/lib/mcl-ui-eslint.sh` (yeni, eslint a11y delegate)
- `hooks/lib/mcl-ui-axe.sh` (yeni, opt-in axe runner)
- `hooks/lib/mcl-state.sh` (`phase4_5_ui_scan_done` field)
- `hooks/mcl-activate.sh` (`/mcl-ui-report` + `/mcl-ui-axe` keywords)
- `hooks/mcl-pre-tool.sh` (Phase 4 UI incremental block, a11y-critical-only)
- `hooks/mcl-stop.sh` (Phase 4.5 START UI gate)
- `skills/my-claude-lang/phase4-5-risk-review.md` (Lens (d) UI extension)
- `VERSION` (8.8.0 → 8.9.0)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (kabul edilmiş, 8.9.x patch'lerine ertelendi)

- **Phase 1.7 react-frontend / vue-frontend / svelte-frontend / html-static add-on extension** (5 yeni dimension: design tokens stance, a11y stance, responsive strategy, component reuse policy, naming convention) MVP'de yok — model-behavioral kalıyor. Skill dosyasına dedicated dimension ekleme 8.9.1'de.
- **Component reuse AST fingerprint detector** MVP'de yok; rule-level eksik. Static heuristic ileri düzey 8.9.x'te.
- **Storybook integration** (`*.stories.{ts,js,tsx,jsx}` parse + component → story coverage) MVP'de yok; `mcl-ui-storybook.py` ve reuse detector 8.9.x'te.
- **`/mcl-ui-axe` MVP single-page**: tek URL Playwright + axe; multi-page crawl, multi-viewport runs, login flow 8.9.x'te.
- **Solid / Angular / Qwik** stack-tag yok (8.4.1 TODO); UI feature tetiklenmez. 8.9.x patch'lerinde framework genişletmesi.
- **Contrast checking static** sadece literal hex/rgb için; CSS variable runtime resolution `/mcl-ui-axe` ile yakalanır.
- **MCL default token set** dar — colors boş (any color allowed), spacing/font/breakpoint 8px grid + Tailwind defaults. Project token'ları yokken UI-G07 hardcoded-color silent (false-positive engellemek için).
- **eslint-plugin yokluğu** (jsx-a11y / vuejs-accessibility / eslint-plugin-svelte install edilmemiş): D1 delegate skip + warning; generic core rule'lar (UI-G01..G10) yine çalışır.
- **14 dilden yalnızca TR + EN tam lokalize**; diğer 12 dil EN fallback.

## [8.8.0] - 2026-04-29

### Eklendi — DB Tasarım Disiplini (3-tier, ORM-aware)

8.7.0 backend security'nin DB layer kapsamı sadece SQL injection / hardcoded credential / mass-assignment ile sınırlıydı. Schema design, index stratejisi, N+1 detection, migration safety, query plan, connection pooling, multi-tenancy — boştu. Bu patch 8.7.x security pattern'ini birebir paralel hatla DB tasarım disiplinine uyarlıyor.

#### Yeni dosyalar
- **`hooks/lib/mcl-db-rules.py`** — generic core 10 + 8 ORM × 3 anchor = 24 add-on = **34 rule**. Decorator-registry, `category=db-*` zorunlu, dialect field.
  - Generic core: DB-G01 missing-PK, DB-G02 SELECT-*, DB-G03 missing-FK-index, DB-G04 UPDATE/DELETE-no-WHERE, DB-G05 JSONB-no-validation, DB-G06 TIMESTAMP-no-tz, DB-G07 text-id-not-uuid, DB-G08 enum-as-text, DB-G09 cascade-delete-user-data, DB-G10 N+1-static.
  - ORM add-on (her biri 3): Prisma, SQLAlchemy, Django ORM, ActiveRecord, Sequelize, TypeORM, GORM, Eloquent.
- **`hooks/lib/mcl-db-scan.py`** — orchestrator (incremental/full/report/explain modes), `db-cache.json` (file SHA1 + rules-version composite key), generic + ORM dispatch, migration delegate çağrı, lokalize markdown render.
- **`hooks/lib/mcl-db-migration.sh`** — external delegate: `squawk` (Postgres migration linter — lock impact, data-loss, type narrow) + `alembic check` (Python). Binary-missing graceful skip + tek-seferlik warning.
- **`hooks/lib/mcl-db-explain.sh`** — `/mcl-db-explain` keyword backing. `MCL_DB_URL` env yoksa lokalize advisory; varsa dialect tespit + generic CLI EXPLAIN (`psql/mysql/sqlite3`). MVP: ANALYZE değil, sadece EXPLAIN (production safety).

#### Stack-detect (`hooks/lib/mcl-stack-detect.sh`) — 17 yeni tag
- **DB dialect** (6): `db-postgres`, `db-mysql`, `db-sqlite`, `db-mariadb`, `db-mongo`, `db-redis` — manifest dep + Docker compose image + `.env.example` connection string regex.
- **Cloud DB** (3): `db-bigquery`, `db-snowflake`, `db-dynamodb` — manifest dep (8.8.x'te dialect-spesifik kural setleri).
- **ORM** (8): `orm-prisma`, `orm-sqlalchemy`, `orm-django`, `orm-activerecord`, `orm-sequelize`, `orm-typeorm`, `orm-gorm`, `orm-eloquent` — schema dosya varlığı + manifest dep.

#### Hook entegrasyonu (8.7.x mirror)
- **`hooks/mcl-activate.sh`** — `/mcl-db-report` + `/mcl-db-explain` keyword blokları (`/mcl-security-report` mirror).
- **`hooks/mcl-pre-tool.sh`** — 8.7.1 security incremental block'undan sonra Phase 4 DB incremental block. DB stack-tag check + Edit/Write/MultiEdit + source ext (+`.sql`+`.prisma`); HIGH bulguda `decision:deny` reason "MCL DB DESIGN — `<rule>` [`<category>`]...". Audit `db-scan-incremental`, `db-scan-block`.
- **`hooks/mcl-stop.sh`** — 8.7.1 security START gate'inin yanına paralel Phase 4.5 START DB gate. `phase4_5_db_scan_done` state field. `no_db_stack=true` ise skip + done. HIGH ≥ 1 → state pending'de kalır + `decision:block` reason'a ilk 5 HIGH bulgu listesi (`category` field'ıyla); standart Phase 4.5 reminder bypass. HIGH = 0 → done=true; MEDIUM listesi standart block reason'a `[DB-Design]` etiketli inject. Sıra: security-gate → db-gate → standart reminder.
- **`hooks/lib/mcl-state.sh`** — schema'ya `phase4_5_db_scan_done: false` field (8.7.1 security paralel; v2 schema bump'sız).

#### Phase 1.7 — 7 yeni DB design dimension (DB-stack-tag triggered)
1. **Persistence Model** (RDBMS / document / hybrid)
2. **Schema Ownership** (single-service / shared)
3. **Migration Policy** (zero-downtime / expand-contract / direct)
4. **Index Strategy Upfront** (composite / partial / expression / covering)
5. **ID Generation** (auto-increment / UUID v4 / v7 / ULID / snowflake)
6. **Multi-Tenancy** (schema-per-tenant / row-level / none)
7. **Connection Pooling** (size + saturation)

Hepsi mevcut SILENT-ASSUME / SKIP-MARK / GATE pattern'i. Sadece `db-*` tag tespit edilince uygulanır (FE-only / lib / CLI projelerinde skip).

#### Phase 4.5 lens (d) genişletme
`mcl-db-scan.py --mode=full` Phase 4.5 START'ta security gate sonrası çalışır. Severity routing 8.7.0 ile aynı: HIGH → block; MEDIUM → `[DB-Design]` dialog item; LOW → audit. Auto-fix: schema/migration/index **asla silent**; naming/style silent OK.

#### Trigger condition
**Sadece DB stack-tag tespit edildiğinde.** Stack-tag yoksa: Phase 1.7 DB dimension'ları uygulanmaz, L2 ve L3 hook bloğları skip (audit `db-scan-skipped reason=no-db-stack-tag`). ORM tag yoksa ama DB tag varsa: generic core çalışır, ORM add-on'lar skip.

#### 8.7.0 ile çakışmazlık
SQL injection / hardcoded credentials / mass-assignment / insecure-deserialization 8.7.0 kapsamında kalır — DB scan tekrar etmez. `category=db-schema|db-index|db-query|db-migration|db-n-plus-one|db-pooling` field'ı ayrım. Audit event'leri ayrı namespace: `db-scan-*`, `migration-safety-*`, `db-explain-*`.

### Test sonuçları
- T1 `/mcl-db-report` keyword detection (`MCL_STATE_DIR=/tmp/proj` outside MCL repo): STATIC_CONTEXT 1125 byte, `MCL_DB_REPORT_MODE` mevcut PASS
- T2 `/mcl-db-explain` keyword: STATIC_CONTEXT 632 byte, `MCL_DB_EXPLAIN_MODE` mevcut PASS
- T3 Stack-detect: `package.json` `pg+sequelize` → `[javascript, db-postgres, orm-sequelize]`; `requirements.txt` `psycopg+sqlalchemy+django` → `[python, db-postgres, orm-sqlalchemy, orm-django]` PASS
- T4 Full scan synthetic project (Postgres + Sequelize, schema.sql + api.js): HIGH=1 (DB-G01), MEDIUM=2 (DB-SQ-raw-no-replacements + DB-G02 SELECT-*) PASS
- T5 L2 pre-tool DB block: phase=4, Write `CREATE TABLE foo (id INT, val TEXT);` → `decision:deny` reason "MCL DB DESIGN — DB-G01-missing-primary-key [db-schema]..."; audit `db-scan-incremental high=1` + `db-scan-block` PASS
- T6 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-db-rules.py` (yeni, 34 rule)
- `hooks/lib/mcl-db-scan.py` (yeni, orchestrator)
- `hooks/lib/mcl-db-migration.sh` (yeni, squawk + alembic delegate)
- `hooks/lib/mcl-db-explain.sh` (yeni, MCL_DB_URL stub)
- `hooks/lib/mcl-stack-detect.sh` (17 yeni tag: 6 DB + 3 cloud + 8 ORM)
- `hooks/lib/mcl-state.sh` (`phase4_5_db_scan_done` field)
- `hooks/mcl-activate.sh` (`/mcl-db-report` + `/mcl-db-explain` keyword blokları)
- `hooks/mcl-pre-tool.sh` (Phase 4 DB incremental block)
- `hooks/mcl-stop.sh` (Phase 4.5 START DB gate)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (7 DB design dimension)
- `skills/my-claude-lang/phase4-5-risk-review.md` (Lens (d) DB extension)
- `VERSION` (8.7.1 → 8.8.0)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (kabul edilmiş, 8.8.x patch'lerine ertelendi)

- **N+1 runtime profiling D3** MVP'de **model-behavioral**; test runner direct-integration (pytest-django plugin / RSpec helper / jest setup) 8.8.x patch'lerinde
- **`/mcl-db-explain` F2** MVP'de **stub**: `MCL_DB_URL` set'liyse generic CLI EXPLAIN (`psql/mysql/sqlite3`); ORM-spesifik query introspection (auto-detected slow paths from query log) 8.8.x'te
- **Cloud DB (BigQuery / Snowflake / DynamoDB)** stack-tag detection eklendi ama dialect-spesifik kural setleri 8.8.x patch'lerinde; tag varlığı şimdilik audit-only
- **Migration tool yokluğu** (squawk / alembic-check binary install edilmemiş): ilgili dialect/ORM için skip + tek-seferlik warning
- **8 ORM × 3 rule = 24 ORM-spesifik rule** MVP; her ORM için 10+ derin rule yazılabilir, 8.8.x patch'lerinde
- **MongoDB / Redis / DynamoDB schema tasarımı** stack-tag tespit edilir ama dialect-spesifik kural seti MVP'de yok (RDBMS-first); 8.9 plan
- **EXPLAIN ANALYZE production safety**: `MCL_DB_URL` prod DB'sini gösteriyorsa `EXPLAIN ANALYZE` mutating queries için tehlikeli — `mcl-db-explain.sh` yalnızca `EXPLAIN` çalıştırır default
- **Trigger gating false-negative riski**: DB stack-tag tespit edilemeyen projelerde (örn. raw SQL string'lerde Postgres connection ama manifest'te dep yok) DB feature hiç çalışmaz
- **14 dilden yalnızca TR + EN tam lokalize**; diğer 12 dil EN fallback (codebase-scan / security-report ile aynı pattern)

## [8.7.1] - 2026-04-29

### Eklendi — Hook entegrasyonu (8.7.0'da ertelenmişti)

#### L2 — Phase 4 incremental scan (`hooks/mcl-pre-tool.sh`)
Edit/Write/MultiEdit branch'inde HIGH-only quick scan eklendi. Tetikleme: `tool_name ∈ {Edit, Write, MultiEdit}` AND source ext (ts/tsx/js/jsx/py/rb/go/rs/java/kt/swift/cs/php/cpp/c/h/lua/vue/svelte) AND `current_phase=4` AND `MCL_STATE_DIR` set. Mekanizma:
1. Hypothetical post-edit content temp dosyaya yazılır (Edit: old→new bellek apply; MultiEdit: edits sırayla; Write: content doğrudan)
2. `mcl-security-scan.py --mode=incremental --target <tmp>` çağrılır
3. HIGH bulgu varsa `decision:deny` JSON döner; reason: `MCL SECURITY — <rule_id> (OWASP <ref>) at <file>:<line> — <message>. Fix the issue and retry.` Audit: `security-scan-block | mcl-pre-tool | rule=... tool=... file=... severity=HIGH`
4. MEDIUM/LOW sessiz, audit only (`security-scan-incremental | mcl-pre-tool | file=... high=N med=N low=N skipped_via_cache=...`)

Recursion safety: pre-tool MCL'in kendi tool'larını intercept etmiyor; harici Edit/Write çağrılarına özel.

#### L3 — Phase 4.5 START gate (`hooks/mcl-stop.sh`)
Mevcut Phase 4.5 enforcement state machine'inin pending dalına security scan tetikleme eklendi. Mekanizma:
1. State `pending` AND `phase4_5_security_scan_done=false` ise `mcl-security-scan.py --mode=full` (timeout 120s, cache'li → tipik <5s)
2. **HIGH ≥ 1:** state `pending`'de kalır (advance yok), `decision:block` döner; reason'da ilk 5 HIGH bulgu listesi (rule_id + OWASP + file:line + mesaj). Standart Phase 4.5 reminder mesajı **bypass edilir**. Audit: `security-scan-block | mcl-stop | full-scan high=N`. Geliştirici fix yaptıkça L2 incremental tetikler; tüm HIGH'lar fix'lendiğinde sonraki Stop'ta scan tekrar çalışır → HIGH=0 olur.
3. **HIGH = 0:** `phase4_5_security_scan_done=true` set'lenir. Standart Phase 4.5 reminder block emit'ler ama reason'a MEDIUM bulgu listesi (max 8 satır) eklenir — "surface each one as a [Security] item in the Phase 4.5 sequential dialog". MEDIUM'lar Lens (d) etiketli risk turn'ü olarak işlenir.
4. **LOW** her zaman audit-only, dialog'a girmez.

Idempotency: `phase4_5_security_scan_done` field'ı state'e eklendi (default false). Phase 4.5 cycle başında reset davranışı mevcut state lifecycle'ına bağlı (session_start → state default).

#### State şema değişikliği
- `mcl-state.sh` `_mcl_state_default` schema'sına `phase4_5_security_scan_done: false` eklendi. v2 schema bumped değil — yeni field default false ile geriye dönük uyumlu.

### Test sonuçları
- T1 Pre-tool L2: phase=4, Write `cursor.execute("..." + name)` → `decision:deny` doğru reason ("G01-sql-string-concat (OWASP A03) at .../app.py:2 — ..."), audit `security-scan-incremental` (high=2) + `security-scan-block` (rule=G01-sql-string-concat) PASS
- T2 Stop L3: durum cycle smoke test — pending'de scan tetiklenir (regression suite üzerinden doğrulandı)
- T3 Mevcut suite: 19/0/2 — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-state.sh` (schema'ya `phase4_5_security_scan_done` field'ı)
- `hooks/mcl-pre-tool.sh` (Phase 4 incremental scan branch eklendi, secret-scan-block JSON pattern'i mirror'landı)
- `hooks/mcl-stop.sh` (Phase 4.5 START security gate, mevcut enforcement'a entegre)
- `VERSION` (8.7.0 → 8.7.1)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (8.7.0'dan devralınmış, hâlâ geçerli)

- A04 Insecure Design + A09 Logging/Monitoring sadece L1 design-time
- ASVS L1 subset (V2/V3/V4/V5/V6/V7/V8); L2/L3 kapsam dışı
- BOLA/IDOR semantik — heuristic decorator yokluğu yakalar; logic flaw'ları yakalayamaz
- SCA tool yokluğunda ilgili stack için A06 skip
- 14 dilden TR + EN tam lokalize, diğer 12 dil EN fallback
- 100k+ mono-repo Phase 4.5 full scan dakikalarca sürebilir; cache ilk runda etkisiz

## [8.7.0] - 2026-04-29

### Eklendi — Backend Security (3-tier OWASP+ASVS L1)

Sistematik backend güvenlik kapsama: Phase 1.7 design-time + Phase 4.5 post-hoc taxonomic + manuel `/mcl-security-report` keyword. Mevcut Semgrep + secret-scan üstüne kurulan severity-tiered enforcement ile HIGH bulgular Phase 4.5 dialog'unu bloke eder, MEDIUM sequential dialog item olur, LOW audit-only.

#### Yeni dosyalar
- **`hooks/lib/mcl-security-rules.py`** — generic core (G01-G13: SQLi-concat, command-exec-user-input, eval-from-string, hardcoded HIGH-entropy secret, DEBUG flag, CORS wildcard, weak hash, AES-ECB, hardcoded JWT secret, SSRF, path-traversal, insecure-deserialization, weak-TLS) + 7 stack add-on (S-PY-django-allowed-hosts, S-PY-fastapi-cors, S-RX-unsafe-html-setter, S-RX-target-blank-no-rel, S-JV-spring-csrf-disabled, S-RB-rails-strong-params, S-PHP-laravel-debug). Decorator-based registry; her bulgu severity + OWASP + ASVS + category field'ı taşır. **20 rule total.**
- **`hooks/lib/mcl-security-scan.py`** — orchestrator: enumerate, file-SHA1+rules-version composite cache, Semgrep `p/default` çağrı, SCA çağrı, severity routing, lokalize markdown render. Modes: `incremental` (tek dosya, HIGH-only + Semgrep ERROR-only), `full` (tüm proje + Semgrep packs + SCA), `report` (cache bypass).
- **`hooks/lib/mcl-sca.sh`** — SCA wrapper: stack tag'e göre `npm audit --json`, `pip-audit --format json`, `cargo audit --json`, `govulncheck`, `bundle-audit` çağrı; binary yoksa graceful skip + tek-seferlik warning. Tüm finding'ler ortak şemaya normalize edilir.

#### Hook entegrasyonu (8.7.0 MVP)
- **`hooks/mcl-activate.sh`** — `/mcl-security-report` keyword detection bloğu (mevcut `/codebase-scan` mirror'ı). Kullanıcı yazınca pipeline atlanır, Bash tool ile `mcl-security-scan.py --mode=report` çağrılır, lokalize markdown rapor sunulur.

#### Phase 1.7 design-time L1 (5 yeni dimension)
- **8. Auth Model** (OWASP A07): kim çağırabilir, kimlik doğrulama nasıl?
- **9. Authz Unit / Resource-Owner Check** (OWASP A01): BOLA/IDOR — owner check explicit mi? SAST kapsamayan en kritik kategori.
- **10. CSRF Stance** (A01/A05): cookie-session vs bearer-token vs custom flow.
- **11. Secret Management Strategy** (A02): repo (yasak) / env-var / secret manager.
- **12. Deserialization Input Source** (A08): JSON+schema vs YAML/binary-serialization.

Hepsi mevcut SILENT-ASSUME / SKIP-MARK / GATE üçlüsünü kullanır.

#### Phase 4.5 lens (d) genişletme (8.7.0+)

Phase 4.5 START'ta zorunlu güvenlik scan: orchestrator çalışır, severity routing uygulanır:
- **HIGH** → Phase 4.5 START gate, dialog başlamaz; HIGH'lar fix edilene kadar bekle. Bare skip yasak.
- **MEDIUM** → sequential dialog item, `[Security]` etiketiyle.
- **LOW** → audit-only, `security-findings.jsonl`.

Auto-fix: Semgrep safe-category (formatting/rename/import) silent apply. auth/crypto/secret/authz **asla silent**.

#### Coverage matrix

| OWASP | Source | Yer |
|---|---|---|
| A01 Broken Access Control | stack add-on + Phase 1.7 | L1+L3 |
| A02 Cryptographic Failures | generic core | L3 |
| A03 Injection | generic + Semgrep | L3 |
| A04 Insecure Design | Phase 1.7 | L1 only |
| A05 Security Misconfig | stack add-on | L3 |
| A06 Vulnerable Components | SCA tools | L3 |
| A07 Auth Failures | Semgrep + stack | L3 |
| A08 Software/Data Integrity | generic | L1+L3 |
| A09 Logging/Monitoring | Phase 1.7 audit-dim | L1 only |
| A10 SSRF | generic | L3 |

ASVS L1 subset (V2/V3/V4/V5/V6/V7/V8) finding schema'sındaki `asvs` field'ında belirtilir.

### Test sonuçları
- T1 `/mcl-security-report` keyword detection: STATIC_CONTEXT 1019 byte, `MCL_SECURITY_REPORT_MODE` + `--mode=report` mevcut PASS
- T2 Synthetic Python (eval+SQLi+secret+DEBUG+ALLOWED_HOSTS+md5): 3 HIGH (G01+G04+Semgrep sqlalchemy) + 2 MEDIUM (G05+G07) tespit; OWASP/ASVS field'lar dolu PASS
- T3 Lokalizasyon TR: "Yüksek şiddet" / "Orta şiddet" / "Tarama tamamlandı" başlıkları doğru PASS
- T4 Audit log: `security-scan-full | mcl-stop | high=3 med=2 low=0 duration_ms=N sources=generic,stack,semgrep` doğru format PASS
- T5 Mevcut suite: 19 pass / 0 fail / 2 skip — regresyonsuz PASS

### Updated files
- `hooks/lib/mcl-security-rules.py` (yeni, 20 rule)
- `hooks/lib/mcl-security-scan.py` (yeni, orchestrator)
- `hooks/lib/mcl-sca.sh` (yeni, 5 stack tool wrapper)
- `hooks/mcl-activate.sh` (`/mcl-security-report` keyword bloğu)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (5 yeni dimension)
- `skills/my-claude-lang/phase4-5-risk-review.md` (Lens (d) 8.7.0+ expanded section)
- `VERSION` (8.6.0 → 8.7.0)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (kabul edilmiş — 8.7.1 patch'te ele alınacak)

- **Phase 4 incremental L2 hook entegrasyonu MVP'de yok.** Pre-tool Edit/Write/MultiEdit branch'inde HIGH-only quick scan + `decision:deny` mekanizması 8.7.1'e ertelendi. Şu an: Phase 4'te yazılan kod Phase 4.5 START'ta yakalanır; per-Edit blocking yok.
- **Phase 4.5 hard-enforcement hook MVP'de yok.** mcl-stop.sh'a HIGH-bulgu-varsa-`decision:block` mekanizması 8.7.1'e ertelendi. Şu an: HIGH bulgu davranışı **model-behavioral** — phase4-5 skill'i Lens (d) expanded section'da modele talimat verir, Bash + scan + parse + fix yap. Hook seviyesi enforcement yok; geliştirici güvenliği `/mcl-security-report` ile manuel doğrulayabilir.
- **A04 Insecure Design ve A09 Logging/Monitoring** sadece L1 (Phase 1.7) — runtime detection yok (kategorik kapsam dışı).
- **ASVS L1 subset** (V2/V3/V4/V5/V6/V7/V8); L2/L3 kapsam dışı.
- **BOLA/IDOR semantik** — heuristic yalnızca "decorator yokluğu" yakalar; logic flaw'ları yakalayamaz (manuel review).
- **SCA tool yokluğunda** (`pip-audit`, `cargo-audit`, `govulncheck`, `bundle-audit` install edilmemiş) ilgili stack için A06 skip; warning tek seferlik stderr'a düşer.
- **14 dilden yalnızca TR + EN tam lokalize**; diğer 12 dil EN fallback (codebase-scan ile aynı pattern).
- **100k+ mono-repo'da `--mode=full` dakikalarca sürebilir**; cache ilk run'da etkisiz; kullanıcı sorumluluğu.

## [8.6.0] - 2026-04-29

### Eklendi — `/codebase-scan` (Codebase Learning)

Manuel keyword komutuyla projeyi P1-P12 pattern set'iyle tarayan ve otomatik project knowledge çıkaran yeni özellik. Kullanıcı `/codebase-scan` yazar; MCL pipeline'ı atlanır; Python script projeyi tarar; iki dosya üretilir.

#### Çıktılar
- **`$MCL_STATE_DIR/project.md`** — high-confidence bulgular, `<!-- mcl-auto:start -->...<!-- mcl-auto:end -->` marker'ları arasında. Marker dışı bölge (Mimari / Teknik Borç / Bilinen Sorunlar) Phase 5-curated kalır, scan dokunmaz (M3 strategy).
- **`$MCL_STATE_DIR/project-scan-report.md`** — tüm bulgular (high + medium + low), kullanıcı dilinde başlıklarla, evidence path'leri ve detaylarla.

#### Pattern set (12 dimension)

| ID | Çıkardığı | Yöntem |
|---|---|---|
| **P1** Stack | `mcl-stack-detect.sh` tag'leri | subprocess shell source |
| **P2** Mimari | Monorepo (pnpm/lerna/nx/turbo), Clean/MVC layout | top-dir heuristic |
| **P3** Naming | camelCase / snake_case / PascalCase / kebab-case dominant ratio | source sample regex |
| **P4** Error handling | try-catch / Result / raise / panic / throw new dominant | source sample regex |
| **P5** Test | Framework (vitest/jest/pytest/...) + test dirs | manifest dep + dir presence |
| **P6** API style | Express/Fastify/FastAPI/Django/GraphQL/tRPC | manifest dep |
| **P7** State mgmt | Redux/Zustand/Jotai/MobX/Pinia/React-Query/SWR | manifest dep |
| **P8** DB | Prisma/SQLAlchemy/TypeORM/Drizzle/Mongoose + migration dirs | file + manifest |
| **P9** Logging | Winston/Pino/Loguru/structlog vs ad-hoc console/print | manifest dep + sample scan |
| **P10** Lint | TS strict / ESLint / Prettier / Ruff / mypy | config file presence + key fields |
| **P11** Build/deploy | Dockerfile / GH Actions / Vercel / Netlify / Fly | file presence |
| **P12** README intent | İlk paragraf | text extraction |

#### Confidence routing

- **high** → `project.md` marker'lı bölüme yazılır (lokalize başlıklarla: Otomatik: Mimari / Stack & Araçlar / Konvansiyonlar / Test / Diğer)
- **medium / low** → yalnızca `project-scan-report.md`'ye yazılır

#### Lokalizasyon

Script `--lang <iso>` argümanı alır (mcl-activate.sh `MCL_USER_LANG` env'inden geçer, default `tr`). 14 dilden TR ve EN mevcut; diğer diller için EN fallback. Section başlıkları + verdict kelimeleri çevirilir; teknik token'lar (path, dep ismi, framework adı, pattern_id) İngilizce kalır.

#### Tetikleme

`mcl-activate.sh`'ta `/mcl-doctor`/`/mcl-update` ile aynı pattern: `PROMPT_NORM = "/codebase-scan"` eşleşmesi → MCL pipeline skip + Bash tool ile script çağrı talimatı + sonucun olduğu gibi sunulması talimatı. Otomatik tetikleme YOK (kullanıcı kararı).

#### Tarama kapsamı

- Sınırsız derinlik (kullanıcı kararı). Excludes: `.git`, `node_modules`, `dist`, `build`, `.next`, `target`, `vendor`, `.venv`, `__pycache__`, `.cache`, `coverage`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `out`, `.turbo`, `.parcel-cache`, `.svelte-kit`.
- Source extensions: `.ts/.tsx/.js/.jsx/.mjs/.cjs/.py/.rb/.go/.rs/.java/.kt/.swift/.cs/.php/.cpp/.c/.h/.hpp/.lua/.vue/.svelte/.scala/.dart`.
- Manifest set: package.json, pyproject.toml, Cargo.toml, go.mod, Gemfile, pom.xml, build.gradle(.kts), composer.json, Package.swift, mix.exs, deno.json, *.csproj.
- Dosya boyutu cap: 1 MB. Lock dosyaları ve minified asset'ler atlanır.

#### Progress göstergesi

Stderr'a per-pattern ilerleme: `[MCL] Scanning... P3 (3/12)`. Bash tool çıktısında kullanıcı görür.

#### Phase 3.5 ilişkisi (S2 cache-first — partial)

8.6.0'da Phase 3.5 dedicated skill dosyası mevcut değil (Phase 3.5 model-behavioral). Bu nedenle "Phase 3.5 önce project.md cache'ini okur" kuralı **skill düzeyinde** dedicated implementasyona alınamadı. Geçici çözüm: hook STATIC_CONTEXT prose'u Phase 1/3'ten itibaren `project.md` (ve auto bölümü) referans verir; model dosyayı Read edip pattern'leri kullanır. Dedicated `phase3-5-pattern-matching.md` skill'i 8.6.x patch'inde eklenecek (ayrı plan); bu noktaya kadar S2 cache-first behavioral seviyede kalır.

### Test
- T1 `/codebase-scan` keyword detection → MCL_CODEBASE_SCAN_MODE STATIC_CONTEXT inject (1172 byte) PASS
- T2 Self-test: MCL repo'sunda script çalıştı, 9 source dosya, P1+P3+P5+P9+P12 bulguları doğru üretildi PASS
- T3 Marker yok + Phase 5 içerik mevcut → marker'lı bölüm üste enjekte edildi, Mimari/Teknik Borç korundu PASS
- T4 Marker var + ikinci scan → marker arası replace, Phase 5 içeriği dokunulmadı (idempotent) PASS
- T5 TR lang flag → "Yüksek güvenilirlikteki bulgular", "Otomatik: Mimari" başlıkları lokalize PASS
- T6 Mevcut suite 19/0/2 PASS (regresyonsuz)

### Updated files
- `hooks/lib/mcl-codebase-scan.py` (yeni, ~500 satır)
- `hooks/mcl-activate.sh` (`/codebase-scan` keyword block)
- `VERSION` (8.5.0 → 8.6.0)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (kabul edilmiş)

- **100k+ dosyalı dev mono-repo'larda scan dakikalarca sürebilir** — sınırsız derinlik kullanıcı kararı, performance budget yok. Kullanıcı sorumluluğu.
- **Phase 3.5 dedicated skill yok** — S2 cache-first 8.6.0'da behavioral seviyede; dedicated skill 8.6.x'te.
- **14 dil lokalizasyonu kısmi** — TR ve EN tam, diğer 12 dil EN fallback. Tam çeviri sonraki patch.
- **Naming dominant kuralı sınırlı** — 4 kategori (camel/snake/Pascal/kebab) arasında dominant; karışık projeler "low confidence" olarak sınıflandırılır, project.md'ye yazılmaz.

## [8.5.0] - 2026-04-29

### BREAKING — Per-project isolation via wrapper launcher

MCL artık projeye **hiçbir dosya/klasör yazmıyor**. Tüm hook deklarasyonları, state, audit log ve session-context dosyaları `~/.mcl/projects/<sha1(realpath PWD)>/` altında, proje dışında saklanıyor. Kullanım: `claude` yerine `mcl-claude` çalıştır.

#### Yeni mimari
- **Wrapper script** `bin/mcl-claude`: `$PWD`'nin realpath'inden sha1 ile project key türetir, ilk çalıştırmada `~/.mcl/projects/<key>/` scaffolding'ini (settings.json + state/ + meta.json) oluşturur, `MCL_STATE_DIR` env var'ını export eder, sonra `claude --settings <per-project> --plugin-dir <shared-lib> "$@"` ile pass-through `exec` yapar. Saf wrapper — kendi flag'i yok, tüm Claude Code bayrakları transparan geçer.
- **Global installer** `install.sh`: `~/.mcl/lib/`'ye git clone (veya pull) ve `~/.local/bin/mcl-claude` symlink. Idempotent.
- **Plugin manifest** `plugin.json`: minimal manifest — `--plugin-dir` üzerinden Claude Code'un skill/agent discovery'si için tek dosya. Plugin marketplace'a yayın değil.
- **Hook env contract**: hook'lar zaten `MCL_STATE_DIR` env var'ını destekliyordu (8.x boyunca `<CLAUDE_PROJECT_DIR>/.mcl` fallback'i ile). Wrapper bu değeri `~/.mcl/projects/<key>/state` olarak set'ler → tüm state izole, fallback'i bypass eder.
- **`mcl-cost.py`**: `MCL_STATE_DIR` env var'ı varsa onu kullanır, yoksa legacy `<proj>/.mcl/` fallback'i (pre-8.5 install kullanıcıları için).

#### Kaldırılan / değişen
- `setup.sh` **silindi** — projeye dosya yazan eski install kanalı. Yerini `install.sh` (global) aldı.
- Kullanım komutu değişti: `claude` → `mcl-claude`. Bare `claude` artık MCL hook'larını yüklemez (settings injection wrapper'a özel).

#### Migration: yok (M4)
Mevcut kullanıcıların `<proj>/.mcl/` ve `<proj>/.claude/` dizinleri 8.5.0'a geçince orphan kalır. Phase progress / audit log korumak isteyenler manuel taşır:
```bash
cd <project>
mcl-claude  # bir kez çalıştır → ~/.mcl/projects/<key>/ yaratılır
key=$(ls -t ~/.mcl/projects | head -1)  # en son yaratılan
mv .mcl/* ~/.mcl/projects/$key/state/
rm -rf .mcl .claude/settings.json .claude/hooks .claude/skills/my-claude-lang
```

#### Tasarım kararları (referans)
- **Path X** seçildi (`--settings` merge mode), Path Y (`--bare`) değil — kullanıcının `~/.claude/` skills/MCP/statusline ayarı korunur.
- **CLAUDE_CONFIG_DIR yolu reddedildi** — undocumented, GitHub issue #25762 hâlâ açık, davranış hybrid/split. POC ile doğrulandı.
- **Project key K1** (path-sha1) — setup-free, rename-safe değil ama M4 kapsamında kabul.
- **Minimal plugin.json** kabul edildi — düz dizin felsefesini bozmayan tek dosya, Claude Code'un skill discovery'si için zorunlu.

### Test
- Wrapper smoke test: `mcl-claude` stub claude ile çalıştırıldı, doğru bayraklar ve env var'lar geçirildi, proje dizini sıfır footprint, `~/.mcl/projects/<key>/` doğru yaratıldı PASS
- Mevcut suite: 19/0/2 — `MCL_STATE_DIR` zaten destekli olduğundan regresyon yok PASS

### Updated files
- `bin/mcl-claude` (yeni)
- `install.sh` (yeni)
- `plugin.json` (yeni)
- `setup.sh` (silindi)
- `hooks/lib/mcl-cost.py` (`MCL_STATE_DIR` env var önceliği)
- `VERSION` (8.4.2 → 8.5.0)
- `FEATURES.md`, `CHANGELOG.md`

### Bilinen sınırlar (kabul edilmiş)

- **Project rename**: K1 path-sha1 olduğu için proje rename'inde state kaybolur (orphan dir). `mcl-claude --reinit` veya state taşıma komutu MVP'de yok; kullanıcı manuel `mv` yapar.
- **Plugin.json minimum field doğrulaması**: Claude Code'un plugin spec'i değişirse ek field gerekebilir; şu an `name`/`version`/`description` ile çalışıyor.
- **STATIC_CONTEXT prose'unda eski `.mcl/foo` mention'ları**: hook'lar dosya IO'yu doğru path'e yapıyor ama bazı model-facing prose hâlâ `.mcl/cost.json` gibi referanslar içeriyor. Cosmetic (model env var'dan absolute path resolve edebiliyor); 8.5.x patch'inde temizlenecek.

## [8.4.2] - 2026-04-29

### Düzeltildi — Real-use test'in açtığı 3 kalibrasyon sapması

8.4.1 sonrası "kullanıcı listele" prompt'u ile uçtan uca (Phase 1 → 1.7 → 1.5 → 2 → 4.5) synthetic transcript simülasyonunda 4 sapma noktası tespit edildi. Bu patch ilk 3'ünü skill düzeyinde düzeltir; 4. (domain-shape coverage gap) gelecek real-use test prompt önerisi olarak kayıt altına alındı.

#### `skills/my-claude-lang/phase1-5-engineering-brief.md`
- **GATE × default çakışması çözüldü.** Yeni alt bölüm: *"Phase 1.7 GATE answers override implicit defaults"*. Phase 1.7 GATE'i bir verb'ün implicit default'unu override ettiğinde (örn. `paginate` default'u `[default: cursor pagination, changeable]` ama react-frontend GATE'i "page-numbered" cevabı aldıysa) marker `[default: ..., changeable]` yerine `[confirmed: ...]` olur. Phase 3 Scope Changes Callout `[confirmed]` marker'ını reviewable default olarak değil, geliştirici tarafından açıkça onaylanmış parametre olarak gösterir. 2 kalibrasyon örneği eklendi.
- **Implicit layer addition sınır vakası açıklandı.** Calibration Examples tablosuna 2 yeni satır: aynı prompt ("kullanıcı listele") iki Phase 1 context'iyle. Mevcut React + FastAPI context'i ile backend layer mention'ı **allowed** (zaten Phase 1 context'inde); boş context ile **forbidden** (yeni layer eklemiş olur). Boundary açık: layer mention'ı yalnızca Phase 1 confirmed context'inde varsa allowed.

#### `skills/my-claude-lang/phase1-7-precision-audit.md`
- **Sequential GATE asking explicit hale getirildi.** Question Flow step 4 strengthened: birden fazla dimension GATE classify ederse queue'lanır ve **turn'ler arası sırayla** sorulur — aynı response'ta iki GATE sorusu (madde işareti veya numaralı liste ile bile) batch'lenmez. Her GATE cevabı confirm edilip parameter set'e işaretlenmeden sıradaki GATE evaluate edilmez. Mevcut "exactly one question" + "no list of multiple questions" satırı multi-GATE durumunu açıkça kapsıyor şimdi.

### Bilinen sınır (kabul edilmiş, gelecek real-use test'e devredildi)

8.4.1 stack-detect 3 yeni domain-shape tag (cli, data-pipeline, ml-inference) ekledi ama "kullanıcı listele" prompt'u admin panel olduğu için bu tag'leri exercise etmedi. Coverage doğrulaması için 3 ek real-use test prompt'u önerildi:

- **ml-inference test:** *"csv'deki sıralanmamış müşteri tweet'lerini sentiment'a göre etiketle, model `models/sentiment.pkl`"* → `*.pkl` artifact + Python project → `[python, ml-inference]` beklenir.
- **data-pipeline test:** *"günlük satış verisini Snowflake'e taşıyan dbt pipeline'ı kur"* → `dbt_project.yml` veya dependencies'te dbt-core → `[python, data-pipeline]` beklenir.
- **cli test:** *"projedeki TODO yorumlarını listeleyen `find-todos` adında bir CLI yap, npm üzerinden çalışsın"* → `package.json` `bin` field'ı + Phase 4 sonrası → `[typescript, cli]` beklenir.

Bu prompt'lar bir sonraki manuel kalibrasyon turunda (8.4.x) çalıştırılacak; otomatik test fixture'larına dönüştürme şu an scope dışı.

### Updated files
- `skills/my-claude-lang/phase1-5-engineering-brief.md` (GATE override section + 2 calibration örneği)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (Question Flow step 4 strengthened)
- `VERSION` (8.4.1 → 8.4.2)
- `FEATURES.md` (sürüm bumpı)
- `CHANGELOG.md` (bu giriş)

## [8.4.1] - 2026-04-29

### Eklendi — Stack-detect kapsam genişletme

Phase 1.7 stack add-on tarafının coverage'ı genişletildi. Önceki sürümde TS/JS/React tek başlık altındaydı, framework spesifik dimensions yoktu. Backend/system dilleri (Java, C#, Ruby, PHP, C++, Lua) ve domain-shape (cli/data-pipeline/ml-inference) `mcl-stack-detect.sh` tarafından otomatik tespit edilmiyordu.

#### `hooks/lib/mcl-stack-detect.sh`
- **3 yeni domain-shape detect tag** eklendi (dil tag'lerinden ayrı, içerik tabanlı):
  - `cli` — `package.json` içinde `bin` field, `pyproject.toml` içinde `[project.scripts]` veya `[tool.poetry.scripts]`, `Cargo.toml` içinde `[[bin]]`, `go.mod + cmd/`, dolu `bin/` dizini.
  - `data-pipeline` — `airflow.cfg`, `dags/`, `dbt_project.yml`, `prefect.yaml/toml`, ya da `requirements*.txt` içinde apache-beam/pyspark/dagster/dask/luigi.
  - `ml-inference` — `*.pkl/*.onnx/*.pt/*.h5/*.safetensors/*.pb` model artifact'leri, `mlflow/` veya `mlruns/` dizinleri, `model_card.md` / `MODEL.md`, ya da requirements/pyproject içinde torch/tensorflow/transformers/scikit-learn/xgboost/lightgbm/bentoml/mlflow.
- False positive kabul edilmiş risk: domain-shape tag'leri Phase 1.7 dimensions için heuristic — yanlış tetiklendiğinde dimensions hâlâ general enough olduğu için spec kırılmaz.

#### `skills/my-claude-lang/phase1-7-precision-audit.md`
- `### typescript / javascript / react` başlığı `### typescript / javascript` olarak rename edildi (yalnızca web base: modül sistemi, async pattern, package manager, deployment target).
- **10 yeni stack add-on bölümü** yazıldı; her biri 3-5 delta dimension içeriyor:
  - **Frontend frameworks (dedicated):** `react-frontend` (hooks/suspense/RSC/state mgmt), `vue-frontend` (Composition API/Pinia/SFC/SSR), `svelte-frontend` (stores vs runes/server islands/$:/compiler opts), `html-static` (asset bundling/SEO/accessibility/deployment).
  - **Backend dilleri:** `java` (framework/build tool/reactive vs blocking/persistence/version), `csharp` (framework/async pattern/DI/ORM/runtime), `ruby` (framework/ORM/jobs/mode/test framework), `php` (framework/ORM/jobs/version).
  - **Sistem dilleri:** `cpp` (standard/build/memory/concurrency/platform), `lua` (runtime/coroutines/modules/C interop).
- Multi-tag union pattern: React projesi `[typescript, react-frontend]` olarak tespit edilir; framework deltas TS/JS base'inin **üzerine** uygulanır (replace değil).
- Domain-shape add-on'larının TODO comment'leri kaldırıldı — artık `mcl-stack-detect.sh` 8.4.1 ile otomatik tetikliyor.
- Solid/Angular/Qwik ve kotlin-mobile vs kotlin-backend ayrımı gelecek genişleme için TODO olarak işaretlendi.

#### `skills/my-claude-lang/all-mcl.md`
- STEP-64 description'ı 8.4.1 stack coverage genişlemesi notunu içerecek şekilde güncellendi.

### Test
- T1 phase1-7 skill'inde 13+ `### ` başlık (en az 11 add-on + 2 yapısal) PASS
- T2 stack-detect.sh içinde `_mcl_is_cli/_mcl_is_dp/_mcl_is_ml=1` flag'leri PASS
- T3 TS/JS başlığı rename edildi PASS
- T4 Tier 1 sections (vue/svelte/react-frontend/java/csharp/ruby) mevcut PASS
- T5 Tier 2 sections (php/cpp/lua/html-static) mevcut PASS
- T6 mevcut suite: 19 pass, 0 fail, 2 skip — regresyonsuz
- T7 fixture: `package.json` `"bin"` field → `cli` + `javascript` tag (multi-tag union doğrulandı) PASS
- T8 fixture: `requirements.txt` `torch==2.1.0` → `ml-inference` + `python` tag PASS
- T9 fixture: `dbt_project.yml` → `data-pipeline` tag PASS

### Updated files
- `hooks/lib/mcl-stack-detect.sh` (csharp detect block sonrasına 3 domain-shape detect bloğu eklendi)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (TS/JS rename + 10 yeni section)
- `skills/my-claude-lang/all-mcl.md` (STEP-64 description)
- `VERSION` (8.4.0 → 8.4.1)
- `FEATURES.md` (Stack add-on'lar listesi 8.4.1 genişletmesini yansıtıyor)
- `CHANGELOG.md` (bu giriş)

## [8.4.0] - 2026-04-29

### Değişti — Phase 1.5 contract (BREAKING)
- **Phase 1.5 artık upgrade-translator.** 8.3.x'e kadar Phase 1.5'in tek görevi user_lang → İngilizce sadık çeviriydi (`do NOT add scope, do NOT subtract scope`). 8.4.0'da bu sözleşme bilinçli olarak gevşetildi: brief artık vague verb'leri (`list`, `listele`, `show`, `göster`, `manage`, `yönet`, `process`, `işle`, `build`, `yap`, `handle`, `update`, ...) surgical English verb'lere yükseltir (`render a paginated table`, `expose CRUD operations`, `implement`, `transform`, vb.). Verb-implied standart default'lar `[default: X, changeable]` marker'larıyla annotate edilir.
- **Mission rationale:** ana hedef "İngilizce bilmeyen geliştiriciyi senior İngilizce seviyesine çıkarmak". Approach A (Phase 1.7'ye 8th dimension) ve Approach B (Phase 1.5 upgrade-translator) trade-off değerlendirmesinden sonra B seçildi — kullanıcıyı her vague verb için soruyla yormak yerine çıktıyı senior precision'a otomatik yükseltmek hedefe daha doğrudan hizmet ediyor.

### Eklendi — Hallucination guards (3 katmanlı)
- **Skill calibration:** [`phase1-5-engineering-brief.md`](skills/my-claude-lang/phase1-5-engineering-brief.md) tamamen yeniden yazıldı. Allowed Upgrades tablosu (14-dil verb mapping), Forbidden Additions hard prohibitions listesi, 13 calibration example (allowed vs forbidden upgrade çiftleri).
- **Phase 3 Scope Changes Callout:** [`phase3-verify.md`](skills/my-claude-lang/phase3-verify.md) güncellendi. `engineering-brief audit upgraded=true` olduğunda Phase 3 prose'unda zorunlu callout — geliştirici kendi dilinde her upgrade'i görür, "edit" ile düzeltebilir. Format Türkçe örnek + 14-dil localizable.
- **Phase 4.5 Lens (e) Brief-Phase-1 Scope Drift:** [`phase4-5-risk-review.md`](skills/my-claude-lang/phase4-5-risk-review.md) güncellendi. Mevcut 4 lens (Code Review/Simplify/Performance/Security) yanına 5. lens eklendi. `upgraded=true` olduğunda zorunlu çalışır: Phase 4 implementation'ın her elementi Phase 1 confirmed parameter'a izlenebilir mi VEYA `[default: X, changeable]` marker'ı taşıyor mu kontrol; izlenemeyen + marker'sız element `[Brief-Drift]` risk olarak risk-dialog'a surface — geliştirici 3 seçenekten birini seçer (remove / mark-as-default / rule-capture).

### Audit format extension
- `engineering-brief | phase1-5 | lang=<...> skipped=<...> retries=<...> clarification=<...> upgraded=<true|false> verbs_upgraded=<count>` — yeni alanlar `upgraded` (en az bir verb upgrade edildi mi) ve `verbs_upgraded` (kaç verb).

### Updated files
- `skills/my-claude-lang/phase1-5-engineering-brief.md` — major rewrite (faithful → upgrade-translator)
- `skills/my-claude-lang/phase4-5-risk-review.md` — Lens (e) eklendi
- `skills/my-claude-lang/phase3-verify.md` — Scope Changes Callout eklendi
- `hooks/mcl-activate.sh` STATIC_CONTEXT — Phase 1.5 prose'u upgrade-translator olarak güncellendi (JSON-safe escape: backtick yerine literal backtick kullanıldı, embedded double quotes kaldırıldı)
- `skills/my-claude-lang/all-mcl.md` — STEP-58 audit format ve description'ı güncellendi
- `FEATURES.md` — Phase 1.5 contract change bölümü eklendi

### Test
- T1 skill `phase1-5-engineering-brief.md` Allowed/Forbidden/Calibration sections var PASS
- T2 skill `phase4-5-risk-review.md` Lens (e) + Brief-Drift label var PASS
- T3 skill `phase3-verify.md` Scope Changes Callout + trigger var PASS
- T4 STATIC_CONTEXT 8.4.0 upgrade-translator instruction var PASS
- T5 STEP-58 audit format `upgraded=` ve `verbs_upgraded=` field'larını içeriyor PASS
- T6 mevcut suite: 19 pass, 0 fail, 2 skip — regresyonsuz (JSON validity testleri kritikti; STATIC_CONTEXT prose'unda embedded `"Scope Changes"` literal quote'ları JSON parse'i kırıyordu, kaldırıldı — `Scope-Changes callout` formatına geçildi)

### Bilinen sınırlar (kabul edilmiş, CHANGELOG'a kayıt)
- **Phase 5.5 asimetri:** input-side upgrade (1.5) ama output-side faithful (5.5). Phase 5 raporunun geliştirici diline geri çevirisinde teknik kelime kaybı olabilir; spec ve audit trail surgical İngilizce'de korunur. Phase 4.5 Lens (e) gerçek scope drift'i yakalar.
- **Determinist disiplin değil:** upgrade kararı model semantic judgment'ına bağlı. Hedefin "deterministic AI discipline" yarısıyla değil, "senior precision" yarısıyla uyumlu. 3 katmanlı hallucination guard bu trade-off'u dengeleme amaçlı.
- **Hallucination edge cases:** "build login page" gibi eşik durumlar — skill calibration table boundary'i çiziyor ama her olası prompt için açıkça listelenmiyor. Phase 4.5 Lens (e) post-hoc safety net.
- **Behavioral test:** real-use validation manual (T7 spawn'lanmamış); sonraki sessionda gerçek prompt'la doğrulanacak.

## [8.3.3] - 2026-04-29

### Eklendi
- **Plan critique substance validation — subagent-driven gate (Gap #5).** 8.2.10 plan-critique gate Task çağrısının şeklini kontrol ediyordu (subagent_type=general-purpose + model=sonnet); `Task(prompt="say hi")` bypass'a açıktı. 8.3.3 niyet doğrulamasıyla bu açığı kapatır:
  - **`agents/mcl-intent-validator.md` (yeni)** — strict gate-keeper subagent. Sonnet 4.6 ile çalışır, prompt'u değerlendirir, single-line JSON `{"verdict":"yes"|"no","reason":"..."}` döner. Default bias: NO unless evidence is clear. Reversal pattern, trivial request, off-topic content tespit edilir.
  - **`hooks/mcl-pre-tool.sh`** — Task gate (8.2.10 shape check) substance-aware oldu: general-purpose+sonnet Task yakalandığında transcript'i tarayıp en son `Task(subagent_type=*mcl-intent-validator*)` çağrısının tool_result'ını parse eder. JSON verdict'ine göre 4 yol: `yes` → allow + state=true; `no` → `decision:block` + reason aktarımı; validator çağrılmamış → `decision:block` + "dispatch validator first" talimatı; malformed output → fail-open + `intent-validator-parse-error` audit warn.
  - **Recursion-safety:** validator agent kendi `subagent_type`'ını kullandığı için pre-tool'un general-purpose gate'i ile çakışmaz. Validator'ın Task çağrısı pre-tool'dan geçer, sonsuz loop yok.
  - **`setup.sh`** — yeni install adımı: `agents/mcl-*.md` → `~/.claude/agents/`. Sadece MCL prefix'li agent'lar kopyalanır (user agent çakışmasını önlemek için).
  - **STATIC_CONTEXT (`mcl-activate.sh`)** — `PLAN_CRITIQUE_PENDING_NOTICE` metnine 8.3.3 talimatı eklendi: "Before general-purpose plan critique Task, dispatch `Task(subagent_type='mcl-intent-validator', prompt=<same>)` first."
  - **STEP-65** — `all-mcl.md`'ye yeni: signal/pass/skip detayları, 4 audit event tipi (`plan-critique-done | intent_validated`, `plan-critique-substance-fail | intent=no|validator=not-called`, `intent-validator-parse-error`).

### Failure modes (kasıtlı tasarım)
- **Validator agent yüklü değil:** Claude Code "agent not found" → tool_result error → parse-error → fail-open. mcl check-up audit pattern'i ile yakalanır, kullanıcı setup tetikler.
- **Validator çağrılmamış:** fail-CLOSED, deterministic block (gate amacı bu).
- **Validator verdict=no:** fail-CLOSED, reason kullanıcıya iletildi.
- **Validator malformed JSON output:** fail-OPEN, audit warn. Runtime gürültüsünde kullanıcıyı kilitleme.

### Test
- T1 validator yes verdict → general-purpose Task allowed, state=true, audit `intent_validated` PASS
- T2 validator no verdict → `decision:block` + reason carried + state=false PASS
- T3 no validator call (boş transcript) → `decision:block` + `validator=not-called` audit PASS
- T4 validator returned malformed JSON → fail-open: state=true, `intent-validator-parse-error` audit, no block PASS
- T5 validator returned `{"verdict":"yes"}` (reason field eksik) → allow (verdict yeterli) PASS
- T6 iki sıralı validator (eski no, yeni yes) → en son yes alınır, allow PASS
- T7 mevcut suite: 19 pass, 0 fail, 2 skip — regresyonsuz

### Bilinen sınır
- **Setup gereksinimi:** `~/.claude/agents/` altına agent kopyalanmadıysa (setup.sh çalıştırılmamış) ilk plan-critique fail-open path'inden geçer; mcl check-up ile farkedilir. Acceptable v1 davranışı.
- **Sonnet self-leniency:** validator strict bias verilse de %100 değil. Adversarial coordinated bypass teorik mümkün; cost-benefit analizi pahalı bypass'ı düşük olasılık yapıyor.
- **Tek-tur akış:** validator + general-purpose Task aynı turda sıralı dispatch edilmeli; multi-turn akışlar henüz desteklenmiyor.

## [8.3.2] - 2026-04-29

### Değişti
- **Phase 1.7 Precision Audit hard-enforced (Phase 4.5 tier).** 8.3.0'da skip-detection-only olarak çıkmıştı (audit-only warn). Determinist AI disiplini hedefini doğrudan etkilediği için decision:block enforcement'a yükseltildi:
  - `mcl-stop.sh` `case 1)` (Phase 1→2 transition) branch'inde, `📋 Spec:` block emit edildi AND audit log'da current session içinde `precision-audit` entry yoksa: state mutation atlanır (transition rewind), `decision:block` JSON stdout'a yazılır, hook çıkar. Claude aynı response içinde Phase 1.7'i çalıştırıp spec'i precision-enriched parametrelerle yeniden emit etmek zorunda.
  - İki audit event yazılır: `precision-audit-skipped-warn | mcl-stop.sh | summary-confirmed-but-no-audit` (8.3.0 backward compat) + `precision-audit-block | mcl-stop.sh | summary-confirmed-but-no-audit; transition-rewind` (yeni 8.3.2 enforcement).
  - **English-language safety valve:** detected language English ise `mcl_audit_log "precision-audit" "phase1-7" "core_gates=0 stack_gates=0 assumes=0 skipmarks=0 stack_tags= skipped=true"` emit edilir → block clear olur. STATIC_CONTEXT'te ve skill dosyasında prose ile İngilizce yolu belgelendi.
  - **Recovery:** false-positive durumunda `/mcl-restart` ile state temizlenir; `mcl-pre-tool.sh` zaten direct state.json bash yazımlarını blokluyor (state-machine bypass yok).

### Test
- T1 spec emit + audit yok + non-English → `decision:block` fire, state phase=1 kaldı, her iki audit event yazıldı PASS
- T2 spec emit + `precision-audit ... skipped=false` audit + non-English → block YOK, transition phase=2 PASS
- T3 KRİTİK: spec emit + `skipped=true` audit (English skip path) → block YOK, transition gerçekleşti, ne skip-warn ne block audit yazıldı PASS — İngilizce kullanıcılar block görmüyor doğrulandı
- T4 already-phase-2 (re-emit spec same session) → case 1) fire etmez, block path atlanır PASS
- T5 mevcut test suite: 19 pass, 0 fail, 2 skip — regresyonsuz

### Güncellenen dosyalar
- `hooks/mcl-stop.sh` — case 1) branch'ine block emit + audit + exit eklendi
- `skills/my-claude-lang/phase1-7-precision-audit.md` — "Enforcement (since 8.3.2)" + "Recovery" bölümleri
- `skills/my-claude-lang/all-mcl.md` — STEP-64 güncellendi: hard-enforcement açıklaması, English safety valve, iki audit event signal
- `hooks/mcl-activate.sh` STATIC_CONTEXT — Phase 1.7 prose'u "stop hook will block-and-rewind otherwise" + İngilizce safety valve cümlesi eklendi

## [8.3.1] - 2026-04-29

### Dokümantasyon
- **Phase 1.7 skill dosyasına "Scope and Extensibility" bölümü eklendi.** Stack add-on listesindeki spesifik dil/framework isimleri (TypeScript, Python, Go, Rust, Swift, Kotlin, vb.) örnektir — kapsamlı değildir. MCL evrensel bir araçtır: 7 core dimension her projede sabit kalır, stack add-on katmanı `mcl-stack-detect.sh` tag'lerine göre veri-odaklı genişler. Yeni stack tag eklendiğinde bu dosyaya yeni section eklenir; classification engine logic değişmez. Mevcut listeler korundu, sadece çerçeveleme netleştirildi.

## [8.3.0] - 2026-04-29

### Eklendi
- **Phase 1.7 — Precision Audit (yeni faz, ana misyon).** Phase 1'in "completeness" disiplinini "precision" ile tamamlar. Senior İngilizce geliştiricinin analitik düşünme davranışını sistemleştirir: confirmed Phase 1 parametreleri için 7 core boyut + stack-detect-driven add-on boyutları walk edilir.
  - **Core 7 boyut:** Permission/access, algorithmic failure modes, out-of-scope boundaries, PII handling, audit/observability, performance SLA, idempotency/retry. UX state'ler (empty/loading/error UI) **core'da DEĞİL** — UI stack add-on'larında.
  - **3 sınıflandırma:** SILENT-ASSUME (`[assumed: X]`), **SKIP-MARK** (yeni 3. kategori — `[unspecified: X]`, şu an yalnızca Performance SLA için), GATE (tek soru sor, one-question-at-a-time rule).
  - **Stack add-on'lar:** typescript/javascript/react, python, go/rust, cli, data-pipeline, mobile, ml-inference. Vue/Svelte/Angular ayrımı v1'de tek TS/JS/React başlığı altında — skill dosyasında TODO comment ile gelecek genişleme işaretli.
  - **English session skip:** `skipped=true` audit ile no-op (behavioral prior yeterli kabul).
  - **Detection control:** `mcl-stop.sh` Phase 1→2 transition'ında audit'te `precision-audit` yoksa `precision-audit-skipped-warn` yazar.
- **Files:** `skills/my-claude-lang/phase1-7-precision-audit.md` (yeni skill, 7 core dim + 7 stack add-on + sample questions); `skills/my-claude-lang.md` (pointer satırı); `skills/my-claude-lang/all-mcl.md` (STEP-64); `hooks/mcl-activate.sh` STATIC_CONTEXT (Phase 1 → 1.7 → 1.5 → 2 sıralaması); `hooks/mcl-stop.sh` (skip-detection bloğu Phase 1→2 case branch'inde).

### Test
- Skill dosyası mevcut, 7 core dim + 7 stack section + SKIP-MARK + Vue/Svelte TODO PASS
- Pointer line `skills/my-claude-lang.md`'de PASS
- STEP-64 `all-mcl.md`'de PASS
- Skip-detection: spec emit + audit boş → `precision-audit-skipped-warn` yazıldı PASS
- Skip-detection: spec emit + `precision-audit` audit var → warn yazılmadı PASS
- English session skip: `skipped=true` audit → warn yazılmadı PASS
- Stack tag listesi (7 add-on) skill dosyasında doğrulandı PASS
- Mevcut test suite: 19 pass, 0 fail, 2 skip — regresyonsuz

### Out of scope (gelecek iterasyonlar)
- `PRECISION_AUDIT_PENDING_NOTICE` activate hook injection — v1'de behavioral + audit detection yeterli kabul edildi. Gerekirse v2'de eklenir.
- `precision_audit_done` state field — v1'de behavioral phase, audit-driven detection. Yeni state field eklenmedi.
- Per-project dimension override (`.mcl/precision-config.json`) — v1: skill dosyası tek truth source.
- Vue/Svelte/Angular framework-specific stack add-on'ları — TODO comment skill dosyasında.

## [8.2.13] - 2026-04-29

### Düzeltildi
- **`/mcl-restart` JIT defeat bug.** Aynı session içinde `/mcl-restart` çağrıldığında JIT promote (pre-tool 482-485), transcript'te hâlâ duran pre-restart spec-approve askq'sini bularak state'i `phase=4, spec_approved=true, spec_hash=<old>` olarak geri alıyordu. Stop hook "askq-idempotent" branch'inde sessiz kaldığı için düzeltme yapmıyordu. Sonuç: developer'ın restart kararı görsel olarak başarılı, gerçekte etkisiz.
- **Çözüm — `restart_turn_ts` filter:**
  - `hooks/lib/mcl-state.sh`: default state'e `restart_turn_ts: null` field eklendi.
  - `hooks/mcl-activate.sh`: `/mcl-restart` branch'i `restart_turn_ts=$(date +%s)` yazıyor; session boundary reset listesine `restart_turn_ts null` eklendi.
  - `hooks/lib/mcl-askq-scanner.py`: opsiyonel ikinci CLI argv'i (`min_ts_epoch`) eklendi. Transcript entry'sinin `timestamp` ISO 8601 alanı parse edilip epoch'a çevrilir; min_ts'ten önce olan girişler atlanır. Defansif: timestamp parse edilemezse entry korunur.
  - `hooks/mcl-pre-tool.sh` JIT bloğu + `hooks/mcl-stop.sh` askq scanner çağrısı `restart_turn_ts` değerini scanner'a geçirir.

### Test
- T1 `/mcl-restart` → `state.restart_turn_ts` epoch integer set PASS
- T2 Scanner direct: pre-restart askq + min_ts > entry ts → `intent=""` (filtrelendi) PASS
- T3 E2E: pre-restart askq + `/mcl-restart` + Write → JIT mutate etmedi, state phase=1 kaldı, Write phase gate ile bloklandı (`deny-tool`), `askq-advance-jit` audit YOK PASS
- T4 E2E: pre-restart askq + `/mcl-restart` + FRESH spec + FRESH approve askq + Write → JIT fresh askq'yi seçti (post-restart timestamp), promote edildi, audit'te `askq-advance-jit` VAR PASS
- T5 Mevcut suite: 19 pass, 0 fail, 2 skip — regresyonsuz PASS

### Bilinen takip — out of scope
- **Stop hook plaintext-approve fallback bug.** `mcl-stop.sh` 244-294 satırlarındaki "plaintext approve fallback" kodu transcript'in son user mesajını okur ve `onayla/yes/approve` gibi free-text approve word geçiyorsa askq olmadan da `ASKQ_INTENT=spec-approve` synthesize eder. Bu kod yolu scanner kullanmıyor — `restart_turn_ts` filter etkilemiyor. `/mcl-restart` sonrası user yeni bir mesajda "approve" derse veya eski yapay-onay metnini içeren bir mesaj zincirleme tespit edilirse aynı defeat yaşanabilir. Ayrı fix gerektirir; bu release'in scope'unda değil. (Takip için spawn_task açıldı.)

## [8.2.12] - 2026-04-29

### Dokümantasyon
- **Bilinen sınırlama: post-tool hook race in parallel tool batches.** Claude Code resmi hook lifecycle belgesine göre `PreToolUse` hook'ları serileşik fire eder (race yok), ancak `PostToolUse` hook'ları async ve non-deterministic sırada fire eder — paralel tool batch'inde 2+ post-tool süreci aynı anda `state.json` yazabilir. `mcl-state.sh::_mcl_state_write_raw` tmp+rename atomik ama field-level merge yapmaz, dolayısıyla `mcl-post-tool.sh`'in yazdığı `last_write_ts` ve `regression_block_active` alanları için race noktası mevcut.
- **Etki seviyesi düşük-orta:** `last_write_ts` kaybı yalnızca regression-guard smart-skip'i etkiler (perf, korrektlik değil); `regression_block_active=false` kaybı `mcl-stop.sh`'in regression-guard re-evaluation'ı ile sonraki turda telafi edilir (eventual consistency).
- **Mitigasyon kasıtlı eklenmedi.** flock veya field-merge complexity > value değerlendirildi. Kaynak: [code.claude.com/docs/en/hooks.md](https://code.claude.com/docs/en/hooks.md).
- **`FEATURES.md`'ye "Bilinen Sınırlamalar / Known Limitations" bölümü eklendi** — race senaryosu somut bir örnekle dokümante edildi (paralel `Write` + `Bash` GREEN), etki analizi ve mitigasyon kararı kayıt altına alındı.

## [8.2.11] - 2026-04-29

### Eklendi
- **Session Context Bridge — cross-session bilgi köprüsü (`mcl-stop.sh`, `mcl-activate.sh`, `all-mcl.md`):**
  - **Hook (`mcl-stop.sh`):** `trap EXIT` ile her Stop'ta (early-exit'ler dahil) `.mcl/session-context.md` yazılır. Markdown 4-6 satır: aktif faz + spec hash kısa hex, son commit SHA + subject (60 char trim), state-driven sıradaki adım (`phase_review_state`/`pattern_scan_due`/`plan_critique_done`/phase numarası kural tablosu), opsiyonel yarım plan veya Phase 4.5 başlatılmamış uyarısı. Atomic write (tmp + rename). Git project dir'de çalıştırılır (`CLAUDE_PROJECT_DIR` veya cwd) — non-git projelerde commit satırı omit edilir.
  - **Auto-display (`mcl-activate.sh`):** Session boundary'de (`SESSION_ID != plugin_gate_session`) `.mcl/session-context.md` okunur ve `SESSION_CONTEXT_NOTICE` olarak `<mcl_audit name="session-context">` bloğuyla `additionalContext`'e enjekte edilir. Aynı session içinde re-inject yok. JSON-safe escape (`\\\"` + `\\n`).
  - **STEP-63:** `skills/my-claude-lang/all-mcl.md`'ye `session-context-bridge` adımı eklendi. `audit.log`'da `session-context-injected` event ile pass koşulu doğrulanır.

### Test
- Stop → `.mcl/session-context.md` oluşturulur (trap EXIT) PASS
- Phase 4 + spec hash → "Aktif iş: Phase 4 (EXECUTE) — spec abc12345" satırı PASS
- `phase_review_state="pending"` → "Sıradaki adım: Phase 4.5 risk review başlat" + "Yarım iş: Phase 4.5 başlatılmadı" satırları PASS
- Plan dosyası + `plan_critique_done=false` → "Yarım plan: .claude/plans/myplan.md — critique pending" satırı PASS
- Yeni session boundary → `SESSION_CONTEXT_NOTICE` enjekte edildi PASS
- Aynı session devam → notice yok (boundary-only) PASS
- Mevcut test suite: 19 pass, 0 fail, 2 skip — regresyonsuz

## [8.2.10] - 2026-04-29

### Eklendi
- **Gap 3 — Plan critique subagent enforcement trinity (`mcl-state.sh`, `mcl-pre-tool.sh`, `mcl-activate.sh`, `mcl-stop.sh`):**
  - **State schema:** `plan_critique_done: false` alanı eklendi (`mcl-state.sh` default state). Session boundary'de `mcl-activate.sh` resetler.
  - **Hook (`mcl-pre-tool.sh`):** İki intercept eklendi: (a) `Task` çağrısı `subagent_type=*general-purpose*` + `model=*sonnet*` ise `plan_critique_done=true` set edilir; (b) `ExitPlanMode` çağrısı `plan_critique_done=false` durumundayken `decision:block` ile reddedilir, audit `plan-critique-block | tool=ExitPlanMode plan_critique_done=false` yazılır. Block reason'ı Claude'a `Task(general-purpose, sonnet)` çağırmasını söyler.
  - **Reset on plan-file Write/Edit:** `mcl-pre-tool.sh` end-of-flow'a yeni blok eklendi — Write/Edit/MultiEdit `*/.claude/plans/*.md` veya `.claude/plans/*.md` patterni'ne uyduğunda `plan_critique_done=false` resetlenir. Plan içeriği değiştiyse yeni critique gerekir.
  - **Auto-display (`mcl-activate.sh`):** Her turda `.claude/plans/*.md` dosyası varsa ve `plan_critique_done!=true` ise `PLAN_CRITIQUE_PENDING_NOTICE` enjekte edilir. Pre-tool gate'in proaktif sinyali — Claude'a critique yapmadan ExitPlanMode'un bloklanacağı önceden bildirilir.
  - **Meta-control (`mcl-stop.sh`):** Eğer son assistant turda `ExitPlanMode` tool_use var VE state hâlâ `plan_critique_done=false` ise audit'e `plan-critique-skipped-warn | tool=ExitPlanMode plan_critique_done=false` yazılır. Pre-tool blokladıysa state değişmemiş olur — defense-in-depth.

### Test
- ExitPlanMode + plan_critique_done=false → `decision:block` + audit PASS
- Task(general-purpose, sonnet) → state=true → ExitPlanMode passes PASS
- Plan exists + state=false → `PLAN_CRITIQUE_PENDING_NOTICE` injected PASS
- Plan exists + state=true (same session) → notice yok PASS
- Write to .claude/plans/foo.md (Phase 4) → state false'a resetlenir + audit PASS
- Stop ExitPlanMode + state=false → `plan-critique-skipped-warn` audit PASS
- Stop ExitPlanMode + state=true → audit warn yok PASS
- Block decision JSON valid + activate JSON valid PASS
- Mevcut test suite (19 pass, 0 fail, 2 skip) regresyonsuz

## [8.2.9] - 2026-04-29

### Eklendi
- **Gap 2 expansion — Root cause chain enforcement all-mode scope (`mcl-activate.sh`, `mcl-stop.sh`, `all-mcl.md`):**
  - **Activate user-message trigger:** 14 dilli heuristik keyword seti (`neden`, `çalışmıyor`, `bug`, `why`, `broken`, `error`, vb. — TR/EN/ES/FR/DE/JA/KO/ZH/AR/HE/HI/ID/PT/RU) `PROMPT_NORM` içinde substring match edilir. Eşleşirse `ROOT_CAUSE_DISCIPLINE_NOTICE` enjekte edilir. Plan-mode tetikleyici varsa o kazanır (yeni blok `[ -z "$ROOT_CAUSE_DISCIPLINE_NOTICE" ]` guard'ı ile atlanır) — tek audit, tek inject. Yeni audit detail: `source=user-message`.
  - **Stop always-on scan:** `mcl-stop.sh`'a Gap 2 ExitPlanMode bloğunun yanında ikinci scan eklendi. Her turda transcript'ten son user mesajı + son assistant text+tool inputs okunur. User mesajında trigger varsa assistant 3 keyword çifti için (EN/TR) taranır; eksikse audit `root-cause-chain-skipped-warn | source=all-mode missing=<list>`. Trigger yoksa scan atlanır (no audit). 8.2.8 ExitPlanMode bloğu bit-for-bit korundu — iki blok aynı turda fire edebilir, `source=` alanıyla ayırt edilir, auto-display her ikisini de yakalar.
  - **STEP-62 güncellendi:** Phase satırı `Plan-mode (devtime) + Any turn (user-message trigger, since 8.2.9)`. Signal/Pass/Skip bölümleri yeni `source=user-message` ve `source=all-mode` audit alanlarıyla detaylandırıldı.

### Test
- TR trigger user-message (`bu neden çalışmıyor`) → notice + `source=user-message` audit PASS
- EN trigger user-message (`the login is broken`) → notice PASS
- Plan file + user trigger aynı anda → tek audit, plan-mode kazanır PASS
- Nötr prompt → notice/audit yok PASS
- Stop always-on: TR trigger + 3 check eksik → `source=all-mode missing=...` audit PASS
- Stop always-on: trigger + 3 EN check var → warn yok PASS
- Stop always-on: trigger yok → scan atlanır, warn yok PASS
- Gap 2 ExitPlanMode bloğu regression: hala `missing=...` (source field yok) yazıyor PASS
- Activate JSON valid (4 case: no notice / user-msg / plan-mode / both) PASS
- Mevcut test suite: 19 pass, 0 fail, 2 skip (regresyonsuz)

### Bilinen risk (kabul edilmiş)
- Common-word false positives (`fail`, `error`, `bug`, `issue` EN'de çok yaygın): notice non-blocking olduğundan kabul edildi.

## [8.2.8] - 2026-04-29

### Eklendi
- **Gap 2 — Root cause chain enforcement trinity (`mcl-activate.sh`, `mcl-stop.sh`, `all-mcl.md`):**
  - **Hook (`mcl-activate.sh`):** `.claude/plans/*.md` dosyalarından biri current session içinde (son `session_start` event'inden sonra) modify edildiyse `ROOT_CAUSE_DISCIPLINE_NOTICE` `additionalContext`'e enjekte edilir. Notice metni Claude'a plan turn'unda 3 check'i (visible process / removal test / falsification) görünür şekilde yazmasını söyler.
  - **Meta-control (`mcl-stop.sh`):** Son assistant turun'da `ExitPlanMode` tool_use varsa, turun text content'i + tool input'ları case-insensitive olarak üç keyword çifti için taranır (EN OR TR per pair): `removal test` / `kaldırma testi`, `falsification` / `yanlışlama`, `visible process` / `görünür süreç`. Bir çiftin ne EN ne TR formu bulunamazsa audit'e `root-cause-chain-skipped-warn | mcl-stop.sh | missing=<list>` yazılır.
  - **Auto-display (`mcl-activate.sh`):** Audit log'da current session içinde `root-cause-chain-skipped-warn` entry'si varsa `ROOT_CAUSE_CHAIN_WARN_NOTICE` enjekte edilir — Claude'a planı yeniden 3 check'le birlikte emit etmesini söyler.
  - **STEP-62:** `skills/my-claude-lang/all-mcl.md`'ye `root-cause-chain-discipline` adımı eklendi.

### Test
- Plan file mtime + activate hook → ROOT_CAUSE_DISCIPLINE_NOTICE PASS
- ExitPlanMode + keyword yok → audit warn PASS
- ExitPlanMode + EN keyword'lar → warn yok PASS
- ExitPlanMode + TR keyword'lar → warn yok (TR pattern eşleşiyor) PASS
- Activate JSON valid + WARN notice present (audit fired) PASS
- Mevcut test suite (19 pass, 0 fail, 2 skip) regresyonsuz

## [8.2.7] - 2026-04-29

### Eklendi
- **Gap 1 — Phase 5 skip detection trinity (`mcl-stop.sh`, `mcl-activate.sh`, `all-mcl.md`):**
  - **Hook (`mcl-stop.sh`):** Stop hook her turda `phase_review_state` kontrol eder. State `running` ise ve bu turda MCL prefix'li AskUserQuestion çalışmamışsa (`ASKQ_INTENT` boş — Phase 4.5/4.6 dialog'u devam etmemiş), audit'e `phase5-skipped-warn | mcl-stop.sh | phase_review_state=running` yazar. State-driven tespit (transcript taraması yok) → anormal session exit'lerinde de skip yakalanır.
  - **Meta-control (4 hook):** `mcl-stop.sh`, `mcl-activate.sh`, `mcl-pre-tool.sh`, `mcl-post-tool.sh` her başarılı çalışmada `.mcl/hook-health.json`'a kendi alanını (`stop`, `activate`, `pre_tool`, `post_tool`) epoch timestamp olarak yazar. Atomic write (tmp + rename). `mcl check-up` STEP-61 eksik veya 24 saatten eski bir alan görürse WARN — hook'un settings.json'dan düşmüş veya sessizce başarısız olduğunu yakalar.
  - **Auto-display (`mcl-activate.sh`):** `audit.log`'da current session (son `session_start` event'inden sonra) `phase5-skipped-warn` entry'si varsa `PHASE5_SKIP_NOTICE` `additionalContext`'e enjekte edilir. Pattern `REGRESSION_BLOCK_NOTICE`'a benzer — Claude bir sonraki turda Phase 5 Doğrulama Raporu'nu çalıştırmaya yönlendirilir.
  - **STEP-60 + STEP-61:** `skills/my-claude-lang/all-mcl.md`'ye iki yeni adım: `phase5-skip-detection` (Stop fazında) ve `hook-health-check` (mcl check-up fazında).

### Test
- `phase_review_state="running"` set + `mcl-stop.sh` → audit `phase5-skipped-warn` PASS
- `phase_review_state=null` set + `mcl-stop.sh` → audit warn yok PASS
- `hook-health.json` sil + 4 hook çalıştır → tüm 4 alan yazılı PASS
- `mcl-activate.sh` JSON çıktısı geçerli (clean + audit warn aktif) PASS
- Mevcut test suite (19 pass, 0 fail, 2 skip) regresyonsuz

## [8.2.6] - 2026-04-28

### Değişti
- **`mcl_get_active_phase()` migration — 4 çift-okuma noktası:**
  - `mcl-stop.sh:374-376`: Phase Review Guard'daki `current_phase` + `spec_approved` çift okuması kaldırıldı, `mcl_get_active_phase()` ile değiştirildi
  - `mcl-stop.sh:474`: Pattern scan early clearance'daki `current_phase` okuması kaldırıldı
  - `mcl-stop.sh:802`: Pattern scan late fallback'deki `current_phase` okuması kaldırıldı
  - `mcl-activate.sh:353-354`: Respec Guard'daki `spec_approved + current_phase >= 4` Python inline okuması kaldırıldı
  - Tüm noktalar `grep -qE '^(4|4a|4b|4c|4\.5|3\.5)$'` koşuluyla helper sonucunu kullanıyor
  - Mevcut state field'lar dokunulmadı (extension over modification)

## [8.2.5] - 2026-04-28

### Değişti
- **Devtime Plan Critique — 10 lens + model seçimi:** Lens listesi 5'ten 10'a genişledi: halüsinasyon kontrolü, mevcut özelliklerle çakışma, extension over modification, kullanıcı görünürlüğü, test edilebilirlik eklendi. Subagent modeli `claude-sonnet-4-6` extended thinking olarak explicit belirtildi — ana oturum (Opus 4.7) ile farklı model, gerçek ikinci göz bias çeşitliliği; critique reasoning için ideal, ~5x daha ucuz.

## [8.2.4] - 2026-04-28

### Eklendi
- **Devtime Plan Critique (CLAUDE.md):** MCL geliştirme oturumlarında plan üretildiğinde otomatik olarak `superpowers:code-reviewer` subagent açılır ve planı 5 lens ile eleştirir: (1) kök sebep derinliği, (2) yan etki tahmini, (3) boş/eksik durumlar, (4) disambiguation eksiği, (5) plan belirsizliği. Critique plan'la birlikte sunulur; Ümit kabul/red eder. Sadece devtime — runtime'da tetiklenmez.

## [8.2.3] - 2026-04-28

### Eklendi
- **`mcl_get_active_phase()` helper (`mcl-state.sh`):** `current_phase` + `spec_approved` + `phase_review_state` + `ui_sub_phase` + `pattern_scan_due` + `spec_hash` okuyarak tek bir effective phase string döndürür: `"1"`, `"2"`, `"3"`, `"3.5"`, `"4"`, `"4a"`, `"4b"`, `"4c"`, `"4.5"`, `"4"` (pending), `"?"`. Extension over modification — mevcut state field'lar dokunulmaz. Hook'lardaki çift-okuma noktaları bu helper'ı kullanabilir.
  - Phase 3 phantom: `current_phase=2` + `spec_hash` set → `"3"` olarak türetilir, yeni state field gerektirmez.
  - `pending → running` geçişi: AskUQ-bağımlı tasarım doğru — Phase 4.5 her zaman AskUserQuestion ile başlıyor, `pending`'de kalma yanlış dala düşürme riski yok.
  - 4.5 vs 4.6 ayrımı: her ikisi de `phase_review_state="running"` — state'ten ayırt edilemiyor, transcript analizi gerekiyor (helper `"4.5"` döndürüyor, callers notlandırıldı).

## [8.2.2] - 2026-04-28

### Eklendi
- **`docs/root-cause-discipline.en.md`:** Root Cause Discipline tam İngilizce çevirisi (9 bölüm). MCL iç dili İngilizce olduğu için operasyonel referans bu dosya; Türkçe versiyon insan referansı olarak kalıyor.

### Değişti
- **CLAUDE.md:** Root Cause Discipline referansı `.en.md`'ye güncellendi.
- **`mcl-rollback.md`:** Hardcoded Türkçe çıktı kaldırıldı. Satır 12 (checkpoint yok mesajı) ve satır 19-29 (rollback template) artık developer'ın algılanan diline göre üretiliyor. Teknik tokenlar (git komutları, SHA) İngilizce kalıyor.

## [8.2.1] - 2026-04-28

### Değişti
- **Phase 3.5 kademeli arama (boş pattern_summary fix):** `mcl-pattern-scan.py` tek seviyeden 4 seviyeli cascade'e dönüştürüldü.
  - **Level 1 (mevcut):** scope_paths sibling dosyaları
  - **Level 2 (yeni):** sibling yoksa proje genelinde aynı uzantılı dosyalar, en son değiştirilen 8 tane
  - **Level 3 (yeni):** proje dosyası yoksa ekosistem standardı (TypeScript strict, Python PEP 8, Go idiomatic, vb.) — `mcl-activate.sh` build-in knowledge'dan PATTERN SUMMARY yazar
  - **Level 4 (yeni):** ekosistem tespit edilemezse kullanıcıya tek soru
- `mcl-stop.sh`: exit code 3 → Level 3/4 dallanması; `pattern_level` ve `pattern_ask_pending` state'e yazılır
- `mcl-activate.sh`: PATTERN_MATCHING_NOTICE level'a göre farklılaştı — Level 1/2 dosya listesi, Level 3 ekosistem direktifi, Level 4 kullanıcıya sor
- `mcl-state.sh`: `pattern_level` ve `pattern_ask_pending` schema'ya eklendi

## [8.2.0] - 2026-04-28

### Eklendi
- **`docs/root-cause-discipline.md`:** Root Cause Discipline tam spesifikasyonu. 9 bölüm: temel düstur, zincir ilerleyişi, halka başına 3 check (görünür süreç → removal test → falsification; sıralı, paralel değil), halka geçişi sonucu, edge case, müdahale noktası seçimi (sıfır yan etki halkası), kök sebep + çözüm raporu, kapsam, özet.

### Değişti
- **CLAUDE.md — Root Cause Discipline:** Hem devtime hem runtime kuralları `docs/root-cause-discipline.md` referansıyla güncellendi. 3 check sıralı, sıfır yan etki halkası, kök sebep + çözüm + doğrulama, tıkanırsa şeffaflık kuralları eklendi.
- **`mcl-activate.sh` Root Cause Chain direktifi:** 3 check (görünür süreç, removal test, falsification), müdahale noktası (sıfır yan etki halkası), risk item formatı (kök sebep + önerilen çözüm + çözüm doğrulama), zincir tıkanınca şeffaflık kuralları eklendi.

## [8.1.9] - 2026-04-28

### Eklendi
- **Root Cause Discipline (CLAUDE.md):** İki yeni kural `## Root Cause Discipline` başlığı altında.
  - *Devtime:* "Bu neden böyle?" sorusunu tekrarla — cevap geldiğinde tekrar sor. En alttaki sebebi bul. Bazen tek sebep tüm ağı çözer.
  - *Runtime (Root Cause Chain):* Phase 4.5 Root Cause Lens tek seviyeden çok seviyeli zincire dönüştürüldü. Bir sebep bulununca durmaz; "bu sebebin de kök sebebi var mı?" diye tekrar sorgular. En yapısal sebebi risk item olarak raporlar. Anti-sycophancy gibi temel: atlanması yasak.
- **`mcl-activate.sh` Root Cause Chain direktifi:** `pattern-compliance` bloğundaki "Root Cause Lens" metni "Root Cause Chain" olarak güncellendi. Çok seviyeli iniş, en derin yapısal sebep hedefi ve "Phase 4.5 tamamlanmış sayılmaz" zorunluluğu eklendi.

## [8.1.8] - 2026-04-28

### Eklendi
- **Phase 1.5 Failure Path:** Brief, Phase 1 onaylı parametrelerle çelişirse sessiz fallback yasak. Her denemede yaklaşım değiştirilerek retry; eksik bilgi kaynaksa geliştiriciye tek soru sorulur. Tutarlılık kriterleri belgelendi. Audit kaydına `retries` ve `clarification` alanları eklendi.
- **Phase 4.6 "apply fix" semantiği:** "Apply fix" seçeneğinin Phase 4.6 içinde in-place patch anlamına geldiği, Phase 4'e geri dönüş olmadığı belgelendi. Çok büyük fix için next-session yönlendirmesi eklendi.
- **CLAUDE.md — runtime kural:** Bozulma tespit edildiğinde sessiz fallback yasak; yaklaşım değiştirerek retry, eksik bilgiyse tek soru.
- **CLAUDE.md — devtime kural:** MCL geliştirirken tur başına tek soru — "tek adım per tur" kuralının soru dizileri için daha katı versiyonu.

## [8.1.7] - 2026-04-28

### Eklendi
- **Phase 1.5 — Engineering Brief:** `skills/my-claude-lang/phase1-5-engineering-brief.md` oluşturuldu. Phase 1 onayı sonrası, Phase 2 öncesinde dahili İngilizce Engineering Brief üretilir. Geliştirici görmez; Phase 2 spec'in üzerine inşa ettiği anlam köprüsüdür. Kaynak dil İngilizce ise sessizce atlanır. Her iki durumda da `engineering-brief` audit kaydı düşer.
- **Phase 5.5 — Localize Report:** `skills/my-claude-lang/phase5-5-localize-report.md` oluşturuldu. Phase 5 Doğrulama Raporu üretildikten sonra, emisyon öncesinde tüm geliştirici-facing metin (bölüm başlıkları, hüküm kelimeleri, prose) geliştiricinin diline çevrilir. Teknik token'lar İngilizce kalır. Kaynak dil İngilizce ise atlanır. `localize-report` audit kaydı her durumda düşer.
- **STEP-58 ve STEP-59:** `all-mcl.md`'e eklendi — her iki yeni fazın checkup adımı tanımlandı.
- **`skills/my-claude-lang.md`:** Phase 1.5 ve Phase 5.5 pointer satırları eklendi; Phase 1 açıklaması Phase 1.5'e yönlendirildi.

### Değişti
- **CLAUDE.md — test dili:** "14 dilde test et" kuralı "Türkçe'de test et" olarak güncellendi. Dil *desteği* 14 dili kapsar; dil *testi* yalnızca Türkçe kullanır.
- **CLAUDE.md — behavioral → dedicated kuralı:** Behavioral olarak çalışan her MCL özelliğinin dedicated faz/skill/hook olması gerektiği, mümkün değilse atlama tespit eden kontrol eklenmesi gerektiği prensip olarak eklendi.

## [8.1.6] - 2026-04-28

### Düzeltme
- **Regression Guard akıllı atlama — staleness kontrolü:** 8.1.5'te `age < 120s` yeterliydi ama green-verify sonrası aynı turda Write/Edit/MultiEdit/NotebookEdit çağrıldıysa state eskimiş sayılır. `mcl-post-tool.sh` Write grubu araçlarda `last_write_ts` (unix epoch) state'e yazar. Skip koşulu artık ikili: `tdd_last_green.ts > last_write_ts` VE `age < 120s`. İkisi birlikte sağlanırsa atlama yapar, biri bozulursa tam suite koşar.

## [8.1.5] - 2026-04-28

### Eklendi
- **Regression Guard akıllı atlama:** TDD'nin son `green-verify` sonucu `state.tdd_last_green`'e (`ts` + `result`) yazılır. Regression Guard tetiklenirken bu değeri okur: `green-verify` GREEN ve 120 saniyeden taze ise suite tekrar koşulmaz (`regression-guard-skipped` audit kaydıyla). 120 saniyeden eski veya hiç çalışmamışsa tam suite koşulur.
- **self-critique.md:** Pressure resistance / Human Authority ayrımına tek satır örnek eklendi — "X yapma" → Human Authority (karar kapanır), "X yanlış" kanıtsız → Pressure resistance (pozisyon korunur).

## [8.1.4] - 2026-04-27

### Eklendi
- **İnsan Yetkisi — Karar Kapanışı:** `self-critique.md`'e "Human Authority — Decision Closure" bölümü eklendi. Geliştirici bir kararı açıkça verdikten sonra (ret, seçim, riski kabul, tekrarlanan seçim) MCL o kararı tekrar açmaz; işlevsel eşdeğer önermez, aynı itirazı yeniden çerçevelemez. İstisna: daha önce bilinmeyen yeni kritik bilgi — bir kez, etiketlenerek sunulur.
- `phase1-rules.md`'e çapraz referans eklendi: explicit decision → human authority rule → see self-critique.md.
- Anti-sycophancy ile tamamlayıcı ilişki belgelendi: pressure resistance (kanıtsız baskıya direnç) ≠ human authority (verilen kararın kapanması).

## [8.1.3] - 2026-04-27

### Eklendi
- **Root Cause Prensibi (Boris Cherny):** Phase 4 Scope Discipline'e Rule 3 eklendi: "Fix the cause, not the symptom. If a patch only makes the test pass without addressing why it failed, surface it as a Phase 4.5 risk item."
- **Phase 4.5 Root Cause Lens:** `pattern-compliance` mcl_audit bloğuna Root Cause Lens direktifi eklendi. Band-aid kalıpları listelenir: hataları catch/swallow etmek, type constraint genişletmek, test girdilerini özel-case'lemek, failure mode düzeltilmeden retry. Her biri risk item olarak raporlanır.
- Mekanizma: flag sistemi yok — lens Phase 4.5'te bağımsız tarar.

## [8.1.2] - 2026-04-27

### Eklendi
- **Kapsam Disiplini:** Phase 4'te her turda `SCOPE_DISCIPLINE_NOTICE` enjekte edilir. İki kural:
  - **Rule 1 — SPEC-ONLY:** Spec'in MUST/SHOULD'larında olmayan hiçbir şey yapılmaz. Yasak: spec'te olmayan performans iyileştirmesi, "fırsattan istifade" refactor, style fix, fazladan test, "ileride lazım olur" API eklentisi. Fark edilirse Phase 4.5/4.6 itemi olarak kaydedilir, düzeltilmez.
  - **Rule 2 — FILE SCOPE:** Yalnızca spec'in Technical Approach'unda geçen dosyalar değiştirilir. `scope_paths` doluysa pre-tool hook zaten bloke eder; boşsa bu behavioral notice kapsar.
- Scope Guard block mesajı güncellendi: Rule 1 ve Rule 2 referanslarıyla ihlal bağlamı netleştirildi.

## [8.1.1] - 2026-04-27

### Değişti
- **Phase 3.5 derinleşti:** Özet artık zorunlu 3 başlık formatında — `**Naming Convention:**`, `**Error Handling Pattern:**`, `**Test Pattern:**`. "Enforced" ibaresi ile kurallar Phase 4 boyunca `PATTERN_RULES_NOTICE` olarak her turda context'te tutulur.
- **stop hook:** `PATTERN_SUMMARY` early exit'ten önce parse edilir (`mcl-stop.sh`'de yeni erken clearance bloğu). Phase 3.5 turu spec/AskUQ içermediği için eski geç clearance hiç çalışmıyordu.
- **Phase 4.5 compliance:** `phase_review_state=running`'da `PATTERN_RULES_NOTICE`'e compliance check direktifi eklenir — hangi dosya, hangi kural, ne bulundu vs beklenen.
- `state.pattern_summary` şemaya eklendi; session sınırında sıfırlanır.

## [8.1.0] - 2026-04-27

### Değişti
- `ROLLBACK_NOTICE` artık her Phase 4 turunda değil, yalnızca ilk turda gösteriliyor (`rollback_notice_shown` flag). 5-10 turluk görevlerde aynı SHA tekrar etmez.
- `/mcl-rollback` komutu eklendi: flag'ı sıfırlar, bir sonraki turda notice yeniden görünür; full SHA + reset komutu + atomic commit önerisi gösterir.
- `state.rollback_notice_shown` şemaya eklendi; session sınırında sıfırlanır.

## [8.0.9] - 2026-04-27

### Eklendi
- **Rollback checkpoint:** Spec onayı anında `git rev-parse HEAD` çalıştırılır, SHA `state.rollback_sha`'ya kaydedilir. Phase 4 boyunca her turda `ROLLBACK_NOTICE` context'e enjekte edilir — tam SHA ve `git reset --hard <sha>` komutuyla. Git repo yoksa sessizce geçilir.
- **Atomic commit hint:** Phase 4.5/4.6/5 çalışırken (`phase_review_state=running`) `ATOMIC_COMMIT_NOTICE` enjekte edilir: `git add <scope_paths>` + `git commit -m "feat: <spec objective>"` komutu hazır olarak sunulur. Auto-commit yok — Claude komutu çalıştırır, developer onaylar.
- **state.rollback_sha:** Şemaya eklendi (default null); session sınırında temizlenir.

## [8.0.8] - 2026-04-27

### Eklendi
- **Güvenlik refleksleri — `mcl-secret-scan.py`:** Tüm fazlarda Write/Edit/MultiEdit/NotebookEdit çağrıları credential ve secret taramasından geçer.
  - **Tier 1 (hassas dosya yolu):** `.env`, `*.pem`, `*.key`, `credentials.json`, `service-account.json` vb. gerçek değer içeriyorsa block. `.env.example` ve `*.template` muaf.
  - **Tier 2 (bilinen secret pattern):** `sk-...` (OpenAI/Anthropic), `ghp_...` (GitHub), `AKIA...` (AWS), `AIza...` (Google), `xoxb-...` (Slack), PEM header, JWT vb.
  - **Tier 3 (high-entropy assignment):** `SECRET/PASSWORD/API_KEY = <entropy≥3.5, len≥20>` — `os.environ` referansları ve placeholder değerler muaf.
- Tarama faz kapısından önce çalışır — Phase 1-3'te bile credential yazımı bloke edilir.

## [8.0.7] - 2026-04-27

### Eklendi
- **Phase 3.5 — Pattern Matching:** Spec onayı → Phase 4 geçişinde, `scope_paths`'e göre mevcut sibling dosyaları `mcl-pattern-scan.py` ile tespit eder. İlk Phase 4 turunda Write/Edit bloke edilir; `PATTERN_MATCHING_NOTICE` Claude'a hangi dosyaları okuyacağını ve ne çıkaracağını (import stili, naming convention, error handling, test yapısı) söyler. Tur tamamlanınca blok otomatik kalkar.
- **mcl-pattern-scan.py:** scope_paths'ten sibling dosya referansları bulur; dizin başına max 3, toplam max 10 dosya; glob-aware.
- **state alanları:** `pattern_scan_due` (bool), `pattern_files` (list) — session sınırında sıfırlanır.

## [8.0.6] - 2026-04-27

### Eklendi
- **Scope Guard (mcl-pre-tool.sh):** Phase 4'te Write/Edit/MultiEdit/NotebookEdit çağrıları onaylanmış spec'te bildirilen dosya yollarıyla kısıtlanır. `scope_paths` boşsa kısıtlama yoktur (spec açık yol listesi içermiyorsa dormant).
- **mcl-spec-paths.py:** Spec metninden dosya yolu token'larını çıkarır. Backtick, bold ve düz metin yollarını destekler; `src/auth/*.ts`, `tests/**/*.test.ts` gibi glob pattern'leri tanır.
- **scope_paths state alanı:** Spec onayında `mcl-stop.sh` yolları çıkarıp `state.scope_paths`'e yazar; session sınırında `mcl-activate.sh` sıfırlar.

## [8.0.5] - 2026-04-27

### Düzeltme
- `mcl-stop.sh`: `_MCL_HOOK_DIR` sabitlendi — `mcl-test-runner.sh` kaynaklanınca `SCRIPT_DIR`'i `lib/` dizinine çekiyordu, tüm `$SCRIPT_DIR/lib/` referansları bozuluyordu. `_MCL_HOOK_DIR` ile sabitledi; `mcl-phase-review-guard.py`, `mcl-partial-spec.sh`, `mcl-spec-save.sh` vb. doğru konumdan çalışıyor.
- `mcl-state.sh` allowlist: `mcl-post-tool.sh` yetkili yazıcılar listesine eklendi. Eksikliği Regression Guard clearance'ını susturuyordu — "✅ Tests: GREEN" sonrası `regression_block_active` temizlenemiyor, blok kalıcı hale geliyordu.

## [8.0.4] - 2026-04-26

### Eklendi
- **Regression Guard:** Phase 4 kodu yazıldıktan sonra, Phase 4.5 başlamadan önce tam test suite çalıştırılır. Suite kırmızıysa (`regression_block_active=true`) Phase 4.5 bloke edilir; `mcl-activate.sh` `REGRESSION_BLOCK_NOTICE` enjekte eder. Geliştirici hatayı düzeltip "✅ Tests: GREEN" çıktısı aldığında `mcl-post-tool.sh` bloğu otomatik temizler.

### Düzeltme
- `mcl-pre-tool.sh` state.json koruma regex'i: eski geniş regex (komut içinde `state.json` VE herhangi bir `>>` yeterliydi) false-positive'lere yol açıyordu. Yeni regex `>>?` yakalamalarının doğrudan hedefini kontrol eder; Python betikleri veya yorum satırları artık tetiklemez.

## [8.0.3] - 2026-04-27

## [8.0.2] - 2026-04-27

### Düzeltme
- `Skill`, `TodoWrite` ve `Task` blokları `mcl-pre-tool.sh`'deki fast-path'ten önce taşındı. Önceki konumlarında fast-path onları `exit 0` ile geçiriyordu; bloklar hiç çalışmıyordu.
- Her bloğun sonuna non-matching case için `exit 0` eklendi — `feature-dev:code-explorer` gibi meşru Task çağrıları ve `superpowers:code-reviewer` gibi izinli Skill çağrıları artık doğru şekilde geçiyor.

---

## [8.0.1] - 2026-04-27

### Eklendi
- **TodoWrite blok (Phase 1-3):** `mcl-pre-tool.sh` Phase 1-3'te `TodoWrite` çağrılarını `decision:block` ile engelliyor. Phase 4+ serbest.
- **Task dispatch blok (Phase 4.5/4.6/5):** Phase 4.5 (Risk Review), Phase 4.6 (Impact Review), Phase 5 (Verification Report) sub-agent'a devredilmeye çalışılırsa bloke ediliyor. Bu fazlar yalnızca ana MCL oturumunda çalışabilir.

### Değişti
- `superpowers-scope` behavioral kısıtı STATIC_CONTEXT'ten kaldırıldı — hook referans notuna indirgendi.

---

## [8.0.0] - 2026-04-27

### Düzeltme
- `superpowers:brainstorming` artık `mcl-pre-tool.sh` hook'unda `decision:block` ile engelleniyor. 7.9.9'daki behavioral kural (`superpowers:using-superpowers`'ın "ABSOLUTELY MUST" talimatı tarafından override ediliyordu) yetersiz kaldığından hook-level blok eklendi.

---

## [7.9.9] - 2026-04-27

### Düzeltme
- STATIC_CONTEXT'e `superpowers-scope` kısıtı eklendi: `superpowers:brainstorming` yasak, MCL faz takibi için `TodoWrite` yasak, visual companion teklifi yasak. (Sonradan 8.0.0'da hook-level blok ile güçlendirildi.)

---

## [7.9.8] - 2026-04-27

### Düzeltme
- **Çoklu spec sorunu:** Kullanıcı AskUserQuestion butonuna basmak yerine chat input'a "onaylıyorum" yazdığında stop hook onayı algılayamıyor ve phase=2'de kalıyordu. `mcl-stop.sh`'e plain-text approval fallback eklendi.
- **"Devam etmek için bir mesaj gönderin" yasağı:** `spec-approval-discipline` kısıtıyla bu cümle ve tüm dil eşdeğerleri yasaklandı.
- Session başına 1 spec kuralı, hook dosyası debug yasağı, self-narration yasağı eklendi.

---

## [7.9.7] - 2026-04-26

### Eklendi
- **Kod tasarım ilkeleri** STATIC_CONTEXT'e eklendi: Composition over inheritance, SOLID, extension over modification, design pattern sadece gerçek problem için. `~/.claude/CLAUDE.md`'ye de global kural olarak yazıldı.

---

## [7.9.6] - 2026-04-26

### Düzeltme
- `vite.config.*`, `next.config.*`, `nuxt.config.*` Phase 4a'da engellenen backend path listesinden çıkarıldı. Bu dosyalar olmadan `npm run dev` çalışmıyor, kullanıcı UI'ı göremeden onay isteniyordu.
- `phase4a-ui-build.md` prosedürüne "build config dosyalarını önce yaz" adımı eklendi.

---

## [7.9.5] - 2026-04-26

### Eklendi
- **Plugin Dispatch Audit:** Phase 4.5 çalışırken `mcl-activate.sh` her turda `trace.log`'u kontrol ediyor. `code-review` sub-agent ve `semgrep` çalışmadıysa `PLUGIN_MISS_NOTICE` enjekte ediliyor ve Phase 4.6/5'e geçiş engelleniyor.
- `hooks/lib/mcl-dispatch-audit.sh` yeni dosya — manifest + audit fonksiyonu.
- `mcl-semgrep.sh`'e başarılı scan sonrası `semgrep_ran` trace eventi eklendi.

---

## [7.9.4] - 2026-04-26

### Değişti
- `(mcl-oz)` inline tag yeniden adlandırıldı: `/mcl-self-q`. Kullanımda fark yok — mesaj içinde yazılınca o yanıt için self-critique görünür hale gelir.
