---
name: mycl-asama02-hassasiyet
description: MyCL Aşama 2 — Hassasiyet Denetimi. Niyetin 7 boyutta tam ve doğru olduğunu doğrula. Her boyut için karar SILENT-ASSUME / SKIP-MARK / GATE. Çıktı `precision-audit + asama-2-complete` audit'i.
---

# Aşama 2 — Hassasiyet Denetimi

## Amaç

Aşama 1'de toplanan niyeti **7 boyutta** kontrol ederek spec yazmadan
önce gözden kaçan mimari kararları yakala. Spec'te eksik kalırsa Aşama
9 TDD'de geç fark edilir, tekrar başa dönmek pahalıdır.

## 7 Boyut

| # | Boyut | Sorulması gereken |
|---|---|---|
| 1 | Erişim hakkı / yetki | Bu özelliği kim kullanabilir? auth/authz nasıl? |
| 2 | Algoritmik hata modları | Hangi input pattern'leri çökertir? null/empty/overflow? |
| 3 | Kapsam dışı sınırlar | Niyet hangi noktada durur? "+ admin paneli" istenmedi mi? |
| 4 | Kişisel veri (PII) | İşlenen veri PII içeriyor mu? log'lara sızabilir mi? |
| 5 | Audit / gözlemlenebilirlik | Critical path'te log/metric/trace var mı? |
| 6 | Performans SLA | Beklenen p50/p99 latency? throughput? |
| 7 | Idempotency / retry | Aynı request iki kez gelirse ne olur? |

## Karar Türleri (boyut başına)

- **SILENT-ASSUME** → Endüstri varsayımı kullan, spec'te `[assumed: X]`
  işaretle. Örnek: HTTPS varsayımı (web app'te).
- **SKIP-MARK** → Güvenli varsayım yok, spec'te `[unspecified: X]`
  bırak. Aşama 4 onayında geliştirici belirler.
- **GATE** → Mimari etkili karar; geliştiriciye sor (AskUserQuestion).

## AskUserQuestion prefix

```
MyCL <version> | Aşama 2 — Precision-audit niyet onayı
MyCL <version> | Phase 2 — Precision-audit intent confirmation
```

## İzinli tool'lar (Layer B)

`AskUserQuestion` + global readonly. Write/Edit/Bash yasak.

## Çıktı (audit)

```
precision-audit
asama-2-complete
```

## Self-critique zorunlu

Aşama 2 `self_critique_required: true` (gate_spec.json). Audit emit
öncesi: "7 boyutu da geçtim mi? GATE kararlarını sordum mu?
SKIP-MARK'ları işaretledim mi?"

## Anti-pattern

- ❌ "7 boyut çok detay, atlayayım" — Aşama 4 spec'i eksik çıkar.
- ❌ Her şey için GATE — kullanıcı bunalır; SILENT-ASSUME/SKIP-MARK ile
  daralt.
- ❌ Karar verme hierarchy karıştırma — bir boyutta SILENT-ASSUME +
  başka boyutta GATE olabilir; her biri bağımsız.

---

# Phase 2 — Precision Audit

## Goal

Verify the intent across **7 dimensions** before writing the spec.

## 7 dimensions

1. Access / authorization
2. Algorithmic failure modes
3. Out-of-scope boundaries
4. PII handling
5. Audit / observability
6. Performance SLA
7. Idempotency / retry

## Decision per dimension

- **SILENT-ASSUME** — industry default, spec marked `[assumed: X]`
- **SKIP-MARK** — no safe default, spec marked `[unspecified: X]`
- **GATE** — architectural impact, ask developer

## AskUserQuestion prefix

`MyCL <version> | Phase 2 — Precision-audit intent confirmation`

## Allowed tools

`AskUserQuestion` + global readonly. Write/Edit/Bash forbidden.

## Audit output

`precision-audit` + `asama-2-complete`. Self-critique required.

## Anti-patterns

- Skipping dimensions ("too detailed").
- Gating everything (overwhelms developer).
