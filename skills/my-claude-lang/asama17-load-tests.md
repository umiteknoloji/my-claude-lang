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

mcl_audit_log "asama-17-end" "mcl-stop.sh" "scripts_added=N met_target=true|false"

mcl_audit_log "asama-17-not-applicable" "mcl-stop.sh" "reason=<why>"
```

After Aşama 17 ends, the quality pipeline (Aşama 10–17) is
complete. The downstream Aşama 18 (Impact Review) reads the per-phase
completion audits emitted by each of Aşama 10–17 to verify the chain
ran end-to-end; no monolithic completion signal is required in v11.

</mcl_phase>
