# my-claude-lang
### The age of AI doesn't speak English. It speaks yours.

---

Until now, the best AI coding tools required you to speak English. Not anymore.

**my-claude-lang** is a plugin for Claude Code that lets you build software in your native language — with zero English knowledge required. No configuration. No language settings. Just start talking. It understands.

This is not a translator. Translators convert words. my-claude-lang converts **meaning**.

### Since 5.0.0 — Universal Activation

my-claude-lang is no longer only for non-English speakers. MCL activates on **every** message — English included — because meaning verification, senior-engineer spec generation, and anti-sycophancy matter regardless of source language. For non-English developers the translation bridge also runs; for English developers it collapses to identity, and every other layer (phase gates, self-critique, disambiguation, Phase 5 verification) still applies in full.

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

It runs a **seven-phase mutual understanding loop** before a single line of code is written:

```
You (your language)
  │
  ▼
Phase 1: MCL gathers what you want — one question at a time.
         No ambiguity passes. You confirm the summary.
         MCL may also challenge your architectural answers: if you
         say "JWT" but describe a server-side session flow, MCL
         surfaces the mismatch and asks which you meant — before
         any spec is written.
  │
  ▼
Phase 1.5 (invisible): Your confirmed intent passes through a strict
         translator pass (user_lang → EN). No interpretation, no
         additions — only natural language is translated; technical
         terms stay intact. The resulting English Engineering Brief
         is the sole input for spec generation.
  │
  ▼
Phase 2+3: Your confirmed intent becomes a visible English spec
           (📋 Spec:) written like a senior engineer with 15+ years
           experience — and MCL explains it back in your language,
           all in the same turn. One AskUserQuestion, one approval.
           The spec block is collapsible — click to hide once you've
           read it.
  │
  ▼
Phase 4: Code gets written. Incremental TDD runs inside this
         phase — for each acceptance criterion: one failing test
         (RED), minimum code to pass it (GREEN), then refactor.
         Cycle repeats per criterion; full suite re-checked at end.
         Every question Claude asks during execution goes through
         the bridge — with context explaining WHY it's asking and
         WHAT each answer changes.

         When a UI surface is detected (default ON), Phase 4 splits:
         ├─ 4a BUILD_UI  — runnable frontend with dummy data only.
         │                 You get a run command; MCL auto-opens it.
         ├─ 4b UI_REVIEW — approve the UI before backend starts.
         │                 Opt-in Playwright vision review available.
         └─ 4c BACKEND   — real API calls, data layer, async wiring.
                           Only runs after UI approval.
  │
  ▼
Phase 4.5 (Risk Review): MCL verifies that the security and
         performance decisions designed in the spec were correctly
         implemented, then scans for any missed risks — edge cases,
         regressions — walking each one with you. After risk fixes,
         TDD re-runs: all green → passes; any red → code is fixed;
         MCL / Claude Code conflict → you decide.
  │
  ▼
Phase 4.6 (Impact Review): MCL scans the rest of the project for
         real downstream effects of the change — callers, shared
         utilities, schema/API shifts — and surfaces each one for
         your decision.
  │
  ▼
Phase 5: Verification Report — Spec Coverage traceability table
         (each MUST/SHOULD requirement linked to the test that
         covers it: ✅ with file:line, ⚠️ partial, ❌ not tested).
         Then: automation barriers detected from your code's call
         graph — only items that genuinely can't be automated
         (live APIs, DOM layout, production env vars).
  │
  ▼
Phase 5.5: The full English report is formally translated back to
         your language — same strict translator pass, no
         interpretation. Technical tokens (file:line, test names)
         stay verbatim.
```

**No ambiguity survives this loop.** At every gate, you can say "no" and MCL goes back to fix it. Nothing proceeds without your explicit approval.

### Approvals via AskUserQuestion (since 6.0.0)

Every closed-ended gate (Phase 1 summary, Phase 3 spec approval, each
Phase 4.5 risk, each Phase 4.6 impact, plugin consent, git-init consent,
drift resolution, `/mcl-update` / `/mcl-finish` / pasted-CLI confirmation)
now arrives as a native Claude Code `AskUserQuestion` prompt with the
question prefix `MCL 8.1.3 | `. You pick an option in the UI — no typing
"yes" or "✅ MCL APPROVED" required. Open-ended Phase 1 gathering stays
as a plain-text conversation.

Spec drift (approved body no longer matches the current emission) is
now **warn-only**: mutating tools are never blocked, but MCL surfaces a
drift notice each turn and asks you via AskUserQuestion whether to
re-approve the new body or revert to the approved one.

Every response starts with `🌐 MCL 8.1.3` so you always know the bridge is active.

### UI Build / Review Sub-Phases (since 6.2.0)

When a task has a UI surface (default for every project), Phase 4
splits into three sub-phases so you never watch MCL build the backend
on top of a UI you wanted to change:

1. **Phase 4a (BUILD_UI)** — MCL writes a runnable frontend with
   dummy data only. React / Vue / Svelte / static HTML depending on
   your stack. You get a run command (`npm run dev` etc.); MCL
   auto-opens it in your browser.
2. **Phase 4b (UI_REVIEW)** — MCL asks whether the UI is right
   before moving on. Four options: approve / revise / **see it
   yourself and report** / cancel. "See it yourself" is an opt-in
   pipeline that uses Playwright + screenshots + Claude's
   multimodal vision to actually look at the UI it built and
   describe what it sees — requires `playwright` installed, never
   auto-installs.
3. **Phase 4c (BACKEND)** — only after you approve, MCL swaps dummy
   fixtures for real API calls, writes the data layer, wires error
   and loading states to real async behavior.

At Phase 1's summary confirm, pick "approve, skip UI" to run Phase 4
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

Since 6.1.0, MCL hard-gates itself until the curated orchestration plugins
(`superpowers`, `security-guidance`) and every stack-detected LSP plugin
are installed. Run the installer for your platform first:

```bash
# macOS / Linux
chmod +x install-claude-plugins.sh
./install-claude-plugins.sh
```

```powershell
# Windows (PowerShell)
.\install-claude-plugins.ps1
```

The scripts register the official `claude-plugins-official` marketplace
plus the community `obra/superpowers-marketplace`, then install the
curated orchestration set and every LSP plugin Claude Code ships. Both
scripts are idempotent — safe to re-run. The `claude` CLI must be on
your PATH.

> **Why this comes first:** if you skip it, MCL's PreToolUse hook will
> deny `Write` / `Edit` / `MultiEdit` / `NotebookEdit` and writer-Bash
> commands (`rm`, `git commit`, package installs, shell redirections,
> ...) on the very first message of a session, and the gate only
> re-checks when a new session starts.

### Step 2 — Install MCL itself

Since 8.5.0, MCL writes **zero files into your projects**. State, hooks, skills, and audit logs all live in `~/.mcl/projects/<project-key>/` outside your repo.

```bash
git clone https://github.com/YZ-LLM/my-claude-lang.git
bash my-claude-lang/install.sh
```

This sets up:
- **Library** → `~/.mcl/lib/` (the cloned repo — single source of truth)
- **Wrapper launcher** → `~/.local/bin/mcl-claude` (symlink)
- **Per-project state root** → `~/.mcl/projects/<sha1(realpath PWD)>/` (auto-created on first run)

Open any project and run `mcl-claude` instead of `claude`:

```bash
cd ~/projects/my-app
mcl-claude
```

The wrapper computes a stable project key from `$PWD`'s realpath, scaffolds `~/.mcl/projects/<key>/` on first run, exports `MCL_STATE_DIR` for hooks, then `exec`'s `claude` with isolated `--settings` and `--plugin-dir`. All Claude Code flags pass through transparently.

**Migrating from pre-8.5?** Existing `<project>/.mcl/` and `<project>/.claude/` directories become orphans. See [CHANGELOG 8.5.0](CHANGELOG.md) for the manual `mv` recipe.

---

## Updating

MCL ships with a passive update check and a one-keyword self-update.

Once per 24 hours, the hook fetches the upstream `VERSION` file in the background. If a newer version exists, the per-turn banner shows a localized warning next to the version number, e.g.:

```
🌐 MCL 5.4.1 (⚠️ 5.4.2 available — type mcl-update)
```

To update, send the literal message `/mcl-update`. MCL skips the normal pipeline (no spec, no phases) and runs:

```
cd $MCL_REPO_PATH && git pull --ff-only && bash install.sh
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

Phase 4.6 surfaces downstream impacts one at a time during execution. Many of those impacts are genuine "I'll verify this next week" items — they belong to a horizon that doesn't fit inside a single session.

`/mcl-finish` is the checkpoint that carries them across.

Every Phase 5 Verification Report ends with a localized reminder line pointing at the command. When you're ready, type the literal message `/mcl-finish` and MCL will:

1. Aggregate every Phase 4.6 impact written to `.mcl/impact/` since the last checkpoint
2. Run a full-project Semgrep rescan on supported stacks (silently skipped on unsupported ones)
3. Emit a project-level finish report in your language
4. Write a new checkpoint to `.mcl/finish/NNNN-YYYY-MM-DD.md`

The next `/mcl-finish` starts a fresh window from that checkpoint — closed impacts stay in the archive, new ones pile up for the next pass. No git commits, no remote pushes, no external reporting — pure local state.

Phase 4.5 risks are NOT accumulated: they're resolved in-session.

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
