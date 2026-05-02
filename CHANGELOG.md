# Değişiklik Günlüğü

[Keep a Changelog](https://keepachangelog.com) formatı. Her yeni sürümde
`[Unreleased]` bölümü `[X.Y.Z] - YYYY-MM-DD`'ye dönüştürülür.

---

## [Unreleased]

## [10.1.7] - 2026-05-02

### Spec-approval gate restored (Option 3) + escape hatch (Option 1)

The MUST-have follow-up to v10.1.6. The herta investigation surfaced
the real root cause: state freeze was the SYMPTOM; the underlying
contract violation was that **writes happened at `spec_approved=false`
because pre-tool was advisory** (v10.0.0 decision:approve replaced
decision:block for "tüm MCL kilitlerini kaldır"). v10.1.5/v10.1.6
made progression more reliable but never closed the actual write gate.
Without this gate, "MCL koruyor" is theater — vulnerable code can
still ship while state machine is perfectly tracked.

#### Implementation

**`hooks/mcl-pre-tool.sh`** — two surgical changes around the
existing spec_approved check:

1. **Layer 4 escape hatch (Option 1)** — before the spec-approval
   block fires, scan audit.log for `asama-4-complete` emit (mandated
   by skills/asama4-spec.md since v10.1.6). When found in current
   session, force-progress `spec_approved=true`,
   `current_phase=7`, `phase_name=EXECUTE` inline at PreToolUse
   (not just at Stop). This means model can recover from a
   classifier miss WITHOUT waiting for end-of-turn — the next
   mutating tool call after the emit succeeds. Audit + trace get
   `asama-4-progression-from-emit` from pre-tool.

2. **Real spec-approval block (Option 3)** — when `spec_approved=
   false` after both JIT askq advance AND escape hatch attempts,
   pre-tool now returns `permissionDecision: "deny"` (was "allow"
   advisory in v10.0.0+). REASON message instructs the model on
   three recovery options: re-emit AskUserQuestion, run the
   `asama-4-complete` Bash audit emit, or wait for 3-strike fail-
   open. Other denial sources (UI path, pattern scan, scope guard)
   STAY ADVISORY — only the spec-approval gate is reverted.

3. **3-strike loop-breaker** — if `spec-approval-block` audit
   already fired ≥3 times in the current session, fail-open with
   `spec-approval-loop-broken` audit + trace. Prevents developer
   lockout when classifier consistently fails AND model can't
   self-recover via the emit path.

**`hooks/lib/mcl-state.sh`** — `_mcl_loop_breaker_count` helper moved
from mcl-stop.sh into the shared lib so both hooks can use it. Stop
hook keeps its local copy for backward-compat (lib version overrides
when sourced first).

#### Why Option 3 was the must-have

The herta v10.1.4 audit log showed 70+ `deny-tool` events but every
single mutating write succeeded — because the decision was "allow"
with a denial REASON for advisory purposes. The model wrote 36 prod
files at `spec_approved=false` despite MCL's stated contract that
spec approval is required first. v10.1.5/v10.1.6 made that violation
TRACKABLE (skip-detection audit) but didn't STOP it. v10.1.7 stops
it.

Why Option 3 alone wasn't enough: classifier coverage gaps mean
spec_approved can stay false even when developer clicked Onayla.
Hard-block alone would lock the developer out. Option 1 (asama-4-
complete escape hatch from v10.1.6, now active in pre-tool too) is
the recovery path. The 3-strike loop-breaker is the final fail-safe.

#### Combined v10.1.0–v10.1.7 effect

- v10.1.0: Aşama 8/9 hard-enforced
- v10.1.1: Stack-aware security MUST checklist
- v10.1.2: M/H findings must-resolve invariant
- v10.1.3: Aşama 7 title fix (test-first emphasis)
- v10.1.4: TDD compliance ratio audit
- v10.1.5: Audit-driven progression — Aşama 8 + 9 (PILOT)
- v10.1.6: Audit-driven progression — full coverage + Layer 3 skip-detection
- **v10.1.7: Spec-approval real block + asama-4-complete escape hatch + 3-strike loop-breaker (this release)**

The spec-approval contract is now actually enforced. herta v10.1.4-
type silent-bypass cannot recur.

#### Tests

180 passing (16 new in `test-v10-1-7-spec-approval-block.sh`,
integration-style — runs actual mcl-pre-tool.sh against synthetic
fixtures, asserts permissionDecision in JSON output, asserts state
side effects, asserts loop-breaker fires after 3 strikes).

Banner: MCL 10.1.6 → MCL 10.1.7.

## [10.1.6] - 2026-05-02

### Audit-driven phase progression — full coverage + skip-detection

Continuation of the v10.1.5 PILOT (Aşama 8 + 9). v10.1.6 extends the
classifier-independent fallback to ALL persisted/transient phases AND
adds Layer 3 skip-detection that surfaces missing emits as audit
warnings. Closes the herta-type "frozen at phase 4" scenario observed
under v10.1.4: state machine no longer depends solely on askq
classifier intent recognition.

#### Implementation

**`hooks/mcl-stop.sh`** — five new scanners + one skip-detector:

- `_mcl_precision_audit_emitted` — scans for the existing
  `precision-audit asama2` audit (mandated by skills/asama2-precision-
  audit.md). Sets `precision_audit_done=true` when found in current
  session. Previously the field was reset to false on restart but
  NEVER set to true — the field was effectively dead. Emits
  `asama-2-progression-from-emit` audit + `phase_transition 1 2`
  trace.
- Aşama 4 progression — `_mcl_asama_4_complete_emitted` + force-
  progression of `spec_approved=true`, `current_phase=7`,
  `phase_name=EXECUTE`. Emits `asama-4-progression-from-emit`
  audit + `phase_transition 4 7` trace.
- `_mcl_audit_emitted_in_session` (generic helper) — scans audit.log
  for `<event>` in current session with optional idempotency marker
  to prevent duplicate progression writes when Stop fires multiple
  times.
- Aşama 10 — explicit `asama-10-complete` emit detection. Emits
  `asama-10-progression-from-emit` + `phase_transition 10 11` trace.
- Aşama 11 — explicit `asama-11-complete` emit detection. Emits
  `asama-11-progression-from-emit` + `phase_transition 11 12` trace.
- Aşama 12 — reuses existing `localize-report asama12` audit
  (mandated by skills/asama12-translate.md). Emits
  `asama-12-progression-from-emit` + `phase_transition 12 done`
  trace.
- `_mcl_skip_detection` (Layer 3) — when `tdd-prod-write` audit
  events are present in current session but the corresponding
  `asama-{4,8,9}-complete` emit is missing, write
  `asama-N-emit-missing | stop | skip-detect prod-write-without-emit`
  audit + `phase_emit_missing N` trace. Pure visibility, no block,
  no decision change. Idempotent — re-runs skip phases already
  flagged.

**Skill instructions added to:**
- `skills/my-claude-lang/asama4-spec.md` — emit `asama-4-complete`
  with `spec_hash=<H> approver=user` after AskUserQuestion approve
  tool_result and BEFORE writing any Aşama 7 code.
- `skills/my-claude-lang/asama10-impact-review.md` — emit
  `asama-10-complete` with `impacts=N resolved=R` at end of impact
  review (or when omitted because no impacts surfaced).
- `skills/my-claude-lang/asama11-verify-report.md` — emit
  `asama-11-complete` with `covered=N must_test=K trace_lines=L`
  after all three Verification Report sections are written.

**No skill changes for Aşama 2 / 12** — both already mandate
existing audits (`precision-audit`, `localize-report`) that v10.1.6
reuses as completion markers.

#### Why this is the root-cause fix (not just a patch)

The herta investigation surfaced the architectural root cause: phase
progression was OPTIMISTIC. State writes only occurred when the
askq-classifier detected a specific intent in transcript text. Any
classifier coverage gap (off-language wording, dropped prefix,
free-form text instead of AskUserQuestion option choice) silently
froze state at phase 4 even when the model proceeded behaviorally.

Three layers of fix in v10.1.5/v10.1.6:

- **Layer 1 (skill behavior):** every phase emits an explicit
  `asama-N-complete` Bash audit at end of run.
- **Layer 2 (hook scanner):** Stop hook scans audit.log per session
  and force-progresses state independently of classifier output.
- **Layer 3 (skip-detection):** when activity signals (tdd-prod-write)
  appear without the matching emit, hook writes
  `asama-N-emit-missing` so the bypass is visible retroactively in
  /mcl-checkup.

Layers 1+2 ensure progression DOES happen when the model complies.
Layer 3 ensures non-compliance is VISIBLE so the developer knows when
the contract was bypassed. Together they close the herta-type freeze
without resorting to brittle classifier improvements.

#### Combined v10.1.0–v10.1.6 effect

- v10.1.0: Aşama 8/9 hard-enforced (no fast-path skip)
- v10.1.1: Stack-aware security MUST checklist
- v10.1.2: M/H findings must-resolve invariant
- v10.1.3: Aşama 7 title fix (test-first emphasis)
- v10.1.4: TDD compliance ratio audit
- v10.1.5: Audit-driven progression — Aşama 8 + 9 (PILOT)
- **v10.1.6: Audit-driven progression — full coverage + Layer 3 skip-detection (this release)**

#### Tests

154 passing (24 new across 3 files):
- `test-v10-1-6-asama-4-progression.sh` — 8 tests (emit detection +
  state side effects + skill contract)
- `test-v10-1-6-phase-progressions.sh` — 8 tests (precision-audit /
  asama-10 / idempotency / asama-12 / hook + skill contracts)
- `test-v10-1-6-skip-detection.sh` — 8 tests (all-missing / partial /
  all-present / no-code-no-flag / idempotent / hook contract)

Banner: MCL 10.1.5 → MCL 10.1.6.

## [10.1.5] - 2026-05-02

### Audit-driven phase progression (PILOT — Aşama 8 + 9)

Real-use diagnosis: the herta project completed Aşama 1–12 end-to-end
yet `state.json` showed `risk_review_state=null`,
`quality_review_state=null`, `tdd_compliance_score=null`. Phase
progression depended on the askq-classifier detecting the right
intent, and any classifier coverage gap (off-language wording, missing
prefix, dropped tool_result) silently froze state at phase 4 even
when the full pipeline ran behaviorally.

v10.1.5 introduces a classifier-independent fallback: each phase
emits an explicit `asama-N-complete` audit at end of run. Stop hook
scans audit.log per session and force-progresses the corresponding
state field. Pilot scope: Aşama 8 + 9 only. Remaining phases (1→2,
4→7, 10/11/12) ship in v10.1.6.

#### Implementation

- **`hooks/mcl-stop.sh`** — two new helpers + scanners:
  - `_mcl_asama_8_complete_emitted` — scans audit.log since
    session_start for `asama-8-complete` events. When found AND
    `risk_review_state != "complete"`, force-progresses state, emits
    `asama-8-progression-from-emit` audit, writes
    `phase_transition 8 9` to trace.
  - `_mcl_asama_9_complete_emitted` — symmetric logic for
    `quality_review_state`, emits `phase_transition 9 10`.
- **`skills/my-claude-lang/asama8-risk-review.md`** — new "## Audit
  Emit on Completion" section. Mandates a Bash audit emit at end of
  Aşama 8 with severity counts (`h_count=N m_count=M l_count=K
  resolved=R`), even when Aşama 8 was OMITTED (no risks worth
  surfacing).
- **`skills/my-claude-lang/asama9-quality-tests.md`** — new "## Audit
  Emit on Completion" section. Mandates a Bash audit emit at end of
  Aşama 9 with sub-step counts (`applied=A skipped=S ambiguous=B
  na=N`). Notes that the v10.1.2 MEDIUM/HIGH must-resolve invariant
  remains independent — audit-driven progression unblocks the state
  field, not the severity gate.

#### Why pilot, not full rollout

Aşama 8 and 9 are the two phases where state-vs-behavior divergence
hurts most: `risk_review_state` and `quality_review_state` directly
gate the v10.1.0 hard-enforcement and the v10.1.2 must-resolve
invariant. Empty values here mean those gates fail open. The remaining
phase transitions (1→2 precision audit, 4→7 spec approve,
10/11/12) are less load-bearing for hard-blocks; they ship next once
the pilot pattern is verified in production use.

#### Combined v10.1.0–v10.1.5 effect

- v10.1.0: Aşama 8/9 hard-enforced (no fast-path skip)
- v10.1.1: Stack-aware security MUST checklist
- v10.1.2: M/H findings must-resolve invariant
- v10.1.3: Aşama 7 title fix (test-first emphasis)
- v10.1.4: TDD compliance ratio audit
- **v10.1.5: Audit-driven phase progression — Aşama 8 + 9 (this release)**

#### Tests

130 passing (13 new across `test-v10-1-5-asama-8-progression-pilot.sh`
and `test-v10-1-5-asama-9-progression-pilot.sh`: 3 emit-detection +
1 stale-session + 1 substring-confusion + 3 hook-contract checks per
phase, 3 of which are shared).

Banner: MCL 10.1.4 → MCL 10.1.5.

## [10.1.4] - 2026-05-02

### Layer 1 TDD compliance audit (cheapest path)

Real-use question: *"TDD'nin gerçekten çalıştığını nasıl
doğrularız?"* — how to verify TDD compliance? v10.1.4 adds the
cheapest verification layer: file-classifier + session compliance
ratio. Pure audit, no block, no developer friction.

#### Implementation

- **`hooks/mcl-post-tool.sh`** — new path classifier inserted
  before regression-guard logic. On every Write/Edit/MultiEdit/
  NotebookEdit, the file path is matched against:
  - **Skip patterns** (`node_modules/`, `dist/`, `build/`,
    `.next/`, `.nuxt/`, `.cache/`, `coverage/`, `.git/` — at start
    or after `/`) → no audit emit
  - **Test patterns** (`__tests__/`, `tests?/`, `specs?/`,
    `.test.{ts,tsx,js,...}`, `.spec.{ts,tsx,js,...}`,
    `_test.{go,py}`, `_spec.rb`, `test_*.py`) → emit
    `tdd-test-write | file=<path>`
  - **Source extensions** (`.ts/.tsx/.js/.py/.go/.rb/.java/.kt/
    .rs/.cpp/.cs/.php/.swift/.lua/.vue/.svelte` etc.) → emit
    `tdd-prod-write | file=<path>`
- **`hooks/mcl-stop.sh`** — new `_mcl_tdd_compliance` helper at
  Stop time scans session audit.log for `tdd-*-write` events.
  Computes: `score = (prod_writes_with_preceding_test_write /
  total_prod_writes) * 100`. Emits `tdd-compliance | score=N%
  preceded=K prod=M` audit + writes to state
  (`tdd_compliance_score`).
- **`hooks/lib/mcl-state.sh`** — new default field
  `tdd_compliance_score: null`.

#### Heuristic limits (intentional, cheapest layer)

- **Path-based, not behavior-based:** detects whether a test file
  was touched in the same session as prod files; does NOT verify
  RED→GREEN cycle (that's Layer 2).
- **"Any test before any prod" heuristic:** counts prod-writes
  that have ANY preceding test-write in session. Doesn't match
  test-to-prod-file pairs (that would require richer state).
- **Audit only, no block:** pure visibility. /mcl-checkup surfaces
  the score; developer decides if intervention needed.

#### Combined v10.1.0–v10.1.4 effect

- v10.1.0: Aşama 8/9 hard-enforced (no fast-path skip)
- v10.1.1: Stack-aware security MUST checklist
- v10.1.2: M/H findings must-resolve invariant
- v10.1.3: Aşama 7 title fix (test-first emphasis)
- **v10.1.4: TDD compliance ratio audit (this release)**

#### Tests

117 passing (23 new in `test-v10-1-4-tdd-compliance.sh`: 7 test-
pattern, 5 prod-pattern, 5 skip-pattern, 3 ratio scenarios + 3
hook contract checks).

Banner: MCL 10.1.3 → MCL 10.1.4.

## [10.1.3] - 2026-05-02

### Aşama 7 başlığı düzeltildi — TDD test-first vurgusu

Real-use feedback: Aşama 7 başlığı *"Kod yazılıyor"* ("Code gets
written") TDD prensibinin tersini ima ediyor — TDD'de önce test
yazılır, sonra kod. Body doğru tarif ediyordu (RED→GREEN→refactor)
ama başlık yanıltıcıydı.

#### Fix

- `README.md` Aşama 7 paragrafı yeniden yazıldı: *"Test-first
  development (TDD). For each acceptance criterion: write the
  failing test FIRST (RED), then the minimum production code to
  make it pass (GREEN), then refactor."*
- `README.tr.md` Aşama 7 paragrafı yeniden yazıldı: *"Test-first
  geliştirme (TDD). Her kabul kriteri için ÖNCE failing test
  yazılıyor (RED), SONRA onu geçecek minimum production kod
  (GREEN), ardından refactor. Test her zaman production kodun
  önünde gelir — 'kod yaz sonra test ekle' değil, gerçek TDD."*
- `skills/my-claude-lang/asama7-execute.md` başlık + naming
  clarification eklendi.

Banner: MCL 10.1.2 → MCL 10.1.3.

## [10.1.2] - 2026-05-02

### MEDIUM/HIGH must-resolve invariant

Closing the security gap loop: v10.1.0 hard-enforced Aşama 8 + 9
ran; v10.1.1 added the explicit MUST checklist; v10.1.2 ensures
no Aşama 11 advance while ANY HIGH or MEDIUM finding is still
unresolved.

#### Implementation

- **`hooks/lib/mcl-state.sh`** — new default field
  `open_severity_count: 0`.
- **`hooks/mcl-stop.sh`** — new `_mcl_open_severity_count()` helper:
  scans audit.log within current session boundary
  (`session_start` in trace.log) for `asama-9-4-ambiguous` events
  matched against `asama-9-4-resolved` events. The set difference
  is the open count. Helper updates state every Stop pass:
  `mcl_state_set open_severity_count <n>`.
- **Stop hook block:** when `quality_review_state="complete"` AND
  `open_severity_count > 0`, emit `decision:block` with the
  must-resolve reason text — Aşama 11 cannot fire until the count
  hits 0. The model resolves each finding by:
  1. Running it through Aşama 8 risk-dialog (developer decides via
     AskUserQuestion: apply fix / accept with rule-capture / cancel)
  2. Writing `mcl_audit_log "asama-9-4-resolved" "stop" "rule=<id>
     file=<f>:<l> status=fixed|accepted"` to mark it resolved.
- **Loop-breaker:** 3 consecutive `open-severity-block` events →
  `open-severity-loop-broken` audit + fail-open. Preserves the
  v9.0.1 fail-open contract.

#### Aşama 11 Verify Report — new "Açık Yüksek/Orta Bulgular" section

If the loop-breaker fired (fail-open path), Aşama 11 emits an
explicit "Açık Yüksek/Orta Bulgular" section listing every still-
open finding from the audit log. Even when MCL gives up enforcing
(loop-broken), the developer sees what was left unresolved.

#### Combined v10.1.0–v10.1.2 effect on real-use audit gaps

| Gap | Caught by |
|---|---|
| Brute-force protection missing | Aşama 8 §2b auth checklist [HIGH] |
| `localStorage` token storage | Aşama 8 §2b frontend [HIGH] |
| JWT revocation missing | Aşama 8 §2b backend [HIGH] |
| Default admin creds | Aşama 8 §2b auth [HIGH] |
| helmet missing | Aşama 8 §2b backend [HIGH] |
| **CSP missing** | Aşama 8 §2b frontend [HIGH] |
| Password policy weak | Aşama 8 §2b auth [HIGH] |
| bcrypt cost = 10 | Aşama 8 §2b backend [MEDIUM] |
| CORS regex too broad | Aşama 8 §2b backend [MEDIUM] |
| RBAC missing | Aşama 8 §2b auth [MEDIUM] |
| Audit log missing | Aşama 8 §2b backend [MEDIUM] |
| Aşamalar 8/9 hiç çalışmamış | v10.1.0 hard-enforcement |
| Açık M/H bulgular ile Aşama 11 fire | v10.1.2 must-resolve invariant |

#### Tests

94 passing (8 new in `test-v10-1-2-must-resolve.sh`: 4 counter
scenarios + hook contract checks + state schema check).

Banner: MCL 10.1.1 → MCL 10.1.2.

## [10.1.1] - 2026-05-02

### Stack-aware security MUST checklist (CSP, JWT, RBAC, audit, etc.)

Real-use audit identified 11 specific OWASP gaps. v10.1.0 added
hard-enforcement for Aşama 8/9 phases; v10.1.1 fills in the
content — the explicit checklist that those phases scan against.

#### Aşama 8 — `asama8-risk-review.md` §2b Stack-Aware Security MUST Checklist

5 stack-aware MUST groups, each entry tagged HIGH or MEDIUM:

- **Backend** (express/fastify/nest/koa/next-api/django/rails/fastapi):
  helmet, rate-limit, bcrypt cost ≥ 12, JWT lifecycle (revocation +
  short-lived access + refresh rotation), cookie flags
  (httpOnly+Secure+SameSite=strict), CORS whitelist, audit log,
  logging hygiene, parameterized queries.
- **Frontend** (react-frontend/vue-frontend/svelte-frontend/html-static):
  Content-Security-Policy (no unsafe-inline/eval), HSTS,
  X-Frame-Options, X-Content-Type-Options, Referrer-Policy,
  Permissions-Policy, Subresource Integrity, Trusted Types, token
  storage NEVER in localStorage, CSRF tokens, raw-HTML insertion
  API review.
- **Auth & Identity:** password schema (zod min(8) + complexity OR
  zxcvbn≥3), default credentials warning, RBAC matrix even for
  single-role, IDOR protection, session fixation defense,
  brute-force lockout.
- **Data & Secrets:** `.env*` in gitignore, weak `JWT_SECRET`
  placeholder detection, file-upload validation.
- **Dependency hygiene:** `npm audit --audit-level=moderate` clean,
  no abandoned/unmaintained packages.

#### Aşama 9.4 — `asama9-quality-tests.md` Security sub-step rewrite

- **Automatic tooling dispatch** at start of 9.4 (Bash invocation,
  not model behavior prior):
  - `bash mcl-semgrep.sh scan <touched-files>`
  - `npm audit --audit-level=moderate --omit=dev`
  - Stack-specific security linters (eslint-plugin-security, bandit,
    gosec, brakeman)
- **Per-finding disposition:**
  - HIGH/MEDIUM with unambiguous autofix → apply silently +
    `state.open_severity_findings.append({status:fixed})`
  - HIGH/MEDIUM ambiguous → **ESCALATE to Aşama 8 dialog** (no
    longer skip — prepares v10.1.2 must-resolve invariant)
  - LOW → suppress
- **Mirror of §2b checklist** — every MUST verified in code; absent
  → `open_severity_findings` entry + escalation.

#### Trade-off

Skill content is heavier (richer checklist) but no behavioral
breakage: existing 86 tests pass. Aşama 9.4 ambiguous-skip path is
gone (replaced with escalation), aligning with v10.1.2 invariant.

Banner: MCL 10.1.0 → MCL 10.1.1.

## [10.1.0] - 2026-05-02

### Aşama 8 + 9 hard-enforcement (real-use security gap fix)

Real-use audit (developer's npm-audit + manual review of test10
backoffice prototype): MCL produced code with multiple OWASP Top 10
gaps (no rate-limit, localStorage tokens, JWT revocation missing,
default admin creds, no helmet, weak password policy, bcrypt cost=10,
no RBAC, no audit log, **no CSP**) that should have been caught by
Aşama 8 risk dialog and Aşama 9 quality+tests pipeline. Neither phase
ran. Cause: v10.0.0 advisory mode swapped Aşama 8's
`phase-review-pending` block from `decision:block` to
`decision:approve`, and Aşama 9 never had hook enforcement at all.

#### Fixes

1. **Aşama 8 block re-enabled** — `mcl-stop.sh` line 724:
   `decision: "approve"` → `"block"`. Existing 3-strike loop-breaker
   (`phase-review-loop-broken`) preserved.

2. **Aşama 9 hard-block added** — new check in `mcl-stop.sh`:
   when `risk_review_state="complete"` AND
   `quality_review_state ≠ "complete"`, emit `decision:block` with
   the 8-sub-step requirements list (9.1 code review, 9.2 simplify,
   9.3 performance, 9.4 security with auto-semgrep + npm audit,
   9.5 unit, 9.6 integration, 9.7 E2E, 9.8 load). Each sub-step must
   write `asama-9-N-start` and `asama-9-N-end` audit entries (skip
   detection control). 3-strike loop-breaker
   (`quality-review-loop-broken`).

3. **STATIC_CONTEXT no-fast-path constraint** — new
   `<mcl_constraint name="asama-8-9-no-fast-path">`:
   *"Once code has been written in Aşama 7 (or any UI sub-phase),
   Aşama 8 AND Aşama 9 MUST both run. Skipping is impossible —
   'task is small', 'prototype only', 'just a UI tweak', 'obvious
   change' are NOT exceptions. Only when no code was written
   (Read/Grep/Glob only) are they skipped."*

#### Trade-off

v10.0.0's advisory mode is partially walked back: now 3 hard-blocks
total (Aşama 6b + 8 + 9). All three follow the same pattern:
state-flag triggered (timing-safe), 3-strike loop-breaker fail-open
(no infinite trap). Other gates (plugin-gate, secret-scan,
spec-presence, scope-guard, etc.) remain advisory.

#### Tests

86 passing (6 new in `test-v10-1-asama8-9-enforcement.sh`: contract
checks for both phases + STATIC_CONTEXT constraint + counter logic).

Banner: MCL 10.0.4 → MCL 10.1.0.

## [10.0.4] - 2026-05-02

### Fix v10.0.3 timing bug — spec-presence enforcement moves to Stop hook audit

Real-use feedback (developer's exact diagnosis): *"konuşmaları takip
etme konusunda bi eksik var bence. MCL herşeyi önceden kaydetmeli
bence. önceden yazarsa bütün tool'ların baktığı yerler güncel
olur."* — there's a gap in conversation tracking; MCL should record
things upfront so all hooks see current state.

#### Root cause

v10.0.3's pre-tool spec-presence block read `transcript.jsonl` at
PreToolUse fire time and scanned for 📋 Spec: in the current turn's
assistant text. **The current turn's assistant text is NOT yet
flushed to transcript when pre-tool fires.** Claude Code persists
assistant content blocks at message-completion time, not
incrementally. Result: even when the model DID emit a spec block
right before its Edit tool call, pre-tool's transcript scan returned
"no spec found" and blocked the Edit. The block then re-fired
multiple times because each retry hit the same timing wall.

#### Fix — move enforcement to Stop hook audit

- `hooks/mcl-pre-tool.sh` — REVERT v10.0.3's pre-tool spec-presence
  block + loop-breaker. Pre-tool no longer enforces spec presence.
- `hooks/mcl-stop.sh` — NEW `_mcl_spec_presence_audit` helper called
  at turn end (transcript fully flushed). Scans the latest assistant
  message: if it contains an Edit/Write/MultiEdit/NotebookEdit
  tool_use block, walks blocks in order, checks whether a 📋 Spec:
  text block precedes the first tool_use. If not, writes
  `spec-required-warn` to audit.log. Visible via `/mcl-checkup`.
- `STATIC_CONTEXT` no-spec-fast-path constraint updated:
  hard-block language replaced with audit-warn description.
- `asama4-spec.md` and `anti-patterns.md` updated to reflect the
  audit-not-block enforcement model.

#### Trade-off (acknowledged)

- **Lost:** mechanical pre-tool block that prevents Edit/Write
  without spec. Model can technically still skip the spec — and
  the audit-warn surfaces it after the fact, not before damage.
- **Gained:** correctness. v10.0.3's block was firing on legitimate
  spec emissions because of the transcript timing wall. v10.0.4's
  audit fires only when the spec is genuinely absent in the
  completed assistant message.

This is consistent with v10.0.0's advisory-mode philosophy: only
Aşama 6b retains a hard-block (and that one works because the
trigger is a state field set at end of prior turn, not in-progress
text). Spec-presence joins the audit-only enforcement tier.

#### Tests

80 passing (8 new test-v10-spec-required assertions for v10.0.4
architecture: hook contract checks (stop has audit, pre-tool no
longer blocks) + 3 detector verdicts (Edit with preceding spec=ok,
Edit without spec=warn, Edit with post-hoc spec=warn).

Banner: MCL 10.0.3 → MCL 10.0.4.

## [10.0.3] - 2026-05-02

### Aşama 4 spec-presence enforcement (MCL-wide rule)

Real-use feedback: in a small-tweak follow-up turn ("remove these
buttons, auto-apply on second pick"), the model called Edit directly
without emitting a 📋 Spec: block — fast-path rationalization based
on perceived task size. The developer asked the model "did you give
the spec to Claude Code in English?" and the model honestly admitted
it had skipped. The developer requested this rule be embedded in MCL
itself, not just in their personal `CLAUDE.md`.

#### Implementation

Three layers — STATIC_CONTEXT (prompt), skill files (documentation),
hook (mechanical enforcement):

1. **STATIC_CONTEXT** — new `<mcl_constraint name="no-spec-fast-path">`
   block: "Every assistant turn that calls Write / Edit / MultiEdit /
   NotebookEdit MUST include a visible 📋 Spec: block emitted BEFORE
   the tool call in the same turn. There is no 'too small' exception.
   Mid-task continuation turns count as new turns."

2. **`hooks/mcl-pre-tool.sh`** — new check inserted before secret-scan:
   when tool is Edit/Write/MultiEdit/NotebookEdit, scan the current
   turn's transcript (assistant text events after the latest user
   message) for 📋 Spec: line via the tolerant SPEC_LINE_RE. If
   absent → return `decision:block` with the required-actions reason
   text + brief-spec template. 3-strike loop-breaker
   (`spec-required-loop-broken` audit) preserves v9.0.1 fail-open.

3. **Skill files** — `asama4-spec.md` gains a "NO FAST-PATH RULE"
   section explaining the brief-spec shape acceptable for follow-up
   turns (Changes / Behavioral contract / Out of scope) so models
   can comply quickly without writing a full Aşama 4 ceremony each
   time. `anti-patterns.md` adds explicit anti-pattern entry.

#### Brief-spec shape (acceptable for follow-up turns)

```
📋 Spec:
Changes:
- file:path — what changes and why
Behavioral contract:
- the observable invariant the change preserves or introduces
Out of scope:
- explicitly excluded behaviors
```

Original full template (Objective / MUST / SHOULD / Acceptance / Edge
Cases / Technical Approach / Out of Scope) still applies for the
FIRST spec of each new task.

#### Tests

81 passing (7 new test-v10-spec-required assertions: counter logic,
hook source contract, transcript SPEC_RE detector positive/negative).

Banner: MCL 10.0.2 → MCL 10.0.3.

## [10.0.2] - 2026-05-02

### Aşama 6b hard enforcement (narrow re-introduction)

Real-use feedback (test10 backoffice prototype): even with v10.0.1's
strengthened STATIC_CONTEXT, the model wrote the entire stack
(frontend + backend + Prisma + Auth.js) in one turn, started the dev
server, ran curl checks, emitted Aşama 11 verify report — and never
asked the developer "do you approve the design?". v10.0.0 advisory
mode + v10.0.1 imperative prompt strengthening were not enough.

The strictest narrow option (A in the developer's last decision):
hook-level enforcement on Aşama 6b only. The model literally cannot
end a turn that wrote UI files in 6a without emitting an
AskUserQuestion this turn. Loop-breaker after 3 strikes preserves
the v9.0.1 "fail-open instead of trap" guarantee.

#### Implementation

- `hooks/mcl-stop.sh` — new check after the active-phase regex (which
  was also remapped from legacy `(4|4a|4b|4c|3.5)` to v9 numbering
  `(5|6a|6b|6c|7)`):
  - When `_PR_ACTIVE_PHASE = "6a"` AND `_PR_CODE = "true"` AND
    `_PR_ASKUQ != "true"`:
    - Increment `ui-review-skip-block` audit count for this session.
    - If count < 3 → return `decision: block` with localized reason
      including the required actions: dev server start, browser
      auto-open, AskUserQuestion shape (prefix, options, bare-verb
      approve label), STOP rule.
    - If count ≥ 3 → fail-open: write `ui-review-loop-broken` audit,
      force `ui_reviewed=true` and `ui_sub_phase=BACKEND` so
      downstream phases unblock.

#### Why narrow

This is the ONLY hard-block reintroduced after v10.0.0 advisory mode.
All other locks (plugin-gate, spec_approved, precision-audit,
phase-review-pending, scope-guard, etc.) remain advisory. The 6b
enforcement is the most one-step-recoverable enforcement in MCL —
the model only needs to call AskUserQuestion ONCE; it cannot fail
multiple times for unrelated reasons. Narrow scope keeps the test10
loop risk minimal.

#### Tests

74 passing (4 new test-v10-asama6b-enforcement assertions covering
loop-breaker counter behavior + hook source contract checks).

## [10.0.1] - 2026-05-02

### UI flow remap miss + auto-run + 6b AskUserQuestion strengthened

Real-use feedback: model wrote UI files but did NOT auto-run the dev
server, did NOT auto-open the browser, did NOT call the Aşama 6b
AskUserQuestion ("did you like it?"). Three causes:

1. **Numbering remap miss** — STATIC_CONTEXT `ui-flow-discipline`
   said *"Aşama 7 MUST split into 4a/4b/4c"* (still legacy). The
   `UI_FLOW_NOTICE` advisory injected on every turn said the same.
   Skill files `asama6a-ui-build.md` and `asama6c-backend.md` had
   `current_phase = 4` (legacy EXECUTE = old Phase 4). All carried
   stale numbering from the v9.0.0 mass-sed pass.
2. **Auto-run + 6b ASKQ underweighted** — instructions buried in
   one short sentence ("Auto-open the browser. STOP. ... present
   AskUserQuestion"). With v10.0.0 advisory mode, no hook enforces
   the sequence; the model treated it as suggestion.
3. **Imperative weakened** — original phrasing was passive
   ("Provide the dev-server run command when done"). Real-use
   showed model interpreted "provide" as "type out the command in
   prose for the developer to copy" rather than "execute it".

#### Fixes

- `hooks/mcl-activate.sh` STATIC_CONTEXT `ui-flow-discipline` rule
  rewritten with REQUIRED ACTIONS list (write configs FIRST → write
  components → npm install → run_in_background dev server → sleep
  3s → `open`/`xdg-open` browser → emit localized URL prose →
  STOP). Numbering migrated to 6a/6b/6c. Aşama 6b AskUserQuestion
  shape spelled out (prefix, options, approve label).
- `hooks/mcl-activate.sh` `UI_FLOW_NOTICE` (per-turn advisory)
  rewritten with the same REQUIRED ACTIONS sequence. Numbering
  migrated to 6a/6b/6c.
- `skills/my-claude-lang/asama6a-ui-build.md` entry condition
  `current_phase = 4` → `7`.
- `skills/my-claude-lang/asama6c-backend.md` entry condition
  `current_phase = 4` → `7`.

68/68 tests pass.

## [10.0.0] - 2026-05-02

### BREAKING — All MCL tool blocks removed (advisory mode)

After repeated real-use friction (test10 prototype-backoffice session
hit the same MCL LOCK loop 4× across v9.0.0 and v9.0.1 — even after
classifier fallback, regex tolerance, and 3-fail loop-breakers landed),
the developer ruled the contract too brittle for daily use and asked
to remove every MCL-side tool lock.

v10.0.0 makes MCL **advisory**:

- `hooks/mcl-pre-tool.sh` — every `decision: "block"` is now
  `decision: "approve"`, every `permissionDecision: "deny"` is now
  `permissionDecision: "allow"`. Affected gates: plugin-gate,
  TodoWrite Aşama 1-3, Task → phase dispatch, plan-critique
  substance, ExitPlanMode plan-critique, Bash → state.json write,
  secret-scan, UI-build sub-phase, pattern-scan-pending, scope-guard,
  spec_approved gate.
- `hooks/mcl-stop.sh` — every `decision: "block"` is now
  `decision: "approve"`. Affected enforcements: precision-audit
  (Aşama 2), phase-review-pending (Aşama 8), Aşama 11 verify-report
  skip detection.
- The hooks **still run** — state machine transitions, audit log
  entries, trace events, JIT askq advance, partial-spec recovery,
  /mcl-restart, /mcl-update, /mcl-finish, plugin orchestration —
  everything that was advisory before remains. Only the **tool
  blocking** is disabled.
- Banner: `🌐 MCL 9.0.1` → `🌐 MCL 10.0.0`.

### Trade-off (accepted)

- **Lost:** the contract guarantee that the model cannot write code
  without spec approval, cannot write code without precision audit,
  cannot ship without risk review, etc. Model behavior priors in
  STATIC_CONTEXT and skill files still teach the pipeline, but no
  hook prevents the model from skipping any step.
- **Gained:** zero MCL-LOCK loop risk. The framework is now purely
  documentary — it shapes model output through context injection
  but never blocks tool execution.

### Migration notes

Existing audit log entries with `... | block-* | ...` /
`... | *-block | ...` / `... | deny-tool | ...` event names remain
in `.mcl/audit.log` as historical record. New audit entries from
v10.0.0 use the same names — they record what MCL **would have
blocked** under the v9.x contract, useful for retrospective
diagnostics via `/mcl-checkup` even though no actual block fires.

### Tests

68/68 still passing. No test relied on tool-blocking behavior; all
tests exercise state transitions and audit emission, which v10.0.0
preserves.

## [9.0.1] - 2026-05-02

### Real-use bug fixes — JIT advance, scanner classifier, loop-breakers

Real-use test10 prototype-backoffice session exposed three failure
modes that combined into an infinite "MCL LOCK — spec_approved=false"
loop. v9.0.1 closes all three layers.

#### A. Scanner classifier expansion (`mcl-askq-scanner.py`)

The model emitted spec-approve questions using Turkish "Şartname"
(specification) instead of "Spec":
`MCL 9.0.0 | Şartname yukarıdaki gibi. Onaylıyor musun?`. The strict
`SPEC_APPROVE_TOKENS` list only knew "spec'i onayl"/"spec onay" and
returned `intent="other"` → JIT askq advance skipped → state stuck at
phase=1 → Write blocked.

Fixes:
- `SPEC_APPROVE_TOKENS` expanded across 14 languages (English
  spec/specification, Turkish şartname variants, Spanish
  especificación, Japanese 仕様, Korean 명세서, Chinese 规范, etc.).
- New `APPROVE_VERBS` list — generic approve-family verbs in 14
  languages (onayla, evet, kabul, aprueb, approuv, genehmig, 承認,
  승인, 批准, موافق, אשר, स्वीकार, setuju, aprovar, одобр, ...).
- `_classify_intent` now accepts question body, options list,
  selected option, and `has_spec` flag. Fallback heuristic: if no
  strict token matches but a `📋 Spec:` block exists in the
  transcript AND an approve-family verb appears in question body OR
  any option label OR the selected option, classify as
  `spec-approve`. Decouples classification from exact wording.
- PREFIX_RE strict match relaxed to fallback: when the model drops
  the `MCL X.Y.Z | ` prefix, scanner falls back to raw question
  text. Combined with the approve+spec heuristic, false positives
  are still ruled out by the spec presence requirement.

#### B. STATIC_CONTEXT hardening (`mcl-activate.sh` + `mcl-stop.sh`)

The model conflated "no GATE questions to ask" with "skip the
Aşama 2 audit emit step". Spec emitted without audit → Stop hook
hard-block → recovery loop.

Fixes:
- Aşama 2 instruction text in STATIC_CONTEXT made explicit: "emit one
  audit entry UNCONDITIONALLY ... THIS AUDIT EMIT IS MANDATORY EVEN
  WHEN ALL DIMENSIONS CLASSIFY AS SILENT-ASSUME — 'no GATE questions
  to ask' does NOT mean 'skip the audit'."
- Stop hook block reason text updated with the same clarification +
  audit emit example uses `asama2` caller (was `phase1-7` legacy
  string) + transition target text "Aşama 1→4" (was 1→2).

#### C. Loop-breakers (`mcl-stop.sh`)

When A and B both fail (e.g., model uses an unrecognized wording AND
fails to emit the audit), the user was trapped in an infinite block
loop. v9.0.1 adds a session-scoped 3-strike counter:

- New `_mcl_loop_breaker_count <event>` helper counts how many times
  the named audit event fired AFTER the most recent `session_start`
  in trace.log.
- Aşama 2 (`precision-audit-block`): on the 4th attempt, fail-open
  with `precision-audit-loop-broken` audit + `precision_audit_done`
  stays false (visible in `/mcl-checkup`).
- Aşama 8 (`phase-review-pending`): on the 4th sticky-pending turn,
  fail-open with `phase-review-loop-broken` audit + mark
  `risk_review_state=complete` so downstream Aşama 9/10/11 can
  proceed.

Trade-off: trades hard contract for soft contract on the
4th-attempt-onwards. The model gets 3 chances to recover (matching
the model's typical recovery latency); after that, the developer
is unblocked rather than trapped.

#### Tests

5 new synthetic tests (68 total, 0 failed):
- `test-v9-classifier-fallback.sh` — 5 scenarios: Şartname-fallback,
  explicit token, no-spec→summary-confirm, no-spec generic approve,
  Japanese 仕様 spec-approve.
- `test-v9-loop-breaker.sh` — 5 counter scenarios: zero baseline,
  under-threshold, threshold, session boundary, different event name.

#### Banner

- `🌐 MCL 9.0.0` → `🌐 MCL 9.0.1` everywhere.

## [9.0.0] - 2026-05-02

### Major rewrite — flat 12-stage pipeline (BREAKING)

MCL phase numbering migrates from fractional (Phase 1, 1.5, 1.7, 2, 3,
3.5, 4, 4.5, 4.6, 5, 5.5) to flat 12-stage (Aşama 1–12). State schema
v3 is incompatible with prior versions; existing `.mcl/state.json` is
reset to default on first activation under v9.0.0 (no backward-compat
migration). All skill files, hook code, audit log keys, and docs use
the new numbering.

#### New 12-stage pipeline

```
Aşama 1: Parameter gathering (was Phase 1)
Aşama 2: 7-dimension precision audit + hard enforcement (was Phase 1.7, NOW VISIBLE)
Aşama 3: Translator (was Phase 1.5; UPGRADE-TRANSLATOR for verb upgrades)
Aşama 4: Spec emit + your-language explanation + AskUserQuestion approval (was Phase 2+3 fused)
Aşama 5: Pattern Matching (was Phase 3.5, NOW VISIBLE)
Aşama 6: UI flow split (conditional, when ui_flow_active=true)
  Aşama 6a BUILD_UI / 6b UI_REVIEW / 6c BACKEND
Aşama 7: Code + TDD (was Phase 4)
Aşama 8: Risk Review — interactive AskUserQuestion dialog (was Phase 4.5 dialog parts)
Aşama 9: Quality + Tests — sequential auto-fix pipeline (was Phase 4.5 lenses + comprehensive tests)
  Aşama 9.1 code review / 9.2 simplify / 9.3 performance / 9.4 security
  Aşama 9.5 unit / 9.6 integration / 9.7 E2E / 9.8 load tests
  NO AskUserQuestion — auto-detect + auto-fix
  Soft applicability: not-applicable cases write audit + skip (yumuşak katılık)
Aşama 10: Impact Review — interactive AskUserQuestion dialog (was Phase 4.6)
Aşama 11: Verify Report (was Phase 5)
Aşama 12: Translate report EN → user_lang (was Phase 5.5)
```

#### State schema v3

- `current_phase` integer remap: `{1→1, 2→4, 4→7, 5→11}`. Validation
  range: `1 ≤ phase ≤ 11`.
- `phase_review_state` SPLIT into `risk_review_state` (Aşama 8) +
  `quality_review_state` (Aşama 9). All hook usages migrated.
- New flag: `precision_audit_done` (Aşama 2 visibility marker).
- Trace events renamed: `phase_review_pending` → `risk_review_pending`.
- Schema version bumped to 3. Old `state.json` → fresh init (no
  migration). Backup at `.mcl/state.json.pre-v9-backup`.

#### Files

- DELETED: `skills/my-claude-lang/phase3-verify.md` (Phase 3 fused into
  Aşama 4).
- RENAMED 11 skill files: `phaseN-*.md` → `asamaN-*.md`. Includes UI
  flow subdirs `phase4a-ui-build/` → `asama6a-ui-build/`.
- SPLIT: `phase4-5-risk-review.md` → `asama8-risk-review.md` (dialog) +
  `asama9-quality-tests.md` (auto-fix pipeline).
- NEW: `asama5-pattern-matching.md` (extracted from inline activate.sh
  logic into a dedicated skill artifact).

#### Hooks

- `hooks/lib/mcl-state.sh` — schema v3, validation `1 ≤ phase ≤ 11`,
  fresh init on schema mismatch, `precision_audit_done` /
  `risk_review_state` / `quality_review_state` fields, removed v1→v2
  migration, removed legacy `phase_review_state` field.
- `hooks/mcl-activate.sh` — STATIC_CONTEXT rewritten for 12-aşama
  numbering, banner version `MCL 9.0.0`, all phase references migrated.
- `hooks/mcl-pre-tool.sh` — `current_phase` integer comparisons remapped,
  JIT askq advance updated, scope guard + pattern guard reference
  Aşama 5/8.
- `hooks/mcl-stop.sh` — phase transitions {1→4, 4→7, 7→...},
  `risk_review_state` replaces `phase_review_state`, Aşama 11 skip
  detection updated, hard enforcement audit keys aligned to new
  numbering.
- `hooks/lib/mcl-askq-scanner.py`, `mcl-dispatch-audit.sh`,
  `mcl-phase-review-guard.py`, `mcl-spec-paths.py`, etc. — phase number
  refs remapped.

#### Aşama 9 — new auto-fix behavior (no dialog)

Replaces Phase 4.5 step 2 (lenses) + step 4 (comprehensive test
coverage). Eight sequential sub-steps run without AskUserQuestion:
detect issues, apply unambiguous auto-fixes, write audit entries
(`asama-9-N-start` / `asama-9-N-end findings=N fixes=M`). Soft
applicability: when a sub-step doesn't apply (E2E for CLI, load test
for calculator), audit `asama-9-N-not-applicable | reason=<why>` and
skip silently.

#### Hard enforcements (preserved)

- Aşama 2 (precision audit): Stop hook blocks Aşama 1→4 transition
  unless audit entry exists in this session.
- Aşama 8 (risk review): Stop hook blocks session-end after Aşama 7
  code if `risk_review_state ≠ complete`.
- Aşama 11 (verify report): Stop hook detects skip and forces
  Verification Report emission.

Loop-breakers (3-fail fail-open) tracked separately in v9.0.1.

#### Documentation

- `README.md`, `README.tr.md` — pipeline diagram replaced with 12-stage
  Aşama version, banner refs `MCL 9.0.0`, all Phase X references
  remapped to Aşama Y.
- `FEATURES.md` — 12-aşama feature catalog, v9.0.0 sürüm.
- `CLAUDE.md` (project) — captured rules updated to reference Aşama
  numbering.
- All 14 phase skill files internal content rewritten for new
  numbering.

#### Test

Existing 21 tests pass under v9.0.0.

### Breaking — no backward compatibility

- Old `state.json` (schema v1/v2) is reset to v3 default on first
  activation under v9.0.0. Backup written to
  `.mcl/state.json.pre-v9-backup`. In-progress task state from older
  MCL is discarded.
- Audit log entries from older MCL retain their original `phase-...`
  prefixes; new entries use `asama-...` / `risk_review_*` /
  `quality_review_*`. Mixed history is expected and acceptable.

## [8.4.5] - 2026-05-02

### Kaldırıldı — Pasif "yeni sürüm mevcut" bildirimi

`mcl-activate.sh` her turda banner'a `(⚠️ <latest> mevcut — mcl-update yaz)` lokalize uyarısını ekleyen UPDATE_NOTICE bloğunu enjekte ediyordu. Bu bildirim kaldırıldı; banner artık sadece `🌐 MCL <version>` formatında.

#### Hook
- `hooks/mcl-activate.sh` — `UPDATE_AVAILABLE` semver karşılaştırması, `UPDATE_NOTICE` enjeksiyon bloğu ve FULL_CONTEXT'teki `${UPDATE_NOTICE}` referansı silindi. LATEST_VERSION fetch + 24h cache mekanizması korundu — `/mcl-update` keyword'ünün upstream-latest raporlaması için hâlâ kullanılıyor.

#### Dokümanlar
- `README.md`, `README.tr.md` — "Updating" / "Güncelleme" bölümünden pasif kontrol paragrafı ve örnek banner çıkarıldı; `/mcl-update` self-update talimatı korundu.
- `skills/my-claude-lang/mcl-tag-schema.md` — `<mcl_audit>` kullanım örneğinden "Hook UPDATE_NOTICE prefix" maddesi silindi.

### Değişmedi
- `/mcl-update` keyword'ü tamamen aynen çalışıyor: blocking fetch ile upstream sürümü raporluyor, `git pull --ff-only && bash setup.sh` çalıştırıyor.

## [8.4.4] - 2026-05-02

### Kaldırıldı — `current_phase < 4` mutating tool bloğu

`hooks/mcl-pre-tool.sh`'in mutating-tool gate'inde iki kontrol vardı: faz numarası (`current_phase < 4`) ve onay boolean'ı (`spec_approved != true`). İki kontrol normal akışta aynı pencereyi kapatıyordu — Phase 1/2/3 ⇒ `spec_approved=false`. Faz numarası kontrolü kaldırıldı; `spec_approved` boolean'ı tek başına spec öncesi kod yazımını engellemeye yetiyor.

#### Değişiklik
- `hooks/mcl-pre-tool.sh` — `if [ "$CURRENT_PHASE" -lt 4 ]` branch'i silindi; `elif [ "$SPEC_APPROVED" != "true" ]` artık `if` olarak tek başına kalıyor.

#### Trade-off (kabul edildi)
- **Kayıp:** Defense-in-depth — `spec_approved=true` ama `current_phase<4` durumunda (state corruption / yarış) artık ikinci bir koruma yok. Hata mesajı da "current_phase=N (PHASE_NAME)" yerine sadece "spec_approved=false" gösteriyor.
- **Kazanç:** Daha sade gate — tek invariant (`spec_approved=true ⇒ Phase 4`) tüm yazma yetkisini yönetiyor.

### Banner
- Tüm `MCL 8.4.3` referansları (`🌐` banner ve `AskUserQuestion` prefix'leri) `MCL 8.4.4` olarak güncellendi.

## [8.4.3] - 2026-05-01

### Kaldırıldı — `superpowers` plugin tamamen MCL'den çıkarıldı

`superpowers` plugin'i MCL'in curated required setinde olduğu için, kurulu değilken MCL kendini kilitliyordu (mutating tool'lar bloke). Artık `superpowers` MCL'in herhangi bir parçası değil — required listesinde yok, dispatch path'lerinde yok, hook block'larında yok, dokümantasyonda yok.

#### Hook'lar
- `hooks/lib/mcl-plugin-gate.sh` — `mcl_plugin_gate_required_plugins()` artık `superpowers` döndürmüyor. Curated tier-A required = sadece `security-guidance` + stack-detected LSP plugin'leri.
- `hooks/mcl-pre-tool.sh` — `superpowers:brainstorming` Skill bloğu kaldırıldı. TodoWrite Phase 1-3 bloğunun reason metni "superpowers:brainstorming interference" referansından arındırıldı.
- `hooks/lib/mcl-dispatch-audit.sh` — Phase 4.5 code-review prefix tuple'ından `superpowers:code-reviewer` çıkarıldı. Artık sadece `pr-review-toolkit` ve `code-review` aranıyor.
- `hooks/mcl-activate.sh` STATIC_CONTEXT — `<mcl_constraint name="superpowers-scope">` bloğu tamamen silindi; sub-agent-phase-discipline ve dispatch-audit constraint'lerinden `superpowers` örnekleri çıkarıldı.

#### Skill'ler
- `skills/my-claude-lang/plugin-orchestration.md` — curated set tablosundan `superpowers` satırı silindi; phase dispatch tablosundan "Ambient" sütunu kaldırıldı; install-suggestion bloğundan ve tier-2 outcome notundan `superpowers` referansları çıkarıldı; "Out of scope" listesinden ambient methodology maddesi silindi; Phase 4.5 manifest tablosundan `superpowers:code-reviewer` çıkarıldı.
- `skills/my-claude-lang/plugin-gate.md` — curated tier-A enumeration `(security-guidance)` olarak kısaltıldı.
- `skills/my-claude-lang/plugin-suggestions.md` — orchestration-set listesinden `superpowers` çıkarıldı.
- `skills/my-claude-lang.md` — curated plugin listesinden ve "always-on ambient methodology layer" paragrafından `superpowers` referansları çıkarıldı.
- 12 phase skill dosyası (`phase1-rules`, `phase2-spec`, `phase3-verify`, `phase4-execute`, `phase4-tdd`, `phase4-5-risk-review`, `phase4-6-impact-review`, `phase4a-ui-build`, `phase4b-ui-review`, `phase4c-backend`, `phase5-review`) — her birindeki `**\`superpowers\` (tier-A, ambient):**` bullet'ı silindi.

#### Dokümanlar
- `README.md`, `README.tr.md` — Step 1 kurulum metninden `superpowers` ve `obra/superpowers-marketplace` çıkarıldı.
- `FEATURES.md` — Hook Dominance tablosundan ve listesinden `superpowers:brainstorming` satırı silindi.
- `CLAUDE.md` (proje) — devtime plan critique notundan `superpowers:code-reviewer` parantezli açıklaması çıkarıldı.
- `install-claude-plugins.sh`, `install-claude-plugins.ps1` — `obra/superpowers-marketplace` marketplace ekleme satırı ve `superpowers` install komutu kaldırıldı.

#### Test
- `tests/cases/test-plugin-gate-no-superpowers.sh` — regression: `mcl_plugin_gate_required_plugins` çıktısının `superpowers` içermediğini ve `security-guidance`'ın hâlâ listede olduğunu assert eder.

#### Banner
- Tüm `MCL 8.4.2` referansları (`🌐` banner ve `AskUserQuestion` prefix'leri) `MCL 8.4.3` olarak güncellendi.

### Geriye dönük uyumluluk

Bu kaldırma kırıcı bir değişiklik değildir — `superpowers` MCL tarafından zaten zorunlu kılınıyordu, çıkarılması mevcut MCL kullanıcıları için yalnızca bir kilit kaldırma anlamına geliyor. `superpowers`'ı manuel olarak yüklemiş olanlar için davranış değişmiyor: MCL artık onu hiçbir şekilde dispatch etmiyor veya gate'lemiyor.

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
