<mcl_constraint name="phase2-design-review-visual-inspect">

# Phase 4b — Visual Inspect (opt-in)

## What It Is

An opt-in capability that lets MCL actually SEE and INTERACT with
the UI it just built, so it can report defects before the developer
opens the browser themselves.

Pipeline:
1. Spin up the dev server (`npm run dev` / `yarn dev` / `pnpm dev`
   / `python -m http.server` depending on detected runner).
2. Drive a headless browser via Playwright to the emitted route.
3. Capture a screenshot to `.mcl/ui-snapshots/<timestamp>-<state>.png`.
4. Read the screenshot back with Claude's multimodal Read tool.
5. Write a structured observation report in the developer's language.
6. Re-call the Phase 4b review `AskUserQuestion`.

## Trigger

Only runs when the developer picks the "See it yourself and report"
option at the Phase 4b review `AskUserQuestion`. It is NOT automatic
and NOT a state flag — the skill is entered fresh each time the
developer requests inspection. Multiple inspections per Phase 4b
are allowed (revise → re-inspect → revise → re-inspect).

## Prerequisites (checked at entry, surfaced once)

- `playwright` must be installed (either in project deps or globally):
  check via `npx playwright --version`. If missing, emit a single
  install hint in the developer's language with the exact command
  (`npm install -D playwright && npx playwright install chromium`),
  then abort this inspection — do NOT auto-install. Return to the
  Phase 4b askq with the install hint visible.
- A dev-server runnable command (`npm run dev` etc.) must exist or
  have been detected. If not, abort with a clear message and return
  to askq.
- `.mcl/ui-snapshots/` directory is created if absent (allowed by
  UI-BUILD path exception since `.mcl/**` is always writable).

## The Inspect Script

Write a throwaway script at `.mcl/ui-snapshots/_inspect.mjs`:

```javascript
import { chromium } from 'playwright';

const url = process.argv[2] ?? 'http://localhost:5173/';
const outPath = process.argv[3] ?? '.mcl/ui-snapshots/shot.png';
const stateQuery = process.argv[4] ?? '';

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await page.goto(url + stateQuery, { waitUntil: 'networkidle', timeout: 15000 });
await page.screenshot({ path: outPath, fullPage: true });
await browser.close();
```

Path is `.mcl/ui-snapshots/_inspect.mjs` on purpose — leading
underscore marks it as internal, and `.mcl/**` is the only path
guaranteed writable in UI-BUILD mode.

## The Inspection Procedure

1. Start dev server in the background: `npm run dev &` (or detected
   equivalent). Capture PID. Wait for `http://localhost:<port>` to
   respond (poll with `curl -s` up to 20 seconds).
2. For each dev-toggleable state the component exposes (`success`,
   `loading`, `empty`, `error`) — run the inspect script with
   `?state=<name>` query param, saving to
   `.mcl/ui-snapshots/<timestamp>-<state>.png`.
3. Read each PNG back via the Read tool.
4. Kill the dev server (`kill <pid>`).
5. Draft the observation report (see format below).
6. Re-call the Phase 4b review askq with the report visible above it.

If the component exposes no state toggle, snapshot the default view
only.

## Observation Report Format

Render in the developer's language. Fixed structure:

```
🖼️  Visual Inspection Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Captured:  .mcl/ui-snapshots/<timestamp>-success.png (1280×800)
Captured:  .mcl/ui-snapshots/<timestamp>-loading.png
Captured:  .mcl/ui-snapshots/<timestamp>-empty.png
Captured:  .mcl/ui-snapshots/<timestamp>-error.png

What I see (success state):
  - <specific observation: layout, spacing, labels>
  - <specific observation>
  - <specific observation>

What looks wrong or worth a second look:
  - <concern 1 + why it is a concern>
  - <concern 2 + why>
  (omit section entirely if nothing stands out)

What I cannot judge from a screenshot alone:
  - <e.g. hover states, keyboard focus order, real data layout>
```

Rules for the "What I see" list:
- Report visible facts, not inferred intent ("button reads 'Save'",
  not "button probably saves the form").
- Mention specific numbers when layout is the point ("header takes
  top 88px", "form column is 420px wide on a 1280px viewport").
- Never claim the UI works correctly — behavior is not visible in a
  static screenshot.

## Failure Handling

- Dev server doesn't start within 20s → report the startup failure
  verbatim in the developer's language and return to askq. Do NOT
  retry silently.
- Screenshot fails (Playwright error, timeout) → report the error
  and return to askq. Still save any partial screenshots that did
  capture.
- Read tool rejects the PNG → extremely rare; if it happens, emit
  the file path so the developer can open it manually.

## What Visual-Inspect Does NOT Do

- No interaction beyond navigation to the URL. MCL does not click
  buttons, fill forms, or simulate user flows — those are Phase 5
  concerns via real test runners.
- No a11y scoring (axe-core). Visual-inspect is about what Claude
  can see with its multimodal eyes, nothing more.
- No cross-browser matrix. Chromium only. If the developer needs
  Firefox/WebKit parity, that is a separate spec.
- No mobile viewport unless the spec MUST required responsive
  verification.
- No persistence of screenshots past the current Phase 4b session.
  They live under `.mcl/ui-snapshots/` which is `.gitignore`d by
  MCL's installer; the developer can opt to keep them by removing
  the ignore entry.

## Privacy Note

Screenshots include whatever the dummy fixtures contain. Since Phase
4a forbids real PII in fixtures (see
`phase2-design-review/fixtures.md`), this pipeline should never capture
real user data. If the developer somehow seeded real data, that is
a Phase 4a violation caught here — surface it and refuse to write
snapshots.

</mcl_constraint>
