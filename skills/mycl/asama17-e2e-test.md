---
name: mycl-asama17-e2e-test
description: MyCL Aşama 17 — E2E Testler (Test Pipeline 3/4). UI varsa Playwright/Cypress headless ile gerçek kullanıcı akışları. Aşama 6 atlandıysa atlanır. Çıktı asama-17-end-green | asama-17-not-applicable reason=no-ui.
---

# Aşama 17 — E2E Testler (Test Pipeline 3/4)

## Amaç

Gerçek **kullanıcı akışlarını** uçtan uca doğrula — UI tıklamadan
backend'e kadar tam zincir.

## Tercih edilen araçlar

| Stack | Tool |
|---|---|
| Web (React/Vue/Svelte/Next) | Playwright (önerilen), Cypress |
| Mobile | Detox (RN), Maestro (RN/Flutter) |
| Desktop | Playwright (Electron), WinAppDriver |

**Headless mode** zorunlu (CI'de + lokal geliştirme). Screenshot
artifacts başarısız test için.

## Aşama 17 mercek

Spec'teki **happy path** + **kritik error path**'ler:

```
Happy path:
  1. login
  2. todo ekle (UI)
  3. liste güncellendi (UI verify)
  4. logout

Kritik error path:
  1. login (yanlış şifre)
  2. error message göründü
  3. login button hâlâ enabled
```

## Pipeline (4-step)

1. **Eksik tespit** → spec AC'den E2E senaryoları çıkar
2. **Test setup** → Playwright config, baseURL, dev server health
   check
3. **Test yaz** → page object pattern (DRY)
4. **Çalıştır headless** → tam suite YEŞİL

## Atlama

UI yok (Aşama 6 skipped) → otomatik atla:
```
asama-17-not-applicable reason=no-ui
```

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Çıktı (audit)

> **Model:** `asama-17-not-applicable reason=no-ui` (UI yoksa) cevap metninde düz yazıyla.
> **Hook:** `asama-17-scan`, `asama-17-test-N-added`, `asama-17-end-green` (Playwright headless YEŞİL post_tool sinyaliyle hook yazar).
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-17-scan count=K
asama-17-test-N-added
asama-17-end-green
asama-17-not-applicable reason=no-ui
```

### Hook enforcement (1.0.28)

Hook, Aşama 15 ile aynı generic text-trigger setini kullanır
(`asama-17-scan / test-M-added`). `end-green` ve `not-applicable` 1.0.21
extended trigger'da yakalanır. Detay: Aşama 15 skill "Hook enforcement
(1.0.28)" bölümü.

## Anti-pattern

- ❌ Headed mode CI'de (display server gerekir, flaky)
- ❌ Hard-coded sleep (5s) — Playwright auto-wait kullan (`expect`
  matchers, `waitFor` helpers)
- ❌ Test interdependency (test A'dan kalan state test B'yi etkiler)

---

# Phase 17 — E2E Tests (Test Pipeline 3/4)

## Goal

Validate full user flows — click to backend, end-to-end.

## Tools

Web: Playwright (preferred), Cypress. Mobile: Detox, Maestro.
Desktop: Playwright (Electron). **Headless required** (CI + local).

## Lenses

Happy paths + critical error paths from spec ACs (login, action,
verify result, error feedback).

## Pipeline

Detect missing → set up (Playwright config, baseURL, health check) →
write tests (page object pattern) → run headless until GREEN.

## Skip

`asama-17-not-applicable reason=no-ui` when Phase 6 was skipped.

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Audit output

> **Model:** `asama-17-not-applicable reason=no-ui` (when no UI) plain text in reply.
> **Hook:** `asama-17-scan`, `asama-17-test-N-added`, `asama-17-end-green` (hook writes on Playwright headless green via post_tool).
> **Details:** see "Audit emission channel" contract in main skill.

`asama-17-scan count=K` → `asama-17-test-N-added` →
`asama-17-end-green` | `asama-17-not-applicable reason=no-ui`.

## Anti-patterns

- Headed mode in CI (display server flake).
- Hard-coded sleeps (use Playwright auto-wait).
- Test interdependency (state leakage between tests).
