<mcl_phase name="plugin-suggestions">

# Plugin Suggestions — Stack-Conditional Recommendations

MCL detects the project's language stack and, when a matching official
Claude Code plugin is not yet installed, asks the developer once per
conversation to install it. Two classes of plugin are suggested here:

- **LSP plugins** — give Claude per-edit compiler feedback (type
  errors, symbol resolution, go-to-def, rename) so the "write, build,
  see error" cycle collapses from minutes to milliseconds.
- **Non-LSP stack-conditional plugins** (currently just
  `frontend-design`) — provide framework-specific tooling that is
  only useful when a matching stack is detected.

This is a passive suggestion. MCL never auto-installs. All
stack-conditional plugins are **install-on-suggest**, distinct from
the curated required set in `plugin-orchestration.md` which MCL
dispatches silently at phase alignment points.

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

## Non-LSP Stack-Conditional Plugins

### `frontend-design`

| Trigger                                      | Plugin            | Install command                                             |
| -------------------------------------------- | ----------------- | ----------------------------------------------------------- |
| `typescript` OR `javascript` stack detected  | `frontend-design` | `/plugin install frontend-design@claude-plugins-official`   |

`frontend-design` has TWO roles since MCL 6.2.0:

1. **Install-suggest at Aşama 1** (unchanged). When the stack is
   `typescript`/`javascript` and the plugin is missing, suggest it
   once per conversation with the install command above.

2. **Auto-dispatch in Aşama 6a (BUILD_UI)** — when the UI flow is
   active (`ui_flow_active = true`) AND the plugin is installed, MCL
   silently dispatches `frontend-design` at the start of Aşama 6a
   under Rule B (multi-angle validation). The plugin's suggestions
   are merged into the component code / Aşama 6a prose; raw plugin
   tool calls are not exposed to the developer. If the plugin is NOT
   installed when Aşama 6a starts, MCL proceeds without it — Phase
   4a is never blocked on an absent plugin.

`frontend-design` is still NOT part of the curated REQUIRED set
(`plugin-gate.md`). It is stack-conditional: required-quality when
the stack matches AND UI flow is on; otherwise passive. Outside
Aşama 6a it runs only via its own explicit slash-command invocations
after install.

Framework markers (`react-frontend`, `vue-frontend`,
`svelte-frontend`, `html-static`) emitted by
`mcl-stack-detect.sh` sharpen Aşama 6a's dispatch — MCL passes the
detected framework as context to the plugin so its suggestions match
the actual component syntax.

## Detection Protocol

At the start of a new conversation in a project (first developer
message), before asking Aşama 1 questions:

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
- Mid-phase execution (Aşama 7 / 4.5 / 4.6 / 5) — do not interrupt
  ongoing work. Suggestion is a Aşama 1 concern only.
- No stack markers (docs-only repo, empty project).

## What MCL does NOT do

- Auto-install the plugin or the binary.
- Remember the decline across conversations. If the developer
  declined today, MCL may ask again in a future conversation.
- Recommend orchestration-set plugins here (`feature-dev`,
  `code-review`, `pr-review-toolkit`). Those belong to the curated
  required set in `plugin-orchestration.md` and surface via the
  consolidated install-suggestion block, not this file.
- Refine `frontend-design` suggestion with framework-marker checks
  for Angular/Solid — `react-frontend`/`vue-frontend`/`svelte-frontend`/
  `html-static` are detected since 6.2.0; Angular/Solid detection is
  deferred to a later release.

</mcl_phase>
