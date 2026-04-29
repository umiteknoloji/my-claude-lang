#!/usr/bin/env bash
# MCL Perf Lighthouse — opt-in CWV scan (8.14.0).
# Reuses MCL_UI_URL env var (shared with /mcl-ui-axe). User sets one
# URL, both axe and lighthouse work against it.
# Usage:
#   bash mcl-perf-lighthouse.sh <project-dir> [lang]      # advisory mode if URL unset
#   --json: emit machine JSON for orchestrator dispatch (no markdown)

set -uo pipefail
PROJECT_DIR="${1:-$PWD}"
LANG_CODE="${2:-en}"
JSON_MODE="${3:-}"

if [ -z "${MCL_UI_URL:-}" ]; then
  if [ "$JSON_MODE" = "--json" ]; then
    printf '{"ran":false,"reason":"no-MCL_UI_URL"}\n'
    exit 0
  fi
  if [ "$LANG_CODE" = "tr" ]; then
    cat <<'TR'
# Performans Raporu (Lighthouse)

`MCL_UI_URL` çevre değişkeni ayarlı değil. Bu komut canlı bir UI URL'sine
Lighthouse ile bağlanıp Core Web Vitals (LCP / CLS / TBT) ölçer.

Etkinleştirmek için (axe + lighthouse aynı env var'ı kullanır):
```
# Önce dev server'ı başlat
export MCL_UI_URL="http://localhost:3000"
mcl-claude
```

Sonra `/mcl-perf-lighthouse` (CWV) veya `/mcl-ui-axe` (a11y) tetiklenebilir.

Gereksinim: `npx lighthouse` çalışmalı (npm üzerinden gelir).
TR
  else
    cat <<'EN'
# Performance Report (Lighthouse)

`MCL_UI_URL` env var is not set. This command connects to a live UI URL
via Lighthouse and measures Core Web Vitals (LCP / CLS / TBT).

To enable (axe and lighthouse share the same env):
```
# Start dev server first
export MCL_UI_URL="http://localhost:3000"
mcl-claude
```

Then `/mcl-perf-lighthouse` (CWV) or `/mcl-ui-axe` (a11y) will run.

Requirement: `npx lighthouse` available (via npm).
EN
  fi
  exit 0
fi

cd "$PROJECT_DIR" || exit 0

if ! command -v npx >/dev/null 2>&1; then
  if [ "$JSON_MODE" = "--json" ]; then
    printf '{"ran":false,"reason":"npx-missing"}\n'
  else
    echo "# Performance Report — 'npx' not found on PATH" >&2
  fi
  exit 0
fi

OUT_FILE="$(mktemp -t mcl-lh-XXXXXX).json"
trap 'rm -f "$OUT_FILE"' EXIT

if ! timeout 90 npx --no-install lighthouse "$MCL_UI_URL" \
    --output=json --output-path="$OUT_FILE" \
    --only-categories=performance \
    --quiet --chrome-flags="--headless --no-sandbox" 2>/dev/null; then
  if [ "$JSON_MODE" = "--json" ]; then
    printf '{"ran":false,"reason":"lighthouse-error","url":"%s"}\n' "$MCL_UI_URL"
  else
    echo "# Performance Report — Lighthouse failed (binary missing or URL unreachable)" >&2
  fi
  exit 0
fi

PARSED="$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(json.dumps({"ran": False, "reason": "parse-error", "error": str(e)})); sys.exit(0)
audits = d.get("audits", {})
def num(key, sub="numericValue"):
    a = audits.get(key, {})
    return a.get(sub)
print(json.dumps({
    "ran": True,
    "url": sys.argv[2],
    "lcp_ms": num("largest-contentful-paint"),
    "cls": num("cumulative-layout-shift"),
    "tbt_ms": num("total-blocking-time"),
    "tti_ms": num("interactive"),
    "fcp_ms": num("first-contentful-paint"),
    "perf_score": (d.get("categories", {}).get("performance", {}) or {}).get("score"),
}))
' "$OUT_FILE" "$MCL_UI_URL")"

if [ "$JSON_MODE" = "--json" ]; then
  printf '%s\n' "$PARSED"
  exit 0
fi

# Markdown rendering for direct keyword display
if [ "$LANG_CODE" = "tr" ]; then
  echo "# Performans Raporu (Lighthouse) — $MCL_UI_URL"
else
  echo "# Performance Report (Lighthouse) — $MCL_UI_URL"
fi
echo
echo '```json'
echo "$PARSED" | python3 -m json.tool 2>/dev/null || echo "$PARSED"
echo '```'
