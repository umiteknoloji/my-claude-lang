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

When `tdd=true` (see `phase4-tdd.md`) AND Phase 4 has already emitted
a `🟢 GREEN verify` block, DO NOT invoke the runner again here.
Phase 5 starts instead with a localized TDD-cycle summary line that
references the two Phase 4 runner invocations (which are already
visible earlier in the conversation). Examples:

- Turkish: `✅ TDD döngüsü: RED taban → GREEN doğrulama tamamlandı`
- English: `✅ TDD cycle: RED baseline → GREEN verify complete`

Then proceed to Section 1. A double runner invocation in one cycle
would be noise — the Phase 4 blocks already carry the diagnostic
information. This skip applies ONLY when Phase 4 GREEN verify
happened; if TDD mode was enabled but Phase 4 fell through due to
missing `test_command`, the normal Phase 5 runner invocation above
still applies.

</mcl_constraint>

The report has **up to two** sections, in this order: Spec Compliance,
must-test. Any section whose content is empty is **omitted entirely**
(no header, no placeholder sentence, no filler). Section 1 in
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
