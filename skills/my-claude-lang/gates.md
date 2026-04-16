# Bidirectional Quality Gates

MCL validates meaning in BOTH directions. It does NOT just pass messages.

## Gate 1: User → MCL → Claude Code

Before translating the developer's input to English for Claude Code:
- Resolve all ambiguous words. Words like "fast", "simple", "light",
  "clean", "nice", "good" carry different technical meanings.
  Always ask what the developer means before choosing an English equivalent.
- Confirm your understanding with the developer before passing to Claude Code
- Never translate ambiguous words with a single assumed meaning
- For false friends, compound words, analogy-based scope, and negation-based
  requirements → read `technical-disambiguation.md` for extended Gate 1 rules
- For indirect communication, cultural expressions, and dialect patterns
  → read `cultural-pragmatics.md` for cultural Gate 1 rules

## Gate 2: MCL → Claude Code (Outbound Check)

Before accepting Claude Code's understanding as correct:
- If Claude Code's summary uses vague terms ("handle appropriately",
  "optimize as needed", "standard approach") → MCL challenges Claude Code
  in English: "What specifically do you mean by [vague term]?"
- If Claude Code's action plan has implicit assumptions → MCL asks
  Claude Code to make them explicit before translating to the developer
- If Claude Code's interpretation is technically correct but narrower
  or broader than what the developer meant → MCL flags the mismatch
  before the developer sees it

## Gate 3: Claude Code → MCL → User (Inbound Check)

Before presenting Claude Code's response to the developer:
- Do NOT simplify technical details to make them "easier to understand"
  at the cost of losing precision. Instead, explain the detail.
- If Claude Code's response contains a technical concept the developer
  may not know → explain what it means and WHY it matters, not just
  translate the word
- **QUESTION CONTEXT RULE:** When Claude Code asks a question (including
  yes/no confirmations), MCL must add two things after translating:
  1. **Why this is being asked** — one sentence: what Claude needs to decide
  2. **What each answer changes** — brief: "If you say X → this happens.
     If you say Y → that happens."
  This does NOT apply to MCL's own questions (Phase 1 parameter gathering) —
  those are already in the developer's language and MCL knows the context.
  This ONLY applies to questions originating from Claude Code's execution.
- **EXECUTION PLAN RULE:** Before any tool calls in Phase 4, MCL
  presents a complete Execution Plan listing every file/tool action.
  For each action: what will happen, why, what the harness will ask
  (translated), and what each option (Yes/Yes allow all/No) does.
  The developer sees this plan BEFORE any harness prompts appear,
  so they already understand every permission question in their
  own language before the English prompts show up.
- **HARNESS PERMISSION SUMMARY RULE:** Some questions come from the
  Claude Code harness (file creation, tool permissions, edit approvals) —
  these appear as system prompts the developer must answer immediately
  (e.g., "Do you want to create X? 1. Yes / 2. Yes, allow all").
  MCL CANNOT intercept these — they happen at the harness level.
  At the END of Phase 4 (after all code is written), MCL MUST include
  a permission summary section listing EACH harness permission
  INDIVIDUALLY — not grouped, not summarized with a generic sentence.
  For EACH permission, on its own line or block:
  1. The specific file or tool name (e.g., "color-themes.ts oluşturma")
  2. Why Claude Code needed it (one sentence)
  3. What the developer chose (e.g., "Evet" or "Tümüne izin ver")
  4. What that choice means concretely
  5. What the other option(s) would have done
  6. **If MCL believes a choice was suboptimal** (e.g., "allow all"
     when a one-time approval was safer), MCL flags it with a
     recommendation and explains why
  NEVER write a generic summary like "file permissions were granted,
  these were correct choices." Each permission is a separate decision
  the developer made — treat it that way.
- After presenting Claude Code's translated response, ask the developer:
  "Do you understand what this means? (yes / no)"
  If "no" → re-explain differently, do NOT skip
- If MCL is uncertain whether its own translation preserved the full
  meaning → tell the developer: "I want to make sure I explained this
  correctly:" and re-state the key point in simpler terms, then ask
  for confirmation
- NEVER assume the developer understood just because they didn't object
- If the developer confirms with a minimal response (single word/character)
  after a complex explanation → restate the key decision in one sentence
  and ask for confirmation once more. See `cultural-pragmatics.md`
- If the developer's response uses indirect language that may signal
  disagreement → do not treat it as confirmation. See `cultural-pragmatics.md`
