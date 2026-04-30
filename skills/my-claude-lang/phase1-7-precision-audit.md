<mcl_phase name="phase1-7-precision-audit">

# Phase 1.7: Precision Audit

Called automatically after Phase 1 AskUserQuestion returns an approve-family
tool_result, before Phase 1.5 (Engineering Brief).

## Scope and Extensibility

The 7 **core dimensions** below are universal — they apply to every project
regardless of stack. The **stack add-on list is illustrative, not exhaustive**.
MCL is a universal tool; the named sections (TypeScript, Python, Go, Rust,
Swift, Kotlin, etc.) are common-case examples that cover frequent stacks but
do not enumerate every possible domain. When a new stack tag is added to
`hooks/lib/mcl-stack-detect.sh`, a new section is appended to this file with
the corresponding delta dimensions — no logic change required, the
classification engine is purely data-driven over the markdown sections.

The core layer stays fixed; the stack add-on layer grows as MCL's stack
coverage grows.

## Purpose

Phase 1 ensures the developer's parameters are **complete** (all fields gathered).
Phase 1.7 ensures they are **precise** (each dimension classified — silent default,
explicit no-default, or asked).

A senior English-speaking engineer does not ship a spec where dimensions like
permission model, idempotency, or PII handling are silently absent. Phase 1.7
walks a fixed checklist of dimensions and forces an explicit decision for each
one. The output is a precision-enriched parameter set that Phase 1.5 translates
to English and Phase 2 expands into the spec body.

## When Phase 1.7 Runs

After the Phase 1 summary `AskUserQuestion` tool_result returns approve-family.
Before Phase 1.5 brief generation. Skipped silently when the developer's
detected language is English — the behavioral prior of a Claude session in
English already biases toward precision; running 1.7 would be redundant and
add latency.

The audit entry is emitted in **both** the run and the skipped case so the
detection control can confirm the phase was evaluated.

## Three Classifications (per dimension)

For each dimension on the checklist, classify the developer's input as one of:

### SILENT-ASSUME
Industry default exists, the choice is reversible, and proceeding with the
default carries near-zero implementation cost. Mark in the spec as
`[assumed: X]` so Phase 3 review can correct if wrong.

### SKIP-MARK (since 8.3.0)
Dimension applies but **no industry-default assumption is safe**. Recording
silence as a default would be wrong — instead, mark explicitly that the
dimension is unspecified. Phase 4.5 risk review can lens these markers and
surface them as risks if the dimension turns out to matter at execution time.
Spec marker: `[unspecified: <reason>]` (e.g., `[unspecified: no SLA stated]`).

Currently used by: **Performance SLA** (dimension 6). Other dimensions either
have safe industry defaults (SILENT-ASSUME) or have architectural impact that
mandates a question (GATE).

### GATE
Architectural impact, irreversible without rework, or developer's input
contains explicit signal that the answer matters (e.g., they used the word
"fast", "scale", "secure"). Ask the developer to confirm.

## GATE Batching (since 8.16.0)

When multiple GATE dimensions in the same **category** fire in a single
Phase 1.7 evaluation, batch them into ONE `AskUserQuestion` call with
`multiSelect: true` instead of asking each dimension in its own turn.
This caps Phase 1.7 turn count at the number of categories (≤ 5)
regardless of how many dimensions fire.

### Categories

| Category | Dimensions covered |
|---|---|
| Security | Permission/Access (1), AuthN/AuthZ (8), Authorization-per-Object (9), CSRF/Session (10), Secrets/Config (11), Untrusted Deserialization (12) |
| Database | Storage Choice (13), Schema Ownership (14), Migration Policy (15), Index Strategy (16), Identifier Strategy (17), Tenant Isolation (18), Connection Pooling (19) |
| UI | every UI stack add-on dimension (a11y, responsive, state mgmt, form validation, …) |
| Operations | Deployment Strategy (20), Observability Tier (21), Test Policy (22), Documentation Level (23) |
| Performance | Performance Budget (24) — single-dimension category, no batching needed |

Single-dimension fires within a category still use the single-question
form. Batching only applies when ≥ 2 dimensions in the same category
fire in the same Phase 1.7 evaluation.

### Batched question shape

One `AskUserQuestion` per category with all firing dimensions as
options, `multiSelect: true`. Each option label names the dimension
plus its decision space ("Deployment: Docker / Procfile / serverless /
skip"). Developer selects one option per dimension in a single turn.

### Reverse path (model-behavioral, until 8.17.0)

If the developer pushes back in the next turn ("ops için TST'yi yanlış
seçtim, tekrar sor"), the model SHOULD discard the batched answer for
the named dimension and re-ask it as a single question. There is no
hook-level rollback — this is a model-behavioral workaround until
8.17.0 introduces a structured batch-revise feature. Skill prose: when
developer feedback explicitly names a batched dimension and contradicts
the prior selection, treat it as a re-ask trigger.

## Core Dimensions (always apply, every project)

### 1. Permission / Access Model
- **SILENT-ASSUME default:** project has no auth surface → `[assumed: no auth required]`. Project has existing auth → `[assumed: matches existing role conventions]`.
- **GATE triggers:** feature surfaces user-specific data, includes admin-only or role-conditional behavior, or modifies multi-user state.
- **Sample question (TR):** "Bu özelliğe kim erişebilir — herkes mi, sadece admin mi, yoksa role-bazlı mı?"
- **Sample question (EN):** "Who can access this — everyone, admin-only, or role-based?"

### 2. Failure Modes (algorithmic / non-UI)
Algorithmic and integration failure handling: empty input, network/dependency error, partial result, stale cached state. **UI rendering states (empty/loading/error views) are NOT in this dimension** — they live in UI stack add-ons.
- **SILENT-ASSUME default:** error → log + return error/code; empty input → no-op or 400.
- **GATE triggers:** degraded behavior is ambiguous, dependency outage handling is business-critical, partial-result semantics differ across modules.
- **Sample question (TR):** "Backend dependency [X] erişilemezse — cached değer mi dönmeli, yoksa 503 mi?"

### 3. Out-of-Scope Boundaries
What this task explicitly does NOT include.
- **SILENT-ASSUME default:** auto-derive from confirmed parameters (anything not mentioned is out of scope).
- **GATE triggers:** request contains hidden sub-tasks (existing Phase 1 pattern) or analogy-based scope ("X gibi yap"); explicit confirmation needed on what is excluded.
- **Sample question (TR):** "[X], [Y], [Z] bu task'in dışında — ayrı ticket'lar olarak mı işlenecek?"

### 4. Data Privacy / PII Handling
Which fields are persisted, logged, or shown to which audience.
- **SILENT-ASSUME default:** no PII fields touched → `[assumed: no PII handling required]`. Standard project convention exists → `[assumed: matches existing redaction policy]`.
- **GATE triggers:** feature touches email, phone, address, payment, government IDs, health info, or any persisted user-specific data.
- **Sample question (TR):** "Bu veride [PII alan adı] var — kim görür, log'larda redact mi olmalı?"

### 5. Audit / Observability
What events emit log entries, what actions require audit trail, what metrics to track.
- **SILENT-ASSUME default:** critical writes log at INFO level; reads are not logged.
- **GATE triggers:** security-sensitive operations (auth changes, permission grants, data exports), regulated paths (GDPR/HIPAA/PCI), feature flag rollouts.
- **Sample question (TR):** "Bu operasyon audit trail gerektiriyor mu — kim, ne zaman, ne yaptı kayıt altına alınmalı mı?"

### 6. Performance SLA — **SKIP-MARK by default**
p95/p99 latency, throughput target, resource budget.
- **SKIP-MARK default:** no SLA stated → `[unspecified: no SLA stated]`. **Do NOT assume an industry default** — performance defaults vary too widely across stacks and contexts to be safely silent.
- **GATE triggers:** developer used the word "fast", "scale", "high traffic", "low latency", or implied volume ("X requests per second", "Y users", "millions of records") in Phase 1.
- **Sample question (TR):** "'Hızlı' dedin — concrete bir target var mı (örn. p95 < 200ms, throughput 1k req/s)?"

### 7. Idempotency / Retry
Operation invoked twice → same observable result?
- **SILENT-ASSUME default:** read operations are idempotent (`[assumed: idempotent read]`). Pure-compute operations idempotent.
- **GATE triggers:** write operations, payment / external side-effect calls, message publishing, file system mutation.
- **Sample question (TR):** "Bu write operasyonu retry edilirse iki kayıt mı oluşur — idempotency key kullanılacak mı?"

## Security Dimensions (since 8.7.0, design-time)

These five dimensions cover the design-time half of MCL's 3-tier backend security: decisions made BEFORE code is written. Each follows the SILENT-ASSUME / SKIP-MARK / GATE classification of the core seven. They surface what runtime SAST cannot: authorization model, secret strategy, threat-model stance.

### 8. Auth Model (OWASP A07)
Who can call this endpoint / module / write path? What identity is presented and how is it verified?
- **SILENT-ASSUME default:** existing project auth applies (e.g. session middleware already wired). Mark `[assumed: existing auth middleware]`.
- **GATE triggers:** new public endpoint surface, new identity provider integration, multi-tenant isolation, B2B/admin distinction, anonymous-vs-authenticated branch in business logic.
- **Sample question (TR):** "Bu endpoint'i kim çağırabilir — anonim, oturum açık, admin? Mevcut auth middleware aynen mi uygulansın?"

### 9. Authz Unit / Resource-Owner Check (OWASP A01)
For each resource access: which actor owns / can access this specific record? BOLA/IDOR is the most common production breach and SAST cannot detect it semantically.
- **SILENT-ASSUME default:** none — authorization SHOULD be explicit per-resource. Default is `[unspecified: authz unit]` and Phase 4.5 lens (d) re-checks.
- **GATE triggers:** any resource fetched / mutated by ID. Always ask: "Does the actor have a relationship to this resource ID?"
- **Sample question (TR):** "GET /users/:id — bu ID herhangi biri olabilir. Owner check uygulansın mı (sadece kendi kaydı), admin bypass var mı?"

### 10. CSRF Stance (OWASP A01 / A05)
For state-changing endpoints with cookie-based session: is CSRF protection on, off, or stateless (token / SameSite=strict)?
- **SILENT-ASSUME default:** REST APIs with bearer tokens have no CSRF surface; stateless token auth → `[assumed: no CSRF surface, bearer-only]`. Cookie-session apps assume framework default (Django CSRF middleware, Rails authenticity_token).
- **GATE triggers:** mixed cookie + token auth, custom CSRF flow, framework default disabled, public form-post endpoints.
- **Sample question (TR):** "State-changing endpoint cookie auth kullanıyor — CSRF token (framework default) mu, SameSite=strict mi, exempt mi?"

### 11. Secret Management Strategy (OWASP A02)
Where do credentials live? Repo (forbidden), env var (acceptable), secret manager (best)?
- **SILENT-ASSUME default:** environment variables loaded via `.env` (not committed) or runtime config. `[assumed: env-var, .env in .gitignore]`.
- **GATE triggers:** dev needs to write/read a credential at runtime, rotation policy required, multi-environment promotion (dev/staging/prod), 3rd-party SDK with API key.
- **Sample question (TR):** "API key nereden gelecek? `.env` (gitignore'da) yeterli mi, yoksa runtime secret manager (Vault, AWS Secrets, GCP Secret Manager) gerek mi?"

### 12. Deserialization Input Source (OWASP A08)
Will the code parse externally-controlled serialized data? Untrusted deserialization is RCE-equivalent.
- **SILENT-ASSUME default:** JSON-only ingress with schema validation (Pydantic, Zod, Joi) → `[assumed: JSON + schema]`. No SILENT for binary formats.
- **GATE triggers:** YAML / Python-pickle-format / Marshal / Java serialization of any external input; webhooks ingesting opaque payload; file upload that may contain serialized object.
- **SKIP-MARK alternative:** if the input source is genuinely undecided, mark `[unspecified: deser-source]` and Phase 4.5 lens (d) blocks until explicit source confirmed.
- **Sample question (TR):** "Bu endpoint dış kaynaktan ne format alıyor — JSON+schema mı, YAML/binary-serialization mı? İkincisi attack surface."

## DB Design Dimensions (since 8.8.0, design-time)

These seven dimensions cover the design-time half of MCL's 3-tier DB design discipline. **Apply only when at least one `db-*` stack tag is detected by `mcl-stack-detect.sh`.** FE-only / lib / CLI projects skip this entire section. SILENT-ASSUME / SKIP-MARK / GATE classification.

### 13. Persistence Model
RDBMS / document store / hybrid?
- **SILENT-ASSUME default:** existing project DB is the persistence model (Postgres/MySQL/SQLite/Mongo/Redis as detected). `[assumed: <detected dialect>]`.
- **GATE triggers:** explicit "save" / "store" / "persist" verbi + mevcut stack çakışıyor (ör. RDBMS + key-value cache karışımı), yeni service ile schema önemli.
- **Sample question (TR):** "Bu veriyi RDBMS'te mi saklayacağız (relational queries var), yoksa document store mu (nested objects yoğun)?"

### 14. Schema Ownership
This service tek sahip mi, shared schema mı (multi-service repo)?
- **SILENT-ASSUME default:** single-service / monorepo'da explicit boundary. `[assumed: this service owns the schema]`.
- **GATE triggers:** multi-service repo, migration commit conflict riski, `db-*` tag birden fazla service'te aktif.
- **Sample question (TR):** "Bu şemaya başka bir service de yazıyor mu? Migration ownership netleştir."

### 15. Migration Policy
Zero-downtime / expand-contract / direct?
- **SILENT-ASSUME default:** dev/staging için direct OK. `[assumed: direct migration, dev-only]`.
- **GATE triggers:** prod data var; ALTER TABLE on >100k rows; sıfır kabul edilemez kesinti.
- **Sample question (TR):** "Bu migration'ın prod'da downtime'ı kabul mü, yoksa expand-contract / online-DDL gerekli mi?"

### 16. Index Strategy Upfront
Composite / partial / expression / covering index ihtiyacı tasarımda düşünüldü mü?
- **SILENT-ASSUME default:** PK + FK index'ler yeterli (read-light path). `[assumed: PK + FK indexes only]`.
- **GATE triggers:** read-heavy query path; ORDER BY + LIMIT pattern; range query; full-text search; multi-column WHERE.
- **Sample question (TR):** "Bu sorgu hangi sütunları filtreliyor — composite index gerekli mi (ve hangi sıra)?"

### 17. ID Generation Strategy
Auto-increment / UUID v4 / UUID v7 / ULID / snowflake?
- **SILENT-ASSUME default:** existing project convention (`[assumed: <detected>]`); yoksa auto-increment INT.
- **GATE triggers:** distributed insert (multi-region / sharded); sortable ID need; ID expose ediliyor (security: enumerable IDs).
- **Sample question (TR):** "ID auto-increment INT mi, UUID v4 mi (random), UUID v7 / ULID mı (sortable)?"

### 18. Multi-Tenancy
Schema-per-tenant / row-level (tenant_id column) / none?
- **SILENT-ASSUME default:** single-tenant. `[assumed: no multi-tenancy]`.
- **GATE triggers:** tenant isolation gereği; "her müşteri kendi verisini görür"; B2B SaaS pattern.
- **Sample question (TR):** "Multi-tenant mı? Hangisi: schema-per-tenant (operasyonel maliyet), row-level + tenant_id (default), database-per-tenant (en izole)?"

### 19. Connection Pooling
Pool size + saturation behavior?
- **SILENT-ASSUME default:** ORM / framework default pool size (SQLAlchemy 5, Sequelize 5, Django CONN_MAX_AGE off). `[assumed: framework default]`.
- **GATE triggers:** high-concurrency (req/s > 100); serverless cold start; custom load balancer; connection limit'e yakın observed.
- **Sample question (TR):** "Concurrent request beklentin nedir? Pool size ne, saturation'da queue mu fail mı?"

## Operations Dimensions (since 8.15.0, design-time)

Four ops dimensions and one perf dimension, applied per their trigger
conditions. They feed `phase1_ops` and `phase1_perf` state objects which
are read by Phase 4.5 ops/perf gates and Phase 6 (a) audit-trail check.

### 20. Deployment Strategy (DEP)
How does this code reach production? CI/CD / manual approval / Docker / serverless / static-deploy?
- **Trigger:** `Dockerfile` OR `.github/workflows/` OR `Procfile` OR `fly.toml` OR `vercel.json` OR `netlify.toml` OR `app.yaml` OR `Jenkinsfile` exists.
- **SILENT-ASSUME default:** existing CI pipeline auto-detected. `[assumed: <detected>]`.
- **GATE triggers:** new public-facing service; zero-downtime mandatory; multi-environment (dev/staging/prod) promotion.
- **Sample question (TR):** "Deploy nasıl olacak — Docker container, serverless (Lambda/Cloud Run), VPS, yoksa managed PaaS (Heroku/Fly/Render)?"

### 21. Observability Tier (MON)
Logging + metrics + alerting requirements?
- **Trigger:** backend stack-tag (`python|java|csharp|ruby|php|go|rust` or node-backend non-FE-only).
- **SILENT-ASSUME default:** prototype/internal → "basic" (logger only); production-bound → "full" (structured logger + metrics + error tracker).
- **GATE triggers:** SLA / uptime hedefi; multi-tenant; incident response zorunluluğu.
- **Sample question (TR):** "Production gözlemlemesi: console-only mı yeterli, yoksa structured logger + metrics + Sentry mi gerek?"

### 22. Test Policy (TST)
TDD strict / pragmatic / prototype-no-tests?
- **Trigger:** test framework manifest (vitest/jest/pytest/rspec/junit/go-test/cargo).
- **SILENT-ASSUME default:** "pragmatic" (Phase 5 Spec Coverage zorunlu, threshold opsiyonel).
- **GATE triggers:** "prototype" / "MVP" keyword in Phase 1; explicit confirmation needed.
- **Sample question (TR):** "Test policy: TDD strict (>80% coverage), pragmatic (>50%), yoksa prototype (test optional)?"

### 23. Documentation Level (DOC)
README + API docs + examples expectation?
- **Trigger:** always-on (every project).
- **SILENT-ASSUME default:** open-source/public repo → "public"; private → "internal".
- **GATE triggers:** library / SDK / public API; contributor onboarding intent.
- **Sample question (TR):** "Doc level: minimal (kendin kullan), internal (takım), public (3rd-party kullanıcılar)?"

## Performance Dimensions (since 8.15.0, design-time)

### 24. Performance Budget (PERF)
JS bundle size + Core Web Vitals + image budget tier?
- **Trigger:** FE stack-tag (`react-frontend|vue-frontend|svelte-frontend|html-static`).
- **SILENT-ASSUME default:** "pragmatic" (200KB JS gzip, LCP 2.5s, image <100KB). `[assumed: pragmatic budget]`.
- **GATE triggers:** Phase 1 prompt has "fast" / "scale" / "low-latency" / "mobile" / "3G" / "performance"; e-commerce / publishing / public-facing context; SLA gerektiren feature.
- **SKIP-MARK alternative:** internal admin tool / prototype / proof-of-concept → `[unspecified: perf-budget, no SLA]`.
- **Sample question (TR):** "Performans hedefi: strict (100KB JS / LCP <2s / WebP zorunlu), pragmatic (200KB / 2.5s / WebP önerilen), yoksa internal-only (budget yok)?"

## Phase 1.7 → 1.5 handoff state-set (since 8.15.0)

After all dimensions (core 7 + security 5 + DB 7 + ops 4 + perf 1 + stack add-ons) are classified and the developer has answered all GATE
questions, emit the following Bash before handing off to Phase 1.5:

```bash
bash -c '
# 8.17.0 — load skill-prose auth token (rotated by mcl-activate.sh).
[ -n "${MCL_STATE_DIR:-}" ] && [ -f "$MCL_STATE_DIR/skill-token" ] \
  && export MCL_SKILL_TOKEN="$(cat "$MCL_STATE_DIR/skill-token")"
for lib in "$MCL_HOME/lib/hooks/lib/mcl-state.sh" \
           "$HOME/.mcl/lib/hooks/lib/mcl-state.sh" \
           "$HOME/.claude/hooks/lib/mcl-state.sh"; do
  [ -f "$lib" ] && source "$lib" && break
done
# 4 ops sub-fields: each is one of (provided value | "skipped" | "default-assumed")
mcl_state_set phase1_ops "{\"deployment_target\":\"<dep_choice>\",\"observability_tier\":\"<mon_choice>\",\"test_policy\":\"<tst_choice>\",\"doc_level\":\"<doc_choice>\"}" >/dev/null 2>&1
# perf budget tier: strict | pragmatic | internal-only
mcl_state_set phase1_perf "{\"budget_tier\":\"<perf_tier>\"}" >/dev/null 2>&1
mcl_audit_log "phase1_ops_populated" "phase1-7" "deployment+observability+test+doc" 2>/dev/null || true
mcl_audit_log "phase1_perf_populated" "phase1-7" "budget_tier=<perf_tier>" 2>/dev/null || true
'
```

The two audit events (since 8.16.0) are required by Phase 6 (a)
audit-trail completeness check. If skill prose Bash is forgotten,
Phase 6 (a) reports a LOW soft fail per missing event.

### Alternative: Marker Emission (since 8.19.0)

Audit telemetry from 8.10.0-8.17.0 production sessions showed skill
prose Bash above is rarely invoked in practice (auth-check / env
inheritance / model behavior — multiple causes). If for ANY reason
the Bash above is not executed, emit these structured text blocks at
the END of your response — `mcl-stop.sh` reads them on the next Stop
turn and writes the state from authorized hook context (idempotent —
will not overwrite values the Bash already wrote):

```
<mcl_state_emit kind="phase1-7-ops">{"deployment_target":"<chosen>","observability_tier":"<chosen>","test_policy":"<chosen>","doc_level":"<chosen>"}</mcl_state_emit>
<mcl_state_emit kind="phase1-7-perf">{"budget_tier":"<strict|pragmatic|internal-only>"}</mcl_state_emit>
```

The Bash path remains the **preferred** path (writes immediately,
audit `caller=skill-prose`, no transcript dependency). The marker is
the **safety net** — text emission only, no tool invocation, no auth
required. If neither path runs, Phase 6 (a) reports the LOW soft
fail and downstream phases proceed with default state.

These state objects feed Phase 4.5 ops gate (8.13.0) and Phase 4.5 perf
gate (8.14.0), and inform threshold defaults (e.g. perf budget_tier
"strict" lowers `bundle_budget_kb` from 200 to 100).

## Stack Add-ons (delta dimensions, applied via `mcl-stack-detect.sh` tags)

Stack tag returned by `mcl-stack-detect.sh detect "$(pwd)"`. Multi-stack
projects union all matching add-ons; deduplicate dimensions that appear in
more than one add-on.

<!-- TODO(post-8.4.1): finer framework splits when needed. Solid, Angular,
     Qwik have distinct reactivity / hydration models that may warrant their
     own entries. Same for kotlin-mobile vs kotlin-backend (currently lumped
     under `### mobile`). Add new sections + corresponding mcl-stack-detect.sh
     tag patterns when usage demands. -->

### typescript / javascript

Generic web base — applies to any TS/JS web project regardless of framework.
Framework-specific deltas live in their own sections below
(`react-frontend`, `vue-frontend`, `svelte-frontend`).

- **Pagination type** — cursor / offset / no-pagination?
- **Search semantics** — client-side filter, server-side search, hybrid?
- **Empty / Loading / Error UI states** — per design system, distinct copy for filtered-empty vs system-empty? (UX state lives here, not in core failure modes.)
- **Route permission gate** — guard at router level, layout level, or per-component?
- **SSR / CSR / hybrid** — does this feature run on the server, client, or both? Hydration impact?

### react-frontend

React-specific deltas (applied in addition to `typescript`/`javascript` base).

- **Hook patterns** — useState/useReducer choice; custom hook extraction conventions; effect cleanup discipline
- **Suspense boundaries** — for data fetching and code splitting; where they live in the tree
- **Server vs client components** — RSC awareness (Next.js App Router, etc.); `"use client"` directive boundaries
- **State management** — built-in (useState/useContext) / Zustand / Redux Toolkit / Jotai / TanStack Query for server state

### vue-frontend

Vue-specific deltas (applied in addition to `typescript`/`javascript` base).

- **Composition vs Options API** — project convention; `<script setup>` shorthand?
- **State management** — Pinia (Vue 3) / Vuex (Vue 2 legacy)
- **SFC structure** — template/script/style block organization, scoped vs global styles
- **Reactivity primitives** — `ref` / `reactive` / `computed` / `watchEffect` choice per use case
- **Rendering target** — Nuxt SSR / Vite SPA / Vite SSG / hybrid

### svelte-frontend

Svelte-specific deltas (applied in addition to `typescript`/`javascript` base).

- **Stores vs runes** — Svelte 4 stores vs Svelte 5 runes (`$state`, `$derived`, `$effect`)
- **Server vs client islands** — SvelteKit form actions, server load functions, progressive enhancement
- **Reactivity model** — `$:` reactive declarations (legacy) vs runes (modern)
- **Compiler optimizations** — opt-in vs default behaviors; `<svelte:options>` per-component

### html-static

For static site projects (no JS framework detected; `index.html` or static HTML files).

- **Asset bundling** — none (raw HTML+CSS+JS) / Vite / esbuild / Webpack / 11ty / Astro
- **SEO** — meta tags, Open Graph, sitemap.xml, robots.txt, structured data
- **Accessibility** — ARIA usage, semantic HTML, keyboard navigation, contrast ratios
- **Deployment target** — static hosting (Netlify/Vercel/CDN) vs Apache/Nginx vs GitHub Pages

### python (FastAPI / Django / Flask / REST)

- **API contract versioning** — URI (`/v1/`), header (`Accept: ...`), or none?
- **Rate limiting strategy** — per-IP, per-user, per-token? sliding window or fixed?
- **Request validation depth** — pydantic schemas, where? marshmallow? manual?
- **Async vs sync handler** — does this path need async I/O or is sync acceptable?

### go / rust

- **Concurrency model** — goroutine pool, channel-based, Tokio runtime, single-threaded?
- **Error propagation pattern** — `error` return / `Result<T,E>` / panic? wrapping convention?
- **Lifetime / ownership impact (Rust)** — does this feature introduce new shared state, `Arc`, `Rc`, or borrow boundaries?

### java

- **Framework** — Spring Boot / Quarkus / Micronaut / vanilla servlet
- **Build tool** — Maven / Gradle (Kotlin DSL or Groovy)
- **Reactive vs blocking I/O** — WebFlux / MVC / Project Loom virtual threads
- **Persistence** — JPA (Hibernate) / JDBC / R2DBC / MyBatis
- **Java version target** — LTS (8 / 11 / 17 / 21) / latest stable

### csharp

- **Framework** — ASP.NET Core / .NET MAUI / WPF / Unity / Console
- **Async pattern** — `Task` / `ValueTask` / `IAsyncEnumerable` / channel-based
- **DI convention** — built-in `IServiceCollection` / Autofac / Simple Injector
- **ORM** — EF Core / Dapper / no ORM (raw SQL)
- **Target runtime** — .NET 6 / 7 / 8 (LTS) vs .NET Framework 4.x legacy

### ruby

- **Framework** — Rails (full-stack) / Rails (API mode) / Sinatra / Hanami / Roda
- **ORM** — ActiveRecord / Sequel / ROM
- **Background jobs** — Sidekiq / GoodJob / SolidQueue (Rails 7.1+)
- **API mode vs full-stack** — JSON-only, ERB views, or hybrid?
- **Test framework** — RSpec / Minitest

### php

- **Framework** — Laravel / Symfony / vanilla / WordPress (CMS context — different concerns)
- **ORM** — Eloquent (Laravel) / Doctrine (Symfony) / no ORM
- **Job queue** — Laravel Horizon / Symfony Messenger / vanilla (cron + DB)
- **PHP version target** — 7.x legacy / 8.x modern (typed properties, enums, readonly)

### cpp

- **Standard target** — C++17 / C++20 / C++23
- **Build system** — CMake / Bazel / Make / MSBuild / xmake
- **Memory management** — RAII + smart pointers / manual / hybrid (legacy boundary)
- **Concurrency** — `std::thread` / coroutines (C++20) / TBB / OpenMP / platform-specific
- **Platform** — cross-platform / Windows-specific / embedded (no STL?) / game console

### lua

- **Runtime** — Lua 5.x / LuaJIT / Roblox Luau / NeoVim plugin runtime
- **Coroutine usage** — async-style patterns, scheduler
- **Module system** — `require` / `package.path` conventions
- **C interop** — LuaJIT FFI / hand-written C bindings / no FFI (pure Lua)

### cli (any stack)

Triggered by `cli` tag (`mcl-stack-detect.sh` since 8.4.1 — bin entries
in language manifests, `bin/` dir, `cmd/` Go convention, etc.).

- **stdin contract** — accepts piped data? format (json / line-delim / binary)? required or optional?
- **Exit code semantics** — 0 success / non-zero? specific codes for specific failure modes?
- **Flag naming** — `--kebab-case`, single-letter aliases, POSIX vs GNU style?
- **TTY vs non-TTY behavior** — color output, progress bars, prompts when not interactive?

### data-pipeline (spark / beam / airflow / dbt / prefect / dagster)

Triggered by `data-pipeline` tag (since 8.4.1 — Airflow `dags/`, dbt
project file, Prefect config, or batch/stream framework deps).

- **Batch vs stream** — one-shot batch, scheduled batch, continuous stream?
- **Watermark / exactly-once semantics** — at-least-once with dedup? exactly-once with checkpointing?
- **Replay semantics** — can the job be re-run on the same input window? backfill strategy?
- **Schema evolution policy** — adding/removing fields, backward/forward compatibility?

### mobile (swift / kotlin)

- **Offline mode** — feature works offline? graceful degrade? sync on reconnect?
- **Push notification handling** — does this feature emit or consume push notifications?
- **OS version compatibility** — minimum iOS/Android version supported?

### ml-inference

Triggered by `ml-inference` tag (since 8.4.1 — model artifact files,
ML library deps in requirements/pyproject, mlflow/mlruns dirs).

- **Input validation** — schema enforcement, range checks, distribution guards?
- **Model version pinning** — explicit version in request, or "latest" with migration path?
- **Drift detection / monitoring** — how is input/output drift surfaced?
- **Latency budget breakdown** — preprocessing / model inference / postprocessing — concrete budget per stage?

## Question Flow

For each dimension in order — core 1→7 first, then matching stack add-ons:

1. Read the confirmed Phase 1 parameters.
2. Classify SILENT-ASSUME, SKIP-MARK, or GATE.
3. If GATE → ask exactly one question (existing one-question-at-a-time rule applies, no introductory sentences, no list of multiple questions).
4. **Wait for the developer's answer before evaluating the next dimension.** When multiple dimensions classify as GATE in the same audit pass, queue them and ask sequentially across turns — never batch two GATE questions in the same response, even with bullet/numbered formatting. Each GATE answer is confirmed and marked in the parameter set before the next GATE is evaluated.
5. Continue to the next dimension.

When all dimensions resolve, emit the audit entry, advance to Phase 1.5.

## Audit

Every Phase 1.7 execution emits one audit entry:

```
precision-audit | phase1-7 | core_gates=N stack_gates=M assumes=K skipmarks=L stack_tags=<comma> skipped=<true|false>
```

- `core_gates`: how many of the 7 core dimensions fired GATE-PRECISION questions
- `stack_gates`: how many stack add-on dimensions fired GATE-PRECISION
- `assumes`: how many dimensions resolved as SILENT-ASSUME (`[assumed: X]` markers)
- `skipmarks`: how many dimensions resolved as SKIP-MARK (`[unspecified: X]` markers)
- `stack_tags`: detected stack tags from `mcl-stack-detect.sh`, comma-separated; empty when no stack detected
- `skipped=true`: detected language is English; entry still emitted as detection control

If skipped (English source), `skipped=true` and other counters are zero.

`mcl-stop.sh` writes `precision-audit-skipped-warn | mcl-stop.sh | summary-confirmed-but-no-audit` when the Phase 1→2 transition fires (first SPEC_HASH detection while `current_phase=1`) without a `precision-audit` entry recorded earlier in the same session. This is the detection control required by the behavioral→dedicated rule — even when Phase 1.7 is a behavioral pass, the audit confirms it was evaluated.

## Failure Path

If the audit entry cannot be emitted (filesystem error, etc.), DO NOT silently
fall back. Retry with maximum effort, changing the approach each attempt. If
the root cause is missing information from the developer, ask one clarifying
question in their language, then retry. Continue until a consistent run is
achieved.

A consistent run produces:
- One `precision-audit | phase1-7 | ...` audit entry
- All core dimensions classified (SILENT-ASSUME / SKIP-MARK / GATE) with the
  appropriate spec marker for SILENT/SKIP and a confirmed answer for GATE
- All matching stack-add-on dimensions classified

## Enforcement (since 8.3.2 — hard tier)

Phase 1.7 is enforced at the same tier as Phase 4.5: `mcl-stop.sh` returns
`{"decision": "block", ...}` when a Phase 2 spec block (`📋 Spec:`) is
detected in the turn AND no `precision-audit` audit entry was emitted earlier
in the same session. State stays at `current_phase=1`; the Phase 1→2
transition is rewound until the audit entry appears.

The block reason instructs Claude to walk Phase 1.7 in the same response and
re-emit the spec with precision-enriched parameters (the prior spec is
discarded — replaced, not duplicated).

Two events are written when the block fires:
- `precision-audit-skipped-warn | mcl-stop.sh | summary-confirmed-but-no-audit` — backward-compat with 8.3.0 detection signal
- `precision-audit-block | mcl-stop.sh | summary-confirmed-but-no-audit; transition-rewind` — the new enforcement event

### English-language safety valve

When the developer's detected language is English, Phase 1.7 is skipped. To
clear the block, emit the audit entry with `skipped=true`:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log "precision-audit" "phase1-7" "core_gates=0 stack_gates=0 assumes=0 skipmarks=0 stack_tags= skipped=true"'
```

The next turn's `mcl-stop.sh` will see the audit entry and allow the
transition. The block does NOT loop for English sessions when this audit is
emitted.

### Recovery

If the block fires repeatedly and you believe it's in error (e.g., audit emit
failed silently due to a filesystem race), the developer can type
`/mcl-restart` to clear all phase state. Manual edits to `.mcl/state.json` are
blocked by `mcl-pre-tool.sh` to prevent state-machine bypass; recovery must
go through `/mcl-restart` or session restart.

</mcl_phase>
