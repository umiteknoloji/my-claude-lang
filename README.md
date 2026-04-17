# my-claude-lang 🌐 MCL 5.1.0

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

It runs a **five-phase mutual understanding loop** before a single line of code is written:

```
You (your language)
  │
  ▼
Phase 1: MCL gathers what you want — one question at a time.
         No ambiguity passes. You confirm the summary.
  │
  ▼
Phase 2: Your confirmed intent becomes a visible English spec
         (📋 Spec:) — written like a senior engineer with 15+ years
         experience. You see it. You approve it.
  │
  ▼
Phase 3: MCL explains the spec back to you in your language.
         You verify Claude understood correctly.
  │
  ▼
Phase 4: Code gets written. Every question Claude asks you during
         execution goes through the bridge — with context explaining
         WHY it's asking and WHAT each answer changes.
  │
  ▼
Phase 5: Results are explained, not just listed.
         You understand what was built and why.
```

**No ambiguity survives this loop.** At every gate, you can say "no" and MCL goes back to fix it. Nothing proceeds without your explicit "yes."

Every response starts with `🌐 MCL 5.1.0` so you always know the bridge is active.

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

Clone and run one command. Done. No configuration. No language settings.

```bash
git clone https://github.com/umiteknoloji/my-claude-lang.git
bash my-claude-lang/setup.sh
```

This installs everything globally:
- **Skill files** → `~/.claude/skills/my-claude-lang/` (MCL rules, gates, phases)
- **Auto-activation hook** → `~/.claude/hooks/mcl-activate.sh` (detects non-English input)
- **Hook config** → `~/.claude/settings.json` (wires the hook into Claude Code)

Open a new Claude Code session and start typing in your language. That's it.

---

## Usage

Two ways to activate:

### 1. Explicit (recommended)

Type `/mcl` or `@mcl` before your message:

```
/mcl bir login sayfası yap
@mcl ログインページを作って
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
