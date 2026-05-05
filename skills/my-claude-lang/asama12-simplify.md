<mcl_phase name="asama12-simplify">

# Aşama 12: Simplify (auto-fix on changed files)

Second of 8 dedicated quality phases (was sub-step `9.2` in v10
monolithic `asama9-quality-tests.md`). Auto-fix only — no
AskUserQuestion.

## When Aşama 11 Runs

Immediately after Aşama 10 (Code Review). Scope: files changed in
the current session.

## Detect

- Functions wrapping a single expression (trivial wrappers)
- Premature abstraction (interface with one impl)
- Duplicate logic across files
- Over-engineering (config layers no caller uses)

## Auto-fix scope

- Inline trivial wrappers
- Extract obvious duplicates into shared helpers IF the helper
  location is unambiguous

When auto-fix is ambiguous (e.g., multiple plausible helper
locations, abstraction may have value the static scan can't see),
write `asama-12-ambiguous` audit and skip.

## Audit emit (dual — v11 + v10 backward-compat)

Start / End / Not-applicable follow the same pattern as Aşama 10:

```
mcl_audit_log "asama-12-start" "mcl-stop.sh" "scope=<files>"
```

```
mcl_audit_log "asama-12-end" "mcl-stop.sh" "findings=N fixes=M skipped=K"
```

```
mcl_audit_log "asama-12-not-applicable" "mcl-stop.sh" "reason=<why>"
```

R8 cutover removes the v10 alias lines.

</mcl_phase>
