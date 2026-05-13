---
name: mycl-asama04-spec
description: MyCL Aşama 4 — Spec Yazımı + Onay. 15+ yıl kıdemli mühendis kalitesinde 📋 Spec bloğu (Objective/MUST/SHOULD/AC/Edge/Technical/OOS). 3-5 cümle özet + askq onay. Çıktı `asama-4-complete + asama-4-ac-count`. spec_approved=True flag pre_tool spec lock'ını açar.
---

# Aşama 4 — Spec Yazımı + Onay

## Amaç

Onaylı niyeti **görünür İngilizce mühendislik spec'ine** dönüştür.
Sonraki tüm fazların tek gerçek kaynağı bu spec.

## 📋 Spec bloğu — zorunlu bölümler

```
📋 Spec — <one-line title>:

## Objective
<1-2 paragraph what + why>

## MUST
- MUST_1: <atomic requirement>
- MUST_2: <atomic requirement>

## SHOULD
- SHOULD_1: <nice-to-have>

## Acceptance Criteria
- Given X, When Y, Then Z (covers MUST_1)
- Given A, When B, Then C (covers MUST_2)

## Edge Cases
- <input boundary, null, overflow, race>

## Technical Approach
- <chosen stack, key decisions, why>

## Out of Scope
- <explicitly excluded>
```

## Koşullu bölümler (tetiklenirse)

| Tetikleyici | Bölüm |
|---|---|
| Aşama 2 boyut 6 GATE | Non-functional Requirements (latency, throughput) |
| Aşama 2 boyut 2 SKIP-MARK | Failure Modes (retry, circuit breaker) |
| Aşama 2 boyut 5 GATE | Observability (log, metric, trace) |
| Production deploy | Reversibility / Rollback |
| External API/service | Data Contract |

## Spec sonrası

Geliştirici diliyle **3-5 cümle** özet:
- "Bu spec X için Y yapıyor. AC: Z. Risk: W."

Teknik sorun varsa ⚠️ tek satır uyarı:
- ⚠️ "Bu yaklaşımda race condition riski var; locking gerekecek."
- ⚠️ "N+1 query ihtimali; eager loading düşün."
- ⚠️ "Auth eksik; Aşama 2'de SKIP-MARK; onay bekliyor."

AskUserQuestion ile onay iste.

## AskUserQuestion prefix

```
MyCL <version> | Aşama 4 — Spec onayı
MyCL <version> | Phase 4 — Spec approval
```

## Onay sonrası (hook eylemi)

Stop hook:
1. Son assistant text'inden Spec block tespit (line-anchored regex)
2. SHA256 hash → state.spec_hash
3. MUST_N + SHOULD_N → state.spec_must_list
4. askq.classify → "approve" → state.spec_approved=True
5. Audit chain auto-fill: `asama-1-complete`, `asama-2-complete`,
   `asama-3-complete`, `asama-4-complete`
6. Universal loop → state.current_phase=5

**spec_approved=True** flag pre_tool.py spec-approval block'ını açar;
artık Write/Edit/Bash mutating izinli (Layer B faza göre).

## İzinli tool'lar (Layer B)

`AskUserQuestion` + global readonly. Write/Edit/Bash Aşama 4'te yasak —
spec onayı önce.

## Çıktı (audit)

> **Model:** Bu aşama özeldir — askq onayı + spec_hash mevcudiyeti tetikler. Model `asama-4-complete` cevap metninde zikretmez; askq classify "approve" sonrası hook chain auto-fill (1, 2, 3, 4) yapar.
> **Hook:** `asama-4-complete` ve `asama-4-ac-count` (chain auto-fill ile) — `_spec_approve_flow` yazar.
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-4-complete
asama-4-ac-count must=N should=M
```

## Disiplin gerekleri

- `self_critique_required: true` — emit öncesi "spec eksik bölümü
  var mı?" self-check
- `public_commitment_required: true` — faz başında "bu fazda yapacağım
  3 şey: spec yaz, ⚠️ uyarıları çıkar, askq onay"
- `spec_block_required: true` — Spec block olmadan complete edilmez
- **Hook enforcement (1.0.42 — soft, 1.0.19'dan devralma):**
  `pre_tool.py` AskUserQuestion + cp==4 öncesi son assistant text'te
  `📋 Spec —` (veya `📋 Spec:`) bloğu arar. Marker yoksa askq
  **ALLOW edilir** ama `spec-format-missing` audit yazılır
  (visibility). Güvenlik kayıp YOK: spec marker yoksa
  `_spec_approve_flow` zaten spec_approved=True yapmaz → Aşama 5+'da
  Bash/Write `spec_lock` deny zinciri ikincil savunma olarak devrede.

  1.0.19'da DENY semantiğiyle eklenmişti ama transcript timing
  false-positive üretti: model spec'i markerla yazıp askq açtı,
  PreToolUse fire'da aynı turn'ün text content'i transcript snapshot'ta
  görünmedi (tool_use bloğu text'ten önce stream'lendi) → false-
  positive deny → gereksiz retry (canlı kullanıcı raporu). 1.0.42'de
  Aşama 1 (1.0.38) ile simetrik soft guidance; CLAUDE.md "soft
  guidance over fail-fast" kuralı.

## Anti-pattern

- ❌ Spec block olmadan onay isteme — `spec_block_required` kontrol
- ❌ Onay sonrası spec'i değiştirme — yeni hash → spec_approved sıfırlanır
- ❌ "Bu kadar yeterli, AC yazmasam olur" — Aşama 9 TDD AC'ler üzerinden
  yürür
- ❌ Türkçe spec — pseudocode kuralı: spec body İngilizce; özet
  kullanıcı dilinde
- ❌ **Özel başlık** — `Teknik Spec — X`, `Engineering Spec`,
  `## Spec for X`, `Final Spec:` gibi özel formlar yasak. Spec başlığı
  **tam olarak** şu şablonu kullanır:

  ```
  📋 Spec — <one-line title>:
  ```

  Başlık başında `📋` emoji + boşluk + `Spec` kelimesi + ` — `
  + tek satır başlık + `:`. `spec_detect.contains` regex'i
  (`^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?(?:\U0001F4CB[ \t]+)?Spec\b[^\n:]*:`)
  bu format'ı yakalar; `Teknik Spec — ...` başında `Teknik` kelimesi
  olduğu için **matchlemez** → `spec_hash=null` → `_spec_approve_flow`
  no-op → `spec_approved=False` → Bash deny zinciri. Format şablona
  birebir uy.

---

# Phase 4 — Spec Writing + Approval

## Goal

Convert approved intent into a visible English engineering spec —
the single source of truth for all subsequent phases.

## 📋 Spec block — required sections

`Objective`, `MUST` (atomic requirements), `SHOULD`, `Acceptance
Criteria` (Given/When/Then, covering each MUST), `Edge Cases`,
`Technical Approach`, `Out of Scope`.

## Conditional sections

NFRs (latency/throughput) when Phase-2 dim 6 gated; Failure Modes
when dim 2 SKIP-MARK; Observability when dim 5 gated; Reversibility
for prod deploys; Data Contract for external APIs.

## After spec

3-5 sentence summary in user's language. ⚠️ one-line warning if a
technical issue is detected (race condition, N+1, missing auth).
Then AskUserQuestion approval.

## AskUserQuestion prefix

`MyCL <version> | Phase 4 — Spec approval`

## Hook action on approval

Stop hook detects line-anchored Spec block, computes SHA256, extracts
MUST_N/SHOULD_N, classifies askq → approve, sets `spec_approved=True`,
auto-fills audit chain (Phases 1-4), advances state.current_phase to 5.

## Audit output

> **Model:** Special — askq approval + spec_hash trigger hook chain auto-fill (Phases 1-4). Model does not mention `asama-4-complete` in reply.
> **Hook:** `_spec_approve_flow` writes `asama-4-complete` and `asama-4-ac-count`.
> **Details:** see "Audit emission channel" contract in main skill.

`asama-4-complete` + `asama-4-ac-count must=N should=M`.

## Discipline requirements

self_critique_required, public_commitment_required, spec_block_required
— all true. **Hook enforcement (1.0.42 — soft, 1.0.19 inherited):** pre_tool.py runs a PreToolUse
soft check before AskUserQuestion at cp==4 — if the last assistant
text exists but does not contain a line-anchored `📋 Spec —` block,
the askq is **still ALLOWED** and a `spec-format-missing` audit is
written (visibility). Security is preserved because without the
marker `_spec_approve_flow` cannot set `spec_approved=True`
(spec_hash stays null), so the Bash/Write `spec_lock` deny chain is
the second line of defense. 1.0.19 used DENY semantics but produced
transcript-timing false-positives (live user report); 1.0.42 mirrors
the Phase 1 soft pattern (1.0.38) per CLAUDE.md "soft guidance over
fail-fast".

## Anti-patterns

- Approval request without a spec block.
- Mutating spec after approval (resets hash → spec_approved=False).
- Skipping AC (Phase 9 TDD walks through ACs).
- Turkish spec body (English required; summary in user's language).
