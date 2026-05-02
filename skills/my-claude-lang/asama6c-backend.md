<mcl_phase name="asama6c-backend">

# Aşama 6c: BACKEND_INTEGRATION — Wire Real Data

## Entry Condition

Aşama 6c starts automatically when:

- `current_phase = 7`
- `spec_approved = true`
- `ui_flow_active = true`
- `ui_reviewed = true` (set by Aşama 6b approve intent)
- `ui_sub_phase = "BACKEND"`

When `ui_flow_active = false` — Aşama 6c is NOT USED. The `asama7-execute.md`
default path runs directly (no split).

## Path Discipline Change

On entry to Aşama 6c, `mcl-pre-tool.sh` lifts the UI-BUILD path
restriction because `ui_sub_phase` is now `"BACKEND"`. All paths
are open again, subject to the standard Aşama 7 gate (spec approved,
phase = 4). Frontend edits are still allowed — there is no new
restriction in the opposite direction.

## Core Intent

Swap the Aşama 6a dummy fixtures for real data sources:
- API routes, service layer, database queries
- `fetch` / `axios` / SDK calls from the frontend
- `.env` / config wiring
- Loading / error / empty states driven by actual async behavior

The spec has not changed — the same MUST / SHOULD requirements the
developer approved in Aşama 4 still apply. Aşama 6c is execution, not
re-specification.

## Aşama 6c Procedure

1. Grep the frontend for `MOCK_` / `__fixtures__/` prefixes and the
   Aşama 6a files that import them. Enumerate the swap-sites.
2. Write backend code in the conventional project location:
   - Next.js: `src/app/api/<route>/route.ts`
   - SvelteKit: `src/routes/<route>/+server.ts`
   - Express/Fastify: `src/api/<route>.ts`
   - Nuxt: `server/api/<route>.ts`
3. Write the data layer:
   - ORM schema / migration under `prisma/` / `drizzle/` when
     detected
   - Query functions under `src/lib/db/` or project-conventional
     service path
4. Replace frontend fixtures with real calls:
   - `const MOCK_USER` becomes `const user = await fetchUser()`
   - State toggle hook (`useState<MockState>`) becomes real async
     state (TanStack Query, SWR, or the project's existing pattern)
   - Error state wired to caught rejections; loading wired to
     pending state; empty wired to empty response
5. Update `.env.example` (never `.env`) with any new required keys.
   Surface them to the developer with install/setup instructions.
6. Run the test runner if `test_command` is configured
   (see `asama1-gather.md` pre-flow) — failures block Aşama 8 exit.

## Preserve the Type Contract

The TypeScript types written alongside Aşama 6a fixtures
(`src/types/user.ts` etc.) stay as-is. The real API returns data
matching the same shape; the type is the boundary. If the real
backend differs from the fixture shape, STOP and surface the
mismatch to the developer as a Aşama 1-4 micro-cycle — do not
silently change the type.

## Remove Dev-Only Bits

Delete:
- `?state=...` URL-param hooks whose purpose was visual state toggle
- `<select>` dev toggles that expose mock-state switching
- `__fixtures__/<name>.fixture.ts` files that have no remaining
  importers (grep before deleting)

Keep:
- Type definitions from `src/types/` — real code uses them
- Any fixture that is also used by test files (the swap targets
  component imports; Jest/Vitest test imports stay)

## Downstream Phases

Aşama 6c exits directly into Aşama 8 (post-code risk review) per
`asama8-risk-review.md`. Risk review covers BOTH the UI layer and
the new backend layer. Then Aşama 10, then Aşama 11.

Aşama 11's Verification Report "must-test" list MUST include:
- UI interaction verification (click primary button, form submit, etc.)
- Real backend verification (network panel shows `POST /api/...`,
  status 200, payload matches type)
- Error-path verification (what happens when the backend returns 500)

## What Aşama 6c Inherits from asama7-execute.md

All the core Aşama 7 rules still apply:
- All code/comments/commits in English
- All communication in the developer's language
- Gate 1/2/3 on every Claude-Code question
- Execution Plan ONLY for `rm`/`rmdir` shell commands (the
  deletion-only rule from `asama7-execute.md` still holds)
- Scope-creep handling: new tasks get fresh Aşama 1-4

Aşama 6c does NOT re-implement those rules — it is Aşama 7 execution
with the UI already committed. Think of it as the second half of the
`ui_flow_active = true` execution pair.

</mcl_phase>
