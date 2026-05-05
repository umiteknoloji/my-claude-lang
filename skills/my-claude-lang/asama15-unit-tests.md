<mcl_phase name="asama15-unit-tests">

# Aşama 15: Unit Tests + TDD verification (auto-fix on changed files)

Fifth of 8 dedicated quality phases (was sub-step `9.5` in v10
monolithic `asama9-quality-tests.md`). Auto-fix only.

## When Aşama 14 Runs

Immediately after Aşama 13 (Security). Scope: files changed in the
current session (Aşama 8 production code).

## Procedure

For each new function/class/module written in Aşama 8:

1. Check existing test files for coverage.
2. If uncovered → WRITE the unit test (use project's pattern from
   Aşama 5 PATTERN_SUMMARY — `describe/it`, `unittest`, etc.).
3. Run `bash ~/.claude/hooks/lib/mcl-test-runner.sh green-verify`.
4. RED → fix the test or fix the code; re-run until GREEN.

## Soft applicability

Skip when `test_command` is unconfigured. Audit:

```
asama-15-not-applicable  reason=test_command-missing
```

(Plus v10 alias `asama-9-5-not-applicable`.)

## Audit emit (dual — v11 + v10 backward-compat)

```
mcl_audit_log "asama-15-start" "mcl-stop.sh" "scope=<files>"

mcl_audit_log "asama-15-end" "mcl-stop.sh" "tests_added=N green=true|false"

mcl_audit_log "asama-15-not-applicable" "mcl-stop.sh" "reason=<why>"
```

R8 cutover removes the v10 alias lines.

</mcl_phase>
