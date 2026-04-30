<mcl_phase name="phase5-review">

# Phase 5: Verification Report

Phase 5 is NOT just a review translation. It is a comprehensive verification
that gives the developer confidence that the AI did the right thing.

## When Phase 5 Runs

After **Phase 4.6 (Post-Risk Impact Review)** is fully resolved — i.e.
every impact MCL surfaced has been answered by the developer (skip /
apply fix / make general rule), and Phase 4.5 before it is also
resolved — MCL MUST produce the Verification Report. This is NOT
optional. Phase 4.6 is NOT the last step.

If you wrote code and stopped without running Phase 4.5, Phase 4.6
AND emitting this report, you skipped phases — go back and produce
all of them.

⛔ STOP RULE: Phase 4 does NOT end with "done" or a summary of changes.
Phase 4 hands off to Phase 4.5; Phase 4.5 hands off to Phase 4.6;
Phase 4.6 hands off to Phase 5. Phase 5 is the last step. If you find
yourself writing "all steps completed" without any of the sections
below, you are violating this rule.

<mcl_constraint name="test-runner-orchestration">

## Test Runner Orchestration (opt-in)

When the developer has opted in by declaring a non-empty `test_command`
in `$(pwd)/.mcl/config.json`, MCL MUST invoke the test runner during
Phase 5 **before** emitting Section 1 of the Verification Report.

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

When `tdd=true` (see `phase4-tdd.md`) AND Phase 4 **or Phase 4.5**
has already emitted a `🟢 GREEN verify` block in this session, DO NOT
invoke the runner again here. Phase 5 starts instead with a localized
TDD-cycle summary line. Examples:

- Phase 4 GREEN only (no Phase 4.5 re-verify):
  - Turkish: `✅ TDD döngüsü: RED taban → GREEN doğrulama tamamlandı`
  - English: `✅ TDD cycle: RED baseline → GREEN verify complete`
- Phase 4 GREEN + Phase 4.5 re-verify GREEN:
  - Turkish: `✅ TDD döngüsü: RED taban → GREEN doğrulama → Phase 4.5 re-doğrulama tamamlandı`
  - English: `✅ TDD cycle: RED baseline → GREEN verify → Phase 4.5 re-verify complete`

Then proceed to Section 1. A double (or triple) runner invocation
would be noise — the earlier GREEN blocks already carry the diagnostic
information. This skip applies ONLY when a GREEN verify has happened;
if TDD mode was enabled but fell through due to missing `test_command`,
the normal Phase 5 runner invocation above still applies.

The TDD-cycle summary line is MANDATORY whenever a GREEN verify
happened in Phase 4 or Phase 4.5 — even when Phase 4.5 and Phase 4.6
both emitted nothing (their "omit entirely" rule does not extend to
this line). The summary is the single most compact proof to the
developer that the runner blocks were the ground truth Phase 5 is
standing on; without it, Phase 5 opens with nothing tying back to
the TDD cycle.

</mcl_constraint>

The report has **up to three** sections, in this order: Spec Compliance,
must-test, Process Trace. Any section whose content is empty is **omitted
entirely** (no header, no placeholder sentence, no filler). Section 1 in
particular is omitted when every MUST/SHOULD is satisfied — the
absence of the section IS the all-clear signal.
(Prior to MCL 5.4.0 the report had a third section, Impact Analysis,
which was extracted into its own Phase 4.6 interactive dialog;
prior to MCL 5.3.0 the report had 4 sections with Missed Risks
embedded; prior to MCL 5.2.0 it had 5 with a Permission Summary.
All are removed.)

## Section 1: Spec Compliance — Mismatches Only

Walk every MUST and SHOULD requirement from the Phase 2 spec, but
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
sandboxed Claude cannot. This list must reflect both Phase 4.5 and
Phase 4.6 decisions (tests for applied fixes; acceptance smoke for
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
- [ ] [Edge case test from Phase 2 spec]
- [ ] [Regression test for consumers surfaced in Phase 4.6]
- [ ] [Smoke test for any risk the developer skipped in Phase 4.5]
```

Tests must be:
- Specific (not "test the feature" but "click X button, expect Y")
- Cover the golden path (happy case)
- Cover edge cases from the spec
- Cover regression for consumers surfaced in Phase 4.6
- Cover residual exposure from Phase 4.5 skipped risks

## Section 3: Process Trace (MCL 6.3.0+)

A one-line-per-step localized rendering of `.mcl/trace.log` so the
developer can verify that MCL actually ran every phase, dispatched
the plugins it claimed to, and advanced state on approval — not just
claimed it in prose. The trace is written by the hooks (deterministic,
not model-compliance-dependent); Phase 5 reads and renders it.

How:

1. Read `.mcl/trace.log` via the Read tool. If the file does not
   exist or is empty, OMIT Section 3 entirely — no header, no
   placeholder. (The file is created by `hooks/lib/mcl-trace.sh` on
   the first event of a session; its absence means no MCL-driven
   events fired, which is itself diagnostic but not a Phase 5
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

## Hook-first audit emission (since 9.1.0)

`mcl-stop.sh` auto-emits the `phase5-verify` audit when the last
assistant text contains a Verification Report header in any of the 14
supported MCL locales (`Verification Report` / `Doğrulama Raporu` / 12
others) AND `current_phase >= 4`. The Bash below remains valid and
preferred (caller=skill-prose audit provenance, synchronous-write) but
is no longer required for Phase 6 audit-trail completeness.

## Phase 5 → 5.5 Audit Emission (since 8.15.0)

After all three Verification Report sections are emitted (Spec
Compliance, MUST TEST THESE, Process Trace) and BEFORE handing off to
Phase 5.5 localized translation, emit the verify audit:

```bash
bash -c '
for lib in "$MCL_HOME/lib/hooks/lib/mcl-state.sh" \
           "$HOME/.mcl/lib/hooks/lib/mcl-state.sh" \
           "$HOME/.claude/hooks/lib/mcl-state.sh"; do
  [ -f "$lib" ] && source "$lib" && break
done
mcl_audit_log "phase5-verify" "phase5" "report-emitted" >/dev/null 2>&1
'
```

This audit event is the **deterministic signal** for Phase 6 (a)
audit-trail completeness check. Without it, Phase 6 falls back to
transcript header string match — heuristic, lokalize 14 dile bağımlı,
gerçek emit garantisi vermez. Explicit `mcl_audit_log "phase5-verify"`
çağrısı Phase 6'ya report'un yazıldığını net olarak söyler.

Skip this only when Phase 5 itself was skipped (no spec, no Phase 4
code) — in which case Phase 6 (a) flags `phase-review-impact` and
`spec-approve` absence first; `phase5-verify` absence becomes
secondary signal.

## Presentation Rules

- ALL sections are in the developer's language
- Code snippets and file names stay in English
- Do NOT include a Missed Risks section — Phase 4.5 handled that
- Do NOT include an Impact Analysis section — Phase 4.6 handled that
- Do NOT include a Permission Summary section — removed in MCL 5.2.0
- Do NOT list ✅-compliant items in Section 1 — mismatches only
- After the full report, ask: "Do you understand everything? (yes / no)"
  If "no" → re-explain the unclear part
- The report is part of MCL's response — it is NOT optional

## Tail Reminder — `mcl-finish` (MCL 5.14.0+)

Every Phase 5 Verification Report MUST end with a single localized
reminder line pointing at the `mcl-finish` slash-command. The line
sits AFTER Section 2 (the must-test checklist) as the final
user-facing line of the report. Its purpose is to keep the
session-local developer aware that Phase 4.6 impacts are
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

- The reminder is MANDATORY on every Phase 5 report — even when
  Section 1 is omitted and Section 2 is the only visible section.
- The reminder is NOT subject to the empty-section-omission rule.
  Unlike Phase 4.5 / 4.6 / Section 1 — which can vanish when
  empty — this line always renders.
- The reminder is a single line. Do NOT wrap it in a named section
  header. Do NOT add surrounding prose explaining what
  `mcl-finish` does (the developer learns by typing it).
- The token `mcl-finish` stays verbatim in all languages (it is
  a fixed technical token per the language rule).
- This reminder does NOT fire inside an `mcl-finish` run itself —
  `mcl-finish` has its own output format and is not followed by a
  Phase 5 report.

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

</mcl_phase>
