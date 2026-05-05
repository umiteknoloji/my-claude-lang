<mcl_phase name="asama15-integration-tests">

# Aşama 15: Integration Tests (auto-fix on changed files)

Sixth of 8 dedicated quality phases (was sub-step `9.6` in v10
monolithic `asama9-quality-tests.md`). Auto-fix only.

## When Aşama 15 Runs

Immediately after Aşama 14 (Unit Tests). Scope: files changed in
the current session.

## Procedure

For each new API endpoint, cross-module data flow, or DB interaction:

1. Check existing integration test files.
2. If uncovered → WRITE integration test (mock external services,
   real DB if available, real cross-module wiring).
3. Run green-verify; iterate until GREEN.

## Soft applicability

Skip when integration boundary doesn't apply. Audit:

```
asama-15-not-applicable  reason=<no-api-or-db>
```

## Audit emit (dual — v11 + v10 backward-compat)

```
mcl_audit_log "asama-15-start" "mcl-stop.sh" "scope=<files>"
mcl_audit_log "asama-9-6-start" "mcl-stop.sh" "scope=<files>"  # v10 alias

mcl_audit_log "asama-15-end" "mcl-stop.sh" "tests_added=N green=true|false"
mcl_audit_log "asama-9-6-end" "mcl-stop.sh" "tests_added=N green=true|false"  # v10 alias

mcl_audit_log "asama-15-not-applicable" "mcl-stop.sh" "reason=<why>"
mcl_audit_log "asama-9-6-not-applicable" "mcl-stop.sh" "reason=<why>"  # v10 alias
```

R8 cutover removes the v10 alias lines.

</mcl_phase>
