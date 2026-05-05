<mcl_phase name="asama6-ui-build">

# Aşama 6: BUILD_UI — Runnable Frontend with Dummy Data

## Entry Condition

Aşama 6 starts automatically when ALL of these hold after spec approval:

- `current_phase = 7`
- `spec_approved = true`
- `ui_flow_active = true` (set by Aşama 1 summary-confirm)
- `ui_reviewed = false`
- `ui_sub_phase = "BUILD_UI"` (set by stop hook on spec-approve)

When `ui_flow_active = false` (developer picked "Onay, UI atlayacağız" at
Aşama 1) — Aşama 6 is SKIPPED. Jump straight to `asama7-execute.md`.

## Core Intent

Write a **runnable** frontend with **dummy data only**, so the developer
can open it in their browser and verify the visual/UX shape BEFORE any
backend work happens. UI mockup and UI build are the same step — there
is no separate preview artifact.

## Sub-Topic Files

For dummy-data fixture conventions (inline constants, `__fixtures__/`
directory, loading/error/success toggles), read
`my-claude-lang/asama6-ui-build/fixtures.md`.

For framework-specific component syntax (React, Vue, Svelte, static
HTML), read `my-claude-lang/asama6-ui-build/frameworks.md`.

For styling fallbacks (when no design system is configured) and
neutrality rules, read `my-claude-lang/asama6-ui-build/styles.md`.

## Path Discipline (enforced by mcl-pre-tool.sh)

While `ui_sub_phase = "BUILD_UI"`, the pre-tool hook:

- **Allows** frontend paths AND build-tool config:
  `src/**/*.{tsx,jsx,vue,svelte,html,css,scss}`,
  `src/components/**`, `src/app/**`, `src/pages/**`,
  `src/**/__fixtures__/**`, `src/**/mocks/**`, `public/**`, `*.html`,
  `src/styles/**`, `tailwind.config.*`, `tsconfig*.json`, `jsconfig.json`,
  `postcss.config.*`, `vite.config.*`, `next.config.*`, `nuxt.config.*`,
  `package.json`, `.mcl/**`.
- **Denies** true backend paths: `src/api/**`, `src/server/**`,
  `src/services/**`, `src/lib/db/**`, `.env*`, `prisma/**`,
  `drizzle/**`, `vercel.json`, `netlify.toml`, `server.{js,ts,mjs}`.

Build tool configs (`vite.config.*`, `next.config.*`, `nuxt.config.*`,
`tailwind.config.*`, `tsconfig*`, `postcss.config.*`) are **explicitly
allowed** — they are needed to run `npm run dev` in Aşama 6. Writing
them in Aşama 6 is correct and required.

If Claude attempts to write a true backend path, the DENY reason says:
> MCL UI-BUILD LOCK — backend is unlocked in the TDD execute backend
> wiring step (`asama7-tdd.md` Step 5; was Aşama 6c) after the UI is
> approved. Keep dummy fixtures in the component for now.

## Curated Plugin Dispatch

Auto-dispatch `frontend-design` plugin silently when Aşama 6 starts
(Rule B — multi-angle validation). Merge its suggestions into the
component code / prose. Never expose the raw plugin output as a tool
call to the developer. See `my-claude-lang/plugin-suggestions.md` for
promotion details.

## Aşama 6 Procedure

1. Read the approved spec.
2. Detect framework from `mcl-stack-detect.sh` tags:
   `react-frontend` / `vue-frontend` / `svelte-frontend` / `html-static`
   / none (fallback to HTML + inline JS).
3. **Write build-tool config files FIRST** — `package.json` (if absent),
   `vite.config.ts`, `tsconfig.json`, `tailwind.config.js`,
   `postcss.config.js`, or equivalent for the detected framework.
   These files are required for `npm run dev` to work. Without them
   the developer cannot see the UI. Do NOT defer them to Aşama 6c.
4. Write the component(s) under appropriate frontend path(s). Use
   dummy data ONLY — inline constants or `__fixtures__/*.ts`. No
   `fetch` / `axios` / database call / env read.
5. Include dev-toggleable state — `const [mockState, setMockState]`
   or `?state=loading` query param — so the developer can eyeball
   loading / empty / error / success states.
6. **Run the dev server and open it in the developer's browser.**
   Prior releases asked the developer to copy-paste a run snippet, then
   pushed an `AskUserQuestion` at them before they had seen anything.
   Since 6.5.0 MCL does the launching itself, because a developer
   cannot meaningfully answer "approve or revise?" without looking at
   the page first.

   Procedure:

   1. **Short-circuit if docker-compose is active.** If
      `docker compose ps --services --filter status=running` emits at
      least one service and the project has a `docker-compose.yml`
      mapping a web port, skip the host run command — assume the UI
      is already served (developer ran `docker compose up`). Jump
      to sub-step 4.
   2. **Resolve the run command** in this order, first match wins:
      - `package.json` scripts: `dev` → `start` → `serve` (pick one)
      - Symfony project (`bin/console` + `composer.json`): `symfony serve -d` if Symfony CLI is on PATH, else `php -S 127.0.0.1:8000 -t public`
      - Django (`manage.py`): `python manage.py runserver`
      - Rails (`bin/rails`): `bin/rails s`
      - `index.html` at repo root with no framework: `python3 -m http.server 8080`
      - Fallback: emit the snippet-only path from the pre-6.5.0 flow
        and STOP (developer must launch manually).
   3. **Dispatch via `Bash` with `run_in_background: true`.** Capture
      the shell id so the stop hook can reference it in the audit
      log. Sleep ~3s to give the server a chance to bind.
   4. **Derive the URL** by framework:
      - Vite: `http://localhost:5173/<route>`
      - Next.js / Nuxt: `http://localhost:3000/<route>`
      - Webpack dev-server default: `http://localhost:8080/<route>`
      - Symfony CLI: `http://127.0.0.1:8000/<route>`
      - PHP built-in: `http://127.0.0.1:8000/<route>`
      - Django: `http://127.0.0.1:8000/<route>`
      - Rails: `http://127.0.0.1:3000/<route>`
      - Static server: `http://localhost:8080/<route>`
      `<route>` comes from the approved spec (e.g. `/login`, `/calculator`).
   5. **Open the browser.** On macOS: `open <url>`. On Linux:
      `xdg-open <url>` (no-op if absent). Windows is not auto-opened
      (MCL emits the URL for the developer to click).
   6. **Emit the localized "UI açıldı" prose** (single short line
      in the developer's language — see table below). Include the
      URL in the line so it is clickable.

   | Locale | "UI açıldı" prose (substitute `<url>`)                                                       |
   | ------ | ------------------------------------------------------------------------------------------- |
   | TR     | UI hazır ve tarayıcıda açıldı: `<url>` — incele, sonra geri dön ve ne düşündüğünü yaz.      |
   | EN     | UI is up and open in your browser: `<url>` — inspect it, then come back and tell me.        |
   | AR     | الواجهة جاهزة ومفتوحة في متصفحك: `<url>` — افحصها ثم عُد وأخبرني برأيك.                     |
   | DE     | UI läuft und ist im Browser geöffnet: `<url>` — sieh es dir an und sag mir dann Bescheid.   |
   | ES     | La UI está lista y abierta en tu navegador: `<url>` — revísala y luego cuéntame qué opinas. |
   | FR     | L'UI est lancée et ouverte dans ton navigateur : `<url>` — regarde-la puis reviens me dire. |
   | HE     | הממשק מוכן ונפתח בדפדפן: `<url>` — בדוק ותחזור לספר לי מה דעתך.                            |
   | HI     | UI तैयार है और ब्राउज़र में खुल गया है: `<url>` — देखें, फिर वापस आकर बताएं।                  |
   | ID     | UI siap dan terbuka di browser-mu: `<url>` — periksa, lalu kembali ceritakan pendapatmu.    |
   | JA     | UIが起動してブラウザで開かれました: `<url>` — 確認してから戻って感想を教えてください。     |
   | KO     | UI가 실행되어 브라우저에서 열렸습니다: `<url>` — 확인하고 돌아와 의견을 알려주세요.           |
   | PT     | A UI está rodando e aberta no navegador: `<url>` — confira e depois me diga o que achou.    |
   | RU     | UI запущен и открыт в браузере: `<url>` — посмотри, потом вернись и расскажи впечатление.   |
   | ZH     | UI 已启动并在浏览器中打开：`<url>` — 先看看，然后回来告诉我你的想法。                       |

6. **STOP.** Do not call `AskUserQuestion` now. The developer needs
   room to inspect the UI in their browser without a modal dialog
   blocking the terminal. Aşama 7 takes over on the developer's
   NEXT turn, after they return with free-form feedback (see
   `my-claude-lang/asama7-ui-review.md`).

## What Does NOT Happen in Aşama 6

- No backend code. No API routes. No database schema. No `.env`
  changes. No server-side config.
- No production mock server (MSW, json-server) — plain inline
  fixtures are enough for visual verification.
- No automated UI tests (Playwright / Cypress). Those land in
  Aşama 11 based on the Aşama 11 `test_command`.
- No manual translations of UI copy into every MCL-supported
  language — the component uses the developer's chosen default
  locale. i18n scaffolding is only written if the spec MUST
  explicitly required it.

## Revise Loop (4a ↔ 4b)

When the developer picks "Revize" in Aşama 7, Aşama 6 re-enters
with free-text feedback ("buttons to the right, bigger header").
Edit the frontend files in place, emit a fresh "run it" snippet,
re-call the Aşama 7 askq. The loop is unbounded — exit only on
approve or cancel from Aşama 7.

</mcl_phase>
