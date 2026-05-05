<mcl_phase name="asama9-risk-review">

> ⚠️ SYNC NOTE: The active Aşama 8 rule lives in `mcl-activate.sh` STATIC_CONTEXT
> (the `<mcl_phase name="asama9-risk-review">` block). This file is the extended
> reference. When updating Aşama 8 behavior, BOTH must be updated together.

# Aşama 9: Post-Code Risk Review (interactive dialog) — was Aşama 8 in v10

Aşama 9 is a **mandatory, sequential, interactive dialog** that runs
AFTER Aşama 8 (code is written via TDD) and BEFORE the quality/test
auto-fix pipeline (still labeled "Aşama 9" in the active code; v11
plan R5 splits it into 8 dedicated phases 10..17). It surfaces risks
the developer must decide on — spec compliance gaps, missed edge
cases, regression surfaces, scope drift — one at a time via
AskUserQuestion.

The deeper code-quality lenses (code review, simplify, performance,
security) and comprehensive test coverage (unit, integration, E2E,
load) are NOT in Aşama 9 — they live in the quality/test pipeline
that R5 will rename out of "Aşama 9".

## When Aşama 9 Runs

Immediately after Aşama 8 finishes writing code (TDD GREEN-verified).
Aşama 8 does NOT end with "done" or a changes summary — it hands off
to Aşama 9.

## The Dialog Structure

Aşama 8 is NOT a one-shot list. It is a **sequential, one-risk-per-turn
conversation**. For each risk:

1. MCL presents **one** risk as plain text with a short explanation of
   why it matters (security gap / data integrity / regression / UX /
   etc.)
2. MCL immediately calls AskUserQuestion:
   ```
   AskUserQuestion({
     question: "MCL <version> | <localized risk decision prompt>",
     options: [
       "<apply-fix-in-language>",   # MCL implements the fix
       "<skip-in-language>",        # accept the risk as-is
       "<make-rule-in-language>"    # triggers Rule Capture
     ]
   })
   ```
3. MCL STOPS and waits for the tool_result **in the next message**.
4. On tool_result: execute the chosen action, then present the next risk.
5. Repeat until all risks are resolved.

⛔ STOP RULE: After presenting a risk and calling `AskUserQuestion`,
STOP. Do NOT list the next risk in the same response. Do NOT proceed
to Aşama 9. Wait for the tool_result.

## What Aşama 8 Reviews

### 1. Spec Compliance Pre-Check

Verify every MUST and SHOULD requirement from the approved `📋 Spec:`
body was implemented in Aşama 7. Particular focus on the **security
and performance decisions** the spec made (e.g., "MUST: rate-limit
endpoints to 60 req/min", "SHOULD: cursor-paginate with default 50
per page") — these are the spec's promised invariants, and Aşama 8's
first job is verifying they actually shipped.

How:
1. Retrieve the approved spec from conversation context (the `📋 Spec:`
   block approved in Aşama 4). If unrecoverable, skip this step
   silently and proceed to missed-risk scan.
2. Walk every MUST, then every SHOULD requirement.
3. For each: inspect Aşama 7 code to determine fully implemented,
   partially, or absent.
4. **Fully implemented** → silent pass.
5. **Partially or absent** → surface as an Aşama 8 risk in the
   sequential dialog (cite spec verbatim, explain gap, three options).

If every MUST/SHOULD is fully implemented, skip this step silently.

### 2. Missed-Risk Scan

After spec compliance, scan for risks the spec didn't explicitly call
out but the code shape suggests. Categories:

- **Data integrity**: race conditions, stale cache, transaction
  boundaries
- **Error handling**: unhandled rejections, missing try/catch where
  needed, swallowed errors
- **Regression**: imports of modified files, shared utilities changed,
  API contract shifts
- **UX**: accessibility, loading states, error states, edge-case UI
  breaks
- **Concurrency**: shared mutable state, event-listener leaks
- **Observability**: missing logs/metrics for new code paths
- **Edge cases**: empty input, null, overflow, off-by-one

Each finding becomes one risk-dialog turn (one AskUserQuestion).

### 2b. Stack-Aware Security MUST Checklist (since v10.1.1)

Walk the following MUST items based on detected stack tags
(`mcl-stack-detect.sh`). Each absent MUST surfaces as a risk-dialog
turn with severity tag. ALL HIGH and MEDIUM findings here MUST be
resolved before Aşama 9 can complete (see "MEDIUM/HIGH must-resolve
invariant" in v10.1.2).

**Backend MUSTs (express / fastify / nest / koa / next-api / django / rails / fastapi):**
- helmet (or framework equivalent) → CSP, HSTS, X-Frame-Options,
  X-Content-Type-Options, Referrer-Policy, Permissions-Policy [HIGH]
- Login/auth endpoint rate-limit + lockout
  (`express-rate-limit`, `@nestjs/throttler`, etc.) [HIGH]
- bcrypt cost ≥ 12 (argon2id preferred for new code) [MEDIUM]
- JWT revocation list / `jti`, short-lived access (≤15min) +
  refresh rotation [HIGH]
- Cookie-based auth: `httpOnly` + `Secure` + `SameSite=strict` [HIGH]
- CORS explicit whitelist (no `*`, no broad regex in prod) [MEDIUM]
- Audit log on critical actions (login attempts, mutations,
  permission changes) [MEDIUM]
- Logging hygiene: no PII/secrets/tokens in logs; structured
  logger (pino/winston/structlog) over console [MEDIUM]
- Parameterized queries (Prisma/SQLAlchemy/TypeORM by default;
  raw SQL flagged) [HIGH]

**Frontend MUSTs (react-frontend / vue-frontend / svelte-frontend / html-static):**
- Content-Security-Policy explicit policy, NO `unsafe-inline`, NO
  `unsafe-eval`, nonce-based for inline scripts [HIGH]
- Strict-Transport-Security: `max-age ≥ 31536000; includeSubDomains;
  preload` (when HTTPS deployed) [HIGH]
- X-Frame-Options: `DENY` (or CSP `frame-ancestors 'none'`) [HIGH]
- X-Content-Type-Options: `nosniff` [MEDIUM]
- Referrer-Policy: `strict-origin-when-cross-origin` or stricter [MEDIUM]
- Permissions-Policy: deny camera/mic/geolocation by default
  unless spec requires them [MEDIUM]
- Subresource Integrity (SRI): `integrity` attribute on every
  `<script src=//cdn>` and `<link href=//cdn>` [MEDIUM]
- Trusted Types policy (script-injection strict control) [MEDIUM]
- Token storage: NEVER `localStorage` / `sessionStorage`. Only
  httpOnly + Secure + SameSite=strict cookie [HIGH]
- CSRF token on state-mutating endpoints [HIGH]
- Raw HTML insertion APIs (React `dangerouslySetInnerHTML`, Vue
  `v-html`, Svelte raw HTML directive): every usage reviewed,
  flagged if user-supplied content reaches them [HIGH]

**Auth & Identity MUSTs:**
- Password schema: zod `min(8)` + complexity (upper/lower/digit/
  symbol) OR `zxcvbn` score ≥ 3 [HIGH]
- Default credentials in seed: surface as Aşama 8 risk when seed
  is committed AND values look common (admin/admin*, root/root*,
  test/test*) [HIGH]
- RBAC matrix explicit even when one role exists [MEDIUM]
- IDOR protection: owner/tenant/role check before DB fetch/update/
  delete on every resource endpoint [HIGH]
- Session fixation defense: regenerate session id after login [MEDIUM]
- Brute-force defense: account lockout after N failures (default 5)
  within window (default 15 min) [HIGH]

**Data & Secrets MUSTs:**
- `.env` / `.env*.local` in `.gitignore` [HIGH]
- Default secrets / weak `JWT_SECRET` placeholders in committed
  files surface [HIGH]
- File-upload endpoints: type/size/name validation, no path
  traversal, no exec mime types [HIGH]

**Dependency hygiene MUSTs:**
- `npm audit --audit-level=moderate` (or pip/cargo/gem equivalent)
  passing [HIGH]
- No abandoned/unmaintained packages flagged for security-
  sensitive surfaces [MEDIUM]

For each absent MUST, surface as one Aşama 8 risk-dialog turn
with explicit severity tag (HIGH/MEDIUM) so the developer's
decision record is severity-aware. The MEDIUM/HIGH must-resolve
invariant (v10.1.2) prevents Aşama 9 → 11 progression while ANY
HIGH or MEDIUM finding is still `open` in
`state.open_severity_findings`.

### 3. Brief-Aşama-1 Scope Drift (since 8.4.0, preserved in v9.0.0)

Aşama 3 (UPGRADE-TRANSLATOR) transforms vague verbs into surgical
English and may add `[default: X, changeable]` markers. This lens
guards against **hallucinated scope** — invented features that lack
both Aşama 1 traceability AND a `[default]` marker.

**When it runs:** mandatory when the session's `engineering-brief`
audit shows `upgraded=true`. Skipped silently when `upgraded=false`.

**Procedure per implementation element:**
1. Walk Aşama 7 code: each function, route, schema field, dependency
   added in this session.
2. For each element ask:
   - Is it traceable to an Aşama 1 confirmed parameter?
   - If not, is it carried by a `[default: X, changeable]` marker in
     the brief or spec?
   - If neither: surface as a Brief-Drift risk.
3. Surface format (one risk per drift):
   ```
   [Brief-Drift] Implementation includes <X> (file:line). User did
   not mention <X> in Aşama 1; brief/spec has no [default: X,
   changeable] marker for it. Likely Aşama 3 upgrade-translator
   hallucination.

   Options:
     (a) Remove from spec + Aşama 7 code (revert to user intent)
     (b) Mark as [default: <X>, changeable] in spec
     (c) Rule-capture: developer wants this default for similar
         specs (writes to CLAUDE.md / .mcl/project.md)
   ```
4. Wait for developer reply before next risk.

## Risk Session Tracking (HEAD-based dedup)

At Aşama 8 start, check `.mcl/risk-session.md`. Run
`git log --oneline -1 | awk '{print $1}'` to get current HEAD.

If the file exists AND `phase4_head` matches current HEAD: read the
'Reviewed' entries; for each risk you generate, if its first 80
characters closely match a 'Reviewed' entry's text, skip it silently.

If the file is missing OR `phase4_head` differs: create/reset the
file with current HEAD and an empty Reviewed list. After EACH risk is
resolved: append `- <decision> | <first 80 chars of risk text>` under
`## Reviewed`. When Aşama 8 completes fully: delete the file.

This dedup is HEAD-based — when Aşama 7 produces new code (HEAD
advances), the dedup resets so post-fix risks are evaluated fresh.

## When There Are No Risks

If after honest review MCL finds no risks worth surfacing, OMIT Aşama
8 entirely from the response — no header, no placeholder, no filler —
and proceed silently to Aşama 9. The review still *happens*; only its
output is suppressed when clean. "No news = good news."

Never fabricate risks. Never present risks already handled in Aşama 1
or 4. Never emit a "No risks identified." sentence.

## TDD Re-Verify

After every Aşama 8 risk is resolved (skipped, fixed, or rule-captured),
run a TDD re-verify before handing off to Aşama 9 — provided
`test_command` is configured.

How:
1. Run `bash ~/.claude/hooks/lib/mcl-test-runner.sh green-verify`.
2. **GREEN** → proceed to Aşama 9.
3. **RED** → a fix introduced a regression. Surface the failing
   test(s) as a new Aşama 8 risk in the sequential dialog. Repeat
   until GREEN.
4. **TIMEOUT** → log audit line, proceed to Aşama 9 without blocking.

Skip the re-verify ONLY when Aşama 8 was omitted entirely.

## Audit Emit on Completion (since v10.1.5)

When all risks (was "Aşama 8 risks" in v10) are resolved and TDD
re-verify is GREEN (or skipped per the rules above), BEFORE handing
off to the next phase (Aşama 10 Code Review in v11; was Aşama 9
Quality+Tests in v10), emit the completion audit via Bash. **Dual
emit since v10.1.22** — v11 audit name plus v10 alias so existing
v10 hook enforcement at mcl-stop.sh keeps operating during the
bridge:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log asama-9-complete mcl-stop "h_count=N m_count=M l_count=K resolved=R"; \
  mcl_audit_log asama-8-complete mcl-stop "h_count=N m_count=M l_count=K resolved=R"'
```

R8 cutover removes the v10 alias (`asama-8-complete`) line.

Where:
- N: HIGH-severity finding count surfaced this session (from §2b checklist)
- M: MEDIUM-severity finding count
- K: LOW-severity finding count
- R: Total resolved (apply-fix + skip + rule-capture)

**Why mandatory:** The Stop hook's askq-classifier can miss the
risk-resolution turn (intent recognition gap, off-language wording,
prefix dropped). When that happens, `risk_review_state` stays `null`
even though the dialog actually ran end-to-end — the herta project
under v10.1.4 showed exactly this gap. An explicit audit emit is
classifier-independent: Stop hook scans audit.log and force-progresses
`risk_review_state` to `complete`. Audit + trace get a
`asama-8-progression-from-emit` record so the bypass is visible.

This emit is required even when Aşama 8 was OMITTED (no risks worth
surfacing) — emit with `h_count=0 m_count=0 l_count=0 resolved=0` so
the state machine knows the phase ran. "No news" still needs a recorded
finish-line.

## Hard Enforcement

Stop hook blocks session-end after Aşama 7 code if `risk_review_state`
is not `complete`. After 3 consecutive same-reason blocks → fail-open
+ audit warn (loop-breaker).

## Handoff to Aşama 9

After every risk is resolved and TDD re-verify passes, proceed to
Aşama 9 (Quality + Tests auto-fix pipeline). Aşama 9 runs without
AskUserQuestion — its findings are auto-fixed, not user-decided.

</mcl_phase>
