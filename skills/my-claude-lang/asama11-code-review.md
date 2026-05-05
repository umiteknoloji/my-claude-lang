<mcl_phase name="asama11-code-review">

# Aşama 11: Code Review (auto-fix on changed files)

Aşama 10 is the first of 8 dedicated quality phases (Aşama 10–17 in
the v11 architecture; previously the sub-step `9.1` of the monolithic
`asama9-quality-tests.md`). Each phase is now a top-level Aşama with
its own audit emits, but the underlying **discipline is unchanged**
from the v10 sub-step:

- No AskUserQuestion. Auto-fix only.
- Detect → fix-if-unambiguous → record audit → proceed.
- "Soft applicability" — when not applicable, write a `not-applicable`
  audit and skip silently.

## When Aşama 10 Runs

Immediately after Aşama 9 (Risk Review dialog complete) and BEFORE
Aşama 11 (Simplify). Scope: files changed in the current session
(Aşama 6 / Aşama 8).

## Detect

Pattern-rules compliance check (from Aşama 5 PATTERN_SUMMARY when
present):

- Naming convention violations
- Error handling pattern violations
- Test pattern violations

Plus general code-review findings:

- Dead code, unreachable branches
- Missing validations on parameters
- Error swallowing (catch blocks that ignore the exception)

## Auto-fix scope

Apply silently via Edit / MultiEdit / Write when the fix is
unambiguous:

- Renames to match Aşama 5 naming convention
- Removed dead code
- Added validation for already-typed inputs

When auto-fix is ambiguous (multiple valid fixes, no clear winner),
write `asama-11-ambiguous` audit and skip the fix. The earlier
Aşama 9 risk dialog already gave the developer a chance to surface
ambiguous items.

## Audit emit (dual — v11 + v10 backward-compat)

Start of phase:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log "asama-11-start" "mcl-stop.sh" "scope=<files>"'
```

End of phase:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log "asama-11-end" "mcl-stop.sh" "findings=N fixes=M skipped=K"'
```

Not applicable:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log "asama-11-not-applicable" "mcl-stop.sh" "reason=<why>"'
```

The `asama-9-1-*` lines are v10 backward-compat aliases. Existing
v10 enforcement helpers (mcl-stop.sh `asama-9-complete` auto-emit,
the open-severity gate) still observe these aliases. R8 cutover
(v11.0.0) removes the v10 lines from this skill — at that point
hook helpers will be retitled to scan `asama-10-*` only.

## Anti-patterns

- Asking the developer questions in Aşama 10 (auto-fix only).
- Skipping the phase without an audit entry (skip-detection requires
  the audit; the not-applicable audit is the correct skip path).
- Re-applying fixes the developer already declined in Aşama 9.

</mcl_phase>
