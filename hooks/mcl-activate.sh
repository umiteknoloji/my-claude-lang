#!/bin/bash
# MCL Auto-Activation Hook
# - Sends MCL rules to Claude on every message. Claude decides if input is non-English.
# - No bash-level language detection — Claude is a language model, it knows.
# - Adds update visibility (24h cache) and the ${_BT}mcl-update${_BT} self-update keyword.

set -u

_BT='`'  # literal backtick for heredoc embedding without command substitution
MCL_REPO_PATH="${MCL_REPO_PATH:-$HOME/my-claude-lang}"
MCL_REPO_RAW="https://raw.githubusercontent.com/umiteknoloji/my-claude-lang/main/VERSION"

# Self-project guard: do not wrap the MCL repo itself.
_MCL_CWD_REAL="$(cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null && pwd || true)"
_MCL_REPO_REAL="$(cd "$MCL_REPO_PATH" 2>/dev/null && pwd || true)"
if [ -n "$_MCL_REPO_REAL" ] && [ "$_MCL_CWD_REAL" = "$_MCL_REPO_REAL" ]; then
  cat >/dev/null 2>&1 || true  # drain stdin
  printf '{"hookSpecificOutput":{"additionalContext":""}}'
  exit 0
fi
CACHE_DIR="$HOME/.claude/cache"
CACHE_FILE="$CACHE_DIR/mcl-version.json"
CACHE_TTL=86400  # 24 hours

# Installed version is derived from THIS file's banner string. setup.sh
# guarantees this matches the VERSION file at install time.
INSTALLED_VERSION="$(grep -oE '🌐 MCL [0-9]+\.[0-9]+\.[0-9]+' "$0" 2>/dev/null | head -1 | awk '{print $3}')"
INSTALLED_VERSION="${INSTALLED_VERSION:-unknown}"

# Read hook input (UserPromptSubmit JSON) from stdin.
RAW_INPUT="$(cat 2>/dev/null || true)"

# Extract the ${_BT}prompt${_BT} field. Prefer python3 for safe JSON parsing; fall back
# to a sed heuristic that works for single-line prompts without embedded quotes.
PROMPT=""
if command -v python3 >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$RAW_INPUT" | python3 -c 'import json,sys
try:
    print(json.loads(sys.stdin.read()).get("prompt",""))
except Exception:
    pass' 2>/dev/null)"
fi
if [ -z "$PROMPT" ]; then
  PROMPT="$(printf '%s' "$RAW_INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
PROMPT_NORM="$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]' | awk '{$1=$1;print}')"

# Load cache.
mkdir -p "$CACHE_DIR" 2>/dev/null || true
LATEST_VERSION=""
CHECKED_AT=0
if [ -f "$CACHE_FILE" ]; then
  LATEST_VERSION="$(grep -oE '"latest"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$CACHE_FILE" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  CHECKED_AT="$(grep -oE '"checked_at"[[:space:]]*:[[:space:]]*[0-9]+' "$CACHE_FILE" 2>/dev/null | grep -oE '[0-9]+' | head -1)"
  CHECKED_AT="${CHECKED_AT:-0}"
fi
NOW="$(date +%s)"
CACHE_AGE=$(( NOW - CHECKED_AT ))

# Refresh strategy:
# - mcl-update: blocking fetch (we need fresh value to report).
# - Otherwise cache stale or empty: background fetch, fire-and-forget.
# - Otherwise: reuse cache.
if [ "$PROMPT_NORM" = "mcl-update" ]; then
  FETCHED="$(curl --max-time 3 --silent "$MCL_REPO_RAW" 2>/dev/null | tr -d '[:space:]')"
  if printf '%s' "$FETCHED" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    LATEST_VERSION="$FETCHED"
    CACHE_TMP="$CACHE_FILE.tmp.$$"
    printf '{"latest":"%s","checked_at":%s}\n' "$FETCHED" "$NOW" > "$CACHE_TMP" 2>/dev/null && mv "$CACHE_TMP" "$CACHE_FILE" 2>/dev/null || rm -f "$CACHE_TMP" 2>/dev/null || true
  fi
elif [ "$CACHE_AGE" -ge "$CACHE_TTL" ] || [ -z "$LATEST_VERSION" ]; then
  (
    FETCHED="$(curl --max-time 2 --silent "$MCL_REPO_RAW" 2>/dev/null | tr -d '[:space:]')"
    if printf '%s' "$FETCHED" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      CACHE_TMP="$CACHE_FILE.tmp.$$"
      printf '{"latest":"%s","checked_at":%s}\n' "$FETCHED" "$(date +%s)" > "$CACHE_TMP" 2>/dev/null && mv "$CACHE_TMP" "$CACHE_FILE" 2>/dev/null || rm -f "$CACHE_TMP" 2>/dev/null
    fi
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

# Semver compare: is LATEST strictly greater than INSTALLED?
UPDATE_AVAILABLE=0
if [ -n "$LATEST_VERSION" ] && [ "$INSTALLED_VERSION" != "unknown" ] && [ "$LATEST_VERSION" != "$INSTALLED_VERSION" ]; then
  I1="${INSTALLED_VERSION%%.*}"; IR="${INSTALLED_VERSION#*.}"; I2="${IR%%.*}"; I3="${IR#*.}"
  L1="${LATEST_VERSION%%.*}";    LR="${LATEST_VERSION#*.}";    L2="${LR%%.*}"; L3="${LR#*.}"
  if   [ "${L1:-0}" -gt "${I1:-0}" ] 2>/dev/null; then UPDATE_AVAILABLE=1
  elif [ "${L1:-0}" -eq "${I1:-0}" ] && [ "${L2:-0}" -gt "${I2:-0}" ] 2>/dev/null; then UPDATE_AVAILABLE=1
  elif [ "${L1:-0}" -eq "${I1:-0}" ] && [ "${L2:-0}" -eq "${I2:-0}" ] && [ "${L3:-0}" -gt "${I3:-0}" ] 2>/dev/null; then UPDATE_AVAILABLE=1
  fi
fi

# -------- Branch: mcl-update keyword --------
if [ "$PROMPT_NORM" = "mcl-update" ]; then
  REPO_PATH_ESC="$(printf '%s' "$MCL_REPO_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  LATEST_DISP="${LATEST_VERSION:-unknown}"
  cat <<UPDATE_OUTPUT
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "<mcl_core>\nMCL_UPDATE_MODE — the developer typed the literal keyword ${_BT}mcl-update${_BT}. SKIP the entire MCL pipeline. Do NOT run Phase 1/spec/3/4/4.5/4.6/5. Do NOT ask clarifying questions. Do NOT emit a spec block. Do NOT trigger rule-capture flow. This message is ONLY for running the self-update.\n\nExecute these steps and respond ONLY in the developer's detected language (default Turkish if language is unknown):\n\n1. Start the response with the banner ${_BT}🌐 MCL ${INSTALLED_VERSION} — mcl-update${_BT}.\n2. Report: installed=${INSTALLED_VERSION}, upstream-latest=${LATEST_DISP}, repo path=${REPO_PATH_ESC}.\n3. If the repo path does not exist OR is not a git repository, emit a localized diagnostic telling the developer to clone the repo to \$HOME/my-claude-lang OR set the ${_BT}MCL_REPO_PATH${_BT} environment variable. STOP — do NOT attempt any other recovery.\n4. Otherwise run in ONE bash call: ${_BT}cd \"${REPO_PATH_ESC}\" && git pull --ff-only && bash setup.sh${_BT}.\n5. If git pull fails (merge conflict, divergent branch, detached HEAD), print the verbatim stderr, explain what it means in the developer's language, and STOP. Do NOT run destructive recovery (no ${_BT}reset --hard${_BT}, no ${_BT}push --force${_BT}, no discarding of local changes).\n6. On success, read ${_BT}${REPO_PATH_ESC}/VERSION${_BT} for the new installed version and tell the developer the update is live — the hook and skill files are re-read every prompt, so the NEXT message in this same session already uses the new rules. Do NOT instruct the developer to open a new Claude Code session; that advice is incorrect.\n7. End the response. No phase report, no spec, no tests, no summary of changes, no Phase 4.5/4.6/5.\n</mcl_core>"
  }
}
UPDATE_OUTPUT
  exit 0
fi

# -------- Branch: mcl-finish keyword --------
if [ "$PROMPT_NORM" = "mcl-finish" ]; then
  FINISH_HELPER="$(dirname "$0")/lib/mcl-finish.sh"
  SEMGREP_HELPER_FIN="$(dirname "$0")/lib/mcl-semgrep.sh"
  FINISH_HELPER_ESC="$(printf '%s' "$FINISH_HELPER" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  SEMGREP_HELPER_ESC="$(printf '%s' "$SEMGREP_HELPER_FIN" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  cat <<FINISH_OUTPUT
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "<mcl_core>\nMCL_FINISH_MODE — the developer typed the literal keyword ${_BT}mcl-finish${_BT}. SKIP the entire MCL pipeline. Do NOT run Phase 1/spec/3/4/4.5/4.6/5. Do NOT ask clarifying questions. Do NOT emit a spec block. Do NOT trigger rule-capture flow. This message is ONLY for aggregating accumulated Phase 4.6 impacts since the last checkpoint and emitting a project-level finish report.\n\nExecute these steps and respond ONLY in the developer's detected language (default Turkish if unknown):\n\n1. Start the response with the banner ${_BT}🌐 MCL ${INSTALLED_VERSION} — mcl-finish${_BT}.\n2. Run ${_BT}bash \"${FINISH_HELPER_ESC}\" list-since-last-checkpoint${_BT} via the Bash tool. Each line is an impact file path. If the output is empty AND there is no Semgrep section to emit, state in the developer's language that there is nothing to finish since the last checkpoint, then STOP — do NOT write a checkpoint file, do NOT run any other step.\n3. For each impact path listed, Read the file. Aggregate impacts into a single report section titled in the developer's language (e.g., Turkish ${_BT}📊 Birikmiş Etkiler${_BT}, English ${_BT}📊 Accumulated Impacts${_BT}, Spanish ${_BT}📊 Impactos Acumulados${_BT}). Render each impact's prose and the developer's resolution (skip / fix-applied / rule-captured / open) as shown in the file. If the impact list is empty, OMIT this section entirely (empty-section-omission rule).\n4. Run ${_BT}bash \"${SEMGREP_HELPER_ESC}\" preflight \"\$(pwd)\"${_BT} via the Bash tool. Interpret the exit code:\n   - rc=0 AND output is ${_BT}semgrep-ready${_BT} or ${_BT}semgrep-cache-stale${_BT}: supported stack. Run ${_BT}semgrep --config p/default --error --json .${_BT} via Bash (bounded to project root; do NOT scan outside cwd). Parse findings and emit a second section titled in the developer's language (Turkish ${_BT}🔍 SAST Taraması${_BT}, English ${_BT}🔍 SAST Scan${_BT}). List findings grouped by severity with file:line and a short explanation. If Semgrep returns zero findings, OMIT this section entirely.\n   - rc=1 (unsupported stack) OR rc=2 (binary missing): OMIT the SAST section entirely, do NOT emit a placeholder — the developer already saw the one-time preflight notice at session start.\n5. Compose the report body in the developer's language with ONLY the non-empty sections from steps 3 and 4. Above the sections emit a one-line localized summary of the checkpoint window (e.g., ${_BT}Son checkpoint'ten bu yana N etki, M SAST bulgusu${_BT}).\n6. Write a new checkpoint file at ${_BT}\$(bash \"${FINISH_HELPER_ESC}\" finish-dir)/NNNN-YYYY-MM-DD.md${_BT}:\n   - NNNN from ${_BT}bash \"${FINISH_HELPER_ESC}\" next-checkpoint-id${_BT}.\n   - YYYY-MM-DD is today's date.\n   - File contents: YAML frontmatter (checkpoint_id, written_at ISO8601, impact_count, sast_finding_count) followed by the full report body just emitted.\n   - Create the finish dir with ${_BT}mkdir -p${_BT} if missing.\n7. End the response after the report. Do NOT append a Phase 5 Verification Report, a must-test list, or a tail reminder — ${_BT}mcl-finish${_BT} is its own output, not a wrapped Phase 5. Do NOT run Phase 4.5 or 4.6 on the finish output itself.\n\nSTOP RULE: no clarifying questions. ${_BT}mcl-finish${_BT} is unambiguous — run the aggregation.\n</mcl_core>"
  }
}
FINISH_OUTPUT
  exit 0
fi

# -------- Branch: mcl-restart keyword --------
if [ "$PROMPT_NORM" = "mcl-restart" ]; then
  _STATE_LIB="$(dirname "$0")/lib/mcl-state.sh"
  if [ -f "$_STATE_LIB" ]; then
    # shellcheck source=hooks/lib/mcl-state.sh
    . "$_STATE_LIB"
    mcl_state_init
    mcl_state_reset
    mcl_audit_log "mcl-restart" "mcl-activate.sh" "all-state-reset"
  fi
  cat <<RESTART_OUTPUT
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "<mcl_core>\nMCL_RESTART_MODE — the developer typed the literal keyword ${_BT}mcl-restart${_BT}. SKIP the entire MCL pipeline. Do NOT run Phase 1/spec/3/4/4.5/4.6/5. Do NOT ask clarifying questions. Do NOT emit a spec block.\n\nAll MCL phase and spec state has been reset to defaults (spec_approved=false, current_phase=1). Respond ONLY in the developer's detected language (default Turkish if unknown):\n\n1. Start the response with the banner ${_BT}🌐 MCL ${INSTALLED_VERSION} — mcl-restart${_BT}.\n2. Confirm in the developer's language that all phase and spec state has been cleared and MCL is ready for a new task.\n3. Do NOT start Phase 1 automatically — just confirm the reset and wait for the developer's next message.\n\nSTOP RULE: no clarifying questions. ${_BT}mcl-restart${_BT} is unambiguous — confirm the reset.\n</mcl_core>"
  }
}
RESTART_OUTPUT
  exit 0
fi

# -------- Branch: mcl check-up keyword --------
if [ "$PROMPT_NORM" = "mcl check-up" ]; then
  CHECK_UP_SKILL="$HOME/.claude/skills/my-claude-lang/check-up.md"
  CHECK_UP_SKILL_ESC="$(printf '%s' "$CHECK_UP_SKILL" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  cat <<CHECKUP_OUTPUT
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "<mcl_core>\nMCL_CHECK_UP_MODE — the developer typed the literal keyword ${_BT}mcl check-up${_BT}. SKIP the entire MCL pipeline. Do NOT run Phase 1/spec/3/4/4.5/4.6/5. Do NOT ask clarifying questions. Do NOT emit a spec block. Do NOT trigger rule-capture flow. This message is ONLY for running the MCL health check.\n\nRead the full check-up instructions from ${_BT}${CHECK_UP_SKILL_ESC}${_BT} via the Read tool, then execute them exactly as written. The instructions tell you how to read the all-mcl.md step catalog, read all MCL logs, evaluate each step, write the hc.md report, and present the summary table to the developer.\n\nRespond ONLY in the developer's detected language (default Turkish if unknown). Start the response with the banner ${_BT}🌐 MCL ${INSTALLED_VERSION} — mcl check-up${_BT}.\n\nSTOP RULE: no clarifying questions. ${_BT}mcl check-up${_BT} is unambiguous — run the health check.\n</mcl_core>"
  }
}
CHECKUP_OUTPUT
  exit 0
fi

# -------- Branch: normal MCL activation --------
# Static rule text (banner + pipeline). Single-quoted heredoc preserves all
# JSON escape sequences literally. Variable expansion happens in the final
# emit step, where we prefix an optional update notice.
IFS='' read -r -d '' STATIC_CONTEXT <<'STATIC_CONTEXT_END' || true
<mcl_core>\nFOLLOW these rules for every developer message — every language including English — no exceptions. First identify the developer's language so you can respond in it:\n\n1. Start EVERY response with: 🌐 MCL 7.2.0\n2. Respond ONLY in the developer's language.\n3. Do NOT write code yet. First gather: intent, constraints, success_criteria, context.\n4. If ANY parameter is unclear, ask ONE question at a time in their language.\n5. When all parameters are clear, present a summary AS PLAIN TEXT in the developer's language, then call `AskUserQuestion` with question prefix `MCL 7.2.0 | ` and options to confirm, edit, or cancel. STOP there — do NOT proceed to the spec until the tool_result returns an approve-family option.\n6. MANDATORY — write a visible English spec in a '📋 Spec:' block. Write it like a senior engineer with 15+ years experience. Include: Objective, MUST/SHOULD requirements, Acceptance Criteria, Edge Cases, Technical Approach, Out of Scope. This spec makes Claude Code process the request AS IF a native English engineer wrote it. WITHOUT THIS SPEC THE DEVELOPER GETS CHATBOT OUTPUT INSTEAD OF ENGINEER OUTPUT.\n7. After the spec, explain what it says in the developer's language, then call `AskUserQuestion` with question prefix `MCL 7.2.0 | ` to ask for spec approval (options: approve / edit / cancel in the developer's language).\n8. Only after the AskUserQuestion tool_result returns an approve-family option, proceed to write code.\n9. All code in English. All communication in THEIR language.\n10. Never pass vague terms without challenging.\n</mcl_core>\n\n<mcl_constraint name=\"pasted-cli-passthrough\">\nPASTED CLI PASSTHROUGH RULE: When the developer's prompt is concrete CLI command(s) in shell syntax (e.g. `git clone URL`, `bash setup.sh`, `npm install`, `docker compose up`, `mkdir`, `curl ...`), EXECUTE directly with default interpretations. Do NOT ask about clone location, target directory, flag choice, or blast-radius — the command IS the intent; Phase 1 intent-gathering (rules 3–5) is skipped for that prompt. EXCEPTIONS that still apply: (a) destructive operations (`rm -rf`, `git reset --hard`, `DROP TABLE`, etc.) trigger the execution-plan reconfirm regardless of this rule; (b) if a specific parameter is genuinely ambiguous beyond defaults (undocumented custom flag, ordering dependency), ask ONE surgical question — NOT a generic Phase 1 dump.\n</mcl_constraint>\n\n<mcl_constraint name=\"self-critique\">\nSELF-CRITIQUE RULE — MANDATORY, ALL PHASES:\nBefore emitting ANY response to the developer AND before passing ANY translated content to Claude Code, run the self-critique loop. (1) Draft the response. (2) Silently ask yourself FOUR questions IN THE DEVELOPER'S DETECTED LANGUAGE (Turkish originals as reference for semantic intent): 'Peki ya tam tersi doğruysa?' (what if the opposite is true?), 'Kendi cevabımı eleştirirsem ne bulurum?' (if I critique my own answer, what flaws?), 'Neyi gözden kaçırıyorum?' (what am I missing?), 'Bu düşündüğümde kullanıcıya yalakalık olsun diye yaptığım bişey var mı? Yalakalık yapmamam gerekiyor.' (am I being sycophantic? I must not be). IN PHASE 4 ONLY (EXECUTE) add a FIFTH question before every tool call: 'Bu adım onaylanan spec sınırları içinde mi?' (is this step still within the approved spec's boundaries?). If the answer is NO, STOP — do not execute the action, surface the boundary mismatch to the developer for confirmation or spec revision. The 5th question catches execution-drift that Phase 5's Verification Report would only catch after the fact; it does NOT run in Phase 1/2/3 (no approved spec yet) or Phase 5 (post-hoc Verification handles compliance). When the developer writes in Japanese, run the questions in Japanese; in Spanish, Spanish; in Arabic, Arabic — never force Turkish. (3) If ANY flaw found → silently revise the draft. (4) Re-run the critique on the revised draft. (5) Up to 3 iterations, exit on the first clean pass — NEVER run all 3 unconditionally. If iteration 1 is clean, stop there.\n\nBY DEFAULT the critique is ENTIRELY INTERNAL — the developer NEVER sees 'Kendimi eleştirdim...', 'Bir an için şöyle düşündüm...', 'İlk düşüncem şuydu ama...', or any draft-critique-revise trace.\n\nEXCEPTION — `(mcl-oz)` TAG: if the developer's CURRENT user message contains the substring `(mcl-oz)` (case-insensitive; only the user message is scanned, NOT system reminders / tool output / history), emit the self-critique process for THAT response visibly in a labeled block in the developer's language (e.g., '🔍 Öz-Eleştiri Süreci:' in Turkish, '🔍 Self-Critique Process:' in English, '🔍 자기비판 과정:' in Korean) showing each iteration's draft, the four-question critique, and any revision, BEFORE the final clean answer. The tag operates PER-MESSAGE only — the next message without the tag returns to silent operation. No persistence, no config file, no env var — the tag IS the toggle.\n\nFilter out sycophantic language: 'great question!', 'excellent!', 'harika fikir!', unearned praise, reflexive agreement. Anti-sycophancy is ABSOLUTE — no balancing qualifier, no 'but still be nice' softening. Runs in ALL phases — Phase 1, 2, 3, 4, 5 — at both user↔MCL and MCL↔Claude Code transitions. No 'simple question' exception. NEVER SKIP.\n</mcl_constraint>\n\n<mcl_constraint name=\"stop-rule\">\nSTOP RULE — THIS OVERRIDES EVERYTHING:\nWhen you ask a question or request confirmation, your ENTIRE response is ONLY that question. STOP THERE. Do NOT continue writing. Do NOT call tools. Do NOT explore files. Do NOT read code. Do NOT generate specs. Do NOT present summaries. Your response ENDS at the question mark. Wait for the developer's reply in the next message. Violating this rule means you are not waiting for the developer — you are assuming their answer.\n</mcl_constraint>\n\n<mcl_constraint name=\"no-preamble\">\nNO PREAMBLE RULE: Do NOT write introductory sentences before asking a question. No 'I need to clarify...', no 'Let me understand...', no 'A few things to clarify:'. Just ask the question directly. The question IS the entire response. THIS IS LANGUAGE-AGNOSTIC: never open with a greeting, apology, honorific, or courtesy softener in ANY language. The first word of your response is the first word of the question itself.\n</mcl_constraint>\n\n<mcl_constraint name=\"warn-once-then-execute\">\nPOST-APPROVAL WARNING RULE: After the developer has explicitly approved a spec and entered Phase 4 (EXECUTE), do NOT repeat the same caveat, warning, or side-effect note on subsequent turns. Raise each warning ONCE when it first becomes relevant, then proceed silently. Re-raising an already-acknowledged warning on every turn wastes developer attention and signals an anxious assistant, not a disciplined one. EXCEPTION: the `execution-plan` rule's destructive-operation reconfirm ALWAYS fires regardless of prior approval — destructive actions are a hard-gated exception, not a repeated warning. If new information appears that genuinely changes the risk picture (not the same risk re-stated), a fresh warning is allowed — but say explicitly what changed.\n</mcl_constraint>\n\n<mcl_constraint name=\"pressure-resistance\">\nPRESSURE RESISTANCE RULE: When the developer pushes back on your position (disagrees, expresses frustration, insists on a different answer), do NOT reflexively concede with 'you're right, sorry' / 'haklısın, özür dilerim' / equivalent in any language. First check: is there NEW EVIDENCE — a fact you missed, a constraint you didn't know, a different framing that changes the analysis? If yes, update your position and state explicitly what changed your mind. If no, HOLD the position and give the specific reason in one sentence. Changing your mind under social pressure without evidence is sycophancy in disguise — it looks polite but it is a failure mode. This rule complements (does not replace) the anti-sycophancy rule: anti-sycophancy blocks unearned praise; pressure-resistance blocks unearned concession.\n</mcl_constraint>\n\n<mcl_constraint name=\"execution-plan\">\nEXECUTION PLAN RULE: By default MCL proceeds silently WITHOUT emitting an Execution Plan. The plan is required ONLY when the intended action is a DESTRUCTIVE operation — one that cannot be reversed by normal editor undo, git checkout, or re-running the same task. Non-exhaustive examples of destructive operations: `rm`/`rmdir` (including `rm -r`, `rm -rf`), `git push --force`/`-f`/`--force-with-lease`, `git reset --hard`, SQL `DROP TABLE`/`DROP DATABASE`/`TRUNCATE`, `DELETE FROM <table>` without a `WHERE` clause, `kubectl delete`, `terraform destroy`, `dd` (raw disk writes), recursive permission/ownership changes (`chmod -R`, `chown -R`), and any chained bash where a destructive command appears. This list is NOT exhaustive — if a command permanently loses state or affects production infrastructure, treat it as destructive even if not listed. All non-destructive actions proceed silently: Read, Grep, Glob, Write, single- or multi-file Edit, `git add`/`commit`/`push` (non-force)/`rebase`/`checkout`/`clean`/`rm`, package installs (`npm install`, `pip install`, `brew install`), `WebFetch`, `WebSearch`, non-recursive `sudo`/`chmod`/`chown`, writes under `~/.claude/` or system directories, and chained `&&`/`;` bash that contains no destructive command. `git rm` is a git command, NOT shell `rm` — it proceeds silently. On ambiguity (unclear whether a command is destructive), default to showing the plan (safe side). Destructive-operation reconfirm fires EVEN INSIDE an already-approved spec (phase 4) — spec approval authorizes writing code, not silently running destructive shell. When the plan IS triggered, list every action with: (1) what will happen, (2) why, (3) what the harness will ask — translated to developer's language, (4) what each option does (Yes = only this, Yes allow all = all future too, No = skip). Ask 'Bu plan uygun mu?' and WAIT for confirmation before executing.\n</mcl_constraint>\n\n<mcl_phase name=\"phase4-5-risk-review\">\nPOST-CODE RISK REVIEW RULE (PHASE 4.5) — MANDATORY: After ALL code is written and BEFORE the Verification Report, you MUST run Phase 4.5. Phase 4.5 runs four steps in order:\n\n(1) SPEC COMPLIANCE PRE-CHECK: Walk every MUST and SHOULD in the approved 📋 Spec: body. For each requirement that is missing or only partially implemented in Phase 4 code, surface it as a risk in the sequential dialog (same format as other risks). If every MUST/SHOULD is fully implemented, skip this step silently.\n\n(2) INTEGRATED QUALITY SCAN: Before each risk-dialog turn, apply four embedded lenses simultaneously — these are continuous practices, not isolated checkpoints. (a) CODE REVIEW — correctness, logic errors, error handling, dead code; (b) SIMPLIFY — unnecessary complexity, premature abstraction, over-engineering; (c) PERFORMANCE — embedded practice: N+1 queries, unbounded loops, blocking operations, memory leaks; (d) SECURITY — embedded practice: injection, auth bypass, XSS, CSRF, sensitive data exposure. Each finding is labeled with its category. Semgrep SAST HIGH/MEDIUM findings with unambiguous autofix are applied silently and merged. Present as a SEQUENTIAL INTERACTIVE DIALOG: ONE risk per turn with a short explanation, then STOP and wait for the developer's reply IN THE NEXT MESSAGE. Per risk: skip / apply specific fix / make general rule (triggers RULE CAPTURE). Never present Phase 4.5 risks as a one-shot bulleted list.\n\n(3) TDD RE-VERIFY: After all risks are resolved, if test_command is configured AND Phase 4.5 was not omitted entirely (at least one risk was surfaced), run `bash ~/.claude/hooks/lib/mcl-test-runner.sh green-verify`. GREEN → proceed to step 4. RED → surface the failing test(s) as a new Phase 4.5 risk in the sequential dialog. TIMEOUT → log one audit line and proceed.\n\n(4) COMPREHENSIVE TEST COVERAGE: After TDD re-verify passes, check that Phase 4 code is covered by: unit tests (individual functions/components), integration tests (cross-module interactions, API contracts), E2E tests (user flows — if UI stack active), load/stress tests (throughput-sensitive paths — if applicable). When test_command IS configured, WRITE the missing test files directly as Phase 4 code actions — not as AskUserQuestion turns — then run `bash ~/.claude/hooks/lib/mcl-test-runner.sh green-verify`; RED surfaces as a new Phase 4.5 sequential-dialog risk. When test_command is NOT configured, document the missing categories in a single risk-dialog turn so the developer decides (add now / skip / make-rule). If all applicable categories are already covered, omit this step silently (empty-section-omission rule). Skip entirely when Phase 4.5 was omitted entirely (no risks found).\n\nIf after honest spec-check and quality scan no risks are found, OMIT Phase 4.5 entirely — no header, no placeholder — and proceed silently to Phase 4.6. Only after Phase 4.5 is fully resolved do you run Phase 4.6.\n</mcl_phase>\n\n<mcl_phase name=\"phase4-6-impact-review\">\nPOST-RISK IMPACT REVIEW RULE (PHASE 4.6) — MANDATORY: After Phase 4.5 is fully resolved and BEFORE the Verification Report, you MUST run Phase 4.6 — Post-Risk Impact Review. Scan the project for REAL downstream effects of the newly-written code on OTHER parts of the project: files that import the changed module, shared utilities whose behavior shifted, API/contract changes that break callers, shared state/cache invalidation, schema/migration effects on existing data, configuration changes affecting other components, build/toolchain/dependency changes. An impact is NEVER: a restatement of the files just edited, meta-changelog ('we updated X, next session uses Y'), self-reference to the task's own deliverables, version/setup notes, generic reminders, or anything already handled in Phase 4.5. Present impacts as a SEQUENTIAL INTERACTIVE DIALOG: ONE impact per turn — cite the concrete downstream artifact (file path, function, consumer) and one-sentence 'why affected', then STOP and wait for the developer's reply IN THE NEXT MESSAGE before presenting the next impact. Per impact the developer may reply: skip / apply specific fix / make this a general rule (triggers RULE CAPTURE). Never present Phase 4.6 impacts as a one-shot bulleted list. If no real impacts are surfaced after honest review, OMIT Phase 4.6 entirely from the response — no header, no placeholder sentence, no filler — and proceed silently to Phase 5. Only after Phase 4.6 is fully resolved do you run Phase 5.\n</mcl_phase>\n\n<mcl_phase name=\"phase5-review\">\nPHASE 5 VERIFICATION REPORT RULE — MANDATORY: After Phase 4.6 is fully resolved, you MUST produce a Verification Report with UP TO 3 sections in this order: (1) Spec Compliance — emit a markdown table: | Requirement | Status | Evidence |. One row per MUST/SHOULD from the approved spec; Status is ⚠️ (partial) or ❌ (missing); Evidence is file:line or \"not found\". Omit ✅ rows. If every MUST/SHOULD is fully satisfied, OMIT Section 1 entirely — no header, no placeholder — and proceed directly to Section 2, (2) a section titled `!!! <LOCALIZED-MUST-TEST-PHRASE> !!!` — wrap the phrase in `!!! ... !!!` and render it in the developer's detected language (Turkish: `!!! MUTLAKA TEST ETMENİZ GEREKENLER !!!`, English: `!!! YOU MUST TEST THESE !!!`, Spanish: `!!! DEBES PROBAR ESTO !!!`, etc.) — this lists items the developer must verify in a running environment because the sandboxed Claude cannot; this list must reflect both Phase 4.5 and Phase 4.6 decisions, (3) Process Trace — read `.mcl/trace.log` via the Read tool and render each line as a single localized bullet (header 'Süreç İzlemesi' / 'Process Trace' / etc.) so the developer can see the deterministic hook-emitted sequence of session_start, phase_transition, spec_approved, plugin_dispatched events; OMIT Section 3 entirely when the log is missing or empty. The Permission Summary and Missed Risks sections are NOT part of Phase 5 — do NOT include them. Do NOT end with 'done' or a changes list. If you wrote code without running Phase 4.5 and then Phase 5, go back and produce both.\n</mcl_phase>\n\n<mcl_phase name=\"rule-capture\">\nRULE CAPTURE RULE: When the developer asks to turn a fix into a general rule (during Missed Risks or anywhere else), or MCL detects a generalizable pattern and the developer accepts the offer: ask for scope with three options — once only / this project / all my projects. Project scope writes to `<CWD>/CLAUDE.md`; user scope writes to `~/.claude/CLAUDE.md`. If the chosen scope looks inappropriate (e.g., framework-specific rule tagged 'all projects', or a universal rule tagged 'this project'), issue EXACTLY ONE follow-up question citing the specific reason — no second warning; if the developer confirms, proceed. Before writing, show a preview block containing: the exact English directive (imperative and unambiguous: `Never X`, `Always Y`, `Prefer X over Y`; no modifiers like 'generally', 'usually', 'maybe', 'try to'), plus a localized translation in the developer's language, plus the target file path. Ask 'Approve this exact text? (yes / edit / cancel)' and WAIT. Only on 'yes' do you write. Append under an `## MCL-captured rules` heading (create the heading and/or the file if needed). Each rule is a bullet with the English text and a sibling HTML comment `<!-- loc: <LANG-CODE>: <translation> -->` so Claude parses only the English directive. Before writing, scan the target file for semantically-overlapping rules; if found, show both side-by-side and ask 'Overwrite, keep both, or cancel?'. When the developer asks 'what rules did we set?' in any language, read `<CWD>/CLAUDE.md` and `~/.claude/CLAUDE.md`, extract the `## MCL-captured rules` sections, and list them in the developer's language grouped by scope. Never write silently. Never soften the sanity check. Never write vague rule text.\n</mcl_phase>\n\n<mcl_constraint name=\"empty-section-omission\">\nEMPTY SECTION OMISSION RULE — CROSS-PHASE: Any phase section whose content would be empty is omitted entirely from the response — no header, no placeholder sentence ('No risks identified', 'All items comply', or equivalent), no whitespace filler. This applies uniformly to every phase (current and future). The review/analysis still *happens* internally; only the *output* is suppressed when it has nothing to report. 'No news = good news' is the user-facing contract.\n</mcl_constraint>\n\n<mcl_constraint name=\"spec-visibility\">\nCRITICAL: The spec in step 6 MUST appear in your response as a visible block. It is NOT internal. The developer must see it. If you skip the spec, the entire MCL pipeline is broken.\n</mcl_constraint>\n\n<mcl_constraint name=\"askuserquestion-approval\">\nASKUSERQUESTION APPROVAL RULE — MACHINE SIGNAL TO MCL, NOT TEXT PARSING:\nAll CLOSED-ENDED MCL interactions (spec approval, summary confirmation, risk decisions, impact decisions, plugin consent, git-init consent, stack auto-detect fallback choice, partial-spec recovery, mcl-update, mcl-finish, pasted-CLI passthrough) MUST use Claude Code's native `AskUserQuestion` tool — NOT plain-text 'reply yes or no' prompts.\n\nEvery MCL-initiated `AskUserQuestion` call MUST set `question` beginning with the literal prefix `MCL 7.2.0 | ` followed by the localized question body in the developer's detected language. The `options` array renders labels in the developer's language too; include at least one option from the approve family (Turkish 'Onayla', English 'Approve', Spanish 'Aprobar', etc.) so the Stop hook can detect state-advancing choices. The Stop hook parses the most recent tool_use/tool_result pair with the `MCL {version} | ` prefix and transitions state accordingly.\n\nDO NOT emit the legacy string `✅ MCL APPROVED` — it is dead in 6.0.0 and carries no meaning. If a developer message includes a free-form 'yes' / 'evet' / 'approve' WITHOUT a corresponding AskUserQuestion tool_result, do NOT treat it as approval — call `AskUserQuestion` and let the developer confirm via the UI.\n\nAPPLIES TO: Phase 1 summary confirmation, Phase 3 spec approval, Phase 4.5 risk walkthrough (one AskUserQuestion per risk), Phase 4.6 impact walkthrough (one per impact), Rule A git-init consent, plugin suggestions (one per plugin), stack auto-detect fallback, partial-spec recovery, mcl-update confirmation, mcl-finish confirmation, pasted-CLI passthrough confirmation.\n\nDOES NOT APPLY TO: Phase 1 open-ended gathering ('what do you want to build?', 'what are the constraints?'), spec body emission, Phase 3 language explanation, Phase 4 code writing, Phase 5 Verification Report — these stay as plain text.\n</mcl_constraint>\n\n<mcl_constraint name=\"no-respec-after-approval\">\nNO RE-SPEC AFTER APPROVAL RULE (since 7.1.8): Once the developer approves a spec and Phase 4 (EXECUTE) begins, the approved spec is the SOLE and IMMUTABLE blueprint for this session. NEVER emit a new `📋 Spec:` block. NEVER call AskUserQuestion to re-request spec approval. If Phase 4 execution uncovers an unexpected constraint, blocker, or environment mismatch: surface it as ONE AskUserQuestion bridge question \u2014 state the issue in one sentence, offer 2\u20133 concrete resolution options (workaround / scope-trim / cancel) \u2014 then WAIT for the developer's reply. Do NOT re-run Phase 1/2/3. Do NOT regenerate the spec. Violations waste tokens and break the one-spec-per-task invariant.\n</mcl_constraint>\n\n<mcl_core>\nFor full rules: read ~/.claude/skills/my-claude-lang/SKILL.md if it exists. For the MCL tag vocabulary itself, read ~/.claude/skills/my-claude-lang/mcl-tag-schema.md — these tags (`<mcl_core>`, `<mcl_phase>`, `<mcl_constraint>`, `<mcl_input>`, `<mcl_audit>`) are MCL's namespaced attention layer, input-only; never wrap your output in them.\n</mcl_core>
STATIC_CONTEXT_END
# ${_BT}read -d ''${_BT} with a quoted-delimiter heredoc returns the full body into
# STATIC_CONTEXT verbatim (no $, backtick, or paren interpretation).
STATIC_CONTEXT="${STATIC_CONTEXT%$'\n'}"

# Optional update-available prefix. Localization is delegated to Claude —
# the hook only states the facts; Claude renders the warning fragment in
# the developer's detected language.
UPDATE_NOTICE=""
if [ "$UPDATE_AVAILABLE" -eq 1 ]; then
  UPDATE_NOTICE="<mcl_audit name=\"update-available\">\\nMCL UPDATE AVAILABLE — installed=${INSTALLED_VERSION}, upstream-latest=${LATEST_VERSION}. When emitting the per-turn banner, append a LOCALIZED warning fragment to it in the developer's detected language meaning ${_BT}(⚠️ <latest> available — type mcl-update)${_BT}. Examples: Turkish ${_BT}🌐 MCL ${INSTALLED_VERSION} (⚠️ ${LATEST_VERSION} mevcut — mcl-update yaz)${_BT}; English ${_BT}🌐 MCL ${INSTALLED_VERSION} (⚠️ ${LATEST_VERSION} available — type mcl-update)${_BT}. Localize for all 14 supported languages (Turkish, English, Spanish, French, German, Japanese, Korean, Chinese, Arabic, Hindi, Indonesian, Portuguese, Russian, Hebrew). This is passive notification only — do NOT interrupt the MCL flow, do NOT mention it outside the banner, do NOT nag. The developer runs the update by sending the literal message ${_BT}mcl-update${_BT}. The banner itself must remain plain text — do NOT leak these ${_BT}<mcl_audit>${_BT} wrapper tags into the visible banner.\\n</mcl_audit>\\n\\n"
fi

# STATE_FILE is used by multiple notice sections below. Define once here.
STATE_FILE="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/state.json"

# Early session-boundary state resets. Task-scoped state flags
# (partial_spec, phase_review_state) must be cleared
# BEFORE any notice computation reads them. Without this,
# PARTIAL_SPEC_NOTICE / PHASE_REVIEW_NOTICE below would fire spurious
# warnings at the start of a new session using stale prior-task state.
_EARLY_STATE_LIB="$(dirname "$0")/lib/mcl-state.sh"
if [ -f "$_EARLY_STATE_LIB" ] && command -v python3 >/dev/null 2>&1; then
  source "$_EARLY_STATE_LIB"
  mcl_state_init 2>/dev/null || true
  _EARLY_SESSION_ID="$(printf '%s' "$RAW_INPUT" | python3 -c 'import json,sys
try:
    print(json.loads(sys.stdin.read()).get("session_id",""))
except Exception:
    pass' 2>/dev/null)"
  _EARLY_LAST_SESSION="$(mcl_state_get plugin_gate_session 2>/dev/null)"
  if [ -n "$_EARLY_SESSION_ID" ] && [ "$_EARLY_SESSION_ID" != "$_EARLY_LAST_SESSION" ]; then
    mcl_state_set partial_spec false >/dev/null 2>&1 || true
    mcl_state_set partial_spec_body_sha null >/dev/null 2>&1 || true
    mcl_state_set phase_review_state null >/dev/null 2>&1 || true
  fi
fi

# Optional Semgrep SAST preflight notice. The helper script
# ${_BT}lib/mcl-semgrep.sh${_BT} checks three things: binary presence, whether at
# least one detected project stack is in Semgrep's supported list, and
# cache freshness. Only non-ready states produce prose — 'ready' stays
# silent. Cache-stale triggers a fire-and-forget background refresh so
# the first Phase 4.5 scan in this session runs against a warm cache.
#
# We emit the prose every activation; the 'warn-once-then-execute' rule
# already in STATIC_CONTEXT keeps MCL from re-rendering the notice to
# the developer on subsequent turns within a session.
SEMGREP_NOTICE=""
SEMGREP_HELPER="$(dirname "$0")/lib/mcl-semgrep.sh"
if [ -f "$SEMGREP_HELPER" ]; then
  SEMGREP_STATUS="$(bash "$SEMGREP_HELPER" preflight "$(pwd)" 2>/dev/null)"
  SEMGREP_RC=$?
  case "$SEMGREP_RC" in
    2)
      # Binary missing — hard-block SAST, but soft-block at the
      # pipeline level: session proceeds without Semgrep in Phase 4.5.
      SEMGREP_HINT="${SEMGREP_STATUS#semgrep-missing|install=}"
      SEMGREP_HINT_ESC="$(printf '%s' "$SEMGREP_HINT" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      SEMGREP_NOTICE="<mcl_audit name=\\\"semgrep-missing\\\">\\nSEMGREP SAST BINARY MISSING — Phase 4.5 (Risk Review) uses Semgrep as its SAST engine but the ${_BT}semgrep${_BT} binary is not on PATH. On the FIRST developer-facing message of this session ONLY, include a LOCALIZED one-sentence notice stating that Semgrep-based SAST will be skipped until installed, and include the install command ${_BT}${SEMGREP_HINT_ESC}${_BT} verbatim (do NOT translate the shell command). Do NOT block or delay the session. Phase 4.5's non-SAST checks still run. Per the warn-once-then-execute rule, do NOT re-emit this notice on subsequent turns.\\n</mcl_audit>\\n\\n"
      ;;
    1)
      # Stack not on the Semgrep-supported matrix — no SAST for this
      # project, ever. Warn once, then silent.
      SEMGREP_NOTICE="<mcl_audit name=\\\"semgrep-unsupported-stack\\\">\\nSEMGREP UNSUPPORTED STACK — No Semgrep-supported language tag (typescript/javascript/python/go/ruby/java/kotlin/php/cpp/csharp/rust) was detected in this project. On the FIRST developer-facing message of this session ONLY, include a LOCALIZED one-sentence notice stating that Semgrep-based SAST will be skipped for this project and Phase 4.5 will run its non-SAST checks only. Per the warn-once-then-execute rule, do NOT re-emit on subsequent turns.\\n</mcl_audit>\\n\\n"
      ;;
    3)
      # Empty project — no source files exist yet (bootstrap/scaffold session).
      # The stack is genuinely unknown because the code hasn't been written yet.
      # Silent skip — do NOT surface a developer notice.
      ;;

    0)
      # Ready or cache-stale. On cache-stale, kick a background refresh
      # so Phase 4.5's first scan hits warm rules. No prose needed.
      if [ "$SEMGREP_STATUS" = "semgrep-cache-stale" ]; then
        ( bash "$SEMGREP_HELPER" refresh-cache >/dev/null 2>&1 ) &
        disown 2>/dev/null || true
      fi
      ;;
  esac
fi

# Partial-spec recovery notice. When the Stop hook detected a
# structurally-truncated ${_BT}📋 Spec:${_BT} block on the prior turn (e.g., a
# rate-limit interrupt cut the emission mid-flight), state carries
# ${_BT}partial_spec=true${_BT}. In that case inject an audit block instructing
# Claude to (a) acknowledge the interruption, (b) re-emit the full spec
# from Phase 1 context, (c) NOT emit ${_BT}✅ MCL APPROVED${_BT} in the recovery
# turn — the Stop hook also ignores approval markers while the flag is
# set as defense-in-depth. Flag auto-clears when a complete spec is
# detected on a later Stop pass. Warn-every-time (not warn-once): the
# audit must repeat until the developer sees a recovered spec.
PARTIAL_SPEC_NOTICE=""
if [ -f "$STATE_FILE" ] && command -v python3 >/dev/null 2>&1; then
  PARTIAL_FLAG="$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        obj = json.load(f)
    v = obj.get("partial_spec")
    print("true" if v is True else "false")
except Exception:
    print("false")
' "$STATE_FILE" 2>/dev/null)"
  if [ "$PARTIAL_FLAG" = "true" ]; then
    PARTIAL_SPEC_NOTICE="<mcl_audit name=\\\"partial-spec-recovery\\\">\\nPARTIAL SPEC RECOVERY — the previous assistant turn emitted a ${_BT}📋 Spec:${_BT} block that is structurally incomplete (missing one or more of: Objective, MUST, SHOULD, Acceptance Criteria, Edge Cases, Technical Approach, Out of Scope). The likely cause is a rate-limit interruption or a network drop mid-emission. Do the following in this turn, in the developer's detected language (default Turkish if unknown):\\n\\n1. Open with ONE short localized line acknowledging that the prior spec was cut off and you are re-emitting it. Examples — Turkish: ${_BT}Önceki spec yarıda kesildi, tam halini yeniden yayınlıyorum.${_BT}; English: ${_BT}The previous spec was truncated; re-emitting the full version.${_BT}; Japanese: ${_BT}前回のスペックは途中で切れました。完全版を再送します。${_BT}; Spanish: ${_BT}La spec anterior se truncó; emitiéndola completa.${_BT}; Arabic: ${_BT}تم قطع المواصفات السابقة؛ أعيد إصدار النسخة الكاملة.${_BT}; German: ${_BT}Der vorherige Spec wurde abgeschnitten; vollständige Version wird erneut gesendet.${_BT}; French: ${_BT}Le spec précédent a été tronqué; je le réémets en entier.${_BT}; Portuguese: ${_BT}O spec anterior foi truncado; reemitindo a versão completa.${_BT}; Italian-style adjustments apply analogously for Indonesian/Korean/Chinese/Russian/Hindi/Hebrew.\\n2. Re-emit the ENTIRE ${_BT}📋 Spec:${_BT} block using the developer's original Phase 1 intent from conversation context — include every required section (Objective, MUST, SHOULD, Acceptance Criteria, Edge Cases, Technical Approach, Out of Scope).\\n3. Do NOT emit the token ${_BT}✅ MCL APPROVED${_BT} in this recovery turn. The developer must explicitly approve the re-emitted spec in a SEPARATE following turn. The Stop hook also mechanically ignores any approval marker while the partial-spec flag is raised — a marker here has no effect.\\n4. End with the standard localized approval prompt (${_BT}Bu mı istiyorsun?${_BT} / ${_BT}Is this what you want?${_BT} / etc.) and STOP. Do NOT proceed to Phase 4 execute in this turn.\\n\\nIf the developer's original intent is unrecoverable from context, ask ONE surgical clarifying question instead of re-emitting a fabricated spec — never guess. Phase 4.5/4.6/5 do NOT run on recovery turns; they run only after fresh approval and a clean execute.\\n</mcl_audit>\\n\\n"
  fi
fi

# Phase review enforcement notice (since 7.1.8). When the Stop hook set
# phase_review_state=pending (code was written without Phase 4.5 starting),
# inject a mandatory block instruction on the developer's next message.
# This catches the case where Phase 4 ends, the developer sends any message,
# and Claude must run Phase 4.5 before answering anything else.
PHASE_REVIEW_NOTICE=""
if [ -f "$STATE_FILE" ] && command -v python3 >/dev/null 2>&1; then
  _PR_STATE_VAL="$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        obj = json.load(f)
    print(obj.get("phase_review_state") or "")
except Exception:
    pass
' "$STATE_FILE" 2>/dev/null)"
  if [ "$_PR_STATE_VAL" = "pending" ]; then
    PHASE_REVIEW_NOTICE="<mcl_audit name=\\\"phase-review-required\\\">\\nPHASE REVIEW MANDATORY BLOCK — Phase 4 code was written in a prior turn but Phase 4.5 Risk Review has NOT been started. The developer's current message must NOT be answered yet.\\n\\nBefore responding to ANYTHING the developer just said, you MUST:\\n1. Acknowledge in the developer's detected language (one sentence) that Phase 4.5 must run before you can continue.\\n2. Immediately start Phase 4.5 Risk Review: review ALL code written in Phase 4 for security vulnerabilities, performance bottlenecks, edge cases, data integrity, race conditions, and regression surfaces.\\n3. Present ONE risk at a time via AskUserQuestion with prefix ${_BT}MCL ${INSTALLED_VERSION} | ${_BT}.\\n4. After ALL Phase 4.5 risks are resolved → run Phase 4.6 Impact Review.\\n5. After Phase 4.6 → run Phase 5 Verification Report.\\n6. Only AFTER Phase 5 is complete → answer the developer's original message.\\n\\nThis is MANDATORY. The developer's message is queued — not ignored — but Phase 4.5/4.6/5 take priority.\\n</mcl_audit>\\n\\n"
  fi
fi

# Re-spec guard notice (since 7.1.8). When spec is approved and current_phase>=4,
# inject a per-turn audit block forbidding new spec emission. Primary guard
# against MCL re-entering Phase 2/3 during Phase 4 execution. The static
# constraint ${_BT}no-respec-after-approval${_BT} in STATIC_CONTEXT is the behavioral
# backstop; this dynamic notice is the per-turn enforcement signal.
RESPEC_GUARD_NOTICE=""
if [ -f "$STATE_FILE" ] && command -v python3 >/dev/null 2>&1; then
  _RG_ACTIVE="$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        obj = json.load(f)
    approved = obj.get("spec_approved") is True
    phase = int(obj.get("current_phase") or 0)
    print("true" if approved and phase >= 4 else "false")
except Exception:
    print("false")
' "$STATE_FILE" 2>/dev/null)"
  if [ "$_RG_ACTIVE" = "true" ]; then
    RESPEC_GUARD_NOTICE="<mcl_audit name=\\\"spec-approved-no-respec\\\">\\nSPEC ALREADY APPROVED — Phase 4 active. STRICT PROHIBITION: Do NOT emit a new ${_BT}📋 Spec:${_BT} block this turn. Do NOT call AskUserQuestion to re-request spec approval. The approved spec is the canonical and immutable blueprint for this session.\\n\\nIf Phase 4 execution found an unexpected constraint, blocker, or environment mismatch: surface it as ONE AskUserQuestion bridge question only — state the issue in one sentence, offer 2–3 concrete resolution options (workaround / scope-trim / cancel) — then STOP and WAIT. Do NOT regenerate the spec, do NOT re-run Phase 1/2/3.\\n</mcl_audit>\\n\\n"
  fi
fi

# Plugin gate notice. On the FIRST UserPromptSubmit of a session we run
# the plugin+binary check and persist ${_BT}plugin_gate_active${_BT} +
# ${_BT}plugin_gate_missing${_BT} to state.json. PreToolUse reads those flags to
# block mutating tools while the gate is active. After the first message
# we re-emit the notice on every turn (hard-gate semantics) but do NOT
# re-run the check — the persisted flag carries the session.
PLUGIN_GATE_NOTICE=""
PLUGIN_GATE_HELPER="$(dirname "$0")/lib/mcl-plugin-gate.sh"
STATE_LIB="$(dirname "$0")/lib/mcl-state.sh"
if [ -f "$PLUGIN_GATE_HELPER" ] && [ -f "$STATE_LIB" ]; then
  # shellcheck source=lib/mcl-state.sh
  source "$STATE_LIB"
  mcl_state_init 2>/dev/null || true

  SESSION_ID="$(printf '%s' "$RAW_INPUT" | python3 -c 'import json,sys
try:
    print(json.loads(sys.stdin.read()).get("session_id",""))
except Exception:
    pass' 2>/dev/null)"
  LAST_GATE_SESSION="$(mcl_state_get plugin_gate_session 2>/dev/null)"

  if [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "$LAST_GATE_SESSION" ]; then
    # Trace: session boundary — emit once per SESSION_ID.
    TRACE_LIB="$(dirname "$0")/lib/mcl-trace.sh"
    if [ -f "$TRACE_LIB" ]; then
      # shellcheck source=lib/mcl-trace.sh
      source "$TRACE_LIB"
      mcl_trace_append session_start "$INSTALLED_VERSION"

      # --- Session log (since 7.1.8): create per-session .md diary ---
      _MCL_LOG_LIB="$(dirname "$0")/lib/mcl-log-append.sh"
      _MCL_LOG_DIR="${MCL_STATE_DIR}/log"
      _MCL_LOG_FILE="$_MCL_LOG_DIR/$(date '+%Y%m%d-%H%M%S').md"
      _MCL_LOG_CURRENT="${MCL_STATE_DIR}/log-current"
      mkdir -p "$_MCL_LOG_DIR" 2>/dev/null || true
      {
        printf '# MCL Oturum Günlüğü — %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf '**Proje:** ${_BT}%s${_BT}  \n' "$(pwd)"
        printf '**MCL Sürümü:** %s\n\n' "$INSTALLED_VERSION"
        printf '---\n\n'
      } > "$_MCL_LOG_FILE" 2>/dev/null || true
      printf '%s\n' "$_MCL_LOG_FILE" > "$_MCL_LOG_CURRENT" 2>/dev/null || true
      if [ -f "$_MCL_LOG_LIB" ]; then
        source "$_MCL_LOG_LIB"
        mcl_log_append "MCL oturumu başlatıldı (${INSTALLED_VERSION})."
      fi

      STACK_DETECT_LIB="$(dirname "$0")/lib/mcl-stack-detect.sh"
      if [ -f "$STACK_DETECT_LIB" ]; then
        STACK_TAGS="$(bash "$STACK_DETECT_LIB" detect "$(pwd)" 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
        [ -n "$STACK_TAGS" ] && mcl_trace_append stack_detected "$STACK_TAGS"

        # UI flow auto-detect (since 6.5.2). No developer prompt —
        # the stack heuristic owns ui_flow_active at activation time.
        UI_CAPABLE="$(bash "$STACK_DETECT_LIB" ui-capable "$(pwd)" 2>/dev/null)"
        if [ "$UI_CAPABLE" = "true" ]; then
          mcl_state_set ui_flow_active true >/dev/null 2>&1 || true
        else
          mcl_state_set ui_flow_active false >/dev/null 2>&1 || true
        fi
        mcl_audit_log "ui-flow-autodetect" "mcl-activate.sh" "ui_capable=${UI_CAPABLE:-false}"
        mcl_trace_append ui_flow_autodetect "${UI_CAPABLE:-false}"

        # UI sub-phase self-heal (since 6.5.3). ui_sub_phase="BUILD_UI"
        # is normally set by mcl-stop.sh during the Phase 2/3→4 spec-
        # approve transition. Carry-over sessions that already had
        # spec_approved=true AND current_phase>=4 from before UI flow
        # existed (pre-6.5.2) would otherwise never enter the UI build
        # sub-phase. Here we retroactively gate BUILD_UI on next session
        # activation so the path-exception in mcl-pre-tool.sh engages.
        if [ "$UI_CAPABLE" = "true" ]; then
          SH_CP="$(mcl_state_get current_phase 2>/dev/null)"
          SH_SA="$(mcl_state_get spec_approved 2>/dev/null)"
          SH_USP="$(mcl_state_get ui_sub_phase 2>/dev/null)"
          SH_UR="$(mcl_state_get ui_reviewed 2>/dev/null)"
          if [ "$SH_SA" = "true" ] && [ "${SH_CP:-0}" -ge 4 ] 2>/dev/null \
             && { [ -z "$SH_USP" ] || [ "$SH_USP" = "null" ]; } \
             && [ "$SH_UR" != "true" ]; then
            mcl_state_set ui_sub_phase '"BUILD_UI"' >/dev/null 2>&1 || true
            mcl_audit_log "ui-flow-self-heal" "mcl-activate.sh" "phase=${SH_CP} entered BUILD_UI"
            mcl_trace_append ui_flow_self_heal BUILD_UI
          fi
        fi
      fi
    fi
    GATE_MISSING="$(bash "$PLUGIN_GATE_HELPER" check "$(pwd)" 2>/dev/null || true)"
    if [ -n "$GATE_MISSING" ]; then
      GATE_JSON_ARR="$(printf '%s\n' "$GATE_MISSING" | python3 -c '
import json, sys
items = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        items.append(json.loads(line))
    except Exception:
        pass
print(json.dumps(items))
' 2>/dev/null)"
      mcl_state_set plugin_gate_active true >/dev/null 2>&1 || true
      mcl_state_set plugin_gate_missing "$GATE_JSON_ARR" >/dev/null 2>&1 || true
      mcl_audit_log "plugin-gate-activated" "mcl-activate.sh" "missing=$(printf '%s' "$GATE_JSON_ARR" | head -c 200)"
    else
      mcl_state_set plugin_gate_active false >/dev/null 2>&1 || true
      mcl_state_set plugin_gate_missing '[]' >/dev/null 2>&1 || true
    fi
    mcl_state_set plugin_gate_session "$SESSION_ID" >/dev/null 2>&1 || true
  fi

  GATE_ACTIVE="$(mcl_state_get plugin_gate_active 2>/dev/null)"
  if [ "$GATE_ACTIVE" = "true" ]; then
    MISSING_PRETTY="$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        obj = json.load(f)
    arr = obj.get("plugin_gate_missing") or []
    bits = []
    for item in arr:
        kind = item.get("kind")
        if kind == "plugin":
            bits.append("plugin:" + item.get("name",""))
        elif kind == "binary":
            bits.append("binary:" + item.get("plugin","") + "/" + item.get("name",""))
    print(" ".join(bits))
except Exception:
    print("")
' "$STATE_FILE" 2>/dev/null)"
    MISSING_ESC="$(printf '%s' "$MISSING_PRETTY" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    PLUGIN_GATE_NOTICE="<mcl_audit name=\\\"plugin-gate\\\">\\nMCL PLUGIN GATE ACTIVE — required plugins or binaries are missing. Missing items: ${MISSING_ESC}. MCL is in a HARD-GATED state for this project: the PreToolUse hook denies mutating tools (Write / Edit / MultiEdit / NotebookEdit and writer-Bash commands) until every missing item is installed. Read-only tools (Read / Grep / Glob / read-only Bash) still work. On the developer's NEXT message, emit the following in their detected language (default Turkish if unknown):\\n\\n1. Open with ONE short localized line acknowledging MCL is gated and what is missing. Example Turkish: ${_BT}MCL kilitli — eksik plugin/binary var.${_BT} English: ${_BT}MCL is gated — required plugins or binaries are missing.${_BT}\\n2. List each missing item with its install command: for ${_BT}plugin:<name>${_BT} items emit the literal line ${_BT}/plugin install <name>@claude-plugins-official${_BT}; for ${_BT}binary:<plugin>/<bin>${_BT} items state BOTH the plugin name AND the binary name so the developer can install the binary via their platform package manager (npm / pip / cargo / brew / apt as appropriate). Do NOT translate slash commands or binary names.\\n3. State plainly that MCL will remain gated until every missing item is resolved and a new MCL session is started (the check re-runs on the first message of the next session).\\n4. Do NOT run Phase 1 intent gathering in this turn. Do NOT call ${_BT}AskUserQuestion${_BT}. Do NOT emit a spec. The gate listing IS the entire response.\\n\\nEmit this block on EVERY turn until the gate clears — no warn-once suppression, the gate is a hard stop.\\n</mcl_audit>\\n\\n"
  fi
fi

FULL_CONTEXT="${UPDATE_NOTICE}${SEMGREP_NOTICE}${PARTIAL_SPEC_NOTICE}${PHASE_REVIEW_NOTICE}${RESPEC_GUARD_NOTICE}${PLUGIN_GATE_NOTICE}${STATIC_CONTEXT}"

cat <<HOOK_OUTPUT
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "${FULL_CONTEXT}"
  }
}
HOOK_OUTPUT
