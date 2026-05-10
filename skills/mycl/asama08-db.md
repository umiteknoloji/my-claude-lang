---
name: mycl-asama08-db
description: MyCL Aşama 8 — Veritabanı Tasarımı. 3NF şema, sorgu desenlerinden türetilen covering index'ler, migration dosyaları. Denormalization gerekçeli olmalı. Veritabanı kapsamda yoksa atlanır. Çıktı asama-8-end tables=N indexes=M migrations=K.
---

# Aşama 8 — Veritabanı Tasarımı

## Amaç

Veriyi **normalleştirme kurallarına uygun** ve **ileriye dönük sorun
çıkarmayacak** şekilde tasarla.

## Ne yapılır

### 1. Şema (3NF default)

- Her tablo tek bir varlığı temsil eder
- Tekrarlayan grup yok (1NF)
- Kısmi bağımlılık yok (2NF)
- Geçişli bağımlılık yok (3NF)
- **Denormalization gerekçeli:** "read latency için users.last_login_at
  cache" gibi bir gerekçe spec'te belgelenmeli; aksi halde 3NF.

### 2. Index stratejisi

- Sorgu desenlerinden **türetilen** index'ler (spec AC'lerini incele)
- **Covering index** tercih: WHERE + ORDER BY + SELECT kolonları
- Filtered/partial index nerede uygunsa
- Index sayısı = O(read pattern) değil O(write throughput) — gereksiz
  index INSERT/UPDATE'i yavaşlatır

### 3. Sorgu planı

Beklenen sıcak sorgu için **erişim yolu** belgele:
```sql
-- Hot query: list user orders
EXPLAIN (FORMAT JSON)
SELECT id, total FROM orders
WHERE user_id = $1 AND status = 'pending'
ORDER BY created_at DESC LIMIT 20;
-- Plan: Index Scan on orders_user_status_created_idx
```

### 4. Migration dosyaları

ORM kullanılıyorsa (Prisma, TypeORM, SQLAlchemy, Django ORM):
- `prisma/migrations/`, `migrations/`, `db/migrate/` (stack'e göre)
- Her migration **reversible** — `down()` veya `--reversible` flag
- Schema değişiklikleri spec MUST'larına bağlı (covers=MUST_3)

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Atlama

Veritabanı kapsamda yoksa:
```
asama-8-not-applicable reason=no-db-in-scope
```

## Çıktı (audit)

> **Model:** `asama-8-not-applicable reason=...` (DB kapsam dışıysa) cevap metninde düz yazıyla.
> **Hook:** `asama-8-end tables=N indexes=M migrations=K` (schema/migration sayımıyla hook yazar).
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-8-end tables=N indexes=M migrations=K
asama-8-not-applicable reason=no-db-in-scope
```

## Anti-pattern

- ❌ "Şimdilik denormalize edeyim, hızlı olur" — gerekçesiz denorm
  Aşama 11 kod inceleme'de yakalanır
- ❌ Index spam — her kolona index = INSERT yavaş + storage waste
- ❌ Migration olmadan schema değişiklik — production'da fark edilmeyen
  drift
- ❌ N+1 query üreten relation tasarım — Aşama 13 performans'ta
  yakalanır

---

# Phase 8 — Database Design

## Goal

Design data per normalization rules with no future-tense problems.

## Action

1. **Schema (3NF default)** — denormalization must be justified.
2. **Index strategy** — covering indexes derived from query patterns;
   beware index spam (write throughput).
3. **Query plan** — hot queries documented with EXPLAIN.
4. **Migrations** — reversible (`down()`); ORM-aware (Prisma/TypeORM/
   SQLAlchemy/Django).

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Skip

`asama-8-not-applicable reason=no-db-in-scope` when DB not in scope.

## Audit output

> **Model:** `asama-8-not-applicable reason=...` (when DB out of scope) plain text in reply.
> **Hook:** `asama-8-end tables=N indexes=M migrations=K` (hook writes after counting schema/migrations).
> **Details:** see "Audit emission channel" contract in main skill.

`asama-8-end tables=N indexes=M migrations=K`.

## Anti-patterns

- Unjustified denormalization.
- Index spam.
- Schema changes without migrations.
- Relation design that yields N+1.
