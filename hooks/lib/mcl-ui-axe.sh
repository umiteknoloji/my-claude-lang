#!/usr/bin/env bash
# MCL UI axe — opt-in runtime a11y scan.
# Usage: bash mcl-ui-axe.sh <project-dir> [lang]
# Reads MCL_UI_URL env. If unset → localized advisory.
# If set → tries Playwright + @axe-core/playwright headless scan.
# Since 8.9.0.

set -uo pipefail

PROJECT_DIR="${1:-$PWD}"
LANG_CODE="${2:-en}"

if [ -z "${MCL_UI_URL:-}" ]; then
  if [ "$LANG_CODE" = "tr" ]; then
    cat <<'TR'
# UI Erişilebilirlik (axe)

`MCL_UI_URL` çevre değişkeni ayarlı değil. Bu komut canlı bir UI URL'sine
Playwright ile bağlanıp axe-core ile a11y kontrolü çalıştırır; URL olmadan
çalışamaz.

Etkinleştirmek için:
```
# Önce dev server'ı başlat (npm run dev / vite / webpack-dev-server vb.)
export MCL_UI_URL="http://localhost:3000"
mcl-claude
```

Sonra `/mcl-ui-axe` yazdığında axe-core canlı sayfayı taraf.

Gereksinimler: `playwright` + `@axe-core/playwright` kurulu olmalı:
```
npm install --save-dev @playwright/test @axe-core/playwright
npx playwright install chromium
```
TR
  else
    cat <<'EN'
# UI Accessibility (axe)

`MCL_UI_URL` env var is not set. This command connects to a live UI URL
via Playwright and runs axe-core for accessibility checks; without a URL
it cannot run.

To enable:
```
# Start your dev server first (npm run dev / vite / webpack-dev-server)
export MCL_UI_URL="http://localhost:3000"
mcl-claude
```

Then `/mcl-ui-axe` will scan the live page.

Requirements: `playwright` + `@axe-core/playwright` installed:
```
npm install --save-dev @playwright/test @axe-core/playwright
npx playwright install chromium
```
EN
  fi
  exit 0
fi

cd "$PROJECT_DIR" || exit 0

if ! command -v npx >/dev/null 2>&1; then
  echo "# axe scan: 'npx' not found on PATH" >&2
  exit 0
fi

# Generate a tiny inline runner.
RUNNER="$(mktemp -t mcl-ui-axe-XXXXXX).js"
cat > "$RUNNER" <<'JS'
const { chromium } = require('playwright');
const AxeBuilder = require('@axe-core/playwright').default;
(async () => {
  const url = process.env.MCL_UI_URL;
  const browser = await chromium.launch();
  const page = await browser.newPage();
  try {
    await page.goto(url, { waitUntil: 'networkidle', timeout: 15000 });
    const results = await new AxeBuilder({ page }).analyze();
    console.log(JSON.stringify({ url, violations: results.violations }, null, 2));
  } catch (e) {
    console.error('axe error:', e.message);
  } finally {
    await browser.close();
  }
})();
JS

if [ "$LANG_CODE" = "tr" ]; then
  echo "# UI Erişilebilirlik (axe) — $MCL_UI_URL"
else
  echo "# UI Accessibility (axe) — $MCL_UI_URL"
fi
echo

OUT="$(node "$RUNNER" 2>&1 || true)"
rm -f "$RUNNER"

if echo "$OUT" | grep -q "axe error\|Cannot find module"; then
  echo "_axe runtime missing; install @axe-core/playwright + playwright (see /mcl-ui-axe with MCL_UI_URL unset for instructions)._"
  echo "$OUT" >&2
  exit 0
fi

echo '```json'
echo "$OUT"
echo '```'
