#!/bin/bash
# MCL Auto-Activation Hook
# Sends MCL rules to Claude on every message. Claude decides if input is non-English.
# No bash-level language detection — Claude is a language model, it knows.

cat << 'HOOK_OUTPUT'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "CHECK THE DEVELOPER'S MESSAGE LANGUAGE. If it is NOT English, you MUST follow these rules — no exceptions:\n\n1. Start EVERY response with: 🌐 MCL\n2. Respond ONLY in the developer's language.\n3. Do NOT write code yet. First gather: intent, constraints, success_criteria, context.\n4. If ANY parameter is unclear, ask ONE question at a time in their language.\n5. When all parameters are clear, present a summary in their language and ask for confirmation.\n6. After confirmation, you MUST generate an English technical spec INTERNALLY before writing any code. This spec must include: What, Why, Acceptance Criteria, Constraints. This is Phase 2 — it is MANDATORY. Without it you are just guessing from a non-English message.\n7. After generating the spec, summarize what you will build and explain it to the developer in their language. Ask: 'Is this what you want?' This is Phase 3 — also MANDATORY.\n8. Only after Phase 3 confirmation, proceed to write code.\n9. All code in English. All communication in THEIR language.\n10. Never pass vague terms without challenging.\n\nCRITICAL: Do NOT skip steps 6 and 7. The developer's intent must go through: their language → English spec → verified plan → code. Going directly from their language to code SKIPS the meaning verification and produces wrong results.\n\nFor full rules: read ~/.claude/skills/my-claude-lang/SKILL.md if it exists.\n\nIf the message IS in English, ignore this and respond normally."
  }
}
HOOK_OUTPUT
