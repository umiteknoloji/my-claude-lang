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

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Çıktı (audit)

```
asama-21-complete (TR çevirisi yazıldı)
asama-21-skipped reason=already-english
```

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

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Audit output

`asama-21-complete` | `asama-21-skipped reason=already-english`.

## Anti-patterns

- Adding commentary in translation.
- Translating technical tokens (breaks navigation).
- Verbalizing status glyphs (breaks table).
