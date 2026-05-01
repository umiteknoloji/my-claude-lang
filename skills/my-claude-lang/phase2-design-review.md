<mcl_phase name="phase2-design-review">

# Phase 2 — Design Review (UI projects only)

> **Goal: produce a clickable UI skeleton (HTML/Tailwind/component
> layout, mock data) so the developer can review and approve the
> design BEFORE Phase 3 implementation.**

Phase 2 is the **second canonical developer-control gate** in the
MCL 10.0.0 phase model. Phase 1 summary-confirm captures intent;
Phase 2 captures visual intent. Without an approved design, Phase 3
implementation cannot start for UI projects — the model would
otherwise be implementing real logic against an unverified visual
shape.

## Entry Condition

Phase 2 starts when ALL of these hold after Phase 1 summary-confirm
approval:

- `current_phase = 2`
- `is_ui_project = true` (set by Phase 1 brief parse — see
  `phase1-rules.md` for the detection rules)
- `design_approved = false`

When `is_ui_project = false`, Phase 2 is **skipped entirely**. The
state machine advances directly from Phase 1 → Phase 3, and this
file is never read.

## Core Intent

Write a **runnable** UI skeleton with **mock data only** so the
developer can open it in a browser and verify the visual / UX shape
BEFORE any backend or business logic is written. The skeleton is the
canonical artifact of Phase 2 — there is no separate preview step.

Mock data is the rule, not the exception. Real `fetch` / `axios` /
DB calls / env reads are deferred to Phase 3. Recharts, lucide-react,
and similar UI / icon libraries are explicitly allowed because they
are part of the visual surface.

## Sub-Topic Files

- For dummy-data fixture conventions (inline constants,
  `__fixtures__/` directory, loading/error/success toggles):
  `my-claude-lang/phase2-design-review/fixtures.md`.
- For framework-specific component syntax (React, Vue, Svelte,
  static HTML): `my-claude-lang/phase2-design-review/frameworks.md`.
- For styling fallbacks (when no design system is configured) and
  neutrality rules: `my-claude-lang/phase2-design-review/styles.md`.
- For the opt-in "MCL sees its own UI" pipeline (Playwright +
  screenshot + Read multimodal):
  `my-claude-lang/phase2-design-review/visual-inspect.md`.

## Path Discipline (enforced by mcl-pre-tool.sh)

While `current_phase = 2`, the pre-tool hook:

- **Allows** frontend paths AND build-tool config:
  `src/**/*.{tsx,jsx,vue,svelte,html,css,scss}`,
  `src/components/**`, `src/app/**`, `src/pages/**`,
  `src/**/__fixtures__/**`, `src/**/mocks/**`, `public/**`, `*.html`,
  `src/styles/**`, `tailwind.config.*`, `tsconfig*.json`,
  `jsconfig.json`, `postcss.config.*`, `vite.config.*`,
  `next.config.*`, `nuxt.config.*`, `package.json`, `.mcl/**`.
- **Denies** true backend paths: `src/api/**`, `src/server/**`,
  `src/services/**`, `src/lib/db/**`, `.env*`, `prisma/**`,
  `drizzle/**`, `vercel.json`, `netlify.toml`,
  `server.{js,ts,mjs}`.

Build-tool configs (`vite.config.*`, `next.config.*`,
`nuxt.config.*`, `tailwind.config.*`, `tsconfig*`,
`postcss.config.*`) are **explicitly allowed** — they are needed
to run `npm run dev`. Writing them in Phase 2 is correct and
required.

If Claude attempts to write a true backend path, the DENY reason
says:
> MCL DESIGN-REVIEW LOCK — backend is unlocked in Phase 3 after the
> design is approved. Keep mock fixtures in the component for now.

### Backend-Sounding Paths — Redirect Before Writing

| Path you might want to write          | Use this path instead                            |
| ------------------------------------- | ------------------------------------------------ |
| `src/api/<name>.ts` (mock client)     | `src/mocks/<name>.mock.ts`                       |
| `src/services/<name>.ts`              | `src/components/__fixtures__/<name>.fixture.ts`  |
| `src/lib/db/<name>.ts`                | `src/mocks/<name>.mock.ts`                       |
| `pages/api/<name>.ts` / `app/api/`    | inline constant — at top of the component file   |
| `prisma/schema.prisma` (mock)         | `src/types/<name>.ts` (type only, no schema)     |
| `migrations/*.sql` (sample)           | inline constant + `src/types/<name>.ts`          |
| `server.ts` / `index.server.ts`       | DON'T WRITE — backend belongs to Phase 3         |

Heuristic: if the filename evokes "real data source", it belongs to
Phase 3. Phase 2 only writes UI + frontend-visible mocks; the mock
location is always `src/mocks/` or `__fixtures__/`. No exceptions.

## Curated Plugin Dispatch

Auto-dispatch the `frontend-design` plugin silently when Phase 2
starts (Rule B — multi-angle validation). Merge its suggestions
into the component code / prose. Never expose the raw plugin output
as a tool call to the developer. See
`my-claude-lang/plugin-suggestions.md` for promotion details.

## Phase 2 Procedure

1. Read the approved Phase 1 brief (the engineering summary the
   developer confirmed).
2. Detect framework from `mcl-stack-detect.sh` tags:
   `react-frontend` / `vue-frontend` / `svelte-frontend` /
   `html-static` / none (fallback to HTML + inline JS).
3. **Write a minimum of 3 files**:
   - **Entry file** — `index.html` (static), `App.tsx` (React),
     `App.vue` (Vue), `+page.svelte` (SvelteKit), or framework
     equivalent.
   - **Base layout component** — header / nav / shell that other
     pages plug into.
   - **One or two placeholder pages** — at least one route the
     developer can click to.
4. **Write build-tool config files alongside the components** —
   `package.json` (if absent), `vite.config.ts`, `tsconfig.json`,
   `tailwind.config.js`, `postcss.config.js`, or equivalent. Without
   them `npm run dev` cannot bind. Configure Tailwind / CSS so the
   skeleton looks intentional, not stock-template.
5. Use mock data ONLY — inline constants or `__fixtures__/*.ts`.
   No `fetch` / `axios` / DB / env. Recharts / lucide-react /
   similar UI libs are allowed for charts and icons in the
   skeleton.
6. Include dev-toggleable state — `const [mockState,
   setMockState]` or `?state=loading` query param — so the
   developer can eyeball loading / empty / error / success states.
7. **Run the dev server** in the background and **emit the URL in
   chat** so the developer can click it. Procedure:

   1. **Short-circuit if docker-compose is active.** If
      `docker compose ps --services --filter status=running` emits
      at least one service and the project has a `docker-compose.yml`
      mapping a web port, skip the host run command — assume the UI
      is already served. Jump to sub-step 4.
   2. **Resolve the run command** in this order, first match wins:
      - `package.json` scripts: `dev` → `start` → `serve` (pick one)
      - Symfony (`bin/console` + `composer.json`): `symfony serve -d` if Symfony CLI is on PATH, else `php -S 127.0.0.1:8000 -t public`
      - Django (`manage.py`): `python manage.py runserver`
      - Rails (`bin/rails`): `bin/rails s`
      - `index.html` at repo root with no framework: `python3 -m http.server 8080`
      - Fallback: emit a snippet-only path and STOP (developer must
        launch manually).
   3. **Dispatch via `Bash` with `run_in_background: true`.**
      Capture the shell id so the stop hook can reference it in the
      audit log. Sleep ~3s for the server to bind.
   4. **Derive the URL** by framework:
      - Vite: `http://localhost:5173/<route>`
      - Next.js / Nuxt: `http://localhost:3000/<route>`
      - Webpack dev-server default: `http://localhost:8080/<route>`
      - Symfony CLI / PHP built-in: `http://127.0.0.1:8000/<route>`
      - Django: `http://127.0.0.1:8000/<route>`
      - Rails: `http://127.0.0.1:3000/<route>`
      - Static server: `http://localhost:8080/<route>`
      `<route>` comes from the approved Phase 1 brief (e.g. `/login`,
      `/calculator`).
   5. **Open the browser.** macOS: `open <url>`. Linux:
      `xdg-open <url>` (no-op if absent). Windows: emit URL only.
   6. **Emit the localized "UI ready" prose** (single short line in
      the developer's language — see table below). Include the URL
      in the line so it is clickable.

   | Locale | "UI ready" prose (substitute `<url>`)                                                       |
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

8. **MANDATORY: Call AskUserQuestion (pinned body).** After the
   `dev-server-started` audit fires AND ≥3 files have been written
   AND the URL is in chat, immediately call:

   ```
   AskUserQuestion({
     question: "MCL {{MCL_VERSION}} | Tasarımı onaylıyor musun?",
     options: [
       { label: "Onayla",   description: "Tasarım uygun, Phase 3'e geç" },
       { label: "Değiştir", description: "Şu değişikliği yap: [açıkla]" },
       { label: "İptal",    description: "Tasarım akışını durdur" }
     ]
   })
   ```

   For English sessions:

   ```
   AskUserQuestion({
     question: "MCL {{MCL_VERSION}} | Approve this design?",
     options: [
       { label: "Approve", description: "Design is good, proceed to Phase 3" },
       { label: "Revise",  description: "Change this: [describe]" },
       { label: "Cancel",  description: "Stop the design flow" }
     ]
   })
   ```

   Localize labels for every supported locale (the table from the
   "UI ready" prose above carries the same locale set; reference
   labels: TR Onayla/Değiştir/İptal, EN Approve/Revise/Cancel, JA
   承認/修正/キャンセル, KO 승인/수정/취소, ZH 批准/修改/取消, AR
   موافق/مراجعة/إلغاء, HE אישור/תיקון/ביטול, DE Genehmigen/
   Überarbeiten/Abbrechen, ES Aprobar/Revisar/Cancelar, FR
   Approuver/Réviser/Annuler, HI स्वीकृति/संशोधन/रद्द करें, ID
   Setuju/Revisi/Batal, PT Aprovar/Revisar/Cancelar, RU Одобрить/
   Доработать/Отмена).

   **Header MUST be `MCL {{MCL_VERSION}} | <body>`** — `{{MCL_VERSION}}`
   is auto-injected by the install pipeline.

## Hook enforcement

`mcl-stop.sh` HARD-ENFORCES the design askq presence in the
transcript before Phase 2 can transition to Phase 3:

- Without the askq call, Stop emits `decision:block` with
  message: "MCL: UI hazır. Phase 2 zorunlu — askq ile onay iste."
- The model cannot proceed past Phase 2 without explicit developer
  approval.
- The block is sticky: it re-fires on every subsequent turn until
  the askq is emitted.

## Approval Detection

The approve label is detected by case-insensitive **contains**
match against the canonical token set:

```
onayla, evet, approve, yes, confirm, ok, proceed
```

Any option whose label or description contains one of these tokens
counts as approve. Revise / cancel are caught by their own token
sets; see `askuserquestion-protocol.md` for the full whitelist.

## Dispatch Table (result of AskUserQuestion)

| Option chosen | Stop-hook intent       | State transition                                       | Next MCL step                  |
| ------------- | ---------------------- | ------------------------------------------------------ | ------------------------------ |
| Approve       | `design-approve`       | `design_approved=true`, `current_phase=3`              | Phase 3 (`phase3-implementation.md`) |
| Revise        | `design-revise`        | no state change                                        | Re-enter Phase 2 with feedback |
| Cancel        | `design-cancel`        | UI flags reset                                         | Abort task                     |

## Revise Loop

When Revise is chosen, the developer's free-text feedback is the
input for the next Phase 2 turn. Treat feedback as parameters for
the existing intent — do NOT re-run Phase 1. The brief is still
canonical; only the visual realization is being tweaked.

If the feedback contradicts the approved Phase 1 brief ("change the
primary button to a signup form instead"), that is scope creep —
treat it exactly like the "Yes but..." rule (see
`phase1-rules.md`): run a fresh Phase 1 cycle for the delta, do
not quietly rewrite.

The loop is unbounded — exit only on Approve or Cancel.

## What Does NOT Happen in Phase 2

- **No backend code.** No API routes, DB schemas, `.env` writes,
  server-side config, real `fetch`. Backend paths are blocked by
  the pre-tool path lock.
- **No production mock server** (MSW, json-server) — plain inline
  fixtures are sufficient for visual verification.
- **No automated UI tests** (Playwright / Cypress). Those land in
  Phase 5 based on `test_command`.
- **No manual translations** of UI copy into every MCL-supported
  language — the component uses the developer's chosen default
  locale. i18n scaffolding is only written if the brief explicitly
  required it.

## On Approval

When the developer selects Approve, the Stop hook:
1. Writes `state.design_approved=true`
2. Writes `state.current_phase=3`
3. Lifts the design-review path lock — Phase 3 backend writes are
   now allowed.
4. Emits `design-approved` audit event for Phase 6 traceability.

Frontend edits are still allowed in Phase 3 — there is no new
restriction in the opposite direction. Phase 3 swaps fixtures for
real calls and wires the data layer; the visual shape stays as
approved.

</mcl_phase>
