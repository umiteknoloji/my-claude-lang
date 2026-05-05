<mcl_phase name="asama21-completeness">

# Aşama 21: Completeness Audit (was Aşama 13 in v10) — audits phases 1–20

Aşama 21 runs AFTER Aşama 20 (Localized Report) and BEFORE the
session closes. It reads the session's audit/state/trace files and
produces a machine-verifiable summary of which phases ran end-to-end
— with deep dives on Aşama 8 (test-first; was Aşama 7 in v10) and
the 8 quality phases Aşama 10–17 (was Aşama 9.1–9.8 sub-steps in v10).

## Critical Questions Aşama 13 Answers

- **Did each phase 1-12 actually complete?** Not just "model claimed
  done" — verified against audit.log signals.
- **Aşama 7 — were tests written? Was test_command run GREEN?** TDD
  compliance is the project's most-violated invariant; surface it.
- **Aşama 9 — did each sub-step (9.1-9.8) start, end, and apply
  auto-fix?** Aşama 9 is the auto-fix pipeline; partial completion
  ships vulnerable code.

## When Aşama 13 Runs

Immediately after Aşama 12 Localized Report. If Aşama 12 was no-op
(English session — nothing to translate), Aşama 13 still runs.
Completeness audit is the LAST output before the session closes.

## Procedure

1. Read `.mcl/audit.log` (Read tool) — full session audit trail.
2. Read `.mcl/state.json` (Read tool) — current state snapshot.
3. Read `.mcl/trace.log` (Read tool) — phase transitions in order.
4. Filter audits to current session (`session_start` boundary in
   trace.log defines the start timestamp).
5. For each phase 1-12, check the phase-completion signal (table
   below) and assign verdict ✓ / ⚠️ / ✗ / n/a.
6. Render the completeness report (markdown, in developer's language
   per the language rule — only the technical signals stay English).
7. Emit completion audit:
   ```
   bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
     mcl_audit_log asama-21-complete mcl-stop "phases_done=N phases_missing=M"'
   ```

## Phase Completion Signals (audit.log inspection)

| Aşama | Signal | Verdict rules |
|---|---|---|
| 1 Gather | `summary_confirmed` (trace) OR `phase_transition 1,4` | ✓ if either, ✗ otherwise |
| 2 Precision | `precision-audit asama2` audit | ✓ if found (skipped=true counts), ✗ otherwise |
| 3 Brief | `engineering-brief` audit OR (state.spec_hash≠null) | ✓ if either |
| 4 Spec | `asama-4-complete` OR (state.spec_approved=true) | ✓ if either |
| 5 Pattern | `pattern-summary-stored` OR `pattern-scan-cleared` | ✓ if found, n/a if empty project (state.pattern_files=[]) |
| 6a Build UI | `ui-flow-enter-build` audit | ✓ if state.ui_flow_active=true and signal present, n/a if ui_flow=false |
| 6b Review | state.ui_reviewed=true OR `ui-review-skip-block` | ✓ if reviewed, ⚠️ if loop-broken |
| 6c Backend | (transient — verified by post-spec writes) | n/a unless ui_flow=true |
| 7 Code+TDD | tdd-test-write vs tdd-prod-write counts + state.tdd_compliance_score | see deep dive below |
| 8 Risk | `asama-8-complete` audit | ✓ if found, ✗ if `asama-8-emit-missing` AND no complete |
| 9 Quality | per-substep audits + `asama-9-complete` | see deep dive below |
| 10 Impact | `asama-10-complete` audit | ✓ if found, n/a if no Aşama 7 code written |
| 11 Verify | `asama-11-complete` audit | ✓ if found, ✗ if Aşama 7 ran without it |
| 12 Localize | `localize-report asama12` audit | ✓ if found (skipped=true counts) |

## Aşama 7 Deep Dive (Test-First Verdict)

Inputs:
- `tdd-test-write` count (T)
- `tdd-prod-write` count (P)
- state.tdd_compliance_score (S)
- state.tdd_last_green (G — `{ts, result}` or null)

Render:

```
Aşama 7 — Test-First Development:
  Test files written:    <T>
  Prod files written:    <P>
  Compliance score:      <S>%  (preceded/total prod writes)
  test_command run:      <yes|no>  (last result: <GREEN|RED|never>)

Verdict:
  ✓ S=100 AND G.result=GREEN  → "Test-first kontratı doğru uygulandı"
  ⚠️ S=100 AND G missing      → "TDD ratio iyi ama test_command çalıştırılmamış"
  ⚠️ 0<S<100                  → "Kısmi TDD — bazı prod yazımları test'siz"
  ✗ P>0 AND T=0               → "ANTI-TDD — prod yazıldı, test yazılmadı"
  ✗ P=0                       → "Aşama 7 hiç çalışmadı (kod yazılmadı)"
```

## Aşama 9 Deep Dive (8 Sub-Steps)

For each N in 1..8, scan audit.log for:
- `asama-9-N-start` (or `aşama-9-N-start`) — start signal
- `asama-9-N-end` (or `aşama-9-N-end`) — end signal with counters
- `asama-9-N-not-applicable` — soft-skip with reason
- `asama-9-4-resolved` — security finding fix counter (sub-step 9.4)

Render:

```
Aşama 9 — Quality + Tests Sub-Step Detail:

| #   | Sub-step          | Start | End | Auto-fix counters         | Verdict |
|-----|-------------------|-------|-----|---------------------------|---------|
| 9.1 | Code Review       | <✓✗>  | <✓✗> | applied=N skipped=M       | <✓⚠️✗> |
| 9.2 | Simplify          | <✓✗>  | <✓✗> | applied=N                 | <✓⚠️✗> |
| 9.3 | Performance       | <✓✗>  | <✓✗> | applied=N                 | <✓⚠️✗> |
| 9.4 | Security          | <✓✗>  | <✓✗> | applied=N resolved=R      | <✓⚠️✗> |
| 9.5 | Unit tests        | <✓✗>  | <✓✗> | applied=N                 | <✓⚠️✗> |
| 9.6 | Integration tests | <✓✗>  | <✓✗> | applied=N                 | <✓⚠️✗> |
| 9.7 | E2E tests         | <✓✗>  | <✓✗> | applied=N                 | <✓⚠️✗> |
| 9.8 | Load tests        | <✓✗>  | <✓✗> | applied=N                 | <✓⚠️✗> |

Sub-step verdict rules:
  ✓ start AND end audits both present
  ✓ not-applicable audit present (soft skip with reason — counts as run)
  ⚠️ start present but end missing → incomplete
  ✗ no start AND no not-applicable → SKIPPED without audit (Aşama 9
    contract violated; v10.1.8 hard enforcement should have caught
    this — investigate)

Aşama 9 overall verdict:
  ✓ All 8 sub-steps ✓ AND asama-9-complete present
  ⚠️ Some sub-steps ⚠️ but asama-9-complete present (audit-claim
    mismatch — model emitted complete but skipped sub-steps)
  ✗ asama-9-complete missing OR any sub-step ✗
```

## Output Format

The full Aşama 13 output, in developer's language for prose
(English for technical signals like file paths, audit names, counts):

```
## Aşama 13 — Completeness Audit  (or localized: "Tamlık Denetimi")

### Faz Coverage
[12-row markdown table per signals above]

### Aşama 7 Detail (Test-First)
[Test-first verdict block from deep dive]

### Aşama 9 Detail (Quality + Tests)
[Sub-step verdict table from deep dive]

### Open Issues
- Aşama N ⚠️/✗: <one-line reason>
- ...
(Empty section omitted per CROSS-PHASE empty-section-omission rule)

### Audit Trail Reference
For full forensic detail: `cat .mcl/audit.log`
```

## Audit Emit on Completion (since v10.1.10)

After the report is rendered (and BEFORE the session closes), emit
the completion audit via Bash:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log asama-21-complete mcl-stop "phases_done=N phases_missing=M"'
```

Where N is the count of phases with ✓ verdict and M is the count
with ⚠️ or ✗ verdict (n/a phases not counted in either bucket).

**Why mandatory:** Same pattern as v10.1.5/v10.1.6 phase-completion
emits — provides a session-end marker that can be inspected by
future tooling, /mcl-checkup, or skip-detection. The emit also
serves as a self-attestation: "the model claims it produced the
completeness report." If the rendered report and the emit drift
(e.g., emit says phases_done=12 but report shows ✗ for Aşama 9),
that's a tractable discrepancy a developer can spot.

## Anti-Patterns

- **Renaming the phase** as "summary" or "verification" — Aşama 13 is
  COMPLETENESS, not coverage. Aşama 11 already did Spec Coverage.
- **Skipping Aşama 13 because "everything looks fine"** — the report
  IS the deliverable; "looks fine" is exactly what skip-detection
  exists to disprove.
- **Emitting `asama-13-complete` without rendering the report** — the
  audit emit reflects work done. False emit = false telemetry.
- **Reading audit.log via Bash grep instead of Read tool** — Aşama 13
  output should be reproducible by the developer; Read tool keeps
  the data inspection in conversation context.

## Skip Detection (Layer 3)

If Aşama 11 emitted (`asama-11-complete` present) but Aşama 13 did
not (`asama-13-complete` missing), Stop hook may emit
`asama-13-emit-missing` audit (visibility only, no block — this
phase is a meta-report, not a contract gate).

</mcl_phase>
