<mcl_phase name="asama13-security">

# Aşama 13: Security Vulnerability Check (whole-project scope)

Fourth of 8 dedicated quality phases (was sub-step `9.4` in v10
monolithic `asama9-quality-tests.md`). **Scope widens in v11**: the
v10 sub-step ran on changed files only; v11 Aşama 13 scans the
**entire project** (per the v11 vision pipeline diagram in
README.md). Auto-fix only — no AskUserQuestion in this phase. The
must-resolve invariant (open HIGH/MEDIUM findings escalate to the
risk dialog) is preserved.

## When Aşama 13 Runs

Immediately after Aşama 12 (Performance). Scope: the whole project,
not just changed files (this is the v11 difference vs v10's
changed-files-only sub-step `9.4`).

## Automatic tooling — invoked at start via Bash, NOT a model behavioral prior

1. `bash ~/.claude/hooks/lib/mcl-semgrep.sh scan <project-root>`
2. `npm audit --audit-level=moderate --omit=dev` (Node projects;
   `pip-audit` / `cargo-audit` / `bundler-audit` equivalents for
   other stacks)
3. Stack-specific linters with security plugins:
   - eslint with `eslint-plugin-security` (JS/TS)
   - bandit (Python)
   - gosec (Go)
   - brakeman (Ruby/Rails)

## Per-finding handling

- **HIGH/MEDIUM with unambiguous autofix** → apply silently via
  Edit/MultiEdit. Record `mcl_audit_log "asama-13-autofix" "stop"
  "rule=<id> file=<f>:<l>"` (v11). Append to
  `state.open_severity_findings` with `status=fixed`.
- **HIGH/MEDIUM ambiguous (no safe autofix)** → ESCALATE to the
  Aşama 9 risk dialog (NOT skip — must-resolve invariant from
  v10.1.2). Append to `state.open_severity_findings` with
  `status=open`. Re-opens Aşama 9 (`risk_review_state="running"`)
  for the developer to decide via AskUserQuestion (apply specific
  fix / accept with rule-capture justification / cancel).
- **LOW** → suppress entirely (false positive rate too high).

## Stack-aware MUST checks

For each MUST item that the Aşama 9 §2b checklist lists for the
detected stack tags, verify implementation in code:

- Backend MUSTs: helmet config / rate-limit / bcrypt cost / JWT
  lifecycle / cookie flags / CORS whitelist / audit log / logging
  hygiene / parameterized queries
- Frontend MUSTs: CSP / HSTS / X-Frame-Options / X-Content-Type-
  Options / Referrer-Policy / Permissions-Policy / SRI / Trusted
  Types / token storage / CSRF / raw-HTML APIs
- Auth MUSTs: password schema / default creds warning / RBAC /
  IDOR / session fixation / brute-force lockout
- Data MUSTs: `.gitignore` env files / weak secret detection /
  upload validation
- Dependency: `npm audit` clean

For each absent or violating MUST → append to
`state.open_severity_findings`. Same disposition rules as
semgrep findings (autofix / escalate / suppress).

Aşama 13 cannot mark itself complete until every MUST item has a
verdict (fixed / accepted / not-applicable with documented reason).

## Audit emit (dual — v11 + v10 backward-compat)

```
mcl_audit_log "asama-13-start" "mcl-stop.sh" "scope=whole-project"

mcl_audit_log "asama-13-end" "mcl-stop.sh" "findings=N fixes=M open=K"

mcl_audit_log "asama-13-ambiguous" "stop" "rule=<id> file=<f>:<l>"

mcl_audit_log "asama-13-resolved" "stop" "rule=<id> file=<f>:<l> status=fixed|accepted"

mcl_audit_log "asama-13-autofix" "stop" "rule=<id> file=<f>:<l>"
```

The v10 enforcement at mcl-stop.sh:1115+ (open-severity must-resolve
gate) still scans `asama-9-4-ambiguous` and `asama-9-4-resolved` —
the v10 aliases keep that gate working. R8 cutover migrates the gate
to scan `asama-13-*` only and removes the v10 alias lines from this
skill.

</mcl_phase>
