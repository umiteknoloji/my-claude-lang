<mcl_phase name="asama9-quality-tests">

# Aşama 9: Quality + Tests (sequential auto-fix pipeline)

Aşama 9 runs AFTER Aşama 8 (risk review dialog complete) and BEFORE
Aşama 10 (Impact Review). Eight sub-steps execute **sequentially**;
each detects + auto-fixes its scope. **No AskUserQuestion** — Claude
Code applies fixes directly.

## Pipeline (sequential, ALL applied)

| # | Sub-step | What it does |
|---|----------|--------------|
| 9.1 | Code review | Correctness, logic errors, dead code, missing validations |
| 9.2 | Simplify | Unnecessary complexity, premature abstraction, duplicate logic |
| 9.3 | Performance | N+1 queries, unbounded loops, blocking calls, memory leaks |
| 9.4 | Security | Injection (SQL/cmd/XSS), auth bypass, CSRF, secret exposure, insecure defaults |
| 9.5 | Unit tests | Any new function/class/module → unit test |
| 9.6 | Integration tests | New API endpoints, cross-module flows, DB interactions |
| 9.7 | E2E tests | UI stack active + new user flows |
| 9.8 | Load tests | Throughput-sensitive paths (queues, bulk, high-concurrency) |

Sub-steps run in order. Each writes its own start/end audit entry so
skip-detection is possible.

## Soft applicability ("yumuşak katılık")

Each sub-step decides if it applies. When NOT applicable for the
current code shape (e.g., load test for a calculator with no API,
E2E for a CLI tool):

1. Write audit entry: `aşama-9-N-not-applicable | mcl-stop.sh | reason=<why>`
2. Skip the sub-step silently.
3. Proceed to next sub-step.

When applicable but tooling missing (e.g., E2E framework not
installed):

1. Auto-fix CAN install lightweight tooling (e.g., `npm install -D
   playwright @playwright/test`) IF the project has a package manager
   and the install is idempotent.
2. Heavy installs (entire frameworks not yet decided) → write audit
   `aşama-9-N-tooling-required | <what is needed>`, skip, proceed.

## Per-sub-step protocol

For each of 9.1–9.8:

1. **Start audit:** `mcl_audit_log "aşama-9-N-start" "mcl-stop.sh" "scope=<files>"`
2. **Detect:** scan Aşama 7 code for sub-step's findings.
3. **Decide:**
   - No findings → skip silently.
   - Findings exist + auto-fix is unambiguous → apply fix via Edit /
     MultiEdit / Write.
   - Findings exist but auto-fix is ambiguous → write audit
     `aşama-9-N-ambiguous | finding=<X>`. Skip the fix. Aşama 8 risk
     dialog already gave the developer a chance to surface ambiguous
     items; Aşama 9 only handles the unambiguous tail.
4. **End audit:** `mcl_audit_log "aşama-9-N-end" "mcl-stop.sh" "findings=N fixes=M skipped=K"`
5. **Update state:** `mcl_state_set quality_review_state running`
   when 9.1 starts; `mcl_state_set quality_review_state complete`
   when 9.8 ends.

## Sub-step details

### 9.1 Code Review

Pattern-rules compliance check (from Aşama 5 PATTERN_SUMMARY):
- Naming convention violations
- Error handling pattern violations
- Test pattern violations

Plus: dead code, unreachable branches, missing validations on
parameters, error swallowing.

Auto-fix scope: unambiguous renames, removed dead code, added
validation for already-typed inputs.

### 9.2 Simplify

Detect:
- Functions wrapping a single expression
- Premature abstraction (interface with one impl)
- Duplicate logic across files
- Over-engineering (config layers no caller uses)

Auto-fix: inline trivial wrappers, extract obvious duplicates into
shared helpers IF the helper location is unambiguous.

### 9.3 Performance

Detect:
- N+1 query patterns (loop containing DB call)
- Unbounded loops over user input
- Synchronous blocking calls in async code paths
- O(n²) where O(n) is straightforward

Auto-fix: convert N+1 to batch query when ORM supports it; add
explicit bound to user-input loops; convert sync→async where the
async equivalent is one-line.

### 9.4 Security (since v10.1.1 — auto-tooling + must-resolve)

**Automatic tooling — invoked at start of 9.4 via Bash, NOT a model
behavior prior:**

1. `bash ~/.claude/hooks/lib/mcl-semgrep.sh scan <touched-files>`
2. `npm audit --audit-level=moderate --omit=dev` (Node projects;
   pip-audit / cargo-audit / bundler-audit equivalent for other
   stacks)
3. Stack-specific linters with security plugins:
   - eslint with `eslint-plugin-security` (JS/TS)
   - bandit (Python)
   - gosec (Go)
   - brakeman (Ruby/Rails)

Per-finding handling:

- **HIGH/MEDIUM with unambiguous autofix** → apply silently via
  Edit/MultiEdit. Record via `mcl_audit_log "asama-9-4-autofix"
  "stop" "rule=<id> file=<f>:<l>"`. Append to
  `state.open_severity_findings` with `status=fixed`.
- **HIGH/MEDIUM ambiguous (no safe autofix)** → ESCALATE to Aşama 8
  risk-dialog (NOT skip — v10.1.2 must-resolve invariant). Append
  to `state.open_severity_findings` with `status=open` so the
  Aşama 9 → 10/11 gate detects unresolved findings. The escalation
  re-opens Aşama 8 (`risk_review_state="running"`) for the
  developer to decide via AskUserQuestion (apply specific fix /
  accept with rule-capture justification / cancel).
- **LOW** → suppress entirely (too many false positives).

**Stack-aware MUST checks (mirror of Aşama 8 §2b checklist):**

For each MUST item that Aşama 8 §2b lists for the detected stack
tags, verify implementation in code:

- Backend MUSTs: helmet config / rate-limit / bcrypt cost /
  JWT lifecycle / cookie flags / CORS whitelist / audit log /
  logging hygiene / parameterized queries
- Frontend MUSTs: CSP / HSTS / X-Frame-Options / X-Content-Type-
  Options / Referrer-Policy / Permissions-Policy / SRI / Trusted
  Types / token storage / CSRF / raw-HTML APIs
- Auth MUSTs: password schema / default creds warning / RBAC /
  IDOR / session fixation / brute-force lockout
- Data MUSTs: `.gitignore` env files / weak secret detection /
  upload validation
- Dependency: `npm audit` clean

For each absent or violating MUST → append to
`state.open_severity_findings` with severity from the checklist.
Same disposition rules as semgrep findings (autofix / escalate /
suppress).

Aşama 9.4 cannot mark itself complete (`asama-9-4-end` audit) until
every MUST item has a verdict (fixed / accepted / not-applicable
with documented reason).

### 9.5 Unit Tests

For each new function/class/module in Aşama 7:

1. Check existing test files for coverage.
2. If uncovered → WRITE the unit test (use project's pattern from
   Aşama 5 PATTERN_SUMMARY — describe/it / unittest / etc.).
3. Run `bash ~/.claude/hooks/lib/mcl-test-runner.sh green-verify`.
4. RED → fix the test or fix the code; re-run until GREEN.

Skip when `test_command` is unconfigured (audit
`aşama-9-5-not-applicable | reason=test_command-missing`).

### 9.6 Integration Tests

For each new API endpoint, cross-module data flow, or DB interaction:

1. Check existing integration test files.
2. If uncovered → WRITE integration test (mock external services,
   real DB if available, real cross-module wiring).
3. Run green-verify; iterate until GREEN.

Skip when integration boundary doesn't apply (audit
`aşama-9-6-not-applicable | reason=<no-api-or-db>`).

### 9.7 E2E Tests

For UI stack active + new user flows:

1. Check existing E2E suite (Playwright / Cypress / etc.).
2. If uncovered → WRITE E2E test for each new flow.
3. Run green-verify in headless mode.

Skip when `ui_flow_active=false` OR no E2E framework available
(audit `aşama-9-7-not-applicable | reason=<no-ui-or-framework>`).

### 9.8 Load Tests

For throughput-sensitive paths (queues, bulk processors,
high-concurrency endpoints):

1. Detect by code shape: explicit batching, async iterators over
   large inputs, endpoints declared in spec as throughput targets.
2. If detected and uncovered → WRITE k6 / locust / ab script.
3. Run script; assert latency/throughput matches spec NFR if
   `[performance:]` marker present in spec.

Skip when no throughput-sensitive path detected (audit
`aşama-9-8-not-applicable | reason=no-throughput-path`).

## State machine

- Entering 9.1 → `mcl_state_set quality_review_state running`
- Each sub-step writes start/end audit
- Exiting 9.8 → `mcl_state_set quality_review_state complete`

## Output discipline

Aşama 9 is **silent during execution** — no per-finding announcement,
no progress meters, no "Aşama 9 başlıyor" headers. The developer
sees only the final summary in Aşama 11 (Verify Report) where
applied fixes appear as part of the diff.

If a sub-step encounters a hard failure (tool missing, write denied,
syntax error in auto-fix), record the failure in audit and surface
ONE concise notice to the developer at end of Aşama 9 only. Never
mid-pipeline.

## Anti-patterns

- Asking the developer questions in Aşama 9 (this stage is auto-fix only).
- Skipping sub-steps without an audit entry (skip-detection requires the audit).
- Re-applying fixes the developer already declined in Aşama 8 (Aşama
  8 took precedence; Aşama 9 only fills the unambiguous tail).
- Heavyweight installs without the project's package manager already
  configured.

## Handoff to Aşama 10

After 9.8 completes (or skips with audit), `quality_review_state` is
set to `complete`. Stop hook detects this and unblocks Aşama 10
(Impact Review).

</mcl_phase>
