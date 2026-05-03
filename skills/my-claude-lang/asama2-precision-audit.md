<mcl_phase name="asama2-precision-audit">

# Aşama 2: Precision Audit

Called automatically after Aşama 1 AskUserQuestion returns an approve-family
tool_result, before Aşama 3 (Engineering Brief).

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

Aşama 1 ensures the developer's parameters are **complete** (all fields gathered).
Aşama 2 ensures they are **precise** (each dimension classified — silent default,
explicit no-default, or asked).

A senior English-speaking engineer does not ship a spec where dimensions like
permission model, idempotency, or PII handling are silently absent. Aşama 2
walks a fixed checklist of dimensions and forces an explicit decision for each
one. The output is a precision-enriched parameter set that Aşama 3 translates
to English and Aşama 4 expands into the spec body.

## When Aşama 2 Runs

After the Aşama 1 summary `AskUserQuestion` tool_result returns approve-family.
Before Aşama 3 brief generation. Skipped silently when the developer's
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
`[assumed: X]` so Aşama 4 review can correct if wrong.

### SKIP-MARK (since 8.3.0)
Dimension applies but **no industry-default assumption is safe**. Recording
silence as a default would be wrong — instead, mark explicitly that the
dimension is unspecified. Aşama 8 risk review can lens these markers and
surface them as risks if the dimension turns out to matter at execution time.
Spec marker: `[unspecified: <reason>]` (e.g., `[unspecified: no SLA stated]`).

Currently used by: **Performance SLA** (dimension 6). Other dimensions either
have safe industry defaults (SILENT-ASSUME) or have architectural impact that
mandates a question (GATE).

### GATE
Architectural impact, irreversible without rework, or developer's input
contains explicit signal that the answer matters (e.g., they used the word
"fast", "scale", "secure"). Ask exactly **one question** following the
existing one-question-at-a-time rule, then mark the answer in spec parameters.

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
- **GATE triggers:** request contains hidden sub-tasks (existing Aşama 1 pattern) or analogy-based scope ("X gibi yap"); explicit confirmation needed on what is excluded.
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
- **GATE triggers:** developer used the word "fast", "scale", "high traffic", "low latency", or implied volume ("X requests per second", "Y users", "millions of records") in Aşama 1.
- **Sample question (TR):** "'Hızlı' dedin — concrete bir target var mı (örn. p95 < 200ms, throughput 1k req/s)?"

### 7. Idempotency / Retry
Operation invoked twice → same observable result?
- **SILENT-ASSUME default:** read operations are idempotent (`[assumed: idempotent read]`). Pure-compute operations idempotent.
- **GATE triggers:** write operations, payment / external side-effect calls, message publishing, file system mutation.
- **Sample question (TR):** "Bu write operasyonu retry edilirse iki kayıt mı oluşur — idempotency key kullanılacak mı?"

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

1. Read the confirmed Aşama 1 parameters.
2. Classify SILENT-ASSUME, SKIP-MARK, or GATE.
3. If GATE → ask exactly one question (existing one-question-at-a-time rule applies, no introductory sentences, no list of multiple questions).
4. **Wait for the developer's answer before evaluating the next dimension.** When multiple dimensions classify as GATE in the same audit pass, queue them and ask sequentially across turns — never batch two GATE questions in the same response, even with bullet/numbered formatting. Each GATE answer is confirmed and marked in the parameter set before the next GATE is evaluated.
5. Continue to the next dimension.

When all dimensions resolve, emit the `precision-audit` audit entry, then emit the Aşama 2 **closing AskUserQuestion** (see "Closing AskUserQuestion" below) and wait for an approve-family answer before advancing to Aşama 3.

## Closing AskUserQuestion (since 10.1.14 — deterministic gate)

After the dimension scan and any GATE answers are collected, Aşama 2 ends with a single `AskUserQuestion` that asks the developer to approve the precision-audited intent. This is the **deterministic gate** that unblocks Aşama 4 (SPEC) emission. Without this approval, `mcl-pre-tool.sh` blocks every mutating tool call with reason `MCL ASAMA 2 SKIP-BLOCK`.

### Title prefix (mandatory)

The askq title MUST start with the exact prefix below so `mcl-askq-scanner.py` can classify the intent as `precision-confirm`:

- **Turkish (calibration):** `MCL <ver> | Faz 2 — Precision-audit niyet onayı: ...`
- **English:** `MCL <ver> | Phase 2 — Precision-audit intent confirmation: ...`
- **Other languages:** keep `Precision-audit` as a literal MCL technical token (same convention as `MCL`, `Spec`, `GATE`, `Faz N`); translate the rest. Example (Spanish): `MCL <ver> | Fase 2 — Precision-audit intención: ...`

### Body structure

- One short paragraph summarizing the precision-audited intent: which dimensions were classified, which were SILENT-ASSUME, which were SKIP-MARK, which had GATE answers.
- Three options: approve / edit / cancel — same 3-option shape as Aşama 1's summary-confirm askq.

### Audit emission (automatic)

When the developer selects an approve-family option, `mcl-stop.sh` emits:

```
asama-2-complete | stop | selected=<option-label>
```

This single audit unblocks Aşama 4 SPEC emission. No other audit substitutes — `summary-confirm-approve`, `precision-audit`, and `asama-1-complete` are no longer sufficient on their own (since 10.1.14). A valid `asama-2-complete` implicitly proves Aşama 1 also ran, since Aşama 2 is canonically called only after Aşama 1's summary-confirm-approve.

### English-language sessions

Aşama 2's dimension scan is skipped for English sources (the audit entry still fires with `skipped=true` as a detection control), but the **closing AskUserQuestion is still required**. The body becomes a one-line confirmation ("Aşama 2 skipped — English session. Approve to proceed to SPEC?"). Determinism is the principle: no exceptions, no language-conditional skips of the gate itself.

### Recovery hatch

If the closing askq fails to emit (model error, transcript loss), the developer can manually emit:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log asama-2-complete mcl-stop "params=precision-audit-confirmed"'
```

This mirrors the `asama-4-complete` Bash recovery hatch from v10.1.7 and is the same shape as other phase-skip recovery paths.

## Audit

Every Aşama 2 execution emits **two** audit entries (since 10.1.14):

```
precision-audit | asama2 | core_gates=N stack_gates=M assumes=K skipmarks=L stack_tags=<comma> skipped=<true|false>
asama-2-complete | stop | selected=<approve-option-label>
```

The first entry (`precision-audit`) is emitted by the model at the end of the dimension scan and records what was classified. The second (`asama-2-complete`) is emitted by `mcl-stop.sh` when the closing AskUserQuestion (intent: `precision-confirm`) returns an approve-family answer; it is the deterministic gate enforced by `mcl-pre-tool.sh` for Aşama 4 SPEC emission.

- `core_gates`: how many of the 7 core dimensions fired GATE-PRECISION questions
- `stack_gates`: how many stack add-on dimensions fired GATE-PRECISION
- `assumes`: how many dimensions resolved as SILENT-ASSUME (`[assumed: X]` markers)
- `skipmarks`: how many dimensions resolved as SKIP-MARK (`[unspecified: X]` markers)
- `stack_tags`: detected stack tags from `mcl-stack-detect.sh`, comma-separated; empty when no stack detected
- `skipped=true`: detected language is English; entry still emitted as detection control

If skipped (English source), `skipped=true` and other counters are zero.

`mcl-stop.sh` writes `precision-audit-skipped-warn | mcl-stop.sh | summary-confirmed-but-no-audit` when the Aşama 1→4 transition fires (first SPEC_HASH detection while `current_phase=1`) without a `precision-audit` entry recorded earlier in the same session. This is the detection control required by the behavioral→dedicated rule — even when Aşama 2 is a behavioral pass, the audit confirms it was evaluated.

## Failure Path

If the audit entry cannot be emitted (filesystem error, etc.), DO NOT silently
fall back. Retry with maximum effort, changing the approach each attempt. If
the root cause is missing information from the developer, ask one clarifying
question in their language, then retry. Continue until a consistent run is
achieved.

A consistent run produces:
- One `precision-audit | asama2 | ...` audit entry
- All core dimensions classified (SILENT-ASSUME / SKIP-MARK / GATE) with the
  appropriate spec marker for SILENT/SKIP and a confirmed answer for GATE
- All matching stack-add-on dimensions classified

## Enforcement (since 8.3.2 — hard tier)

Aşama 2 is enforced at the same tier as Aşama 8: `mcl-stop.sh` returns
`{"decision": "block", ...}` when a Aşama 4 spec block (`📋 Spec:`) is
detected in the turn AND no `precision-audit` audit entry was emitted earlier
in the same session. State stays at `current_phase=1`; the Aşama 1→4
transition is rewound until the audit entry appears.

The block reason instructs Claude to walk Aşama 2 in the same response and
re-emit the spec with precision-enriched parameters (the prior spec is
discarded — replaced, not duplicated).

Two events are written when the block fires:
- `precision-audit-skipped-warn | mcl-stop.sh | summary-confirmed-but-no-audit` — backward-compat with 8.3.0 detection signal
- `precision-audit-block | mcl-stop.sh | summary-confirmed-but-no-audit; transition-rewind` — the new enforcement event

### English-language safety valve

When the developer's detected language is English, Aşama 2 is skipped. To
clear the block, emit the audit entry with `skipped=true`:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log "precision-audit" "asama2" "core_gates=0 stack_gates=0 assumes=0 skipmarks=0 stack_tags= skipped=true"'
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
