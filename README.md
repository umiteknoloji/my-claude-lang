# my-claude-lang (MCL) 10.0.0

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

MCL is a Claude Code plugin that grafts two wings onto every conversation: a **language bridge** that lets developers think in their own language while Claude produces senior-level English engineering output, and an **AI discipline** layer that drags every change through a deterministic 6-phase pipeline with hook-enforced gates for security, DB design, UI accessibility, and operational hygiene. It runs entirely outside your project — zero files written into your repo since 8.5.0. Rules are stack-agnostic: the same discipline applies to React, Python, Go, Rust, Java, Ruby, or any other stack.

---

## Quick install

```bash
git clone https://github.com/YZ-LLM/my-claude-lang.git
bash my-claude-lang/install.sh
```

This sets up:
- **Library:** `~/.mcl/lib/` (the cloned repo — single source of truth)
- **Wrapper launcher:** `~/.local/bin/mcl-claude` (symlink)
- **Per-project state root:** `~/.mcl/projects/<sha1(realpath)>/` (auto-created on first run)

Then in any project, run `mcl-claude` instead of `claude`:

```bash
cd ~/projects/my-app
mcl-claude
```

The wrapper computes a stable project key from `$PWD`'s realpath, scaffolds `~/.mcl/projects/<key>/` on first run, exports `MCL_STATE_DIR` for hooks, then `exec`'s `claude` with isolated `--settings` and `--plugin-dir`. **All Claude Code flags pass through transparently.** Your project gets nothing — no `.mcl/`, no `.claude/`, no settings file.

**Update:**
```bash
cd ~/.mcl/lib && git pull --ff-only && bash install.sh
```
Or type `/mcl-update` inside a session.

> **Upgrading from 9.x?** State is auto-migrated to schema v3 on the first activate after install. A backup is kept at `.mcl/state.json.backup.pre-v3`. No manual action required. See [CHANGELOG.md](CHANGELOG.md#1000) for details.

---

## Phase model

MCL 10.0.0 has six phases. Phase 2 (DESIGN_REVIEW) only runs for UI projects; for non-UI projects the flow goes Phase 1 → Phase 3 directly.

| Phase | Name | Responsibility | Approval gate |
|---|---|---|---|
| 1 | INTENT | Clarifying questions, precision audit, brief, `is_ui_project` detection | Summary-confirm askq |
| 2 | DESIGN_REVIEW | UI skeleton + dev server (UI projects only) | Design approval askq |
| 3 | IMPLEMENTATION | 📋 Spec emission + full code (TDD, scope guard) | None |
| 4 | RISK_GATE | Security, DB, UI/a11y, ops, perf, architectural drift, intent violation | Auto-block on HIGH |
| 5 | VERIFICATION | Test, lint, build, smoke report | None |
| 6 | FINAL_REVIEW | Audit-trail completeness, regression, promise-vs-delivery double-check | None |

### Flow

```
Phase 1 ──approve──▶ [Phase 2 if is_ui_project] ──approve──▶ Phase 3 ──▶ Phase 4 ──▶ Phase 5 ──▶ Phase 6
```

Severity tier across all gates: **HIGH** = `decision:deny` / `decision:block`; **MEDIUM** = sequential dialog item; **LOW** = audit-only.

### Approval gates

There are exactly two askq approval gates:
1. **Phase 1 summary-confirm** — the developer confirms the intent / constraints / success / context summary. This is the canonical scope contract. There is no separate spec-approval step.
2. **Phase 2 design approval** — UI projects only. After the clickable skeleton + dev server are running, MCL asks "Approve this design?" / "Tasarımı onaylıyor musun?". Approval sets `state.design_approved=true` and advances to Phase 3.

Approve and cancel tokens are matched strictly: only exact tokens (after lowercase + lead/trail whitespace+punct strip) qualify. `evet`, `Evet.`, `yes` are accepted; `evet, ama X de ekle` (carrying additional intent) and multi-word phrases are rejected — the developer's `but X` intent is preserved instead of being silently swallowed by an approve-fallback. From Phase 2 or Phase 3, typing a clean cancel token (`iptal`, `geri al`, `yanlış`, `vazgeç`, `cancel`, `undo`, `revert`, `abort`) rolls state back to Phase 1 (INTENT) and clears all Phase 2+ flags (`design_approved`, scan-done flags, etc.) — no `/mcl-restart` needed for in-flight rollback.

Phase 3's `📋 Spec:` block is **documentation** — it is the entry artifact for the implementation phase, populates `state.scope_paths` for the scope guard, and provides an English semantic bridge for non-English prompts. Format violations are advisory: the hook emits a `spec-format-warn` audit and continues; 3+ violations across turns trigger a Phase 6 LOW soft fail, never a Write block.

### `is_ui_project` detection

Phase 1 brief parser sets `state.is_ui_project` from three signals:
- Intent keywords (`UI`, `frontend`, `tasarım`, `mockup`, `design`, …)
- Stack tags from `mcl-stack-detect.sh` (react-frontend, vue-frontend, svelte-frontend, html-static, expo, …)
- Project file hints (`vite.config.*`, `next.config.*`, `tailwind.config.*`, `index.html` at root, …)

If signals are ambiguous, MCL defaults to `is_ui_project=true` (the cost of a skipped design review on a non-UI project is an extra confirmation; the cost of skipping it on a real UI project is a wrong-design implementation).

### Phase 4 risk gate

Phase 4 runs after every Phase 3 implementation step and before Phase 5. It aggregates findings across categories:

- **Security** — 3-tier scan (design dimensions, per-Edit incremental, START gate full scan); 13 generic core rules + 7 stack add-ons + Semgrep `p/default` + SCA dispatch. HIGH blocks Write.
- **DB design** — 10 generic + 8 ORM × 3 anchor = 34 rules; `squawk` + `alembic check` delegates.
- **UI / a11y** — 9 a11y-critical rules trigger HIGH; design tokens / reuse / responsive = MEDIUM dialog.
- **Ops** — 4 packs × 20 rules (deployment / monitoring / testing / docs).
- **Performance** — 3 packs × 11 rules (bundle / CWV / image), FE-only trigger.
- **Architectural drift** — `state.scope_paths` (from spec) vs actual Phase 3 writes. LOW if scope is empty (advisory), MEDIUM if writes touch a sibling layer, HIGH if they cross to a different layer (frontend → backend).
- **Intent violation** — `state.phase1_intent` negations (`no auth`, `no DB`, `frontend only`) matched against import paths and modified files. HIGH violations block Write.

Spec compliance is checked here too (each MUST/SHOULD vs the implementation), but format issues stay advisory.

### Phase 6 double-check

Three orthogonal checks run before the session can close:
- **(a) Audit trail completeness** — required STEP audit events emitted? (Catches silently skipped phases.)
- **(b) Final scan regression** — security + DB + UI scans re-run; new HIGH findings since the Phase 4 START baseline = block.
- **(c) Promise-vs-delivery** — Phase 1 confirmed parameters keyword-matched against modified files (reverse Lens-e traceability).

Skip impossible: state field `phase6_double_check_done` enforced via `decision:block`.

---

## Feature catalog

### Language bridge
Detects the developer's language from the first message, keeps every clarifying question, risk dialog, verification report, and section header in that language. Internal engineering output (specs, code, technical tokens) stays English. TR + EN supported. All section headers, audit messages, and skill prose are localized for these two languages only.

### Per-project isolation
MCL writes **zero files into your project**. State, hooks, skills, agents, audit logs, scan caches, dev-server logs — everything lives in `~/.mcl/projects/<key>/`. Per-project keys are SHA1 of `realpath($PWD)`, so renames lose state (intentional, no migration). Multiple projects work in parallel without state collision.

### Codebase scan — `/codebase-scan`
Scans the project once with 12 pattern extractors (P1–P12: stack detection, architecture markers, naming convention, error handling style, test pattern, API style, state management, DB layer, logging, lint strictness, build/deploy, README intent). Writes high-confidence findings to `project.md` between `<!-- mcl-auto -->` markers; medium/low confidence to `project-scan-report.md`.

### Pause-on-error — `/mcl-resume`
When a scan helper crashes, validator returns malformed JSON, audit log fails to write, hook script crashes, or external delegate fails non-gracefully, MCL **explicitly pauses** instead of silent fail-open: `state.paused_on_error.active=true`, every subsequent tool returns `decision:deny` with the error context. Resume with `/mcl-resume <your resolution>`.

### Interactive design loop — `/mcl-design-approve`, `/mcl-dev-server-start`, `/mcl-dev-server-stop`
During Phase 2 DESIGN_REVIEW, MCL auto-starts a dev server (10 stack detection: vite, next, cra, vue-cli, sveltekit, rails, django, flask, expo, static) in the background, allocates a port (default + 4 fallbacks), tracks PID in `$MCL_STATE_DIR/dev-server.pid`, and surfaces the URL via state. Build errors detected from `dev-server.log` trigger pause-on-error. Headless environments (`MCL_HEADLESS`, `CI`, Linux SSH no-DISPLAY) skip auto-start with manual instructions. The loop closes with `/mcl-design-approve` (sets `design_approved=true`, advances to Phase 3).

---

## Keyword reference

All keywords skip the normal MCL pipeline and run a dedicated mode. Type the keyword as the entire prompt.

| Keyword | Purpose |
|---|---|
| `/mcl-doctor` | Token & cost accounting report |
| `/mcl-update` | `git pull` MCL repo + re-install |
| `/mcl-restart` | Reset MCL state to Phase 1 within the same session |
| `/codebase-scan` | Run 12-pattern codebase scan |
| `/mcl-security-report` | Full backend security scan |
| `/mcl-db-report` | Full DB design scan |
| `/mcl-db-explain` | Run `EXPLAIN` on saved query files (requires `MCL_DB_URL`) |
| `/mcl-ui-report` | Full UI scan |
| `/mcl-ui-axe` | Runtime `axe-core` accessibility scan via Playwright (requires `MCL_UI_URL`) |
| `/mcl-resume <resolution>` | Clear `paused_on_error` state |
| `/mcl-phase6-report` | On-demand Phase 6 double-check report |
| `/mcl-design-approve` | Stop dev server, advance from Phase 2 to Phase 3 |
| `/mcl-dev-server-start` | Manually start the dev server |
| `/mcl-dev-server-stop` | Manually stop the dev server |
| `/mcl-ops-report` | Full operational discipline scan |
| `/mcl-perf-report` | Full performance scan |
| `/mcl-perf-lighthouse` | Runtime Core Web Vitals scan via Lighthouse |

---

## Example transcript (UI project)

```
dev:  Build a small task list app, React + Tailwind, no backend yet — just dummy data.

MCL Phase 1 — INTENT
  - Asks 2 GATE questions (auth model? persistence?)
  - Detects is_ui_project=true (intent + stack hints)
  - Summary askq: "Confirm this scope?" → dev approves → state.current_phase=2

MCL Phase 2 — DESIGN_REVIEW
  - Builds clickable skeleton (React + Tailwind, dummy data)
  - Auto-starts vite dev server on http://localhost:5173
  - askq: "Tasarımı onaylıyor musun?" → dev approves
    → state.design_approved=true, current_phase=3

MCL Phase 3 — IMPLEMENTATION
  - Emits 📋 Spec block (documentation; populates scope_paths)
  - TDD red-green-refactor over Acceptance Criteria
  - Pattern matching against project conventions

MCL Phase 4 — RISK_GATE
  - Security / DB / UI / ops / perf scans
  - Architectural drift: scope_paths vs writes
  - Intent violation: phase1_intent negations vs imports
  - HIGH findings block Write; MEDIUM → sequential dialog

MCL Phase 5 — VERIFICATION
  - Test + lint + build + smoke report
  - Spec coverage table (MUST/SHOULD vs tests)

MCL Phase 6 — FINAL_REVIEW
  - Audit-trail completeness check
  - Regression vs Phase 4 baseline
  - Promise-vs-delivery (Phase 1 params vs modified files)
```

For a non-UI project (e.g. a Go CLI), Phase 2 is skipped: Phase 1 → Phase 3 → Phase 4 → Phase 5 → Phase 6.

---

## Stack-agnostic discipline

MCL rules are not tied to any one ecosystem. Stack detection (`mcl-stack-detect.sh`) informs which add-on rule packs run; it never gates the core pipeline. The same TDD discipline, scope guard, risk gate, and verification report apply whether you are working on:

- **Frontend** — React, Vue, Svelte, plain HTML
- **Backend** — Python (FastAPI/Django), Java (Spring/Quarkus), C# (ASP.NET), Ruby (Rails/Sinatra), PHP (Laravel/Symfony), Go, Rust, Node.js
- **Mobile** — Swift, Kotlin
- **Systems / data** — C/C++, Lua, data pipelines (Airflow/dbt/Prefect/Dagster), ML inference

Detection informs add-on selection; it never gates the core pipeline.

---

## Known limitations

- **Project rename** loses state (path-SHA1 keying; intentional for setup-free).
- **Headless `/mcl-ui-axe`, `/mcl-perf-lighthouse`, and `/mcl-db-explain`** require explicit env vars (`MCL_UI_URL` for axe + Lighthouse, `MCL_DB_URL` for DB EXPLAIN); skip with localized advisory otherwise.
- **Bundle size** measured from existing build output only — `npm run build` is not invoked automatically.
- **External tool delegates** (Semgrep, squawk, hadolint, eslint-plugin-jsx-a11y, `axe-core`, Playwright, `pip-audit`, `cargo-audit`, `govulncheck`, `bundle-audit`) gracefully skip when binaries are missing.
- **TR + EN only.** Other languages are out of scope; if the developer writes in a third language MCL asks once whether to continue in Turkish or English.
- **N+1 detection is static-only**; runtime profiling deferred.

For full per-version detail, see [CHANGELOG.md](CHANGELOG.md).

---

## Repository

- Source: <https://github.com/YZ-LLM/my-claude-lang>
- Issues / discussion: GitHub Issues on the repo above
- License: [MIT](LICENSE)
