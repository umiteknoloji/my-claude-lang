---
name: mycl-asama11-kod-inceleme
description: MyCL Aşama 11 — Kod İncelemesi (Kalite Pipeline 1/4). Doğruluk, mantık hataları, hata yakalama eksikliği, ölü kod, eksik validasyon, yanlış adlandırma. Otomatik tara → düzelt → yeniden tara, K=0 olana kadar (max 5). askq YOK. Çıktı asama-11-scan + asama-11-rescan count=0.
---

# Aşama 11 — Kod İncelemesi (Kalite Pipeline 1/4)

## Amaç

**Yeni veya değişen** dosyalarda doğruluk + mantık + hata yakalama
sorunlarını otomatik bulup düzelt.

## Pipeline pattern (Aşama 11-14 ortak)

Her kalite fazı aynı **3-step döngü**:

1. **Tara** → faza özgü açıdan dosyaları gözden geçir, sorunları **say (K)**
2. **Düzelt** → her soruna **otomatik fix uygula** (askq YOK, dialog YOK)
3. **Yeniden tara** → yeni durum, **K=0 olana kadar tekrar** (max 5)

## Aşama 11 mercek

| Sorun | Örnek |
|---|---|
| Doğruluk | Off-by-one, yanlış operatör (=, ==), ters condition |
| Mantık hataları | Eksik branch, unreachable code, çelişen if/else |
| Hata yakalama | try/catch eksik, swallowed exception, log+rethrow yok |
| Ölü kod | Kullanılmayan import, unreferenced function, commented-out |
| Eksik validasyon | Input boundary, null check, type narrowing eksik |
| Yanlış adlandırma | Misleading name, abbreviation, naming convention ihlali |

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

**askq YOK** kuralı: Bu fazda kullanıcıya sorulmaz; auto-fix uygulanır.
AskUserQuestion sadece kritik karar gerektiren senaryolar için (örn.
silme + revert için onay) — pratikte kalite pipeline'da askq açma.

## Çıktı (audit)

```
asama-11-scan count=K1
asama-11-issue-1-fixed
asama-11-issue-2-fixed
...
asama-11-rescan count=K2
asama-11-issue-... (yeni iterasyon)
asama-11-rescan count=0   # bitiş
asama-11-complete
```

K=0 olana kadar **max 5 rescan**. Aşılırsa `asama-11-escalation-needed`
audit (geliştirici müdahalesi).

## Anti-pattern

- ❌ "Sadece spec dosyalarına bak" — Aşama 11 **yeni veya değişen
  TÜM** dosyalara bakar (post_tool last_write_ts ile tespit edilen)
- ❌ Auto-fix yerine "manuel bakacağım" notu — pipeline auto-fix'i
  zorunlu kılar
- ❌ Fix sonrası rescan atlama — yeni issue oluşmuş olabilir

---

# Phase 11 — Code Review (Quality Pipeline 1/4)

## Goal

Auto-detect + auto-fix correctness / logic / error-handling / dead-
code / validation / naming issues in new or changed files.

## Pipeline pattern (shared by Phases 11-14)

3-step loop: **Scan** (count K issues) → **Fix** (auto, no askq) →
**Rescan** until K=0 (max 5 iterations).

## Phase 11 lens

Correctness, logic errors, missing error handling, dead code, missing
validation, misleading naming.

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.
**No askq** in quality pipeline; auto-fix only.

## Audit output

`asama-11-scan count=K` → `asama-11-issue-N-fixed` per fix →
`asama-11-rescan count=K2` → ... → `asama-11-rescan count=0` →
`asama-11-complete`. Max 5 rescans before
`asama-11-escalation-needed`.

## Anti-patterns

- Limiting scope to spec files only.
- Manual-fix notes instead of auto-fix.
- Skipping post-fix rescan.
