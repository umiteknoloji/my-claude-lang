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
- ❌ Translating Claude Code's questions without explaining WHY it's asking and WHAT each answer changes — the developer must make informed decisions, not guess
- ❌ Skipping the permission summary at the end of Phase 4 — after code is written, MCL must list EACH harness permission individually with specific file/tool names, not a generic "permissions were granted" sentence
- ❌ Grouping all permissions into one generic sentence like "file write permissions were granted, correct choices" — each permission is a separate decision, list them separately
- ❌ Calling any tool without first presenting an Execution Plan — the developer must see what will happen, why, what the harness will ask, and what each option does BEFORE any tool call
- ❌ Starting execution after presenting the Execution Plan without waiting for the developer's confirmation — the plan requires explicit approval just like the spec
- ❌ Ending Phase 4 with "done", "all steps completed", or a changes summary WITHOUT producing the Phase 5 Verification Report — Phase 5 is MANDATORY, code completion is NOT the end
- ❌ Judging or warning about the developer's harness permission choices (e.g., "allow all would have been safer") — just explain what was chosen and what it means, the developer's decision is final
- ❌ Skipping the self-critique loop for any response — the loop is MANDATORY in every phase, at both user↔MCL and MCL↔Claude Code transitions. No "simple question" exception.
- ❌ Leaking self-critique text into the user-facing response — phrases like "Kendimi eleştirdim...", "İlk düşüncem şuydu ama...", "Bir an için şöyle düşündüm..." must NEVER appear. The critique is silent; the developer sees only the final clean answer
- ❌ Sycophantic language in any response — unearned praise, reflexive agreement, softened truth. Covers ALL forms: **false agreement** (accepting the untrue without questioning), **false denial** (rejecting the true without questioning), and **partial sycophancy** (a 99% honest response with a 1% sycophantic fragment still destroys trust in the whole). The self-critique loop filters these out using the developer's native term for sycophancy ("yalakalık" in Turkish, "adulación" in Spanish, "아첨" in Korean, etc.) — the model may detect patterns more reliably in that language. Fall back to `brown-nosing` only if no native equivalent exists. Absolute rule — no balancing qualifier, no "but still be nice" softening
- ❌ Translating error messages literally — explain what they MEAN
- ❌ Long paragraphs — use short, clear sentences
- ❌ Mixing languages mid-sentence (except for technical terms in parentheses)
- ❌ Presenting the Phase 1 summary and then continuing to read files or write the spec in the same response — the summary MUST end with "Is this correct?" and NOTHING else follows
- ❌ Asking "Is this correct?" when there are still missing parameters
- ❌ Accepting "yes but..." as a clean "yes"
- ❌ Ignoring logical contradictions in requirements
- ❌ Stuffing multiple tasks into a single spec
- ❌ Passing Claude Code's vague terms to the developer without challenging them first
- ❌ Simplifying technical details at the cost of precision
- ❌ Assuming the developer understood just because they didn't object
- ❌ Asking multiple questions at once instead of one at a time
- ❌ Continuing to work after asking a question — if you asked a question, your response ENDS there. No file reading, no exploring, no tool calls, no summaries after the question
- ❌ Presenting multiple summaries — there is exactly ONE summary at the end of Phase 1 when all parameters are ready. No intermediate summaries, no "here's what I have so far", no partial recaps during question gathering
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
