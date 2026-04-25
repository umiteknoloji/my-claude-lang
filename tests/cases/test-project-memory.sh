#!/bin/bash
# Test: project memory injection and proactive notice.

echo "--- test-project-memory ---"

_pm_dir="$(setup_test_dir)"

# Case 1: No project.md → no injection.
# Check: </mcl_project_memory> absent (closing tag only present when actually injected;
# STATIC_CONTEXT only references the opening tag in rule text).
_out="$(run_activate_hook "$_pm_dir" "Login sayfası yap")"
assert_json_valid "no project.md → valid JSON" "$_out"
python3 -c "
import json, sys
ctx = json.loads(sys.argv[1])['hookSpecificOutput']['additionalContext']
assert '</mcl_project_memory>' not in ctx, 'unexpected project_memory injection'
print('  PASS: no project.md → no injection')
" "$_out" 2>/dev/null && PASS=$((PASS+1)) || { echo "  FAIL: no project.md → unexpected injection"; FAIL=$((FAIL+1)); }

# Case 2: project.md exists → closing tag present, content visible.
cat > "$_pm_dir/.mcl/project.md" << 'PMEOF'
# Test Projesi

**Stack:** TypeScript, React
**Güncelleme:** 2026-04-25

## Mimari
- JWT auth, session yok

## Teknik Borç
- [ ] UserService unit testleri eksik

## Bilinen Sorunlar
- [ ] Product list N+1 sorunu
PMEOF

_out="$(run_activate_hook "$_pm_dir" "Login sayfası yap")"
assert_json_valid "project.md → valid JSON" "$_out"
assert_contains "project.md → closing tag present" "$_out" "</mcl_project_memory>"
assert_contains "project.md → stack visible (TypeScript)" "$_out" "TypeScript"

# Case 3: open items → proactive notice injected.
assert_contains "open items → proactive-items notice" "$_out" "proactive-items"
assert_contains "open items → item text visible" "$_out" "UserService"

# Case 4: project.md with no open items → memory injected but no proactive notice.
cat > "$_pm_dir/.mcl/project.md" << 'PMEOF2'
# Test Projesi

**Stack:** TypeScript
**Güncelleme:** 2026-04-25

## Teknik Borç
- [x] Login sayfası (2026-04-24)
PMEOF2

_out="$(run_activate_hook "$_pm_dir" "Dashboard yap")"
assert_json_valid "no open items → valid JSON" "$_out"
assert_contains "no open items → memory still injected" "$_out" "</mcl_project_memory>"
python3 -c "
import json, sys
ctx = json.loads(sys.argv[1])['hookSpecificOutput']['additionalContext']
# proactive-items only from PROACTIVE_NOTICE, not from STATIC_CONTEXT rule text
# STATIC_CONTEXT says: 'mcl_audit name=\"proactive-items\"' — check the closing </mcl_audit>
# that immediately follows the PROACTIVE notice content
assert 'PROACTIVE ITEMS' not in ctx, 'unexpected proactive items when no open items'
print('  PASS: no open items → no proactive notice')
" "$_out" 2>/dev/null && PASS=$((PASS+1)) || { echo "  FAIL: no open items → unexpected proactive notice"; FAIL=$((FAIL+1)); }

cleanup_test_dir "$_pm_dir"
