# MyCL — my-claude-lang 1.0.0

A semantic-verification layer on top of Claude Code. MyCL imposes a
22-phase development pipeline, ratchets discipline through audit
chains, and refuses to fail open. Pure Python 3.8+, no AI agent
frameworks, no MCP servers.

> Türkçe sürüm: [README.tr.md](README.tr.md)

## What MyCL is (and isn't)

MyCL **is** four Python hooks (`UserPromptSubmit`, `PreToolUse`,
`PostToolUse`, `Stop`) that:

- Track the active phase in `.mycl/state.json`
- Seal each phase with an audit entry in `.mycl/audit.log`
- Enforce per-phase tool allowlists (`gate_spec.json`) — fail-closed
- Detect spec blocks line-anchored, hash them, and gate downstream
  tools on developer approval
- Inject phase-specific context (`<mycl_active_phase_directive>`,
  `<mycl_phase_status>`, `<mycl_phase_allowlist_escalate>`) every turn
- Speak TR + EN bilingually (no labels, blank-line separated)

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
5. Merges 4 hooks into `~/.claude/settings.json` (idempotent — safe
   to re-run)
6. Smoke-tests `py_compile` + lib imports

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

521 tests cover lib units (every module), each hook (subprocess
chain), and a smoke matrix that exercises pseudocode invariants
(state × tool, STRICT no-fail-open, state lock, completeness loop,
DSI integration).

## Disabling

Remove the `mycl`-prefixed entries from `~/.claude/settings.json`'s
`hooks` array. The MyCL state files (`.mycl/`) live per-project and
can be deleted independently.

## License

MIT — see `LICENSE`.
