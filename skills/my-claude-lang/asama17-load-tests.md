<mcl_phase name="asama17-load-tests">

# Aşama 17: Load Tests (auto-fix on changed files)

Eighth and last of the dedicated quality phases (was sub-step `9.8`
in v10 monolithic `asama9-quality-tests.md`). Auto-fix only.

## When Aşama 17 Runs

Immediately after Aşama 16 (E2E Tests). Scope: throughput-sensitive
paths in changed files (queues, bulk processors, high-concurrency
endpoints).

## Procedure

1. Detect by code shape: explicit batching, async iterators over
   large inputs, endpoints declared in spec as throughput targets.
2. If detected and uncovered → WRITE k6 / locust / `ab` script.
3. Run script; assert latency/throughput matches the spec NFR if a
   `[performance:]` marker is present in the approved spec.

## Soft applicability

Skip when no throughput-sensitive path is detected. Audit:

```
asama-17-not-applicable  reason=no-throughput-path
```

## Audit emit (dual — v11 + v10 backward-compat)

```
mcl_audit_log "asama-17-start" "mcl-stop.sh" "scope=<files>"
mcl_audit_log "asama-9-8-start" "mcl-stop.sh" "scope=<files>"  # v10 alias

mcl_audit_log "asama-17-end" "mcl-stop.sh" "scripts_added=N met_target=true|false"
mcl_audit_log "asama-9-8-end" "mcl-stop.sh" "scripts_added=N met_target=true|false"  # v10 alias

mcl_audit_log "asama-17-not-applicable" "mcl-stop.sh" "reason=<why>"
mcl_audit_log "asama-9-8-not-applicable" "mcl-stop.sh" "reason=<why>"  # v10 alias
```

After Aşama 17 ends, the model emits the cumulative phase-9
completion audit (the v10 monolithic completion signal) so existing
v10 enforcement at mcl-stop.sh continues to operate:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log asama-9-complete mcl-stop \
  "applied=A skipped=S ambiguous=B na=N (v11 phases 10-17 split)"'
```

R8 cutover removes both the v10 alias lines AND this monolithic
`asama-9-complete` emit.

</mcl_phase>
