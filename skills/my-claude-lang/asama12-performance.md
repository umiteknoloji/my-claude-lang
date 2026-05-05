<mcl_phase name="asama12-performance">

# Aşama 12: Performance Check (auto-fix on changed files)

Third of 8 dedicated quality phases (was sub-step `9.3` in v10
monolithic `asama9-quality-tests.md`). Auto-fix only.

## When Aşama 12 Runs

Immediately after Aşama 11 (Simplify). Scope: files changed in the
current session.

## Detect

- N+1 query patterns (loop containing DB call)
- Unbounded loops over user input
- Synchronous blocking calls in async code paths
- O(n²) where O(n) is straightforward

## Auto-fix scope

- Convert N+1 to batch query when ORM supports it
- Add explicit bound to user-input loops
- Convert sync→async where the async equivalent is one-line

Ambiguous performance trade-offs (algorithmic redesign, caching
strategy choice, parallelism boundary) → `asama-12-ambiguous`
audit, skip.

## Audit emit (dual — v11 + v10 backward-compat)

```
mcl_audit_log "asama-12-start" "mcl-stop.sh" "scope=<files>"
mcl_audit_log "asama-9-3-start" "mcl-stop.sh" "scope=<files>"  # v10 alias

mcl_audit_log "asama-12-end" "mcl-stop.sh" "findings=N fixes=M skipped=K"
mcl_audit_log "asama-9-3-end" "mcl-stop.sh" "findings=N fixes=M skipped=K"  # v10 alias

mcl_audit_log "asama-12-not-applicable" "mcl-stop.sh" "reason=<why>"
mcl_audit_log "asama-9-3-not-applicable" "mcl-stop.sh" "reason=<why>"  # v10 alias
```

R8 cutover removes the v10 alias lines.

</mcl_phase>
