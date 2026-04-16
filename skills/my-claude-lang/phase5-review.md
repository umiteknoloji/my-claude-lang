# Phase 5: Verification Report

Phase 5 is NOT just a review translation. It is a comprehensive verification
that gives the developer confidence that the AI did the right thing.

## When Phase 5 Runs

After Phase 4 completes (all code is written), MCL MUST produce a
Verification Report with four mandatory sections:

## Section 1: Spec Compliance Check

Go through EVERY requirement in the Phase 2 spec and verify:

```
📋 Spec Uyum Kontrolü:
✅ MUST: [requirement] → Karşılandı: [how]
✅ MUST: [requirement] → Karşılandı: [how]
❌ MUST: [requirement] → EKSİK: [what's missing]
✅ SHOULD: [requirement] → Karşılandı
⚠️ SHOULD: [requirement] → Kısmen: [what's partial]
```

Every MUST item must be checked. If any MUST is not met, flag it
immediately — do not hide it.

## Section 2: Missed Risks

Things the developer didn't think of and MCL didn't catch in Phase 1-2
but that became apparent during implementation:

```
⚠️ Kaçırılmış Riskler:
- [Risk 1]: [explanation of what could go wrong]
- [Risk 2]: [explanation]
- Yoksa: "Ek risk tespit edilmedi."
```

Examples of missed risks:
- Security: input validation missing, auth bypass possible
- Performance: N+1 queries, large DOM renders
- Data: race conditions, stale cache, missing error handling
- UX: edge case where UI breaks, accessibility issues

If no risks found, explicitly say so — do not skip the section.

## Section 3: Impact Analysis

What other parts of the project MIGHT be affected by this change:

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

## Section 4: Test Checklist

Specific, actionable test steps the developer should perform:

```
🧪 Test Kontrol Listesi:
- [ ] [Step 1: specific action → expected result]
- [ ] [Step 2: specific action → expected result]
- [ ] [Edge case test]
- [ ] [Regression test for affected areas from Section 3]
```

Tests must be:
- Specific (not "test the feature" but "click X button, expect Y")
- Cover the golden path (happy case)
- Cover edge cases from the spec
- Cover regression for impacted areas from Section 3

## Section 5: Permission Summary

List EACH harness permission the developer answered during execution
INDIVIDUALLY — not grouped, not a generic sentence:

```
🔐 İzin Özeti:
- [file.ts] oluşturma → Neden: [reason] → Seçimin: [choice] → 
  Alternatif: [what other option would have done]
- [file.css] düzenleme → Neden: [reason] → Seçimin: [choice] → 
  Alternatif: [what other option would have done]
⚠️ Öneri: [if any choice was suboptimal, explain why]
```

## Presentation Rules

- ALL sections are in the developer's language
- Code snippets and file names stay in English
- Do NOT skip any section — even if empty, say "nothing found"
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
