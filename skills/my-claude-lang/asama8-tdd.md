<mcl_phase name="asama8-tdd">

# Aşama 8 TDD: incremental red-green-refactor

Aşama 8 normally writes production code immediately after the spec
is approved. This overlay turns that into an **incremental TDD cycle**:
for each Acceptance Criterion, one test → RED → minimum code → GREEN
→ refactor — then move to the next criterion. The full cycle happens
entirely inside Aşama 8; the next phase (Risk Review), Aşama 10
(Impact Review in v10 numbering), and Aşama 11 (Verification Report
in v10 numbering) run afterward as usual.

TDD is **mandatory** — it runs on every Aşama 8 execution. There
is no opt-in flag. The only path that skips TDD is when the test
command cannot be resolved even after auto-detection and the
developer explicitly declines to provide one (see Step 1).

<mcl_constraint name="tdd-incremental-flow">

## Step 1 — Resolve the test command

Before writing any production code in Aşama 7, resolve the test
command in this order:

1. **Explicit config** — read `test_command` from `.mcl/config.json`:

   ```
   bash ~/.claude/hooks/lib/mcl-config.sh get test_command
   ```

   If non-empty, use it.

2. **Framework auto-detect** — if config is empty, inspect the
   project root (`$CLAUDE_PROJECT_DIR`) for a recognized manifest
   and derive the command:

   | Manifest                             | Derived command          |
   | ------------------------------------ | ------------------------ |
   | `package.json` with `scripts.test`   | `npm test`               |
   | `pyproject.toml` (pytest detected)   | `pytest`                 |
   | `Cargo.toml`                         | `cargo test`             |
   | `go.mod`                             | `go test ./...`          |
   | `pom.xml`                            | `mvn test`               |
   | `build.gradle` or `build.gradle.kts` | `gradle test`            |

   The helper `mcl_test_detect_command` in
   `hooks/lib/mcl-test-runner.sh` encodes this mapping. First match
   wins; multi-manifest projects (e.g. JS frontend + Python backend)
   fall through to `test_command` config if the developer wants a
   composed runner.

3. **Developer prompt** — normally this case never hits in Aşama 7
   because `asama1-gather.md`'s Test-Command Resolution pre-flow
   already resolved it on the first developer message. This option
   is a defensive fallback for sessions where Aşama 1 pre-flow was
   skipped. Ask the developer ONE question in their language:

   > Turkish: *Testler hangi komutla koşuyor? ('yok' dersen TDD
   > bu session için atlanır.)*
   >
   > English: *What command runs the tests? (type 'none' to skip
   > TDD for this session.)*

   - Non-empty answer → use it for this session; offer to persist
     to `.mcl/config.json` as `test_command`.
   - `none` / equivalent → fall through to non-TDD Aşama 7 with
     the warning in Step 2. This is the ONLY path that skips TDD.

## Step 2 — Precondition warning (only when Step 1 returned 'none')

If Step 1 could not resolve a command AND the developer explicitly
declined, warn in their language then proceed with normal Aşama 7
(no RED/GREEN cycle):

> Turkish: *TDD bu session için atlanıyor — koşulabilir bir test
> komutu yok. Test altyapısı eklendiğinde MCL otomatik devreye
> girer.*
>
> English: *TDD is skipped for this session — no runnable test
> command is available. MCL will auto-engage once a test setup
> exists.*

In every other case (command resolved via config, auto-detect, or
developer prompt) TDD continues with Step 3.

## Step 3 — Incremental TDD loop (repeat per Acceptance Criterion)

Work through each Acceptance Criterion from the Aşama 4 spec **one
at a time**. For each criterion, execute sub-steps A through E
before moving to the next criterion.

### A. Write the smallest possible failing test

Write ONE test for this criterion — the smallest test that will
fail for exactly one reason: the criterion is not yet implemented.

- Do NOT write tests for multiple criteria at once.
- Do NOT write the production code yet.
- New test files MUST match whatever path pattern the resolved
  command picks up (e.g. `test/*.test.mjs`, `tests/test_*.py`).
  Do not introduce a different test framework.

### B. RED verify

Invoke the runner with label `red-baseline`:

```
bash ~/.claude/hooks/lib/mcl-test-runner.sh red-baseline
```

Paste the runner's stdout **verbatim** under a localized header:

- Turkish: `🔴 RED doğrulama (criterion N)`
- English: `🔴 RED verify (criterion N)`
- Spanish: `🔴 Verificación RED (criterio N)`
- French: `🔴 Vérification RED (critère N)`
- German: `🔴 RED-Prüfung (Kriterium N)`
- Portuguese: `🔴 Verificação RED (critério N)`
- Russian: `🔴 RED проверка (критерий N)`
- Arabic: `🔴 التحقق الأحمر (المعيار N)`
- Hindi: `🔴 RED सत्यापन (मानदंड N)`
- Hebrew: `🔴 אימות RED (קריטריון N)`
- Japanese: `🔴 RED 検証 (基準 N)`
- Korean: `🔴 RED 검증 (기준 N)`
- Chinese: `🔴 RED 验证 (标准 N)`
- Indonesian: `🔴 Verifikasi RED (kriteria N)`

**Interpreting the result:**
- **New test fails (expected)** — proceed to C silently. Do NOT
  emit a transitional sentence — the RED block IS the transition.
- **New test passes immediately** — STOP. The assertion may be
  trivially true, or the code already satisfies this criterion.
  Surface to the developer in their language and wait for their
  call before proceeding.
- **Pre-existing tests fail** — a previous cycle broke something.
  Diagnose and fix before continuing.

### C. Write the minimum production code

Write only enough production code to make THIS test pass. No more.

- No future-proofing beyond what the failing test demands.
- No infrastructure for criteria not yet reached.
- Hardcode values if that is genuinely the minimum (it rarely is,
  but do not over-engineer to avoid it).

### D. GREEN verify

Invoke the runner a second time with label `green-verify`:

```
bash ~/.claude/hooks/lib/mcl-test-runner.sh green-verify
```

Paste stdout verbatim under a localized header:

- Turkish: `🟢 GREEN doğrulama (criterion N)`
- English: `🟢 GREEN verify (criterion N)`
- Spanish: `🟢 Verificación GREEN (criterio N)`
- French: `🟢 Vérification GREEN (critère N)`
- German: `🟢 GREEN-Prüfung (Kriterium N)`
- Portuguese: `🟢 Verificação GREEN (critério N)`
- Russian: `🟢 GREEN проверка (критерий N)`
- Arabic: `🟢 التحقق الأخضر (المعيار N)`
- Hindi: `🟢 GREEN सत्यापन (मानदंड N)`
- Hebrew: `🟢 אימות GREEN (קריטריון N)`
- Japanese: `🟢 GREEN 検証 (基準 N)`
- Korean: `🟢 GREEN 검증 (기준 N)`
- Chinese: `🟢 GREEN 验证 (标准 N)`
- Indonesian: `🟢 Verifikasi GREEN (kriteria N)`

If GREEN verify comes back RED or TIMEOUT: surface the failure,
diagnose, and fix. Only move to E after all tests pass.

### E. Refactor

With tests GREEN, improve the code's internal quality without
changing its behavior:

- Remove duplication (DRY — across this criterion's code AND
  earlier criteria's code).
- Improve naming: variables, functions, modules.
- Extract a function or module if it makes intent clearer.
- Delete dead code and fast-coding artifacts (temporary prints,
  scaffolding comments).

**Hard limits:**
- Do NOT add behavior not demanded by the current test.
- Do NOT fix bugs that have no test — write a test first.
- Do NOT refactor into a design that has not been tested yet.

After refactoring, run the test runner once more (no label needed)
to confirm tests are still GREEN. If any test turns RED: the
refactor changed behavior — revert the change and try a smaller
refactor.

### F. Next criterion

Move to the next Acceptance Criterion and repeat from A.

## Step 4 — Final full-suite run

After all criteria are complete, invoke the runner one final time
to catch regressions between criteria (label: `green-verify`):

```
bash ~/.claude/hooks/lib/mcl-test-runner.sh green-verify
```

- GREEN → Aşama 7 is complete; proceed to Aşama 8.
- RED → a criterion's code broke another criterion's tests.
  Surface the failing test as a Aşama 8 risk (do not iterate
  silently — the developer must see the regression).

## Step 5 — Backend Wiring (UI Flow Path)

This step runs **only** when `ui_flow_active=true` and the developer
has approved the UI in Aşama 7 (`ui_sub_phase` advanced to `"BACKEND"`
by the Stop hook). When `ui_flow_active=false`, skip this step
entirely — TDD already covers the full execution path.

When this step runs, it owns the swap from Aşama 6's dummy fixtures
to real data sources. The spec has not changed — the same MUST /
SHOULD requirements approved in Aşama 4 still apply. This is
execution, not re-specification.

(Content folded from `asama6c-backend.md` in v10.1.18; that file
is removed because the v11 architecture merges backend wiring into
this phase rather than keeping it as a separate Aşama 6c.)

### Path Discipline Change

On entry to this step, `mcl-pre-tool.sh` lifts the UI-BUILD path
restriction because `ui_sub_phase` is now `"BACKEND"`. All paths are
open again, subject to the standard Aşama 7 gate (spec approved,
phase = 4). Frontend edits are still allowed — there is no new
restriction in the opposite direction.

### Procedure

1. Grep the frontend for `MOCK_` / `__fixtures__/` prefixes and the
   Aşama 6 files that import them. Enumerate the swap-sites.
2. Write backend code in the conventional project location:
   - Next.js: `src/app/api/<route>/route.ts`
   - SvelteKit: `src/routes/<route>/+server.ts`
   - Express/Fastify: `src/api/<route>.ts`
   - Nuxt: `server/api/<route>.ts`
3. Write the data layer:
   - ORM schema / migration under `prisma/` / `drizzle/` when
     detected
   - Query functions under `src/lib/db/` or project-conventional
     service path
4. Replace frontend fixtures with real calls:
   - `const MOCK_USER` becomes `const user = await fetchUser()`
   - State toggle hook (`useState<MockState>`) becomes real async
     state (TanStack Query, SWR, or the project's existing pattern)
   - Error state wired to caught rejections; loading wired to
     pending state; empty wired to empty response
5. Update `.env.example` (never `.env`) with any new required keys.
   Surface them to the developer with install/setup instructions.
6. Run the test runner if `test_command` is configured (Step 1
   above) — failures block Aşama 8 exit.

### Preserve the Type Contract

The TypeScript types written alongside Aşama 6 fixtures
(`src/types/user.ts` etc.) stay as-is. The real API returns data
matching the same shape; the type is the boundary. If the real
backend differs from the fixture shape, STOP and surface the
mismatch to the developer as a Aşama 1-4 micro-cycle — do not
silently change the type.

<!-- v11: will move to Aşama 19, do not execute here.
     Mock-data cleanup is parked under v11 plan R7 — the verification
     report (Aşama 19) owns this responsibility, not the TDD execute
     phase (Aşama 8). Until R7 ships, this block stays inert: do
     NOT execute these deletions during Aşama 7/8 even though the
     prose below describes them — they will be triggered later by
     Aşama 19 in the v11 architecture.

### Remove Dev-Only Bits (DEFERRED — see fence above)

Delete:
- `?state=...` URL-param hooks whose purpose was visual state toggle
- `<select>` dev toggles that expose mock-state switching
- `__fixtures__/<name>.fixture.ts` files that have no remaining
  importers (grep before deleting)

Keep:
- Type definitions from `src/types/` — real code uses them
- Any fixture that is also used by test files (the swap targets
  component imports; Jest/Vitest test imports stay)
-->

### Phase Behavior Notes

- This step inherits all of `asama8-execute.md` discipline (English
  code/comments/commits, dev-language communication, Gate 1/2/3,
  deletion-only execution-plan rule, scope-creep handling).
- This step does NOT re-implement those rules — it is Aşama 7
  execution with the UI already committed. Think of it as the
  second half of the `ui_flow_active = true` execution pair.
- Aşama 11's Verification Report "must-test" list MUST include:
  - UI interaction verification (click primary button, form submit, etc.)
  - Real backend verification (network panel shows `POST /api/...`,
    status 200, payload matches type)
  - Error-path verification (what happens when the backend returns 500)

## Phase transition

After a final GREEN verify (and Step 5 backend wiring if
`ui_flow_active=true`), Aşama 7 is complete. Aşama 8 (Risk
Review) and Aşama 10 (Impact Review) run as usual. The Aşama 11
Verification Report cites the Aşama 7 GREEN verify instead of
re-invoking the runner — see `asama19-verify-report.md` for the exact
summary-line format.

## Audit trail

Each runner invocation writes one audit entry with the appropriate
label:

```
test-run | runner | label=red-baseline  result=RED   exit=1 ...
test-run | runner | label=green-verify  result=GREEN exit=0 ...
```

Refactor-confirm runs (no label) are not audited unless they fail.

</mcl_constraint>

</mcl_phase>
