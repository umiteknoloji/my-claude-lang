---
name: mycl-asama03-ozet
description: MyCL Aşama 3 — Mühendislik Özeti. Onaylı niyeti İngilizce mühendislik diline çevir; SESSİZ faz, askq yok. Belirsiz fiilleri cerrahi fiillere yükselt; yeni varlık/feature/NFR ekleme yasak. Çıktı `engineering-brief + asama-3-complete`.
---

# Aşama 3 — Mühendislik Özeti

## Amaç

Aşama 1-2'de onaylanan niyeti **İngilizce mühendislik diline çevir.**
Sıkı çevirmen rolü — yorum yok, ekleme yok. Sonraki Aşama 4 spec'i
bu özet üzerinden yazılır.

## Ne yapılır

**SESSİZ FAZ** — askq yok, kullanıcıya soru sorulmaz. Hook bu fazı
otomatik tamamlanmış sayar.

Doğal dil çevirisi yapılır (kullanıcı dili → İngilizce):

| Türkçe | İngilizce mühendislik |
|---|---|
| listele | render a paginated table |
| yönet | expose CRUD operations |
| yap / oluştur | implement |
| getir | fetch / retrieve |
| sil | delete |

Belirsiz fiiller cerrahi fiillere **yükseltilir** (model implicit
karar veriyor); bu yükseltmeler `[default: X, changeable]` etiketiyle
işaretlenir.

## Yasaklar

- ❌ Yeni varlık ekleme (Aşama 1'de yoksa Aşama 3'e gelmez)
- ❌ Yeni özellik ekleme ("admin paneli de gerekli olabilir" → yasak)
- ❌ Yeni NFR ekleme ("p99 < 50ms olmalı" — Aşama 2'de gating yoksa
  yasak)
- ❌ Auth ekleme (Aşama 2 boyut 1 sormadıysa)
- ❌ Persistence layer ekleme (Aşama 2 boyut 8 sormadıysa)

## İzinli tool'lar

Yok (silent_phase: true). Read global allowlist'te ama gerek yok —
sadece çeviri.

## Çıktı (audit)

```
engineering-brief
asama-3-complete
```

Hook silent_phase olduğu için otomatik emit (model emit etmez):
universal completeness loop Aşama 2'den 3'e advance ettikten sonra
hemen 4'e advance eder (`silent_phase: true` flag'i + `engineering-brief`
audit `required_audits_any` listesinde).

Pratik: model Aşama 3'te bir tur "ben özet yazdım, devam ediyorum"
diyebilir; hook universal loop ile state.current_phase 4'e geçer.

## Anti-pattern

- ❌ "Niyet eksik gibi, bir şey daha ekleyeyim" — Aşama 1'e geri dön.
- ❌ "Aşama 3 sessiz, atlayayım" — özet yapılmazsa Aşama 4 spec'i kötü.
- ❌ Türkçe spec yazma — Aşama 4 İngilizce; çeviri zincirini bozma.

---

# Phase 3 — Engineering Brief

## Goal

Translate the approved intent (Phases 1-2) into engineering English.
Strict translator role — no interpretation, no additions.

## Action

**SILENT phase** — no askq, no user prompt. Hook auto-completes.

Verb upgrades from natural language to surgical engineering verbs:
- "list" → "render a paginated table"
- "manage" → "expose CRUD operations"
- "build" → "implement"
- "fetch" → "fetch / retrieve"

Marked `[default: X, changeable]`.

## Forbidden

- New entities, features, NFRs not in Phase 1
- Auth/persistence not gated in Phase 2

## Audit output

`engineering-brief` + `asama-3-complete`. Auto-advanced via universal
completeness loop (silent_phase=true).

## Anti-patterns

- Adding entities/features beyond Phase 1.
- Skipping the brief (degrades Phase 4 spec quality).
- Writing the brief in Turkish (Phase 4 is English).
