#!/bin/bash
# Regression: superpowers must NOT appear in the gate's required-plugin set.
# security-guidance must still be present (curated tier-A required).

echo "--- test-plugin-gate-no-superpowers ---"

_required="$(bash "$REPO_ROOT/hooks/lib/mcl-plugin-gate.sh" required-plugins "$REPO_ROOT" 2>/dev/null)"

if printf '%s' "$_required" | grep -qx "superpowers"; then
  FAIL=$((FAIL+1))
  printf '  FAIL: gate must not require superpowers\n'
  printf '        required-plugins output:\n%s\n' "$_required"
else
  PASS=$((PASS+1))
  printf '  PASS: gate does not require superpowers\n'
fi

if printf '%s' "$_required" | grep -qx "security-guidance"; then
  PASS=$((PASS+1))
  printf '  PASS: gate still requires security-guidance\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: gate must still require security-guidance\n'
  printf '        required-plugins output:\n%s\n' "$_required"
fi
