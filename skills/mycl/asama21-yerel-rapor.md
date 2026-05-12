---
name: mycl-asama21-yerel-rapor
description: MyCL Aşama 21 — Yerelleştirilmiş Rapor (atlanabilir). Aşama 20 raporunu kullanıcı diline çevir; sıkı çevirmen — yorum/ekleme yok. Teknik token'lar (file:line, test isimleri, CLI flag) korunur. İngilizce oturumda kimlik fonksiyonu — atlanır.
---

# Aşama 21 — Yerelleştirilmiş Rapor (atlanabilir)

## Amaç

Aşama 20 raporunu **kullanıcının diline çevir.** Geliştirici
İngilizce raporu okumak zorunda kalmasın.

## Sıkı çevirmen rolü

- ✅ EN → kullanıcı dili çevirisi
- ❌ Yorum eklemek yasak
- ❌ Ekleme/silme yasak
- ❌ "Şu daha iyi olur" notu yasak

## Korunan teknik token'lar

Aşağıdakiler çevrilmez (1.0.0 sözleşmesi):

| Tip | Örnek |
|---|---|
| Dosya yolu | `tests/auth.test.js:42` |
| Test ismi | `test_user_can_login` |
| Audit ismi | `asama-9-ac-1-green` |
| Timestamp | `2026-05-09T20:00:00Z` |
| CLI flag | `--config p/security-audit` |
| Code identifier | `OrderService.create()` |
| Status glyph | ✅ ⚠️ ❌ |

## Atlama (otomatik)

İngilizce oturumda zaten İngilizce — **kimlik fonksiyonu** (boşa
çevirmek anlamsız):

```
asama-21-skipped reason=already-english
```

Diğer destekli dil: **Türkçe** (TR + EN MyCL'in 2 desteklediği dil).
Aşama 20 EN raporu Türkçeye çevrilir; başka dilde session'larda 1.0.0
İngilizce'de kalır (1.0.x'te 14 dil eski sürümden geri gelebilir).

## İzinli tool'lar (Layer B)

`Write` + global readonly. Sıkı çevirmen rolü gereği `Edit`/`MultiEdit`/
`Bash` izinli değil — Aşama 21 yeni bir lokalize rapor yazar, mevcut
dosyaları düzenlemez (gate_spec.json kanonik kaynak).

## Çıktı (audit)

> **Model:** `asama-21-complete` (TR çevirisi yazıldıktan sonra) veya `asama-21-skipped reason=already-english` (EN oturumda) cevap metninde düz yazıyla.
> **Hook:** Aşama 21'e özel hook kodu yok; mevcut generic kanallar yakalar.
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-21-complete (TR çevirisi yazıldı)
asama-21-skipped reason=already-english
```

### Audit capture kanalı (1.0.31)

Aşama 21'e özel hook kodu yok; mevcut generic kanallar yeterli:

- `asama-21-complete` → `_detect_phase_complete_trigger` (generic
  complete trigger) tarafından yakalanır.
- `asama-21-skipped reason=already-english` → `_PHASE_EXTENDED_TRIGGER_RE`
  (1.0.21 generic extended trigger; `skipped` suffix'i tüm fazlar için
  yakalar) tarafından yakalanır.

Hook auto-emit YOK; her iki audit modelin sorumluluğunda. Dil tespiti
de modelin: prompt'tan TR/EN'i ayırt eder, ona göre çeviri yapar veya
atlar. Aşama 22 tamlık denetimi `asama-21-skipped` audit'ini görerek
skip kararını doğrular (silent skip riskini detection control ile
kapatır).

## Anti-pattern

- ❌ Çeviriye ekleme yapma ("şunu da belirtelim") — sıkı çevirmen
- ❌ Teknik token'ı çevirme (`tests/auth.test.js` → `testler/...`) —
  navigasyon kırılır
- ❌ Status glyph'i sözel çevir (`✅` → "tamam") — tablo bozulur

---

# Phase 21 — Localized Report (skippable)

## Goal

Translate Phase 20 report to the developer's language.

## Strict translator role

EN → user language. No additions, no comments, no "this would be
better" suggestions.

## Preserved technical tokens

File paths, test names, audit names, timestamps, CLI flags, code
identifiers, status glyphs (✅ ⚠️ ❌) — never translated.

## Skip

`asama-21-skipped reason=already-english` for English sessions
(identity function). MyCL 1.0.0 supports TR + EN; other languages
remain in English (1.0.x may restore 14-language support).

## Allowed tools

`Write` + global readonly. Strict translator role: Phase 21 writes a
new localized report, not edit existing files (gate_spec.json is the
canonical source).

## Audit output

> **Model:** `asama-21-complete` (after TR translation) or `asama-21-skipped reason=already-english` (EN session) plain text in reply.
> **Hook:** No phase-21-specific hook code; existing generic channels capture.
> **Details:** see "Audit emission channel" contract in main skill.

`asama-21-complete` | `asama-21-skipped reason=already-english`.

### Audit capture channel (1.0.31)

No Phase-21-specific hook code is needed; the existing generic
channels suffice:

- `asama-21-complete` is captured by `_detect_phase_complete_trigger`
  (the generic complete-trigger detector).
- `asama-21-skipped reason=already-english` is captured by
  `_PHASE_EXTENDED_TRIGGER_RE` (the 1.0.21 generic extended trigger
  matches the `skipped` suffix across all phases).

No hook auto-emit; both audits are model-responsibility. Language
detection is also model-responsibility (it distinguishes TR/EN from
the prompt and either translates or skips). Phase 22 completeness
verifies the skip decision by reading the `asama-21-skipped` audit
(detection control closes the silent-skip risk).

## Anti-patterns

- Adding commentary in translation.
- Translating technical tokens (breaks navigation).
- Verbalizing status glyphs (breaks table).
