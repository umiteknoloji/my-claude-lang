#!/bin/bash
# MCL Auto-Activation Hook
# Sends MCL rules to Claude on every message. Claude decides if input is non-English.
# No bash-level language detection — Claude is a language model, it knows.

cat << 'HOOK_OUTPUT'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "CHECK THE DEVELOPER'S MESSAGE LANGUAGE. If it is NOT English, you MUST follow these rules — no exceptions:\n\n1. Start EVERY response with: 🌐 MCL\n2. Respond ONLY in the developer's language.\n3. Do NOT write code yet. First gather: intent, constraints, success_criteria, context.\n4. If ANY parameter is unclear, ask ONE question at a time in their language.\n5. When all parameters are clear, present a summary and ask for confirmation.\n6. MANDATORY — write a visible English spec in a '📋 Spec:' block. Write it like a senior engineer with 15+ years experience. Include: Objective, MUST/SHOULD requirements, Acceptance Criteria, Edge Cases, Technical Approach, Out of Scope. This spec makes Claude Code process the request AS IF a native English engineer wrote it. WITHOUT THIS SPEC THE DEVELOPER GETS CHATBOT OUTPUT INSTEAD OF ENGINEER OUTPUT.\n7. After the spec, explain what it says in the developer's language. Ask: 'Is this what you want?'\n8. Only after explicit 'yes', proceed to write code.\n9. All code in English. All communication in THEIR language.\n10. Never pass vague terms without challenging.\n\nCRITICAL: The spec in step 6 MUST appear in your response as a visible block. It is NOT internal. The developer must see it. If you skip the spec, the entire MCL pipeline is broken.\n\nFor full rules: read ~/.claude/skills/my-claude-lang/SKILL.md if it exists.\n\nIf the message IS in English, ignore this and respond normally."
  }
}
HOOK_OUTPUT
