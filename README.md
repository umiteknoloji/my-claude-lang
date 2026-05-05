# my-claude-lang
### The age of AI doesn't speak English. It speaks yours.

---

Until now, the best AI coding tools required you to speak English. Not anymore.

**my-claude-lang** is a plugin for Claude Code that lets you build software in your native language — with zero English knowledge required. No configuration. No language settings. Just start talking. It understands.

This is not a translator. Translators convert words. my-claude-lang converts **meaning**.

### Since 5.0.0 — Universal Activation

my-claude-lang is no longer only for non-English speakers. MCL activates on **every** message — English included — because meaning verification, senior-engineer spec generation, and anti-sycophancy matter regardless of source language. For non-English developers the translation bridge also runs; for English developers it collapses to identity, and every other layer (phase gates, self-critique, disambiguation, Aşama 11 verification) still applies in full.

---

## The Problem No One Talks About

Claude Code is the most powerful AI coding tool in the world. It plans like a senior engineer, writes tests before code, reviews its own work, and ships production-grade software.

But it thinks in English. And if you don't speak English, you're locked out of all of that.

You could use a translator. But here's what happens when you translate your request to English and paste it into Claude Code:

- Your intent gets flattened into literal words
- Nuance disappears — "I want it fast" becomes speed, not simplicity
- Context evaporates — your constraints, your preferences, your "obviously I meant..." — gone
- You get technically correct code that does the wrong thing
- You waste hours, tokens, and patience

**my-claude-lang exists because translation is not understanding.**

---

## What my-claude-lang Actually Does

It runs a **twenty-one-stage mutual understanding loop** before a single line of code is written:

> **Note (v11.0 vision):** The pipeline below is MCL's v11.0 target architecture. The current stable release (see `VERSION`) still runs the 13-phase architecture; v11.0 is being delivered incrementally. During the bridge period, CHANGELOG.md describes which phases the active version supports.

```
You (in your own language)
  │
  ▼
Phase 1: MCL asks you one question at a time to understand what you want.
         No ambiguity passes through. You approve the summary.
         MCL also challenges your architectural answers:
         if you say "JWT" but describe a server-side session flow,
         MCL surfaces the contradiction and asks which one
         you meant — before any spec is written.
  │
  ▼
Phase 2: Verifies the correctness and completeness of your intent
         with a 7-dimension precision audit + hard enforcement.
  │
  ▼
Phase 3: The approved intent goes through a strict translator pass
         (user language → EN). No interpretation, no additions —
         only natural language is translated; technical terms
         remain as-is. The resulting English Engineering
         Brief becomes the sole input for spec generation.
  │
  ▼
Phase 4: The approved intent becomes a visible English technical
         specification (📋 Spec:) — written like a senior engineer
         with 15+ years of experience — and MCL explains the spec
         back to you in your own language; both in the same turn,
         with a single AskUserQuestion approval. The spec block
         is collapsible — click to hide it once you've read it.
  │
  ▼
Phase 5: Pattern Matching is performed. Skipped if the project
         is being created from scratch.
  │
  ▼
Phase 6: Front-end is built with dummy data. The project and all
         its dependencies are brought up. The project is automatically
         opened in the browser.
  │
  ▼
Phase 7: You inspect the UI. If updates are needed, tell MCL.
         Opt-in Playwright visual review is available. You can
         have it run too if you want, but it is costly.
  │
  ▼
Phase 8: Test-first development (TDD). For every acceptance
         criterion, a failing test is written FIRST (RED), THEN
         the minimum production code to pass it (GREEN), then
         refactor. The cycle repeats for each criterion; at the
         end the full suite is run again. Tests always come
         before production code — not "write code then add tests",
         real TDD.
  │
  ▼
Phase 9 (Risk Review): MCL verifies that the security and
         performance decisions designed in the spec are correctly
         implemented; then scans for missed risks — edge cases,
         regressions — and walks through each one with you. After
         risk fixes are done, TDD tests are re-run: all green →
         passes; red → the relevant code is fixed; conflict →
         you decide.
  │
  ▼
Phase 10: Code review is performed on new or changed files.
          Found issues are auto-fixed.
  │
  ▼
Phase 11: Simplify is performed on new or changed files.
          Found issues are auto-fixed.
  │
  ▼
Phase 12: Performance check is performed on new or changed files.
          Found issues are auto-fixed.
  │
  ▼
Phase 13: Security vulnerability check is performed on the
          entire project. Found issues are auto-fixed.
  │
  ▼
Phase 14: Unit tests and TDD tests are performed on new or
          changed files. Found issues are auto-fixed.
  │
  ▼
Phase 15: Integration tests are performed on new or changed files.
          Found issues are auto-fixed.
  │
  ▼
Phase 16: E2E tests are performed on new or changed files.
          Found issues are auto-fixed.
  │
  ▼
Phase 17: Load tests are performed on new or changed files.
          Found issues are auto-fixed.
  │
  ▼
Phase 18 (Impact Review): MCL scans the rest of the project for
          actual downstream effects of the change — callers,
          shared utilities, schema/API shifts — and puts each
          one in front of you for your decision.
  │
  ▼
Phase 19: Verification Report — Spec Coverage table (each
          MUST/SHOULD requirement linked to the test that covers
          it: ✅ with file:line, ⚠️ partial, ❌ no test written).
          Mock data is removed from the project.
  │
  ▼
Phase 20: The full English report is translated to your language
          with a strict translator pass (EN → user language) —
          no interpretation, no additions. Technical tokens
          (file:line, test names) are preserved as-is.
  │
  ▼
Phase 21: Completeness Audit — `.mcl/audit.log` is read and
          each phase 1-20 is verified to have actually completed
          end-to-end. The Open Issues section surfaces gaps the
          pipeline missed.
```

**No ambiguity survives this loop.** At every gate, you can say "no" and MCL goes back to fix it. Nothing proceeds without your explicit approval.

### Approvals via AskUserQuestion (since 6.0.0)

Every closed-ended gate (Aşama 1 summary, Aşama 4 spec approval, each
Aşama 8 risk, each Aşama 10 impact, plugin consent, git-init consent,
drift resolution, `/mcl-update` / `/mcl-finish` / pasted-CLI confirmation)
arrives as a native Claude Code `AskUserQuestion` prompt with the
question prefix `MCL 10.1.19 | `. You pick an option in the UI — no typing
"yes" or "✅ MCL APPROVED" required. Open-ended Aşama 1 gathering stays
as a plain-text conversation.

Spec drift (approved body no longer matches the current emission) is
now **warn-only**: mutating tools are never blocked, but MCL surfaces a
drift notice each turn and asks you via AskUserQuestion whether to
re-approve the new body or revert to the approved one.

Every response starts with `🌐 MCL 10.1.19` so you always know the bridge is active.

### UI Build / Review Sub-Phases (since 6.2.0)

When a task has a UI surface (default for every project), Aşama 6
splits into three sub-phases so you never watch MCL build the backend
on top of a UI you wanted to change:

1. **Aşama 6a (BUILD_UI)** — MCL writes a runnable frontend with
   dummy data only. React / Vue / Svelte / static HTML depending on
   your stack. You get a run command (`npm run dev` etc.); MCL
   auto-opens it in your browser.
2. **Aşama 6b (UI_REVIEW)** — MCL asks whether the UI is right
   before moving on. Four options: approve / revise / **see it
   yourself and report** / cancel. "See it yourself" is an opt-in
   pipeline that uses Playwright + screenshots + Claude's
   multimodal vision to actually look at the UI it built and
   describe what it sees — requires `playwright` installed, never
   auto-installs.
3. **Aşama 6c (BACKEND)** — only after you approve, MCL swaps dummy
   fixtures for real API calls, writes the data layer, wires error
   and loading states to real async behavior.

At Aşama 1's summary confirm, pick "approve, skip UI" to run Aşama 7
without the split (same behavior as 6.1.1). UI is default ON because
most projects have a UI surface; bash scripts and backend-only
changes opt out in one click.

---

## Informed Decisions, Not Blind Answers

When Claude Code asks you a question during execution, MCL doesn't just translate it. It adds:

1. **Why this question matters** — what Claude needs to decide
2. **What each answer changes** — so you know the implications before you respond

You're never guessing. You're deciding with full context — like having a senior engineer explain every decision point in your language.

---

## Proven Results: Better Than Writing in English

We tested MCL across 13 languages and compared the output against what a senior English-speaking engineer (15+ years experience) would produce by writing the same request directly in English.

**Result: 2 EQUAL, 11 MCL BETTER.**

MCL doesn't just match a native English engineer's quality — in 11 out of 13 languages, it produces **better** specs.

| # | Language | vs. Senior Engineer | Why |
|---|----------|-------------------|-----|
| 1 | 🇹🇷 Turkish | EQUAL | Optimized — MCL was built on Turkish |
| 2 | 🇯🇵 Japanese | EQUAL | Japanese is already precise and structured |
| 3 | 🇩🇪 German | **MCL BETTER** | Catches more edge cases |
| 4 | 🇨🇳 Chinese | **MCL BETTER** | Breaks analogies into concrete specs |
| 5 | 🇰🇷 Korean | **MCL BETTER** | Preserves cultural expressions |
| 6 | 🇪🇸 Spanish | **MCL BETTER** | Converts negation into positive specs |
| 7 | 🇫🇷 French | **MCL BETTER** | Detects vagueness others miss |
| 8 | 🇮🇩 Indonesian | **MCL BETTER** | Resolves vague terms before execution |
| 9 | 🇸🇦 Arabic | **MCL BETTER** | Completes missing details |
| 10 | 🇧🇷 Portuguese | **MCL BETTER** | Catches technical homonyms + audit trail |
| 11 | 🇷🇺 Russian | **MCL BETTER** | Decomposes hidden sub-tasks |
| 12 | 🇮🇳 Hindi | **MCL BETTER** | Flags privacy concerns in vague requests |
| 13 | 🇮🇱 Hebrew | **MCL BETTER** | Disambiguates authorization models |

### Why These 13 Languages?

These languages were chosen to represent the world's major writing systems:

- **Latin** — Turkish, German, Spanish, French, Indonesian, Portuguese
- **CJK** — Chinese (Hanzi), Japanese (Kanji + Hiragana + Katakana), Korean (Hangul)
- **Cyrillic** — Russian
- **Devanagari** — Hindi
- **Arabic script (RTL)** — Arabic
- **Hebrew script (RTL)** — Hebrew

This covers the script families used by the vast majority of the world's developers — left-to-right, right-to-left, character-based, and syllabary systems. If MCL works across all of these, it works for your language too.

### Why Does MCL Beat Native English?

Because the advantage isn't linguistic — it's **procedural**.

A senior engineer writing in English might type "Build a notification system" and Claude starts coding. Maybe Claude asks clarifying questions. Maybe it doesn't. There's no guarantee.

MCL makes disambiguation **mandatory, not optional**:
- Every vague term gets challenged
- Every hidden sub-task gets surfaced
- Every cultural expression gets decoded
- Every assumption gets verified before a single line of code is written

**MCL doesn't teach Claude your language. It enforces engineering discipline on Claude. And that produces better results than English alone.**

---

## Installation

### Step 1 — Install the required Claude Code plugins (BEFORE MCL)

Since 6.1.0, MCL hard-gates itself until the curated orchestration plugin
(`security-guidance`) and every stack-detected LSP plugin are installed.
Run the installer for your platform first:

```bash
# macOS / Linux
chmod +x install-claude-plugins.sh
./install-claude-plugins.sh
```

```powershell
# Windows (PowerShell)
.\install-claude-plugins.ps1
```

The scripts register the official `claude-plugins-official` marketplace,
then install the curated orchestration set and every LSP plugin Claude
Code ships. Both scripts are idempotent — safe to re-run. The `claude`
CLI must be on your PATH.

> **Why this comes first:** if you skip it, MCL's PreToolUse hook will
> deny `Write` / `Edit` / `MultiEdit` / `NotebookEdit` and writer-Bash
> commands (`rm`, `git commit`, package installs, shell redirections,
> ...) on the very first message of a session, and the gate only
> re-checks when a new session starts.

### Step 2 — Install MCL itself

Clone and run one command. No configuration. No language settings.

```bash
git clone https://github.com/YZ-LLM/my-claude-lang.git
bash my-claude-lang/setup.sh
```

This installs everything globally:
- **Skill files** → `~/.claude/skills/my-claude-lang/` (MCL rules, gates, phases)
- **Auto-activation hook** → `~/.claude/hooks/mcl-activate.sh` (detects non-English input)
- **Hook config** → `~/.claude/settings.json` (wires the hook into Claude Code)

Open a new Claude Code session and start typing in your language. That's it.

---

## Updating

To update, send the literal message `/mcl-update`. MCL skips the normal pipeline (no spec, no phases) and runs:

```
cd $MCL_REPO_PATH && git pull --ff-only && bash setup.sh
```

`MCL_REPO_PATH` defaults to `$HOME/my-claude-lang`. Override via environment variable if your clone lives elsewhere. The updated hook and skill files are re-read on every prompt, so the next message in the same session already uses the new rules — no session restart needed.

---

## Partial Spec Recovery — Rate-Limit Interruption Defense

Long specs can get cut off mid-stream by a rate-limit, a network drop, or a process kill. Before 5.15.0, a follow-up `yes` from you would silently promote that truncated spec to EXECUTE — because MCL's state machine only listened for the approval token, not the structural completeness of the spec body. You'd end up with an approved spec that was missing half its requirements, and the only way out was a manual `rm .mcl/state.json`.

Since 5.15.0, MCL detects the truncation at the Stop-hook layer: if a `📋 Spec:` block is missing any of the seven required sections (Objective, MUST, SHOULD, Acceptance Criteria, Edge Cases, Technical Approach, Out of Scope), a `partial_spec=true` flag is raised in state. The next activation tells Claude to re-emit the full spec — and ignores any approval token until the flag is cleared by a complete spec. Defense-in-depth: the developer doesn't need to notice the interrupt; MCL notices for them.

---

## Token & Cost Accounting — `/mcl-doctor`

MCL logs the size of its context injection on every turn. Type `/mcl-doctor` to see a breakdown:

- **MCL injection overhead** per turn (chars → estimated tokens)
- **Cache write vs cache read** cost (Sonnet 4.6 rates)
- **MCL on vs off comparison** — net cost of running MCL this session
- **Session token summary** from your actual session log

Pricing is estimated. For exact billing, check Claude Console.
To reset the counter: `rm .mcl/cost.json`

---

## Cross-Session Finish Mode — `/mcl-finish`

Aşama 10 surfaces downstream impacts one at a time during execution. Many of those impacts are genuine "I'll verify this next week" items — they belong to a horizon that doesn't fit inside a single session.

`/mcl-finish` is the checkpoint that carries them across.

Every Aşama 11 Verification Report ends with a localized reminder line pointing at the command. When you're ready, type the literal message `/mcl-finish` and MCL will:

1. Aggregate every Aşama 10 impact written to `.mcl/impact/` since the last checkpoint
2. Run a full-project Semgrep rescan on supported stacks (silently skipped on unsupported ones)
3. Emit a project-level finish report in your language
4. Write a new checkpoint to `.mcl/finish/NNNN-YYYY-MM-DD.md`

The next `/mcl-finish` starts a fresh window from that checkpoint — closed impacts stay in the archive, new ones pile up for the next pass. No git commits, no remote pushes, no external reporting — pure local state.

Aşama 8 risks are NOT accumulated: they're resolved in-session.

---

## Usage

Two ways to activate:

### 1. Explicit (recommended)

Type `/mcl` or `/mcl` before your message:

```
/mcl bir login sayfası yap
ログインページを作って
/mcl 做一个登录页面
```

This **guarantees** activation. No ambiguity. Once activated, MCL stays active for the entire conversation — no need to type it again.

### 2. Automatic (with hook)

Just write in your language. If you installed the hook, MCL auto-activates on every non-English message — no prefix needed. If you didn't install the hook, type `/mcl` once to force activation.

---

## What Makes This Different From Translation

A translator sees:

> "kullanıcı giriş yaptıktan sonra ana sayfaya yönlendirilsin"

And produces:

> "redirect user to main page after login"

my-claude-lang sees the same sentence and asks you:

- What authentication method? Session-based? JWT? OAuth?
- Client-side redirect or server-side?
- What happens if the session expires mid-redirect?
- Is there a "remember me" option?
- Where does a failed login redirect to?
- What should the loading state look like?

Then it translates all those questions back to you — with context explaining why each question matters and what your answer will change. It gets your answers, translates them back to English, and only THEN lets Claude Code start building.

**That's not translation. That's a senior engineer who speaks your language.**

---

## How Technical Terms Work

- Universal terms stay in English: API, REST, GraphQL, Docker, Git, database
- Semi-technical terms get both: "endpoint (erişim noktası)"
- Conceptual terms are fully explained in your language with English in parentheses
- If a term has no established translation in your language, it stays in English — no invented words

---

## Works With Everything

my-claude-lang integrates with the entire Claude Code ecosystem:

- **Superpowers** — brainstorming and planning questions go through the bridge
- **Local-Review** — code review results are explained, not just translated
- **Claude-Mem** — memory works alongside the bridge
- **Any plugin that talks to you** — all communication routes through my-claude-lang

---

## Supported Languages

Every language Claude supports. Auto-detected. No setup.

---

## The Real AI Age

For years, AI coding tools had an invisible gate: English proficiency.

If you grew up in Istanbul, São Paulo, Tokyo, Cairo, or Seoul — and you didn't learn English along the way — the most powerful development tools on Earth were behind a wall you couldn't climb.

my-claude-lang removes that wall.

Not by teaching you English. Not by dumbing down the tools. But by building a bridge that preserves every ounce of your intent, your nuance, your expertise — and delivers it to Claude Code in the language it thinks best in.

**The real AI age is not about tools that work in English. It's about tools that work in yours.**

---

## License

MIT — free to use, modify, and distribute.
