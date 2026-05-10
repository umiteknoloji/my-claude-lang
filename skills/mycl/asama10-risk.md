---
name: mycl-asama10-risk
description: MyCL Aşama 10 — Risk İncelemesi. Üç adım: spec uyum öncül + atlanmış risk taraması (4 mercek paralel) + TDD yeniden doğrulama. Her risk askq ile sunulur (Skip/Fix/Rule). Sınırsız soru — pipeline değer kazanır. Çıktı asama-10-items-declared + asama-10-item-N-resolved.
---

# Aşama 10 — Risk İncelemesi (sınırsız soru)

## Amaç

Kod yazıldıktan sonra **atlanmış riskleri yüzeye çıkar** — uç durumlar,
gerilemeler, güvenlik/performans/UX/eşzamanlılık boşlukları. Risk
askq'sı **sınırsız** — pipeline değer kazanır, kullanıcı zaman
yatırımı kabul eder.

## 3 adım

### 1. Spec uyum öncül kontrolü

- Spec'teki **her MUST/SHOULD** karşılandı mı? (state.spec_must_list
  üzerinden geç)
- Spec'in güvenlik / performans / observability kararları doğru
  uygulandı mı?
- Eksik MUST → risk olarak işaretle

### 2. Atlanmış risk taraması (4 mercek paralel)

| Mercek | Bakış |
|---|---|
| Code Review | Bug, mantık hatası, hata yakalama eksikliği, validasyon |
| Simplify | Erken soyutlama, duplikat, gereksiz pattern |
| Performance | Hot path, N+1, büyük O, gereksiz allocation |
| Security | Auth bypass, IDOR, SQL injection, XSS, secret leak |

**Semgrep SAST** HIGH/MEDIUM bulguları **otomatik uygulanır** (askq
sormadan); LOW seviyeli bulgu askq.

### 3. TDD yeniden doğrulama

Tüm risk düzeltmeleri sonrası **tam test takımı** çalıştırılır.
Regression varsa Aşama 9'a geri dön.

## Risk askq formatı

Her risk **tek tek** AskUserQuestion ile geliştiriciye sunulur:

```
MyCL <version> | Aşama 10 — Risk maddesi #1
```

Seçenekler (3):
- **Skip** → bu riski yok say (`asama-10-item-1-resolved decision=skip`)
- **Fix** → spesifik düzeltmeyi uygula (`decision=apply`)
- **Rule** → bunu kalıcı kural yap (Rule Capture; `decision=rule`)

**Rule Capture:** Geliştirici "bunu kural yap" derse, MyCL CLAUDE.md'de
veya proje config'inde kalıcı kural ekler ("captured rules" bloğu).
Sonraki sessionlerde aynı pattern bulunursa otomatik flag.

## Sınırsız soru

Aşama 10 (ve Aşama 19) zaman kısıtlı **değil**. Risk listesi 5 maddeyse
5 askq, 50 maddeyse 50 askq açılır. Pipeline değer kazanır; kullanıcı
buna zaman yatırımı kabul eder.

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Çıktı (audit)

> **Model:** `asama-10-complete` (tüm risk maddeleri çözüldükten sonra) cevap metninde düz yazıyla.
> **Hook:** `asama-10-items-declared count=K`, `asama-10-item-N-resolved decision=...` (her askq sonucu için hook + askq classifier yazar).
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-10-items-declared count=K
asama-10-item-1-resolved decision=apply  # veya skip/rule
asama-10-item-2-resolved decision=skip
...
asama-10-complete  # tüm K maddesi resolved
```

## Disiplin gerekleri

- `subagent_rubber_duck: true` — Aşama 10 kritik; haiku subagent ile
  ikinci-göz pair-check
- Mid-pipeline reconfirmation (#13) — risk listesi uzunsa "hâlâ bu
  yönde mi?" askq

## Anti-pattern

- ❌ "Risk yok" deyip count=0 emit — 4 mercek paralel taraması yapıldı
  mı kontrol; semgrep çalıştı mı?
- ❌ Risk askq'sını batch tek askq olarak açma — pseudocode "tek tek"
  diyor; tek askq'da 10 madde = kullanıcı bunalır
- ❌ Skip seçildi diye Rule Capture atlanma — "skip" kararı **gerekçesi**
  audit'e yazılır
- ❌ Tüm risk fix sonrası TDD yeniden doğrulamayı atlama — regression
  riski

---

# Phase 10 — Risk Review (unbounded questions)

## Goal

Surface missed risks after code is written: edge cases, regressions,
security/perf/UX/concurrency gaps. **Unbounded** — pipeline gains
value; user accepts the time cost.

## 3 steps

1. **Spec compliance** — every MUST/SHOULD met?
2. **Missed-risk scan (4 lenses parallel)**: Code Review, Simplify,
   Performance, Security. Semgrep SAST HIGH/MEDIUM auto-applied;
   LOW → askq.
3. **TDD revalidation** — full suite after fixes.

## Risk askq

Each risk presented one-by-one via AskUserQuestion:
`MyCL <version> | Phase 10 — Risk item #N`. Options: Skip / Fix / Rule
(Rule Capture writes a permanent rule).

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Audit output

> **Model:** `asama-10-complete` (after all risk items resolved) plain text in reply.
> **Hook:** `asama-10-items-declared count=K`, `asama-10-item-N-resolved decision=...` (askq classifier writes per item).
> **Details:** see "Audit emission channel" contract in main skill.

`asama-10-items-declared count=K` + `asama-10-item-N-resolved
decision=apply|skip|rule` per item + `asama-10-complete`.

## Discipline

`subagent_rubber_duck: true` (haiku pair-check). Mid-pipeline
reconfirmation when risk list is long.

## Anti-patterns

- Emit `count=0` without running 4-lens scan + semgrep.
- Batching all risks in one askq.
- Skipping Rule Capture for `skip` decisions (rationale required).
- Skipping TDD revalidation after fixes.
