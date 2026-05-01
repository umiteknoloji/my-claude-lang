<mcl_constraint name="phase2-design-review-frameworks">

# Phase 4a — Framework-Specific Syntax

Pick the syntax that matches the stack-detect tag. When multiple tags
match (monorepo), pick the dominant one — the framework with the most
entries in `package.json` dependencies. When none match, fall back to
static HTML.

## React (`react-frontend`)

- Components: `.tsx` if `typescript` tag present, otherwise `.jsx`.
- Functional components only — no class components.
- Hooks for state (`useState`, `useEffect`, `useReducer`). No state
  mgmt library introduced in Phase 4a — if the spec implies Redux /
  Zustand, scaffold it in Phase 4c after approval.
- Path: `src/components/<Name>.tsx` for shared, `src/pages/<Name>.tsx`
  for route pages (Next.js/Vite), `src/app/<route>/page.tsx` for
  Next.js App Router. Detect which one by presence of `app/` vs
  `pages/` directory.
- Routing: if the project already has a router (React Router, TanStack
  Router), wire the new component into it. If not, do NOT introduce
  one — leave the component mountable from any entry.

## Vue (`vue-frontend`)

- Single-file components: `.vue` with `<script setup lang="ts">` when
  TypeScript is detected, otherwise `<script setup>`.
- Composition API only — no Options API.
- Path: `src/components/<Name>.vue`, pages under
  `src/pages/<name>.vue` (Nuxt) or `src/views/<Name>.vue` (plain Vue).
- Vue Router: same rule as React Router — wire in if present, do not
  introduce.

## Svelte (`svelte-frontend`)

- `.svelte` files. `<script lang="ts">` when TypeScript detected.
- Use Svelte 5 runes (`$state`, `$derived`, `$props`) when
  `svelte@^5` is in `package.json`, else Svelte 4 stores.
- Path: `src/lib/components/<Name>.svelte` for SvelteKit,
  `src/components/<Name>.svelte` for plain Svelte. Routes under
  `src/routes/<name>/+page.svelte` when SvelteKit detected.

## Static HTML (`html-static`)

Used when no frontend framework is detected OR when the project has
no `package.json` but has `index.html`.

- Single file: `index.html` or `<name>.html` at project root or under
  `public/`.
- Inline `<style>` and `<script>` allowed for MVP components — no
  bundler required. Keep the file self-contained so
  `python -m http.server` is enough to preview.
- ES module scripts fine (`<script type="module">`) — they work over
  `http://` but not `file://`, so always emit the "run via local
  server" instruction.
- No build step introduced. If the developer later asks for a
  bundler, that is a new Phase 1 request.

## Fallback Cascade

If stack-detect returns MULTIPLE framework tags (e.g. monorepo with
React and Vue apps), ask the developer which app directory to target
BEFORE writing code. This is a genuine ambiguity — not an auto-fix
risk.

If stack-detect returns NO framework tag but `package.json` exists
(e.g. a pure backend project that the developer wants to add a UI
to), ask whether to scaffold React + Vite as the default frontend.
This consent goes through a standard `AskUserQuestion`. Never
scaffold a bundler silently.

## What Never Changes in Phase 4a

- `package.json` dependencies — adding deps is a Phase 4c concern
  when the backend integration needs them. Phase 4a works with
  whatever is already installed.
- `tsconfig.json`, `vite.config.*`, `next.config.*`, `nuxt.config.*`
  — all deny-listed by `mcl-pre-tool.sh` during Phase 2 DESIGN_REVIEW.
- Bundler build output (`dist/`, `.next/`, `.svelte-kit/`) — those
  are generated, not hand-written.

</mcl_constraint>
