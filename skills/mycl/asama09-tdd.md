---
name: mycl-asama09-tdd
description: MyCL Aşama 9 — TDD Yürütme. Aşama 4 spec'teki her AC için sırayla RED → GREEN → REFACTOR. UI flow varsa fake data → real API geçişi bu fazda. Aşama 5 pattern_summary her tur DSI'da hatırlatılır. Çıktı her AC için 3 audit (asama-9-ac-N-red/green/refactor).
---

# Aşama 9 — TDD Yürütme

## Amaç

**Test-First geliştirme** — kod yazılmadan önce **her AC için** test
yazılır, sonra kodu geçer hale getirilir. Spec MUST'larının teknik
karşılığı bu fazda doğar.

## TDD döngüsü (her AC için)

### 1. KIRMIZI (RED)

- Spec AC'sini test'e dönüştür: "Given X, When Y, Then Z"
- Önce **başarısız olan test yaz**, çalıştır → **fail görsün**
- Audit: `asama-9-ac-{i}-red`

### 2. YEŞİL (GREEN)

- Testi geçirecek **MİNİMUM üretim kodu** yaz
- "Future-proof" değil — sadece bu testi geçecek kadar
- Çalıştır → **pass**
- Audit: `asama-9-ac-{i}-green`

### 3. REFAKTÖR (REFACTOR)

- Kodu temizle: DRY, isimlendirme, ölü kod sil
- **Testler hâlâ yeşil** — break edilmedi
- Aşama 5 pattern_summary'e uygunluk kontrolü
- Audit: `asama-9-ac-{i}-refactor`

## AC sırası

Spec'teki sıraya göre — atlama yok. AC_1 RED+GREEN+REFACTOR
tamamlanmadan AC_2'ye geçme.

## Sonda tam test takımı

Tüm AC'ler refactor edildikten sonra **tam test suite** yeniden
çalıştırılır:
```bash
npm test          # veya pytest, go test, cargo test, vs.
```

post_tool reaktif:
- Test runner GREEN → `regression_block_active=False`
- Audit: `regression-clear`

## UI flow varsa

Aşama 6'da fake data ile UI yazıldı. Aşama 9'da:
- API endpoint'leri yaz (Aşama 8 schema'ya göre)
- UI'daki fake data'yı **gerçek API çağrısına** değiştir
- E2E happy path test ile doğrula

## DSI hatırlatma (Aşama 5 pattern)

Her tur başı DSI'da `state.pattern_summary` görünür:
> "Bu projede error handling Result type kullanır. Test naming
> snake_case. Yeni kod buna uysun."

Bu hatırlatma TDD koduna uygulanır — yeni test mevcut framework +
fixture düzenine uyar.

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Çıktı (her AC için 3 audit)

> **Model:** `asama-9-complete` (sonda — tüm AC'ler bittikten sonra) cevap metninde düz yazıyla.
> **Hook:** `asama-9-ac-N-red/green/refactor` (her AC döngüsünde test runner sonucuyla `tdd.py` yazar) + `regression-clear` (tam suite YEŞİL post_tool sinyali).
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-9-ac-1-red
asama-9-ac-1-green
asama-9-ac-1-refactor
asama-9-ac-2-red
asama-9-ac-2-green
asama-9-ac-2-refactor
...
asama-9-complete (sonda — tüm AC'ler tamamlandı)
```

`asama-9-complete` `required_audits_any` listesinde → universal loop
Aşama 10'a advance.

## Disiplin gerekleri

- `subagent_rubber_duck: true` — kritik faz; haiku subagent ile
  ikinci-göz pair-check sonda

## Anti-pattern

- ❌ Önce kod yaz, sonra test (TDD'nin tersi) — RED audit yok demektir
- ❌ Aşırı production code GREEN aşamasında — minimum geçecek kadar yaz
- ❌ Refactor edmeden complete — kod kirli kalır, Aşama 11-14 fazla iş
- ❌ AC atlama — sıralı yürütme; eksik AC Aşama 22'de yüzeye çıkar
- ❌ Fake data ile production'a geçiş — UI flow'da gerçek API'ye
  geçişi unutma

---

# Phase 9 — TDD Execution

## Goal

Test-First — write a failing test for each AC, then minimum code,
then refactor.

## Cycle (per AC)

1. **RED** — failing test, run, see fail. Audit: `asama-9-ac-{i}-red`.
2. **GREEN** — minimum code to pass. Audit: `asama-9-ac-{i}-green`.
3. **REFACTOR** — clean code, tests still green. Audit:
   `asama-9-ac-{i}-refactor`.

## Order

Spec AC order — no skipping. Each AC's full cycle before next.

## Final test run

After all refactors, full test suite. post_tool:
`regression_block_active=False`, audit `regression-clear`.

## UI flow

Phase 6 used mock data. Phase 9: write API endpoints (per Phase 8
schema), replace mocks with real calls, validate via E2E.

## DSI reminder

`state.pattern_summary` (from Phase 5) is shown every turn — new
code must follow existing patterns.

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Audit output

> **Model:** `asama-9-complete` (at end — after all ACs) plain text in reply.
> **Hook:** `asama-9-ac-N-red/green/refactor` per AC (`tdd.py` writes on test runner result) + `regression-clear` (full suite green via post_tool).
> **Details:** see "Audit emission channel" contract in main skill.

3 audits per AC + `asama-9-complete` at end.

## Discipline

`subagent_rubber_duck: true` (haiku pair-check at end).

## Anti-patterns

- Code before test (no RED audit).
- Over-engineering in GREEN.
- Skipping refactor.
- Skipping ACs (surfaces in Phase 22 completeness audit).
- Forgetting fake → real API in UI flow.
