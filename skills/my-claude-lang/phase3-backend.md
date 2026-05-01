<mcl_phase name="phase3-backend">

# Phase 3 (UI path): Backend Integration — Wire Real Data

## Entry Condition

This is the UI-after-design subset of Phase 3, entered when:

- `current_phase = 3`
- `is_ui_project = true`
- `design_approved = true` (set by Phase 2 design askq approve)

When `is_ui_project = false` — this file is NOT USED. The
`phase3-execute.md` default path runs directly (no split).

## Path Discipline Change

On Phase 3 entry, `mcl-pre-tool.sh` lifts the Phase 2
DESIGN-REVIEW path restriction. All paths are open again, subject
to the standard Phase 3 gate. Frontend edits are still allowed
— there is no new restriction in the opposite direction.

## Core Intent

Swap the Phase 2 dummy fixtures for real data sources:
- API routes, service layer, database queries
- `fetch` / `axios` / SDK calls from the frontend
- `.env` / config wiring
- Loading / error / empty states driven by actual async behavior

The Phase 1 brief has not changed — the same MUST / SHOULD
requirements still apply. Phase 3 backend integration is
execution, not re-specification.

## Procedure

1. Grep the frontend for `MOCK_` / `__fixtures__/` prefixes and the
   Phase 2 files that import them. Enumerate the swap-sites.
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
   (see `phase1-rules.md` pre-flow) — failures block Phase 4 exit.

## Preserve the Type Contract

The TypeScript types written alongside Phase 2 fixtures
(`src/types/user.ts` etc.) stay as-is. The real API returns data
matching the same shape; the type is the boundary. If the real
backend differs from the fixture shape, STOP and surface the
mismatch to the developer as a fresh Phase 1 micro-cycle — do not
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

Phase 3 backend integration exits directly into Phase 4 (risk gate)
per `phase4-risk-gate.md`. The risk gate covers BOTH the UI layer
and the new backend layer. The impact lens follows, then Phase 5.

Phase 5's Verification Report "must-test" list MUST include:
- UI interaction verification (click primary button, form submit, etc.)
- Real backend verification (network panel shows `POST /api/...`,
  status 200, payload matches type)
- Error-path verification (what happens when the backend returns 500)

## Inherited Phase 3 Rules

All the core Phase 3 rules from `phase3-execute.md` still apply:
- All code/comments/commits in English
- All communication in the developer's language
- Gate 1/2/3 on every Claude-Code question
- Execution Plan ONLY for `rm`/`rmdir` shell commands (the
  deletion-only rule from `phase3-execute.md` still holds)
- Scope-creep handling: new tasks get fresh Phase 1 cycle

This file does NOT re-implement those rules — it is the UI-after-
design Phase 3 path with the visual skeleton already committed.

</mcl_phase>
