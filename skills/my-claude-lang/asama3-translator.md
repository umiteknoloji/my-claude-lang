<mcl_phase name="asama3-engineering-brief">

# Aşama 3: Engineering Brief (Upgrade-Translator since 8.4.0)

Called automatically after Aşama 2 Precision Audit completes
(approve-family Aşama 1 confirmation + dimension classification done) and
before Aşama 4 spec generation.

## Purpose

Aşama 3 has TWO duties:

1. **Translate** non-English Aşama 1 parameters to English faithfully.
2. **Upgrade** vague verbs to surgical English verbs that carry standard
   technical implications.

The brief is the bridge between the developer's loose-English (or
non-English) intent and Aşama 4's senior-engineer spec. Until 8.3.x the
brief was a faithful translator only — vague verbs ("list", "show",
"manage") survived to Aşama 4 unchanged. From 8.4.0 the brief upgrades
verbs to surgical English so Aşama 4 spec uses senior-engineer
vocabulary by default.

## When Aşama 3 Runs

After Aşama 2's closing `precision-confirm` AskUserQuestion returns an approve-family option (Stop hook emits `asama-2-complete` audit). Aşama 3 then runs **before** Aşama 4. The phase chain is strict: Aşama 1 → Aşama 2 → Aşama 3 → Aşama 4. Skipping Aşama 3 is the most common failure mode that makes the Aşama 4 SPEC body land in the developer's language instead of English.

For English source language: translation step skipped (no language
conversion needed); **upgrade step still runs** because vague English
("list users") needs upgrade to surgical English ("render a paginated
user table") same as Turkish "kullanıcı listele" needs it.

## Why this phase exists (preventive frame, since 10.1.15)

Aşama 3 is the **only** phase that converts dev-language parameters into the English parameter set Aşama 4 emits as the SPEC body. If Aşama 3 is skipped, Aşama 4 has nothing English to derive from — it would either invent English on the fly (lossy) or default to dev-language (wrong). The activate hook prompt mandates Aşama 3 explicitly between Aşama 2's closing approve and Aşama 4's SPEC emit; this skill file is the deep reference. There is no detection-only enforcement for "Aşama 3 ran" — the preventive contract is in the prompt itself.

## Output Format

The brief is INTERNAL — not shown to the developer unless `/mcl-self-q`
is active. It is passed as context to Aşama 4 spec generation.

Structure:
```
[ENGINEERING BRIEF — INTERNAL]
Goal: <one sentence, English, surgical verb>
Actor: <who performs / initiates the action>
Constraints: <enumerated, English>
Success criteria: <observable outcomes, English>
Out of scope: <explicitly excluded, English>
Assumed defaults: <[assumed: X] items from Aşama 2 SILENT-ASSUME>
Skip-marks: <[unspecified: X] items from Aşama 2 SKIP-MARK>
Verb upgrades: <list of vague→surgical mappings applied this run>
```

## Allowed Upgrades

### Verb-level: vague → surgical

Map common vague verbs (any of MCL's 14 supported languages) to surgical
English verbs that imply a standard technical pattern:

| Vague verb (examples) | Surgical upgrade (per context) |
|---|---|
| list / listele / listar / 列表 / 列出 | "render a paginated table" (UI) / "fetch a paginated collection" (API) / "stream" (real-time) |
| show / göster / mostrar / 表示 / 顯示 | "render" (UI) / "return" (API) / "display with empty/loading/error states" (UI with reactive states) |
| manage / yönet / gestionar / 管理 | "expose CRUD operations on" / "provide create/read/update/delete handlers for" |
| process / işle / procesar / 处理 | context-dependent: "transform" / "validate" / "ingest" / "compute" |
| handle / yönet / handle / 处理 | "respond to" (events) / "route" (requests) / "delegate" (architectural) |
| build / yap / construir / 构建 | "implement" / "scaffold" / "compose" |
| create / oluştur / crear / 创建 | usually already surgical; if vague then "instantiate" / "provision" / "register" |
| fix / düzelt / corregir / 修复 | requires Aşama 1 to resolve WHICH bug — brief cannot upgrade vague-fix |
| improve / iyileştir / mejorar / 改进 | requires Aşama 1 to resolve WHICH metric — brief cannot upgrade vague-improve |
| update / güncelle / actualizar / 更新 | "modify" / "patch" / "migrate" (per scope) |
| do / yap / hacer / 做 | almost always too vague; Aşama 1 must resolve |

### Implicit defaults from surgical verb (allowed)

When a surgical verb upgrade implies a standard technical pattern,
ANNOTATE it with `[default: X, changeable]`. The marker tells Aşama 4
to surface this default to the developer for review.

Examples:
- "paginate" → standard pattern is cursor or offset → `[default: cursor pagination, changeable]`
- "render" → standard UI lifecycle → `[default: empty/loading/error states, changeable]`
- "fetch" → standard error contract → `[default: error propagation via Result/throw per project convention, changeable]`
- "validate" → standard input enforcement → `[default: schema validation at boundary, changeable]`
- "expose CRUD" → standard HTTP verbs → `[default: GET/POST/PUT/DELETE on resource path, changeable]`
- "transform" → standard data flow → `[default: pure-function transformation, changeable]`

These defaults are ALWAYS marked as `changeable` so Aşama 4 review can
correct without friction. They are NOT silently embedded — the marker
makes them visible.

### Aşama 2 GATE answers override implicit defaults

When Aşama 2 fired a GATE on a dimension that overlaps a verb's
implicit default (e.g., `paginate` default is `[default: cursor
pagination, changeable]`, but the react-frontend GATE asked
"page-numbered or infinite scroll?" and the developer answered
"page-numbered, 25 rows"), the GATE answer **wins**. Replace the
`[default: ..., changeable]` marker with `[confirmed: ...]`. The
`[confirmed]` marker tells Aşama 4 the value came from explicit
developer input, not from a verb default — Aşama 4's Scope Changes
Callout shows it as a confirmed parameter, not as a reviewable default.

Examples:
- Verb `paginate` + Aşama 2 GATE answer "page-numbered 25 rows" →
  `[confirmed: page-numbered pagination, 25 rows]` (NOT
  `[default: cursor pagination, changeable]`).
- Verb `render` + Aşama 2 GATE answer "skip loading state, show only
  empty + error" → `[confirmed: empty + error states only]` (NOT
  `[default: empty/loading/error states, changeable]`).

If Aşama 2 did NOT GATE the dimension, keep the `[default: ...,
changeable]` marker as before.

## Forbidden Additions

The brief MUST NOT introduce content not derivable from the user's
explicit Aşama 1 confirmation OR a verb's standard implicit default.

Hard prohibitions:

- **New entities**: user said "list users" → DO NOT add "admin role",
  "team membership", "audit log entry", "soft-delete column"
- **New features**: user said "show data" → DO NOT add "filter",
  "search", "export", "sort"
- **New non-functional requirements**: user said "list" → DO NOT add
  "p95 < 200ms", "100k items/sec throughput", "horizontal scaling"
  unless user mentioned performance/scale
- **New auth or security boundaries**: unless user said "auth", do NOT
  add authentication, authorization, role-based access, OAuth, JWT,
  rate limiting
- **New cross-cutting concerns**: logging, metrics, distributed tracing,
  caching, retry policies, circuit breakers — only if user mentioned
- **New data persistence decisions**: unless user said which DB, do NOT
  pick PostgreSQL/MySQL/Redis/etc.

## Calibration Examples

Concrete cases showing the upgrade boundary:

| User prompt | Faithful (pre-8.4.0) | Upgraded (8.4.0+) | Allowed? |
|---|---|---|---|
| "kullanıcı listele" | "list users" | "Render a paginated user table" | YES — list verb implies pagination + UI rendering |
| "kullanıcı listele" | "list users" | "Render a paginated user table with role-based access" | NO — RBAC was not mentioned |
| "auth ekle" | "add auth" | "Implement authentication" | YES — surgical verb, no specifics added |
| "auth ekle" | "add auth" | "Implement OAuth2 with PKCE flow" | NO — specific protocol invented |
| "API düzelt" | "fix the API" | (cannot upgrade — vague-fix) | Aşama 1 must resolve which bug FIRST |
| "deploy to staging" | "deploy to staging" | "Deploy to staging" | YES — already surgical, no change |
| "show user data" | "show user data" | "Render user data with empty/loading/error states" | YES — render verb implies state lifecycle |
| "show user data" | "show user data" | "Render user data table with filter and sort" | NO — filter/sort not mentioned |
| "kayıtları göster" | "show records" | "Render record table with pagination [default: cursor, changeable]" | YES — pagination is a render+collection default |
| "build login page" | "build login page" | "Implement login page UI" | YES — surgical implement verb |
| "build login page" | "build login page" | "Implement password-based login with bcrypt + JWT" | NO — bcrypt + JWT invented |
| "manage users" | "manage users" | "Expose CRUD operations on users [default: GET/POST/PUT/DELETE on /users, changeable]" | YES — manage→CRUD with HTTP default |
| "manage users" | "manage users" | "Expose user CRUD with admin-only access" | NO — admin-only invented |
| "kullanıcı listele" (Aşama 1 context: existing React + FastAPI project) | "list users" | "Render a paginated user table backed by a paginated GET endpoint exposed by the existing FastAPI service" | YES — backend layer is already in Aşama 1 confirmed context, brief may mention it |
| "kullanıcı listele" (Aşama 1 context: empty / no stack confirmed) | "list users" | "Render a paginated user table backed by a new REST API" | NO — no backend layer in Aşama 1 context, brief MUST stay frontend-only or send back to Aşama 1 |

The boundary: **surgical verb implies STANDARD industry default;
specific features and constraints require user mention.**

## Rules

1. **Translate intent** of confirmed Aşama 1 parameters to English. For
   English source, translation is identity.
2. **Upgrade vague verbs** in the goal/requirements/success-criteria
   per the table above. For each upgrade, record `<vague_verb> →
   <surgical_verb>` in the brief's "Verb upgrades" line.
3. **Mark implicit defaults** with `[default: X, changeable]`.
4. **Preserve Aşama 2 markers** verbatim (`[assumed: X]`,
   `[unspecified: X]`).
5. **Reject forbidden additions** — if context tempts you to add scope
   beyond verb implication, DO NOT. Wait for Aşama 8 brief-drift lens
   to surface the missing piece if implementation reveals a gap.

## Audit

Every Aşama 3 execution emits one audit entry:
```
engineering-brief | asama3 | lang=<detected> skipped=<true|false> retries=<N> clarification=<true|false> upgraded=<true|false> verbs_upgraded=<count>
```

- `skipped=true` ONLY when source language is English AND no vague verbs
  were detected (translation skipped, upgrade not needed). Skip is
  rare — most prompts in any language have at least one vague verb.
- `upgraded=true` when at least one verb was upgraded.
- `verbs_upgraded=N` — count of verbs upgraded this run.
- `retries=N` — number of internal retries on contradiction.
- `clarification=true` when developer was asked a question during
  failure path.

The audit is a detection control, not a permission gate. Aşama 8
brief-drift lens catches scope drift; the audit's `upgraded` field tells
the lens whether to scan.

## Failure Path

If the brief contradicts confirmed Aşama 1 parameters (drops a
constraint, contradicts a stated requirement) OR introduces a forbidden
addition, silent fallback is FORBIDDEN.

Retry with maximum effort, changing the approach each attempt — a retry
that uses the same formulation as the previous attempt does not count.
If the root cause is missing information, ask the developer one
clarifying question in their language, then retry.

A consistent brief produces:
- Every goal/actor maps to a confirmed Aşama 1 parameter or a verb
  upgrade with marked default
- No constraint from Aşama 1 is absent
- No new scope appears that lacks either Aşama 1 mention or
  `[default: X, changeable]` marker

Once consistent, continue to Aşama 4.

## Aşama 8 Brief-Drift Lens (Companion Check)

When this audit emits `upgraded=true`, Aşama 8 risk review runs Lens
(e): Brief-Phase-1 Scope Drift. The lens compares Aşama 7 implementation
against the user's ORIGINAL Aşama 1 confirmed parameters (NOT the
upgraded brief or downstream spec) and surfaces any element that:

- Lacks traceability to a Aşama 1 confirmed parameter, AND
- Lacks a `[default: X, changeable]` marker in the brief/spec.

This is the safety net. If Aşama 3 hallucinated scope, Aşama 8
catches it before Aşama 11 sign-off. See
`my-claude-lang/asama8-risk-review.md` Lens (e) for full rules.

## Aşama 4 Scope Changes Callout (Companion Check)

When this audit emits `upgraded=true`, Aşama 4 spec verification adds a
"Scope Changes" section in the developer's language listing every
upgrade made. The developer sees what was added beyond their literal
prompt and can correct via the edit option. See
`asama4-spec.md` "Scope Changes Callout" for the
required format.

</mcl_phase>
