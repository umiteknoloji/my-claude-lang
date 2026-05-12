---
name: mycl-asama06-ui-yapim
description: MyCL Aşama 6 — UI Yapımı. Frontend dosyalarını sahte verilerle yaz; gerçek API/DB bağlanmaz. Build config önce, sonra dev server + tarayıcı otomatik açar. denied_paths backend yollarını kapatır. UI yoksa atlanır. Çıktı asama-6-complete | asama-6-skipped | asama-6-end (server+browser sertifikası).
---

# Aşama 6 — UI Yapımı

## Amaç

Kullanıcı arayüzünü **gerçek API/DB bağlanmadan**, sahte verilerle
hayata geçir. Geliştirici **hemen tarayıcıda görsün**, onay vermeden
backend yazılmasın.

## Ne yapılır

1. **Build config önce:** `vite.config.*`, `next.config.*`,
   `nuxt.config.*`, `tailwind.config.*`, `tsconfig.json` (stack'e göre)
2. **UI dosyaları:** React/Vue/Svelte/static HTML — sahte data /
   fixture kullan
3. **Gerçek API çağrısı YOK** — `fetch('/api/...')` yerine inline
   mock array
4. **`npm install`** — bağımlılıkları kur
5. **`npm run dev` arka planda çalıştır** (background process)
6. **2 saniye bekle**, sonra tarayıcı OTOMATİK aç:
   - macOS: `open http://localhost:5173`
   - Linux: `xdg-open ...`
   - Windows: `start ...`

## denied_paths (Layer B)

```
src/api/**
src/server/**
server/**
prisma/**
models/**
migrations/**
schema/**
db/**
```

Bu yollara Write/Edit denenirse pre_tool DENY → `phase-allowlist-path`
audit. Backend Aşama 8 (DB) veya Aşama 9 (TDD)'de yazılır.

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

**`Task` ve `Agent` (subagent dispatch) bu fazda YASAK** (Aşama 1/3/5
pattern'i, 1.0.21). Frontend yazımı + npm install/dev + browser auto-
open ana bağlamda yürür; subagent dispatch gereksiz, bağlam zaten
mevcut. Subagent sadece Aşama 10/14 paralel mercek için.

## Çıktı (3 seçenek)

> **Model:** Üç audit'ten birini cevap metnine düz yazıyla emit eder:
> 1. `asama-6-complete` — UI hazır (basit complete)
> 2. `asama-6-skipped reason=no-ui-flow` — proje UI içermez (CLI/lib/backend-only)
> 3. `asama-6-end server_started=true browser_opened=true` — KATI mod sertifikası (tercih edilen)
>
> **Hook (1.0.21):** Generic extended trigger regex `asama-(\d+)-(end|skipped|...)`
> bu emit'leri yakalar + audit emit eder. `asama-6-end` parametrelerinde
> `browser_opened=false` varsa hook `asama-6-no-browser-warn` soft audit
> ekler (görünür sinyal, hard deny değil). Model `server_started`/
> `browser_opened` doğru emit etmek zorunda — hook doğrulamaz; pseudocode
> KATI mod model'in sorumluluğu.
>
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

| Audit | Anlam |
|---|---|
| `asama-6-complete` | UI hazır (manuel emit) |
| `asama-6-skipped reason=no-ui-flow` | Proje UI içermiyor (CLI, lib, backend-only) |
| `asama-6-end server_started=true browser_opened=true` | Sunucu + tarayıcı doğrulandı (STRICT mode sertifikası) |

`asama-6-end` tercih edilen çıktı — server_started + browser_opened
sertifikası kullanıcının gerçekten görsel kontrol yapabildiğinin
kanıtı.

## post_tool reaktif yan etki

UI dosyası yazıldığında (Aşama 6 + .tsx/.jsx/.vue/.svelte veya
src/components|pages|app|views/**):
- `state.ui_flow_active = True`
- Aşama 7 (UI İncelemesi) deferred mode aktif

## Atlama

Proje UI içermiyorsa (CLI, kütüphane, backend-only):
```
asama-6-skipped reason=no-ui-flow
```

## Anti-pattern

- ❌ Backend dosyası yazma (denied_paths) — pre_tool DENY
- ❌ Gerçek API/DB çağrısı (fetch, axios live endpoint) — fake data ile
- ❌ `npm run dev` çalıştırmadan complete emit — server_started=false
- ❌ Tarayıcı açmadan complete emit — browser_opened=false; geliştirici
  manuel açma zorunda kalır

---

# Phase 6 — UI Build

## Goal

Implement the UI with **mock data**, no real API/DB. Developer sees
it in the browser **before** any backend is written.

## Action

1. Build config first (vite/next/nuxt/tailwind/tsconfig).
2. UI files (React/Vue/Svelte/static HTML) with mock data.
3. **No real API calls** — inline mock arrays only.
4. `npm install` + background `npm run dev`.
5. Wait 2s, auto-open browser (`open` / `xdg-open` / `start`).

## denied_paths

`src/api/**`, `src/server/**`, `server/**`, `prisma/**`, `models/**`,
`migrations/**`, `schema/**`, `db/**` — pre_tool DENY with
`phase-allowlist-path` audit.

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Audit output (one of three)

> **Model:** `asama-6-complete` or `asama-6-skipped reason=no-ui-flow` plain text in reply.
> **Hook:** `asama-6-end server_started=... browser_opened=...` (server+browser certificate — hook writes after verification).
> **Details:** see "Audit emission channel" contract in main skill.

- `asama-6-complete` (manual emit)
- `asama-6-skipped reason=no-ui-flow` (no UI in project)
- `asama-6-end server_started=true browser_opened=true` (preferred —
  STRICT certificate)

## post_tool reactive effect

UI file write in Phase 6 → `state.ui_flow_active = True` for Phase 7
deferred mode.

## Anti-patterns

- Writing into denied backend paths.
- Real API/DB calls instead of mocks.
- `asama-6-complete` emit without dev server / browser.
