# Plugin Gate — Hard Install Requirement

Since MCL 6.1.0, the curated orchestration plugins AND the stack-detected
LSP plugins MUST be installed for MCL to operate. When any required
plugin — or any required binary that a plugin wraps — is missing, MCL
enters **gated mode**: mutating tools and writer-Bash are denied by the
PreToolUse hook until every missing item is resolved.

This replaces the pre-6.1.0 "soft suggestion" behavior. The gate is a
hard stop, not a friendly reminder.

## When the gate fires

The `mcl-activate.sh` hook runs the gate check exactly once per session
— on the FIRST `UserPromptSubmit` of that session. It:

1. Computes the required set: curated tier-A (`security-guidance`)
   plus one LSP plugin per stack tag returned by
   `mcl-stack-detect.sh` (e.g. `typescript-lsp`, `pyright-lsp`,
   `gopls-lsp`).
2. Reads `~/.claude/plugins/installed_plugins.json` and verifies a key
   matching `<name>@*` exists for every required plugin.
3. For each installed plugin, verifies the plugin's wrapped binary
   resolves under a login shell (`bash -lc 'command -v <bin>'`).
4. If anything is missing, persists `plugin_gate_active=true` and the
   missing list (as an array of `{"kind":"plugin"|"binary", ...}` items)
   to `.mcl/state.json`.

Subsequent activations in the same session DO NOT re-run the check —
they read the persisted flag. A new Claude Code session re-runs the
check.

## What the gate blocks

When `plugin_gate_active=true`, the `mcl-pre-tool.sh` hook denies:

- `Write`, `Edit`, `MultiEdit`, `NotebookEdit`
- `Bash` commands that match the writer-Bash heuristic: shell
  redirections (`>`, `>>`), file-mutating commands (`rm`, `mv`, `cp`,
  `touch`, `mkdir`, `chmod`, `chown`, `ln`, `dd`, `patch`, `sed -i`,
  etc.), mutating `git` subcommands (`commit`, `push`, `add`, `reset`,
  `checkout`, etc.), package-manager installs (`npm install`, `pip
  install`, `cargo install`, `brew install`, etc.), running local
  scripts (`bash foo.sh`, `python foo.py`), and infrastructure mutators
  (`docker ... up/run/build`, `kubectl ...`, `terraform ...`).

Read-only tools still pass: `Read`, `Grep`, `Glob`, `TodoWrite`,
`WebFetch`, `WebSearch`, `AskUserQuestion`, and read-only `Bash`
(`ls`, `cat`, `grep`, `find`, etc.).

## What Claude must do when gated

When the activate hook emits a `<mcl_audit name="plugin-gate">` block,
the gate notice IS the entire response. Claude must:

1. Open with one localized line in the developer's language saying MCL
   is gated and what is missing (e.g. Turkish `MCL kilitli — eksik
   plugin/binary var.` / English `MCL is gated — required plugins or
   binaries are missing.`).
2. List each missing item with its install command:
   - `plugin:<name>` → emit the literal line `/plugin install
     <name>@claude-plugins-official`
   - `binary:<plugin>/<bin>` → state BOTH the plugin name AND the
     binary name so the developer can install via their platform
     package manager (`npm i -g typescript-language-server`, `pip
     install pyright`, `cargo install rust-analyzer`, etc.)
3. State plainly that MCL stays gated until every missing item is
   resolved AND a new MCL session is started.
4. Do NOT run Phase 1 intent gathering. Do NOT call `AskUserQuestion`.
   Do NOT emit a spec. The gate listing is the entire response.

The gate repeats on EVERY turn until resolved — the `warn-once-then-
execute` rule does NOT apply, because the gate is a hard stop.

## Stack → plugin → binary mapping

The canonical table lives in `plugin-suggestions.md`. The gate mirrors
it as a pure-bash lookup in `hooks/lib/mcl-plugin-gate.sh` so the gate
has zero runtime dependency on the skill file.

| Stack tag             | LSP plugin           | Wrapped binary                |
| --------------------- | -------------------- | ----------------------------- |
| typescript/javascript | `typescript-lsp`     | `typescript-language-server`  |
| python                | `pyright-lsp`        | `pyright-langserver`          |
| go                    | `gopls-lsp`          | `gopls`                       |
| rust                  | `rust-analyzer-lsp`  | `rust-analyzer`               |
| java                  | `jdtls-lsp`          | `jdtls`                       |
| kotlin                | `kotlin-lsp`         | `kotlin-language-server`      |
| csharp                | `csharp-lsp`         | `csharp-ls`                   |
| php                   | `php-lsp`            | `intelephense`                |
| ruby                  | `ruby-lsp`           | (bundled)                     |
| swift                 | `swift-lsp`          | `sourcekit-lsp`               |
| cpp                   | `clangd-lsp`         | `clangd`                      |
| lua                   | `lua-lsp`            | `lua-language-server`         |

## Audit trail

Every gate event lands in `.mcl/audit.log` independently of
`MCL_DEBUG`:

- `plugin-gate-activated` — written by `mcl-activate.sh` when the
  session's first check finds missing items.
- `plugin-gate-block` — written by `mcl-pre-tool.sh` each time a
  mutating tool or writer-Bash command is denied while the gate is
  active.

This is a security-relevant trail: if Claude tries to route around the
gate (running a fresh Bash command for each denied attempt, for
example), every attempt is visible in the log.
