#!/usr/bin/env bash
# MCL UI ESLint a11y delegate.
# Usage: bash mcl-ui-eslint.sh <project-dir> <stack-tags-csv> <files...>
# Stdout: JSON array of findings (severity, source=eslint, rule_id, file, line, message, category=ui-a11y)
# Exit: 0 always.
# Since 8.9.0.

set -uo pipefail

PROJECT_DIR="${1:-$PWD}"
STACK_TAGS_CSV="${2:-}"
shift 2 2>/dev/null || true
FILES=("$@")

cd "$PROJECT_DIR" || { printf '[]\n'; exit 0; }

if ! command -v npx >/dev/null 2>&1; then
  printf '[]\n'; exit 0
fi

# Pick relevant a11y rules per framework.
RULES=""
case ",$STACK_TAGS_CSV," in
  *",react-frontend,"*)
    RULES="jsx-a11y/alt-text,jsx-a11y/anchor-is-valid,jsx-a11y/click-events-have-key-events,jsx-a11y/no-static-element-interactions,jsx-a11y/role-has-required-aria-props"
    ;;
  *",vue-frontend,"*)
    RULES="vuejs-accessibility/alt-text,vuejs-accessibility/anchor-has-content,vuejs-accessibility/form-control-has-label,vuejs-accessibility/click-events-have-key-events"
    ;;
  *",svelte-frontend,"*)
    RULES="svelte/a11y-img-redundant-alt,svelte/a11y-no-onchange,svelte/a11y-click-events-have-key-events"
    ;;
esac

if [ -z "$RULES" ] || [ ${#FILES[@]} -eq 0 ]; then
  printf '[]\n'; exit 0
fi

# Try eslint with --no-eslintrc (avoid project conflicts) — best-effort.
ESLINT_OUT="$(npx --no-install eslint --format json --no-eslintrc \
  --parser-options ecmaFeatures:'{"jsx":true}' \
  --rule "{}" \
  "${FILES[@]}" 2>/dev/null || true)"

if [ -z "$ESLINT_OUT" ]; then
  echo "[MCL/UI] eslint a11y plugin not available; skip" >&2
  printf '[]\n'; exit 0
fi

python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read() or "[]")
except json.JSONDecodeError:
    print("[]"); sys.exit(0)
out = []
for entry in data:
    fp = entry.get("filePath", "?")
    for msg in entry.get("messages", []):
        rid = msg.get("ruleId") or "eslint-unknown"
        if "a11y" not in rid and "accessibility" not in rid:
            continue
        sev = "HIGH" if msg.get("severity") == 2 else "MEDIUM"
        out.append({
            "severity": sev, "source": "eslint", "rule_id": f"eslint-{rid}",
            "file": fp, "line": msg.get("line", 0),
            "message": (msg.get("message") or "")[:200],
            "category": "ui-a11y", "framework": "", "autofix": None,
        })
print(json.dumps(out))
' <<< "$ESLINT_OUT"
