---
name: mycl-asama19-etki
description: MyCL Aşama 19 — Etki İncelemesi (sınırsız soru). "Bu değişiklik başka neyi kırar?" Çağıranlar, ortak yardımcılar, API contract, schema/migration, config, cache, build/toolchain. Aşama 10'la karışmaz (orada risk, burada downstream). Her etki askq (skip/fix/rule).
---

# Aşama 19 — Etki İncelemesi (sınırsız soru)

## Amaç

Yazılan kodun **projenin DİĞER yerlerine** olan downstream etkilerini
bul. Sorusu: "Bu değişiklik başka neyi kırar?"

## Aşama 10'la fark

- **Aşama 10 (Risk):** Yazdığım kodun **kendi içinde** boşluğu var mı?
  (eksik validation, race, n+1)
- **Aşama 19 (Etki):** Yazdığım kodun **dışına** etkisi var mı?
  (importer'lar, contract, downstream)

## Aşama 19 mercek

| Etki | Örnek |
|---|---|
| Çağıran dosyalar (importer'lar) | `userService.getUser()` döndürdüğü tip değişti |
| Davranışı değişen ortak yardımcılar | `formatDate()` artık UTC dönüyor |
| API/contract kırılması | `/api/users` endpoint response shape değişti |
| Şema/migration etkileri | Yeni NOT NULL column → eski rows? |
| Konfigürasyon değişiklikleri | `LOG_LEVEL` default değişti, prod davranış? |
| Cache invalidation | Format değişti, cache eski payload tutuyor |
| Build/toolchain/dependency | Major bump → CI runtime farkı |

## YASAKLAR

- ❌ **Aşama 10'da çözülmüş riskleri tekrar etmek** — Aşama 19 farklı
  kapı; downstream etkiyi kontrol et
- ❌ **"Sadece bu turda yazılan dosyalar"** listesi — eksik;
  importer'lar farklı dosyalarda
- ❌ **"Bir sonraki sefere bakacağız"** notu — pipeline kapanmaz, etki
  şimdi belgelenir

## Etki askq formatı

Her etki **tek tek** AskUserQuestion (Aşama 10'a benzer):

```
MyCL <version> | Aşama 19 — Etki maddesi #1
```

Seçenekler (3):
- **Skip** → bu etkiyi yok say (`asama-19-item-1-resolved decision=skip`)
- **Fix** → spesifik düzeltme uygula (`decision=apply`)
- **Rule** → kalıcı kural yap (Rule Capture; `decision=rule`)

## Sınırsız soru

Aşama 10 gibi sınırsız — etki listesi 30 maddeyse 30 askq açılır.

## Mid-pipeline reconfirmation (#13)

Etki listesi 10. maddeyi aştığında hook `asama-19-mid-reconfirm-needed`
audit'i yazar; DSI direktifi modele askq açma yönlendirmesi gönderir:
```
MyCL <version> | Aşama 19 ortası — hâlâ bu yönde mi ilerleyelim?
```
Geliştirici cevapladıktan sonra model cevabına
`asama-19-mid-reconfirm-acked` text-trigger'ını yazar; hook yakalar,
direktif susar. **Soft guidance**: askq açılmasını hook deny ile
zorlamaz — geliştirici context'i bilir, gerekirse direktifi ihmal
edebilir.

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Çıktı (audit)

> **Model:** `asama-19-complete` (tüm etki maddeleri çözüldükten sonra) cevap metninde düz yazıyla.
> **Hook:** `asama-19-items-declared count=K`, `asama-19-item-N-resolved decision=...` (her askq sonucu için askq classifier yazar).
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-19-items-declared count=K
asama-19-item-1-resolved decision=apply  # veya skip/rule
asama-19-item-2-resolved decision=skip
...
asama-19-complete
```

### Hook enforcement (1.0.29)

- `asama-19-items-declared count=K` → audit emit **ve**
  `state.open_impact_count = K` (Aşama 22 tamlık denetimi okur). Aşama
  10'a özel `state.open_severity_count`'tan ayrı; karışmaz.
- `asama-19-item-M-resolved decision=apply|skip|rule` → audit emit;
  `decision=rule` ek `asama-19-rule-capture-M` audit (1.0.25
  Aşama 10 ile ortak generic kanal).
- Audit log'da `asama-19-item-M-resolved` sayısı 10'a ulaşınca hook
  idempotent `asama-19-mid-reconfirm-needed` emit eder; DSI direktifi
  modele askq açma yönlendirmesi gönderir.
- Model askq sonrası `asama-19-mid-reconfirm-acked` text-trigger'ı
  yazar; hook yakalar, direktif susar.

**Hook auto-emit YOK** (`complete`, `escalation`, vb. model
sorumluluğunda — 1.0.26+ sözleşmesi).

## Aspirational flag'ler (gelecek tur)

`gate_spec.json` Aşama 19'da `self_critique_required: true` ve
`public_commitment_required: true` set edilmiş ama şu an hiçbir hook
tarafından enforce edilmiyor. `hooks/lib/selfcritique.py` modülü
mevcut, API tam — ama hook bağlantısı eksik. Aşama 14 _note'unda
aynı durum belgelendi; ileri tur ayrı kapsam.

## Anti-pattern

- ❌ count=0 ile geç — gerçek etki taraması yapıldı mı? Grep
  importer'ları, api contract, schema diff
- ❌ Sürekli skip → Rule Capture yapmadan; "bu pattern'i bir daha
  yakalama" niyetini kalıcı yap
- ❌ Aşama 10'la duplicate item → Aşama 19 downstream-only

---

# Phase 19 — Impact Review (unbounded questions)

## Goal

Find downstream effects of written code: "what else breaks?"

## Difference from Phase 10

Phase 10 = self risks (within written code). Phase 19 = downstream
impact (outside).

## Lenses

Importers, shared utilities behavior change, API/contract breakage,
schema/migration impact on existing data, config defaults
propagation, cache invalidation, build/toolchain/dependency drift.

## Forbidden

Repeating Phase-10-resolved risks; only-this-turn file lists; "next
session" notes.

## Impact askq

Same one-by-one pattern as Phase 10. Options: Skip / Fix / Rule
(Rule Capture). Mid-pipeline reconfirmation when list >10 items.

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Audit output

> **Model:** `asama-19-complete` (after all impact items resolved) plain text in reply.
> **Hook:** `asama-19-items-declared count=K`, `asama-19-item-N-resolved decision=...` (askq classifier writes per item).
> **Details:** see "Audit emission channel" contract in main skill.

`asama-19-items-declared count=K` → `asama-19-item-N-resolved
decision=apply|skip|rule` → `asama-19-complete`.

### Hook enforcement (1.0.29)

- `asama-19-items-declared count=K` → audit + `state.open_impact_count = K`.
- `asama-19-item-M-resolved decision=...` → audit; `decision=rule`
  emits an extra `asama-19-rule-capture-M`.
- When 10+ `asama-19-item-M-resolved` audits exist, hook emits
  `asama-19-mid-reconfirm-needed` (idempotent); DSI directive prompts
  model to open an askq.
- Model emits `asama-19-mid-reconfirm-acked` text-trigger after the
  developer answers; hook captures it and the directive falls silent.
- Hook does NOT auto-emit `complete` or `escalation-needed`
  (model-responsibility boundary preserved from 1.0.26+).

## Aspirational flags (next turn)

`gate_spec.json` Phase 19 has `self_critique_required: true` and
`public_commitment_required: true`, but no hook enforces them.
`hooks/lib/selfcritique.py` exists with a complete API but is not
wired in. Same situation as Phase 14 _note; out of scope for this
turn.

## Anti-patterns

- count=0 without grepping importers / contract diff / schema diff.
- Continuous skip without Rule Capture.
- Duplicating Phase 10 items (downstream-only here).
