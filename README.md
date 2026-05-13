# MyCL — my-claude-lang 1.0.45

A semantic-verification layer on top of Claude Code. MyCL imposes a
22-phase development pipeline, ratchets discipline through audit
chains, and refuses to fail open. **Opt-in per session** via `/mycl`
(1.0.5+) — silent until you ask for it. Pure Python 3.8+, no AI
agent frameworks, no MCP servers.

> Türkçe sürüm: [README.tr.md](README.tr.md)

## What MyCL is (and isn't)

MyCL **is** six Python hooks (`UserPromptSubmit`, `PreToolUse`,
`PostToolUse`, `Stop`, `SubagentStop`, `PreCompact`) that, **once
activated with `/mycl`**:

- Track the active phase in `.mycl/state.json`
- Seal each phase with an audit entry in `.mycl/audit.log`
- Enforce per-phase tool allowlists (`gate_spec.json`) — fail-closed
- Detect spec blocks line-anchored, hash them, and gate downstream
  tools on developer approval
- Inject phase-specific context (`<mycl_active_phase_directive>`,
  `<mycl_phase_status>`, `<mycl_phase_allowlist_escalate>`) every turn
- Speak TR + EN bilingually (no labels, blank-line separated)

**Before activation** (default state for any new session): all six
hooks no-op — banner, deny, audit, snapshot — nothing fires. Claude
Code behaves exactly as without MyCL installed.

MyCL **is not**:

- An AI agent framework (we don't reinvent Claude Code)
- LangGraph or any state-machine library (the 22 phases are *data*
  in `gate_spec.json`)
- An MCP server (Plugin Rule C filters out any plugin with
  `.mcp.json`)

## Quick install

```bash
git clone https://github.com/YZ-LLM/my-claude-lang.git
cd my-claude-lang
bash setup.sh
```

The installer:
1. Verifies Python 3.8+
2. Copies the repo to `~/.claude/mycl/`
3. Registers `mycl.md` skill in `~/.claude/skills/`
4. Drops data files into `~/.claude/data/`
5. Merges 6 hooks into `~/.claude/settings.json` (idempotent — safe
   to re-run)
6. Smoke-tests `py_compile` + lib imports

## Activation (1.0.5+)

MyCL is **opt-in per Claude Code session**. After installation:

```
> /mycl                  # bare activation — MyCL now runs the pipeline
> /mycl todo app yap     # activation + first intent in one prompt
```

Once `/mycl` is detected on any prompt, the active session ID is
written to `.mycl/active_session.txt` and MyCL stays on for the rest
of that session. Closing Claude Code starts a fresh session ID, so the
next time you open it, MyCL is silent again until you type `/mycl`.

The `/mycl` token is stripped from the prompt before the model sees
the user's actual message; the model receives an `<mycl_activation_note>`
that quotes the stripped message so it knows what the user asked.

**Why opt-in?** Many sessions don't need the 22-phase pipeline (quick
edits, exploration, scripts). MyCL only kicks in when you explicitly
ask for it.

## The 22 phases

| # | Phase | What it does |
|---|---|---|
| 1 | Intent Gathering | Clarify what the developer wants — one question per turn, summary + askq approval |
| 2 | Precision Audit | Validate intent across 7 dimensions (auth, failure modes, scope, PII, observability, SLA, idempotency) |
| 3 | Engineering Brief | Translate intent to engineering English — silent phase |
| 4 | Spec + Approval | Write 📋 Spec block (Objective/MUST/SHOULD/AC/Edge/Technical/OOS) + askq approval |
| 5 | Pattern Matching | Learn naming/error/test patterns from existing code (greenfield → skip) |
| 6 | UI Build | Frontend with mock data, dev server + browser auto-open (no UI → skip) |
| 7 | UI Review | Deferred — free-form intent classify (approve/revise/cancel/sen-de-bak) |
| 8 | Database Design | 3NF schema, covering indexes, reversible migrations (no DB → skip) |
| 9 | TDD Execution | RED → GREEN → REFACTOR per AC; final test suite green |
| 10 | Risk Review | 4-lens parallel scan (review/simplify/perf/security) + unbounded askq |
| 11 | Code Review | Auto-fix correctness/logic/error-handling/dead-code |
| 12 | Simplification | Remove premature abstractions, duplicates, unnecessary patterns |
| 13 | Performance | Auto-fix N+1, blocking I/O, memory leaks, allocation churn |
| 14 | Security (project-wide) | semgrep + npm/pip/cargo audit + secret scanner |
| 15 | Unit Tests | Code-coverage tests beyond Phase 9's AC tests |
| 16 | Integration Tests | Real cross-module flows (testcontainers, in-memory DB) |
| 17 | E2E Tests | Playwright headless (no UI → skip) |
| 18 | Load Tests | k6/locust against spec NFRs (no NFR → skip) |
| 19 | Impact Review | Downstream effects (importers, contracts, schema, cache) |
| 20 | Verification + Mock Cleanup | Spec coverage table + automation barriers + process trace |
| 21 | Localized Report | Translate Phase 20 to user's language (skippable) |
| 22 | Completeness Audit | Hook-written audit; surfaces uncovered MUSTs |

For each phase, see `skills/mycl/asama<NN>-*.md`.

## Architecture

```
USER  ←→  MyCL (semantic verification)  ←→  CLAUDE CODE (model + tools)
              │
              ├─ 4 hooks (Python files Claude Code invokes)
              ├─ state.json (current_phase, spec_approved, ...)
              ├─ audit.log (append-only event log)
              ├─ 22 phases as data (gate_spec.json)
              └─ skill files for each phase
```

Hooks communicate **indirectly** via `state.json` and `audit.log` —
they don't import each other. The four hooks each import from
`hooks/lib/*` (state, audit, gate, askq, spec_detect, transcript,
bilingual, dsi, plugin, …).

## Plugin Rules

- **Rule A** — local `.git/` is required. First activation asks once
  whether MyCL may run `git init` (no remote, no push, no
  auto-commit); decision persists in `.mycl/config.json`.
- **Rule B** — curated plugins dispatch silently and merge findings
  by `(file, line, rule-equivalent)` dedup. Plugin disagreement →
  Phase-10 risk item.
- **Rule C** — any plugin with `.mcp.json` is filtered out at
  curation time. Binary CLI tools via `Bash` (semgrep, linters,
  compilers) are NOT MCP and allowed.

## Bilingual output

All hook messages, askq prompts, manifesto framings, and phase-end
notifications come in two blocks:

```
[Türkçe blok — kullanıcı için]

[English block — model's working language]
```

Blank-line separated, no labels. File paths, audit names, CLI
commands, and code identifiers are never translated.

## STRICT mode (no fail-open)

When data is insufficient or uncertain, MyCL **denies** rather than
opens a default-allow path. After 5 consecutive denies of the same
kind, an `*-escalation-needed` audit is written; the block remains
in place until developer intervention. There is no auto-tiebreak,
no "let it pass after N strikes," no graceful degradation.

## Testing

```bash
python3 -m pytest tests/ -v
```

808 tests cover lib units (every module), each hook (subprocess
chain), and a smoke matrix that exercises pseudocode invariants
(state × tool, STRICT no-fail-open, state lock, completeness loop,
DSI integration, PreCompact snapshot, reinforcement reminder,
Agent tool globally allowed, stale-emit silence).

## Coexistence with Anthropic Official Plugins

MyCL is designed to **coexist** with Anthropic's curated plugin
directory (`anthropics/claude-plugins-official`). Selected official
plugins that complement MyCL's 22-phase pipeline:

- **`security-guidance`** — `PreToolUse` hook on Edit/Write/MultiEdit;
  augments MyCL Phase 14 with inline pattern warnings. No conflict —
  runs alongside MyCL's `pre_tool.py`.
- **`anthropics/claude-code-security-review`** (separate repo) —
  manual `/code-review` for PR-based deep security audit; use after
  Phase 14 scan for repository-wide review.
- **`code-review`** / **`code-simplifier`** — manual slash commands;
  optional developer-initiated second-pass for Phases 11 & 12.
- **`session-report`** — manual `/session-report` for token / cache
  statistics. **Complements (does not replace)** MyCL Phase 22
  completeness audit (different scope: statistics vs MUST coverage).

### ⚠️ Hook collision warning

The `hookify` plugin (community) registers on **4 events**
(UserPromptSubmit, PreToolUse, PostToolUse, Stop) — it will collide
with MyCL's hook chain and may interrupt phase transitions. **Do not
install `hookify` alongside MyCL.** For rule-based action prevention,
add MyCL captured-rules in `CLAUDE.md` instead.

## Inspiration & Community References

MyCL stands on the shoulders of mature Claude Code community projects:

- **[Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec)** —
  spec-driven development framework; MyCL Phase 4 spec block format
  conceptually compatible.
- **[obra/superpowers](https://github.com/obra/superpowers)** — TDD
  methodology + spec-first workflow; reference for MyCL Phase 9 TDD
  cycle structure.
- **[Playwright agents](https://github.com/topics/playwright-agent)** —
  E2E test orchestration patterns for MyCL Phase 17.
- **[komunite/kalfa](https://github.com/komunite/kalfa)** — Turkish
  Claude Code OS (10 agents, 22 commands, 993 skills); inspiration
  for MyCL's Turkish intent layer + Phase 21 localized report.
- **[Anthropic Issue #53223](https://github.com/anthropics/claude-code/issues/53223)** —
  official acknowledgment that "CLAUDE.md instruction compliance is
  architecturally unenforced"; MyCL's per-phase PreToolUse enforcement
  + PreCompact reminder = direct implementation of Anthropic's
  recommended deterministic counter-measure.

## Disabling

Remove the `mycl`-prefixed entries from `~/.claude/settings.json`'s
`hooks` array. The MyCL state files (`.mycl/`) live per-project and
can be deleted independently.

## License

MIT — see `LICENSE`.
