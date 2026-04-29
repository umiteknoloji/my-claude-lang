# my-claude-lang (MCL)

[![Version](https://img.shields.io/badge/version-8.13.0-blue.svg)](VERSION)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

MCL is a Claude Code plugin that grafts two wings onto every conversation: a **language bridge** that lets developers think in their own language while Claude produces senior-level English engineering output, and an **AI discipline** layer that drags every change through a deterministic phase pipeline (Phase 1 → 1.5 → 1.7 → 2 → 3 → 3.5 → 4 → 4.5 → 5 → 6) with hook-enforced gates for security, DB design, UI accessibility, and operational hygiene. It runs entirely outside your project — zero files written into your repo since 8.5.0.

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

---

## Feature catalog (8.13.0)

### Language bridge
Detects the developer's language from the first message, keeps every clarifying question, risk dialog, verification report, and section header in that language. Internal engineering output (specs, code, technical tokens) stays English. 14 languages supported (TR / EN / AR / DE / ES / FR / HE / HI / ID / JA / KO / PT / RU / ZH); TR + EN fully localized for tooling output, others fall back to English for tool reports.

### Per-project isolation (8.5.0+)
MCL writes **zero files into your project**. State, hooks, skills, agents, audit logs, scan caches, dev-server logs — everything lives in `~/.mcl/projects/<key>/`. Per-project keys are SHA1 of `realpath($PWD)`, so renames lose state (intentional, no migration). Multiple projects work in parallel without state collision.

### Codebase scan (8.6.0) — `/codebase-scan`
Scans the project once with 12 pattern extractors (P1–P12: stack detection, architecture markers, naming convention, error handling style, test pattern, API style, state management, DB layer, logging, lint strictness, build/deploy, README intent). Writes high-confidence findings to `project.md` between `<!-- mcl-auto -->` markers (Phase 5 sections preserved); medium/low to `project-scan-report.md`.

### Backend security — 3-tier (8.7.0 / 8.7.1) — `/mcl-security-report`
13 generic core rules + 7 stack add-ons (Django ALLOWED_HOSTS, FastAPI CORS, React unsafe HTML setter, Spring CSRF disabled, Rails strong params, Laravel debug, …) + Semgrep `p/default` integration + SCA tool dispatch (npm/pip/cargo/go/bundle audit). OWASP Top 10 + ASVS L1 subset. Severity-tiered: HIGH=`decision:deny` block, MEDIUM=Phase 4.5 sequential dialog, LOW=audit log.
- **L1 Phase 1.7** — 5 design-time dimensions (auth model, authz unit, CSRF stance, secret management, deserialization input)
- **L2 Phase 4 per-Edit** — incremental scan on Edit/Write/MultiEdit; `decision:deny` if HIGH
- **L3 Phase 4.5 START gate** — full scan; HIGH keeps state in `pending`, blocks Phase 4.5 dialog until fixed

### DB design discipline (8.8.0) — `/mcl-db-report`, `/mcl-db-explain`
10 generic core rules (missing PK, SELECT *, missing FK index, UPDATE/DELETE without WHERE, JSONB without validation, TIMESTAMP without timezone, text-id-not-UUID, enum-as-text, cascade-delete on user data, N+1 static heuristic) + 8 ORM add-ons × 3 anchor rules (Prisma, SQLAlchemy, Django ORM, ActiveRecord, Sequelize, TypeORM, GORM, Eloquent) = 34 rules. External delegates: `squawk` (Postgres migration linter) + `alembic check`. Optional `MCL_DB_URL` env enables `/mcl-db-explain` for live `EXPLAIN` plan analysis (no `ANALYZE` by default — production safety).

### UI enforcement (8.9.0) — `/mcl-ui-report`, `/mcl-ui-axe`
10 generic core HTML/a11y rules (img-no-alt, button-no-name, link-no-href, input-no-label, div-onClick-no-keyboard, heading-skip, hardcoded color/spacing/font-size, magic breakpoint) + 12 framework add-ons across React / Vue / Svelte / HTML-static = 22 rules. **Severity tuned for UI iteration tempo:** only a11y-critical findings (9 rules, e.g. img-no-alt, controlled-input-without-onChange, html-no-lang) trigger HIGH `decision:deny`; design tokens / reuse / responsive / naming = MEDIUM dialog; advisory = LOW audit. Design tokens detected hybrid: project's `tailwind.config` / CSS vars / `theme.ts` / `design-tokens.json`, falling back to MCL default 8px grid + Tailwind-ish scale. Optional `MCL_UI_URL` enables `/mcl-ui-axe` for live `axe-core` runtime scan via Playwright.

### Pause-on-error (8.10.0) — `/mcl-resume`
When a scan helper crashes, validator returns malformed JSON, audit log fails to write, hook script crashes, or external delegate fails non-gracefully, MCL **explicitly pauses** instead of silent fail-open: state.paused_on_error.active=true, every subsequent tool returns `decision:deny` with the error context, suggested fix, and last-known phase. Resume with `/mcl-resume <your resolution>` (free-form natural-language argument), or via skill-driven natural-language acknowledgment. Sticky across session boundaries — paused state survives Claude Code restarts. Build errors from the dev server (8.12.0) feed into the same channel.

### Phase 6 Double-check (8.11.0) — `/mcl-phase6-report`
After Phase 5 verification, three orthogonal checks run before the session can close:
- **(a) Audit trail completeness** — were all required STEP audit events emitted? (Catches silently skipped phases.)
- **(b) Final scan aggregation** — re-runs security + DB + UI scans; new HIGH findings since the Phase 4.5 START baseline = regression block.
- **(c) Promise-vs-delivery** — Phase 1 confirmed parameters (intent + constraints) keyword-matched against modified source files (reverse Lens-e traceability).

Skip impossible: state field `phase6_double_check_done` enforced via `decision:block`.

### Interactive design loop (8.12.0) — `/mcl-design-approve`, `/mcl-dev-server-start`, `/mcl-dev-server-stop`
After Phase 4a UI build, MCL auto-starts a dev server (10 stack detection: vite, next, cra, vue-cli, sveltekit, rails, django, flask, expo, static) in the background, allocates a port (default + 4 fallbacks), tracks PID in `$MCL_STATE_DIR/dev-server.pid`, and surfaces the URL via state. Build errors detected from `dev-server.log` (stack-specific regex map) trigger pause-on-error. Headless environments (`MCL_HEADLESS`, `CI`, Linux SSH no-DISPLAY) skip auto-start with manual instructions. Loop closes with `/mcl-design-approve` (sets `ui_reviewed=true`, advances to Phase 4c BACKEND).

### Operational discipline (8.13.0) — `/mcl-ops-report`
4 rule packs × 20 rules across deployment / monitoring / test coverage / documentation:
- **Deployment** (8): no-CI, workflow YAML errors, Dockerfile root user, `:latest` tag, no `HEALTHCHECK`, missing `.env.example`, env drift, undocumented secrets
- **Monitoring** (4): no structured logger (winston/pino/loguru/structlog), no `/metrics` endpoint, no error tracker (Sentry/Bugsnag/Rollbar), logger without level
- **Testing** (3): coverage below threshold (configurable: HIGH < 50%, MEDIUM < 70%), no test framework, changed file without test
- **Docs** (5): no README, no install section, no usage section, API surface without OpenAPI/Swagger, low function-level docstring coverage

Coverage delegated to vitest / jest / pytest / go-test / cargo-tarpaulin (binary missing → graceful skip). Configurable via `$MCL_STATE_DIR/ops-config.json`.

---

## Keyword reference

All keywords skip the normal MCL pipeline and run a dedicated mode. Type the keyword as the entire prompt.

| Keyword | Purpose |
|---|---|
| `/mcl-doctor` | Token & cost accounting report (per-turn injection overhead, session totals) |
| `/mcl-update` | `git pull` MCL repo + re-install (`bash install.sh`) |
| `/mcl-restart` | Reset MCL state to Phase 1 within the same session (preserves project) |
| `/codebase-scan` | Run 12-pattern codebase scan, write `project.md` + `project-scan-report.md` |
| `/mcl-security-report` | Full backend security scan (generic + stack + Semgrep + SCA), localized markdown |
| `/mcl-db-report` | Full DB design scan (generic + ORM + migration delegate), localized markdown |
| `/mcl-db-explain` | Run `EXPLAIN` on saved query files (requires `MCL_DB_URL` env) |
| `/mcl-ui-report` | Full UI scan (generic + framework + token + ESLint a11y delegate), localized markdown |
| `/mcl-ui-axe` | Runtime `axe-core` accessibility scan via Playwright (requires `MCL_UI_URL` env) |
| `/mcl-resume <resolution>` | Clear `paused_on_error` state with free-form resolution text |
| `/mcl-phase6-report` | On-demand Phase 6 double-check report (audit trail + regression + promise-delivery) |
| `/mcl-design-approve` | Stop dev server, advance from Phase 4b UI_REVIEW to Phase 4c BACKEND |
| `/mcl-dev-server-start` | Manually start the dev server (auto-detect stack) |
| `/mcl-dev-server-stop` | Manually stop the dev server (loop stays open) |
| `/mcl-ops-report` | Full operational discipline scan (deployment + monitoring + testing + docs) |

---

## Phase pipeline

Each developer message flows through this sequence. A phase doesn't advance without its required parameters.

```
Phase 1     Understanding             intent / constraints / success / context
Phase 1.5   Engineering Brief         translator + verb upgrade (vague → surgical English)
Phase 1.7   Precision Audit           7 core dims + stack add-ons + 5 security + 7 DB; SILENT-ASSUME / SKIP-MARK / GATE
Phase 2     Spec emission             📋 Spec block with MUST/SHOULD requirements
Phase 3     Verification + approval   developer reviews scope-changes callout, approves
Phase 3.5   Pattern matching          read project code, extract conventions
Phase 4     Code authoring (TDD)      4a BUILD_UI dummy data → 4b UI_REVIEW (dev server) → 4c BACKEND
Phase 4.5   Risk Review               sticky-pause → security gate → db gate → ui gate → ops gate → standard reminder
Phase 4.6   Impact analysis           track downstream effects of fixes
Phase 5     Verification report       spec coverage + manual-test surface + process trace + 5.5 localized
Phase 6     Double-check              audit trail + final scan regression + promise-vs-delivery
```

Severity tier across all gates: **HIGH** = `decision:deny` / `decision:block`; **MEDIUM** = sequential dialog item; **LOW** = audit-only.

---

## Known limitations

- **Project rename** loses state (path-SHA1 keying; intentional for setup-free).
- **Headless `/mcl-ui-axe` and `/mcl-db-explain`** require explicit env vars (`MCL_UI_URL`, `MCL_DB_URL`); skip with localized advisory otherwise.
- **External tool delegates** (Semgrep, squawk, hadolint, eslint-plugin-jsx-a11y, `axe-core`, `playwright`, `pip-audit`, `cargo-audit`, `govulncheck`, `bundle-audit`) gracefully skip when binaries are missing — install them for full coverage.
- **14 languages supported, but only TR + EN are fully localized for tool reports.** Others fall back to English for scan output (clarifying questions and risk dialog still respect the developer's language via skill prose).
- **N+1 detection is static-only**; runtime profiling (test-runner integration) deferred to 8.x.
- **Phase 5 `phase5-verify` audit event** is model-behavioral; older skill files don't emit it. Phase 6 (a) treats absence as LOW soft fail with transcript fallback (`Verification Report` / `Doğrulama Raporu` string match).
- **L2 ops scan** (per-Edit Dockerfile / workflow / README block) deferred to 8.13.x; 8.13.0 has L3 + manual `/mcl-ops-report` only.
- **Cloud DB** (BigQuery / Snowflake / DynamoDB) detected at the stack-tag level; dialect-specific rule packs deferred to 8.8.x.

For full per-version detail, see [CHANGELOG.md](CHANGELOG.md).

---

## Repository

- Source: <https://github.com/YZ-LLM/my-claude-lang>
- Issues / discussion: GitHub Issues on the repo above
- License: [MIT](LICENSE)
