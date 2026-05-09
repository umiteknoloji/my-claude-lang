<mcl_phase name="asama11-code-review">

# Aşama 11: Kod İncelemesi (auto-fix on changed files)

Kod İncelemesi, kalite boru hattının ilk fazı (Aşama
11-14). Auto-fix only — askq yok,
dialog yok. Detect → fix-if-unambiguous → record audit → proceed.

"Soft applicability" — uygulanabilir değilse `not-applicable` audit yaz, sessizce atla.

## When Aşama 11 Runs

Immediately after Aşama 10 (Risk İncelemesi
dialog complete) and BEFORE Aşama 12 (Sadeleştirme).
Scope: files changed in the current session (Aşama 6 /
Aşama 9).

## Detect

Pattern-rules compliance check (from Aşama 5
PATTERN_SUMMARY when present):

- Naming convention violations
- Error handling pattern violations
- Test pattern violations

Plus general code-review findings:

- Dead code, unreachable branches
- Missing validations on parameters
- Error swallowing (catch blocks that ignore the exception)

## Auto-fix scope

Apply silently via Edit / MultiEdit / Write when the fix is unambiguous:

- Renames to match Aşama 5 naming convention
- Removed dead code
- Added validation for already-typed inputs

When auto-fix is ambiguous (multiple valid fixes, no clear winner),
write `asama-11-ambiguous` audit and skip the fix.
The earlier Aşama 10 risk dialog already gave the
developer a chance to surface ambiguous items.

## Audit emit

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

## Anti-patterns

- Asking the developer questions in Aşama 11 (auto-fix only).
- Skipping the phase without an audit entry (skip-detection requires
  the audit; the not-applicable audit is the correct skip path).
- Re-applying fixes the developer already declined in Aşama 10.

</mcl_phase>
