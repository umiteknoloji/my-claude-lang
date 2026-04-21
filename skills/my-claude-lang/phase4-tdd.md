<mcl_phase name="phase4-tdd">

# Phase 4 TDD: mandatory batch TDD

**`superpowers` (tier-A, ambient):** active throughout this overlay (both test-writing and code-writing sub-phases) — no explicit dispatch point; its methodology layer applies as a behavioral prior.

Phase 4 normally writes production code immediately after the spec
is approved. This overlay turns that into a **batch TDD cycle**:
all tests first, RED baseline, all code, GREEN verify. The cycle
happens entirely inside Phase 4; Phase 4.5, Phase 4.6, and Phase 5
run afterward as usual.

TDD is **mandatory** — it runs on every Phase 4 execution. There
is no opt-in flag. The only path that skips TDD is when the test
command cannot be resolved even after auto-detection and the
developer explicitly declines to provide one (see Step 1).

<mcl_constraint name="tdd-batch-flow">

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
   skipped (e.g., MCL was installed mid-session). Ask the developer
   ONE question in their language:

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

## Step 3 — Test-writing sub-phase

Before any production code is touched, walk every Acceptance
Criterion from the Phase 2 spec and write a corresponding test
case. All tests go into the project's existing test files (or new
files matching the project's test layout). New test file paths
MUST match whatever pattern the resolved command picks up (e.g. if
the command is `node --test 'test/*.test.mjs'`, a new file must
live at `test/<name>.test.mjs` or the runner will never execute
it). The test framework is whatever the resolved command runs —
do not introduce a different framework.

Do NOT write production code in this step. If the implementation
does not yet exist, the test is expected to fail at the next
step; that is the point of a RED baseline.

## Step 4 — RED baseline

Invoke the runner with label `red-baseline`:

```
bash ~/.claude/hooks/lib/mcl-test-runner.sh red-baseline
```

Paste the runner's stdout **verbatim** under a localized header.
Examples:

- Turkish: `🔴 RED taban (kod öncesi)`
- English: `🔴 RED baseline (pre-code)`
- Spanish: `🔴 Línea base RED (antes del código)`
- French: `🔴 Base RED (avant le code)`
- German: `🔴 RED-Basislinie (vor Code)`
- Portuguese: `🔴 Linha base RED (pré-código)`
- Russian: `🔴 RED базовый (до кода)`
- Arabic: `🔴 الأساس الأحمر (قبل الكود)`
- Hindi: `🔴 RED आधार रेखा (कोड से पहले)`
- Hebrew: `🔴 בסיס RED (לפני הקוד)`
- Japanese: `🔴 RED ベースライン (コード前)`
- Korean: `🔴 RED 베이스라인 (코드 이전)`
- Chinese: `🔴 RED 基线 (代码前)`
- Indonesian: `🔴 Baseline RED (sebelum kode)`

## Step 5 — RED baseline interpretation

The runner result is informational, not a gate. React to it:

- **All tests fail (expected)** — proceed to Step 6 silently. The
  RED block is already visible; no extra commentary needed. Do NOT
  emit a transitional sentence like "proceeding to code" or "koda
  geçiliyor" — the RED block IS the transition; a trailing prose
  line is noise.
- **Some tests pass** — flag to the developer in their language
  before proceeding:

  > Bazı testler RED tabanında geçti. Bu testler ya zaten mevcut
  > davranışı ölçüyor ya da yeterince sıkı değil. Koda geçmeden
  > önce gözden geçirin.

  English equivalent:

  > Some tests passed on RED baseline. They either exercise
  > already-implemented behavior or are not tight enough. Review
  > before proceeding to code.

  This is non-blocking. Proceed after the developer acknowledges
  or says continue.
- **All tests pass** — stronger warning, same non-blocking stance:

  > Tüm testler RED tabanında geçti. Ya özellik zaten mevcut, ya
  > testler spec'i egzersiz etmiyor. Onayınız olmadan koda
  > geçmiyorum.

  English:

  > All tests passed on RED baseline. Either the feature already
  > exists or the tests do not exercise the spec. Not proceeding
  > to code without your confirmation.

  Wait for the developer's call.

## Step 6 — Code-writing sub-phase

Write production code so the tests pass. Minimum-to-green is NOT
required (this is batch TDD, not strict red-green-refactor);
normal spec-aligned implementation is expected.

## Step 7 — GREEN verify

Invoke the runner a second time with label `green-verify`:

```
bash ~/.claude/hooks/lib/mcl-test-runner.sh green-verify
```

Paste stdout verbatim under a localized header:

- Turkish: `🟢 GREEN doğrulama (kod sonrası)`
- English: `🟢 GREEN verify (post-code)`
- Spanish: `🟢 Verificación GREEN (post-código)`
- French: `🟢 Vérification GREEN (après code)`
- German: `🟢 GREEN-Prüfung (nach Code)`
- Portuguese: `🟢 Verificação GREEN (pós-código)`
- Russian: `🟢 GREEN проверка (после кода)`
- Arabic: `🟢 التحقق الأخضر (بعد الكود)`
- Hindi: `🟢 GREEN सत्यापन (कोड के बाद)`
- Hebrew: `🟢 אימות GREEN (אחרי הקוד)`
- Japanese: `🟢 GREEN 検証 (コード後)`
- Korean: `🟢 GREEN 검증 (코드 이후)`
- Chinese: `🟢 GREEN 验证 (代码后)`
- Indonesian: `🟢 Verifikasi GREEN (pasca-kode)`

If GREEN verify comes back RED or TIMEOUT, do NOT silently
continue. Surface the failure, diagnose, and iterate (either fix
the production code or — if a test itself is wrong — fix the
test and re-run GREEN verify). Only proceed to Phase 4.5 after a
GREEN result.

## Phase transition

After a GREEN verify, Phase 4 is complete. Phase 4.5 (Risk
Review) and Phase 4.6 (Impact Review) run exactly as usual. The
Phase 5 Verification Report then cites the Phase 4 GREEN verify
instead of re-invoking the runner — see `phase5-review.md` for
the exact summary-line format.

## Audit trail

Each runner invocation writes one audit entry with the
appropriate label:

```
test-run | runner | label=red-baseline  result=RED   exit=1 ...
test-run | runner | label=green-verify  result=GREEN exit=0 ...
```

The two labels let log-consumers distinguish the two moments of
a single TDD cycle.

</mcl_constraint>

</mcl_phase>
