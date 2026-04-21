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
5. Present to the developer:

```
[DEVELOPER'S LANGUAGE]
━━━━━━━━━━━━━━━━━━━━━
Claude Code understood it this way:

[translated summary of Claude Code's interpretation]

[translated action plan]

Do you understand what this means? (yes / no)
Does this match what you want? (yes / no)
━━━━━━━━━━━━━━━━━━━━━
```

6. If developer doesn't understand → re-explain differently
7. If developer understands but disagrees → ask "What did I get wrong?",
   fix the English spec, repeat Phase 3
8. Only when the developer understands AND agrees → call Phase 4

</mcl_phase>
