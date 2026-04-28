#!/bin/bash
# MCL Auto-Activation Hook
# - Sends MCL rules to Claude on every message. Claude decides if input is non-English.
# - No bash-level language detection — Claude is a language model, it knows.
# - Adds update visibility (24h cache) and the ${_BT}/mcl-update${_BT} self-update keyword.

set -u

_BT='`'  # literal backtick for heredoc embedding without command substitution
MCL_REPO_PATH="${MCL_REPO_PATH:-$HOME/my-claude-lang}"
MCL_REPO_RAW="https://raw.githubusercontent.com/YZ-LLM/my-claude-lang/main/VERSION"

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
# - /mcl-update: blocking fetch (we need fresh value to report).
# - Otherwise cache stale or empty: background fetch, fire-and-forget.
# - Otherwise: reuse cache.
if [ "$PROMPT_NORM" = "/mcl-update" ]; then
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

# -------- Branch: /mcl-update keyword --------
if [ "$PROMPT_NORM" = "/mcl-update" ]; then
  REPO_PATH_ESC="$(printf '%s' "$MCL_REPO_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  LATEST_DISP="${LATEST_VERSION:-unknown}"
  cat <<UPDATE_OUTPUT
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "<mcl_core>\nMCL_UPDATE_MODE — the developer typed the literal keyword ${_BT}/mcl-update${_BT}. SKIP the entire MCL pipeline. Do NOT run Phase 1/spec/3/4/4.5/4.6/5. Do NOT ask clarifying questions. Do NOT emit a spec block. Do NOT trigger rule-capture flow. This message is ONLY for running the self-update.\n\nExecute these steps and respond ONLY in the developer's detected language (default Turkish if language is unknown):\n\n1. Start the response with the banner ${_BT}🌐 MCL ${INSTALLED_VERSION} — mcl-update${_BT}.\n2. Report: installed=${INSTALLED_VERSION}, upstream-latest=${LATEST_DISP}, repo path=${REPO_PATH_ESC}.\n3. If the repo path does not exist OR is not a git repository, emit a localized diagnostic telling the developer to clone the repo to \$HOME/my-claude-lang OR set the ${_BT}MCL_REPO_PATH${_BT} environment variable. STOP — do NOT attempt any other recovery.\n4. Otherwise run in ONE bash call: ${_BT}cd \"${REPO_PATH_ESC}\" && git pull --ff-only && bash setup.sh${_BT}.\n5. If git pull fails (merge conflict, divergent branch, detached HEAD), print the verbatim stderr, explain what it means in the developer's language, and STOP. Do NOT run destructive recovery (no ${_BT}reset --hard${_BT}, no ${_BT}push --force${_BT}, no discarding of local changes).\n6. On success, read ${_BT}${REPO_PATH_ESC}/VERSION${_BT} for the new installed version and tell the developer the update is live — the hook and skill files are re-read every prompt, so the NEXT message in this same session already uses the new rules. Do NOT instruct the developer to open a new Claude Code session; that advice is incorrect.\n7. End the response. No phase report, no spec, no tests, no summary of changes, no Phase 4.5/4.6/5.\n</mcl_core>"
  }
}
UPDATE_OUTPUT
  exit 0
fi

# -------- Branch: /mcl-finish keyword --------
if [ "$PROMPT_NORM" = "/mcl-finish" ]; then
  FINISH_HELPER="$(dirname "$0")/lib/mcl-finish.sh"
  SEMGREP_HELPER_FIN="$(dirname "$0")/lib/mcl-semgrep.sh"
  FINISH_HELPER_ESC="$(printf '%s' "$FINISH_HELPER" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  SEMGREP_HELPER_ESC="$(printf '%s' "$SEMGREP_HELPER_FIN" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  cat <<FINISH_OUTPUT
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "<mcl_core>\nMCL_FINISH_MODE — the developer typed the literal keyword ${_BT}/mcl-finish${_BT}. SKIP the entire MCL pipeline. Do NOT run Phase 1/spec/3/4/4.5/4.6/5. Do NOT ask clarifying questions. Do NOT emit a spec block. Do NOT trigger rule-capture flow. This message is ONLY for aggregating accumulated Phase 4.6 impacts since the last checkpoint and emitting a project-level finish report.\n\nExecute these steps and respond ONLY in the developer's detected language (default Turkish if unknown):\n\n1. Start the response with the banner ${_BT}🌐 MCL ${INSTALLED_VERSION} — mcl-finish${_BT}.\n2. Run ${_BT}bash \"${FINISH_HELPER_ESC}\" list-since-last-checkpoint | bash \"${FINISH_HELPER_ESC}\" reconcile \"\$(pwd)\"${_BT} via the Bash tool (one pipeline command). Each output line has format ${_BT}path|STATUS|detail|days_old${_BT}. STATUS values: RESOLVED (already closed — fix-applied / rule-captured), FILE_DELETED (referenced file gone), FILE_CHANGED (file modified since impact was recorded), STALE (>30 days, no file reference), OPEN (still relevant), ERROR (unreadable). If the output is empty AND there is no Semgrep section to emit, state in the developer's language that there is nothing to finish since the last checkpoint, then STOP — do NOT write a checkpoint file, do NOT run any other step.\n3. For each reconciliation line that is NOT RESOLVED: Read the impact file at the given path. Aggregate all non-RESOLVED impacts into a report section titled in the developer's language (e.g., Turkish ${_BT}📊 Birikmiş Etkiler${_BT}, English ${_BT}📊 Accumulated Impacts${_BT}, Spanish ${_BT}📊 Impactos Acumulados${_BT}). Render each impact with a STATUS prefix: FILE_DELETED → ${_BT}🗑️${_BT} + one localized note (Turkish: ${_BT}[dosya silindi — muhtemelen geçersiz]${_BT}; English: ${_BT}[file deleted — likely obsolete]${_BT}); FILE_CHANGED → ${_BT}🔄${_BT} + one localized note with detail (Turkish: ${_BT}[dosya değişti — yeniden değerlendir: <detail>]${_BT}; English: ${_BT}[file changed — re-evaluate: <detail>]${_BT}); STALE → ${_BT}⏳${_BT} + one localized note (Turkish: ${_BT}[N gün eski — hâlâ geçerli mi?]${_BT}; English: ${_BT}[N days old — still relevant?]${_BT}); OPEN or ERROR → no prefix, render normally. If ALL impacts are RESOLVED, OMIT this section. Above the section, emit a one-line localized reconciliation summary (Turkish example: ${_BT}N etki: M açık, K dosyası silindi, L yeniden değerlendir, J eskimiş${_BT}; English: ${_BT}N impacts: M open, K file deleted, L re-evaluate, J stale${_BT}).\n4. Run ${_BT}bash \"${SEMGREP_HELPER_ESC}\" preflight \"\$(pwd)\"${_BT} via the Bash tool. Interpret the exit code:\n   - rc=0 AND output is ${_BT}semgrep-ready${_BT} or ${_BT}semgrep-cache-stale${_BT}: supported stack. Run ${_BT}semgrep --config p/default --error --json .${_BT} via Bash (bounded to project root; do NOT scan outside cwd). Parse findings and emit a second section titled in the developer's language (Turkish ${_BT}🔍 SAST Taraması${_BT}, English ${_BT}🔍 SAST Scan${_BT}). List findings grouped by severity with file:line and a short explanation. If Semgrep returns zero findings, OMIT this section entirely.\n   - rc=1 (unsupported stack) OR rc=2 (binary missing): OMIT the SAST section entirely, do NOT emit a placeholder — the developer already saw the one-time preflight notice at session start.\n5. Compose the report body in the developer's language with ONLY the non-empty sections from steps 3 and 4. Above the sections emit a one-line localized summary of the checkpoint window (e.g., ${_BT}Son checkpoint'ten bu yana N etki, M SAST bulgusu${_BT}).\n6. Write a new checkpoint file at ${_BT}\$(bash \"${FINISH_HELPER_ESC}\" finish-dir)/NNNN-YYYY-MM-DD.md${_BT}:\n   - NNNN from ${_BT}bash \"${FINISH_HELPER_ESC}\" next-checkpoint-id${_BT}.\n   - YYYY-MM-DD is today's date.\n   - File contents: YAML frontmatter (checkpoint_id, written_at ISO8601, impact_count, sast_finding_count) followed by the full report body just emitted.\n   - Create the finish dir with ${_BT}mkdir -p${_BT} if missing.\n7. End the response after the report. Do NOT append a Phase 5 Verification Report, a must-test list, or a tail reminder — ${_BT}/mcl-finish${_BT} is its own output, not a wrapped Phase 5. Do NOT run Phase 4.5 or 4.6 on the finish output itself.\n\nSTOP RULE: no clarifying questions. ${_BT}/mcl-finish${_BT} is unambiguous — run the aggregation.\n</mcl_core>"
  }
}
FINISH_OUTPUT
  exit 0
fi

# -------- Branch: /mcl-doctor keyword --------
if [ "$PROMPT_NORM" = "/mcl-doctor" ]; then
  COST_HELPER="$(dirname "$0")/lib/mcl-cost.py"
  COST_HELPER_ESC="$(printf '%s' "$COST_HELPER" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  PROJECT_DIR_ESC="$(printf '%s' "${CLAUDE_PROJECT_DIR:-$(pwd)}" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  cat <<DOCTOR_OUTPUT
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "<mcl_core>\nMCL_DOCTOR_MODE — the developer typed the literal keyword ${_BT}/mcl-doctor${_BT}. SKIP the entire MCL pipeline. Do NOT run Phase 1/spec/3/4/4.5/4.6/5. Do NOT ask clarifying questions. Do NOT emit a spec block.\n\nExecute these steps and respond ONLY in the developer's detected language (default Turkish if unknown):\n\n1. Start the response with the banner ${_BT}🌐 MCL ${INSTALLED_VERSION} — mcl-doctor${_BT}.\n2. Run ${_BT}python3 \"${COST_HELPER_ESC}\" \"${PROJECT_DIR_ESC}\"${_BT} via the Bash tool.\n3. Present the full output of that command to the developer as-is (it is already markdown-formatted).\n4. After the report, offer the developer one option: ${_BT}rm .mcl/cost.json${_BT} to reset the injection counter for this project (explain this clears accumulated per-turn data, not the session logs).\n\nSTOP RULE: no clarifying questions. ${_BT}/mcl-doctor${_BT} is unambiguous — run the cost report.\n</mcl_core>"
  }
}
DOCTOR_OUTPUT
  exit 0
fi

# -------- Branch: /mcl-restart keyword --------
if [ "$PROMPT_NORM" = "/mcl-restart" ]; then
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
    "additionalContext": "<mcl_core>\nMCL_RESTART_MODE — the developer typed the literal keyword ${_BT}/mcl-restart${_BT}. SKIP the entire MCL pipeline. Do NOT run Phase 1/spec/3/4/4.5/4.6/5. Do NOT ask clarifying questions. Do NOT emit a spec block.\n\nAll MCL phase and spec state has been reset to defaults (spec_approved=false, current_phase=1). Respond ONLY in the developer's detected language (default Turkish if unknown):\n\n1. Start the response with the banner ${_BT}🌐 MCL ${INSTALLED_VERSION} — mcl-restart${_BT}.\n2. Confirm in the developer's language that all phase and spec state has been cleared and MCL is ready for a new task.\n3. Do NOT start Phase 1 automatically — just confirm the reset and wait for the developer's next message.\n\nSTOP RULE: no clarifying questions. ${_BT}/mcl-restart${_BT} is unambiguous — confirm the reset.\n</mcl_core>"
  }
}
RESTART_OUTPUT
  exit 0
fi

# -------- Branch: /mcl-checkup keyword --------
if [ "$PROMPT_NORM" = "/mcl-checkup" ]; then
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

# -------- Branch: /mcl-version keyword --------
if [ "$PROMPT_NORM" = "/mcl-version" ]; then
  cat <<VERSION_OUTPUT
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "<mcl_core>\nMCL_VERSION_MODE — the developer typed the literal keyword ${_BT}/mcl-version${_BT}. SKIP the entire MCL pipeline. Respond ONLY in the developer's detected language (default Turkish if unknown). Start the response with the banner ${_BT}🌐 MCL ${INSTALLED_VERSION}${_BT}. Then state the installed version number clearly. Do NOT start Phase 1 or any other phase. End the response there.\n</mcl_core>"
  }
}
VERSION_OUTPUT
  exit 0
fi

# -------- Branch: normal MCL activation --------
# Static rule text (banner + pipeline). Single-quoted heredoc preserves all
# JSON escape sequences literally. Variable expansion happens in the final
# emit step, where we prefix an optional update notice.
IFS='' read -r -d '' STATIC_CONTEXT <<'STATIC_CONTEXT_END' || true
<mcl_core>\nFOLLOW these rules for every developer message — every language including English — no exceptions. First identify the developer's language so you can respond in it:\n\n1. Start EVERY response with: 🌐 MCL 8.1.3\n2. Respond ONLY in the developer's language.\n3. Do NOT write code yet. First gather: intent, constraints, success_criteria, context.\n4. DISAMBIGUATION TRIAGE — when a parameter is unclear, classify before acting. SILENT (assume, do NOT ask): trivial defaults (pagination size, error message wording, log level, timeout value) → mark `[assumed: X]` in spec; reversible choices (which library within a category, file naming convention, color scheme) → mark `[default: X, changeable]` in spec. GATE (ask, one at a time): schema or migration decisions; auth or permission model; public API surface or breaking changes; business logic with irreversible data consequences (\"what happens to user posts on account deletion?\"); security boundary decisions. Heuristic: if you can write the spec without the answer, assume silently and document the assumption. If you cannot write the spec without the answer, ask. Phase 3 spec review is the safety net — users can correct wrong assumptions there. GATE-ANSWER COHERENCE CHECK: After each GATE answer involving an architectural choice (auth model, data storage, API shape, consistency model), silently check: do the technical implications of this answer fit the system behavior described in the conversation? If the answer requires capability X but the described flow requires NOT-X, surface ONE sentence in the developer's language citing the specific conflict, then ask which they meant — (a) the stated choice with its architectural implication, or (b) the architecture implied by the described flow. This is a GATE — resolve before writing the spec. Only fire for concrete technical incompatibilities (JWT with server-side-state flow; NoSQL with multi-table ACID transactions; stateless API with cross-device persistence), not style preferences or vague concerns.\n5. When all parameters are clear, present a summary AS PLAIN TEXT in the developer's language, then call `AskUserQuestion` with question prefix `MCL 8.1.3 | ` and options to confirm, edit, or cancel. STOP there — do NOT proceed to the spec until the tool_result returns an approve-family option. PHASE 1.5 — ENGINEERING BRIEF: After the tool_result returns an approve-family option from the Phase 1 confirmation, BEFORE writing the spec, produce a collapsible Engineering Brief block using translator mode (user_lang → EN). Format exactly: `<details><summary>🔄 Engineering Brief [EN]</summary>` on its own line, then a blank line, then: `[MCL TRANSLATOR PASS — <detected_lang> → EN]` on its own line; then `Task:` / `Requirements:` / `Success criteria:` / `Context:` fields each on their own line, each being a precise English translation of the corresponding Phase 1 summary field — no interpretation, no additions, technical terms left as-is. Then `</details>` on its own line. This brief is invisible to the user (collapsed by default). The spec that follows MUST be derived from this brief — it ensures Phase 2 engineering is entirely in English.\n6. MANDATORY — write a visible English spec starting with '📋 Spec:' on its own line, immediately followed by a '<details open><summary>spec (collapse to hide)</summary>' tag on the next line, then the full spec body, then '</details>' to close. This makes the spec collapsible in the Claude Code UI while keeping '📋 Spec:' as the line-start anchor for hooks. Write it like a senior engineer with 15+ years experience. BASE SECTIONS (always include): Objective, MUST/SHOULD requirements, Acceptance Criteria, Edge Cases, Technical Approach, Out of Scope. CONDITIONAL SECTIONS (include only when triggered — omit entirely otherwise): Non-functional Requirements (when performance, scale, or resource constraints are mentioned or implied); Failure Modes & Degradation (when external dependencies, async operations, or distributed concerns exist); Observability (when the feature touches a critical production path, security audit trail, or user behavior tracking); Reversibility/Rollback (when DB schema changes, data migrations, destructive operations, or feature flags are in scope); Data Contract (when API surface changes, shared schemas, or cross-service boundaries are involved). This spec makes Claude Code process the request AS IF a native English engineer wrote it. WITHOUT THIS SPEC THE DEVELOPER GETS CHATBOT OUTPUT INSTEAD OF ENGINEER OUTPUT.\n7. After the spec, you MUST write a visible summary paragraph in the developer's language — this is NOT optional and NOT the AskUserQuestion description. Format: plain text, developer's language, 3-5 sentences covering what will be built and the key technical approach. MANDATORY: this paragraph appears BEFORE the AskUserQuestion call, never inside it. Then call `AskUserQuestion` with question prefix `MCL 8.1.3 | ` to ask for spec approval (options: approve / edit / cancel in the developer's language).\n8. Only after the AskUserQuestion tool_result returns an approve-family option, proceed to write code.\n9. All code in English. All communication in THEIR language.\n10. Never pass vague terms without challenging.\n</mcl_core>\n\n<mcl_constraint name=\"pasted-cli-passthrough\">\nPASTED CLI PASSTHROUGH RULE: When the developer's prompt is concrete CLI command(s) in shell syntax (e.g. `git clone URL`, `bash setup.sh`, `npm install`, `docker compose up`, `mkdir`, `curl ...`), EXECUTE directly with default interpretations. Do NOT ask about clone location, target directory, flag choice, or blast-radius — the command IS the intent; Phase 1 intent-gathering (rules 3–5) is skipped for that prompt. EXCEPTIONS that still apply: (a) destructive operations (`rm -rf`, `git reset --hard`, `DROP TABLE`, etc.) trigger the execution-plan reconfirm regardless of this rule; (b) if a specific parameter is genuinely ambiguous beyond defaults (undocumented custom flag, ordering dependency), ask ONE surgical question — NOT a generic Phase 1 dump.\n</mcl_constraint>\n\n<mcl_constraint name=\"self-critique\">\nSELF-CRITIQUE RULE — MANDATORY, ALL PHASES:\nBefore emitting ANY response to the developer AND before passing ANY translated content to Claude Code, run the self-critique loop. (1) Draft the response. (2) Silently ask yourself FOUR questions IN THE DEVELOPER'S DETECTED LANGUAGE (Turkish originals as reference for semantic intent): 'Peki ya tam tersi doğruysa?' (what if the opposite is true?), 'Kendi cevabımı eleştirirsem ne bulurum?' (if I critique my own answer, what flaws?), 'Neyi gözden kaçırıyorum?' (what am I missing?), 'Bu düşündüğümde kullanıcıya yalakalık olsun diye yaptığım bişey var mı? Yalakalık yapmamam gerekiyor.' (am I being sycophantic? I must not be). IN PHASE 4 ONLY (EXECUTE) add a FIFTH question before every tool call: 'Bu adım onaylanan spec sınırları içinde mi?' (is this step still within the approved spec's boundaries?). If the answer is NO, STOP — do not execute the action, surface the boundary mismatch to the developer for confirmation or spec revision. The 5th question catches execution-drift that Phase 5's Verification Report would only catch after the fact; it does NOT run in Phase 1/2/3 (no approved spec yet) or Phase 5 (post-hoc Verification handles compliance). When the developer writes in Japanese, run the questions in Japanese; in Spanish, Spanish; in Arabic, Arabic — never force Turkish. (3) If ANY flaw found → silently revise the draft. (4) Re-run the critique on the revised draft. (5) Up to 3 iterations, exit on the first clean pass — NEVER run all 3 unconditionally. If iteration 1 is clean, stop there.\n\nBY DEFAULT the critique is ENTIRELY INTERNAL — the developer NEVER sees 'Kendimi eleştirdim...', 'Bir an için şöyle düşündüm...', 'İlk düşüncem şuydu ama...', or any draft-critique-revise trace.\n\nEXCEPTION — `/mcl-self-q` TAG: if the developer's CURRENT user message contains the substring `/mcl-self-q` (only the user message is scanned, NOT system reminders / tool output / history), emit the self-critique process for THAT response visibly in a labeled block in the developer's language (e.g., '🔍 Öz-Eleştiri Süreci:' in Turkish, '🔍 Self-Critique Process:' in English, '🔍 자기비판 과정:' in Korean) showing each iteration's draft, the four-question critique, and any revision, BEFORE the final clean answer. The tag operates PER-MESSAGE only — the next message without the tag returns to silent operation. No persistence, no config file, no env var — the tag IS the toggle.\n\nFilter out sycophantic language: 'great question!', 'excellent!', 'harika fikir!', unearned praise, reflexive agreement. Anti-sycophancy is ABSOLUTE — no balancing qualifier, no 'but still be nice' softening. Runs in ALL phases — Phase 1, 2, 3, 4, 5 — at both user↔MCL and MCL↔Claude Code transitions. No 'simple question' exception. NEVER SKIP.\n</mcl_constraint>\n\n<mcl_constraint name=\"stop-rule\">\nSTOP RULE — THIS OVERRIDES EVERYTHING:\nWhen you ask a question or request confirmation, your ENTIRE response is ONLY that question. STOP THERE. Do NOT continue writing. Do NOT call tools. Do NOT explore files. Do NOT read code. Do NOT generate specs. Do NOT present summaries. Your response ENDS at the question mark. Wait for the developer's reply in the next message. Violating this rule means you are not waiting for the developer — you are assuming their answer.\n</mcl_constraint>\n\n<mcl_constraint name=\"no-preamble\">\nNO PREAMBLE RULE: Do NOT write introductory sentences before asking a question. No 'I need to clarify...', no 'Let me understand...', no 'A few things to clarify:'. Just ask the question directly. The question IS the entire response. THIS IS LANGUAGE-AGNOSTIC: never open with a greeting, apology, honorific, or courtesy softener in ANY language. The first word of your response is the first word of the question itself.\n</mcl_constraint>\n\n<mcl_constraint name=\"warn-once-then-execute\">\nPOST-APPROVAL WARNING RULE: After the developer has explicitly approved a spec and entered Phase 4 (EXECUTE), do NOT repeat the same caveat, warning, or side-effect note on subsequent turns. Raise each warning ONCE when it first becomes relevant, then proceed silently. Re-raising an already-acknowledged warning on every turn wastes developer attention and signals an anxious assistant, not a disciplined one. EXCEPTION: the `execution-plan` rule's destructive-operation reconfirm ALWAYS fires regardless of prior approval — destructive actions are a hard-gated exception, not a repeated warning. If new information appears that genuinely changes the risk picture (not the same risk re-stated), a fresh warning is allowed — but say explicitly what changed.\n</mcl_constraint>\n\n<mcl_constraint name=\"pressure-resistance\">\nPRESSURE RESISTANCE RULE: When the developer pushes back on your position (disagrees, expresses frustration, insists on a different answer), do NOT reflexively concede with 'you're right, sorry' / 'haklısın, özür dilerim' / equivalent in any language. First check: is there NEW EVIDENCE — a fact you missed, a constraint you didn't know, a different framing that changes the analysis? If yes, update your position and state explicitly what changed your mind. If no, HOLD the position and give the specific reason in one sentence. Changing your mind under social pressure without evidence is sycophancy in disguise — it looks polite but it is a failure mode. This rule complements (does not replace) the anti-sycophancy rule: anti-sycophancy blocks unearned praise; pressure-resistance blocks unearned concession.\n</mcl_constraint>\n\n<mcl_constraint name=\"honest-assessment\">\nHONEST ASSESSMENT RULE: When the developer's message contains a validation-seeking pattern — asking for your opinion on a technical choice, approach, or design (Turkish: 'iyi mi?', 'doğru mu?', 'mantıklı mı?', 'ne düşünüyorsun?', 'bu yaklaşım işe yarar mı?', 'bu doğru yol mu?'; English: 'is this good?', 'what do you think?', 'does this make sense?', 'should I?', 'is this right?'; or equivalent in any language) — structure your response as VERDICT FIRST, REASONS SECOND.\n\nVERDICT FORMAT: Positive — state what works and the specific technical reason. Negative — state the concrete problem in the FIRST SENTENCE ('Bu yaklaşımda [spesifik teknik sorun] var.'), then what would work instead. Mixed — state the problematic part first, then what works. Never lead with the positive when there is a problem.\n\nFORBIDDEN before the verdict: softening qualifiers ('interesting approach, but...', 'a good start, however...', 'I can see what you're going for, but...'). These bury the technical finding. The verdict is first; qualifiers may follow.\n\nPROACTIVE FIRING: if the developer proposes something technically unsound without explicitly asking for feedback, surface the concern in the first sentence — not the fifth. Technical peer, not yes-man.\n</mcl_constraint>\n\n<mcl_constraint name=\"execution-plan\">\nEXECUTION PLAN RULE: By default MCL proceeds silently WITHOUT emitting an Execution Plan. The plan is required ONLY when the intended action is a DESTRUCTIVE operation — one that cannot be reversed by normal editor undo, git checkout, or re-running the same task. Non-exhaustive examples of destructive operations: `rm`/`rmdir` (including `rm -r`, `rm -rf`), `git push --force`/`-f`/`--force-with-lease`, `git reset --hard`, SQL `DROP TABLE`/`DROP DATABASE`/`TRUNCATE`, `DELETE FROM <table>` without a `WHERE` clause, `kubectl delete`, `terraform destroy`, `dd` (raw disk writes), recursive permission/ownership changes (`chmod -R`, `chown -R`), and any chained bash where a destructive command appears. This list is NOT exhaustive — if a command permanently loses state or affects production infrastructure, treat it as destructive even if not listed. All non-destructive actions proceed silently: Read, Grep, Glob, Write, single- or multi-file Edit, `git add`/`commit`/`push` (non-force)/`rebase`/`checkout`/`clean`/`rm`, package installs (`npm install`, `pip install`, `brew install`), `WebFetch`, `WebSearch`, non-recursive `sudo`/`chmod`/`chown`, writes under `~/.claude/` or system directories, and chained `&&`/`;` bash that contains no destructive command. `git rm` is a git command, NOT shell `rm` — it proceeds silently. On ambiguity (unclear whether a command is destructive), default to showing the plan (safe side). Destructive-operation reconfirm fires EVEN INSIDE an already-approved spec (phase 4) — spec approval authorizes writing code, not silently running destructive shell. When the plan IS triggered, list every action with: (1) what will happen, (2) why, (3) what the harness will ask — translated to developer's language, (4) what each option does (Yes = only this, Yes allow all = all future too, No = skip). Ask 'Bu plan uygun mu?' and WAIT for confirmation before executing.\n</mcl_constraint>\n\n<mcl_phase name=\"phase4-5-risk-review\">\nPOST-CODE RISK REVIEW RULE (PHASE 4.5) — MANDATORY: After ALL code is written and BEFORE the Verification Report, you MUST run Phase 4.5. Phase 4.5 runs four steps in order:\n\nRISK SESSION TRACKING: At Phase 4.5 start, check `.mcl/risk-session.md` (absolute path is `<MCL_STATE_DIR>/risk-session.md` — resolve MCL_STATE_DIR as `<CLAUDE_PROJECT_DIR>/.mcl`). Run `git log --oneline -1 | awk '{print $1}'` to get current HEAD. If the file exists AND `phase4_head` matches current HEAD: read the 'Reviewed' entries; for each risk you generate, if its first 80 characters closely match a 'Reviewed' entry's text, skip it silently. If the file is missing OR `phase4_head` differs from current HEAD: create/reset the file with current HEAD and an empty Reviewed list. After EACH risk is resolved: append `- <decision> | <first 80 chars of risk text>` under `## Reviewed` in the file. When Phase 4.5 completes fully (all risks resolved): delete the file (`rm .mcl/risk-session.md`).\n\n(1) SPEC COMPLIANCE PRE-CHECK: Walk every MUST and SHOULD in the approved 📋 Spec: body. For each requirement that is missing or only partially implemented in Phase 4 code, surface it as a risk in the sequential dialog (same format as other risks). If every MUST/SHOULD is fully implemented, skip this step silently.\n\n(2) INTEGRATED QUALITY SCAN: Before each risk-dialog turn, apply four embedded lenses simultaneously — these are continuous practices, not isolated checkpoints. (a) CODE REVIEW — correctness, logic errors, error handling, dead code; (b) SIMPLIFY — unnecessary complexity, premature abstraction, over-engineering; (c) PERFORMANCE — embedded practice: N+1 queries, unbounded loops, blocking operations, memory leaks; (d) SECURITY — embedded practice: injection, auth bypass, XSS, CSRF, sensitive data exposure. Each finding is labeled with its category. Semgrep SAST HIGH/MEDIUM findings with unambiguous autofix are applied silently and merged. Present as a SEQUENTIAL INTERACTIVE DIALOG: ONE risk per turn with a short explanation, then STOP and wait for the developer's reply IN THE NEXT MESSAGE. Per risk: skip / apply specific fix / make general rule (triggers RULE CAPTURE). Never present Phase 4.5 risks as a one-shot bulleted list.\n\n(3) TDD RE-VERIFY: After all risks are resolved, if test_command is configured AND Phase 4.5 was not omitted entirely (at least one risk was surfaced), run `bash ~/.claude/hooks/lib/mcl-test-runner.sh green-verify`. GREEN → proceed to step 4. RED → surface the failing test(s) as a new Phase 4.5 risk in the sequential dialog. TIMEOUT → log one audit line and proceed.\n\n(4) COMPREHENSIVE TEST COVERAGE: After TDD re-verify passes, check that Phase 4 code is covered by: unit tests (individual functions/components), integration tests (cross-module interactions, API contracts), E2E tests (user flows — if UI stack active), load/stress tests (throughput-sensitive paths — if applicable). When test_command IS configured, WRITE the missing test files directly as Phase 4 code actions — not as AskUserQuestion turns — then run `bash ~/.claude/hooks/lib/mcl-test-runner.sh green-verify`; RED surfaces as a new Phase 4.5 sequential-dialog risk. When test_command is NOT configured, document the missing categories in a single risk-dialog turn so the developer decides (add now / skip / make-rule). If all applicable categories are already covered, omit this step silently (empty-section-omission rule). Skip entirely when Phase 4.5 was omitted entirely (no risks found).\n\nIf after honest spec-check and quality scan no risks are found, OMIT Phase 4.5 entirely — no header, no placeholder — and proceed silently to Phase 4.6. Only after Phase 4.5 is fully resolved do you run Phase 4.6.\n</mcl_phase>\n\n<mcl_phase name=\"phase4-6-impact-review\">\nPOST-RISK IMPACT REVIEW RULE (PHASE 4.6) — MANDATORY: After Phase 4.5 is fully resolved and BEFORE the Verification Report, you MUST run Phase 4.6 — Post-Risk Impact Review. Scan the project for REAL downstream effects of the newly-written code on OTHER parts of the project: files that import the changed module, shared utilities whose behavior shifted, API/contract changes that break callers, shared state/cache invalidation, schema/migration effects on existing data, configuration changes affecting other components, build/toolchain/dependency changes. An impact is NEVER: a restatement of the files just edited, meta-changelog ('we updated X, next session uses Y'), self-reference to the task's own deliverables, version/setup notes, generic reminders, or anything already handled in Phase 4.5. Present impacts as a SEQUENTIAL INTERACTIVE DIALOG: ONE impact per turn — cite the concrete downstream artifact (file path, function, consumer) and one-sentence 'why affected', then STOP and wait for the developer's reply IN THE NEXT MESSAGE before presenting the next impact. Per impact the developer may reply: skip / apply specific fix / make this a general rule (triggers RULE CAPTURE). Never present Phase 4.6 impacts as a one-shot bulleted list. If no real impacts are surfaced after honest review, OMIT Phase 4.6 entirely from the response — no header, no placeholder sentence, no filler — and proceed silently to Phase 5. Only after Phase 4.6 is fully resolved do you run Phase 5.\n</mcl_phase>\n\n<mcl_phase name=\"phase5-review\">\nPHASE 5 VERIFICATION REPORT RULE — MANDATORY: After Phase 4.6 is fully resolved, you MUST produce a Verification Report with UP TO 3 sections in this order:\n\n(1) Spec Coverage — emit a full markdown table: | Requirement | Test | Status |. One row per MUST/SHOULD from the approved spec. Status: ✅ = test exists and passed GREEN (show test file:line and function name in the Test column); ⚠️ = test written but RED or partial (show file:line); ❌ = no test written (show — in Test column). OMIT this section entirely ONLY when test_command was never configured this session (no TDD ran at all).\n\n(2) A section titled `!!! <LOCALIZED-MUST-TEST-PHRASE> !!!` — wrap in `!!! ... !!!`, localize (Turkish: `!!! MUTLAKA TEST ETMİNİZ GEREKENLER !!!`, English: `!!! YOU MUST TEST THESE !!!`, Spanish: `!!! DEBES PROBAR ESTO !!!`, etc.). List ONLY items where automation is structurally impossible. Detect by scanning Phase 4 code for these call patterns — NOT spec keywords: (a) DOM API / render() calls / document.* — visual layout cannot be asserted without visual regression runner; (b) HTTP fetch or third-party SDK calls (Stripe, AWS, Twilio, etc.) to non-localhost hosts with no mock in the test suite — live API credentials and side effects; (c) file write calls to paths outside test temp directories — environment-specific filesystem behavior; (d) shell or subprocess invocation without mock — OS-level side effects; (e) production-only env vars (prod DB URL, production API key env var) read at runtime — production environment dependency. Each item MUST cite file:line and one sentence explaining why it cannot be automated. Apply empty-section-omission rule — if no automation barriers are found after honest scan, OMIT this section entirely.\n\n(3) Process Trace — read `.mcl/trace.log` via the Read tool and render each line as a single localized bullet (header 'Süreç İzlemesi' / 'Process Trace' / etc.); OMIT entirely when the log is missing or empty.\n\nThe Permission Summary and Missed Risks sections are NOT part of Phase 5 — do NOT include them. Do NOT end with 'done' or a changes list. If you wrote code without running Phase 4.5 and then Phase 5, go back and produce both. PHASE 5.5 — LOCALIZED REPORT: After all three sections above are complete, produce a user-language translation of the full report using translator mode (EN → user_lang). Format: `━━━━━━━━━━━━━━━━━━━━━` on its own line, then the localized section title (Turkish: `Doğrulama Özeti`, English: `Verification Summary`, Spanish: `Resumen de verificación`, etc.) on its own line, then `━━━━━━━━━━━━━━━━━━━━━` on its own line, then the translated content. Translation rules: translate section headers, requirement descriptions, test status labels, and barrier explanations; preserve file:line references, test function names, timestamps, CLI flags, and all technical tokens verbatim. The translator instruction is: 'You are now in translator mode. Do not interpret, add, or omit anything. Preserve the structured format exactly. Leave technical terms as-is. Translate only natural language. EN → [user_lang].'\n</mcl_phase>\n\n<mcl_phase name=\"rule-capture\">\nRULE CAPTURE RULE: When the developer asks to turn a fix into a general rule (during Missed Risks or anywhere else), or MCL detects a generalizable pattern and the developer accepts the offer: ask for scope with three options — once only / this project / all my projects. Project scope writes to `<CWD>/CLAUDE.md`; user scope writes to `~/.claude/CLAUDE.md`. If the chosen scope looks inappropriate (e.g., framework-specific rule tagged 'all projects', or a universal rule tagged 'this project'), issue EXACTLY ONE follow-up question citing the specific reason — no second warning; if the developer confirms, proceed. Before writing, show a preview block containing: the exact English directive (imperative and unambiguous: `Never X`, `Always Y`, `Prefer X over Y`; no modifiers like 'generally', 'usually', 'maybe', 'try to'), plus a localized translation in the developer's language, plus the target file path. Ask 'Approve this exact text? (yes / edit / cancel)' and WAIT. Only on 'yes' do you write. Append under an `## MCL-captured rules` heading (create the heading and/or the file if needed). Each rule is a bullet with the English text and a sibling HTML comment `<!-- loc: <LANG-CODE>: <translation> -->` so Claude parses only the English directive. Before writing, scan the target file for semantically-overlapping rules; if found, show both side-by-side and ask 'Overwrite, keep both, or cancel?'. When the developer asks 'what rules did we set?' in any language, read `<CWD>/CLAUDE.md` and `~/.claude/CLAUDE.md`, extract the `## MCL-captured rules` sections, and list them in the developer's language grouped by scope. Never write silently. Never soften the sanity check. Never write vague rule text.\n</mcl_phase>\n\n<mcl_constraint name=\"empty-section-omission\">\nEMPTY SECTION OMISSION RULE — CROSS-PHASE: Any phase section whose content would be empty is omitted entirely from the response — no header, no placeholder sentence ('No risks identified', 'All items comply', or equivalent), no whitespace filler. This applies uniformly to every phase (current and future). The review/analysis still *happens* internally; only the *output* is suppressed when it has nothing to report. 'No news = good news' is the user-facing contract.\n</mcl_constraint>\n\n<mcl_constraint name=\"spec-visibility\">\nCRITICAL: The spec in step 6 MUST appear in your response as a visible block. It is NOT internal. The developer must see it. If you skip the spec, the entire MCL pipeline is broken.\n</mcl_constraint>\n\n<mcl_constraint name=\"askuserquestion-approval\">\nASKUSERQUESTION APPROVAL RULE — MACHINE SIGNAL TO MCL, NOT TEXT PARSING:\nAll CLOSED-ENDED MCL interactions (spec approval, summary confirmation, risk decisions, impact decisions, plugin consent, git-init consent, stack auto-detect fallback choice, partial-spec recovery, mcl-update, mcl-finish, pasted-CLI passthrough) MUST use Claude Code's native `AskUserQuestion` tool — NOT plain-text 'reply yes or no' prompts.\n\nEvery MCL-initiated `AskUserQuestion` call MUST set `question` beginning with the literal prefix `MCL 8.1.3 | ` followed by the localized question body in the developer's detected language. The `options` array renders labels in the developer's language too; include at least one option from the approve family (Turkish 'Onayla', English 'Approve', Spanish 'Aprobar', etc.) so the Stop hook can detect state-advancing choices. The Stop hook parses the most recent tool_use/tool_result pair with the `MCL {version} | ` prefix and transitions state accordingly.\n\nDO NOT emit the legacy string `✅ MCL APPROVED` — it is dead in 6.0.0 and carries no meaning. If a developer message includes a free-form 'yes' / 'evet' / 'approve' WITHOUT a corresponding AskUserQuestion tool_result, do NOT treat it as approval — call `AskUserQuestion` and let the developer confirm via the UI.\n\nAPPLIES TO: Phase 1 summary confirmation, Phase 3 spec approval, Phase 4.5 risk walkthrough (one AskUserQuestion per risk), Phase 4.6 impact walkthrough (one per impact), Rule A git-init consent, plugin suggestions (one per plugin), stack auto-detect fallback, partial-spec recovery, /mcl-update confirmation, /mcl-finish confirmation, pasted-CLI passthrough confirmation.\n\nDOES NOT APPLY TO: Phase 1 open-ended gathering ('what do you want to build?', 'what are the constraints?'), spec body emission, Phase 3 language explanation, Phase 4 code writing, Phase 5 Verification Report — these stay as plain text.\n</mcl_constraint>\n\n<mcl_constraint name=\"no-respec-after-approval\">\nNO RE-SPEC AFTER APPROVAL RULE (since 7.1.8): Once the developer approves a spec and Phase 4 (EXECUTE) begins, the approved spec is the SOLE and IMMUTABLE blueprint for this session. NEVER emit a new `📋 Spec:` block. NEVER call AskUserQuestion to re-request spec approval. If Phase 4 execution uncovers an unexpected constraint, blocker, or environment mismatch: surface it as ONE AskUserQuestion bridge question \u2014 state the issue in one sentence, offer 2\u20133 concrete resolution options (workaround / scope-trim / cancel) \u2014 then WAIT for the developer's reply. Do NOT re-run Phase 1/2/3. Do NOT regenerate the spec. Violations waste tokens and break the one-spec-per-task invariant.\n</mcl_constraint>\n\n<mcl_constraint name=\"project-memory\">\nPROJECT MEMORY RULE:\n\n(1) READ: If `<mcl_project_memory>` is injected, it contains `.mcl/project.md` — the project knowledge base. During Phase 1, skip questions about facts already documented there (stack, architecture, conventions). Reference it naturally when relevant to the task.\n\n(2) PROACTIVE: If `<mcl_audit name=\"proactive-items\">` is injected, follow its priority rule exactly: developer request first, top open item surfaced at Phase 5 end via AskUserQuestion. One item only — never dump all open items.\n\n(3) WRITE after Phase 5: After emitting the Verification Report, write or update `.mcl/project.md` via the Write tool (Read existing content first if file exists). Structure: markdown heading with project name, `**Stack:**` and `**Güncelleme:**` lines, then: `## Mimari` (lasting architectural decisions, one bullet each), `## Teknik Borç` ([ ]/[x] checklist — unresolved Phase 4.5 risks become new `[ ]` items; items fixed this session become `[x] (YYYY-MM-DD)`), `## Bilinen Sorunlar` ([ ]/[x] for known bugs/issues). Add decisions from this session's spec. Keep under 50 lines. Create if missing. Path: `<CLAUDE_PROJECT_DIR>/.mcl/project.md`.\n</mcl_constraint>\n\n<mcl_constraint name=\"ui-flow-discipline\">\nUI FLOW DISCIPLINE — MANDATORY when ui_flow_active=true: Phase 4 MUST split into 4a/4b/4c. Never collapse these into a single phase or skip any. Phase 4a (BUILD_UI): build the complete frontend with dummy/mock data only — zero real API calls. Provide the dev-server run command when done. Auto-open the browser. STOP. Phase 4b (UI_REVIEW): present AskUserQuestion for UI approval (prefix MCL X.Y.Z |) with options approve/revise. If revised: re-enter Phase 4a with the feedback. NEVER start Phase 4c until the developer clicks approve in Phase 4b. Phase 4c (BACKEND): only after UI approval — wire real API calls, data layer, async operations. Sub-agents in Phase 4a build UI only; backend wiring is forbidden for them. Phase 4b AskUserQuestion runs in the main MCL session, never in a sub-agent. When ui_flow_active=false (no UI surface detected): skip 4a/4b/4c entirely, proceed with normal Phase 4.\n</mcl_constraint>\n\n<mcl_constraint name=\"sub-agent-phase-discipline\">\nSUB-AGENT PHASE DISCIPLINE — MANDATORY: When sub-agents, parallel agents, or any Task-dispatch pattern (superpowers, subagent-driven-development, dispatching-parallel-agents, etc.) are used to write Phase 4 code, the MAIN MCL session retains EXCLUSIVE responsibility for Phase 4.5, 4.6, and 5. Sub-agents only write code. They CANNOT replace, skip, or partially substitute any MCL phase. After ALL sub-agents complete:\n1. Immediately run Phase 4.5 Risk Review in the main session — review ALL code written by ALL sub-agents as a single body of work. Never dispatch Phase 4.5 to a sub-agent.\n2. Run Phase 4.6 Impact Review in the main session.\n3. Run Phase 5 Verification Report + Phase 5.5 Localized Report in the main session.\nTDD: If test_command is configured, EACH sub-agent writing production code MUST also write corresponding tests before finishing. If not configured after spec approval, ask the developer once (STEP-24 resolution) — do NOT silently skip. A sub-agent labelled spec-compliance-review does NOT satisfy Phase 4.5 — Phase 4.5 requires the main MCL interactive risk dialog (one AskUserQuestion per risk). No shortcuts, no bulk summaries.\nFORBIDDEN: dispatching Phase 4.5, 4.6, or 5 to a sub-agent. These phases require the main MCL session to run the interactive AskUserQuestion dialog directly.\n</mcl_constraint>\n\n<mcl_constraint name=\"spec-approval-discipline\">\nSPEC APPROVAL DISCIPLINE — strict rules for Phase 2/3 flow:\n1. ONE SPEC PER SESSION: Once a spec block has been emitted (spec_hash is set in state.json), do NOT emit another spec block. Do NOT call AskUserQuestion for spec approval more than once per session unless the developer explicitly requests changes (revise option). If the developer sends a plain-text approve-family message (onaylıyorum, approve, evet, yes, etc.) and current_phase=2, treat it as spec approval and proceed to Phase 4 immediately.\n2. NO HOOK FILE DEBUGGING: Never read ~/.claude/hooks/*.sh or state.json to diagnose why the phase did not advance. Trust the stop hook. If state shows current_phase=2 after an approval, proceed as if approved — the stop hook processes asynchronously.\n3. NO CONTINUE PROMPT: NEVER say [Devam etmek icin bir mesaj gonderin], [Please send a message to continue], [send a message to proceed], or any equivalent phrase in any language. The developer knows how to continue. This phrase is banned unconditionally.\n4. NO SELF-NARRATION: After spec approval, do NOT narrate [State update will be processed at end of this response] or equivalent. Proceed directly to Phase 4.\n</mcl_constraint>\n\n<mcl_constraint name=\"dispatch-audit\">\nDISPATCH AUDIT — Phase 4.5 MANDATORY DISPATCHES: During Phase 4.5 Risk Review you MUST dispatch both of the following before writing Phase 4.6 or Phase 5 content:\n1. CODE-REVIEW SUB-AGENT — call Task with subagent_type=\"pr-review-toolkit:code-reviewer\" (or equivalent \"code-review\", \"superpowers:code-reviewer\" sub-agent). This is the multi-lens review (Code Review + Simplify + Performance + Security). Do NOT skip it, do NOT summarize it inline — call the Task tool.\n2. SEMGREP SCAN — run ${_BT}bash hooks/lib/mcl-semgrep.sh scan <modified_files>${_BT} via Bash tool (only when semgrep binary is available and stack is supported — if SEMGREP_NOTICE is present, semgrep is already flagged as unavailable, skip this item).\nIF PLUGIN_MISS_NOTICE IS PRESENT: You have NOT yet dispatched the listed plugins. Dispatch them IMMEDIATELY as the FIRST action of this turn. Do NOT write Phase 4.6 or Phase 5 content until PLUGIN_MISS_NOTICE disappears. The notice clears automatically once dispatches appear in trace.log.\n</mcl_constraint>\n\n<mcl_constraint name=\"superpowers-scope\">\nSUPERPOWERS SCOPE — enforced by mcl-pre-tool.sh hook (decision:block). superpowers:brainstorming is blocked when MCL is active; TodoWrite is blocked in Phase 1-3; Phase 4.5/4.6/5 Task dispatch is blocked. See hook for details.\n</mcl_constraint>\n\n<mcl_constraint name=\"coding-principles\">\nCODING PRINCIPLES — apply to ALL code written in Phase 4 (and sub-agents):\n1. COMPOSITION OVER INHERITANCE — build behavior by composing small units, not class hierarchies. When inheritance depth exceeds 1, switch to composition.\n2. SOLID — enforce all five: Single Responsibility (one reason to change per unit), Open/Closed (open for extension, closed for modification), Liskov Substitution (subtypes must be substitutable), Interface Segregation (no fat interfaces), Dependency Inversion (depend on abstractions, not concretions).\n3. EXTENSION OVER MODIFICATION — add new behavior by extending, not by editing working code. New requirement → new file/class/function alongside existing ones, not a diff inside them.\n4. DESIGN PATTERNS ONLY WHEN THEY SOLVE A REAL PROBLEM — name the problem first, then the pattern. Never introduce a pattern because it looks clean. If the pattern cannot be justified by a concrete problem in the current code, omit it.\n</mcl_constraint>\n\n<mcl_constraint name=\"translator-mode\">\nTRANSLATOR MODE RULE: Two formal translation passes occur in every MCL session. In each pass, apply the translator instruction exactly: do NOT interpret, add, or omit anything; preserve the structured format; leave technical terms as-is (file paths, code identifiers, CLI flags, MUST/SHOULD, version numbers, test names, timestamps); translate ONLY natural language text. The two passes: (1) Phase 1.5 — user_lang → EN: translates the confirmed Phase 1 intent summary into the Engineering Brief before spec generation; (2) Phase 5.5 — EN → user_lang: translates the completed verification report into the developer language after all three Phase 5 sections. Never merge these passes with interpretation or engineering judgment — they are pure translation only.\n</mcl_constraint>\n\n<mcl_core>\nFor full rules: read ~/.claude/skills/my-claude-lang/SKILL.md if it exists. For the MCL tag vocabulary itself, read ~/.claude/skills/my-claude-lang/mcl-tag-schema.md — these tags (`<mcl_core>`, `<mcl_phase>`, `<mcl_constraint>`, `<mcl_input>`, `<mcl_audit>`) are MCL's namespaced attention layer, input-only; never wrap your output in them.\n</mcl_core>
STATIC_CONTEXT_END
# ${_BT}read -d ''${_BT} with a quoted-delimiter heredoc returns the full body into
# STATIC_CONTEXT verbatim (no $, backtick, or paren interpretation).
STATIC_CONTEXT="${STATIC_CONTEXT%$'\n'}"

# Optional update-available prefix. Localization is delegated to Claude —
# the hook only states the facts; Claude renders the warning fragment in
# the developer's detected language.
UPDATE_NOTICE=""
if [ "$UPDATE_AVAILABLE" -eq 1 ]; then
  UPDATE_NOTICE="<mcl_audit name=\\\"update-available\\\">\\nMCL UPDATE AVAILABLE — installed=${INSTALLED_VERSION}, upstream-latest=${LATEST_VERSION}. When emitting the per-turn banner, append a LOCALIZED warning fragment to it in the developer's detected language meaning ${_BT}(⚠️ <latest> available — type mcl-update)${_BT}. Examples: Turkish ${_BT}🌐 MCL ${INSTALLED_VERSION} (⚠️ ${LATEST_VERSION} mevcut — mcl-update yaz)${_BT}; English ${_BT}🌐 MCL ${INSTALLED_VERSION} (⚠️ ${LATEST_VERSION} available — type mcl-update)${_BT}. Localize for all 14 supported languages (Turkish, English, Spanish, French, German, Japanese, Korean, Chinese, Arabic, Hindi, Indonesian, Portuguese, Russian, Hebrew). This is passive notification only — do NOT interrupt the MCL flow, do NOT mention it outside the banner, do NOT nag. The developer runs the update by sending the literal message ${_BT}/mcl-update${_BT}. The banner itself must remain plain text — do NOT leak these ${_BT}<mcl_audit>${_BT} wrapper tags into the visible banner.\\n</mcl_audit>\\n\\n"
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
    mcl_state_set scope_paths '[]' >/dev/null 2>&1 || true
    mcl_state_set pattern_scan_due false >/dev/null 2>&1 || true
    mcl_state_set pattern_files '[]' >/dev/null 2>&1 || true
    mcl_state_set rollback_sha null >/dev/null 2>&1 || true
    mcl_state_set rollback_notice_shown false >/dev/null 2>&1 || true
    mcl_state_set pattern_summary null >/dev/null 2>&1 || true
    mcl_state_set tdd_last_green null >/dev/null 2>&1 || true
    mcl_state_set last_write_ts null >/dev/null 2>&1 || true
    mcl_state_set pattern_level null >/dev/null 2>&1 || true
    mcl_state_set pattern_ask_pending false >/dev/null 2>&1 || true
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
  elif [ "$_PR_STATE_VAL" = "running" ]; then
    _RISK_SESSION_PATH="${MCL_STATE_DIR}/risk-session.md"
    _RS_ESC="$(printf '%s' "$_RISK_SESSION_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    PHASE_REVIEW_NOTICE="<mcl_audit name=\\\"phase-review-recovery\\\">\\nPHASE 4.5 RECOVERY — interruption detected. DO NOT tell the developer the session was interrupted. Just continue naturally as if it never stopped.\\n\\nBefore answering the developer's message:\\n1. Read ${_BT}${_RS_ESC}${_BT}. Check ${_BT}phase4_head${_BT} vs current HEAD (${_BT}git log --oneline -1 | awk '{print \$1}'${_BT}).\\n2. If HEAD matches: skip risks whose text closely matches a 'Reviewed' entry. Continue from the next unreviewed risk via AskUserQuestion.\\n3. If HEAD differs or file missing: run Phase 4.5 fresh (code changed).\\n4. After all risks resolved → Phase 4.6 → Phase 5 → answer developer's message.\\n</mcl_audit>\\n\\n"
  fi
fi

# Re-spec guard notice (since 7.1.8). When spec is approved and current_phase>=4,
# inject a per-turn audit block forbidding new spec emission. Primary guard
# against MCL re-entering Phase 2/3 during Phase 4 execution. The static
# constraint ${_BT}no-respec-after-approval${_BT} in STATIC_CONTEXT is the behavioral
# backstop; this dynamic notice is the per-turn enforcement signal.
RESPEC_GUARD_NOTICE=""
if [ -f "$STATE_FILE" ] && command -v python3 >/dev/null 2>&1; then
  _RG_EFF_PHASE="$(mcl_get_active_phase "$STATE_FILE" 2>/dev/null)"
  _RG_ACTIVE="false"
  if echo "$_RG_EFF_PHASE" | grep -qE '^(4|4a|4b|4c|4\.5|3\.5)$'; then
    _RG_ACTIVE="true"
  fi
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

# Project memory injection — reads .mcl/project.md once per turn.
# Injects content + proactive open-item notice into FULL_CONTEXT.
# UI_FLOW_NOTICE — injected when ui_flow_active=true to enforce 4a/4b/4c
UI_FLOW_NOTICE=""
if [ -f "$STATE_FILE" ] && command -v python3 >/dev/null 2>&1; then
  _UF_ACTIVE="$(python3 -c '
import json, sys
try:
    obj = json.load(open(sys.argv[1]))
    usp = obj.get("ui_sub_phase") or ""
    reviewed = obj.get("ui_reviewed") or False
    active = obj.get("ui_flow_active") or False
    phase = obj.get("current_phase") or 1
    print(f"{active}|{usp}|{reviewed}|{phase}")
except Exception:
    print("false||false|1")
' "$STATE_FILE" 2>/dev/null)"
  _UF_ACTIVE_V="${_UF_ACTIVE%%|*}"
  _UF_REST="${_UF_ACTIVE#*|}"
  _UF_USP="${_UF_REST%%|*}"
  _UF_REST2="${_UF_REST#*|}"
  _UF_REVIEWED="${_UF_REST2%%|*}"
  _UF_PHASE="${_UF_REST2#*|}"
  if [ "$_UF_ACTIVE_V" = "True" ] || [ "$_UF_ACTIVE_V" = "true" ]; then
    if [ "${_UF_PHASE:-0}" -ge 4 ] 2>/dev/null && [ "$_UF_REVIEWED" != "True" ] && [ "$_UF_REVIEWED" != "true" ]; then
      UI_FLOW_NOTICE="<mcl_audit name=\\\"ui-flow-required\\\">\\nUI FLOW MANDATORY — A UI surface was detected in this project. Phase 4 MUST follow the 4a/4b/4c sub-phase sequence. DO NOT write backend code or run Phase 4.5/4.6/5 until Phase 4b UI_REVIEW is complete.\\n\\nCurrent ui_sub_phase: ${_UF_USP:-BUILD_UI}. ui_reviewed: false.\\n\\nRequired sequence:\\n1. Phase 4a BUILD_UI — build the full frontend UI with dummy/mock data only. Write build-tool config files FIRST (vite.config.*, tailwind.config.*, tsconfig.json, postcss.config.*) — the project must be runnable before asking for approval. NO real API calls. When done: run npm install if needed, start the dev server in background, auto-open in browser.\\n2. Phase 4b UI_REVIEW — STOP. Present an AskUserQuestion for UI approval with prefix ${_BT}MCL ${INSTALLED_VERSION} | ${_BT}. Options: approve UI / request revisions. Do NOT proceed to backend until developer approves.\\n3. Phase 4c BACKEND — only after UI approval: wire real API calls, data layer, async operations.\\n\\nSub-agents dispatched during Phase 4a MUST build UI only — no backend wiring. Phase 4b AskUserQuestion MUST run in the main MCL session, not a sub-agent.\\n</mcl_audit>\\n\\n"
    fi
  fi
fi

# Pattern Matching notice (Phase 3.5) — fires on the FIRST Phase 4 turn.
# Tells Claude which existing files to read before writing any code.
# Cleared after one turn (stop hook sets pattern_scan_due=false).
PATTERN_MATCHING_NOTICE=""
if [ -f "$STATE_FILE" ] && command -v python3 >/dev/null 2>&1; then
  _PM_DATA="$(python3 -c '
import json, sys
try:
    obj = json.load(open(sys.argv[1]))
    due = obj.get("pattern_scan_due")
    phase = obj.get("current_phase")
    files = obj.get("pattern_files") or []
    level = obj.get("pattern_level") or 1
    ask = obj.get("pattern_ask_pending") is True
    if due is True and str(phase) == "4":
        print(f"{level}|{int(ask)}|" + json.dumps(files))
    else:
        print("")
except Exception:
    pass
' "$STATE_FILE" 2>/dev/null)"
  if [ -n "$_PM_DATA" ]; then
    _PM_LEVEL="${_PM_DATA%%|*}"
    _PM_REST="${_PM_DATA#*|}"
    _PM_ASK="${_PM_REST%%|*}"
    _PM_FILES_JSON="${_PM_REST#*|}"

    if [ "$_PM_ASK" = "1" ]; then
      # Level 4 — no files, no ecosystem match: ask user
      PATTERN_MATCHING_NOTICE="<mcl_audit name=\"phase-3.5-pattern-scan\">\nPHASE 3.5 — PATTERN NOT FOUND\n\nNo existing code files were found in this project to infer patterns from. Before writing Phase 4 code, ask the developer one question in their language:\n\n\"Bu projede henüz kod yok. Hangi kod stilini kullanalım?\" (adapt to developer's language)\n\nOffer 3-4 concrete options appropriate to the detected stack (e.g. for TypeScript: strict ESLint + Prettier defaults / Airbnb style guide / Standard TS / custom). After the developer answers, write the PATTERN SUMMARY in exactly this format:\n\n**PATTERN SUMMARY**\n**Naming Convention:** <rule>\n**Error Handling Pattern:** <rule>\n**Test Pattern:** <rule>\n\nThen proceed to Phase 4. Writes unlock after the summary turn.\n</mcl_audit>\n\n"
      mcl_audit_log "pattern-matching-notice" "mcl-activate.sh" "level=4 ask=true"
    elif [ "$_PM_LEVEL" = "3" ]; then
      # Level 3 — ecosystem standard
      _ECO_NAME="$(printf '%s' "$_PM_FILES_JSON" | python3 -c '
import json,sys
files = json.loads(sys.stdin.read())
eco = files[0].replace("-ecosystem-standard","") if files else "unknown"
labels = {"typescript":"TypeScript strict (noImplicitAny, strict: true, ESLint recommended)",
          "javascript":"JavaScript Standard (ESLint recommended, no semicolons optional)",
          "python":"Python PEP 8 (black formatter, type hints, pytest)",
          "go":"Go idiomatic (gofmt, errors as values, table-driven tests)",
          "rust":"Rust idiomatic (clippy clean, Result<T,E>, #[cfg(test)])",
          "java":"Java standard (checkstyle, Optional over null, JUnit 5)",
          "ruby":"Ruby idiomatic (rubocop, frozen_string_literal, RSpec)",
          "php":"PHP PSR-12 (PHPStan level 5+, PHPUnit)",
          "csharp":"C# idiomatic (nullable enabled, xUnit, StyleCop)",
          "kotlin":"Kotlin idiomatic (ktlint, coroutines, JUnit 5)",
          "swift":"Swift idiomatic (SwiftLint, XCTest, value types preferred)"}
print(labels.get(eco, eco + " standard conventions"))
' 2>/dev/null || echo 'standard conventions')"
      PATTERN_MATCHING_NOTICE="<mcl_audit name=\"phase-3.5-pattern-scan\">\nPHASE 3.5 — NO PROJECT FILES FOUND — USING ECOSYSTEM DEFAULTS\n\nNo existing code files were found in this project to read patterns from. Apply the following ecosystem standard as the PATTERN SUMMARY:\n\n**PATTERN SUMMARY**\n**Naming Convention:** ${_ECO_NAME} — naming conventions\n**Error Handling Pattern:** ${_ECO_NAME} — error handling conventions\n**Test Pattern:** ${_ECO_NAME} — test conventions\n\nWrite the actual pattern lines (not placeholders) based on your knowledge of ${_ECO_NAME}. These become ENFORCED conventions for all Phase 4 code. End the turn after the summary — writes unlock on the next turn.\n</mcl_audit>\n\n"
      mcl_audit_log "pattern-matching-notice" "mcl-activate.sh" "level=3 ecosystem=$(printf '%s' "$_PM_FILES_JSON" | python3 -c 'import json,sys; f=json.loads(sys.stdin.read()); print(f[0].replace("-ecosystem-standard","") if f else "unknown")' 2>/dev/null)"
    elif [ -n "$_PM_FILES_JSON" ] && [ "$_PM_FILES_JSON" != "[]" ]; then
      # Level 1 or 2 — real files
      _PM_LIST="$(printf '%s' "$_PM_FILES_JSON" | python3 -c '
import json,sys
files = json.loads(sys.stdin.read())
print("\n".join(f"  - {f}" for f in files))
' 2>/dev/null)"
      PATTERN_MATCHING_NOTICE="<mcl_audit name=\"phase-3.5-pattern-scan\">\nPHASE 3.5 — PATTERN SCAN REQUIRED (one-time, this turn only)\n\nThis turn: READ ONLY — no file writes. Read the files below, then write a PATTERN SUMMARY in exactly this format (three bold headings, one line each):\n\n**PATTERN SUMMARY**\n**Naming Convention:** <one concrete rule — e.g. camelCase functions, PascalCase types, kebab-case files>\n**Error Handling Pattern:** <one concrete rule — e.g. Result<T,E> type, never throw, always log at boundary>\n**Test Pattern:** <one concrete rule — e.g. describe/it, Arrange-Act-Assert, jest.mock for all external deps>\n\nFiles to read:\n${_PM_LIST}\n\nThese three rules become ENFORCED conventions for all Phase 4 code and are checked in Phase 4.5 compliance scan. Write only what is actually present in the codebase — do not invent conventions. If a pattern is absent or inconsistent, write: [not established].\n\nEnd the turn after the summary — writes unlock on the next turn.\n</mcl_audit>\n\n"
      mcl_audit_log "pattern-matching-notice" "mcl-activate.sh" "level=${_PM_LEVEL} shown"
    fi
  fi
fi

# Pattern rules notice — injected every Phase 4 turn (after 3.5 scan is done)
# so Claude always has the three extracted conventions in scope while coding.
# Also adds a compliance check directive for Phase 4.5.
PATTERN_RULES_NOTICE=""
if [ -f "$STATE_FILE" ] && command -v python3 >/dev/null 2>&1; then
  _PR_RULES="$(python3 -c '
import json, sys
try:
    obj = json.load(open(sys.argv[1]))
    phase = str(obj.get("current_phase",""))
    scan_due = obj.get("pattern_scan_due") is True
    summary = obj.get("pattern_summary")
    pr_state = (obj.get("phase_review_state") or "")
    if phase != "4" or scan_due or not summary:
        print("")
        sys.exit(0)
    naming = summary.get("naming","[not established]")
    error  = summary.get("error","[not established]")
    test   = summary.get("test","[not established]")
    compliance = "1" if pr_state in ("pending","running") else "0"
    print(f"{naming}|{error}|{test}|{compliance}")
except Exception:
    print("")
' "$STATE_FILE" 2>/dev/null)"
  if [ -n "$_PR_RULES" ]; then
    _PR_NAMING="${_PR_RULES%%|*}"
    _PR_R1="${_PR_RULES#*|}"
    _PR_ERROR="${_PR_R1%%|*}"
    _PR_R2="${_PR_R1#*|}"
    _PR_TEST="${_PR_R2%%|*}"
    _PR_COMPLIANCE="${_PR_R2#*|}"
    PATTERN_RULES_NOTICE="<mcl_audit name=\\\"pattern-rules\\\">\\nCODEBASE PATTERN RULES (Phase 3.5 — enforced in all Phase 4 code)\\n• Naming:         ${_PR_NAMING}\\n• Error Handling: ${_PR_ERROR}\\n• Test Pattern:   ${_PR_TEST}\\n</mcl_audit>\\n\\n"
    if [ "$_PR_COMPLIANCE" = "1" ]; then
      PATTERN_RULES_NOTICE="${PATTERN_RULES_NOTICE}<mcl_audit name=\\\"pattern-compliance\\\">\\nPHASE 4.5 COMPLIANCE — check each Phase 4 file against the pattern rules above AND the root cause rule below.\\nReport violations as risk items: which file, which rule, what was found vs what is required.\\n\\nRoot Cause Chain: for each bug fix or behavioral change in Phase 4 code, apply a multi-level chain — do NOT stop at the first cause found. At each ring, apply three checks IN ORDER before descending: (1) Visible process — write out the reasoning steps that led to this ring; (2) Removal test — if this cause were eliminated, would the parent problem be resolved? If no, wrong ring — backtrack; (3) Falsification — if this cause is correct, what observable X should also be present? X must be verifiable (visible in code, logs, behavior, or files). If X is not observed, wrong ring — backtrack. If all three pass, descend to the next ring. Descend until the deepest structural cause with no further parent is found. Intervention point: NOT the root cause itself, but the nearest ring that produces ZERO side effects on other parts of the system. Band-aids to surface at any ring: catching/swallowing errors, widening type constraints, special-casing test inputs, retrying without fixing the failure mode. If the chain gets stuck (no verifiable causes remain), report transparently — do not hallucinate a cause. Report as a risk item: root cause + proposed fix + fix verification result (does applying the fix eliminate the root cause?). Skipping this chain is forbidden — Phase 4.5 is not complete until the chain bottoms out.\\n</mcl_audit>\\n\\n"
    fi
  fi
fi

# Scope discipline notice — injected every Phase 4 turn.
# Rule 1: spec-only (no bonus improvements).
# Rule 2: file scope (Scope Guard enforces when scope_paths is set;
#          this notice covers the behavioral gap when scope_paths=[]).
SCOPE_DISCIPLINE_NOTICE=""
_SD_PHASE="$(mcl_state_get current_phase 2>/dev/null)"
_SD_APPROVED="$(mcl_state_get spec_approved 2>/dev/null)"
if [ "$_SD_PHASE" = "4" ] && [ "$_SD_APPROVED" = "true" ]; then
  SCOPE_DISCIPLINE_NOTICE="<mcl_audit name=\\\"scope-discipline\\\">\\nSCOPE DISCIPLINE — three hard rules for Phase 4:\\n\\nRule 1 — SPEC-ONLY: Implement ONLY what the spec's MUST/SHOULD items explicitly require. FORBIDDEN without exception: performance improvements not in spec, refactors \\\"while I'm here\\\", style fixes, extra tests beyond acceptance criteria, API additions \\\"for future use\\\", removing unrelated dead code. If you notice something worth fixing: record it as a Phase 4.5/4.6 item — do NOT fix it now.\\n\\nRule 2 — FILE SCOPE: Only write/edit files the spec's Technical Approach references. If scope_paths is set the pre-tool hook blocks unlisted files. If it is empty: before touching any file verify it is spec-referenced — if unsure, surface it as a risk rather than silently editing.\\n\\nRule 3 — ROOT CAUSE: Fix the cause, not the symptom. If a patch only makes the test pass without addressing why it failed, surface it as a Phase 4.5 risk item instead of committing it.\\n</mcl_audit>\\n\\n"
fi

# Rollback checkpoint notice — shown ONCE (first Phase 4 turn) to avoid repeating the
# same SHA on every turn. Re-shown when /mcl-rollback resets the flag.
# ATOMIC_COMMIT_NOTICE fires on Phase 4.5/5 (pr_state=running) — also once.
ROLLBACK_NOTICE=""
ATOMIC_COMMIT_NOTICE=""
if [ -f "$STATE_FILE" ] && command -v python3 >/dev/null 2>&1; then
  _RBACK_DATA="$(python3 -c '
import json, sys
try:
    obj = json.load(open(sys.argv[1]))
    sha = (obj.get("rollback_sha") or "").strip()
    phase = str(obj.get("current_phase",""))
    pr_state = (obj.get("phase_review_state") or "")
    scope = obj.get("scope_paths") or []
    spec_hash = (obj.get("spec_hash") or "")[:12]
    shown = obj.get("rollback_notice_shown") is True
    if not sha or phase != "4":
        print("")
        sys.exit(0)
    scope_str = " ".join(scope) if scope else "."
    atomic = "1" if pr_state == "running" else "0"
    # show=1 means emit ROLLBACK_NOTICE this turn; show=0 means already shown
    show = "0" if shown else "1"
    print(f"{sha}|{scope_str}|{spec_hash}|{atomic}|{show}")
except Exception:
    print("")
' "$STATE_FILE" 2>/dev/null)"
  if [ -n "$_RBACK_DATA" ]; then
    _RB_SHA="${_RBACK_DATA%%|*}"
    _RB_REST="${_RBACK_DATA#*|}"
    _RB_SCOPE="${_RB_REST%%|*}"
    _RB_REST2="${_RB_REST#*|}"
    _RB_SPEC_HASH="${_RB_REST2%%|*}"
    _RB_REST3="${_RB_REST2#*|}"
    _RB_ATOMIC="${_RB_REST3%%|*}"
    _RB_SHOW="${_RB_REST3#*|}"
    _RB_SHORT="${_RB_SHA:0:12}"
    if [ "$_RB_SHOW" = "1" ]; then
      ROLLBACK_NOTICE="<mcl_audit name=\"rollback-checkpoint\">\nROLLBACK CHECKPOINT (pre-spec Phase 4 HEAD)\nSHA: ${_RB_SHA}\nCommand: git reset --hard ${_RB_SHA}\nEffect: reverts ALL Phase 4 file changes (irreversible — stash or commit first if needed)\nRe-show: /mcl-rollback\n</mcl_audit>\n\n"
      # Mark as shown so subsequent turns stay quiet
      mcl_state_set rollback_notice_shown true >/dev/null 2>&1 || true
    fi
    if [ "$_RB_ATOMIC" = "1" ]; then
      ATOMIC_COMMIT_NOTICE="<mcl_audit name=\"atomic-commit\">\nATOMIC COMMIT — after Phase 5 verification report, create one reversible commit:\n  git add ${_RB_SCOPE}\n  git commit -m \"feat: <spec objective — first sentence>\"\nThis makes the entire spec deliverable a single revertable unit.\nSpec: ${_RB_SPEC_HASH}  Rollback: git reset --hard ${_RB_SHORT}\n</mcl_audit>\n\n"
    fi
  fi
fi

# Regression guard notice — fires when Phase 4 code broke existing tests.
# Injected when phase_review_state=pending AND regression_block_active=true.
# Claude must fix failing tests BEFORE starting Phase 4.5 risk dialog.
REGRESSION_BLOCK_NOTICE=""
if [ -f "$STATE_FILE" ] && command -v python3 >/dev/null 2>&1; then
  _RG_ACTIVE="$(python3 -c '
import json, sys
try:
    obj = json.load(open(sys.argv[1]))
    pr = obj.get("phase_review_state") or ""
    rg = obj.get("regression_block_active")
    if pr == "pending" and rg is True:
        out = obj.get("regression_output") or ""
        print("block|" + out[:800])
    else:
        print("")
except Exception:
    pass
' "$STATE_FILE" 2>/dev/null)"
  if [ -n "$_RG_ACTIVE" ] && [ "${_RG_ACTIVE%%|*}" = "block" ]; then
    _RG_OUTPUT="${_RG_ACTIVE#block|}"
    _RG_ESC="$(printf '%s' "$_RG_OUTPUT" | sed 's/\/\\/g; s/"/\"/g')"
    REGRESSION_BLOCK_NOTICE="<mcl_audit name=\"regression-block\">\nREGRESSION GUARD — Phase 4 code broke the existing test suite. Phase 4.5 is BLOCKED until all tests pass again.\n\nFailing output:\n${_RG_ESC}\n\nRequired actions (in order):\n1. Identify which file(s) you wrote in Phase 4 caused the regression.\n2. Fix the regression — do NOT delete or skip the failing tests.\n3. Run ${_BT}bash ~/.claude/hooks/lib/mcl-test-runner.sh green-verify${_BT} to confirm GREEN.\n4. Once tests pass, this block clears automatically and Phase 4.5 can start.\n\nDo NOT proceed to Phase 4.5 risk dialog until this block is gone.\n</mcl_audit>\n\n"
    mcl_audit_log "regression-block-notice" "mcl-activate.sh" "shown"
  fi
fi

# Plugin dispatch audit — fires when Phase 4.5 is running to check whether
# required plugins (code-review sub-agent, semgrep) were actually dispatched.
PLUGIN_MISS_NOTICE=""
_DISPATCH_AUDIT_LIB="$(dirname "$0")/lib/mcl-dispatch-audit.sh"
if [ -f "$_DISPATCH_AUDIT_LIB" ] && [ -f "$STATE_FILE" ] && command -v python3 >/dev/null 2>&1; then
  _DA_REVIEW_STATE="$(mcl_state_get phase_review_state 2>/dev/null)"
  if [ "$_DA_REVIEW_STATE" = "running" ]; then
    _DA_TRACE="${MCL_STATE_DIR}/trace.log"
    # semgrep_skip: true if SEMGREP_NOTICE is non-empty (binary missing or unsupported stack)
    _DA_SGREP_SKIP="false"
    [ -n "${SEMGREP_NOTICE:-}" ] && _DA_SGREP_SKIP="true"
    source "$_DISPATCH_AUDIT_LIB" 2>/dev/null || true
    _DA_MISSED="$(mcl_check_phase45_dispatches "$_DA_TRACE" "$_DA_SGREP_SKIP" 2>/dev/null)"
    if [ -n "$_DA_MISSED" ]; then
      _DA_MISSED_ESC="$(printf '%s' "$_DA_MISSED" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      PLUGIN_MISS_NOTICE="<mcl_audit name=\\\"plugin-dispatch-gap\\\">\\nPLUGIN DISPATCH GAP — Phase 4.5 is running but the following required plugins have NOT been dispatched yet: ${_DA_MISSED_ESC}.\\n\\nYou MUST dispatch each missing plugin as a Task sub-agent BEFORE writing any Phase 4.6 or Phase 5 content:\\n- ${_BT}code-review${_BT}: call Task with subagent_type=${_BT}pr-review-toolkit:code-reviewer${_BT} (or equivalent code-review sub-agent).\\n- ${_BT}semgrep${_BT}: run ${_BT}bash hooks/lib/mcl-semgrep.sh scan <files>${_BT} via Bash tool.\\nAfter dispatching, this notice will automatically clear on the next turn. Do NOT proceed to Phase 4.6 until it clears.\\n</mcl_audit>\\n\\n"
      mcl_audit_log "plugin-dispatch-gap" "mcl-activate.sh" "missing=${_DA_MISSED}"
    fi
  fi
fi

PROJECT_MEMORY_FILE="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/project.md"
PROJECT_MEMORY_NOTICE=""
PROACTIVE_NOTICE=""

if [ -f "$PROJECT_MEMORY_FILE" ] && command -v python3 >/dev/null 2>&1; then
  _PM_CONTENT="$(cat "$PROJECT_MEMORY_FILE" 2>/dev/null)"
  if [ -n "$_PM_CONTENT" ]; then
    _PM_ESC="$(printf '%s' "$_PM_CONTENT" | python3 -c '
import json, sys
print(json.dumps(sys.stdin.read())[1:-1])
' 2>/dev/null)"
    PROJECT_MEMORY_NOTICE="<mcl_project_memory>\\n${_PM_ESC}\\n</mcl_project_memory>\\n\\n"

    _OPEN_ITEMS="$(printf '%s' "$_PM_CONTENT" | grep -E '^\s*- \[ \]' | head -3 2>/dev/null)"
    if [ -n "$_OPEN_ITEMS" ]; then
      _OPEN_ESC="$(printf '%s' "$_OPEN_ITEMS" | python3 -c '
import json, sys
print(json.dumps(sys.stdin.read().strip())[1:-1])
' 2>/dev/null)"
      PROACTIVE_NOTICE="<mcl_audit name=\\\"proactive-items\\\">\\nPROACTIVE ITEMS — open action items in .mcl/project.md:\\n${_OPEN_ESC}\\n\\nRULE: Developer request takes PRIORITY. If the developer has a task in this message, complete it fully (full MCL pipeline). At Phase 5 end, surface the TOP 1 open item via AskUserQuestion in the developer's language — one item only, not a dump, with a short localized explanation of why it matters. If developer has no task (just a question or greeting), mention the top item in one localized sentence BEFORE Phase 1, then proceed normally.\\n</mcl_audit>\\n\\n"
    fi
  fi
fi

FULL_CONTEXT="${UPDATE_NOTICE}${SEMGREP_NOTICE}${PROJECT_MEMORY_NOTICE}${PROACTIVE_NOTICE}${PARTIAL_SPEC_NOTICE}${PATTERN_MATCHING_NOTICE}${PATTERN_RULES_NOTICE}${SCOPE_DISCIPLINE_NOTICE}${ROLLBACK_NOTICE}${ATOMIC_COMMIT_NOTICE}${REGRESSION_BLOCK_NOTICE}${PHASE_REVIEW_NOTICE}${RESPEC_GUARD_NOTICE}${PLUGIN_GATE_NOTICE}${UI_FLOW_NOTICE}${PLUGIN_MISS_NOTICE}${STATIC_CONTEXT}"

# Log MCL injection size for cost accounting (mcl-doctor)
if command -v python3 >/dev/null 2>&1; then
  _MCL_CF="${MCL_STATE_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}/cost.json"
  _MCL_IC="${#FULL_CONTEXT}"
  python3 -c "
import json, os, time
p = '$_MCL_CF'
d = {'turns': []}
if os.path.isfile(p):
    try:
        d = json.load(open(p))
    except Exception:
        pass
d.setdefault('turns', []).append({'ts': int(time.time()), 'chars': $_MCL_IC})
t = p + '.tmp'
json.dump(d, open(t, 'w'))
os.replace(t, p)
" 2>/dev/null || true
fi


cat <<HOOK_OUTPUT
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "${FULL_CONTEXT}"
  }
}
HOOK_OUTPUT
