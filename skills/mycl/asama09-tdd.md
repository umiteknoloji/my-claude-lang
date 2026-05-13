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

## Hook enforcement (1.0.24)

- **AC audit yakalama:** `stop.py::_detect_phase_9_ac_trigger` özel
  regex (`asama-9-ac-(\d+)-(red|green|refactor)`) ile model'in emit
  ettiği AC audit'lerini yakalar, idempotent audit emit eder.
  GREEN stage → `state.tdd_last_green` güncellenir.
- **TDD compliance score:** `post_tool.py::_maybe_record_tdd_write`
  cp==9'da her Write/Edit success'i `tdd.record_write`'a iletir →
  `state.tdd_compliance_score` 0-100 güncellenir (test-before-prod
  oranı). Aşama 22 tamlık denetimi bu skoru okur.
- **Regression block (1.0.24):** `post_tool.py::_maybe_clear_regression_block`
  test runner Bash sonucuna göre `state.regression_block_active`
  set/clear eder. FAIL → True + `regression-fail` audit; GREEN →
  False + `regression-clear` audit. 1.0.23 öncesi sadece clear vardı.

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

**`Task` ve `Agent` (subagent dispatch) bu fazda YASAK** (Aşama
1/3/5/6/7/8 pattern'i). TDD red/green/refactor döngüsü ana bağlamda
yürür; subagent dispatch gereksiz. Subagent sadece Aşama 10/14 paralel
mercek için ayrıldı.

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

- `self_critique_required: true` — 1.0.33'ten itibaren hook
  enforce'da. Aşama 9 sonunda `selfcritique-passed phase=9` veya
  `selfcritique-gap-found phase=9 items="..."` yazılır; Aşama 22
  invariant 6 doğrular.
- `public_commitment_required: true` — 1.0.34'ten itibaren hook
  enforce'da. Faz başlarken `commitment-recorded phase=9 text="..."`
  yazılır.
- Not (1.0.36): `subagent_rubber_duck` skill claim'i gate_spec'te
  zaten 1.0.24'te kaldırılmıştı; doc-truth ile burada da silindi.

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

- `self_critique_required: true` — hook-enforced since 1.0.33. At
  Phase 9 end the model writes `selfcritique-passed phase=9` or
  `selfcritique-gap-found phase=9 items="..."`; Phase 22 invariant 6
  verifies it.
- `public_commitment_required: true` — hook-enforced since 1.0.34.
  At phase entry the model writes `commitment-recorded phase=9
  text="..."`.
- Note (1.0.36): the `subagent_rubber_duck` skill claim was already
  removed from gate_spec in 1.0.24; doc-truth cleanup here.

## Anti-patterns

- Code before test (no RED audit).
- Over-engineering in GREEN.
- Skipping refactor.
- Skipping ACs (surfaces in Phase 22 completeness audit).
- Forgetting fake → real API in UI flow.
