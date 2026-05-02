# Plugin Orchestration — Curated Required Set

MCL auto-dispatches to a curated set of Claude Code plugins at the
natural alignment points of its phase pipeline. The developer never
types `/feature-dev`, `/code-review`, etc. — MCL decides what runs
and when, merges the plugin's output into its own phase prose, and
renders the result in the developer's language. Every member of the
curated set is **required**: missing ones are surfaced in a single
consolidated install-suggestion block at the first developer message.

This file is distinct from two nearby files:

- `plugin-suggestions.md` covers **stack-conditional optional**
  plugins (LSPs, frontend-design) — install-on-suggest, no dispatch.
- `plugin-integration.md` covers what happens when the developer
  **explicitly** invokes a plugin via slash-command — a language
  bridge rule, not a dispatch rule.

This file covers the **silent auto-dispatch** path: MCL invokes
plugin agents via the Agent tool as sub-steps of its own phases,
without the developer asking, as a required part of every session.

## The curated set

| Plugin               | Tier                           | Trigger                                                                            | MCL phase alignment                                                    |
| -------------------- | ------------------------------ | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `feature-dev`        | tier-B (classifier-gated)      | Request-type classifier returns `feature`                                          | code-explorer → Aşama 1; code-architect → Aşama 7; code-reviewer → Aşama 8; FD-7 → Aşama 11 |
| `code-review`        | tier-A (diff-gated)            | Meaningful diff exists in current git working tree                                 | Findings merge into Aşama 8 dialog                                   |
| `pr-review-toolkit`  | tier-A + selective             | Always-on for high-signal agents; selective sub-agents fire on code-shape triggers | Selective findings merge into Aşama 8 dialog                         |
| `security-guidance`  | tier-A (ambient hook)          | Plugin-native PreToolUse on Edit/Write/MultiEdit                                   | Write-time guardrail — shapes Aşama 7 output before code lands         |

`security-guidance` is a PreToolUse hook; MCL does not dispatch it
and does not merge findings from it (plugin injects guidance text
directly into Claude's context, which shapes code before it is
written). It complements Spec-1's Semgrep SAST (post-write delta
scan) — the two cover write-time vs post-write windows
independently. Rule B's "different-angle = value" invariant is the
reason both exist in the set.

`frontend-design` is **not** in the curated set. It lives in
`plugin-suggestions.md` as a stack-conditional optional plugin
(suggested when a frontend stack is detected).

## Rule A — MCL guarantees git

Many curated plugins depend on a git repository to read diffs or
blame. To make dispatch uniform and never-skip, MCL ensures a
`.git/` directory exists in the project root.

**Why:** Developer commitment — "projelerde git kullanıldığını
varsaymamalısın. hiç bir SVN kullanılmıyor olabilir." MCL's earlier
drafts gated git-requiring plugins on git presence and skipped them
when absent. The developer's follow-up reframe — "MCL git e private
olarak koyar projeyi. o zaman hiç bişey atlanmaz" — replaces the
gate with a guarantee: no skip, because git is always present.

**How to apply:**

- On first MCL activation in a project, if `.git/` is missing, MCL
  asks the developer **once** in their language: *"Plugin orchestration
  için yerel bir `.git/` dizini kurayım mı? Sadece yerel bookkeeping
  için — uzak repo eklenmez."* Single yes/no prompt.
- Consent → `git init` silently, persist `git_ensure_consent: true`
  in `.mcl/config.json`. No further prompts for this project.
- Decline → persist `git_ensure_consent: false`. Curated plugins
  that need git (code-review, git-aware pr-review-toolkit agents)
  silently skip for the rest of the project's lifetime, with a
  one-line note in Aşama 8 report ("code-review skipped: no git").
- Write failure (read-only mount, permission denied) → fail open:
  log to `<project>/.mcl/audit.log`, silently skip git-dependent
  plugins, do not block the session.
- MCL never adds a remote, never pushes, never commits on the
  developer's behalf inside this repo. The repo exists for read-only
  bookkeeping by plugins.

## Rule B — Different-angle dispatch + silent merge

When MCL's own phase logic and a curated plugin cover overlapping
ground (e.g., MCL Aşama 8 risk review + feature-dev's
code-reviewer + code-review's 4-agent PR review), the overlap is
**multi-angle validation**, not redundancy. MCL dispatches all of
them silently and merges their findings.

**Why:** Developer commitment — "kullanacağımız plugin lerin işini
yapan şeyler bizde olsa bile onlar daha farklı açıdan yaklaşıyor
olabilir. o yüzden onları da sessizce kullansın MCL ve sonuçları
mantıklı bi şekilde birleştirsin." Different training data, different
heuristics, different model prompting surface the long-tail of risks
that any single pass misses.

**How to apply:**

- Dispatch is silent — the developer never sees a spinner or a "running
  feature-dev code-reviewer…" line. Output merges into the existing
  MCL phase block as if MCL produced it.
- Merge logic for findings: dedupe on `(file, line, rule-equivalent)`,
  union the remaining set, localize all developer-facing text per MCL's
  language bridge, preserve file paths / line numbers / code
  identifiers verbatim.
- When plugins disagree (one says "safe", another says "unsafe"), do NOT
  apply an automatic tiebreaker. Surface the conflict as a single Phase
  4.5 risk item with explicit provenance:

  ```
  [PLUGIN CONFLICT] <file>:<line> — <brief description>
    • <plugin-A>: <verdict> — <one-sentence rationale>
    • <plugin-B>: <verdict> — <one-sentence rationale>
  ```

  Present via AskUserQuestion with options matching the conflict
  (skip / apply plugin-A fix / apply plugin-B fix / make rule).
  The developer's decision auto-triggers rule-capture so the same
  conflict type does not resurface in future sessions.

### Plugin output filtering — file-reference verification

Some plugins were authored against a specific reference repository
and recommend internal utility paths that do not exist in the
developer's project. These recommendations are false positives when
consumed as-is.

**Rule:** When plugin output recommends a specific project-internal
file path (e.g. "use `src/utils/execFileNoThrow.ts` instead of
`child_process.exec`"), Claude MUST verify the file exists in the
current project before acting on it. If the path does not resolve,
Claude drops the specific recommendation and falls back to the
plugin's generic guidance (or MCL's own equivalent) — e.g. the
abstract rule "avoid shell-enabled subprocess" stays; the pointer
to a non-existent utility is discarded.

**Motivating example:** `security-guidance`'s `child_process.exec`
pattern recommends `src/utils/execFileNoThrow.ts`, a utility that
exists only in the `anthropics/claude-code` repository. In every
other project this pointer is noise. The generic guidance (prefer
argv-form `execFile` over `exec` with shell interpolation) remains
valid and is what Claude acts on.

**Scope:** The rule is generic — it applies to any plugin output,
not just `security-guidance`. Resolution is filesystem-level
(`test -f` / `fs.existsSync` semantics from the project root);
module-path resolution (e.g. `@project/utils/foo` without a file
extension) is out of scope for this rule.

## Rule C — No MCP server calls

MCL does not invoke MCP-server plugins. If a plugin's source contains
`.mcp.json`, it is filtered out of the curated set and any future
candidate evaluation.

**Why:** Developer commitment — "context7 bir MCP server. MCL, MCP
server çağırmasın." MCP servers route data through third-party
endpoints; some phone home project metadata or full file content
during tool use. MCL's privacy invariant — "MCL projelerinde bilgi
dışarı gitmemeli" — cannot be verified plugin-by-plugin at runtime.
Excluding MCP wholesale is the only auditable rule.

**How to apply:**

- Before adding any plugin to the curated set, inspect its source for
  `.mcp.json`. Present → rejected.
- Binary CLI tools invoked via `Bash` (e.g., `semgrep` in Spec-1, any
  future linter, formatter, or compiler) are **not** MCP and are
  allowed. The binary runs locally; no MCP transport is involved.
- The one permissible network call pattern is downloading static
  resources (e.g., Semgrep rule packs from `registry.semgrep.dev`) with
  no project-derived payload. Per-plugin network endpoints must be
  auditable; see each plugin's own spec for the allowlist.

## Phase dispatch map

Alignment points between plugin sub-agents and MCL phases.

| MCL phase                    | Plugins dispatched (when applicable)                                                                                            |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Aşama 1 (gather)             | `feature-dev/code-explorer` (if classifier=feature) — findings feed MCL's Aşama 1 question pool                                 |
| Aşama 4 (spec)               | No plugin dispatch — MCL-native                                                                                                  |
| Aşama 4 (verify)             | No plugin dispatch — MCL-native                                                                                                  |
| Aşama 7 (execute)            | `feature-dev/code-architect` (if classifier=feature) — architecture options localized + presented alongside MCL's own analysis; `security-guidance` (PreToolUse hook) |
| Aşama 8 (risk review)      | `feature-dev/code-reviewer`; `code-review` 4-agent suite; `pr-review-toolkit` selective agents; Semgrep (Spec-1 SAST)             |
| Aşama 10 (impact analysis)  | No plugin dispatch — MCL-native                                                                                                  |
| Aşama 11 (verification)       | `feature-dev` FD-7 summary merged into MCL's Verification Report                                                                 |

## Request-type classifier (tier-B gate)

Before Aşama 1 questions, MCL classifies the developer's request
into one of: `feature`, `bug`, `refactor`, `question`, `ops`. This
is a one-shot LLM call with the developer's opening message; the
classification persists for the rest of the conversation unless
the developer pivots explicitly.

`feature-dev` is tier-B-gated: it dispatches only when classifier
returns `feature`. For `bug`, `refactor`, `question`, `ops`,
feature-dev's sub-agents do not fire — the request shape doesn't
benefit from its exploration/architecture scaffolding.

## Selective dispatch triggers — `pr-review-toolkit`

Four selective sub-agents fire on specific code-shape events emitted
during Aşama 7:

| Trigger                                      | Sub-agent dispatched    |
| -------------------------------------------- | ----------------------- |
| Aşama 7 output introduces a new type         | `type-design-analyzer`  |
| Aşama 7 output adds a `try`/`catch`          | `silent-failure-hunter` |
| Aşama 7 output adds a comment                | `comment-analyzer`      |
| Aşama 7 output writes a test                 | `pr-test-analyzer`      |

The trigger check runs once on Aşama 7 → Aşama 8 transition; the
fired sub-agents run in parallel; results merge per Rule B.

## Install-suggestion protocol

At the first developer message of a session in a project, MCL reads
`~/.claude/plugins/installed_plugins.json` and identifies curated
plugins that are absent. If any are missing, MCL emits a **single
consolidated block** in the developer's language — not a sequence of
per-plugin nags:

> *"MCL orkestrasyon seti için şu plugin'ler eksik:*
> *`/plugin install feature-dev@claude-plugins-official`*
> *`/plugin install code-review@claude-plugins-official`*
> *`/plugin install pr-review-toolkit@claude-plugins-official`*
> *`/plugin install security-guidance@claude-plugins-official`*
> *Kurmadan devam edebilirsin; o plugin'in faydalandığı adımlar atlanır."*

Decline for this session → persist session-scoped flag via
`mcl_state_set plugin_install_declined_in_session true`; MCL does
not re-ask in the same conversation.

No cross-conversation memory — the next session may re-ask if
plugins are still missing. Developer choice to skip is respected
per-session only.

## What MCL does NOT do

- Auto-install plugins. Even curated-required plugins require the
  developer's explicit `/plugin install` execution.
- Override a curated plugin's internal workflow, agent prompts, or
  phase structure. MCL consumes plugin output and merges it; the
  plugin runs as its authors designed it.
- Skip its own phases. MCL runs its 1 → 4.6 → 5 pipeline in full
  every session; plugin dispatch is additive, not replacement.
- Maintain a blocklist of MCP plugins. Rule C is evaluated per-plugin
  at curation time; runtime does not inspect plugin archives.

## Tier-2 survey outcome — `claude-plugins-official` walk (2026-04-21)

The full `claude-plugins-official` marketplace (145 plugins, the same
list Claude Code's `/plugin` Discover tab surfaces) was walked against
the tier-2 criteria: no `.mcp.json` (Rule C), natural alignment with
a single MCL phase, and no role overlap with the curated set unless
Rule B different-angle value is clear.

**Result: 0 additions to the curated set.** The pool partitioned as:

- **MCP-transported (Rule C):** `greptile` (contains `.mcp.json`),
  `semgrep` (source path `semgrep/mcp-marketplace`), and by strong
  SaaS-backed signal `sourcegraph`, `coderabbit`, `optibot`,
  `autofix-bot`. MCL already uses the `semgrep` CLI binary directly
  via `Bash`, which is Rule-C-compliant; the marketplace plugin
  wrapper is not needed.
- **Role overlap without Rule B justification:** `atomic-agents`,
  `ai-firstify`, `qodo-skills` — duplicate `code-review` / `feature-dev`
  territory with comparable angle and training surface.
- **Vertical / domain-specific:** `shopify*`, `ui5`, `aws-serverless`,
  `adlc`, `nightvision`, `frontend-design`, `playground`, `gopls-lsp`,
  and similar stack-scoped plugins. These do not align with a universal
  MCL phase and are already surfaced organically through
  `plugin-suggestions.md` at Aşama 1 entry when a matching stack is
  detected.
- **Meta / developer-invoked:** `skill-creator`, `claude-md-management`.
  Useful for developers maintaining MCL itself or their own `CLAUDE.md`,
  but not phase-aligned and not suitable for silent auto-dispatch.

The negative outcome is load-bearing: it is the reason the curated
set stays at five. Future candidates must either survive Rule C with
non-MCP transport or present a Rule B different-angle case against
this survey's partitioning.

## Out of scope

- Dynamic discovery of plugins beyond the curated list. MCL does not
  query the marketplace at runtime.
- `mcl-finish` mode — cross-session impact/risk aggregation and
  full-project final review. Tracked as Spec-2.
- Custom (developer-authored) plugins. MCL's curated set is
  authoritative; a developer's own plugins run via the
  `plugin-integration.md` slash-command path if invoked explicitly.

## Dispatch Audit (since 7.9.5)

Aşama 8 has a mandatory dispatch manifest — specific plugins that MUST
be dispatched before Aşama 10/5 can proceed. The audit is enforced by
`hooks/lib/mcl-dispatch-audit.sh`, called from `mcl-activate.sh` on every
turn where `phase_review_state=running`.

### Aşama 8 Manifest

| Dispatch type | Required plugin | Detection |
|---|---|---|
| Task sub-agent | `pr-review-toolkit:*` or `code-review:*` | `plugin_dispatched` event in `trace.log` after last `phase_review_pending` |
| Bash tool | semgrep scan | `semgrep_ran` event in `trace.log` after last `phase_review_pending` |

Semgrep is only required when the binary is available and the project stack
is supported. If `SEMGREP_NOTICE` is present in the current turn's context,
semgrep is skipped from the manifest automatically.

### Gap Handling

When any manifest entry is missing:
1. `PLUGIN_MISS_NOTICE` (`<mcl_audit name="plugin-dispatch-gap">`) is
   injected into `FULL_CONTEXT`.
2. `audit.log` records `plugin-dispatch-gap | mcl-activate.sh | missing=<list>`.
3. The `dispatch-audit` constraint in STATIC_CONTEXT blocks Aşama 10/5
   until the gap is resolved.
4. Once dispatched, the notice clears automatically on the next turn
   (no manual state clearing required).
