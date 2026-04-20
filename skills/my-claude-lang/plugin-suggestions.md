<mcl_phase name="plugin-suggestions">

# Plugin Suggestions — Stack-Aware LSP Recommendations

MCL detects the project's language stack and, when a matching official
Claude Code LSP plugin is not yet installed, asks the developer once
per conversation to install it. Purpose: give Claude per-edit compiler
feedback (type errors, symbol resolution, go-to-def, rename) so the
"write, build, see error" cycle collapses from minutes to milliseconds.

This is a passive suggestion. MCL never auto-installs.

## Overlap with built-in behavior

Claude Code's harness already prompts for an LSP plugin when the
matching language-server **binary** is present on the developer's
machine. MCL's value-add over that:

- Detects stack from **project files** (package.json, pyproject.toml,
  go.mod, etc.) — works before any binary is installed.
- Asks in the **developer's language**, consistent with MCL's ethos.
- Surfaces **both** requirements in one step: the plugin AND the
  binary it needs.

When the harness has already prompted and the developer installed the
plugin, MCL sees it in `~/.claude/plugins/` and stays silent.

## Stack → Plugin Mapping

| Stack tag  | Plugin                         | Language server binary       |
| ---------- | ------------------------------ | ---------------------------- |
| typescript | `typescript-lsp`               | `typescript-language-server` |
| javascript | `typescript-lsp` (covers JS)   | `typescript-language-server` |
| python     | `pyright-lsp`                  | `pyright-langserver`         |
| go         | `gopls-lsp`                    | `gopls`                      |
| rust       | `rust-analyzer-lsp`            | `rust-analyzer`              |
| java       | `jdtls-lsp`                    | `jdtls`                      |
| kotlin     | `kotlin-lsp`                   | `kotlin-language-server`     |
| csharp     | `csharp-lsp`                   | `csharp-ls`                  |
| php        | `php-lsp`                      | `intelephense`               |
| ruby       | `ruby-lsp`                     | (bundled)                    |
| swift      | `swift-lsp`                    | `sourcekit-lsp`              |
| cpp        | `clangd-lsp`                   | `clangd`                     |
| lua        | `lua-lsp`                      | `lua-language-server`        |

Install command format:
```
/plugin install <plugin-name>@claude-plugins-official
```

Stack tags come from `hooks/lib/mcl-stack-detect.sh detect [dir]`. A
single project may return multiple tags (e.g. a monorepo with both
`package.json` and `pyproject.toml` returns `typescript` and `python`
on separate lines) — recommend the plugin for each.

## Detection Protocol

At the start of a new conversation in a project (first developer
message), before asking Phase 1 questions:

1. Run `bash ~/.claude/hooks/lib/mcl-stack-detect.sh detect "$(pwd)"`.
   Empty output → no recognizable stack → skip this protocol entirely.
2. For each detected tag, check whether the matching plugin name
   appears as a key under `.plugins` in
   `~/.claude/plugins/installed_plugins.json`. This file is the
   authoritative registry — presence there means installed, absence
   means not installed. Already installed → silent no-op for that tag.
3. For each detected-but-missing plugin, ask the developer ONCE, in
   their language. Keep the ask to one sentence + the install command.
   If the language-server binary is also likely missing, mention it
   with the install hint for their OS (e.g. `npm i -g
   typescript-language-server`, `pip install pyright`, `brew install
   gopls`).

## When to stay silent

- Plugin already installed for every detected tag.
- Developer declined earlier in this conversation — do not re-ask.
- Mid-phase execution (Phase 4 / 4.5 / 4.6 / 5) — do not interrupt
  ongoing work. Suggestion is a Phase 1 concern only.
- No stack markers (docs-only repo, empty project).

## What MCL does NOT do

- Auto-install the plugin or the binary.
- Remember the decline across conversations. If the developer
  declined today, MCL may ask again in a future conversation.
- Recommend non-LSP official plugins here (code-review, feature-dev,
  session-report, security-guidance). Those overlap with existing
  MCL phases and require separate integration analysis.

</mcl_phase>
