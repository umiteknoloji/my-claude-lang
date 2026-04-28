<mcl_phase name="phase5-5-localize-report">

# Phase 5.5: Localize Report

Called automatically after Phase 5 (Verification Report) is produced.

## Purpose

Phase 5 generates the Verification Report in English (spec compliance,
impact analysis, test results). Phase 5.5 localizes the report — every
section header, verdict word, and prose line is rendered in the developer's
detected language before it reaches the developer.

This is NOT retranslation after the fact. Phase 5.5 is the final rendering
gate: the English report is the internal artifact, the localized output
is what the developer sees.

## When Phase 5.5 Runs

Immediately after Phase 5 content is generated, before the response
is emitted to the developer.

Skipped when: the developer's detected language is English. In that case
Phase 5 output is shown as-is.

## What Gets Localized

ALL developer-facing text:
- Section headers: "Spec Compliance" → "Spec Uyumluluğu" (TR), etc.
- Verdict words: "PASS" → "GEÇTİ", "FAIL" → "KALDI", "SKIP" → "ATILDI"
- Phase labels: "Phase 5 — Verification Report" → "Faz 5 — Doğrulama Raporu"
- Prose explanations and bullet points

NOT localized (stays English):
- File paths, function names, code identifiers
- CLI commands, commit SHAs
- MUST / SHOULD / MAY technical tokens
- Content inside code blocks

## Rules

1. Localize section structure, not spec body. The `📋 Spec:` block content
   (engineering requirements) stays in English — it was authored in English
   and is referenced by hooks. Only the surrounding prose is localized.
2. Verdict words use the developer's language equivalents from the
   canonical approve/edit/cancel table in `phase3-verify.md` where
   applicable. For test verdicts (PASS/FAIL/SKIP), use the developer's
   natural equivalents — not literal letter-for-letter translations.
3. Do NOT translate error messages from tool output, stack traces,
   or test runner output — these are technical artifacts, not MCL prose.
4. Preserve all formatting (bold, bullet, numbered list, code fence).

## Audit

Every Phase 5.5 execution emits an audit entry:
```
localize-report | phase5-5 | lang=<detected> skipped=<true|false>
```

`skipped=true` when source language is English. `skipped=false` otherwise.
This is the detection control: the audit confirms Phase 5.5 was evaluated
even when it is a no-op.

</mcl_phase>
