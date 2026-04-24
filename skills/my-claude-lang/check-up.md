<mcl_core>
MCL_CHECK_UP_MODE — the developer typed the literal keyword `mcl check-up`.
SKIP the entire MCL pipeline. Do NOT run Phase 1/spec/3/4/4.5/4.6/5.
Do NOT ask clarifying questions. Do NOT emit a spec block.
Do NOT trigger rule-capture flow.
This message is ONLY for running the MCL health check.

Execute these steps and respond ONLY in the developer's detected language
(default Turkish if unknown):

---

## Step 1 — Banner

Start the response with: `🌐 MCL <version> — mcl check-up`
(version from `session_start` in trace.log, or from the `🌐 MCL` banner
in the current session's activate hook output)

---

## Step 2 — Read the Step Catalog

Read `~/.claude/skills/my-claude-lang/all-mcl.md` via the Read tool.
This is the authoritative list of all MCL steps (STEP-01 through STEP-52).

---

## Step 3 — Locate the Project State Directory

STATE_DIR = `<cwd>/.mcl`  (or `$MCL_STATE_DIR` if set in environment)

Read the following files IN PARALLEL (all via the Read tool):

| File | What it provides |
|------|-----------------|
| `STATE_DIR/trace.log` | Deterministic hook events |
| `STATE_DIR/audit.log` | Operational event trail |
| `STATE_DIR/state.json` | Phase state machine fields |
| `STATE_DIR/log-current` | Pointer to the active session diary path |

Then read the diary path returned by `log-current` (if the file exists).

Also run these directory listings via Bash (read-only):
- `ls -1t STATE_DIR/specs/ 2>/dev/null | head -20`  (newest specs first)
- `ls -1t STATE_DIR/impact/ 2>/dev/null | head -20` (newest impacts first)

If any file is missing, note it as absent — do NOT fail the entire check-up.

---

## Step 4 — Scope Check-Up to the Latest Session

`trace.log` accumulates events across ALL sessions (never rotated).
Evaluate ONLY events from the LAST `session_start` line forward.

Procedure:
1. Split `trace.log` by lines containing `| session_start |`.
2. Take only the segment after the final `session_start` line.
3. All checks below operate on this segment only.
4. Count the total number of `session_start` events in the full
   `trace.log` — report this count in the report header.

---

## Step 5 — Evaluate Each Step

For every STEP-NN in `all-mcl.md` (in order, STEP-01 first):

Assign one of these status codes:

| Code | Meaning |
|------|---------|
| ✅ PASS | Pass condition is met by available evidence |
| ❌ FAIL | Pass condition NOT met AND step was not legitimately skipped |
| ⚠️ WARN | Pass condition partially met, or signal present but ambiguous |
| ⏭️ SKIP | Documented Skip condition applies — correct behavior |
| ❓ UNKNOWN | Log evidence insufficient to determine status |

**UNKNOWN vs SKIP distinction:**
- SKIP = a documented skip condition exists and the evidence matches it
- UNKNOWN = evidence would exist IF the step ran, but logs don't show it,
  AND no documented skip condition explains the absence

**Graceful degradation rules:**
- If `trace.log` is empty or absent → all trace-dependent steps = ❓ UNKNOWN
- If `audit.log` is empty or absent → all audit-dependent steps = ❓ UNKNOWN
- If `state.json` is absent → state-dependent steps = ❓ UNKNOWN
- If the session diary is unreadable → diary-dependent steps = ❓ UNKNOWN
- Missing files are NOT failures — they mean the project has not run MCL yet

---

## Step 6 — Write the Health Check Report

Write the following Markdown to `STATE_DIR/log/hc.md`
(overwrite if it already exists; create directory with `mkdir -p` if needed):

```markdown
# MCL Health Check — <ISO-8601 local datetime>

**Proje / Project:** `<cwd>`
**MCL Sürümü / Version (log):** <version from session_start>
**Oturum sayısı / Session count:** <N> session_start events in trace.log
**Son oturum / Latest session:** <timestamp of last session_start>
**Rapor / Report generated:** <ISO-8601>

---

## Özet / Summary

| Step | ID | Durum / Status | Not / Note |
|------|----|----------------|------------|
| STEP-01 | session-boundary | ✅ PASS | ... |
| STEP-02 | version-banner | ... | ... |
[... all 28 steps ...]

---

## Detay / Detail

### STEP-01: session-boundary
**Durum:** ✅ PASS
**Kanıt / Evidence:** audit.log line: "set | mcl-activate.sh | field=phase_review_state value=null"
**Not:** (any nuance)

[one block per step]

---

## Sorunlu Adımlar / Failing & Warning Steps

(Emit this section ONLY if any FAIL or WARN exists)

- **STEP-NN (id):** Ne bekleniyor / Expected: ... | Ne bulundu / Found: ...

---
*`mcl check-up` tarafından oluşturuldu · MCL <version> · <date>*
```

---

## Step 7 — Display Summary to Developer

After writing `hc.md`, show the developer:

1. The Summary table in their language.
2. The count of PASS / FAIL / WARN / SKIP / UNKNOWN.
3. The Failing & Warning Steps section (if any), with one-sentence
   localized explanations.
4. The path where `hc.md` was written.

---

## Step 8 — STOP

Do NOT proceed to Phase 4.5/4.6/5.
Do NOT call AskUserQuestion.
Do NOT suggest fixing any failing step in this turn.
`mcl check-up` is READ-ONLY. The developer reads the report and decides
whether to act in a separate session.

STOP RULE: the summary IS the entire response after the banner.
No phase report, no spec, no must-test list.
</mcl_core>
