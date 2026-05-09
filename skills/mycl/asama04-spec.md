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
- `subagent_rubber_duck: true` — kritik faz; haiku subagent ile
  ikinci-göz pair-check

## Anti-pattern

- ❌ Spec block olmadan onay isteme — `spec_block_required` kontrol
- ❌ Onay sonrası spec'i değiştirme — yeni hash → spec_approved sıfırlanır
- ❌ "Bu kadar yeterli, AC yazmasam olur" — Aşama 9 TDD AC'ler üzerinden
  yürür
- ❌ Türkçe spec — pseudocode kuralı: spec body İngilizce; özet
  kullanıcı dilinde

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

`asama-4-complete` + `asama-4-ac-count must=N should=M`.

## Discipline requirements

self_critique_required, public_commitment_required, spec_block_required,
subagent_rubber_duck — all true.

## Anti-patterns

- Approval request without a spec block.
- Mutating spec after approval (resets hash → spec_approved=False).
- Skipping AC (Phase 9 TDD walks through ACs).
- Turkish spec body (English required; summary in user's language).
