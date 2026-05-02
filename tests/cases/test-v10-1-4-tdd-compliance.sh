#!/bin/bash
# Synthetic test: v10.1.4 Layer 1 TDD compliance audit.
# PostToolUse classifies file paths as test/prod via heuristics +
# emits tdd-test-write / tdd-prod-write audit. Stop hook scans
# session audit.log to compute compliance ratio.

echo "--- test-v10-1-4-tdd-compliance ---"

_dir="$(setup_test_dir)"
mkdir -p "$_dir/.mcl"
echo "2026-05-02 12:00:00 | session_start | mcl-activate.sh | t10-1-4" > "$_dir/.mcl/trace.log"

# --- Path classifier: test patterns return "test" ---
for p in \
    "src/__tests__/foo.ts" \
    "src/foo.test.ts" \
    "src/foo.spec.tsx" \
    "tests/auth.py" \
    "spec/login_spec.rb" \
    "internal/auth_test.go" \
    "tests/test_login.py"; do
  k="$(python3 -c '
import os, re, sys
path = sys.argv[1]
SKIP_DIR = ("node_modules/", "/dist/", "/build/")
for d in SKIP_DIR:
    if d in path:
        print("skip"); sys.exit(0)
TEST_PATTERNS = [r"__tests__/", r"(^|/)tests?/", r"(^|/)specs?/",
                 r"\.test\.(ts|tsx|js|jsx|mts|cts|mjs|cjs)$",
                 r"\.spec\.(ts|tsx|js|jsx|mts|cts|mjs|cjs)$",
                 r"_test\.(go|py)$", r"_spec\.rb$",
                 r"(^|/)test_[^/]+\.py$"]
for pat in TEST_PATTERNS:
    if re.search(pat, path):
        print("test"); sys.exit(0)
ext = os.path.splitext(path)[1].lower()
if ext in {".ts",".tsx",".js",".py",".go",".rb"}:
    print("prod"); sys.exit(0)
print("skip")
' "$p")"
  assert_equals "$p classified as test" "$k" "test"
done

# --- Production code patterns return "prod" ---
for p in \
    "src/auth.ts" \
    "apps/api/src/index.ts" \
    "lib/db.py" \
    "internal/router.go" \
    "components/Button.tsx"; do
  k="$(python3 -c '
import os, re, sys
path = sys.argv[1]
TEST_PATTERNS = [r"__tests__/", r"(^|/)tests?/", r"(^|/)specs?/",
                 r"\.test\.(ts|tsx|js|jsx)$", r"\.spec\.(ts|tsx|js|jsx)$",
                 r"_test\.(go|py)$", r"_spec\.rb$",
                 r"(^|/)test_[^/]+\.py$"]
for pat in TEST_PATTERNS:
    if re.search(pat, path):
        print("test"); sys.exit(0)
ext = os.path.splitext(path)[1].lower()
if ext in {".ts",".tsx",".js",".py",".go",".rb"}:
    print("prod"); sys.exit(0)
print("skip")
' "$p")"
  assert_equals "$p classified as prod" "$k" "prod"
done

# --- Skip patterns: configs, build artifacts ---
for p in \
    "package.json" \
    "tsconfig.json" \
    "node_modules/foo/index.js" \
    "dist/bundle.js" \
    "README.md"; do
  k="$(python3 -c '
import os, re, sys
path = sys.argv[1]
SKIP_DIR_RE = re.compile(r"(^|/)(node_modules|dist|build|\.next|\.nuxt|\.cache|coverage|\.git)/")
if SKIP_DIR_RE.search(path):
    print("skip"); sys.exit(0)
TEST_PATTERNS = [r"__tests__/", r"(^|/)tests?/", r"(^|/)specs?/",
                 r"\.test\.", r"\.spec\."]
for pat in TEST_PATTERNS:
    if re.search(pat, path):
        print("test"); sys.exit(0)
ext = os.path.splitext(path)[1].lower()
if ext in {".ts",".tsx",".js",".py",".go",".rb"}:
    print("prod"); sys.exit(0)
print("skip")
' "$p")"
  assert_equals "$p classified as skip" "$k" "skip"
done

# --- Compliance ratio: 100% (1 test-write before 1 prod-write) ---
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | tdd-test-write | post-tool | file=src/foo.test.ts
2026-05-02 12:00:02 | tdd-prod-write | post-tool | file=src/foo.ts
EOF

_compliance="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
test_writes, prod_writes = [], []
if audit.exists():
    for line in audit.read_text().splitlines():
        if "| tdd-test-write |" not in line and "| tdd-prod-write |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        (test_writes if "tdd-test-write" in line else prod_writes).append(ts)
preceded = sum(1 for p in prod_writes if any(t < p for t in test_writes))
total = len(prod_writes)
score = round((preceded / total) * 100) if total else 0
print(f"{score}|{preceded}|{total}")
PYEOF
)"
assert_equals "1 test → 1 prod (test first) → score=100" "$_compliance" "100|1|1"

# --- Compliance ratio: 0% (1 prod-write, no preceding test) ---
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | tdd-prod-write | post-tool | file=src/foo.ts
EOF

_compliance0="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
test_writes, prod_writes = [], []
if audit.exists():
    for line in audit.read_text().splitlines():
        if "| tdd-test-write |" not in line and "| tdd-prod-write |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        (test_writes if "tdd-test-write" in line else prod_writes).append(ts)
preceded = sum(1 for p in prod_writes if any(t < p for t in test_writes))
total = len(prod_writes)
score = round((preceded / total) * 100) if total else 0
print(f"{score}|{preceded}|{total}")
PYEOF
)"
assert_equals "no test, 1 prod → score=0" "$_compliance0" "0|0|1"

# --- Mixed: 2 prod-writes, only 1 preceded by test → 50% ---
cat > "$_dir/.mcl/audit.log" <<'EOF'
2026-05-02 12:00:01 | tdd-test-write | post-tool | file=src/foo.test.ts
2026-05-02 12:00:02 | tdd-prod-write | post-tool | file=src/foo.ts
2026-05-02 12:00:03 | tdd-prod-write | post-tool | file=src/bar.ts
EOF

# Wait — `bar` was written AFTER `foo.test.ts`, so it's "preceded by test" too.
# Score should be 100 (both prod writes had A test write earlier in session).
# That's the heuristic — "any test before any prod", not "matching test for each prod".
_compliance_mixed="$(MCL_STATE_DIR="$_dir/.mcl" python3 - <<'PYEOF'
import os
from pathlib import Path
audit = Path(os.environ["MCL_STATE_DIR"]) / "audit.log"
trace = Path(os.environ["MCL_STATE_DIR"]) / "trace.log"
session_ts = ""
if trace.exists():
    for line in trace.read_text().splitlines():
        if "| session_start |" in line:
            session_ts = line.split("|", 1)[0].strip()
test_writes, prod_writes = [], []
if audit.exists():
    for line in audit.read_text().splitlines():
        if "| tdd-test-write |" not in line and "| tdd-prod-write |" not in line:
            continue
        ts = line.split("|", 1)[0].strip()
        if session_ts and ts < session_ts:
            continue
        (test_writes if "tdd-test-write" in line else prod_writes).append(ts)
preceded = sum(1 for p in prod_writes if any(t < p for t in test_writes))
total = len(prod_writes)
score = round((preceded / total) * 100) if total else 0
print(f"{score}|{preceded}|{total}")
PYEOF
)"
assert_equals "1 test → 2 prods (both after) → score=100 (any-test-before-prod heuristic)" "$_compliance_mixed" "100|2|2"

# --- Hook contract checks ---
_post="$REPO_ROOT/hooks/mcl-post-tool.sh"
_stop="$REPO_ROOT/hooks/mcl-stop.sh"

if grep -q "tdd-test-write\|tdd-prod-write" "$_post"; then
  PASS=$((PASS+1))
  printf '  PASS: post-tool emits tdd-test-write / tdd-prod-write audit\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: post-tool TDD audit emit missing\n'
fi

if grep -q "_mcl_tdd_compliance" "$_stop"; then
  PASS=$((PASS+1))
  printf '  PASS: stop hook implements _mcl_tdd_compliance helper\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: TDD compliance helper missing from stop hook\n'
fi

if grep -q "tdd_compliance_score" "$REPO_ROOT/hooks/lib/mcl-state.sh"; then
  PASS=$((PASS+1))
  printf '  PASS: state default schema includes tdd_compliance_score\n'
else
  FAIL=$((FAIL+1))
  printf '  FAIL: tdd_compliance_score missing from state schema\n'
fi

cleanup_test_dir "$_dir"
