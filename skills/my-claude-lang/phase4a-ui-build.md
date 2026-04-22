<mcl_phase name="phase4a-ui-build">

# Phase 4a: BUILD_UI — Runnable Frontend with Dummy Data

**`superpowers` (tier-A, ambient):** active throughout this phase.

## Entry Condition

Phase 4a starts automatically when ALL of these hold after spec approval:

- `current_phase = 4`
- `spec_approved = true`
- `ui_flow_active = true` (set by Phase 1 summary-confirm)
- `ui_reviewed = false`
- `ui_sub_phase = "BUILD_UI"` (set by stop hook on spec-approve)

When `ui_flow_active = false` (developer picked "Onay, UI atlayacağız" at
Phase 1) — Phase 4a is SKIPPED. Jump straight to `phase4-execute.md`.

## Core Intent

Write a **runnable** frontend with **dummy data only**, so the developer
can open it in their browser and verify the visual/UX shape BEFORE any
backend work happens. UI mockup and UI build are the same step — there
is no separate preview artifact.

## Sub-Topic Files

For dummy-data fixture conventions (inline constants, `__fixtures__/`
directory, loading/error/success toggles), read
`my-claude-lang/phase4a-ui-build/fixtures.md`.

For framework-specific component syntax (React, Vue, Svelte, static
HTML), read `my-claude-lang/phase4a-ui-build/frameworks.md`.

For styling fallbacks (when no design system is configured) and
neutrality rules, read `my-claude-lang/phase4a-ui-build/styles.md`.

## Path Discipline (enforced by mcl-pre-tool.sh)

While `ui_sub_phase = "BUILD_UI"`, the pre-tool hook:

- **Allows** frontend paths: `src/**/*.{tsx,jsx,vue,svelte,html,css,scss}`,
  `src/components/**`, `src/app/**`, `src/pages/**`,
  `src/**/__fixtures__/**`, `src/**/mocks/**`, `public/**`, `*.html`,
  `src/styles/**`, `tailwind.config.*`, `.mcl/**`.
- **Denies** backend paths: `src/api/**`, `src/server/**`,
  `src/services/**`, `src/lib/db/**`, `.env*`, `prisma/**`,
  `drizzle/**`, `vite.config.*`, `next.config.*`, `vercel.json`,
  `server.{js,ts,mjs}`.

If Claude attempts to write a backend path, the DENY reason says:
> MCL UI-BUILD LOCK — backend is unlocked in Phase 4c after the UI
> is approved. Keep dummy fixtures in the component for now.

## Curated Plugin Dispatch

Auto-dispatch `frontend-design` plugin silently when Phase 4a starts
(Rule B — multi-angle validation). Merge its suggestions into the
component code / prose. Never expose the raw plugin output as a tool
call to the developer. See `my-claude-lang/plugin-suggestions.md` for
promotion details.

## Phase 4a Procedure

1. Read the approved spec.
2. Detect framework from `mcl-stack-detect.sh` tags:
   `react-frontend` / `vue-frontend` / `svelte-frontend` / `html-static`
   / none (fallback to HTML + inline JS).
3. Write the component(s) under appropriate frontend path(s). Use
   dummy data ONLY — inline constants or `__fixtures__/*.ts`. No
   `fetch` / `axios` / database call / env read.
4. Include dev-toggleable state — `const [mockState, setMockState]`
   or `?state=loading` query param — so the developer can eyeball
   loading / empty / error / success states.
5. **Do NOT run the dev server yourself** — emit a "run it" snippet
   so the developer launches it in their terminal:
   ```
   UI dummy data ile hazır. Çalıştır:
     npm run dev      (veya yarn dev / pnpm dev / python -m http.server)
   Tarayıcıda: http://localhost:5173/<route>
   ```
   Detect the run command from `package.json` scripts; if no
   frontend framework, fall back to `python -m http.server 8080`.
6. Immediately transition to Phase 4b by calling the review
   `AskUserQuestion` (see `my-claude-lang/phase4b-ui-review.md`).

## What Does NOT Happen in Phase 4a

- No backend code. No API routes. No database schema. No `.env`
  changes. No server-side config.
- No production mock server (MSW, json-server) — plain inline
  fixtures are enough for visual verification.
- No automated UI tests (Playwright / Cypress). Those land in
  Phase 5 based on the Phase 5 `test_command`.
- No manual translations of UI copy into every MCL-supported
  language — the component uses the developer's chosen default
  locale. i18n scaffolding is only written if the spec MUST
  explicitly required it.

## Revise Loop (4a ↔ 4b)

When the developer picks "Revize" in Phase 4b, Phase 4a re-enters
with free-text feedback ("buttons to the right, bigger header").
Edit the frontend files in place, emit a fresh "run it" snippet,
re-call the Phase 4b askq. The loop is unbounded — exit only on
approve or cancel from Phase 4b.

</mcl_phase>
