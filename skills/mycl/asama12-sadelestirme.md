---
name: mycl-asama12-sadelestirme
description: MyCL Aşama 12 — Sadeleştirme (Kalite Pipeline 2/4). Erken soyutlama, gereksiz karmaşa, duplikat mantık, gereksiz pattern, "ileride lazım olur" kodu. tara → düzelt → yeniden tara döngüsü, K=0 olana kadar. askq YOK. Çıktı asama-12-rescan count=0.
---

# Aşama 12 — Sadeleştirme (Kalite Pipeline 2/4)

## Amaç

Yeni veya değişen dosyalarda **gereksiz karmaşıklığı** yok et.

## Aşama 12 mercek

| Sorun | Örnek |
|---|---|
| Erken soyutlama | 1 implementasyonu olan interface, factory tek caller |
| Gereksiz karmaşa | 5 line'lık yardımcı `f = (x) => x` |
| Duplikat mantık | Aynı validation 3 dosyada — common util'e alınabilir |
| Gereksiz pattern | Singleton, observer, strategy patterns gereksizken |
| "İleride lazım olur" | Hiç çağrılmayan parametre, unused config flag |

## Pipeline (3-step döngü)

1. **Tara** → 5 mercekten her birini ayrı geç, K1 sorunu listele
2. **Düzelt** → otomatik fix (kod silme, util çıkarma, pattern kaldırma)
3. **Yeniden tara** → K=0 olana kadar tekrar (max 5)

## CLAUDE.md prensipleri

- **Composition over inheritance** — derin class hierarchy → composition
- **Three similar lines is better than a premature abstraction** — 3
  benzer satır soyutlamadan iyi
- **Don't add features beyond what the task requires** — task dışı
  feature ekleme

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.
askq YOK (kalite pipeline kuralı).

## Çıktı (audit)

> **Model:** `asama-12-complete` (rescan count=0 olduktan sonra) cevap metninde düz yazıyla.
> **Hook:** `asama-12-scan`, `asama-12-issue-N-fixed`, `asama-12-rescan` (tarayıcı/fixer döngüsünde hook yazar).
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-12-scan count=K
asama-12-issue-N-fixed
asama-12-rescan count=0
asama-12-complete
```

### Hook enforcement (1.0.26)

Hook, Aşama 11 ile aynı generic text-trigger setini kullanır
(`asama-12-scan / issue-M-fixed / rescan / escalation-needed`).
`asama-12-complete` ve `asama-12-escalation-needed` modelin
sorumluluğunda; hook auto-emit yapmaz. Detay: Aşama 11 skill
"Hook enforcement (1.0.26)" bölümü.

## Anti-pattern

- ❌ "Soyutlama olsa daha temiz olur" → 1 caller varsa soyutlama
  zaten erken
- ❌ Gereksiz pattern eklemek (Aşama 12 onu **kaldırır**, eklemez)
- ❌ Refactor sırasında yeni feature eklemek — sadece **azaltma**

---

# Phase 12 — Simplification (Quality Pipeline 2/4)

## Goal

Eliminate **unnecessary complexity** in new/changed files.

## Phase 12 lens

Premature abstraction, unnecessary complexity, duplicate logic,
unnecessary patterns, "future-proof" dead code.

## CLAUDE.md principles applied

- Composition over inheritance.
- 3 similar lines beat premature abstraction.
- No features beyond task scope.

## Pipeline

Scan → fix (auto, no askq) → rescan until K=0 (max 5).

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Audit output

> **Model:** `asama-12-complete` (after rescan count=0) plain text in reply.
> **Hook:** `asama-12-scan`, `asama-12-issue-N-fixed`, `asama-12-rescan` (scanner/fixer cycle).
> **Details:** see "Audit emission channel" contract in main skill.

`asama-12-scan count=K` → `asama-12-issue-N-fixed` →
`asama-12-rescan count=0` → `asama-12-complete`.

### Hook enforcement (1.0.26)

Hook uses the same generic text-trigger set as Phase 11 (`asama-12-scan
/ issue-M-fixed / rescan / escalation-needed`). `asama-12-complete`
and `asama-12-escalation-needed` are model-responsibility — no
auto-emit. See Phase 11 skill "Hook enforcement (1.0.26)" for details.

## Anti-patterns

- Adding abstractions ("for cleanliness").
- Adding patterns (Phase 12 *removes*, never adds).
- Adding features during refactor.
