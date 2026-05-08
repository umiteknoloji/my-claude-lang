#!/bin/bash
# MCL hook-level test runner — no API calls required.
# Usage: bash tests/run-tests.sh

set -eo pipefail

# v13.0.13 — Tests always run in devtime mode (full debug REASON text).
# Without this, tests run in /tmp/<random> dirs which don't match the
# 'my-claude-lang' path heuristic — _mcl_is_devtime returns false and
# REASON metins use the short Turkish runtime variant, breaking tests
# that assert against the long debug strings.
export MCL_DEVTIME=1

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
SKIP=0

# shellcheck source=tests/lib/test-helpers.sh
source "$REPO_ROOT/tests/lib/test-helpers.sh"

for _test_file in "$REPO_ROOT"/tests/cases/test-*.sh; do
  # shellcheck source=/dev/null
  source "$_test_file"
done

echo ""
echo "========================================="
printf 'MCL Tests: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
echo "========================================="
[ "$FAIL" -eq 0 ]
