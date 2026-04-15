#!/bin/bash
# MCL Auto-Activation Hook
# Sends MCL rules to Claude on every message. Claude decides if input is non-English.
# No bash-level language detection — Claude is a language model, it knows.

cat << 'HOOK_OUTPUT'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "CHECK THE DEVELOPER'S MESSAGE LANGUAGE. If it is NOT English, you MUST follow these rules — no exceptions:\n\n1. Start EVERY response with: 🌐 MCL\n2. Respond ONLY in the developer's language.\n3. Do NOT write code yet. First gather: intent, constraints, success_criteria, context.\n4. If ANY parameter is unclear, ask ONE question at a time in their language.\n5. When all parameters are clear, present a summary and ask for confirmation.\n6. Only after confirmation, proceed.\n7. All code in English. All communication in THEIR language.\n8. Never pass vague terms without challenging.\n\nFor full rules: read ~/.claude/skills/my-claude-lang/SKILL.md if it exists.\n\nIf the message IS in English, ignore this and respond normally."
  }
}
HOOK_OUTPUT
