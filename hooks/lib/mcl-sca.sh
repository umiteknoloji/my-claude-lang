#!/usr/bin/env bash
# MCL SCA wrapper — invokes language-specific vulnerability scanners
# based on stack tags and emits a normalized JSON list of findings.
#
# Usage: bash mcl-sca.sh <project-dir> <stack-tags-csv>
# Stdout: JSON array of finding dicts (severity, source=sca, rule_id, file, line, message, owasp=A06, ...)
# Stderr: progress / warnings
# Exit: 0 always (errors yield empty array)
#
# Since 8.7.0.

set -uo pipefail

PROJECT_DIR="${1:-$PWD}"
STACK_TAGS_CSV="${2:-}"

cd "$PROJECT_DIR" || exit 0

# Helper: emit an empty array and exit cleanly.
_empty_and_exit() { printf '[]\n'; exit 0; }

# Collect findings into a temp JSONL and then convert.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

_emit() {
  # args: severity rule_id file message
  python3 -c '
import json, sys
print(json.dumps({
  "severity": sys.argv[1],
  "source": "sca",
  "rule_id": sys.argv[2],
  "file": sys.argv[3],
  "line": 0,
  "message": sys.argv[4],
  "owasp": "A06",
  "asvs": "V14.2.1",
  "category": "vulnerable-dep",
  "autofix": None,
}))
' "$1" "$2" "$3" "$4" >> "$TMP"
}

_has_tag() {
  case ",$STACK_TAGS_CSV," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---- npm audit (typescript / javascript / react-frontend / vue-frontend / svelte-frontend) ----
if _has_tag "typescript" || _has_tag "javascript" || _has_tag "react-frontend" || _has_tag "vue-frontend" || _has_tag "svelte-frontend"; then
  if command -v npm >/dev/null 2>&1 && [ -f "package-lock.json" ]; then
    NPM_OUT="$(npm audit --json 2>/dev/null || true)"
    if [ -n "$NPM_OUT" ]; then
      python3 -c '
import json, sys
data = json.loads(sys.stdin.read() or "{}")
sev_map = {"critical":"HIGH", "high":"HIGH", "moderate":"MEDIUM", "low":"LOW", "info":"LOW"}
for name, vuln in (data.get("vulnerabilities") or {}).items():
    sev = sev_map.get((vuln.get("severity") or "").lower(), "LOW")
    via = vuln.get("via") or []
    title = via[0].get("title") if via and isinstance(via[0], dict) else f"vulnerable: {name}"
    print(json.dumps({
      "severity": sev, "source": "sca",
      "rule_id": f"sca-npm-{name}",
      "file": "package-lock.json", "line": 0,
      "message": (title or f"npm dep {name} vulnerable")[:200],
      "owasp": "A06", "asvs": "V14.2.1",
      "category": "vulnerable-dep", "autofix": None,
    }))
' <<< "$NPM_OUT" >> "$TMP"
    fi
  elif command -v npm >/dev/null 2>&1 && [ -f "package.json" ]; then
    echo "[MCL/SCA] npm audit needs package-lock.json (run npm install first)" >&2
  fi
fi

# ---- pip-audit / safety (python) ----
if _has_tag "python"; then
  if command -v pip-audit >/dev/null 2>&1; then
    PA_OUT="$(pip-audit --format json 2>/dev/null || true)"
    if [ -n "$PA_OUT" ]; then
      python3 -c '
import json, sys
data = json.loads(sys.stdin.read() or "[]")
for entry in data:
    name = entry.get("name", "?")
    for vuln in entry.get("vulns", []):
        sev = "HIGH" if vuln.get("severity") in ("CRITICAL","HIGH") else "MEDIUM"
        print(json.dumps({
          "severity": sev, "source": "sca",
          "rule_id": f"sca-pip-{name}-{vuln.get(\"id\",\"?\")}",
          "file": "requirements.txt", "line": 0,
          "message": (vuln.get("description","") or f"vulnerable: {name}")[:200],
          "owasp": "A06", "asvs": "V14.2.1",
          "category": "vulnerable-dep", "autofix": None,
        }))
' <<< "$PA_OUT" >> "$TMP"
    fi
  else
    echo "[MCL/SCA] pip-audit not installed; skipping Python SCA" >&2
  fi
fi

# ---- cargo audit (rust) ----
if _has_tag "rust"; then
  if command -v cargo-audit >/dev/null 2>&1 && [ -f "Cargo.lock" ]; then
    CA_OUT="$(cargo audit --json 2>/dev/null || true)"
    if [ -n "$CA_OUT" ]; then
      python3 -c '
import json, sys
data = json.loads(sys.stdin.read() or "{}")
for v in (data.get("vulnerabilities", {}) or {}).get("list", []):
    advisory = v.get("advisory", {})
    name = (v.get("package") or {}).get("name", "?")
    print(json.dumps({
      "severity": "HIGH", "source": "sca",
      "rule_id": f"sca-cargo-{name}-{advisory.get(\"id\",\"?\")}",
      "file": "Cargo.lock", "line": 0,
      "message": (advisory.get("title") or f"vulnerable: {name}")[:200],
      "owasp": "A06", "asvs": "V14.2.1",
      "category": "vulnerable-dep", "autofix": None,
    }))
' <<< "$CA_OUT" >> "$TMP"
    fi
  else
    [ -f "Cargo.lock" ] && echo "[MCL/SCA] cargo-audit not installed; skipping Rust SCA" >&2
  fi
fi

# ---- govulncheck (go) ----
if _has_tag "go"; then
  if command -v govulncheck >/dev/null 2>&1 && [ -f "go.mod" ]; then
    GV_OUT="$(govulncheck -json ./... 2>/dev/null || true)"
    if [ -n "$GV_OUT" ]; then
      # govulncheck JSON is line-delimited stream; parse defensively.
      python3 -c '
import json, sys
emitted = 0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    if "finding" not in obj:
        continue
    f = obj["finding"]
    osv = f.get("osv","?")
    msg = f.get("trace",[{}])[0].get("module","?") + " — " + osv
    print(json.dumps({
      "severity": "HIGH", "source": "sca",
      "rule_id": f"sca-go-{osv}",
      "file": "go.mod", "line": 0,
      "message": msg[:200],
      "owasp": "A06", "asvs": "V14.2.1",
      "category": "vulnerable-dep", "autofix": None,
    }))
    emitted += 1
' <<< "$GV_OUT" >> "$TMP"
    fi
  fi
fi

# ---- bundle audit (ruby) ----
if _has_tag "ruby"; then
  if command -v bundle-audit >/dev/null 2>&1 && [ -f "Gemfile.lock" ]; then
    BA_OUT="$(bundle-audit check --format json 2>/dev/null || true)"
    if [ -n "$BA_OUT" ]; then
      python3 -c '
import json, sys
data = json.loads(sys.stdin.read() or "{}")
for r in data.get("results", []):
    name = r.get("gem", {}).get("name", "?")
    adv = r.get("advisory", {})
    sev_map = {"critical":"HIGH","high":"HIGH","medium":"MEDIUM","low":"LOW"}
    sev = sev_map.get((adv.get("criticality") or "").lower(), "MEDIUM")
    print(json.dumps({
      "severity": sev, "source": "sca",
      "rule_id": f"sca-ruby-{name}-{adv.get(\"id\",\"?\")}",
      "file": "Gemfile.lock", "line": 0,
      "message": (adv.get("title") or f"vulnerable: {name}")[:200],
      "owasp": "A06", "asvs": "V14.2.1",
      "category": "vulnerable-dep", "autofix": None,
    }))
' <<< "$BA_OUT" >> "$TMP"
    fi
  fi
fi

# Emit as JSON array.
if [ -s "$TMP" ]; then
  python3 -c '
import json, sys
arr = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        arr.append(json.loads(line))
    except Exception:
        continue
print(json.dumps(arr))
' < "$TMP"
else
  printf '[]\n'
fi
