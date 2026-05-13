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

> **Model:** `asama-11-complete` (rescan count=0 olduktan sonra) cevap metninde düz yazıyla.
> **Hook:** `asama-11-scan`, `asama-11-issue-N-fixed`, `asama-11-rescan` (tarayıcı/fixer döngüsünde hook yazar) + `asama-11-escalation-needed` (max 5 rescan aşılırsa).
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

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

### Hook enforcement (1.0.26)

Hook, asistan metninde dört text-trigger'ı line-anchored regex ile
yakalar (Aşama 11, 12, 13 ortak — Aşama 14 subagent kanalıyla geldiği
için scope dışı):

- `asama-11-scan count=K` → audit emit
- `asama-11-issue-M-fixed` → audit emit (her issue ayrı kayıt)
- `asama-11-rescan count=K` → audit emit
- `asama-11-escalation-needed` → audit emit

**Hook auto-emit YAPMAZ**: `asama-11-complete` ve
`asama-11-escalation-needed` audit'lerini **model** kendi cevabında
yazar; hook sadece yakalar. STRICT mode bypass ödülünü önlemek için
"5 rescan aşıldı, hook escalation auto-yazar" davranışı eklenmedi.

Tüm trigger'lar idempotent — aynı transcript yeniden taranınca
duplicate audit yazılmaz.

### İkinci açı: `/code-review` plugin (opsiyonel, Plugin Kural B)

Anthropic'in `code-review` curated plugin'ini paralel ikinci açı olarak
kullanmak istersen `/code-review` slash command'ını çağır. MyCL Aşama
11 zaten auto-fix döngüsünü çalıştırır; plugin çıktısı ek-açı sağlar
ama zorunlu değil. Bulgular Aşama 10 risk dialogu'na taşınırsa (skill
kontratı) provenance + her iki gerekçe AskUserQuestion ile yüzeye
çıkar.

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

> **Model:** `asama-11-complete` (after rescan count=0) plain text in reply.
> **Hook:** `asama-11-scan`, `asama-11-issue-N-fixed`, `asama-11-rescan` (scanner/fixer cycle) + `asama-11-escalation-needed` (over max 5 rescans).
> **Details:** see "Audit emission channel" contract in main skill.

`asama-11-scan count=K` → `asama-11-issue-N-fixed` per fix →
`asama-11-rescan count=K2` → ... → `asama-11-rescan count=0` →
`asama-11-complete`. Max 5 rescans before
`asama-11-escalation-needed`.

### Hook enforcement (1.0.26)

Hook scans assistant text for four text-triggers via line-anchored
regex (shared by Phases 11, 12, 13 — Phase 14 uses the subagent
channel and is out of scope to avoid double-emit):

- `asama-11-scan count=K` → audit
- `asama-11-issue-M-fixed` → audit (one per issue)
- `asama-11-rescan count=K` → audit
- `asama-11-escalation-needed` → audit

**Hook does NOT auto-emit** `asama-11-complete` or
`asama-11-escalation-needed`; the **model** writes them in its reply,
the hook only captures. The defensive "auto-emit escalation after 5
rescans" behavior is deliberately omitted to prevent STRICT-mode
bypass-as-reward.

All triggers are idempotent — rescanning the same transcript does not
duplicate audits.

## Anti-patterns

- Limiting scope to spec files only.
- Manual-fix notes instead of auto-fix.
- Skipping post-fix rescan.
