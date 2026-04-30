<mcl_phase name="phase4c-backend">

# Phase 4c: BACKEND_INTEGRATION — Wire Real Data

**`superpowers` (tier-A, ambient):** active throughout this phase.

## Entry Condition

Phase 4c starts automatically when:

- `current_phase = 4`
- `spec_approved = true`
- `ui_flow_active = true`
- `ui_reviewed = true` (set by Phase 4b approve intent)
- `ui_sub_phase = "BACKEND"`

When `ui_flow_active = false` — Phase 4c is NOT USED. The `phase4-execute.md`
default path runs directly (no split).

## Path Discipline Change

On entry to Phase 4c, `mcl-pre-tool.sh` lifts the UI-BUILD path
restriction because `ui_sub_phase` is now `"BACKEND"`. All paths
are open again, subject to the standard Phase 4 gate (spec approved,
phase = 4). Frontend edits are still allowed — there is no new
restriction in the opposite direction.

## Core Intent

Swap the Phase 4a dummy fixtures for real data sources:
- API routes, service layer, database queries
- `fetch` / `axios` / SDK calls from the frontend
- `.env` / config wiring
- Loading / error / empty states driven by actual async behavior

The spec has not changed — the same MUST / SHOULD requirements the
developer approved in Phase 3 still apply. Phase 4c is execution, not
re-specification.

## Phase 4c Procedure

1. Grep the frontend for `MOCK_` / `__fixtures__/` prefixes and the
   Phase 4a files that import them. Enumerate the swap-sites.
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
   (see `phase1-rules.md` pre-flow) — failures block Phase 4.5 exit.

## Preserve the Type Contract

The TypeScript types written alongside Phase 4a fixtures
(`src/types/user.ts` etc.) stay as-is. The real API returns data
matching the same shape; the type is the boundary. If the real
backend differs from the fixture shape, STOP and surface the
mismatch to the developer as a Phase 1-3 micro-cycle — do not
silently change the type.

## Remove Dev-Only Bits

Delete:
- `?state=...` URL-param hooks whose purpose was visual state toggle
- `<select>` dev toggles that expose mock-state switching
- `__fixtures__/<name>.fixture.ts` files that have no remaining
  importers (grep before deleting)
- Tüm `src/mocks/` dizini, içindeki her `*.mock.ts` dosyasının kalan
  importer'ı yoksa. Doğrulama:
  ```
  grep -rEn "from ['\"][^'\"]*src/mocks/|from ['\"]\.\./mocks/|from ['\"]@/mocks/" src/ \
    --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx'
  ```
  Grep çıktısında veya `*.test.*` / `*.spec.*` dosyalarında referans
  bulunan herhangi bir `*.mock.ts` silinmez. Çıktı boşsa
  `rm -rf src/mocks/` Phase 4 Execution Plan kuralı altında çalıştırılır
  (destructive op → reconfirm).

Keep:
- Type definitions from `src/types/` — real code uses them
- Any fixture that is also used by test files (the swap targets
  component imports; Jest/Vitest test imports stay)

## Downstream Phases

Phase 4c exits directly into Phase 4.5 (post-code risk review) per
`phase4-5-risk-review.md`. Risk review covers BOTH the UI layer and
the new backend layer. Then Phase 4.6, then Phase 5.

Phase 5's Verification Report "must-test" list MUST include:
- UI interaction verification (click primary button, form submit, etc.)
- Real backend verification (network panel shows `POST /api/...`,
  status 200, payload matches type)
- Error-path verification (what happens when the backend returns 500)

## What Phase 4c Inherits from phase4-execute.md

All the core Phase 4 rules still apply:
- All code/comments/commits in English
- All communication in the developer's language
- Gate 1/2/3 on every Claude-Code question
- Execution Plan ONLY for `rm`/`rmdir` shell commands (the
  deletion-only rule from `phase4-execute.md` still holds)
- Scope-creep handling: new tasks get fresh Phase 1-3

Phase 4c does NOT re-implement those rules — it is Phase 4 execution
with the UI already committed. Think of it as the second half of the
`ui_flow_active = true` execution pair.

</mcl_phase>
