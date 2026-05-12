---
name: mycl-asama22-tamlik
description: MyCL Aşama 22 — Tamlık Denetimi. HOOK kendi yazar (model değil). audit.log + state.json + trace.log üç dosyayı okuyup 1-21 fazlarının audit'lerini doğrular. Aşama 9 TDD ve Aşama 11-18 pipeline derin denetim. Atlanan/eksik fazlar "Açık Konular"'da yüzeye. Çıktı asama-22-complete.
---

# Aşama 22 — Tamlık Denetimi

## Amaç

Tüm pipeline'ın **gerçekten uçtan uca tamamlandığını** doğrula.
Atlanan adımları yüzeye çıkar.

## CRITICAL: Hook yazar, model yazmaz

`asama-22-complete` audit'i ve tamlık raporu **hook tarafından** üretilir
— model emit edemez. Bu kural pipeline'ın objektif kapanış sertifikası.

- Bash kanalından `audit_emit asama-22-complete` denenirse pre_tool
  DENY (`phase-transition-illegal-emit-attempt`)
- Stop hook universal completeness loop Aşama 22'de durur — manuel
  emit beklemez

## Üç dosya okur

```
.mycl/audit.log     # tüm phase audit'leri + decision'lar
.mycl/state.json    # spec_must_list, current_phase, ui_flow_active
.mycl/trace.log     # session_start, phase transitions, regression
```

## Doğrulanan invariantlar

### 1. Faz audit zinciri (1-21)

Her faz için en az bir `required_audits_any` audit var mı?
Eksik faz → "Açık Konular"da yüzeye.

### 2. Aşama 9 TDD derin denetim

```
for ac in spec_must_list:
    assert audit.has(f"asama-9-ac-{ac.id}-red")
    assert audit.has(f"asama-9-ac-{ac.id}-green")
    assert audit.has(f"asama-9-ac-{ac.id}-refactor")
assert audit.has("regression-clear")  # son test runner GREEN
```

### 3. Aşama 11-18 pipeline derin denetim

```
for phase in [11, 12, 13, 14, 15, 16, 17, 18]:
    if not_applicable(phase):
        assert audit.has(f"asama-{phase}-not-applicable")
    else:
        assert audit.has(f"asama-{phase}-scan")
        assert audit.has(f"asama-{phase}-rescan count=0")
```

### 4. Spec MUST kapsanma

state.spec_must_list × audit `asama-9-ac-N-green` ↔
audit `covers=MUST_N` zincirinden:
- Hangi MUST test ile bağlandı?
- Hangi MUST test'siz kaldı? → "Açık Konular"

### 5. Aşama 21 skip doğrulama (1.0.31)

Aşama 21 (Yerelleştirilmiş Rapor) skip kararı model davranışında —
hook tarafında dil tespiti yok. Detection control olarak Aşama 22
audit log'da Aşama 21'in **ya `asama-21-complete` ya `asama-21-skipped
reason=already-english`** içerdiğini doğrular. Hiçbiri yoksa **silent
skip** → "Açık Konular"'a düşer (Aşama 21 sessiz atlandı, denetlenmedi).

## Tamlık raporu (hook yazar)

```
📋 Aşama 22 — Tamlık Raporu (hook tarafından oluşturuldu)

✅ Aşama 1-21 audit zinciri: tam
✅ Aşama 9 TDD: 5/5 AC red→green→refactor + final GREEN
✅ Aşama 11-18 pipeline: tüm rescan count=0
⚠️ Spec MUST kapsanma: 4/5 (MUST_3 test yok)

Açık Konular:
  - MUST_3: kullanıcı silme akışı — Aşama 9'da AC işlendi mi? red/green
    audit yok. Aşama 9'a dönüş veya manuel test ekleme.

Process Trace özeti:
  - session_start: 2026-05-09T20:00:00Z
  - 21 phase transition (1→2→...→21)
  - 23 audit emit
  - Final regression-clear: 2026-05-09T22:30:14Z
  - Toplam süre: 2h 30m 14s

🤖 Hook signature: stop.py @ 2026-05-09T22:35:00Z
```

## Bilingual

Rapor **TR + EN** iki blok (boş satır ayrılı, etiketsiz). Hook
`bilingual.render("completeness_report_header")` ile başlık çağırır.

## İzinli tool'lar (Layer B)

`Read` (audit/state/trace okumak için) + Write (rapor yazmak için).
Bash AskUserQuestion gerekmez — hook tek başına çalışır.

## Çıktı (audit)

> **Model:** Bu aşama özeldir — model `asama-22-complete` **emit etmez**. Pre_tool model'in Bash/Write ile emit denemesini DENY ile bloklar.
> **Hook:** `asama-22-complete` tek başına stop hook tarafından, tamlık raporu üretildikten sonra yazılır.
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-22-complete (HOOK tarafından — modelden değil)
```

### Hook enforcement (1.0.32)

**Bu turda Aşama 22 implementasyonu hook'a getirildi.** Önceden skill
tasarlanmış ama hiçbir hook çalışmıyordu (declared-but-not-implemented).

- `_run_completeness_loop` Aşama 22 dalı: cp == 22 ve
  `asama-22-complete` yoksa rapor üretilir + audit emit edilir.
  Idempotent.
- `_detect_phase_complete_trigger` Aşama 22 guard: model
  `asama-22-complete` cevap metnine yazsa bile hook bu audit'i
  yazmaz; bunun yerine `phase-22-illegal-emit-attempt` audit emit
  edilir (görünür sinyal, kontrat ihlali kaydı).
- `_emit_phase_22_completeness_report`: 5 invariant kontrolü
  (audit zinciri 1-21, Aşama 9 TDD derinliği, Aşama 11-18 pipeline
  derinliği, Spec MUST kapsanma, Aşama 21 skip doğrulama). Bilingual
  rapor `.mycl/completeness_report.md` dosyasına yazılır. State'in
  `last_phase_output` alanına özet konur.
- `regression-clear` semantiği: test failure hiç olmadıysa bu audit
  yazılmaz. Final GREEN sinyali OR mantığıyla — `regression-clear`
  VEYA son `asama-9-ac-N-green` audit'i.
- Boş `spec_must_list` durumunda crash yok; rapora "Spec MUST listesi
  boş — Aşama 4 onaylanmamış olabilir" soft uyarısı düşer.

## Disiplin gerekleri

`subagent_rubber_duck: true` — Aşama 22 kritik faz; haiku ikinci-göz
"bu tamlık raporu doğru mu?" check.

## Anti-pattern

- ❌ Modelin `asama-22-complete` emit etmesi → pre_tool DENY +
  `phase-transition-illegal-emit-attempt` audit
- ❌ "Açık Konular yok" deyip yüzeye çıkarmama — hook objektif
  doğrulayıcı; eksik MUST var ise rapora yaz
- ❌ Bilingual rapor formatını bozma (sadece TR veya sadece EN) —
  hook her zaman iki blok üretir

---

# Phase 22 — Completeness Audit

## Goal

Verify the pipeline truly completed end-to-end. Surface skipped steps.

### Phase 21 skip verification (1.0.31)

Phase 21 (Localized Report) skip decision lives in model behavior —
no hook-side language detection. Phase 22 acts as a detection control:
it verifies the audit log contains **either `asama-21-complete` or
`asama-21-skipped reason=already-english`**. If neither is present,
it's a **silent skip** → surfaced under "Open Issues".

## CRITICAL: hook writes, model does NOT

`asama-22-complete` is hook-emitted. Bash attempts → pre_tool DENY +
`phase-transition-illegal-emit-attempt` audit.

## Reads three files

`.mycl/audit.log`, `.mycl/state.json`, `.mycl/trace.log`.

## Verified invariants

1. Phase 1-21 audit chain (each phase has a `required_audits_any`).
2. Phase 9 TDD: each AC has red/green/refactor + final
   `regression-clear`.
3. Phase 11-18 pipeline: scan/rescan count=0 or `not-applicable`.
4. Spec MUST coverage via `spec_must_list × asama-9-ac-N-green`.

## Report (hook writes)

Bilingual TR + EN, sections: pipeline status, open issues, process
trace summary, hook signature.

## Allowed tools

`Read` (audit/state/trace) + `Write` (report).

## Audit output

> **Model:** This phase is special — model **does not** emit `asama-22-complete`. Pre_tool DENYs Bash/Write emission attempts.
> **Hook:** `asama-22-complete` is hook-emitted by stop hook after the completeness report is generated.
> **Details:** see "Audit emission channel" contract in main skill.

`asama-22-complete` (hook only — never model).

### Hook enforcement (1.0.32)

**Phase 22 hook implementation landed in this turn** (previously a
declared-but-not-implemented skill).

- `_run_completeness_loop` Phase 22 branch: when `cp == 22` and
  `asama-22-complete` is absent, the hook generates the report and
  emits the audit. Idempotent.
- `_detect_phase_complete_trigger` Phase 22 guard: even if the model
  writes `asama-22-complete` in its reply, the hook does NOT promote
  it to an audit; it emits `phase-22-illegal-emit-attempt` instead
  (visible signal — contract violation).
- `_emit_phase_22_completeness_report`: 5 invariant checks (audit
  chain 1-21, Phase 9 TDD depth, Phase 11-18 pipeline depth, spec
  MUST coverage, Phase 21 skip verification). Bilingual report
  written to `.mycl/completeness_report.md`; summary placed in
  `state.last_phase_output`.
- `regression-clear` semantics: not written if no test failure ever
  occurred. Final GREEN signal uses OR — either `regression-clear`
  OR the last `asama-9-ac-N-green` audit.
- Empty `spec_must_list` does not crash; the report surfaces "spec
  MUST list empty — Phase 4 may not be approved" as a soft notice.

## Discipline

`subagent_rubber_duck: true`.

## Anti-patterns

- Model emitting `asama-22-complete` (pre_tool blocks).
- Claiming no open issues without verifying spec MUST coverage.
- Breaking bilingual format (must be TR + EN both).
