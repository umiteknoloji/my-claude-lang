#!/bin/bash
# MCL Config — .mcl/config.json reader (opt-in developer config).
#
# Sourceable library AND CLI. Reads optional developer config at
# <project>/.mcl/config.json. Missing file is normal (opt-in): returns
# empty output, exit 0. Malformed JSON prints a stderr warning and
# returns empty output, exit 0 — never crashes the caller.
#
# Schema (all fields optional, add more as new features land):
#   {
#     "test_command":                "npm test",
#     "test_command_timeout_seconds": 120,
#     "_warning": "test_command runs in your shell with no isolation — MCL does not sandbox it."
#   }
#
# Fields whose name begins with `_` are ignored by the loader. This
# is the JSON-without-comments convention — the file can carry a
# human-visible warning without the loader treating it as config.
#
# CLI:
#   mcl-config.sh get <field>        # read-only, prints scalar value
#
# Sourced:
#   source hooks/lib/mcl-config.sh
#   cmd="$(mcl_config_get test_command)"
#   [ -n "$cmd" ] || exit 0

set -u

MCL_CONFIG_DIR="${MCL_CONFIG_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}/.mcl}"
MCL_CONFIG_FILE="${MCL_CONFIG_FILE:-$MCL_CONFIG_DIR/config.json}"

mcl_config_get() {
  # mcl_config_get <field> — prints the field value.
  #   strings  → printed without quotes
  #   numbers  → printed as literal
  #   booleans → "true"/"false"
  #   objects/arrays → printed as JSON (rare; not used by v1 callers)
  # Empty stdout (exit 0) for any of:
  #   - no field argument
  #   - field name starts with `_` (ignored by convention)
  #   - config file missing
  #   - config file empty
  #   - JSON malformed (stderr warning printed)
  #   - root is not a JSON object (stderr warning printed)
  #   - field absent or null
  local field="${1:-}"
  [ -n "$field" ] || return 0
  [ -f "$MCL_CONFIG_FILE" ] || return 0
  local body
  body="$(cat "$MCL_CONFIG_FILE" 2>/dev/null)"
  [ -n "$body" ] || return 0
  printf '%s' "$body" | python3 -c '
import json, sys
field = sys.argv[1]
path  = sys.argv[2]
if field.startswith("_"):
    sys.exit(0)
try:
    obj = json.loads(sys.stdin.read())
except Exception as e:
    print("mcl-config: malformed JSON at " + path + " — " + str(e), file=sys.stderr)
    sys.exit(0)
if not isinstance(obj, dict):
    print("mcl-config: root of " + path + " is not a JSON object", file=sys.stderr)
    sys.exit(0)
val = obj.get(field)
if val is None:
    sys.exit(0)
if isinstance(val, bool):
    print("true" if val else "false")
elif isinstance(val, (int, float)):
    print(val)
elif isinstance(val, str):
    print(val)
else:
    print(json.dumps(val))
' "$field" "$MCL_CONFIG_FILE"
}

# CLI dispatch — only when invoked directly, not when sourced.
# READ-ONLY from CLI. No write operations exist in v1.
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
  cmd="${1:-}"
  case "$cmd" in
    get)
      shift
      mcl_config_get "${1:-}"
      ;;
    *)
      echo "usage: $0 get <field>" >&2
      exit 2
      ;;
  esac
fi
