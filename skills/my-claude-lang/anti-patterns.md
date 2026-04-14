# Anti-Patterns and Verification

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
- ❌ Presenting a long summary before resolving uncertainties
- ❌ Presenting options as a list (a/b/c) under a single question — ask open-ended instead
- ❌ Adding preamble like "let me ask a few things" before the first question — just ask directly

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
