# my-claude-lang  (MCL)

### The age of AI doesn't speak English. It speaks yours.

---

Until now, the best AI coding tools required you to speak English. Not anymore.

**my-claude-lang** is a plugin for Claude Code that lets you build software in your native language — with zero English knowledge required. No configuration. No language settings. Just start talking. It understands.

This is not a translator. Translators convert words. my-claude-lang converts **meaning**.

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

It creates a **three-phase mutual understanding loop** before a single line of code is written:

```
You (your language)
  │
  ▼
Phase 1: my-claude-lang listens, then tells you what it understood
         in YOUR language. You confirm or correct.
  │
  ▼
Phase 2: Your confirmed intent becomes a precise English
         technical specification.
  │
  ▼
Phase 3: Claude Code reads the spec and explains what IT understood.
         That explanation is translated back to you.
         You confirm or correct.
  │
  ▼
All three parties agree on the exact same thing → Code gets written.
```

**No ambiguity survives this loop.** If you say "no" at any point, it goes back and tries again. It does not proceed until you say "yes."

During execution, every question Claude Code asks you goes through the bridge. Every answer you give goes back through the bridge. Every status update, every code review result, every error message — explained to you in your language, not just translated.

---

## Installation

Download. Install. Done. No configuration. No language settings.

### As a Plugin

```bash
/plugin marketplace add umiteknoloji/my-claude-lang
/plugin install my-claude-lang@umiteknoloji
```

### As a Skill

```bash
cp my-claude-lang/SKILL.md ~/.claude/skills/my-claude-lang/SKILL.md
```

### Auto-Activation Hook (recommended)

The hook detects non-English input automatically and forces MCL activation on every message. Run once — works globally:

```bash
bash my-claude-lang/hooks/setup.sh
```

This installs a `UserPromptSubmit` hook that analyzes each prompt for non-English content (Unicode scripts, accented characters, and common function words across 14+ languages). When detected, Claude receives a mandatory MCL activation reminder.

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

my-claude-lang sees the same sentence and produces an English spec that asks:

- What authentication method? Session-based? JWT? OAuth?
- Client-side redirect or server-side?
- What happens if the session expires mid-redirect?
- Is there a "remember me" option?
- Where does a failed login redirect to?
- What should the loading state look like?

Then it translates all those questions back to you, gets your answers, translates those answers back to English, and only THEN lets Claude Code start building.

**That's not translation. That's a senior engineer who happens to speak your language.**

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
