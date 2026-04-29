#!/usr/bin/env bash
# MCL Ops Coverage delegate (8.13.0).
# Usage: bash mcl-ops-coverage.sh <project-dir> <test-framework>
# Stdout: JSON {total: <pct>, by_file: {...}} or {} on skip.
# Exit: 0 always (binary missing graceful skip).

set -uo pipefail

PROJECT_DIR="${1:-$PWD}"
FRAMEWORK="${2:-}"
cd "$PROJECT_DIR" || { printf '{}\n'; exit 0; }

case "$FRAMEWORK" in
  vitest|jest)
    if ! command -v npx >/dev/null 2>&1; then
      echo "[MCL/OPS] npx not found; coverage skip" >&2
      printf '{}\n'; exit 0
    fi
    OUT="$(timeout 30 npx --no-install "$FRAMEWORK" --coverage --coverageReporters=json-summary 2>/dev/null)"
    SUMMARY="$PROJECT_DIR/coverage/coverage-summary.json"
    if [ -f "$SUMMARY" ]; then
      python3 -c "
import json, sys
try:
    d = json.load(open('$SUMMARY'))
    pct = d.get('total', {}).get('lines', {}).get('pct', None)
    print(json.dumps({'total': pct, 'tool': '$FRAMEWORK'}))
except Exception:
    print('{}')
"
    else
      printf '{}\n'
    fi
    ;;
  pytest)
    if ! command -v pytest >/dev/null 2>&1; then
      echo "[MCL/OPS] pytest not installed; coverage skip" >&2
      printf '{}\n'; exit 0
    fi
    timeout 30 pytest --cov=. --cov-report=json:.mcl-cov.json --quiet >/dev/null 2>&1
    if [ -f ".mcl-cov.json" ]; then
      python3 -c "
import json
try:
    d = json.load(open('.mcl-cov.json'))
    pct = d.get('totals', {}).get('percent_covered', None)
    print(json.dumps({'total': pct, 'tool': 'pytest'}))
except Exception:
    print('{}')
"
      rm -f .mcl-cov.json
    else
      printf '{}\n'
    fi
    ;;
  go-test)
    if ! command -v go >/dev/null 2>&1; then
      echo "[MCL/OPS] go not installed; coverage skip" >&2
      printf '{}\n'; exit 0
    fi
    OUT="$(timeout 30 go test -coverprofile=/tmp/mcl-cov.out -covermode=atomic ./... 2>&1 | tail -20)"
    if [ -f /tmp/mcl-cov.out ]; then
      PCT="$(go tool cover -func=/tmp/mcl-cov.out 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d '%')"
      rm -f /tmp/mcl-cov.out
      if [ -n "$PCT" ]; then
        printf '{"total": %s, "tool": "go-test"}\n' "$PCT"
      else
        printf '{}\n'
      fi
    else
      printf '{}\n'
    fi
    ;;
  cargo)
    if ! command -v cargo-tarpaulin >/dev/null 2>&1; then
      echo "[MCL/OPS] cargo-tarpaulin not installed; coverage skip" >&2
      printf '{}\n'; exit 0
    fi
    OUT="$(timeout 60 cargo tarpaulin --print-summary 2>&1 | tail -5)"
    PCT="$(printf '%s' "$OUT" | grep -oE '[0-9]+\.[0-9]+%' | tail -1 | tr -d '%')"
    if [ -n "$PCT" ]; then
      printf '{"total": %s, "tool": "cargo-tarpaulin"}\n' "$PCT"
    else
      printf '{}\n'
    fi
    ;;
  *)
    printf '{}\n'
    ;;
esac
