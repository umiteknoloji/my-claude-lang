---
name: mycl-asama16-entegrasyon-test
description: MyCL Aşama 16 — Entegrasyon Testleri (Test Pipeline 2/4). Modüller arası akış, API endpoint, veritabanı katmanı. Mock değil gerçek (in-memory DB / test container) tercih edilir. Çıktı asama-16-end-green | asama-16-not-applicable.
---

# Aşama 16 — Entegrasyon Testleri (Test Pipeline 2/4)

## Amaç

Modüller arası **gerçek akışları** doğrula — birim seviyesinde
mock'lanmış sınırlar gerçek hayatta yumuşak çuvallayabilir.

## Aşama 16 mercek

| Akış | Test |
|---|---|
| API endpoint | HTTP request → handler → DB → response |
| DB katmanı | Repository → query → in-memory PG / SQLite test |
| Service-Service | OrderService → InventoryService gerçek bağlantı |
| Background job | Job emit → queue → consumer → DB write |

## Mock vs gerçek

**Tercih: gerçek** (in-memory DB, test container, embedded service).
- Mock'lar prod ↔ test divergence üretir (örn. mock query string
  match doğru ama gerçek SQL yanlış)
- testcontainers / docker-compose test setup tercih
- Mock yalnızca **dış servis** (3rd-party API) için

## CLAUDE.md auto-rule

> **Don't mock the database in these tests** — mocked tests passed but
> the prod migration failed. Integration tests must hit a real DB.

## Pipeline (4-step)

1. **Eksik tespit** → her cross-module path için integration test
   var mı?
2. **Test setup** → testcontainers / in-memory DB / fixture
3. **Test yaz** → uçtan uca akış doğrulama
4. **Çalıştır** → tam suite YEŞİL

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Çıktı (audit)

> **Model:** `asama-16-not-applicable reason=...` (kapsam dışıysa) cevap metninde düz yazıyla.
> **Hook:** `asama-16-scan`, `asama-16-test-N-added`, `asama-16-end-green` (tam suite YEŞİL post_tool sinyaliyle hook yazar).
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-16-scan count=K
asama-16-test-N-added
asama-16-end-green
asama-16-not-applicable reason=<sebep>
```

### Hook enforcement (1.0.28)

Hook, Aşama 15 ile aynı generic text-trigger setini kullanır
(`asama-16-scan / test-M-added`). `end-green` ve `not-applicable` 1.0.21
extended trigger'da yakalanır. Detay: Aşama 15 skill "Hook enforcement
(1.0.28)" bölümü. Hook auto-emit YOK.


## Anti-pattern

- ❌ Mock-everything yaklaşımı — prod farkı gizlenir
- ❌ "Integration test yavaş, atlayım" — `asama-16-not-applicable`
  yazmak zorunda; sessiz atlama yok
- ❌ DB seed sürekli aynı → state pollution; her test fresh state

---

# Phase 16 — Integration Tests (Test Pipeline 2/4)

## Goal

Validate **real cross-module flows** — mocked unit boundaries can
soft-fail in prod.

## Lenses

API endpoint (HTTP → handler → DB → response), DB layer (repository
→ query → in-memory PG/SQLite), service-to-service real connections,
background jobs (emit → queue → consumer → DB).

## Mock vs real

**Prefer real:** in-memory DB, testcontainers, embedded service.
Mock only for external services (3rd-party APIs).

## CLAUDE.md auto-rule

> Don't mock the database — mocked tests passed but prod migration
> failed. Integration tests must hit a real DB.

## Pipeline

Detect missing → set up (testcontainers / in-memory) → write end-to-
end flow tests → run until GREEN.

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Audit output

> **Model:** `asama-16-not-applicable reason=...` (when out of scope) plain text in reply.
> **Hook:** `asama-16-scan`, `asama-16-test-N-added`, `asama-16-end-green` (hook writes on full-suite green via post_tool).
> **Details:** see "Audit emission channel" contract in main skill.

`asama-16-scan count=K` → `asama-16-test-N-added` →
`asama-16-end-green` | `asama-16-not-applicable`.

## Anti-patterns

- Mock-everything (hides prod divergence).
- Silent skip without audit.
- DB state pollution (each test must start fresh).
