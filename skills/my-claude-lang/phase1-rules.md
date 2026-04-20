<mcl_phase name="phase1-rules">

# Phase 1: Gather Parameters — Detailed Rules

## Pre-Flow: LSP Plugin Check (first developer message only)

Before Step 1 below, on the **first** developer message of a conversation:

1. Run `bash ~/.claude/hooks/lib/mcl-stack-detect.sh detect "$(pwd)"`.
   Empty stdout → no recognizable stack → skip the rest of this
   pre-flow and proceed to Main Flow Step 1.
2. For each detected tag, check whether the matching plugin name is
   present as a key under `.plugins` in
   `~/.claude/plugins/installed_plugins.json`. If present → silent
   no-op for that tag.
3. For each detected-but-missing plugin, surface a one-sentence
   suggestion in the developer's language with the install command
   (`/plugin install <name>@claude-plugins-official`). If the language
   server binary is likely also missing, mention it with the OS-appropriate
   install hint. See `my-claude-lang/plugin-suggestions.md` for the full
   stack→plugin→binary table.
4. The developer may accept, decline, or ignore. Either way, proceed to
   Main Flow Step 1 immediately — the suggestion does not gate Phase 1.
   If the developer declines, do not re-ask in this conversation.

Skip this pre-flow entirely when:
- Not the first developer message in the conversation.
- Mid-phase execution (Phase 4 / 4.5 / 4.6 / 5) is in progress.
- Every detected tag already has its plugin installed.

## Main Flow

When the developer describes what they want:

1. Read their full message in their language
2. Extract parameters: intent, constraints, success_criteria, technical_context
3. If ANY parameter is missing or unclear → start asking questions immediately
   using the Question Flow Rule. Do NOT present a summary first.
   Just ask the first question directly and naturally.
4. Once ALL parameters are clear and complete → present ONE summary
   AND ask "Is this correct? (yes / no)".
   Do NOT present intermediate summaries during question gathering.
   Do NOT summarize twice. There is exactly ONE summary — when all
   parameters are ready. No partial summaries, no "here's what I
   have so far" — just questions until done, then one final summary:

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

**⛔ STOP RULE:** After presenting this summary, your response ENDS.
Do NOT read files. Do NOT explore code. Do NOT start writing the spec.
Do NOT say "I'll prepare the spec now." STOP and wait for the developer
to say "yes" or "no." The summary + "Is this correct?" is the ENTIRE response.

5. If the developer says "no" → ask "What did I get wrong?", re-summarize
6. Only after developer explicitly confirms with "yes" → call Phase 2

## Question Flow Rule

**⛔ STOP RULE:** When you ask a question, your ENTIRE response is ONLY that
question. STOP THERE. Do not continue writing. Do not call tools. Do not
explore files. Do not read code. Your response ENDS at the question mark.
Wait for the developer's reply in the next message.

Always ask uncertain questions ONE AT A TIME.
- Ask one question directly and naturally — the question IS your entire response
- No introductory sentences ("I need to clarify...", "A few things...", "Let me understand...")
- No framing, no context-setting before the question — just ask it
- **Language-agnostic**: never open with a greeting, apology, honorific, or courtesy softener in any language. The first word of your response is the first word of the question itself.
- Wait for the answer — this means your response ENDS after the question
- Confirm your understanding of that specific answer with the developer
- Translate the confirmed answer to English for Claude Code
- Get Claude Code's confirmation on that specific point
- Only after all three parties agree on that answer → move to the next question
- Repeat until all parameters are complete
- Only THEN present the full summary for final confirmation
- If multiple ambiguous terms are detected, resolve them one at a time
  in order. When asking about the first one, mention that you noticed
  others too: "I also need to clarify [term2] after this."

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

## Nested Conditional Requirements

If the developer describes a requirement with multiple conditions,
branches, or exceptions in a single sentence:

Examples:
- German: "Wenn...und...soll...wobei...es sei denn..." (if...and...should...
  where...unless...)
- Any language: "If X and Y, then do Z, but if W, then do V instead"

MCL response pattern:
- Break each condition into a separate line item
- Present the conditions back as a numbered list:
  "I see these conditions: 1) If user is logged in AND has permission →
  export data. 2) Format should be configurable. 3) UNLESS sensitive data
  → restrict export. Is this correct?"
- Confirm each branch before writing the spec
- Do NOT try to handle nested conditionals as a single requirement

## Hidden Sub-Tasks

If a developer's request looks like a single task but actually contains
multiple implicit sub-components:

Examples:
- "ユーザー管理画面を作って" (make a user management screen) = login +
  CRUD + roles + permissions + search + UI
- "Pura backend fix karo" (fix the entire backend) = multiple bugs +
  deps + deploy
- "Build a dashboard" = data source + charts + filters + export + permissions

MCL response pattern:
- Identify the likely sub-components
- Ask: "This contains several parts. I see: [list sub-components].
  Should I handle all of these, or is there a specific subset you want?"
- Run Phase 1-3 for the confirmed sub-components
- If the developer says "all of them" → prioritize order together

## Multi-Rule Collision

When multiple MCL rules trigger simultaneously on a single message
(e.g., emotional frustration + authority reference + vague scope):

MCL priority order:
1. **Acknowledge emotion first** — if the developer is frustrated,
   a brief acknowledgment before anything else
2. **Gather the most critical missing parameter** — usually WHAT
   (intent) before WHO said it or WHEN it's due
3. **Then resolve secondary patterns** — urgency, authority, ambiguity
4. **One question at a time still applies** — never stack multiple
   pattern resolutions into one message

Example: "Boss ne bola hai ye feature urgent hai" (authority + urgency
+ no spec) → MCL: "I understand this is urgent. What specifically
should I build?" — addresses urgency, asks for intent, one question.

## Multi-Task Rule

If the developer requests multiple distinct tasks in one message:

- Identify each separate task
- Inform the developer: "I see [N] separate tasks. I'll handle each one
  individually to make sure nothing gets lost."
- Run Phase 1-3 separately for each task
- Execute tasks in the agreed order

</mcl_phase>
