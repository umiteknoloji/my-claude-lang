# Phase 5: Verification Report

Phase 5 is NOT just a review translation. It is a comprehensive verification
that gives the developer confidence that the AI did the right thing.

## When Phase 5 Runs

After **Phase 4.5 (Post-Code Risk Review)** is fully resolved — i.e. every
risk MCL surfaced has been answered by the developer (skip / apply fix /
make general rule) — MCL MUST produce the Verification Report. This is
NOT optional. Phase 4.5 is NOT the last step.

If you wrote code and stopped without running Phase 4.5 AND emitting
this report, you skipped two phases — go back and produce both.

⛔ STOP RULE: Phase 4 does NOT end with "done" or a summary of changes.
Phase 4 hands off to Phase 4.5; Phase 4.5 hands off to Phase 5. Phase 5
is the last step. If you find yourself writing "all steps completed"
without the 3 sections below, you are violating this rule.

The report has **exactly three** mandatory sections — no more, no less.
(Prior to MCL 5.3.0 the report had 4 sections with Missed Risks embedded;
prior to MCL 5.2.0 it had 5 with a Permission Summary. Both are removed.)

## Section 1: Spec Compliance — Mismatches Only

Walk every MUST and SHOULD requirement from the Phase 2 spec, but
**only report items that did NOT fully comply**. Use ⚠️ for partial
compliance and ❌ for missing/failed items.

```
📋 Spec Uyumluluğu:
❌ MUST: [requirement] → EKSİK: [what's missing]
⚠️ SHOULD: [requirement] → Kısmen: [what's partial, what's not]
```

If EVERY MUST and SHOULD requirement is fully satisfied, emit exactly
one sentence in the developer's language and nothing more:

- Turkish: `Tüm MUST/SHOULD maddeleri karşılandı.`
- English: `All MUST/SHOULD items comply.`
- Spanish: `Todos los elementos MUST/SHOULD cumplen.`
- Japanese: `すべての MUST/SHOULD 項目が満たされています。`
- Korean: `모든 MUST/SHOULD 항목이 충족되었습니다.`
- Arabic: `جميع عناصر MUST/SHOULD مستوفاة.`
- Hindi: `सभी MUST/SHOULD आइटम अनुपालन करते हैं।`
- Portuguese: `Todos os itens MUST/SHOULD estão em conformidade.`
- French: `Tous les éléments MUST/SHOULD sont conformes.`
- German: `Alle MUST/SHOULD-Punkte sind erfüllt.`
- Chinese: `所有 MUST/SHOULD 项均符合要求。`
- Russian: `Все пункты MUST/SHOULD соблюдены.`
- Hebrew: `כל פריטי MUST/SHOULD עומדים בדרישות.`
- Indonesian: `Semua item MUST/SHOULD terpenuhi.`

Do NOT list satisfied items. Do NOT emit a table of ✅ lines. The
developer reads the spec; they do not need every green check restated.

## Section 2: Impact Analysis

What other parts of the project MIGHT be affected by this change,
**reflecting the developer's Phase 4.5 decisions**. If the developer
applied a fix for a risk in Phase 4.5, the impact picture may shrink;
if they skipped a risk, the impact may include known-accepted exposure.

```
🔍 Etki Analizi:
- [file/feature 1]: [why it might be affected]
- [file/feature 2]: [why it might be affected]
- Yoksa: "Bu değişiklik izole, başka yerleri etkilemiyor."
```

Check for:
- Files that import the modified files
- Shared components/utilities that were changed
- API contracts that may have shifted
- Database schema changes that affect other queries
- CSS/style changes that may cascade to other pages
- Consequences of accepted/skipped risks from Phase 4.5

## Section 3: `!!! <LOCALIZED-MUST-TEST-PHRASE> !!!`

Items the developer MUST verify in a running environment — because the
sandboxed Claude cannot. This list must reflect Phase 4.5 decisions
(tests for applied fixes; acceptance smoke for skipped risks).

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
- [ ] [Regression test for affected areas from Section 2]
- [ ] [Smoke test for any risk the developer skipped in Phase 4.5]
```

Tests must be:
- Specific (not "test the feature" but "click X button, expect Y")
- Cover the golden path (happy case)
- Cover edge cases from the spec
- Cover regression for impacted areas from Section 2
- Cover residual exposure from Phase 4.5 skipped risks

## Presentation Rules

- ALL sections are in the developer's language
- Code snippets and file names stay in English
- Do NOT include a Missed Risks section — Phase 4.5 handled that
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
