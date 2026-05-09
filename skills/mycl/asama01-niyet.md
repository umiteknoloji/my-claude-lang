---
name: mycl-asama01-niyet
description: MyCL Aşama 1 — Niyet Toplama. Geliştiricinin ne istediğini netleştir; hiçbir belirsizlik kalmasın. Her turda tek soru, sırayla. Tüm değişkenler net olunca özet + AskUserQuestion onay. Aşama 1 çıktısı `summary-confirm-approve` audit'i.
---

# Aşama 1 — Niyet Toplama

## Amaç

Geliştiricinin ne istediğini netleştir. **Hiçbir belirsizlik kalmasın.**
Aşama 4 spec'i bu niyetten türetilecek; gri alan kalırsa spec yanlış
çıkar.

## Ne yapılır

1. **Belirsizlik varsa tek tek soru sor** — her turda **tek soru**
   (CLAUDE.md "one solid step per turn"). Cevap gelince sonrakini sor.

2. **Tüm değişkenler net ise:**
   - Tek bir özet hazırla (~3-5 cümle)
   - AskUserQuestion ile onay iste

3. **Çelişki tespit et:** Niyette mantıksal çatışma varsa yüzeye çıkar
   ve hangisini kastettiğini sor. Örnek:
   - "JWT auth + server-side session state" → ikisi tek seçilmeli
   - "Real-time + cron-based" → ikisi tek seçilmeli
   - "PostgreSQL + denormalized JSON" → tasarım kararı netleşsin

## AskUserQuestion prefix

```
MyCL <version> | Aşama 1 — Niyet özeti onayı
MyCL <version> | Phase 1 — Intent summary confirmation
```

## İzinli tool'lar (Layer B)

`AskUserQuestion` (gate_spec.json'a göre). Read/Glob/Grep/LS global
allowlist'te — niyet doğrulamak için codebase okuyabilirsin.

`Write/Edit/Bash` Aşama 1'de **yasak** — kod yazımı Aşama 4 spec onayı
sonrası başlar.

## Çıktı (audit)

```
summary-confirm-approve
asama-1-complete
```

İkisinden biri yazılınca Aşama 2'ye advance.

## Anti-pattern

- ❌ "Niyet anladım, kod yazmaya başlıyorum" — Aşama 4 onayı yok.
- ❌ Tek turda 5 soru — kullanıcı bunalır, cevap kalitesi düşer.
- ❌ Belirsizliği "varsayım yapayım" ile geçiştir — Aşama 2 hassasiyet
  denetiminin görevi; Aşama 1'de net soru sor.
- ❌ AskUserQuestion açmadan "evet onaylıyorsan devam edeyim" — askq
  hook için zorunlu (intent classifier sonrası `spec_approved` flag).

## Recovery

Manual emit (geliştirici müdahalesi):
```bash
python3 -c "from hooks.lib import audit; audit.log_event('summary-confirm-approve', 'recovery', 'manual')"
```

---

# Phase 1 — Intent Gathering

## Goal

Clarify what the developer wants. **No ambiguity.** Phase 4 spec is
derived from this intent; gray areas yield wrong specs.

## What to do

1. **One question per turn** — wait for answer before next.
2. **All variables clear → summary (3-5 sentences) + AskUserQuestion
   approval.**
3. **Surface contradictions:** logical conflicts in the intent are
   raised explicitly (e.g., "JWT + server-side session state").

## AskUserQuestion prefix

`MyCL <version> | Phase 1 — Intent summary confirmation`

## Allowed tools (Layer B)

Only `AskUserQuestion` per phase; Read/Glob/Grep/LS globally allowed.
Write/Edit/Bash forbidden in Phase 1 — code writing starts after Phase
4 spec approval.

## Audit output

`summary-confirm-approve` or `asama-1-complete` advances to Phase 2.

## Anti-patterns

- Starting code after intent without Phase 4 approval.
- Asking 5 questions in one turn.
- Replacing precision with assumptions (Phase 2's job).
- Skipping AskUserQuestion ("if you agree, I'll continue").
