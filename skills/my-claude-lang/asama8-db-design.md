<mcl_phase name="asama8-db-design">

# Aşama 8: DB Design (since v12.0)

Aşama 8 is a **dedicated database design phase** introduced in v12.0.
Runs after Aşama 7 (UI inspection approval) and BEFORE Aşama 9
(TDD execute), so the database schema is in place when the test-first
cycle begins. Design-only — no application code writes here, only
schema files, migrations, and (where the ORM supports them) seed
fixtures for tests.

## When Aşama 8 Runs

Immediately after Aşama 7's UI approval (`ui_sub_phase` advanced to
`"BACKEND"` by the Stop hook) AND before any Aşama 9 production
code is written. When `ui_flow_active=false` (no UI surface), Aşama 8
still runs whenever the approved spec declares persistence —
detection key is the spec body, not the UI flow.

## Soft Applicability — when Aşama 8 is skipped

Aşama 8 is **not applicable** when ALL of these hold:

- Approved spec declares no persistent entities, no DB driver, no
  ORM, no schema concerns (e.g., a CLI tool that prints output, a
  static site, a pure transform that doesn't read/write storage).
- Project root has no existing `prisma/`, `drizzle/`, `migrations/`,
  `db/`, `*.sql` schema files.
- Stack detection returns no DB-related tag (`postgres`, `mysql`,
  `sqlite`, `mongodb`, `redis`, etc. absent).

When skipped, emit:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log asama-8-not-applicable mcl-stop "reason=no-db-in-scope"'
```

Then proceed to Aşama 9 directly.

## Procedure

### Step 1 — Read approved spec for entity declarations

Walk the Aşama 4 approved spec. Extract:

- Entities (nouns the spec talks about as persisted state)
- Relations (1-to-1, 1-to-many, many-to-many implied by the prose)
- Cardinality constraints (at-most-one-active, must-have-N, etc.)
- Lifecycle declarations (soft-delete? hard-delete? archival?)
- PII / sensitivity markers (encryption-at-rest hints)

If the spec is ambiguous on any of these, STOP and surface as a
Aşama 1-style micro-question — do NOT silently invent entities.

### Step 2 — Schema design (3NF default)

Default to **third normal form** (3NF):

- Each table has a primary key
- Each non-key column depends on the whole key (no partial deps)
- Each non-key column depends on the key only (no transitive deps)

**Justify denormalization explicitly when applied.** Acceptable
denormalization triggers:

- Read-path performance bottleneck observable from spec hot paths
- Audit trail (immutable history table — copy of source columns)
- Reporting/aggregate tables fed by triggers or materialized views
- Soft-delete archive tables

Each denormalization decision goes into the migration file as a
SQL comment with the reason.

### Step 3 — Index strategy

Design indexes by query pattern, NOT by column shape. For each
known query path from the spec hot paths:

- **PK indexes** — every table (default; ORM emits)
- **FK indexes** — every foreign-key column (composite when relation
  is many-to-many or multi-tenant)
- **Composite indexes** — exact column order matters; left-most
  prefix used for partial matches
- **Partial / filtered indexes** — when a query consistently filters
  on a low-cardinality column (e.g., `WHERE deleted_at IS NULL`)
- **Unique indexes** — at column AND composite level for invariants
  the spec declares (`unique(tenant_id, slug)`)
- **Avoid** — indexing every column, indexing low-cardinality alone,
  indexing columns that change frequently if write throughput
  matters

For each index, record in the migration file:

```sql
-- index: <name>
-- reason: <which query / spec hot path uses it>
-- estimated_selectivity: <high|medium|low>
CREATE INDEX <name> ON <table>(<cols>) [WHERE <filter>];
```

### Step 4 — Generate ORM migration files

Detect ORM by stack signal (Aşama 5 PATTERN_SUMMARY when present,
fall back to project root inspection):

| ORM | Migration path | Generator command |
|---|---|---|
| Prisma | `prisma/migrations/<ts>_<name>/migration.sql` | `npx prisma migrate dev --name <name> --create-only` |
| Drizzle | `drizzle/migrations/<ts>_<name>.sql` | `npx drizzle-kit generate` |
| TypeORM | `src/migrations/<ts>-<name>.ts` | `npx typeorm migration:create src/migrations/<name>` |
| Django | `<app>/migrations/<NNNN>_<name>.py` | `python manage.py makemigrations` |
| ActiveRecord | `db/migrate/<ts>_<name>.rb` | `bin/rails generate migration <name>` |
| Alembic | `alembic/versions/<rev>_<name>.py` | `alembic revision -m "<name>"` |
| SQL-only | `migrations/<NNNN>_<name>.sql` | manual, monotonic numbering |

Use `--create-only` (or equivalent) so migrations are reviewed
before they're applied. The Aşama 9 TDD red-green cycle will
apply them through its test runner.

### Step 5 — Query plan estimates for hot paths

For each hot path the spec declares (e.g., "list latest 50 posts
by user", "search products by name + category"), provide a brief
plan estimate in the migration comment block:

```sql
-- hot path: list-latest-posts-by-user
-- expected plan:
--   1. Index scan on posts(user_id, created_at DESC) → 50 rows
--   2. Hash join posts.id → users.id → 50 rows
-- expected p95: < 5ms at 10k rows/user
-- regression triggers: missing (user_id, created_at) index, full
--   scan on posts, FK index missing on users.id
```

This is **estimation, not measurement**. Aşama 13 (Performance) and
Aşama 18 (Load tests) verify the actual plan against these estimates.

## Forbidden in Aşama 8

- **Application code** — no controllers, no services, no repositories.
  Only schema, migrations, optional seed fixtures.
- **Production data writes** — migrations can be applied to dev/test
  DBs but never to production from inside MCL.
- **Schema decisions absent from the spec** — if the spec doesn't
  declare an entity, do NOT add it. Surface as a micro-question.
- **Index every column** — indexes have write cost; design them by
  query pattern, not column shape.

## Audit emit

Start of phase:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log "asama-8-start" "mcl-stop.sh" "scope=schema-design"'
```

End of phase:

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log "asama-8-end" "mcl-stop.sh" "tables=N indexes=M migrations=K denormalizations=D"'
```

Not applicable (no DB in scope):

```
bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; \
  mcl_audit_log "asama-8-not-applicable" "mcl-stop.sh" "reason=no-db-in-scope"'
```

## Phase transition

After Aşama 8 ends (or skips with the not-applicable audit), Aşama 9
(TDD execute) can begin. The TDD runner picks up the migrations as
test setup; Aşama 9's RED step exercises queries that depend on the
indexes Aşama 8 designed.

## Anti-patterns

- Asking the developer questions in Aşama 8 (auto-design only; spec
  ambiguity escalates back to Aşama 1).
- Designing schema without reading the spec (defeats the point).
- Generating migrations that drop columns/tables a previous spec
  approved without an explicit migration-rollback decision.
- Adding tables for "future-proofing" not declared in the spec.

</mcl_phase>
