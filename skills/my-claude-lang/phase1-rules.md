<mcl_phase name="phase1-rules">

# Phase 1: Gather Parameters — Detailed Rules

**`superpowers` (tier-A, ambient):** active throughout this phase — no explicit dispatch point; its methodology layer applies as a behavioral prior.

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
   as plain text AND immediately call `AskUserQuestion` (since 6.0.0).
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
━━━━━━━━━━━━━━━━━━━━━
```

Then call:
```
AskUserQuestion({
  question: "MCL 7.1.6 | <localized 'Is this correct?'>",
  options: [
    "<approve-verb>",
    "<edit-verb>",
    "<cancel-verb>"
  ]
})
```

The 3-option form is canonical since 6.5.2. `ui_flow_active` is
NOT decided here — it is auto-detected at session activation by
`mcl-activate.sh` running the stack heuristic
(`mcl_is_ui_capable` in `hooks/lib/mcl-stack-detect.sh`). The
heuristic returns true when the project has a UI surface
(package.json + templates/, `src/components/**`, Django + templates/,
Rails `app/views/`, root `index.html`, etc.) and false otherwise.
The developer is never prompted about UI skip — if there is no UI
surface, Phase 4a is silently bypassed and standard Phase 4 runs.

Reference approve/edit/cancel label triples (full 14-language set
pinned in `phase3-verify.md` Label Discipline section):

| Locale | Approve    | Edit        | Cancel     |
| ------ | ---------- | ----------- | ---------- |
| TR     | Onayla     | Düzenle     | İptal      |
| EN     | Approve    | Edit        | Cancel     |
| JA     | 承認       | 編集        | キャンセル |
| KO     | 승인       | 편집        | 취소       |
| ZH     | 批准       | 编辑        | 取消       |
| AR     | موافق     | تعديل       | إلغاء      |
| HE     | אשר        | ערוך        | ביטול      |
| DE     | Genehmigen | Bearbeiten  | Abbrechen  |
| ES     | Aprobar    | Editar      | Cancelar   |
| FR     | Approuver  | Modifier    | Annuler    |
| HI     | स्वीकार    | संपादित करें | रद्द करें  |
| ID     | Setujui    | Edit        | Batal      |
| PT     | Aprovar    | Editar      | Cancelar   |
| RU     | Одобрить   | Изменить    | Отмена     |

**⛔ STOP RULE:** After presenting the summary and calling
`AskUserQuestion`, your response ENDS. Do NOT read files. Do NOT
explore code. Do NOT start writing the spec. Do NOT say "I'll prepare
the spec now." STOP and wait for the tool_result.

5. If the tool_result is non-approve-family (edit/cancel/etc.) → ask
   "What did I get wrong?" and re-run gathering.
6. Only after the tool_result returns an approve-family option → call
   Phase 2. `ui_flow_active` is already set by activation; stop hook
   does NOT touch it on summary-confirm.

## Disambiguation Triage

Before asking any clarifying question, classify the ambiguity:

### SILENT — assume and document (do NOT ask)

**Trivial defaults** — standard industry values where any reasonable choice
works and changing it later is cheap:
- Pagination size (assume 20/page)
- Error message wording
- Log level for non-critical paths
- Timeout values where no SLA is specified
- Variable/function naming conventions (match existing codebase)

→ Mark in spec as `[assumed: X]` under the relevant section.

**Reversible choices** — a direction must be picked but it's easy to change:
- Which CSS library within a category (Tailwind vs. Bootstrap)
- State management approach for a simple feature
- File/folder naming within the project's existing conventions
- Test data structure

→ Mark in spec as `[default: X, changeable]` under the relevant section.

### GATE — ask one question at a time

Ask only when writing the spec is impossible without the answer:
- **Schema / migration decisions** — adding a non-null column, dropping a table, changing an index
- **Auth or permission model** — who can see/do what
- **Public API surface or breaking changes** — endpoint naming, response shape, versioning
- **Business logic with irreversible data consequences** — "what happens to a user's posts when their account is deleted?"
- **Security boundary decisions** — what is private, what is audited, what is encrypted

**Heuristic:** "Can I write the spec without this answer?"
- Yes → assume silently, mark it.
- No → ask.

**Safety net:** Phase 3 spec review shows all assumptions. If an assumption
was wrong, the developer corrects it there — before any code is written.
This means a wrong silent assumption has zero implementation cost.

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

### Logical Parameter Contradictions

Before advancing from Phase 1 to Phase 2, check all parameters for
logical contradictions. Examples:

- "offline AND always show real-time data" → contradictory
- "no database BUT persist user data" → contradictory
- "simple AND enterprise-grade with full audit logging" → potentially contradictory

If contradictions are found:
- Explain the contradiction in the developer's language
- Ask: "Which one takes priority?"
- Resolve before advancing

### GATE Answer Coherence

After each GATE answer involving an architectural choice, silently check:
do the technical implications of this answer fit the system behavior
described in the conversation?

**Trigger condition:** architectural choices only (auth model, data storage,
API shape, consistency model). Not trivial parameters.

**Mismatch examples:**
- User said "JWT" but described flow requires server-side state lookup on every
  request → JWT is stateless, cannot do this without a token store (= sessions)
- User said "NoSQL" but requirements include multi-table transactional consistency
  → NoSQL typically lacks multi-entity ACID guarantees
- User said "stateless API" but described "remember me across devices"
  → cross-device persistence requires server-side state
- User said "microservice per domain" but described a flow needing ACID transactions
  spanning multiple domains

**Format** (verdict first — one sentence, developer's language):
```
⚠️ [Specific technical conflict]:
"JWT seçtiniz, ama tarif ettiğiniz [behavior] sunucu tarafı oturum takibi
gerektiriyor — JWT'nin stateless yapısıyla çelişiyor.
(a) Stateless JWT → [what needs to change]
(b) Server-side sessions → [described flow works as-is]"
```

**Rules:**
- One conflict, one question — never a list
- Only fire for concrete technical incompatibility — not style preference
- Vague concern → skip silently
- If user insists without new evidence: pressure-resistance rule applies (hold position)
- If user makes an explicit decision ("proceed", "I accept the risk"): human authority
  rule applies — close the topic, do not circle back (see self-critique.md)

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

## Phase 1 → 1.7 handoff (since 8.15.0)

After Phase 1 summary is approved (AskUserQuestion confirmed, developer
accepted the captured intent / constraints / success / context), emit
the following Bash commands BEFORE handing off to Phase 1.5/1.7. These
populate state fields that downstream phases (Phase 1.7 ops/perf
add-ons, Phase 4.5 ops/perf gates, Phase 6 promise-vs-delivery) rely on:

```bash
bash -c '
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0")")" 2>/dev/null || true
# Try multiple state-lib paths (per-project install / wrapper install / dev clone).
for lib in "$MCL_HOME/lib/hooks/lib/mcl-state.sh" \
           "$HOME/.mcl/lib/hooks/lib/mcl-state.sh" \
           "$HOME/.claude/hooks/lib/mcl-state.sh"; do
  [ -f "$lib" ] && source "$lib" && break
done
mcl_state_set phase1_intent "<one-line intent summary, English>" >/dev/null 2>&1
mcl_state_set phase1_constraints "<one-line constraints CSV (stack, env, scale, etc.)>" >/dev/null 2>&1
mcl_state_set phase1_stack_declared "<comma-separated stack tags inferred from Phase 1 context, e.g. react-frontend,python,db-postgres>" >/dev/null 2>&1
_mcl_validate_stack_tags "<same comma-separated tags as above>" || true
mcl_audit_log "phase1_state_populated" "phase1" "intent+constraints+stack" 2>/dev/null || true
'
```

The `_mcl_validate_stack_tags` call (since 8.16.0) checks each token
against the canonical known-tag set in `mcl-state.sh`. Unknown tokens
(typos like `react-frontnd`, non-canonical aliases like `db-postgresql`)
emit a stderr WARN and an `stack-tag-unknown` audit entry. The set
write itself is not blocked — the warning is advisory so Phase 1.7 can
continue with whatever subset of tags did match.

The `phase1_state_populated` audit event (since 8.16.0) is required by
Phase 6 (a) audit-trail completeness check. If skill prose Bash is
forgotten, Phase 6 (a) reports a LOW soft fail.

`phase1_stack_declared` is the **greenfield fallback** for
`mcl-stack-detect.sh` — when the project has no manifest yet but the
developer has stated the stack in Phase 1, downstream stack-add-on
gates (Phase 1.7 DB / UI / ops / perf dimensions) read this field and
apply the relevant rule subset. Without it, Phase 1.7 stack add-ons
silently skip on greenfield projects.

`phase1_intent` and `phase1_constraints` are required by Phase 6 (c)
promise-vs-delivery — keyword extraction reads these fields and
matches against modified source files. If unset, Phase 6 (c) skips
with LOW advisory.

</mcl_phase>
