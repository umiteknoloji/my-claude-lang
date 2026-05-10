---
name: mycl-asama20-dogrulama
description: MyCL Aşama 20 — Doğrulama Raporu + Sahte Veri Temizliği. Spec Coverage tablosu (her MUST/SHOULD ↔ test). Otomasyon Bariyerleri (yapısal olarak otomatize edilemeyen). Process Trace (trace.log'dan adım adım). Mock data temizliği (__fixtures__/, geçici sahte veri).
---

# Aşama 20 — Doğrulama Raporu + Sahte Veri Temizliği

## Amaç

Spec'teki **her gereksinimin** (MUST/SHOULD) hangi testle
kapsandığını gösteren rapor + projeyi sahte veriden temizle.

## 4 bölüm

### 1. Spec Coverage tablosu

```
| Requirement | Test                       | Status         |
|-------------|----------------------------|----------------|
| MUST_1: ... | tests/auth.test.js:42      | ✅ green       |
| MUST_2: ... | tests/order.test.ts:18     | ✅ green       |
| SHOULD_1: ..| tests/foo.test.ts:8        | ⚠️ partial     |
| MUST_3: ... | —                          | ❌ test yok    |
```

**Status semantiği:**
- `✅ green` → AC fully covered + test green
- `⚠️ partial` → AC covered but test incomplete (örn. error path eksik)
- `❌ test yok` → MUST için test yazılmamış (Aşama 22'de yüzeye çıkar)

state.spec_must_list ↔ audit `asama-9-ac-N-green` zinciri ile her
satır otomatik üretilir.

### 2. Otomasyon Bariyerleri

Yapısal olarak otomatize edilemeyen testler listelenir:
- DOM render correctness (semantik HTML, ARIA)
- Third-party API gerçek davranış (rate limit, partial failure)
- Üretim env var'ı (sadece prod'da set ediliyor)
- Cron job timing (zamansal koşul)
- Multi-region latency
- A/B test variant flag

Bu bölüm kullanıcıyı bilinçli risk farkındalığına getirir;
"otomatize edemeyiz, ama biliyoruz" raporu.

### 3. Process Trace

`trace.log`'dan **adım adım** rapor — pipeline boyunca:
- session_start ts
- Faz transition'lar (1→2→3→...)
- AC RED/GREEN/REFACTOR'ler
- Risk decision'ları
- Impact decision'ları
- Final test green ts

### 4. Mock data temizliği

- `__fixtures__/` ağacı sil (ya da test-only path'e taşı)
- Geçici sahte veri inline (Aşama 6 UI mock array'leri) — gerçek API'ye
  geçiş Aşama 9'da yapıldı, kalıntı yok kontrol
- Seed script'ler (`scripts/seed-dev.ts`) yalnızca dev env'de
- Hardcoded test user'lar source'da yok (`admin/admin123` gibi)

## STRICT mode (fail-open YOK)

Spec Coverage'da `❌ test yok` MUST varsa:
- Aşama 22'de "açık konu" olarak yüzeye çıkar
- `asama-20-complete` audit yine emit edilir (görünürlük + tamlık denetimi
  Aşama 22'nin işi)

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Çıktı (audit)

> **Model:** `asama-20-complete` (rapor + mock cleanup tamamlandıktan sonra) cevap metninde düz yazıyla.
> **Hook:** `asama-20-spec-coverage-rendered must_total=... must_green=...`, `asama-20-mock-cleanup-resolved` (rapor üretiminde hook yazar).
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-20-spec-coverage-rendered must_total=N must_green=M
asama-20-mock-cleanup-resolved
asama-20-complete
```

## Disiplin gerekleri

`subagent_rubber_duck: true` (gate_spec.json) — kritik faz; haiku
ikinci-göz pair-check.

## Anti-pattern

- ❌ Coverage tablosunu yazıp "✅" işaretleme — gerçek test bağlantısı
  yoksa tablo yalan
- ❌ Mock cleanup atlama — production'a sızabilir (test user, seed
  script, fake API key)
- ❌ Process Trace olmadan complete — trace.log oku, gerçek zincirden
  rapor üret

---

# Phase 20 — Verification Report + Mock Data Cleanup

## Goal

Show which test covers each spec requirement (MUST/SHOULD); clean up
fake data from the project.

## 4 sections

1. **Spec Coverage table** — `Requirement | Test | Status`. Status:
   ✅ green / ⚠️ partial / ❌ no test. Auto-generated from
   `spec_must_list` × `asama-9-ac-N-green` audits.
2. **Automation Barriers** — what cannot be automated (DOM render,
   3rd-party API, prod env vars, cron timing, multi-region, A/B
   variants).
3. **Process Trace** — step-by-step from `trace.log` (session_start,
   phase transitions, AC red/green/refactor, decisions, final green).
4. **Mock cleanup** — remove `__fixtures__/`, inline mocks, dev-only
   seeds out of prod path, no hardcoded test users.

## STRICT

Even with `❌ no test` MUSTs, `asama-20-complete` is emitted; Phase
22 surfaces these as open issues.

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Audit output

> **Model:** `asama-20-complete` (after report + mock cleanup) plain text in reply.
> **Hook:** `asama-20-spec-coverage-rendered must_total=... must_green=...`, `asama-20-mock-cleanup-resolved` (hook writes during report rendering).
> **Details:** see "Audit emission channel" contract in main skill.

`asama-20-spec-coverage-rendered must_total=N must_green=M` +
`asama-20-mock-cleanup-resolved` + `asama-20-complete`.

## Discipline

`subagent_rubber_duck: true`.

## Anti-patterns

- ✅-marking without real test linkage.
- Skipping mock cleanup (prod leakage).
- Skipping Process Trace (use real `trace.log`).
