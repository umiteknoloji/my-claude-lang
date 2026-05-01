#!/bin/bash
# MCL hook-level test runner — no API calls required.
# Usage: bash tests/run-tests.sh

set -eo pipefail

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
