<mcl_phase name="asama19-verify-report">

# Aşama 19: Verification Report (was Aşama 11 in v10)

Aşama 11 is NOT just a review translation. It is a comprehensive verification
that gives the developer confidence that the AI did the right thing.

## When Aşama 11 Runs

After **Aşama 10 (Post-Risk Impact Review)** is fully resolved — i.e.
every impact MCL surfaced has been answered by the developer (skip /
apply fix / make general rule), and Aşama 8 before it is also
resolved — MCL MUST produce the Verification Report. This is NOT
optional. Aşama 10 is NOT the last step.

If you wrote code and stopped without running Aşama 8, Aşama 10
AND emitting this report, you skipped phases — go back and produce
all of them.

⛔ STOP RULE: Aşama 7 does NOT end with "done" or a summary of changes.
Aşama 7 hands off to Aşama 8; Aşama 8 hands off to Aşama 10;
Aşama 10 hands off to Aşama 11. Aşama 11 is the last step. If you find
yourself writing "all steps completed" without any of the sections
below, you are violating this rule.

<mcl_constraint name="test-runner-orchestration">

## Test Runner Orchestration (opt-in)

When the developer has opted in by declaring a non-empty `test_command`
in `$(pwd)/.mcl/config.json`, MCL MUST invoke the test runner during
Aşama 11 **before** emitting Section 1 of the Verification Report.

How:
1. Check config via `bash ~/.claude/hooks/lib/mcl-config.sh get test_command`.
2. If the output is empty, skip this step entirely — there is no opt-in.
3. Otherwise invoke `bash ~/.claude/hooks/lib/mcl-test-runner.sh` via the
   Bash tool in the developer's project root.
4. Paste the runner's stdout **verbatim** at the very top of the
   Verification Report — above any other section, before Section 1.

The runner emits one of three formatted blocks (GREEN / RED / TIMEOUT)
with duration and an optional fenced `text` block carrying merged
stdout+stderr. Do not reformat, summarize, or translate the runner's
output — it is a fixed-format machine block the developer reads directly.

Failure is NOT a gate. A RED or TIMEOUT result is information for the
developer; MCL still emits the full Verification Report below it. The
runner is orchestration, not enforcement.

When `test_command` is absent or empty, this constraint is a no-op —
the Verification Report proceeds exactly as specified elsewhere in this
phase file.

### TDD mode — skip re-invocation

When `tdd=true` (see `asama8-tdd.md`) AND Aşama 7 **or Aşama 8**
has already emitted a `🟢 GREEN verify` block in this session, DO NOT
invoke the runner again here. Aşama 11 starts instead with a localized
TDD-cycle summary line. Examples:

- Aşama 7 GREEN only (no Aşama 8 re-verify):
  - Turkish: `✅ TDD döngüsü: RED taban → GREEN doğrulama tamamlandı`
  - English: `✅ TDD cycle: RED baseline → GREEN verify complete`
- Aşama 7 GREEN + Aşama 8 re-verify GREEN:
  - Turkish: `✅ TDD döngüsü: RED taban → GREEN doğrulama → Aşama 8 re-doğrulama tamamlandı`
  - English: `✅ TDD cycle: RED baseline → GREEN verify → Aşama 8 re-verify complete`

Then proceed to Section 1. A double (or triple) runner invocation
would be noise — the earlier GREEN blocks already carry the diagnostic
information. This skip applies ONLY when a GREEN verify has happened;
if TDD mode was enabled but fell through due to missing `test_command`,
the normal Aşama 11 runner invocation above still applies.

The TDD-cycle summary line is MANDATORY whenever a GREEN verify
happened in Aşama 7 or Aşama 8 — even when Aşama 8 and Aşama 10
both emitted nothing (their "omit entirely" rule does not extend to
this line). The summary is the single most compact proof to the
developer that the runner blocks were the ground truth Aşama 11 is
standing on; without it, Aşama 11 opens with nothing tying back to
the TDD cycle.

</mcl_constraint>

The report has **up to three** sections, in this order: Spec Compliance,
must-test, Process Trace. Any section whose content is empty is **omitted
entirely** (no header, no placeholder sentence, no filler). Section 1 in
particular is omitted when every MUST/SHOULD is satisfied — the
absence of the section IS the all-clear signal.
(Prior to MCL 5.4.0 the report had a third section, Impact Analysis,
which was extracted into its own Aşama 10 interactive dialog;
prior to MCL 5.3.0 the report had 4 sections with Missed Risks
embedded; prior to MCL 5.2.0 it had 5 with a Permission Summary.
All are removed.)

## Section 1: Spec Compliance — Mismatches Only

Walk every MUST and SHOULD requirement from the Aşama 4 spec, but
**only report items that did NOT fully comply**. Use ⚠️ for partial
compliance and ❌ for missing/failed items.

```
📋 Spec Uyumluluğu:
❌ MUST: [requirement] → EKSİK: [what's missing]
⚠️ SHOULD: [requirement] → Kısmen: [what's partial, what's not]
```

If EVERY MUST and SHOULD requirement is fully satisfied, OMIT
Section 1 entirely — no "📋 Spec Uyumluluğu:" header, no "All
MUST/SHOULD items comply." sentence, no placeholder of any kind.
Proceed directly to Section 2. The absence of Section 1 IS the
all-clear signal.

Do NOT list satisfied items. Do NOT emit a table of ✅ lines. Do NOT
emit a consolation sentence. The developer reads the spec; they do
not need every green check restated — and they do not need a
placeholder telling them there is nothing to read.

## Section 2: `!!! <LOCALIZED-MUST-TEST-PHRASE> !!!`

Items the developer MUST verify in a running environment — because the
sandboxed Claude cannot. This list must reflect both Aşama 8 and
Aşama 10 decisions (tests for applied fixes; acceptance smoke for
skipped risks; regression coverage for impacted consumers).

The section title MUST be wrapped in `!!! ... !!!` and rendered in the
developer's detected language:

- Turkish: `!!! MUTLAKA TEST ETMENİZ GEREKENLER !!!`
- English: `!!! YOU MUST TEST THESE !!!`
- Spanish: `!!! DEBES PROBAR ESTO !!!`
- Japanese: `!!! 必ずテストしてください !!!`
- Korean: `!!! 반드시 테스트해야 할 것들 !!!`
- Arabic: `!!! يجب عليك اختبار هذه !!!`
- Hindi: `!!! आपको इनका परीक्षण अवश्य करना चाहिए !!!`
- Portuguese: `!!! VOCÊ DEVE TESTAR ISSO !!!`
- French: `!!! VOUS DEVEZ TESTER CECI !!!`
- German: `!!! SIE MÜSSEN DAS TESTEN !!!`
- Chinese: `!!! 您必须测试这些 !!!`
- Russian: `!!! ВЫ ДОЛЖНЫ ПРОТЕСТИРОВАТЬ ЭТО !!!`
- Hebrew: `!!! עליך לבדוק את אלה !!!`
- Indonesian: `!!! ANDA HARUS MENGUJI INI !!!`

The emphatic wrapping and localization are NOT optional. Never use
the old "Test Checklist" / "🧪 Test Kontrol Listesi" label.

Content format:

```
!!! MUTLAKA TEST ETMENİZ GEREKENLER !!!
- [ ] [Step 1: specific action → expected result]
- [ ] [Step 2: specific action → expected result]
- [ ] [Edge case test from Aşama 4 spec]
- [ ] [Regression test for consumers surfaced in Aşama 10]
- [ ] [Smoke test for any risk the developer skipped in Aşama 8]
```

Tests must be:
- Specific (not "test the feature" but "click X button, expect Y")
- Cover the golden path (happy case)
- Cover edge cases from the spec
- Cover regression for consumers surfaced in Aşama 10
- Cover residual exposure from Aşama 8 skipped risks

## Section 3: Process Trace (MCL 6.3.0+)

A one-line-per-step localized rendering of `.mcl/trace.log` so the
developer can verify that MCL actually ran every phase, dispatched
the plugins it claimed to, and advanced state on approval — not just
claimed it in prose. The trace is written by the hooks (deterministic,
not model-compliance-dependent); Aşama 11 reads and renders it.

How:

1. Read `.mcl/trace.log` via the Read tool. If the file does not
   exist or is empty, OMIT Section 3 entirely — no header, no
   placeholder. (The file is created by `hooks/lib/mcl-trace.sh` on
   the first event of a session; its absence means no MCL-driven
   events fired, which is itself diagnostic but not a Aşama 11
   rendering concern.)
2. Parse each line as `<ISO-8601 UTC> | <event_key> | <csv-args>`.
3. Emit a localized section header, then ONE bullet per event
   describing what happened in the developer's language. The
   `event_key` is English (stable machine token); the prose around
   it is in the developer's language. Keep each bullet to a single
   short sentence.

Localized section header:

- Turkish: `📜 Süreç İzlemesi:`
- English: `📜 Process Trace:`
- Spanish: `📜 Traza del Proceso:`
- French: `📜 Trace du Processus:`
- German: `📜 Prozess-Trace:`
- Japanese: `📜 プロセストレース:`
- Korean: `📜 프로세스 추적:`
- Chinese: `📜 流程追踪：`
- Arabic: `📜 تتبع العملية:`
- Hindi: `📜 प्रक्रिया ट्रेस:`
- Portuguese: `📜 Rastreamento do Processo:`
- Russian: `📜 Трассировка Процесса:`
- Hebrew: `📜 מעקב תהליך:`
- Indonesian: `📜 Jejak Proses:`

Event → localized prose mapping (use as a semantic key; render ONE
short sentence per event in the developer's language):

- `session_start,<version>` → "MCL `<version>` oturumu başladı." / "MCL `<version>` session started."
- `stack_detected,<tags>` → "Stack algılandı: `<tags>`." / "Stack detected: `<tags>`."
- `phase_transition,<from>,<to>` → "Faz `<from>` → `<to>`." / "Phase `<from>` → `<to>`."
- `summary_confirmed,ui_enabled` → "Özet onaylandı (UI akışı açık)." / "Summary confirmed (UI flow on)."
- `summary_confirmed,ui_skipped` → "Özet onaylandı (UI atlandı)." / "Summary confirmed (UI skipped)."
- `spec_approved,<hash12>` → "Spec onaylandı (`<hash12>`)." / "Spec approved (`<hash12>`)."
- `ui_flow_enabled` → "UI akışı BUILD_UI'ya girdi." / "UI flow entered BUILD_UI."
- `ui_review_approved` → "UI review onaylandı → BACKEND." / "UI review approved → BACKEND."
- `plugin_dispatched,<subagent>` → "Plugin çağrıldı: `<subagent>`." / "Plugin dispatched: `<subagent>`."
- Unknown event key → render it verbatim as a single bullet, do
  NOT omit. Future events added to the hook library will surface
  here even if this skill file has not been updated.

Format each bullet with the ISO timestamp trimmed to `HH:MM:SSZ`
(date prefix dropped — the full session runs in a short window):

```
📜 Süreç İzlemesi:
- 14:32:01Z — MCL 6.3.0 oturumu başladı.
- 14:32:01Z — Stack algılandı: typescript,react.
- 14:34:12Z — Faz 1 → 2.
- 14:35:08Z — Özet onaylandı (UI akışı açık).
- 14:37:44Z — Spec onaylandı (a1b2c3d4e5f6).
- 14:37:44Z — Faz 3 → 4.
- 14:40:12Z — Plugin çağrıldı: code-reviewer.
- 14:55:02Z — UI review onaylandı → BACKEND.
```

Rules:

- Do NOT dedupe or reorder events; the chronological order is the
  signal.
- Do NOT summarize with "N events fired" — render every line; the
  developer is checking specific steps happened, a count does not
  help.
- If `.mcl/trace.log` has more than 50 lines, render the first 5
  and the last 40 with a single localized bridge line between them
  (Turkish: `… (X ara olay atlandı) …` / English: `… (X middle events elided) …`).
  The head tells the reader how the session started; the tail tells
  them what just happened.
- This section is subject to the empty-section-omission rule — if
  the file is missing or empty, Section 3 vanishes cleanly.

## Presentation Rules

- ALL sections are in the developer's language
- Code snippets and file names stay in English
- Do NOT include a Missed Risks section — Aşama 8 handled that
- Do NOT include an Impact Analysis section — Aşama 10 handled that
- Do NOT include a Permission Summary section — removed in MCL 5.2.0
- Do NOT list ✅-compliant items in Section 1 — mismatches only
- After the full report, ask: "Do you understand everything? (yes / no)"
  If "no" → re-explain the unclear part
- The report is part of MCL's response — it is NOT optional

## Tail Reminder — `mcl-finish` (MCL 5.14.0+)

Every Aşama 11 Verification Report MUST end with a single localized
reminder line pointing at the `mcl-finish` slash-command. The line
sits AFTER Section 2 (the must-test checklist) as the final
user-facing line of the report. Its purpose is to keep the
session-local developer aware that Aşama 10 impacts are
accumulating on disk and a cross-session finish pass is one
keyword away.

Localized forms:

- Turkish: `Son kontroller için \`mcl-finish\` yazın.`
- English: `Type \`mcl-finish\` for final cross-session checks.`
- Spanish: `Escribe \`mcl-finish\` para las verificaciones finales entre sesiones.`
- French: `Tapez \`mcl-finish\` pour les vérifications finales inter-sessions.`
- German: `Geben Sie \`mcl-finish\` für abschließende sitzungsübergreifende Prüfungen ein.`
- Japanese: `セッション横断の最終確認は \`mcl-finish\` と入力してください。`
- Korean: `세션 간 최종 확인은 \`mcl-finish\` 를 입력하세요.`
- Chinese: `输入 \`mcl-finish\` 进行跨会话的最终检查。`
- Arabic: `اكتب \`mcl-finish\` لإجراء فحوصات نهائية عبر الجلسات.`
- Hindi: `सत्रों के बीच अंतिम जाँच के लिए \`mcl-finish\` टाइप करें।`
- Portuguese: `Digite \`mcl-finish\` para verificações finais entre sessões.`
- Russian: `Введите \`mcl-finish\` для финальных межсессионных проверок.`
- Hebrew: `הקלידו \`mcl-finish\` לבדיקות סופיות בין הפעלות.`
- Indonesian: `Ketik \`mcl-finish\` untuk pemeriksaan akhir lintas sesi.`

Rules:

- The reminder is MANDATORY on every Aşama 11 report — even when
  Section 1 is omitted and Section 2 is the only visible section.
- The reminder is NOT subject to the empty-section-omission rule.
  Unlike Aşama 8 / 4.6 / Section 1 — which can vanish when
  empty — this line always renders.
- The reminder is a single line. Do NOT wrap it in a named section
  header. Do NOT add surrounding prose explaining what
  `mcl-finish` does (the developer learns by typing it).
- The token `mcl-finish` stays verbatim in all languages (it is
  a fixed technical token per the language rule).
- This reminder does NOT fire inside an `mcl-finish` run itself —
  `mcl-finish` has its own output format and is not followed by a
  Aşama 11 report.

## Legacy: Code Review and Test Results

When code review, test results, or completion reports come back
(from other tools or manual review):

1. MCL applies Gate 3 to all findings before presenting to the developer
2. For code review issues, explain:
   - What the issue is (in developer's language)
   - Why it matters (in developer's language)
   - The code snippet (keep in English — code is universal)
   - The suggested fix explanation (in developer's language)
3. For test results:
   - Passed/failed status in developer's language
   - Failure explanations in developer's language — explain what went wrong,
     not just translate the error message
   - Code references stay in English
4. After presenting results, ask: "Do you understand what this means? (yes / no)"
   If "no" → re-explain differently

## Audit Emit on Completion (since v10.1.6; dual-emit since v10.1.22)

After all three Verification Report sections are emitted (Spec
Coverage, MUST-test phrase, Process Trace) and BEFORE proceeding to
Aşama 20 (Localized Translation), emit BOTH the v11 audit name AND
the v10 alias:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log asama-19-complete mcl-stop "covered=N must_test=K trace_lines=L"'
```

Where:
- N: rows in the Spec Coverage table (one per MUST/SHOULD)
- K: items in the !!! YOU MUST TEST THESE !!! section (0 if omitted)
- L: lines rendered from trace.log

The v10 alias keeps existing v10 enforcement at mcl-stop.sh:1041+
operating during the bridge. R8 cutover removes the alias line.

Aşama 19 is a TRANSIENT phase (no persisted state field). The emit
serves trace.log completeness so the developer can prove the
verification report ran. Stop hook scans audit.log and writes
`phase_transition 11 12` to trace.log (v10 numbering; R8 retitles).

## Mock Data Cleanup (since v10.1.23 — moved from Aşama 6c → fenced in Aşama 8 → active here)

After the Spec Coverage / MUST-test / Process Trace sections are
written, AND after the v11 + v10 completion audit has been emitted,
Aşama 19 owns one final responsibility: **remove the dummy/mock data
that Aşama 6 introduced for the UI build**. This step is the
v11 architecture's natural location for the cleanup that v10 placed
inside Aşama 6c (BACKEND_INTEGRATION); R2 fenced the block inside
`asama8-tdd.md` so it would not execute during TDD; R7 (this release)
moves it here where it actually executes.

### Detection

Scan the project for mock data left over from Aşama 6:

```bash
# 1. Path-based index — files in __fixtures__/ or mocks/ directories
find . -type d -name "__fixtures__" -prune -o \
       -type d -name "mocks" -prune -o \
       -type f \( -name "*.fixture.ts" -o -name "*.fixture.tsx" \
                  -o -name "*.fixture.js" -o -name "*.fixture.jsx" \) -print

# 2. Symbol-based index — MOCK_ / mock_ prefix in source code
grep -rln "^[[:space:]]*\(const\|let\|var\)[[:space:]]\+MOCK_\|^[[:space:]]*\(const\|let\|var\)[[:space:]]\+mock_" src/

# 3. State-toggle index — components with `?state=…` URL-param hooks
#    or `<select>` dev toggles for mock-state switching
grep -rln "useSearchParams\(\).*state\|<select.*mock\|const \[mockState," src/
```

### Per-fixture handling

For each `__fixtures__/*.fixture.{ts,tsx,js,jsx}` file:

```bash
# Find importers
grep -rln "from.*['\"].*__fixtures__/<name>.fixture['\"]" src/
```

- **Zero importers** → safe to delete the fixture file.
- **Imported by test files only** (`*.test.*`, `*.spec.*`) → KEEP.
  Tests are still allowed to use fixtures.
- **Imported by component files** → STOP. The Aşama 8 backend
  wiring step (asama8-tdd.md Step 5) was supposed to swap these for
  real `fetch`/`axios` calls. Surface as a Aşama 21 Open Issue:
  "fixture `<file>` still has component importers — backend wiring
  incomplete." Do NOT delete.

### What to KEEP (never delete)

- Type definitions in `src/types/**` — production code reuses them.
- Any fixture imported by test files (Jest/Vitest/etc.).
- `__fixtures__/` directories that contain only test-imported files.

### What to DELETE

- `?state=...` URL-param hooks whose purpose was visual state toggle.
- `<select>` dev toggles that expose mock-state switching to the
  developer.
- `__fixtures__/<name>.fixture.{ts,tsx,js,jsx}` files with zero
  importers (verified by step above).
- `MOCK_<NAME>` / `mock_<name>` constants in component files that
  are not referenced anywhere else after backend wiring (rare;
  usually swapped during Aşama 8 backend wiring step).

### Audit emit

Before the cleanup runs:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log asama-19-mock-cleanup-started mcl-stop "candidates=N"'
```

After the cleanup completes:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log asama-19-mock-cleanup-end mcl-stop "deleted=D kept=K orphan_components=O"'
```

Where:
- D: count of files actually deleted
- K: count of fixtures kept (test-imported or has type-only role)
- O: count of fixtures still imported by component files
  (surfaced as Aşama 21 Open Issues)

Skip case (no UI flow, no fixtures present, or no `__fixtures__/`
directory exists):

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log asama-19-mock-cleanup-skipped mcl-stop "reason=<no-ui-flow|no-fixtures-found>"'
```

The cleanup is **advisory** in v10.1.23 — `mcl-pre-tool.sh` does NOT
gate any tool on these audits. The audit trail lets Aşama 21 surface
gaps but does not block tool execution. R8 cutover may upgrade to
hard enforcement once the cleanup logic has been validated in
production sessions.

</mcl_phase>
