---
name: mycl-asama15-birim-test
description: MyCL Aşama 15 — Birim Testler (Test Pipeline 1/4). Her yeni fonksiyon/sınıf/modül için unit test. Aşama 9 TDD testlerini doğrular. Test takımı YEŞİL olana kadar sürer. Çıktı asama-15-end-green | asama-15-not-applicable.
---

# Aşama 15 — Birim Testler (Test Pipeline 1/4)

## Amaç

Aşama 9 TDD'de **AC bazlı** testler yazıldı. Aşama 15 **kod kapsama**
testleri ekliyor: her **yeni veya değişen** fonksiyon/sınıf/modül için
izole birim test.

## Pipeline pattern (Aşama 15-18 ortak)

Her test fazı:
1. **Eksik tespit** → kapsanmamış kod yolu + branch + edge case
2. **Test yaz** → ilgili dosya yanına / `tests/` ağacına
3. **Çalıştır** → tam takım YEŞİL olana kadar
4. **Atlama** → kapsamda değilse `asama-N-not-applicable` (sessiz
   atlama YASAK; audit emit zorunlu)

## Aşama 15 mercek

| Eksik | Test |
|---|---|
| Function `parseInput()` | Happy path, null, empty, malformed |
| Class `OrderService` | Constructor, her public method, error case |
| Module utility | Pure function input/output table |
| Aşama 9 test'leri | Coverage tool ile gap analiz |

## Coverage hedefi

Kesin sayı yok (Goodhart riski) — kritik paths %100, getter/setter %0
kabul. Spec MUST'larına bağlı kod path'leri **mutlaka kapsanır**.

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Çıktı (audit)

> **Model:** `asama-15-not-applicable reason=...` (Aşama 15 kapsam dışıysa) cevap metninde düz yazıyla.
> **Hook:** `asama-15-scan`, `asama-15-test-N-added`, `asama-15-end-green` (tam suite YEŞİL post_tool sinyaliyle hook yazar).
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-15-scan count=K (eksik test sayısı)
asama-15-test-N-added
asama-15-end-green (tam suite YEŞİL)
asama-15-not-applicable reason=<sebep>
```

### Hook enforcement (1.0.28)

Hook, asistan metninde aşağıdaki text-trigger'ları line-anchored regex
ile yakalar (Aşama 15-18 ortak):

- `asama-15-scan count=K` → audit emit
- `asama-15-test-M-added` → audit emit (her test ayrı kayıt; Aşama
  15-17 için; Aşama 18 bunun yerine `asama-18-scenario-M-passed`
  kullanır)
- Aşama 18'e özel: `asama-18-scenario-M-passed` + `asama-18-target-missed`
- `end-green`, `end-target-met`, `not-applicable`, `skipped` zaten
  1.0.21 extended trigger'da yakalanıyor — Aşama 15-18 bitiş sinyalleri
  burayı kullanır

**Hook auto-emit YOK** — `asama-15-complete`, `not-applicable`,
`end-green` audit'lerini **model** kendi cevabında yazar; hook sadece
yakalar. 1.0.26 Quality Pipeline sözleşmesiyle simetrik.

Tüm trigger'lar idempotent.

## Anti-pattern

- ❌ Coverage % hedefini "100" gibi mutlak yap → trivial getter
  testleri yazılır, gerçek bug'lar gözden kaçar
- ❌ Aşama 9 TDD test'leri zaten unit test → yeni unit test gerek
  yok varsayımı (Aşama 9 AC bazlı, Aşama 15 kod-kapsama)
- ❌ Test atlama "yeterince test var" → audit emit zorunlu

---

# Phase 15 — Unit Tests (Test Pipeline 1/4)

## Goal

Add **code-coverage** unit tests for new/changed
functions/classes/modules; complement Phase 9's AC-based tests.

## Pipeline pattern (Phases 15-18)

1. Detect missing coverage (paths, branches, edge cases).
2. Write tests next to file or in `tests/`.
3. Run full suite until GREEN.
4. Skip with `asama-N-not-applicable reason=<reason>` (silent skip
   FORBIDDEN).

## Phase 15 lens

Pure functions (input/output table), classes (each public method +
error case), modules (utility functions). MUST-bound paths must be
covered.

## Coverage target

No fixed % (Goodhart risk) — critical paths 100%, getter/setter 0% OK.

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Audit output

> **Model:** `asama-15-not-applicable reason=...` (when out of scope) plain text in reply.
> **Hook:** `asama-15-scan`, `asama-15-test-N-added`, `asama-15-end-green` (hook writes on full-suite green via post_tool).
> **Details:** see "Audit emission channel" contract in main skill.

`asama-15-scan count=K` → `asama-15-test-N-added` →
`asama-15-end-green` | `asama-15-not-applicable`.

### Hook enforcement (1.0.28)

Hook scans assistant text for the following text-triggers via
line-anchored regex (shared by Phases 15-18):

- `asama-15-scan count=K` → audit
- `asama-15-test-M-added` → audit (one per test; Phases 15-17 only;
  Phase 18 uses `asama-18-scenario-M-passed` instead)
- Phase 18 only: `asama-18-scenario-M-passed` and
  `asama-18-target-missed`
- `end-green`, `end-target-met`, `not-applicable`, `skipped` are
  already captured by the 1.0.21 extended trigger — Phases 15-18 end
  signals use that channel

**Hook does NOT auto-emit** `asama-15-complete`, `not-applicable`, or
`end-green`; the **model** writes them in its reply, the hook only
captures. Symmetric with the 1.0.26 Quality Pipeline contract.

All triggers are idempotent.

## Anti-patterns

- Absolute coverage % targets (trivial-test farms).
- Conflating Phase 9 (AC-based) with Phase 15 (code coverage).
- Silent skip without audit.
