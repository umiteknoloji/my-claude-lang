---
name: mycl-asama13-performans
description: MyCL Aşama 13 — Performans (Kalite Pipeline 3/4). N+1 sorgular, sınırsız döngüler, bloklayan I/O, bellek sızıntısı, gereksiz allocation. tara → düzelt → yeniden tara, K=0 olana kadar. Spec NFR'lara karşı doğrula. askq YOK. Çıktı asama-13-rescan count=0.
---

# Aşama 13 — Performans (Kalite Pipeline 3/4)

## Amaç

Yeni veya değişen dosyalarda **performans sorunlarını** bul + auto-fix.
Spec'te NFR (Aşama 4) varsa hedefe karşı doğrula.

## Aşama 13 mercek

| Sorun | Örnek |
|---|---|
| N+1 sorgu | Loop içinde DB call → JOIN/IN/eager load'a dönüştür |
| Sınırsız döngü | `while (true)` exit kanalı belirsiz, iteration cap yok |
| Bloklayan I/O | Senkron fs.readFileSync hot path'te |
| Bellek sızıntısı | Event listener cleanup yok, cache unbounded grow |
| Gereksiz allocation | Loop içinde new Date(), array.map().filter().map() chain |

## Pipeline (3-step döngü)

1. **Tara** → 5 mercekten geç, profiling output (varsa) oku
2. **Düzelt** → otomatik fix (eager load, pagination, async/await,
   memo, weakref)
3. **Yeniden tara** → K=0 olana kadar tekrar

## NFR doğrulama (spec-bound)

Aşama 4 spec'inde NFR varsa (ör. p99 < 50ms):
- Aşama 9 TDD'den load test fixture varsa çalıştır
- Yoksa Aşama 18 (Yük Testi)'ne defer

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.
askq YOK.

## Çıktı (audit)

> **Model:** `asama-13-complete` (rescan count=0 olduktan sonra) cevap metninde düz yazıyla.
> **Hook:** `asama-13-scan`, `asama-13-issue-N-fixed`, `asama-13-rescan` (tarayıcı/fixer döngüsünde hook yazar).
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-13-scan count=K
asama-13-issue-N-fixed
asama-13-rescan count=0
asama-13-complete
```

### Hook enforcement (1.0.26)

Hook, Aşama 11 ile aynı generic text-trigger setini kullanır
(`asama-13-scan / issue-M-fixed / rescan / escalation-needed`).
`asama-13-complete` ve `asama-13-escalation-needed` modelin
sorumluluğunda; hook auto-emit yapmaz. Detay: Aşama 11 skill
"Hook enforcement (1.0.26)" bölümü.

## Anti-pattern

- ❌ "Performans için micro-optimization yapmadan ölç" — Aşama 13'te
  ölçülebilir N+1 / sync I/O / leak'ler düzeltilir; speculative
  optimization (Aşama 12 sadeleştirme'de yakalanır)
- ❌ NFR olmadan performans hedefi uydurma — spec'te yoksa
  benchmarklamak Aşama 18'in işi
- ❌ Caching ekleme (cache invalidation karmaşası) — basit fix yoksa
  Aşama 10 risk dialog'una taşı

---

# Phase 13 — Performance (Quality Pipeline 3/4)

## Goal

Auto-fix N+1 queries, unbounded loops, blocking I/O, memory leaks,
unnecessary allocations. Validate against spec NFRs (if any).

## Phase 13 lens

N+1 (loop → JOIN/IN/eager), unbounded loops (cap iteration), blocking
I/O (sync → async), memory leaks (cleanup, weakref, bounded cache),
allocation churn (memo, hoist).

## NFR validation

If Phase 4 spec includes NFR (e.g., p99 < 50ms): use Phase 9 fixtures
or defer to Phase 18.

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Audit output

> **Model:** `asama-13-complete` (after rescan count=0) plain text in reply.
> **Hook:** `asama-13-scan`, `asama-13-issue-N-fixed`, `asama-13-rescan` (scanner/fixer cycle).
> **Details:** see "Audit emission channel" contract in main skill.

`asama-13-scan count=K` → `asama-13-issue-N-fixed` →
`asama-13-rescan count=0` → `asama-13-complete`.

### Hook enforcement (1.0.26)

Hook uses the same generic text-trigger set as Phase 11 (`asama-13-scan
/ issue-M-fixed / rescan / escalation-needed`). `asama-13-complete`
and `asama-13-escalation-needed` are model-responsibility — no
auto-emit. See Phase 11 skill "Hook enforcement (1.0.26)" for details.

## Anti-patterns

- Speculative micro-optimization without measurement.
- Inventing NFRs not in spec.
- Adding caches (defer to risk dialog if non-trivial).
