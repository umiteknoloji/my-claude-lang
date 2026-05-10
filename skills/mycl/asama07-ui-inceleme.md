---
name: mycl-asama07-ui-inceleme
description: MyCL Aşama 7 — UI İncelemesi (DEFERRED). Aşama 6 STOP eder; askq önceden açılmaz. Geliştiricinin sonraki tur free-form cevabı intent classify edilir (approve/revise/cancel/sen-de-bak). approve+revise birlikteyse revise kazanır. Aşama 6 atlandıysa otomatik atlanır.
---

# Aşama 7 — UI İncelemesi (DEFERRED)

## Amaç

Geliştirici UI'ı tarayıcıda görüp onaylasın. Yanlışsa Aşama 6'ya
**geri sarma şansı** — backend yazılmadan önce.

## DEFERRED mode (v6.5.0+)

**Aşama 6 dev server + browser auto-open ile biter ve STOP.** Aşama 7
askq **önceden açılmaz** — geliştiricinin bir sonraki turn'undaki
free-form cevabı intent classification ile yorumlanır.

### Intent classification (lib/askq.py)

| Intent | Cue örnekleri (TR + EN) |
|---|---|
| approve | "tamam", "güzel", "onaylıyorum", "ok", "looks good", "approved" |
| revise | "değiştir", "büyüt", "renk", "küçült", "change", "make it" |
| cancel | "iptal", "vazgeç", "cancel", "stop" |

### Sıralama (CRITICAL)

```
cancel > revise > approve > ambiguous
```

**"Approve + revise birlikte"** (örn. "güzel ama font'u büyüt") →
**revise kazanır** (kullanıcı değişiklik istiyor).

### Boş / ambiguous fallback

Boş cevap, tek emoji, anlaşılmaz metin → fallback **askq açılır** (4
seçenek):
- **Onayla** → asama-7-complete
- **Revize** → Aşama 6'ya geri dön
- **Sen-de-bak** → opt-in Playwright + screenshot + multimodal Claude
  UI'a bakar (1.0.x'te)
- **İptal** → pipeline durur

## Narration kuralı (v13.0.15)

Aşama 7 deferred **≠ skipped**. Faz listesi yazılırken DAİMA görünür
kalır:

```
Aşama 5 → 6 → 7 (deferred) → 8 → 9
```

Sadece Aşama 6 atlandığında işaretlenir:
```
Aşama 5 → 6 (atlandı) → 7 (atlandı — Aşama 6) → 8 → 9
```

## Atlama (otomatik)

Aşama 6 atlandıysa Aşama 7 otomatik atlanır:
```
asama-7-skipped reason=asama-6-skipped
```

## İzinli tool'lar (Layer B)

`AskUserQuestion` (fallback için) + global readonly. Write/Edit/Bash
yasak — Aşama 6'ya dönünce orada açılır.

## Çıktı (audit)

> **Model:** Bu aşama askq intent classification ile sürer; model `asama-7-complete` zikretmez. Free-form intent → hook karar verir (approve/revise/cancel).
> **Hook:** `asama-7-complete`, `asama-7-skipped`, `asama-7-revise-requested` — askq classifier sonucuna göre hook yazar.
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-7-complete    # approve veya fallback "Onayla"
asama-7-skipped     # cancel veya Aşama 6 skipped
```

revise → Aşama 6'ya geri dön (state.current_phase=6 set, ui_reviewed=
False); audit `asama-7-revise-requested`.

## Anti-pattern

- ❌ Aşama 7'de askq önceden açma — DEFERRED mode bunu yasaklıyor;
  free-form intent classify önce
- ❌ "approve + revise birlikte" → approve kabul etme — sıralama
  kuralı: revise kazanır
- ❌ Aşama 7'yi listede gizleme — narration kuralı: deferred ≠ skipped

---

# Phase 7 — UI Review (DEFERRED)

## Goal

Developer reviews the UI in the browser; gets a chance to roll back
to Phase 6 before backend is written.

## Deferred mode

Phase 6 ends with dev server + browser auto-opened. Phase 7 askq is
**not pre-opened**. The developer's next free-form response is
intent-classified.

## Intent priority

`cancel > revise > approve > ambiguous`. **Approve + revise together
→ revise wins** (developer wants change).

## Fallback askq (4 options)

When response is empty / single emoji / ambiguous:
- Approve → asama-7-complete
- Revise → back to Phase 6
- Sen-de-bak → opt-in Playwright + screenshot + multimodal review
- Cancel → pipeline halts

## Narration rule

Phase 7 deferred ≠ skipped. Always visible in phase list as
`Phase 7 (deferred)` unless Phase 6 was actually skipped.

## Auto-skip

Phase 6 skipped → `asama-7-skipped reason=asama-6-skipped`.

## Allowed tools

`AskUserQuestion` (fallback only) + global readonly.

## Anti-patterns

- Pre-opening askq before reviewing free-form intent.
- Treating "approve + revise" as approve.
- Hiding Phase 7 in phase list (must show as deferred).
