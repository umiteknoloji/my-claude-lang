<mcl_phase name="phase4-tdd">

# Phase 4 TDD: opt-in batch TDD overlay

**`superpowers` (tier-A, ambient):** active throughout this overlay (both test-writing and code-writing sub-phases) — no explicit dispatch point; its methodology layer applies as a behavioral prior.

Phase 4 normally writes production code immediately after the spec
is approved. This overlay turns that into a **batch TDD cycle**:
all tests first, RED baseline, all code, GREEN verify. The cycle
happens entirely inside Phase 4; Phase 4.5, Phase 4.6, and Phase 5
run afterward as usual.

TDD is **opt-in**. It activates only when `.mcl/config.json`
carries `"tdd": true` AND a non-empty `test_command`. When either
is missing, this file is a silent no-op and normal Phase 4 runs.

<mcl_constraint name="tdd-batch-flow">

## Step 1 — Activation check

Before writing any production code in Phase 4, read the opt-in
flag:

```
bash ~/.claude/hooks/lib/mcl-config.sh get tdd
```

If the output is anything other than `true` (including empty),
this entire constraint is a no-op. Proceed with normal Phase 4.

## Step 2 — Precondition check

If `tdd=true` but `test_command` is empty:

```
bash ~/.claude/hooks/lib/mcl-config.sh get test_command
```

Warn the developer in their language, then fall through to non-TDD
Phase 4. Example Turkish wording:

> TDD modu etkin ama `.mcl/config.json` içinde `test_command`
> tanımlı değil. Runner olmadan RED/GREEN ölçülemez —
> normal Phase 4 akışına düşülüyor.

Example English wording:

> TDD mode is enabled but `.mcl/config.json` does not declare
> `test_command`. Without a runner, RED/GREEN cannot be
> measured — falling back to non-TDD Phase 4.

## Step 3 — Test-writing sub-phase

Before any production code is touched, walk every Acceptance
Criterion from the Phase 2 spec and write a corresponding test
case. All tests go into the project's existing test files (or new
files matching the project's test layout). New test file paths
MUST match whatever pattern `test_command` picks up (e.g. if
`test_command` is `node --test 'test/*.test.mjs'`, a new file
must live at `test/<name>.test.mjs` or the runner will never
execute it). The test framework is whatever `test_command` runs
— do not introduce a different framework.

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
