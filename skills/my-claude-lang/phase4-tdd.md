<mcl_phase name="phase4-tdd">

# Phase 4 TDD: incremental red-green-refactor

**`superpowers` (tier-A, ambient):** active throughout this overlay — no explicit dispatch point; its methodology layer applies as a behavioral prior.

Phase 4 normally writes production code immediately after the spec
is approved. This overlay turns that into an **incremental TDD cycle**:
for each Acceptance Criterion, one test → RED → minimum code → GREEN
→ refactor — then move to the next criterion. The full cycle happens
entirely inside Phase 4; Phase 4.5, Phase 4.6, and Phase 5 run
afterward as usual.

TDD is **mandatory** — it runs on every Phase 4 execution. There
is no opt-in flag. The only path that skips TDD is when the test
command cannot be resolved even after auto-detection and the
developer explicitly declines to provide one (see Step 1).

<mcl_constraint name="tdd-incremental-flow">

## Step 1 — Resolve the test command

Before writing any production code in Phase 4, resolve the test
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

3. **Developer prompt** — normally this case never hits in Phase 4
   because `phase1-rules.md`'s Test-Command Resolution pre-flow
   already resolved it on the first developer message. This option
   is a defensive fallback for sessions where Phase 1 pre-flow was
   skipped. Ask the developer ONE question in their language:

   > Turkish: *Testler hangi komutla koşuyor? ('yok' dersen TDD
   > bu session için atlanır.)*
   >
   > English: *What command runs the tests? (type 'none' to skip
   > TDD for this session.)*

   - Non-empty answer → use it for this session; offer to persist
     to `.mcl/config.json` as `test_command`.
   - `none` / equivalent → fall through to non-TDD Phase 4 with
     the warning in Step 2. This is the ONLY path that skips TDD.

## Step 2 — Precondition warning (only when Step 1 returned 'none')

If Step 1 could not resolve a command AND the developer explicitly
declined, warn in their language then proceed with normal Phase 4
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

Work through each Acceptance Criterion from the Phase 2 spec **one
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

- GREEN → Phase 4 is complete; proceed to Phase 4.5.
- RED → a criterion's code broke another criterion's tests.
  Surface the failing test as a Phase 4.5 risk (do not iterate
  silently — the developer must see the regression).

## Phase transition

After a final GREEN verify, Phase 4 is complete. Phase 4.5 (Risk
Review) and Phase 4.6 (Impact Review) run as usual. The Phase 5
Verification Report cites the Phase 4 GREEN verify instead of
re-invoking the runner — see `phase5-review.md` for the exact
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
