# Phase 1: Gather Parameters — Detailed Rules

## Main Flow

When the developer describes what they want:

1. Read their full message in their language
2. Extract parameters: intent, constraints, success_criteria, technical_context
3. If ANY parameter is missing or unclear → start asking questions immediately
   using the Question Flow Rule. Do NOT present a summary first.
   Just ask the first question directly and naturally.
4. Once ALL parameters are clear and complete → present the full summary:

```
[DEVELOPER'S LANGUAGE]
━━━━━━━━━━━━━━━━━━━━━
I understood the following:

**What you want:**
[summary of the goal]

**Constraints:**
[any limitations, tech stack, requirements mentioned]

**Success looks like:**
[what "done" means]

Is this correct? (yes / no)
━━━━━━━━━━━━━━━━━━━━━
```

5. If the developer says "no" → ask "What did I get wrong?", re-summarize
6. Only after developer confirms → call Phase 2

## Question Flow Rule

Always ask uncertain questions ONE AT A TIME.
- Ask one question directly and naturally — no preamble, no summary first
- Wait for the answer
- Confirm your understanding of that specific answer with the developer
- Translate the confirmed answer to English for Claude Code
- Get Claude Code's confirmation on that specific point
- Only after all three parties agree on that answer → move to the next question
- Repeat until all parameters are complete
- Only THEN present the full summary for final confirmation

## "Yes but..." Rule

If the developer's confirmation contains additional scope or modifications
(e.g., "yes but also add...", "yes but change..."):

- This is NOT a "yes" — it is a parameter change
- Check if the new request contradicts any existing confirmed parameter
  - If contradiction → flag it: "This conflicts with [existing parameter].
    Which one should I keep?"
  - If no contradiction → accept the new parameter, add it to the existing ones
- Run Phase 1-3 ONLY for the new addition — do NOT re-confirm already
  confirmed parameters. They are done.
- Previous work stays. New work gets added on top.

## Contradiction Detection

Before advancing from Phase 1 to Phase 2, check all parameters for
logical contradictions. Examples:

- "offline AND always show real-time data" → contradictory
- "no database BUT persist user data" → contradictory
- "simple AND enterprise-grade with full audit logging" → potentially contradictory

If contradictions are found:
- Explain the contradiction in the developer's language
- Ask: "Which one takes priority?"
- Resolve before advancing

## Multi-Task Rule

If the developer requests multiple distinct tasks in one message:

- Identify each separate task
- Inform the developer: "I see [N] separate tasks. I'll handle each one
  individually to make sure nothing gets lost."
- Run Phase 1-3 separately for each task
- Execute tasks in the agreed order
