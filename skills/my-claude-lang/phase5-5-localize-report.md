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
   canonical approve/edit/cancel table in `phase2-design-review.md`
   (UI projects' design askq) and `askuserquestion-protocol.md`
   (general askq vocabulary). For test verdicts (PASS/FAIL/SKIP), use
   the developer's natural equivalents — not literal letter-for-letter
   translations.
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

## Localized Verification Report Headers (since 8.15.0)

When emitting the Phase 5.5 localized translation, the section header
MUST be one of these exact strings — Phase 6 trigger transcript
fallback regex (`mcl-stop.sh:~1769`) depends on a literal match. Other
phrasings risk Phase 6 missing the trigger and skipping the
double-check.

| Lang | Localized header (use verbatim) |
|---|---|
| EN | `Verification Report` |
| TR | `Doğrulama Raporu` |
| FR | `Rapport de Vérification` |
| DE | `Verifizierungsbericht` |
| ES | `Informe de Verificación` |
| JA | `検証レポート` |
| KO | `검증 보고서` |
| ZH | `验证报告` |
| AR | `تقرير التحقق` |
| HE | `דוח אימות` |
| HI | `सत्यापन रिपोर्ट` |
| ID | `Laporan Verifikasi` |
| PT | `Relatório de Verificação` |
| RU | `Отчёт о проверке` |

Pick the row matching the developer's detected language. If the language
is not in this 14-set, fall back to English (`Verification Report`) — the
audit `phase5-verify` event (Phase 5 skill prose, since 8.15.0) is the
deterministic Phase 6 signal and does not depend on the header.

</mcl_phase>
