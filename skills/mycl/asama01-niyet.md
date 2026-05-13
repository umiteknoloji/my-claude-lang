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
   - Tek bir özet hazırla (~3-5 cümle) — assistant cevabına **düz metin
     olarak** yaz, başlık satırı `🎯 Niyet özeti:` (emoji opsiyonel —
     `Niyet özeti:` de geçerli)
   - Özet **AskUserQuestion prompt'una gömülmez** — askq prompt'una
     "onaylıyor musun?" yaz, özet ayrı assistant text'te kal
   - AskUserQuestion ile onay iste

3. **Çelişki tespit et:** Niyette mantıksal çatışma varsa yüzeye çıkar
   ve hangisini kastettiğini sor. Örnek kategoriler (exhaustive değil):
   - **State modeli:** "JWT auth + server-side session state" → ikisi
     bir arada olmaz; stateless mi stateful mi tek seçilmeli
   - **Zaman modeli:** "Real-time + cron-based" → push mu pull mu
     tek seçilmeli
   - **Veri tutarlılığı:** "PostgreSQL + denormalized JSON" →
     ilişkisel mi NoSQL mi, tasarım kararı netleşsin

   Bu kategoriler ipucu — yeni çelişki türü görürsen onu da yüzeye
   çıkar (deployment modeli, ölçek beklentisi, güvenlik modeli, vb.).

## AskUserQuestion prefix

```
MyCL <version> | Aşama 1 — Niyet özeti onayı
MyCL <version> | Phase 1 — Intent summary confirmation
```

### Hook enforcement (1.0.37)

`pre_tool.py` Aşama 1'de AskUserQuestion çağrısı yapılırken son
assistant text'te `🎯 Niyet özeti:` (veya `Niyet özeti:` / `Intent
summary:`) line-anchored marker'ı arar (`spec_detect.contains_
intent_summary`). Yoksa askq DENY edilir + `intent-summary-format-
missing` audit yazılır. Aşama 4 spec format guard'ı (1.0.19) ile
simetrik. Marker olmayan özet, prose içinde gömülürse hook detection
yapamaz; CLAUDE.md captured rule "line-anchored regex".

## İzinli tool'lar (Layer B)

`AskUserQuestion` (gate_spec.json'a göre). Read/Glob/Grep/LS global
allowlist'te — niyet doğrulamak için codebase okuyabilirsin.

`Write/Edit/Bash` Aşama 1'de **yasak** — kod yazımı Aşama 4 spec onayı
sonrası başlar.

`Task` (subagent dispatch) Aşama 1'de **yasak** (1.0.16 — over-engineering
temizliği). Niyet toplama küçük scope; ana bağlamda Skill + AskUserQuestion
yeterli. Bağlam şişmez. Subagent dispatch sadece Aşama 10/14 paralel
mercek için ayrılmış.

## Çıktı (audit)

Aşama 1 tamamlandığında cevap metninde **düz yazıyla** zikret:

```
asama-1-complete
```

Stop hook transcript'i okur, sıralı eşleşmeyi (N == current_phase)
doğrular, `.mycl/audit.log`'a yazar ve `current_phase`'i 2'ye
ilerletir. Atlama denemesi (`asama-9-complete` vb.) reddedilir +
`phase-skip-attempt` audit'lenir. Sen `Write`/`Bash` çağırma —
gereksiz; pre_tool zaten bloklar. Tam mekanizma: ana skill "Audit
emission kanalı" sözleşmesi.

## Anti-pattern

- ❌ "Niyet anladım, kod yazmaya başlıyorum" — Aşama 4 onayı yok.
- ❌ Tek turda 5 soru — kullanıcı bunalır, cevap kalitesi düşer.
- ❌ Belirsizliği "varsayım yapayım" ile geçiştir — Aşama 2 hassasiyet
  denetiminin görevi; Aşama 1'de net soru sor.
- ❌ AskUserQuestion açmadan "evet onaylıyorsan devam edeyim" — askq
  hook için zorunlu (intent classifier sonrası `spec_approved` flag).

## Recovery (yalnızca geliştirici müdahalesi)

**Model için değildir** — bu komutu sen çalıştırma. Hook arızası
şüphesi varsa geliştirici yerel terminalden manuel emit eder:

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
   approval.** The summary is plain assistant text headed by
   `🎯 Intent summary:` (emoji optional — `Intent summary:` also OK).
   It must NOT be embedded inside the askq prompt; the prompt asks
   "approve?", the summary lives in the reply text.
3. **Surface contradictions:** logical conflicts in the intent are
   raised explicitly (e.g., "JWT + server-side session state").

## AskUserQuestion prefix

`MyCL <version> | Phase 1 — Intent summary confirmation`

### Hook enforcement (1.0.37)

In Phase 1, `pre_tool.py` requires a line-anchored `🎯 Intent summary:`
(or `Intent summary:` / `Niyet özeti:`) marker in the last assistant
text before any AskUserQuestion call. If absent, the askq is DENIED
with `intent-summary-format-missing` audit. Symmetric with the Phase
4 spec format guard (1.0.19). Per CLAUDE.md captured rule, the regex
is MULTILINE + line-anchored — prose-embedded summaries don't count
because they break the hook's marker-based detection.

## Allowed tools (Layer B)

Only `AskUserQuestion` per phase; Read/Glob/Grep/LS globally allowed.
Write/Edit/Bash forbidden in Phase 1 — code writing starts after Phase
4 spec approval.

## Audit output

When Phase 1 is complete, mention this trigger word in your reply text
(plain words, no file write):

```
asama-1-complete
```

The Stop hook reads the transcript, verifies sequential match
(N == current_phase), appends to `.mycl/audit.log`, and advances
`current_phase` to 2. Skip attempts (e.g. `asama-9-complete`) are
rejected and audited as `phase-skip-attempt`. Don't call
`Write`/`Bash` — unnecessary; pre_tool blocks them anyway. Full
mechanism: see "Audit emission channel" contract in main skill.

## Anti-patterns

- Starting code after intent without Phase 4 approval.
- Asking 5 questions in one turn.
- Replacing precision with assumptions (Phase 2's job).
- Skipping AskUserQuestion ("if you agree, I'll continue").
