<mcl_phase name="phase3-verify">

# Phase 3: Claude Code Understanding Verification

**`superpowers` (tier-A, ambient):** active throughout this phase — no explicit dispatch point; its methodology layer applies as a behavioral prior.

Called automatically when spec is generated.

1. Claude Code must summarize its understanding in English
2. Format: "I understand the task as: [summary]. I will: [action plan]. Is this correct?"
3. MCL applies Gate 2: check Claude Code's summary for vague terms or
   implicit assumptions. Challenge if found. Only proceed when Claude Code's
   understanding is precise.
4. MCL applies Gate 3: translate Claude Code's verified summary to the
   developer's language. Explain technical concepts, don't just translate words.
5. Present the translated summary and action plan as plain text:

```
[DEVELOPER'S LANGUAGE]
━━━━━━━━━━━━━━━━━━━━━
Claude Code understood it this way:

[translated summary of Claude Code's interpretation]

[translated action plan]
━━━━━━━━━━━━━━━━━━━━━
```

6. Then call (since 6.0.0):
```
AskUserQuestion({
  question: "MCL {version} | <localized 'Approve this spec?' — e.g.
    Turkish: Bu spec'i onaylıyor musun?; English: Approve this spec?>",
  options: [
    { label: "<approve-verb-only>", description: "<free-form context>" },
    { label: "<edit-verb>",         description: "<free-form context>" },
    { label: "<cancel-verb>",       description: "<free-form context>" }
  ]
})
```

   **Label Discipline (since 6.4.1 — MANDATORY).** The approve option's
   `label` is the BARE VERB in the developer's detected language — NO
   descriptive suffix. Use the canonical 14-language set from
   [askuserquestion-protocol.md:32](my-claude-lang/askuserquestion-protocol.md):

   | Locale | Approve label |
   | ------ | ------------- |
   | TR     | Onayla        |
   | EN     | Approve       |
   | ES     | Aprobar       |
   | FR     | Approuver     |
   | DE     | Genehmigen    |
   | JA     | 承認           |
   | KO     | 승인           |
   | ZH     | 批准           |
   | AR     | موافق          |
   | HE     | אשר           |
   | HI     | स्वीकार        |
   | ID     | Setujui       |
   | PT     | Aprovar       |
   | RU     | Одобрить      |

   FORBIDDEN approve labels (examples of drift): `Onayla, kodu yaz`,
   `Approve and proceed`, `Approve, write code`, `Aprobar y continuar`,
   `承認して実装へ`, `승인하고 코드 작성`, `Genehmigen und codieren`.
   Any descriptive context belongs in the option's `description` field,
   NOT in `label`.

   The `edit` and `cancel` labels stay free-form localized verbs
   (`Düzenle` / `İptal` / `Edit` / `Cancel` / etc.) — this rule
   restricts the approve label only.

   Do NOT emit the legacy `✅ MCL APPROVED` marker — dead in 6.0.0.

7. If developer picks a non-approve option → ask "What did I get
   wrong?", fix the English spec, repeat Phase 3.
8. Only when the tool_result returns an approve-family option → Stop
   hook flips state to Phase 4 (`approve-via-askuserquestion` audit).

</mcl_phase>
