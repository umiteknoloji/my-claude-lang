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
  question: "MCL 6.0.0 | <localized 'Approve this spec?' — e.g.
    Turkish: Bu spec'i onaylıyor musun?; English: Approve this spec?>",
  options: ["<approve-family-in-language>", "<edit>", "<cancel>"]
})
```
   Do NOT emit the legacy `✅ MCL APPROVED` marker — dead in 6.0.0.

7. If developer picks a non-approve option → ask "What did I get
   wrong?", fix the English spec, repeat Phase 3.
8. Only when the tool_result returns an approve-family option → Stop
   hook flips state to Phase 4 (`approve-via-askuserquestion` audit).

</mcl_phase>
