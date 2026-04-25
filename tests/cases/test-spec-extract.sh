#!/bin/bash
# Test: _mcl_spec_extract_body returns only the spec-containing assistant turn.
# SKIPPED — requires a real .jsonl conversation fixture with Claude's exact
# message format. Test manually after a Phase 3 session produces a spec.

echo "--- test-spec-extract ---"
skip_test "spec-extract" "requires real JSONL conversation fixture (see tests/fixtures/spec-sample.txt)"
