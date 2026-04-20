#!/bin/bash
# MCL repo validator — two independent checks:
#   1. Hook JSON well-formedness under representative inputs.
#   2. Skill-file mcl_* XML tag balance.
# Run before every commit that touches hooks or skill files.
# Exit 0 = all green. Exit 1 = at least one failure.

set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_DIR="$REPO_DIR/hooks"
SKILL_DIR="$REPO_DIR/skills/my-claude-lang"
FAIL=0

say_ok()   { echo "[OK] $1"; }
say_fail() { echo "[FAIL] $1"; FAIL=1; }

# ---------- 1. JSON well-formedness ----------

check_json_path() {
  local label="$1" cmd="$2"
  local out err
  out="$(mktemp)"; err="$(mktemp)"
  if bash -c "$cmd" > "$out" 2> "$err"; then
    if python3 -m json.tool < "$out" > /dev/null 2>&1; then
      say_ok "$label"
    else
      say_fail "$label — output is not valid JSON"
      head -c 400 "$out"; echo
    fi
  else
    say_fail "$label — hook exited non-zero"
    head -c 400 "$err"; echo
  fi
  rm -f "$out" "$err"
}

echo "=== JSON checks ==="

check_json_path "mcl-activate.sh (normal path)" \
  "echo '{}' | bash '$HOOK_DIR/mcl-activate.sh'"

check_json_path "mcl-activate.sh (mcl-update path)" \
  "printf '%s' '{\"prompt\":\"mcl-update\"}' | bash '$HOOK_DIR/mcl-activate.sh'"

SANDBOX="$(mktemp -d -t mcl-validate-XXXXXX)"
mkdir -p "$SANDBOX/.mcl"

printf '%s\n' '{"schema_version":1,"current_phase":1,"phase_name":"COLLECT","spec_approved":false,"spec_hash":null,"last_update":0}' \
  > "$SANDBOX/.mcl/state.json"
check_json_path "mcl-pre-tool.sh (phase-lock deny)" \
  "MCL_STATE_DIR='$SANDBOX/.mcl' bash -c \"echo '{\\\"tool_name\\\":\\\"Edit\\\"}' | bash '$HOOK_DIR/mcl-pre-tool.sh'\""

printf '%s\n' '{"schema_version":1,"current_phase":4,"phase_name":"EXECUTE","spec_approved":true,"spec_hash":"a","last_update":0,"drift_detected":true,"drift_hash":"b"}' \
  > "$SANDBOX/.mcl/state.json"
check_json_path "mcl-pre-tool.sh (drift deny)" \
  "MCL_STATE_DIR='$SANDBOX/.mcl' bash -c \"echo '{\\\"tool_name\\\":\\\"Edit\\\"}' | bash '$HOOK_DIR/mcl-pre-tool.sh'\""

rm -rf "$SANDBOX"

echo ""
echo "=== XML balance checks ==="

if [ ! -d "$SKILL_DIR" ]; then
  say_fail "Skill dir missing: $SKILL_DIR"
else
  # mcl-tag-schema.md is the schema documentation — it references tags
  # as examples, not as wrappers. Balance check doesn't apply.
  for f in "$SKILL_DIR"/*.md; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    if [ "$base" = "mcl-tag-schema.md" ]; then
      echo "[SKIP] $base (schema doc — tags are referenced, not wrapped)"
      continue
    fi
    result="$(python3 - "$f" <<'PY'
import sys, re
from collections import Counter
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
opens = re.findall(r"<(mcl_[a-z_0-9]+)(?:\s[^>]*)?>", text)
closes = re.findall(r"</(mcl_[a-z_0-9]+)>", text)
oc, cc = Counter(opens), Counter(closes)
problems = []
for tag in sorted(set(list(oc) + list(cc))):
    if oc[tag] != cc[tag]:
        problems.append(f"{tag}: {oc[tag]} open vs {cc[tag]} close")
if problems:
    print("FAIL")
    for p in problems:
        print(p)
else:
    print("OK")
PY
)"
    if [ "$(printf '%s' "$result" | head -1)" = "OK" ]; then
      say_ok "$base"
    else
      say_fail "$base"
      printf '%s\n' "$result" | tail -n +2 | sed 's/^/    /'
    fi
  done
fi

# Also check repo CLAUDE.md
if [ -f "$REPO_DIR/CLAUDE.md" ]; then
  result="$(python3 - "$REPO_DIR/CLAUDE.md" <<'PY'
import sys, re
from collections import Counter
text = open(sys.argv[1], encoding="utf-8").read()
opens = re.findall(r"<(mcl_[a-z_0-9]+)(?:\s[^>]*)?>", text)
closes = re.findall(r"</(mcl_[a-z_0-9]+)>", text)
oc, cc = Counter(opens), Counter(closes)
problems = [f"{t}: {oc[t]} open vs {cc[t]} close"
            for t in sorted(set(list(oc) + list(cc))) if oc[t] != cc[t]]
print("OK" if not problems else "FAIL")
for p in problems:
    print(p)
PY
)"
  if [ "$(printf '%s' "$result" | head -1)" = "OK" ]; then
    say_ok "CLAUDE.md"
  else
    say_fail "CLAUDE.md"
    printf '%s\n' "$result" | tail -n +2 | sed 's/^/    /'
  fi
fi

echo ""
if [ "$FAIL" = "0" ]; then
  echo "[OK] All validation checks passed."
  exit 0
else
  echo "[FAIL] Validation failed."
  exit 1
fi
