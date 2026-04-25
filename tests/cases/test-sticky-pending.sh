#!/bin/bash
# Test: phase_review_state=pending causes BLOCK in mcl-stop.sh even when
# _PR_CODE=false (Bash-only turns after code writing must still be blocked).
# SKIPPED — requires setting up a real JSONL conversation file and a stop hook
# payload with specific tool call history. Test manually after a Phase 4 session.

echo "--- test-sticky-pending ---"
skip_test "sticky-pending" "requires real JSONL conversation fixture (manual test)"
