<mcl_constraint name="phase2-design-review-fixtures">

# Phase 4a — Dummy Data & Fixtures

## Placement

- **Inline constants** — for single-component fixtures, keep them at
  the top of the component file as `const MOCK_USER`, `const MOCK_POSTS`.
- **`__fixtures__/` directory** — for shared fixtures or >20 lines of
  data. Path: `src/**/__fixtures__/<name>.fixture.ts`. Kebab-case
  filename, singular noun (`user-profile.fixture.ts`, not
  `user-profiles.fixtures.ts`).
- Backend-paterni yollar (`src/api/**`, `src/services/**`, `src/lib/db/**`,
  `prisma/**`, vb.) deny-listed. Tam yol-yönlendirme tablosu için
  ana skill'e bak: `phase2-design-review.md` → "Backend-Sounding Paths".

## What is FORBIDDEN in a Phase 4a fixture

- `fetch`, `axios`, `XMLHttpRequest`, `WebSocket`
- ORM / query-builder calls (`prisma.*`, `drizzle.*`, `knex.*`, raw SQL)
- `process.env.*` reads except `process.env.NODE_ENV` for dev toggles
- `import` from `src/api/`, `src/server/`, `src/services/`, `src/lib/db/`
- Async I/O that would fail without a running backend

The fixture MUST resolve synchronously or with `Promise.resolve(...)`.

## TypeScript Shape

Fixtures MUST have an explicit type annotation matching the eventual
real data contract. This is what makes Phase 4c's backend swap
mechanical instead of guesswork. Example:

```ts
// src/components/__fixtures__/user.fixture.ts
import type { User } from '@/types/user';

export const MOCK_USER: User = {
  id: 'usr_mock_001',
  email: 'alice@example.test',
  name: 'Alice Example',
  createdAt: new Date('2026-01-15T10:00:00Z'),
};

export const MOCK_USERS: User[] = [
  MOCK_USER,
  { id: 'usr_mock_002', email: 'bob@example.test', name: 'Bob Example',
    createdAt: new Date('2026-02-01T14:30:00Z') },
];
```

If `@/types/user` does not yet exist, write the type definition first
under `src/types/` (allowed path). Phase 4c will reuse the same type
when wiring the real API.

## State Toggle (loading / empty / error / success)

Every non-trivial component MUST expose a dev toggle so the developer
can see each state without a real backend. Two acceptable patterns:

### Pattern A — local state hook

```tsx
import { useState } from 'react';

type MockState = 'loading' | 'empty' | 'error' | 'success';

export function UserList() {
  const [mockState, setMockState] = useState<MockState>('success');
  // ... render based on mockState
  return (
    <>
      <div style={{ position: 'fixed', top: 4, right: 4, fontSize: 12 }}>
        <select value={mockState}
                onChange={e => setMockState(e.target.value as MockState)}>
          <option value="loading">loading</option>
          <option value="empty">empty</option>
          <option value="error">error</option>
          <option value="success">success</option>
        </select>
      </div>
      {/* render based on mockState */}
    </>
  );
}
```

### Pattern B — URL query param

```tsx
const mockState = new URLSearchParams(location.search).get('state')
  ?? 'success';
// visit ?state=loading to see that branch
```

Pattern A is preferred for components with multiple sub-states
(dashboards). Pattern B is fine for simple pages (`/login?state=error`).

## Sensitive-Data Hygiene

Never use real PII in fixtures — even mock PII. Use:

- Emails: `@example.test` or `@example.com` (reserved TLDs)
- Names: generic (Alice, Bob, Carol) — not scraped from real datasets
- IDs: prefix `mock_` or `demo_` so they are grep-able before deploy
- Dates: realistic but obviously synthetic (round numbers, 2026-01-01)

## Removal Signal

In Phase 4c, Claude greps for `__fixtures__/`, `MOCK_`, or `mock_`
prefixes to know what to swap. Keep the prefix consistent — do not
invent new naming like `DEMO_DATA_*` mid-component.

</mcl_constraint>
