# Phase 4: Execution with Live Translation

Called automatically when Phase 3 is confirmed.

1. All code, comments, variable names, commit messages → English
2. All communication with the developer → their language
3. When Claude Code asks a question:
   - MCL applies Gate 2: verify the question is precise before translating
   - Translate the question to the developer's language
   - Add context: WHY Claude is asking this + WHAT each answer changes
     (see Gate 3 Question Context Rule)
   - Get the answer
   - MCL applies Gate 1: resolve any ambiguity in the answer
   - Translate the confirmed answer to English for Claude Code
   - Confirm: "I told Claude Code: [English version]. Is that what you meant?"
4. When Claude Code reports progress:
   - MCL applies Gate 3: explain, don't just translate
   - Translate the status update to the developer's language
   - Include key technical terms in both languages: "authentication (kimlik doğrulama)"
5. At every decision point requiring developer input:
   - Present options in the developer's language with explanations
   - After selection, confirm the English version before proceeding
6. **PRE-ACTION EXPLANATION RULE:** Before Claude Code creates a file,
   runs a tool, or makes an edit, MCL MUST explain what is about to
   happen BEFORE the action occurs:
   - What Claude Code is about to do (e.g., "X dosyasını oluşturacak")
   - Why it needs to do this (one sentence)
   - What will change if this action is taken
   This explanation appears in the developer's language, in the same
   response, BEFORE Claude Code calls the tool. The developer then
   sees the harness permission prompt with full context — they already
   know what it is and why.
   When multiple actions happen in one step (e.g., creating 3 files),
   explain each action as a numbered list before the tool calls:
   "1. `config.ts` — yapılandırma ayarları için. 2. `types.ts` — ..."
7. When harness-level permission prompts appear during execution
   (file creation, tool approval, edit confirmation):
   - MCL tracks all harness permissions the developer answered
   - At the END of Phase 4 (after all code is written), MCL includes
     a "Permission Summary" section that lists every harness permission:
     a) What the question was about
     b) Why Claude Code needed it
     c) What the developer chose and what it means
     d) What the other options would have done
     e) If MCL thinks a choice was suboptimal, it flags it with a
        recommendation (e.g., "You chose 'allow all' but a one-time
        approval would have been safer here because...")
8. If the developer introduces a NEW task during Phase 4 execution
   (scope creep, "by the way also fix...", "bu arada şunu da..."):
   - Do NOT fold the new task into the current spec
   - Acknowledge it: "I noted this as a separate task."
   - Ask: "Should I finish the current task first, or pause and
     switch to this new one?"
   - If finish first → save the new task, continue current execution
   - If switch → pause current task at a safe point, run Phase 1-3
     for the new task
   - Either way, the new task gets its own Phase 1-3 cycle
