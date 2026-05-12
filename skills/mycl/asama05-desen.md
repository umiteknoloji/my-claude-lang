---
name: mycl-asama05-desen
description: MyCL Aşama 5 — Desen Eşleştirme. Spec'teki dosya yollarına benzer mevcut dosyaları oku; naming/error/test desenlerini çıkar. PATTERN_RULES_NOTICE Aşama 9 TDD boyunca her turda hatırlatılır. Greenfield ya da benzer dosya yoksa atlanır.
---

# Aşama 5 — Desen Eşleştirme

## Amaç

Mevcut kodun **adlandırma / hata-yakalama / test desenlerini** öğren.
Aşama 9 TDD'de yazılan kod, mevcut kodla **tutarlı görünsün** —
"projenin Claude'u" gibi davransın.

## 3 desen

| Boyut | Ne yakalanır |
|---|---|
| Naming Convention | camelCase / snake_case / kebab-case, dosya adlandırma, ID tipi |
| Error Handling | try/catch, Result type, custom error class, error code |
| Test Pattern | test framework (jest/vitest/pytest), fixture düzeni, naming |

## Çalışma akışı

1. Spec'teki dosya yollarına benzer mevcut dosyaları **Glob** ile bul:
   - `src/api/users/*` → `src/api/products/*` (sister directories)
   - Spec'te `src/services/orders.py` → mevcut `src/services/*.py`
2. **Read** ile en az 3-5 dosyayı oku
3. 3 desen için kanıt topla
4. PATTERN_RULES_NOTICE özetini state.pattern_summary'e yaz

## Atlama (skippable)

`gate_spec.json`'da `skippable: true, skip_reason: "greenfield"`.

- **Greenfield:** Yeni proje, benzer dosya yok
- **No-match:** Spec yolları mevcut dosyalarla eşleşmiyor (örn. tek
  dosyalık script)

`asama-5-skipped reason=greenfield` audit emit; Aşama 6'ya geç.

## İzinli tool'lar (Layer B)

`Read, Glob, Grep, LS` (global allowlist'te). Write/Edit/Bash yasak.

**`Task` ve `Agent` (subagent dispatch) bu fazda YASAK** (Aşama 1/3
ile tutarlı, 1.0.20). `_global_always_allowed_tools` listesinde
olsalar bile Aşama 5 küçük scope — Glob/Grep ile codebase tara, 3
deseni özetle. Subagent gereksiz, bağlam şişmez. Subagent dispatch
sadece Aşama 10/14 paralel mercek için ayrıldı.

## Çıktı (audit + state)

> **Model:** Cevap metnine **iki satır** düz yazıyla yaz:
> 1. `pattern-summary: <camelCase|snake_case>, <error pattern>, <test framework>`
> 2. `asama-5-complete` (veya `asama-5-skipped reason=greenfield`)
>
> **Hook (1.0.20):** `asama-5-complete` text-trigger yakalandığında:
> 1. `pattern-summary-stored` yan audit otomatik emit (side_audits)
> 2. Cevap metninden `pattern-summary: <özet>` satırı parse → `state.pattern_summary` yazılır
> 3. Aşama 9 TDD'de DSI `<mycl_pattern_rules>` ile her turda hatırlatır

Örnek emit (greenfield değil):

```
pattern-summary: snake_case dosya adı + camelCase fonksiyon, try/except Result type, pytest fixtures
asama-5-complete
```

Greenfield ise sade:

```
asama-5-skipped reason=greenfield
```

Üçünden biri `required_audits_any` listesinde → universal completeness
loop advance eder.

## Aşama 9 ile bağlantı

state.pattern_summary Aşama 9 TDD'de **her turda** modele DSI ile
hatırlatılır:
> "Bu projede error handling Result type kullanır. Test naming
> snake_case. Yeni kod buna uysun."

## Anti-pattern

- ❌ "Greenfield, ben de yeni desen yaratırım" — pattern olmaması
  pattern olmadığı anlamına gelmez; framework convention varsa onu
  kullan.
- ❌ Pattern özetini state'e yazmadan Aşama 9'a geçme — DSI hatırlatma
  kaybolur.
- ❌ Tek dosya okuyup desen çıkarmak — en az 3-5 dosya oku.

---

# Phase 5 — Pattern Matching

## Goal

Learn the project's naming / error-handling / test patterns so Phase
9 TDD code blends with existing style.

## Three patterns

- Naming convention (camelCase/snake_case, file/ID naming)
- Error handling (try/catch, Result type, custom errors)
- Test pattern (framework, fixtures, naming)

## Workflow

Glob sister files of spec paths → Read 3-5 → extract patterns →
write summary to `state.pattern_summary`.

## Skippable

`skippable: true, skip_reason: "greenfield"` when no similar files.

## Allowed tools

Read/Glob/Grep/LS only.

## Audit output

> **Model:** `asama-5-complete` or `asama-5-skipped reason=...` plain text in reply.
> **Hook:** `pattern-summary-stored` and side audits — model does not write these.
> **Details:** see "Audit emission channel" contract in main skill.

`pattern-summary-stored` | `asama-5-complete` | `asama-5-skipped
reason=greenfield`.

## Phase 9 link

`pattern_summary` is reminded every turn during Phase 9 via DSI.

## Anti-patterns

- "Greenfield → I'll invent a pattern" — use framework conventions.
- Skipping the state write (DSI loses the reminder).
- Reading one file and calling it a pattern.
