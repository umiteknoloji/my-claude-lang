<mcl_phase name="asama17-e2e-tests">

# Aşama 17: E2E Tests (auto-fix on changed files)

Seventh of 8 dedicated quality phases (was sub-step `9.7` in v10
monolithic `asama9-quality-tests.md`). Auto-fix only.

## When Aşama 16 Runs

Immediately after Aşama 15 (Integration Tests). Scope: files changed
in the current session, only when `ui_flow_active=true`.

## Procedure

For UI stack active + new user flows:

1. Check existing E2E suite (Playwright / Cypress / etc.).
2. If uncovered → WRITE E2E test for each new flow.
3. Run green-verify in headless mode.

## Soft applicability

Skip when `ui_flow_active=false` OR no E2E framework available. Audit:

```
asama-17-not-applicable  reason=<no-ui-or-framework>
```

## Audit emit (dual — v11 + v10 backward-compat)

```
mcl_audit_log "asama-17-start" "mcl-stop.sh" "scope=<files>"

mcl_audit_log "asama-17-end" "mcl-stop.sh" "tests_added=N green=true|false"

mcl_audit_log "asama-17-not-applicable" "mcl-stop.sh" "reason=<why>"
```

R8 cutover removes the v10 alias lines.

</mcl_phase>
