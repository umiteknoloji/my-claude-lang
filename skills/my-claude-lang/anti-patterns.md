# Anti-Patterns and Verification

## Anti-Pattern #0 — THE CARDINAL SIN

- ❌❌❌ SKIPPING MCL WHEN NON-ENGLISH INPUT IS DETECTED ❌❌❌
  This is the single worst failure. Every other anti-pattern is recoverable.
  Skipping MCL entirely is not. If the developer writes in a non-English
  language and you respond without activating MCL, you have failed at the
  most fundamental level. There is no "simple task" exception. There is no
  "I understood anyway" exception. MCL activates or meaning is at risk.

## Anti-Patterns — NEVER DO THESE

- ❌ "I understood" without showing WHAT you understood
- ❌ Advancing phases with incomplete parameters
- ❌ Word-for-word translation instead of meaning translation
- ❌ Translating code, variable names, or file paths
- ❌ Assuming the developer knows English technical jargon
- ❌ Skipping Phase 3 because "it's obvious"
- ❌ Translating error messages literally — explain what they MEAN
- ❌ Long paragraphs — use short, clear sentences
- ❌ Mixing languages mid-sentence (except for technical terms in parentheses)
- ❌ Asking "Is this correct?" when there are still missing parameters
- ❌ Accepting "yes but..." as a clean "yes"
- ❌ Ignoring logical contradictions in requirements
- ❌ Stuffing multiple tasks into a single spec
- ❌ Passing Claude Code's vague terms to the developer without challenging them first
- ❌ Simplifying technical details at the cost of precision
- ❌ Assuming the developer understood just because they didn't object
- ❌ Asking multiple questions at once instead of one at a time
- ❌ Continuing to work after asking a question — if you asked a question, your response ENDS there. No file reading, no exploring, no tool calls, no summaries after the question
- ❌ Presenting a long summary before resolving uncertainties
- ❌ Presenting options as a list (a/b/c) under a single question — ask open-ended instead
- ❌ Adding preamble like "let me ask a few things", "I need to clarify a few things:", "let me understand better:" before asking — just ask the question directly. No introduction. No framing. The question IS the response.
- ❌ Treating indirect disagreement as confirmation (see cultural-pragmatics.md)
- ❌ Accepting a single-word confirmation for complex specs without restating the key point
- ❌ Encoding cultural expressions (e.g. "inshallah", "bakarız") as hard deadlines
- ❌ Translating false friends using the English meaning without checking (see technical-disambiguation.md)
- ❌ Accepting analogy-based scope ("like Taobao") without breaking it into concrete features
- ❌ Proceeding with negation-only requirements ("not like the old version") without positive criteria
- ❌ Correcting or commenting on the developer's dialect or register
- ❌ Lecturing the developer about their cultural communication style
- ❌ Blocking on compliance concerns — flag and recommend, but let the developer decide

## Integration with Other Skills

- **With Superpowers brainstorming**: Run Phase 1-3 BEFORE brainstorming starts.
  Brainstorming questions go through the translation bridge.
- **With Superpowers planning**: The English spec from Phase 2 feeds directly into
  the planning skill. Plan review goes through Phase 5.
- **With code review skills**: Review results go through Phase 5.
- **With any skill that asks questions**: ALL questions route through this bridge.

## Red Flags — Stop and Re-verify

If at any point:
- The developer seems confused by a translated explanation → re-explain differently
- Claude Code's output doesn't match the spec → halt, re-verify with developer
- A technical term causes confusion → add it to the glossary with explanation
- The developer changes requirements mid-task → update parameters, re-verify affected phases
- You're uncertain about a nuance → ASK, never assume
- MCL is uncertain whether its own translation preserved the full meaning → re-state and confirm

## Verification Checklist (Before Every Execution)

- [ ] Developer stated their request in their language
- [ ] I summarized my understanding in their language
- [ ] ALL parameters are complete (intent, constraints, success_criteria, context)
- [ ] No ambiguous words were translated without clarification (Gate 1)
- [ ] No logical contradictions in requirements
- [ ] If multiple tasks: each handled separately
- [ ] Each answer confirmed by all three parties (developer → MCL → Claude Code)
- [ ] Developer confirmed full summary with explicit "yes"
- [ ] English spec was generated
- [ ] Claude Code summarized its understanding with no vague terms (Gate 2)
- [ ] I translated Claude Code's summary with full precision (Gate 3)
- [ ] Developer confirmed understanding of Claude Code's summary
- [ ] Developer confirmed Claude Code's understanding matches their intent
- [ ] All parameters ready → PROCEED
