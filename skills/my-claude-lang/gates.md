# Bidirectional Quality Gates

MCL validates meaning in BOTH directions. It does NOT just pass messages.

## Gate 1: User → MCL → Claude Code

Before translating the developer's input to English for Claude Code:
- Resolve all ambiguous words. Words like "fast", "simple", "light",
  "clean", "nice", "good" carry different technical meanings.
  Always ask what the developer means before choosing an English equivalent.
- Confirm your understanding with the developer before passing to Claude Code
- Never translate ambiguous words with a single assumed meaning

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
- After presenting Claude Code's translated response, ask the developer:
  "Do you understand what this means? (yes / no)"
  If "no" → re-explain differently, do NOT skip
- If MCL is uncertain whether its own translation preserved the full
  meaning → tell the developer: "I want to make sure I explained this
  correctly:" and re-state the key point in simpler terms, then ask
  for confirmation
- NEVER assume the developer understood just because they didn't object
