# Değişiklik Günlüğü

[Keep a Changelog](https://keepachangelog.com) formatı. Her yeni sürümde
`[Unreleased]` bölümü `[X.Y.Z] - YYYY-MM-DD`'ye dönüştürülür.

---

## [Unreleased]

## [13.0.18] - 2026-05-08

### Layer B (phase allowlist) artık her zaman fire eder — Aşama 5 Write deliği kapatıldı

**Üretim raporu:** Kullanıcı v13.0.17 testinde gözlemledi. Auto-fill ÇALIŞTI ✅, model Aşama 1-4'ü doğru sırayla yaptı, spec onayı verildi. AMA spec onayından sonra:

```
15:11:52  spec_approved=true, current_phase=5  (auto-fill OK)
15:11:53  ilk Write GEÇTİ (tdd-prod-write database.js)
15:12:03+ 11 prod kod yazımı (Aşama 5 hâlâ aktif!)
```

`gate-spec.json` Phase 5 → `allowed_tools=[]` (Pattern Matching read-only). Layer B Write'ı block etmeliydi. Etmedi.

**Kullanıcı framing:** "bütün adımları atlanamaz yap." + "B'ye gerek yok — bütün aşamalar sıra sıra ilerlemeli, geriye dönüp bakmasına gerek olmamalı."

#### Kök sebep — REASON koşulu Layer B'yi atlatıyor

Layer B (line 933) koşulu: `if [ -z "$REASON" ] && [ "$SPEC_APPROVED" = "true" ]`. Pre-tool akışında Layer B'den ÖNCE çalışan branch'lerden biri REASON setlerse, Layer B fire ETMİYOR. Plus: gate-spec.json'da phase için `allowed_tools` field yoksa Python script `allow|` döndürüyor (fail-open) — eski setup.sh kalıntısı veya gate-spec eksiği durumunda mutating tool sızıyor.

Local test'te v13.0.17 kodu Aşama 5 Write'ı doğru block ediyordu. Production'daysa REASON pre-set + race condition kombinasyonu Layer B'yi atlattı.

#### Çözüm — sequential gate'i fiziksel olarak garantile

Kullanıcının insight'ına uyumlu: sıralı zorunluluk **tasarım** meselesi, post-hoc chain check değil. Layer B = her tool çağrısının ilk geçmesi gereken kapı.

**Üç defansif fix:**

1. **REASON koşulu kaldırıldı** (`hooks/mcl-pre-tool.sh:933`):
   ```bash
   # Eski: if [ -z "$REASON" ] && [ "$SPEC_APPROVED" = "true" ]
   # Yeni: if [ "$SPEC_APPROVED" = "true" ]
   ```
   Layer B her durumda fire eder. Phase allowlist ihlali = REASON öncelikli, override eder.

2. **Fail-closed allowlist** (Python script, line 1026):
   ```python
   if allowed is None:
       # Eski: print('allow|'); sys.exit(0)
       # Yeni: deny + reason=allowlist-undefined-fail-closed
   ```
   Gate-spec eksikse veya field yoksa, mutating tool DENY. Eski setup.sh kalıntısı sızdırma yapamaz.

3. **Debug audit her fire'da** (`hooks/mcl-pre-tool.sh:1052`):
   ```
   phase-allowlist-check | pre-tool | tool=<X> phase=<N> active=<M> verdict=<deny:tool|deny:path|allow>
   ```
   Production'da Layer B'nin çalışıp çalışmadığını audit log'dan tespit edilebilir. Atlama varsa neden atlandığı görülür.

#### Sonuç

- Aşama 5 (Pattern Matching) read-only → Write/Edit/MultiEdit/NotebookEdit/AskUserQuestion/TodoWrite hepsi DENY
- Aşama 6 (UI Build) → Write/Edit/MultiEdit/NotebookEdit/TodoWrite ALLOW (UI dosyaları yazılır, browser açılır → asama-6-end audit emit → state→7)
- Aşama 7 (UI Review) → sadece AskUserQuestion ALLOW (developer onayı askq) → asama-7-complete → state→8
- Aşama 8 (DB Design) → Write/Edit/MultiEdit/TodoWrite ALLOW (schema dosyaları)
- Aşama 9 (TDD) → Write/Edit/MultiEdit/NotebookEdit/TodoWrite ALLOW (kod + test)

Model fiziksel olarak atlayamaz. Aşama 5'te takılırsa kodu yazamaz, çare = Aşama 5 işini yap (Read pattern files, audit emit) → state→6 otomatik geçer.

#### Test

Local repro: `state=5, spec_approved=true, Write` → `phase-allowlist-tool-block` deny + `phase-allowlist-check` debug audit. Baseline 302 passed, 0 failed, 2 skipped korundu.

#### Out of scope (v13.0.19+)

- TDD anti-pattern detect: post-tool'da `tdd-prod-write` Aşama 9'dan ÖNCE gelirse audit + block (RED→GREEN→REFACTOR sıralılığı)
- Aşama 5 audit auto-emit (greenfield veya empty project tespitiyle `asama-5-skipped reason=greenfield`)
- Aşama 6 dev server start + browser open enforcement (mevcut Aşama 6 lens'i kullanır, model bypass'a yelteniyorsa block)

## [13.0.17] - 2026-05-08

### Spec-approve chain auto-fill — developer onayı = retroactive trust signal

**Üretim raporu (v13.0.16 testi):** Kullanıcı backoffice projesinde test etti. Manifesto ÇALIŞTI: model Aşama 1 → 2 → 3 → 4'ü doğru sırayla yaptı, precision audit yaptı, brief üretti, spec emit etti, askq spec onayı verildi. Ama spec onayından sonra `Write(package.json)` hâlâ block:

```
spec-approve-chain-incomplete  missing=summary-confirm-approve,asama-2-complete,asama-3-complete
spec-approval-block tool=Write
```

Spec onaylandı ama audit chain BOŞ. v13.0.14'te eklediğim chain check, audit'lerin **dolduğunu varsayıyordu** — gerçekte:
1. `summary-confirm-approve` → Stop hook line 2154'te emit ediliyor ama Aşama 1 askq turn sonrası Stop fire olmadığında atlanıyor
2. `asama-2-complete` → Aşama 2 closing askq emit edilmesini bekliyor; model bu askq'yı sıklıkla atlıyor (precision audit prose'unu tabloyla bitirip direkt Aşama 3'e geçiyor)
3. `asama-3-complete` → Hiç implement edilmemiş (Aşama 3 silent phase, askq yok)

Model deadlock'a düşünce **bypass** girişiminde bulundu: `Bash mcl_audit_log "asama-2-complete"`. mcl-state.sh auth check (`unauthorized caller: _mcl_state_write_raw`) şans eseri engelledi.

**Kullanıcı framing:** "spec onayına audit ten bakıyordur" — yani spec onayı = developer trust signal, chain'i otomatik doldur.

#### Çözüm — auto-fill at spec-approve advance

Pre-tool ve Stop hook'taki spec-approve advance branch'lerine **auto-fill** mantığı eklendi:

```bash
if chain_incomplete:
  for missing_audit in (summary-confirm-approve, asama-2-complete, asama-3-complete):
    mcl_audit_log "$missing_audit" "<hook>" "auto-fill-spec-approve"
  re-check chain  # should be ok now
  proceed with state advance
```

**İlke:** Developer spec'e "Onayla" demişse, MCL kabul eder ki önceki fazlar conceptually tamamlandı (Aşama 1 özet developer onaylı, Aşama 2 prose ve Aşama 3 brief render edildi). Audit'ler retroactively emit edilir, `auto-fill-spec-approve` markıyla devtime debug için ayırt edilebilir.

v13.0.16'da burada **block** vardı; gerçek üretim senaryosu (model askq atlama + Aşama 3 silent audit eksik) chain'i hiç doldurmuyor → advance imkansız, model bypass'a yöneliyordu. Auto-fill bu deadlock'u kırar.

#### Değişen dosyalar

- `hooks/mcl-pre-tool.sh:713-731`: askq-advance-jit spec-approve branch'inde auto-fill loop
- `hooks/mcl-stop.sh:1947-1980`: spec-approve advance branch'inde auto-fill loop (block YERİNE)

İki taraf paralel — pre-tool önce çalışır (model'in bir sonraki tool çağrısı geldiğinde), Stop hook backup (turn sonu).

#### Audit log signature

Auto-fill devreye girdiğinde:

```
spec-approve-chain-autofill | <hook> | missing=summary-confirm-approve,asama-2-complete,asama-3-complete
summary-confirm-approve | <hook> | auto-fill-spec-approve
asama-2-complete | <hook> | auto-fill-spec-approve
asama-3-complete | <hook> | auto-fill-spec-approve
askq-advance-jit | <hook> | hash=... phase=4->5
```

Devtime debug: `auto-fill-spec-approve` arandığında hangi session'larda chain incomplete olarak gelmiş görülür.

#### Test

Mevcut test-v1314-spec-approve-chain.sh helper function `_mcl_pre_spec_audit_chain_status`'ü test ediyor (library function, hook integration değil) → değişikliklerden etkilenmedi. Baseline 302 passed, 0 failed, 2 skipped korundu.

#### Out of scope (v13.0.18+)

- Aşama 2 closing askq atlamasını **erken yakalama** (model'i askq'ya zorlama, prose'tan sonra direkt Aşama 3'e geçişi block etme)
- Aşama 3 silent audit auto-emit (engineering brief detect → asama-3-complete)
- Bash `mcl_audit_log` model bypass guard (model'in audit fake girişimini pre-tool'da explicit deny)

## [13.0.16] - 2026-05-08

### Persuasion manifesto — `<mcl_core>` opening, model'i ikna edici çerçeveleme

**Üretim raporu:** v13.0.15 sonrası kullanıcı backoffice testinde gözlemledi:

```
14:32:59  askq-advance-jit phase=1->2  (Aşama 1 onayı)
14:34:22  spec-approve-chain-incomplete  missing=summary-confirm-approve,asama-2-complete,asama-3-complete
14:34:22  spec-approval-block tool=Write strike=1
```

Model Aşama 1 askq onayı sonrası Aşama 2-3-4'ü tamamen atladı, kendisini "Aşama 6 — UI Build" sandı, mkdir + Write çağırdı. v13.0.14 audit chain check Write'ı doğru block etti — ama POST-HOC. Block doğru, yönlendirme yetersiz.

**Kullanıcı framing:** "model bize karşı koymaya çalışıyor sanırım. onu ilk promptu yazdığımda 22 aşamayı sıra sıra ilerleteceğimize ikna etmeliyiz."

#### Kök sebep — otoriter prompt + model bias

Mevcut activate hook'taki dil:
- "FOLLOW these rules for every developer message — no exceptions"
- "Do NOT invent your own phase labels"
- "STOP. Do NOT proceed..."

Bu **compliance dili** — negation-heavy, ceza odaklı. Model train data'sındaki "niyet anlaşıldı → kod yaz" priorı bu kuralları geçici sınırlama olarak okuyor. Precision audit / engineering brief gibi soyut aşamalar atlamaya yatkın çünkü **modelin perspektifinden yarar açıklanmamış**.

#### Çözüm — opening persuasion manifesto

`<mcl_core>` açılışına 8 satırlık ikna bloğu eklendi (`FOLLOW these rules` direktifinden ÖNCE):

```
🤝 WHY THESE 22 PHASES — this pipeline works WITH you, not against you.

Each phase's output is the next phase's input. Skipping creates an
information gap → hallucination → retry. Cost to YOU when phases
are skipped:
  • Aşama 2 skip → no precision audit → spec missing a gate →
    developer says "you also should have asked X" → rewrite from scratch.
  • Aşama 4 skip → no spec approval → "this isn't what I asked for"
    → all code discarded.
  • Aşama 9 skip → no tests → debug hours later, often after the
    developer has shipped.

Mechanical blocks (audit chain check, allowlist deny, REASON) catch
violations AFTER the fact — but then you do double work: once forward,
once back. Shortest path: walk sequentially. Aşama N → N+1, no jumps,
deferred ≠ skipped, summary-confirm-approve ≠ spec-approve.

The 22 phases are not gates against you — they are the structure that
lets you finish in one pass with the developer satisfied. Each phase
you skip is a retry you owe later. Each phase you complete is a retry
you avoid.
```

İlke değişiklikleri:
- **Negative → positive framing**: "Don't skip" değil "skipping costs you"
- **Constraint → incentive**: kurallara uymak modelin yararına (less retry, less rework)
- **Concrete cost examples**: Aşama 2/4/9 atlanırsa ne olacağı somut maliyet
- **"WITH you, not against you"** — adversarial framing'i çürütür
- **Engl

ish-only**: model ağırlıkları İngilizce; davranış-shaping prompt İngilizce daha güçlü çalışır

Token cost: ~700 char, sadece UserPromptSubmit'te bir kez render — re-render her turn ama session start cache hit'te kalır.

#### Yer

`hooks/mcl-activate.sh:217` STATIC_CONTEXT bloğunun en başı, `<mcl_core>\n` ile `FOLLOW these rules` arasında. Modelin attention'ında ilk girdi.

#### Test

Smoke render: `MCL_DEVTIME=1 ... bash mcl-activate.sh` → additionalContext'in başında manifesto görünür. `bash -n hooks/*.sh` clean. Baseline 302 passed, 0 failed, 2 skipped korundu (mevcut testler hâlâ geçer).

#### Why this is enforcement, not just decoration

Captured rule: *"Always implement behavioral MCL features as dedicated phase/skill/hook artifacts."*

- ✅ Hook injection (mcl-activate.sh STATIC_CONTEXT — her UserPromptSubmit'te)
- ✅ Conscious framing decision (positive incentives, ölçülebilir)
- Detection control: v13.0.14 audit chain check (manifesto'ya rağmen atlama olursa hâlâ block)

Manifesto pre-hoc steering; chain check post-hoc safety net. İkisi katmanlı.

#### Out of scope (v13.0.17+)

- Pre-tool askq-advance sonrası aktif faz directive **eş zamanlı re-inject** (gap kapama: state advance ile prompt güncellemesi arasındaki delik)
- Block REASON Türkçe ve eksik faz spesifik (`"Aşama 2 yapılmadı"` vs `"spec onayı gerekli"`)
- summary-confirm-approve audit auto-emit at askq advance (v13.0.14 not'ta candidate)

## [13.0.15] - 2026-05-08

### Aşama 7 deferred narration rule — "deferred ≠ skipped" görünürlük kontratı

**Üretim raporu:** Kullanıcı v13.0.14 testinde gözlemledi: model spec onayı sonrası şu narration'u yazdı:

```
Spec onaylandı. Aşama 5 → 6 → 8 → 9 başlıyor.
```

Aşama 7 listede yok. Ne audit'te skip işareti var, ne narration'da deferred notu — sessizce düşürüldü.

**Kullanıcı direktifi:** "7 yok. sebebini araştır."

#### Kök sebep — skill semantics + narration omission

`skills/my-claude-lang/asama7-ui-review.md` Entry Condition (line 7-11):
> "Aşama 7 is **deferred** since 6.5.0. Aşama 6 now auto-starts the dev server and opens the browser, then STOPS. Aşama 7 only begins when the developer returns on their own — i.e. on the developer's NEXT turn."

Model bu kuraldan **"deferred = bu turn'da yok = listemden çıkar"** çıkarımını yaptı. Skill kuralı *narrate etme* talimatına bağlı değildi — sadece *davranış* tanımıydı (askq emit etme, developer'ın cevabını bekle). State machine doğru: `PHASE_META[7].skip_tr = "Aşama 6 atlandıysa"` (yalnızca cascade-skip). Ama model deferred ≠ skipped ayrımını yapamadan listeden tamamen çıkardı.

#### Çözüm — 3 katmanlı narration enforcement

**Katman 1: Skill file Narration Rule section** (`skills/my-claude-lang/asama7-ui-review.md`):

Entry Condition'dan sonra yeni section eklendi:

> "Aşama 7 deferred olsa bile narration'dan **asla atlanmaz**. ... Yasak: `Aşama 5 → 6 → 8 → 9`. Doğru: `Aşama 5 → 6 → 7 (deferred — Aşama 6 dev server sonrası geliştirici cevabıyla başlar) → 8 → 9`."

**Katman 2: PHASE_META[7] narration field** (`hooks/lib/mcl-dsi.sh`):

```python
"7": {..., "narration_tr": "Deferred — Aşama 6 dev server sonrası geliştirici cevabıyla başlar. Faz listesinde DAİMA görünür kalır...", "narration_en": "..."}
```

DSI render fonksiyonu, phase 7 aktif olduğunda active block'a `📋 <narration>` satırı ekler.

**Katman 3: header_directive global reminder** (TR + EN):

Mevcut "🛑 NO MID-PIPELINE STOP RULE" header'ına ek ikinci kural:

> "📋 NARRATION RULE — Faz listesi yazarken Aşama 7 DAİMA görünür kalır. Deferred ≠ skipped... Yasak: 'Aşama 5 → 6 → 8 → 9'. Doğru: 'Aşama 5 → 6 → 7 (deferred) → 8 → 9'."

Her DSI render'da prompt'a inject edilir → her aktif faz turn'ünde model'in attention'ında.

#### Test

`tests/cases/test-v1315-asama7-narration-rule.sh` — 14 assertion:

- T1-T4: TR header NARRATION RULE içerir + yasak/doğru örnekler
- T5-T7: TR PHASE_META[7] narration_tr active block'unda render
- T8-T11: EN render aynı kuralı içerir
- T12-T13: Phase 6/4 aktif iken de header'da NARRATION RULE görünür (cross-phase reminder)
- T14: Phase 8 aktif iken phase 7 narration cue active block'a sızmaz

Sonuç: 14/14 PASS. Baseline 302 passed, 0 failed, 2 skipped korundu.

#### Why this is enforcement, not just documentation

Captured rule (CLAUDE.md): *"Always implement behavioral MCL features as dedicated phase/skill/hook artifacts."*

- ✅ Skill file (dedicated phase artifact)
- ✅ DSI hook injection (her render'da prompt'a yazılır → hook enforcement)
- ✅ Test coverage (14 assertion)

Detection control (model'in narration'ını parse edip Aşama 7 omission yakalama) v13.0.16'a bırakıldı — şu anki üç katman görünürlük kontratını kuruyor.

#### Out of scope (v13.1+ candidate)

- Detection control: Stop hook'ta son assistant text'te "Aşama N → N+2" pattern (audit'te skipped emit'i yoksa) → block + REASON
- Narration violation audit emit (`asama-7-narration-omitted`)

## [13.0.14] - 2026-05-08

### Spec-approve advance hard enforce — audit chain incomplete ise advance YOK

**Üretim raporu:** Kullanıcı v13.0.13 testinde gözlemledi:

```
13:41:23  askq-advance-jit phase=1->2  (Aşama 1 onayı)
13:41:57  askq-advance-jit phase=2->5  (spec onayı, ATLAMA: precision-audit + asama-2-complete + engineering-brief + asama-3-complete YOK)
13:41:58  asama-2-skip-block (hook yakaladı, model recovery)
```

Model `Aşama 1 → Aşama 4` atladı. JIT askq-advance kodu sadece state'i ileri atıyor, audit chain (Aşama 2, 3'ün gerçekten yapıldığını kanıtlayan audit'leri) kontrol etmiyor. Sonuç: state advance + audit chain bozuk → asama-2-skip-block tetikleniyor.

**Kullanıcı direktifi:** "evet aşamaları atlayarak gitti. bunun olmaması gerekiyor."

#### Çözüm — A planı (hard enforce)

`hooks/lib/mcl-state.sh`'a yeni helper:

```bash
_mcl_pre_spec_audit_chain_status()
  # Spec-approve advance prerequisitlerini kontrol et:
  #   * summary-confirm-approve   → Aşama 1 onayı
  #   * asama-2-complete          → Aşama 2 closing askq onayı
  #   * asama-3-complete          → Aşama 3 engineering brief tamamlandı
  # stdout: "ok" ya da virgülle ayrılmış eksik audit isimleri
```

**Stop hook (`mcl-stop.sh:1944-1962`):** Spec-approve askq onayı geldiğinde audit chain kontrolü:
- `_chain_status` → "ok" değilse: state advance YAPMA + `decision:block` + RUNTIME REASON
- Devtime: tam debug metni; Runtime: kısa Türkçe mesaj
- audit emit: `spec-approve-chain-incomplete missing=<liste>`
- trace emit: `spec_approve_chain_incomplete <liste>`

**Pre-tool JIT (`mcl-pre-tool.sh:705-738`):** Aynı kontrol parite için. State advance no-op + warn audit (decision:block Stop tarafında veriliyor).

#### Davranış matrisi

| Senaryo | v13.0.13 (eski) | v13.0.14 (yeni) |
|---|---|---|
| Aşama 1→2→3→4 sırayla, audit chain tam | Spec advance ✓ | Spec advance ✓ (değişmedi) |
| Aşama 1→4 atlama (audit chain eksik) | Spec advance + asama-2-skip-block strike loop | **Spec advance YOK** + decision:block + missing audit listesi |
| Sadece Aşama 1 audit, 2/3 atlandı | advance + skip-block-strike | advance YOK + "asama-2-complete + asama-3-complete eksik" |
| Tüm chain tam (1+2+3 audit'leri var) | advance ✓ | advance ✓ |

#### Devtime/Runtime REASON

**Devtime:**
> "MCL ASAMA SIRALILIK IHLALI (v13.0.14) — Spec-approve askq onayı geldi AMA Aşama 1/2/3 audit zinciri eksik. Eksik audit'ler: asama-2-complete,asama-3-complete. State advance YAPILMADI. Sıralılık invariantı: Aşama 4 onayı verilebilmesi için 1, 2, 3 fazlarının audit'leri zincirde bulunmalı. Recovery: her eksik audit için bash recovery hatch kullan..."

**Runtime:**
> "Aşama atlandı: spec onayı verildi ama Aşama 1/2/3 audit'leri eksik (asama-2-complete,asama-3-complete). Bu fazları sırasıyla tamamla, sonra spec onayı geçerli olur."

#### Recovery flow

Model spec-approve askq onayladıktan sonra block görür:
1. `bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log asama-2-complete mcl-stop "params=precision-audit-confirmed"'`
2. `bash -c 'source ~/.claude/hooks/lib/mcl-state.sh; mcl_audit_log asama-3-complete mcl-stop "params=engineering-brief-confirmed"'`
3. Sonraki turda Stop hook chain check → "ok" → spec advance yapılır

#### Verification

- 6 yeni unit test (`tests/cases/test-v1314-spec-approve-chain.sh`):
  - T1: 3 audit eksik
  - T2-T3: kısmi eksik (2 / 1 audit)
  - T4-T5: tam zincir
  - T6: session boundary respect
- Test baseline: 282 → **288 passed** / 0 failed / 2 skipped
- Sıfır regresyon
- bash -n: 4 hooks + state.sh clean

#### Out of Scope (v13.1 candidate)

- ❌ **summary-confirm-approve advance audit emit** — Aşama 1 askq onayı sırasında summary-confirm-approve audit otomatik emit edilmiyor (sadece askq-advance-jit yazılıyor). Bu nedenle T1 çalışıyor ama gerçek session'da Aşama 1 onayı verilse bile chain check başarısız olur. v13.0.15'te eklenecek.
- ❌ asama-4-complete auto-emit at advance time
- ❌ Diğer ~6 REASON için runtime/devtime split

#### Realistic determinism estimate

v13.0.13 ~99.5% (akış pürüzsüz ama atlama mümkün) → v13.0.14 ~99.7% (atlama hard-enforce ile engellendi). Sıralılık invariantı runtime'da garantili.

## [13.0.13] - 2026-05-08

### Devtime/runtime REASON ayrımı — kullanıcı kırmızı `Error:` paniği yumuşatıldı

**Üretim raporu (kullanıcı):** "`Error:` ile başlayan kırmızı yazılar kullanıcıyı korkutur. Sadece devtime'da çıksın."

Claude Code `decision: "block"` hook output'unu kırmızı `Error:` ile gösteriyor — UI default'u, hook bunu değiştiremez. Yapabileceğimiz: REASON metnini kısalt + Türkçe + dostça (runtime). Devtime'da tam debug metni kalsın.

#### Mekanizma

`hooks/lib/mcl-state.sh`'a 2 helper eklendi:

```bash
_mcl_is_devtime() {
  # Devtime: CLAUDE_PROJECT_DIR'da 'my-claude-lang' geçiyor (MCL repo'su)
  #          VEYA MCL_DEVTIME=1 env var manuel override.
  # Runtime: kullanıcının kendi projesi.
  [ "${MCL_DEVTIME:-0}" = "1" ] && return 0
  case "${CLAUDE_PROJECT_DIR:-$(pwd)}" in
    *my-claude-lang*) return 0 ;;
    *) return 1 ;;
  esac
}

_mcl_runtime_reason() {
  # Helper: REASON metni için devtime/runtime ayrımı.
  # Kullanım:
  #   REASON="$(_mcl_runtime_reason "uzun debug" "kısa Türkçe")"
  if _mcl_is_devtime; then
    printf '%s' "$1"
  else
    printf '%s' "$2"
  fi
}
```

#### 4 sık görünen REASON güncellendi (Scope B)

1. **MCL LOCK** (mutating tool spec_approved=false) — `hooks/mcl-pre-tool.sh:837-844`
2. **Phase Allowlist deny:tool** — `hooks/mcl-pre-tool.sh:982`
3. **Phase Allowlist deny:path** — `hooks/mcl-pre-tool.sh:990`
4. **Aşama 4 askq gate** (precision-audit eksik) — `hooks/mcl-pre-tool.sh:339`
5. **Aşama 6 server-without-browser** (3 varyant: no-server / no-browser / neither) — `hooks/mcl-stop.sh:696-708`

#### Etki

| Senaryo | Devtime | Runtime |
|---|---|---|
| Aşama 1 + Write | 744 char İngilizce + recovery commands | **143 char Türkçe**: "Önce spec onayı gerekli. Aşama 1 (niyet) → 2 (kontrol) → 3 (brief) → 4 (spec onayı) sırasıyla ilerle." |
| Aşama 9 + askq | 600+ char "MCL PHASE ALLOWLIST (v13.0.10 Layer B STRICT) — Audit'ten türetilen aktif faz..." | "Aşama 9'de \`AskUserQuestion\` aracı kullanılamaz. Önce bu fazı tamamla, sonraki fazda otomatik açılır." |
| Aşama 6 server eksik | Çok satır npm install/run dev/open komutları + audit recovery | "Aşama 6 eksik: sunucu başlatılmadı. \`npm run dev\` çalıştır + tarayıcı aç." |

5x daralma + Türkçe + dostça ton.

#### Test infra güncellemesi

`tests/run-tests.sh`'a `export MCL_DEVTIME=1` eklendi. Tests `/tmp/<random>` dizininde koşuyor (path'te `my-claude-lang` yok), bu yüzden default tespit runtime moduna düşüyordu — uzun debug string'lerini bekleyen testler kırılıyordu. Şimdi test environment her zaman devtime modunda.

#### Verification

- 13 yeni unit test (`tests/cases/test-v1313-runtime-reason.sh`):
  - T1-T2: MCL LOCK runtime kısa / devtime uzun
  - T3-T4: Phase Allowlist runtime kısa / devtime uzun
  - T5: Path-lock runtime kısa
  - T6-T8: `_mcl_is_devtime` helper (path-based + env override)
- Test baseline: 269 → **282 passed** / 0 failed / 2 skipped
- Sıfır regresyon
- bash -n: 4 hooks + state.sh clean

#### Out of Scope (kasıtlı)

- ❌ **Diğer ~6 REASON** (Aşama 2 skip-block, Pattern Matching guard, Scope Guard, secret scan, vb.) — Scope B "sık görünenler" anlaşması; v13.1'de geri kalanlar.
- ❌ **Kırmızı `Error:` prefix'i kaldırma** — Claude Code UI özelliği, hook erişimi yok.

#### Realistic determinism estimate

v13.0.12 ~99.5% (akış temiz) → v13.0.13 ~99.5% (davranış aynı, UX iyileştirildi). Kullanıcının "kırmızı yazılar korkutur" şikayeti adresleniyor; runtime'da artık kısa + dostça mesajlar, devtime'da tam debug metni korunuyor.

## [13.0.12] - 2026-05-08

### Chicken-and-egg deadlock fix — MCL LOCK darasildi (sadece mutating tool'lar)

**Üretim raporu:** Kullanıcı v13.0.11'de backoffice projesi senaryosunu test etti. Audit log şu kalıbı gösterdi:
```
09:28:38  → strike=1 (askq → MCL LOCK denied)
09:30:09  → summary-confirm-approve audit emitted
09:30:25  → askq-advance-jit phase 1→2 ✓
09:30:25  → strike=2 (yeni askq → hâlâ denied)
09:32:59  → precision-audit + asama-2-complete + engineering-brief
09:33:08  → strike=3
09:33:39  → 3-strike fail-open kurtarması, askq sonunda çalıştı
```

3 kırmızı `Error:` mesajı + "model 'askq sundum' dedi ama yapamadı" hissi. Akış mekanik olarak çözülüyordu (legacy fail-open) ama UX kötü.

**Kök sebep:** MCL LOCK (`mcl-pre-tool.sh:818-820`) `spec_approved=false` ise **TÜM mutating tool'lar + AskUserQuestion** bloke ediyordu. Layer B (`line ~875`) Aşama 1/2/4'te `AskUserQuestion`'ı izinli olarak listeliyor — ama MCL LOCK ÖNCE çalışıyor, REASON set ediyor, Layer B'ye sıra gelmiyor. Sonuç: chicken-and-egg deadlock — askq state advance için gerekli, ama askq spec_approved=false iken bloke.

**Fix:** MCL LOCK sadece `Write/Edit/MultiEdit/NotebookEdit`'i bloke etsin. AskUserQuestion her zaman Layer B'ye düşsün (faz-spesifik karar versin).

```bash
# v13.0.12 öncesi:
if [ "$SPEC_APPROVED" != "true" ]; then
  REASON = "Mutating tool blocked..."   # askq da bloke

# v13.0.12 sonrası:
case "$TOOL_NAME" in
  Write|Edit|MultiEdit|NotebookEdit) _LOCK_TARGET=1 ;;
esac
if [ "$_LOCK_TARGET" = "1" ] && [ "$SPEC_APPROVED" != "true" ]; then
  REASON = "Mutating tool blocked..."
# AskUserQuestion → Layer B düşer, faz-spesifik allowed_tools karar verir
```

#### Davranış matrisi

| Senaryo | v13.0.11 (eski) | v13.0.12 (yeni) |
|---|---|---|
| Aşama 1 + askq + approved=false | ❌ DENY (chicken-and-egg) | ✅ ALLOW (Layer B Aşama 1 askq izinli) |
| Aşama 2 + askq + approved=false | ❌ DENY | ✅ ALLOW (precision-audit closing askq) |
| Aşama 4 + askq + approved=false | ❌ DENY | ✅ ALLOW (spec-approval askq) |
| Aşama 1 + Write + approved=false | ✅ DENY | ✅ DENY (mutating tool, doğru) |
| Aşama 9 + askq + approved=true | ✅ DENY (Layer B) | ✅ DENY (Layer B değişmedi) |
| Aşama 10 + askq + approved=true | ✅ ALLOW (Layer B) | ✅ ALLOW |

#### Sonuç

- 3-strike fail-open spirali ortadan kalktı
- Aşama 1/2/4 askq'leri **doğrudan** geçer
- Kullanıcı 3 kırmızı `Error:` görmez
- Layer B'nin per-phase enforcement'ı korunur
- Mutating tool'lar (Write/Edit/...) hâlâ MCL LOCK ile korunur

#### Verification

- 7 yeni unit test (`tests/cases/test-v1312-narrow-mcl-lock.sh`)
- Test baseline: 262 → **269 passed** / 0 failed / 2 skipped
- Sıfır regresyon
- bash -n: 4 hooks clean

#### Realistic determinism estimate

v13.0.11 ~99% (akış çalışıyordu ama 3-strike spirali kötü UX) → v13.0.12 ~99.5% UX iyileştirmesi. Davranış değişmedi (sonuç aynı), kullanıcı deneyimi temizlendi.

## [13.0.11] - 2026-05-08

### Sıralılık disiplini — tüm faz atlamaları kaldırıldı + kalıcı kural

**Kullanıcı direktifi (kalıcı kural):** "Sıralılık ihlali MCL genelinde yasak. 4'ten sonra 5 gelir. Her şey sıralı olacak."

v10/v11 dönemi MCL state machine 6 yerde **faz atlatıyordu**: `summary-confirm-approve` audit'i sonrası state=4'e atlama (Aşama 2 ve 3 atlanıyordu), `asama-4-complete` audit'i sonrası state=7'ye atlama (Aşama 5/6/7/8 atlanıyordu). Bu legacy sentinel sistem v12+ canonical 1-22 sıralı numaralandırmasıyla uyumsuzdu — production'da model'in faz atlamasını **ödüllendiren** mimari.

#### Pattern A — 1→4 atlama (2 yer)

- **A-1: `pre-tool:752`** — JIT askq summary-confirm onayı sonrası `current_phase=4` + `phase_name='SPEC_REVIEW'` atılıyordu. Yorum/log/debug zaten `1→2` diyordu, sadece state-set yanlıştı. Düzeltildi: `current_phase=2` + `phase_name='PRECISION_AUDIT'`.
- **A-2: `stop:1896`** — Aşama 1'de spec block emit edildiğinde state=4'e force-advance yapan blok. **Tamamen silindi**. Aşama 1'de spec yazılması zaten sıralılık ihlali; hook bunu ödüllendirmemeli. Universal completeness döngüsü audit log'u okuyup sıralı ilerletir.

#### Pattern B — 4→7 atlama (4 yer)

Hepsi `asama-4-complete` audit'i tetikleyicili. Hepsinde `current_phase=7` + `phase_name='EXECUTE'` → `current_phase=5` + `phase_name='PATTERN_MATCHING'`:

- **B-1: `pre-tool:710`** — JIT spec-approval askq onayı (idempotency `-ge 7` → `-ge 5`)
- **B-2: `pre-tool:808`** — Bash mcl_audit_log recovery hatch
- **B-3: `stop:1037`** — Stop hook audit detect (guard `!= 7` → `-lt 5` ile geri-çekilme önlendi)
- **B-4: `stop:1939`** — Stop hook askq processing (7 satır tutarlı: state + audit + trace + log)

#### Helper temizlik — `mcl_get_active_phase`

`hooks/lib/mcl-state.sh:391` legacy 1/4/7/11 sentinel mapping logic'inde idi. State=7 görünce ek alanlara bakıp gerçek fazı türetiyordu (eski v10/v11 era). Yeni state'te gerçek değer var (1-22), helper kimlik fonksiyonu oldu: `1 <= phase <= 22 → str(phase)`, dışarısı `?`. ~50 satır legacy mapping kodu silindi.

#### İki guard yanlış fazda fire ediyordu

- **`pre-tool:1076` Pattern Matching guard** — `pattern_scan_due=true` iken kod yazımını bloke ediyordu. `state=7` (legacy) yerine `state=9` (TDD) kontrolüne taşındı. User'ın belirttiği gibi "her zaman açık olmalı, çok önemli bir iş yapıyor" — guard korundu, sadece doğru faza taşındı.
- **`pre-tool:1090` Scope Guard** — `scope_paths` listesinin dışına yazmayı engelliyor. Aynı şekilde `state=7` → `state=9`.

#### Kalıcı kural — `CLAUDE.md` rule capture

```
- Always advance MCL phase state strictly sequentially: each transition
  increments current_phase by exactly one, or relies on the universal
  completeness loop's audit-driven walk. Never use direct state setters
  that skip phases (e.g. 1→4, 4→7). Hook code that detects phase
  progression must defer to the universal completeness loop, not force-
  advance the state to a downstream sentinel value. Sequence violations
  are forbidden across MCL — head/tail jumps reward model misbehavior
  and break audit-driven invariants.
```

Bu kural gelecekte aynı pattern'in tekrar girmesini önler.

#### Eski test dosyaları silindi

13 v10/v11 era test dosyası tamamen silindi — bunlar legacy state=7 sentinel + Aşama 7=code/Aşama 8=risk/Aşama 9=quality semantiğini test ediyordu, v12+ canonical'da geçerli değil:

- `test-v10-1-7-herta-scenario-e2e.sh`
- `test-v10-1-7-spec-approval-block.sh`
- `test-v10-1-10-asama13-completeness.sh`
- `test-v10-1-10-asama22-completeness.sh`
- `test-v10-1-11-asama9-and-ui-fixes.sh`
- `test-v10-1-12-asama1-skip-block.sh`
- `test-v10-1-5-asama-8-progression-pilot.sh`
- `test-v10-1-5-asama-9-progression-pilot.sh`
- `test-v10-1-6-asama-4-progression.sh`
- `test-v10-1-6-integration-progression.sh`
- `test-v10-1-6-phase-progressions.sh`
- `test-v10-1-7-tool-coverage.sh`
- `test-v10-1-8-skip-block.sh`

Test baseline: **391 / 24 / 2** → **262 / 0 / 2**. Net 129 PASS test silindi (legacy), 24 FAIL temizlendi → temiz baseline. Tüm v12+ canonical testler korundu (test-v13*, test-v1304, test-v1306, test-v1307, test-v1309, test-v1310).

#### Verification

- bash -n: 4 hooks + dsi.sh + mcl-state.sh clean
- Sıfır regresyon (262/0/2 her commit'te korundu)
- Smoke: state=2 / 5 / 22 / 7 / 99 senaryolarında `mcl_get_active_phase` doğru cevap döndürüyor

#### Production etkisi

v13.0.10'da kullanıcı şikayeti: spec onayı sonrası model 30 dosya yazdı, Aşama 5/6/7/8 atlandı. Kök sebep: state=7 sentinel + Layer B'nin `state=7` semantiğini "Aşama 7=UI Review askq only" olarak yorumlaması → 5 strike sonrası fail-open → unbounded writes.

v13.0.11'de:
- State artık gerçek faz değeri tutuyor (5, 6, 7, 8, 9 ardışık)
- Layer B her gerçek fazın `allowed_tools` listesini doğru uyguluyor
- Universal completeness döngüsü audit-driven sıralı ilerleme
- Faz atlama mimarsı seviyede yasaklandı

## [13.0.10] - 2026-05-07

### Layer B STRICT mode + audit-derived active phase (legacy state=7 sentinel fix)

**Real-world failure (kullanıcı raporu):** v13.0.9 üretim testi: backoffice projesi senaryosunda spec onayı sonrası model 30 dosya yazdı, Aşama 5/6/7/8 tamamen atlandı, Aşama 9 kod yazıldı ama TDD audit'leri yok, Aşama 10/11-18/19/20/21/22 atlandı. Layer B fire etmedi — model "tüm fazları unuttu."

**Kök sebep analizi:**

1. Legacy state machine: `mcl-pre-tool.sh:708` (JIT askq) ve `:803` (Bash audit emit) `asama-4-complete` audit'i emit edilince `state.current_phase=7` atıyor. Bu v10/v11 era catch-all sentinel — "post-spec-approval, EXECUTE phase". v12+ canonical numaralandırmada Aşama 7 = UI Review (askq only).

2. v13.0.9 Layer B `state.current_phase=7` görünce → gate-spec'te Aşama 7 spec'i (UI Review) → `allowed_tools=[AskUserQuestion]`. Model `Write` denerse normalde deny ederdi.

3. **AMA** v13.0.9'un **5-strike fail-open loop-breaker'ı** vardı. Model 5 deny aldıktan sonra Layer B fail-open yapıp tüm sonraki Write'lara izin veriyordu. 30 dosya bu kapıdan geçti.

4. Üstüne, state=7 sentinel'i v12+ canonical Aşama 5 (Pattern Matching) yerine Aşama 7'yi temsil ettiği için, model'in fazlardan geçmesi imkansızdı — universal completeness loop bile state=7'den başlayıp 8'e atlıyordu, Aşama 5/6 hiç değerlendirilmiyordu.

**v13.0.10 fix — iki cerrahi değişiklik:**

#### 1. Audit-derived active phase resolver (mcl-pre-tool.sh Layer B)

Layer B'nin Python verdict logic'i artık `state.current_phase=7` (legacy sentinel) gördüğünde audit log'dan **gerçek aktif fazı türetir**:

```python
sp = int(state_phase)
if sp == 7:
    # Legacy sentinel — derive from audit. Walk 5..22, first incomplete.
    derived = None
    for p in range(5, 23):
        if not phase_complete_basic(str(p)):
            derived = p
            break
    active_phase = str(derived) if derived else "22"
elif sp >= 1 and sp <= 22:
    active_phase = str(sp)  # canonical, use as-is
```

Sonuç: state=7 + asama-5 audit yoksa → active=5 → Aşama 5 allowed_tools=[] → model'in Write denemesi block.

Diğer state değerleri (1-6, 8-22) **canonical v12+ olarak yorumlanır**, audit-derive YAPILMAZ. Bu v13.0.9 testlerinin (T5-T8 state=9/10/6 ile) regression yapmamasını sağlar.

#### 2. STRICT loop-breaker — fail-open KALDIRILDI

v13.0.9'un 5-strike fail-open mekanizması Layer B için kaldırıldı. Yeni davranış:
- Her strike audit'lenir + `_mcl_loop_breaker_count` artar
- 5+ strike sonrası → **block KALMAYA devam eder** + `phase-allowlist-tool-escalate` audit emit edilir (idempotent — turn başına 1 kez)
- Activate hook bir sonraki turda escalation audit'i okur ve kullanıcıya görünür uyarı enjekte eder (`PHASE_ALLOWLIST_ESCALATE_NOTICE`)

Escalate notice 3 çözüm yolu sunar:
1. Doğru fazın audit'ini emit et (gate-spec'e bak)
2. Skip-eligible faz ise `mcl_audit_log asama-N-skipped reason=<somut>`
3. `/mcl-restart` → state ve faz akışı sıfırdan

**Sonuç:** Üretimde model 30-dosya dump yapamaz. 5 deny sonrası user uyarılır, block kalır, geliştirici müdahale eder.

#### REASON metni iyileştirmesi

Eski: "Aşama 7 aktif iken `Write` tool'una izin verilmez" (state value, yanıltıcı)
Yeni: "Audit'ten türetilen aktif faz: Aşama 5 (state.current_phase=7 legacy değer). `Write` tool'una bu fazda izin verilmez."

#### Out of Scope (v13.0.11'e ertelenen)

- ❌ **Aşama 9 TDD enforcement** — `current_phase=9` (gerçek v12+) iken `asama-9-ac-{i}-red` audit'i emit edilmeden Write/Edit. Mevcut Layer B Aşama 9'da Write'a izin veriyor; TDD discipline ayrı enforcement gerektiriyor.
- ❌ **Aşama 6 UI Build mandatory check generalize** — v13.0.8 specific lens var; UI flow detected ama `asama-6-end` yok durumunda generalize edilmedi.
- ❌ **Legacy state machine migration** — `current_phase=7` sentinel'ini `current_phase=5` ile değiştirmek 4 yerde değişiklik + `mcl_get_active_phase` mapping güncelleme; çok dosya etkiliyor, riskli. v13.1'e ertelendi.

#### Verification

- bash -n: 4 hooks + dsi.sh clean
- 9 yeni unit test (`tests/cases/test-v1310-strict-allowlist-and-derive.sh`):
  - T1: state=7 + audit yok → derive active=5 + Write deny + REASON shows active_phase=5
  - T2: state=7 + asama-5-skipped → derive active=6 + frontend Write allow
  - T3: state=7 + asama-5-skipped + Edit src/api → derive active=6 + denied_paths deny
  - T4: STRICT 6/6 deny (NO fail-open)
  - T5: 5+ strike → escalate audit emitted
  - T6: state=9 canonical (NOT 7) + Edit → allow (no derive, no regress)
  - T7: state=10 canonical + AskUserQuestion → allow
  - T8: activate hook surfaces escalation notice
- Test baseline: 382 → **391 passed** / 24 failed (unchanged) / 2 skipped — sıfır regresyon

#### Realistic determinism estimate

v13.0.9 ~99% (production'da fail-open ile model 30-dosya dump yaptı, yani gerçek %50-60) → v13.0.10 ~99.5% **with strict mode**. Fail-open kapısı kapatıldı; kaçış valve = developer escalation (manual intervention), automatic bypass yok.

## [13.0.9] - 2026-05-07

### Determinism mimari değişikliği — single-phase view + phase allowlist + reference doc

**Problem:** v13.0.2'den v13.0.8'e kadar 8 ardışık release her biri spot-fix ekledi (Aşama 1 strict gate, Aşama 2 zero-gate synthesis, Aşama 4 askq gate, Aşama 6 server-without-browser, vb). Üretimde model hâlâ "Tamamlandı" deyip duruyor. Asıl mimari sorun: (a) attention decay (lost-in-the-middle, 54KB prompt'un orta-pipeline fazları silikleşiyor); (b) tool-level enforcement yok (model wrong-phase tool çağırabiliyor).

**Çözüm:** İki mimari kaldıraç + 1 referans doc.

#### Layer A — Single-phase PHASE SCRIPT (mcl-activate.sh + mcl-dsi.sh)

**Önceki:** Activate hook STATIC_CONTEXT'te 22 statik `━━━ Aşama N` bloğu (v13.0.2'de eklenen). Aşama 5-22 detayları her UserPromptSubmit'te yüklü → attention decay.

**Yeni:** Aşama 1-4 detaylı blokları korundu (askq prefix'leri version embed eder, exact format gerekir). Aşama 5-22 explicit blokları kaldırıldı, yerine TEK referans satırı: `<mcl_active_phase_directive>` block'una yönlendir.

`<mcl_active_phase_directive>` her turda dinamik render edilir (`_mcl_dsi_render_active_phase` yeni helper):
- AKTİF FAZ: Aşama N — `<name>` (skill file, görev, emit pattern, skip)
- SONRAKİ FAZ: Aşama N+1 preview
- TÜM FAZLAR: kompakt 6-satır 22-faz indeksi (current marker `← AKTİF`)
- Header: NO MID-PIPELINE STOP RULE

**Sonuç:** Prompt size 54,646 → 50,456 char (-4,190 static, +1,400 dinamik = net -2,800 char). Daha önemli: model'in attention odağı tüm 22 faz listesi yerine ŞU AKTİF FAZ'a yöneliyor.

#### Layer B — Phase allowlist + denied_paths (mcl-pre-tool.sh + gate-spec.json)

`gate-spec.json` her faza yeni alan kazandı:
- `allowed_tools`: Bu fazda izin verilen mutating tool'lar (Write/Edit/MultiEdit/NotebookEdit/AskUserQuestion/TodoWrite arasından)
- `denied_paths`: Tool izinli olsa bile glob pattern eşleşince block (Aşama 6 backend yollarını yasaklıyor)
- `phase_marker_audits`: Faz aktivite işareti (Layer C için altyapı, v13.1)

**Global-always-allowed tools** (her fazda izinli, gate-spec'e bakılmıyor): Read, Glob, Grep, LS, WebFetch, WebSearch, Task, Skill, Bash. Investigation valves + audit-emit always available.

**Per-phase enforcement (örnek):**
- Aşama 9 (TDD) `allowed_tools`: `[Write, Edit, MultiEdit, NotebookEdit, TodoWrite]` — AskUserQuestion DEĞİL → Aşama 10 askq açmak için önce phase advance şart
- Aşama 6 (UI Build) `allowed_tools`: `[Write, Edit, MultiEdit, NotebookEdit, TodoWrite]` + `denied_paths`: `[src/api/**, src/server/**, prisma/**, models/**, ...]` — frontend yazılır, backend yasak
- Aşama 10 (Risk Review) `allowed_tools`: `[AskUserQuestion, Edit, Write, MultiEdit, TodoWrite]` — askq + risk-fix tool'ları açık
- Aşama 21/22 (Localized Report, Completeness): mutating tool yok (sadece Bash audit emit)

**Decision dispatcher** (mcl-pre-tool.sh:1148): yeni REASON_KIND'ler `phase-allowlist-tool` + `phase-allowlist-path` → DECISION=deny + 5-strike loop-breaker.

**Fast-path düzeltmesi** (line 588): AskUserQuestion + TodoWrite artık fast-path'i geçip Layer B'ye ulaşıyor (önceki v'ler exit 0 ile by-pass ediyordu).

#### Layer E — `docs/llm-attention-failure-patterns.md` referans doc

17 LLM agent anti-pattern + counter-mechanism + MCL coverage tablosu. Devtime checklist (hook logic değil): yeni özellik tasarlarken / üretim failure analizinde "bu pattern'i hangi mekanizmayla kapsadık" cevabı.

3 known gap işaretli: #7 halüsinasyon, #15 reward hacking, #17 context kirliliği.

#### Out of Scope (v13.1'e ertelenen)

- ❌ **Layer C — Checkpoint ritual.** Plan'da explicit "asama-N-complete olmadan N+1 tool yasak" gate vardı. Layer B'nin `allowed_tools` kontrolü zaten bunu büyük ölçüde sağlıyor (current_phase=N iken Aşama N+1'e özgü tool'lar genelde izinsiz). Layer C eklemek redundant olurdu — v13.1'de production data'sıyla değerlendirilir.
- ❌ **Layer D — Stop hook full validation generalize.** Mevcut v13.0.6/0.7/0.8 lens'leri (Aşama 6 server-browser, Aşama 2 zero-gate, Aşama 6 strict) korunmuş halde çalışıyor. Generalize etmek mevcut testleri etkileyebilir; v13.1'de "bilmiyorum" valve + 5-strike loop-breaker ile birlikte alınacak.
- ❌ Pattern #7/15/17 (open gaps) — v13.1.

#### Verification

- **Test baseline:** 361 → **382 passed** / 24 failed (değişmedi) / 2 skipped — sıfır regresyon
- 21 yeni unit test (`tests/cases/test-v1309-active-phase-allowlist.sh`):
  - T1-T3: Layer A active phase render (markers, EN variant, last-phase no-next)
  - T4-T10: Layer B phase allowlist (deny:tool, deny:path, allow patterns, global-always-allowed)
  - T11: Integration (activate hook injects `<mcl_active_phase_directive>`, prompt < 55KB)
- bash -n: 4 hooks + dsi.sh clean
- Prompt size: 50,456 char (54,646'dan -7.7%)

#### Critical files

- `hooks/mcl-activate.sh` — PHASE SCRIPT replace (Aşama 5-22 static blocks → dynamic injection wiring)
- `hooks/lib/mcl-dsi.sh` — `_mcl_dsi_render_active_phase` yeni helper (PHASE_META dict, EN/TR labels)
- `hooks/mcl-pre-tool.sh` — phase allowlist branch + REASON_KIND dispatcher genişlemesi + fast-path düzeltmesi
- `skills/my-claude-lang/gate-spec.json` — allowed_tools + denied_paths + phase_marker_audits her faza
- `docs/llm-attention-failure-patterns.md` — YENİ referans doc

#### Realistic determinism estimate

v13.0.8 ~98-99% → v13.0.9 ~99% (Layer B hard gate + Layer A attention focus). Layer C/D v13.1'e ertelendi — eğer üretimde Layer A+B yeterli değilse o zaman ele alınır.

## [13.0.8] - 2026-05-07

### Aşama 6 lens hardened — full invariant enforcement (block:neither + path-aware regex)

**Real-world failure (kullanıcı raporu):** Production session — model frontend dosyalarını yazdı, `npm install` (paket kurulumu) çalıştırdı, `node -e 'console.log(...)'` test komutu çalıştırdı, "Tamamlandı" deyip durdu. **Sunucuyu hiç başlatmadı, tarayıcıyı hiç açmadı.** v13.0.6 lens'i sadece "server STARTED + browser MISSING" durumunu yakalıyordu; "neither" durumunu yakalamıyordu.

**Aşama 6 spec (MCL_Pipeline.md):**
> "Front-end dummy data ile yapılır. Proje ve tüm bağımlılıkları **ayağa kaldırılır**. Proje **otomatik olarak tarayıcıda açılır**."

3 invariant: (a) frontend yazıldı, (b) sunucu çalıştırıldı, (c) tarayıcı açıldı. v13.0.6 sadece (b)→(c) bağımlılığı zorluyordu; v13.0.8 hem (b) hem (c) varlığını zorluyor.

#### Mekanizma

`_mcl_asama_6_server_browser_check` (mcl-stop.sh) güncellemeleri:
- **Scan scope**: last-assistant-turn → **session-wide** (tüm assistant turn'leri session_start'tan beri). Multi-turn workflow'ları desteklemek için (turn 1 kod yaz, turn 2 install, turn 3 server+browser).
- **Output artırıldı** 4 değere:
  - `ok` — server + browser her ikisi de session içinde mevcut
  - `block:no-server` — browser açıldı ama server hiç başlatılmadı (yeni)
  - `block:no-browser` — server başlatıldı ama browser açılmadı (v13.0.6'dan)
  - `block:neither` — her ikisi de eksik (yeni — kullanıcının senaryosu)
- **Server regex path-aware**: `node\s+(?:[\w./\-]*/)?(?:server|index|app|...)` — `node ./src/index.js`, `node backend/main.js` gibi path-prefixed varyantları kapsıyor (eski regex sadece direct keyword'leri yakalıyordu).
- **Branch'e göre özel REASON**: 3 ayrı block kindi için ayrı talimat (no-server / no-browser / neither). Audit tag'leri de farklı: `asama-6-server-not-started-block`, `asama-6-server-without-browser-block`, `asama-6-server-and-browser-missing-block`.

`block:neither` REASON model'e şunu söyler:
- `npm install` paket kurulumu — sunucu BAŞLATMAZ
- `node -e` test komutu — sunucu DEĞİL
- Sunucu çalıştır: `npm run dev` / `node server.js` / `flask run` / vb. (run_in_background:true)
- Sleep + `open http://localhost:<port>` (macOS) / `xdg-open` (Linux)
- `asama-6-end` audit emit
- Aşama 7 askq

#### STRICT mode preserved

Loop-breaker yok. Fail-open yok. Aşama 6 active iken her stop'ta:
- BOTH server + browser cumulative session'da mevcut DEĞİLSE → block
- `asama-6-end` veya `asama-6-skipped` audit emit edilmediyse block
- Test T9 (5 ardışık stop) hâlâ doğrular

#### Out of Scope (kasıtlı)

- ❌ "Sunucu çalışıp çalışmadığını network probe ile doğrulama" — model'in çalıştırdığı komutu güveniyoruz, network probe overhead/complexity
- ❌ Diğer Aşama'lar için benzer "evidence required" lens — v13.0.6 single targeted exception'ı genişletmiyoruz, başka mid-task abandonment pattern'leri ayrı kararlar gerektirir

#### Verification

- bash -n: 4 hook + dsi.sh clean
- 14 unit test (test-v1306 dosyasına T13+T14 eklendi):
  - T13: real-world npm install + node -e + "Tamamlandı" → block:neither + spesifik REASON + distinct audit tag
  - T14: node ./src/index.js path-form → server regex doğru match
- T10 v13.0.6 davranışından v13.0.8 strict davranışa güncellendi (no-server-no-browser → block, intentional)
- Test baseline: 357 → **361 passed** / 24 failed (unchanged) / 2 skipped — sıfır regresyon

#### Production simulation (kullanıcı senaryosu)

User session: backoffice projesi, model dosyaları yazdı + npm install + node -e tests + "Tamamlandı" → durdu.

v13.0.6'da: lens fire etmedi (server_started=false, "block" sadece server-started+no-browser durumunda).

v13.0.8'de: lens `block:neither` döndürür → Stop hook decision:block + REASON model'e tam talimat verir → model bir sonraki turda `npm run dev` + `open http://localhost:3000` + `asama-6-end` audit emit etmek zorunda. Audit emit edilmezse hâlâ block.

## [13.0.7] - 2026-05-07

### Aşama 2 zero-gate synthesis — auto-complete when nothing to ask

**Real-world failure trigger (kullanıcı raporu):** "faz 2 soracak bişey bulamazsa asama-2-complete yapmalı." Production'da gözlenen pattern: model Aşama 2'yi prose olarak yürüyor (7 boyutu zihinde sınıflıyor, hepsini SILENT-ASSUME buluyor), `precision-audit` Bash audit'ini emit etmiyor, GATE askq da açmıyor. Gate engine `_mcl_gate_check 2` `incomplete` döner (precision-audit yok), universal loop ilerlemez, phase=2 stuck.

**Çözüm:** Stop hook'ta hedefli synthesis. Model Aşama 2'de hiçbir audit/askq evidence üretmemişse, hook synthetic precision-audit emit eder (core_gates=0), universal loop bunu görüp `asama-2-complete` ile devam eder.

#### Trigger koşulları (hepsi current session'da, `AND`)

1. `current_phase = 2`
2. `summary-confirm-approve` audit present (Aşama 1 tamamlandı)
3. NO `precision-audit` audit (model dimension scan emit etmedi)
4. NO MCL `Faz 2 / Phase 2 / Aşama 2 / Etape 2 / ...` AskUserQuestion in last assistant turn (model GATE sormadı) — 14-dilli regex
5. NO `asama-2-complete` audit (idempotent)

Hepsi tutarsa synthesize:
```
precision-audit | stop-auto | core_gates=0 stack_gates=0 assumes=7 skipmarks=0 stack_tags= skipped=false synthesized=true
asama-2-zero-gate-synthesis | stop-auto | reason=no-precision-audit-no-faz2-askq
```

Sonra v13.0 universal loop bu yeni audit'i okur, gate engine'in `auto_complete_check: no_gates_or_skipped` logic'i (v13.0.1'den) "complete" döner, loop `asama-2-complete | stop-auto | gate=passed` emit eder ve phase 2→3 advance eder.

#### Safe by construction

- Synthesis sadece model **HİÇBİR Aşama 2 evidence üretmemişse** fire eder (audit yok + askq yok + complete yok).
- Eğer model GATE bulup askq açmışsa (T3) veya audit emit etmişse (T2) → synthesis fire etmez, model'in akışı respect edilir.
- Eğer Aşama 2 zaten `asama-2-complete` ile bitmişse (T6) → idempotent, fire etmez.
- Eğer phase=2 değilse (T4) veya Aşama 1 tamamlanmamışsa (T5) → fire etmez.

#### Verification

- bash -n: 4 hook + dsi.sh + state libs clean
- 10 yeni unit test (`tests/cases/test-v1307-asama2-zero-gate-synthesis.sh`):
  - T1: classic synth path → phase 2→3 + audit chain
  - T2-T7: 6 farklı bypass koşulu (model audit emitted, GATE askq, phase=1, no Aşama 1, already complete, EN prefix)
- Test baseline: 347 → **357 passed** / 24 failed (unchanged) / 2 skipped — sıfır regresyon
- Production simulation: model "All dimensions silent-assume" prose-only response → synth + auto-complete + phase advance (T1 doğrulamış)

#### Realistic determinism estimate

v13.0.6 ~98-99% → v13.0.7 ~99% (Aşama 2 zero-gate stuck pattern eliminate). Model'in audit emit etmemesi gibi behavior gap'lerini hook sentezliyor; pre-hoc + post-hoc synthesis kombinasyonu.

## [13.0.6] - 2026-05-07

### Aşama 6 server-without-browser STRICT lens (post-hoc — single targeted exception)

**Real-world failure trigger:** Production session — model `node server.js` ile sunucu başlattı, ardından "Sunucu çalışıyor. Tarayıcıyı açıyorum:" yazıp **durdu**. Tool çağrısı yapmadı. Pre-hoc fiziksel olarak yakalayamaz: PreToolUse model'in çağırmadığı tool'a fire etmez.

**Mimari değişiklik:** v13.0.2'deki "post-hoc gerekmesin" direktifi **bu spesifik pattern için** yumuşatıldı. Kullanıcı kararı: "minimal stop hook lens ama katı olsun." Tek targeted post-hoc lens, başka pattern eklenmedi.

#### Mekanizma

`hooks/mcl-stop.sh` yeni helper `_mcl_asama_6_server_browser_check`:
- Transcript'in son assistant turundaki Bash tool_use komutlarını tarar
- **Server-start regex** (yaygın stack'ler): `npm/pnpm/yarn (run )?(dev|start|serve)`, `node server/index/app/dist/...`, `nodemon`, `deno`, `bun`, `python -m http.server/flask/manage.py runserver/uvicorn`, `flask run`, `fastapi dev`, `uvicorn`, `gunicorn`, `php -S`, `php artisan serve`, `rails server`, `dotnet run/watch`, `go run`, `cargo run`, `mvn spring-boot:run`, `gradle bootRun`
- **Browser-open regex**: `open <url>` (macOS), `xdg-open <url>` (Linux), `start <url>` (Windows), `cmd /c start`, `powershell Start-Process`, `python -m webbrowser`, `google-chrome <url>`, `firefox <url>`
- Server detected, browser absent → return "block"

Main flow branch (mcl-stop.sh:642 öncesi):
- Tetiklenir: `current_phase=6` OR `ui_sub_phase=BUILD_UI`
- Bypass: `asama-6-end` / `asama-6-skipped` / `asama-6-complete` audit'lerinden biri current session'da emit edilmişse
- Block decision: `decision:block` + REASON model'e adım adım talimat (open komutu + asama-6-end audit + Aşama 7 askq)

#### STRICT mode

**Loop-breaker yok. Fail-open yok.** Diğer benzer block mekanizmaları (UI review skip, quality review pending, open-severity) 3 strike sonrası fail-open yapar; bu lens **kasıtlı olarak yapmaz**. Kullanıcı direktifi: "katı olsun". Model browser açmadıkça veya `asama-6-skipped` audit emit etmedikçe block kalkmaz. Test T9 5 ardışık stop ile bunu doğrular.

#### Out of Scope (kasıtlı)

- ❌ Diğer mid-task abandonment pattern'leri (server start ≠ tek failure mode'u — model "test çalıştırıyorum:" deyip durabilir, "deploy ediyorum:" deyip durabilir vb.) — her biri ayrı targeted lens gerektirir, blanket lens yapılmaz
- ❌ PostToolUse-time enjeksiyon (server start sonrası "şimdi de browser aç" notice) — Stop hook block daha güçlü
- ❌ Loop-breaker ekleme — strict directive'e aykırı; model browser açana dek block sürdürülür

#### Verification

- bash -n: 4 hook clean
- 12 yeni unit test (`tests/cases/test-v1306-asama6-server-browser.sh`):
  - T1-T2: server-only block, server+browser bypass
  - T3: chained `node server.js & sleep 2 && open <url>` aynı Bash içinde
  - T4: Linux `xdg-open` variant
  - T5-T6: `asama-6-end` / `asama-6-skipped` audit bypass
  - T7: phase=9 (Aşama 6 değil) → dormant
  - T8: legacy `ui_sub_phase=BUILD_UI` (current_phase başka) → fires
  - T9: **STRICT** 5 ardışık stop, hepsi block (fail-open yok)
  - T10-T12: edge cases (ls only, flask, pnpm)
- Test baseline: 335 → **347 passed** / 24 failed (unchanged) / 2 skipped — sıfır regresyon

#### Realistic determinism estimate

v13.0.5 ~96-98% (pre-hoc) → v13.0.6 ~98-99% (Aşama 6 mid-task gap kapatıldı). Diğer mid-task abandonment patterns hâlâ açık. Her biri için ayrı lens kararı kullanıcıya kalmış (LLM instruction-following ceiling realistic'tir).

## [13.0.5] - 2026-05-07

### 3-Layer pre-hoc deterministic enforcement — fast-skip / spec-skip protection

**Real-world failure trigger:** Production session — geliştirici "backoffice projesi yapacağım..." dedi, model **doğrudan Write(package.json)** denedi (Aşama 1-4 atlandı). PreToolUse Write block fire etti (mevcut MCL LOCK), ardından model **Aşama 1 disambiguation, Aşama 2 precision-audit, Aşama 3 brief'i atlayarak direkt Aşama 4 prose spec emisyonuna** atladı. v13.0.4 DSI yeterli direktif sağlamadı.

**Kullanıcı kararı (option A):** Pre-hoc only — post-hoc safety net (Stop hook spec-detection block) eklenmedi.

#### Layer 1 — MCL LOCK conditional enrichment

`hooks/mcl-pre-tool.sh` mevcut `spec_approved=false` MCL LOCK'unun REASON metni audit-aware:
- Audit boş (yeni oturum, hiçbir Aşama 1-4 audit'i yok) → **enriched directive**: "Sirayla yap: (1) Asama 1 gelistirici niyeti, tek soru ya da SILENT-ASSUME ozet + summary-confirm-approve audit. (2) Asama 2 7 boyutluk precision audit + asama-2-complete. (3) Asama 3 engineering-brief. (4) Asama 4 spec emit + onay askq."
- Audit'te en az bir Aşama 1+ marker varsa → **original recovery message** (backward compat preserved — mevcut skip-block testleri etkilenmez).

Detection: Aşama 1+ markers = `asama-1-`, `summary-confirm-approve`, `asama-2-`, `asama-3-`, `asama-4-`, `precision-audit`, `engineering-brief`. Session boundary respect.

#### Layer 2 — AskUserQuestion @ Aşama 4 spec-approval gate

PreToolUse'da yeni branch (line ~292): TOOL_NAME=AskUserQuestion + question prefix `MCL <ver> | Faz 4 / Phase 4 / Aşama 4 / Etape 4 / ...` → audit'te `asama-2-complete` veya `precision-audit` aranır. Yoksa **block** + REASON: "Asama 4 spec onay AskUserQuestion'i acilamaz: precision-audit yok. Onceki spec emisyonunu unut. Sirayla: (1) Asama 2 (2) closing askq (3) Asama 3 brief (4) Asama 4 spec." Multilingual prefix support: `Faz / Phase / Aşama / Étape / Étape / Fase / フェーズ / 阶段 / 단계 / مرحلة / שלב / चरण / Tahap / Этап / Step`.

#### Layer 3 — DSI loud Aşama 1 ZORUNLU mode

`hooks/lib/mcl-dsi.sh`: phase=1 + audit boş → forbidden-list mode:
```
⛔ ASAMA 1 ZORUNLU — Henuz hicbir Asama 1 audit i emit edilmedi.
YASAK: Spec yazma. Write/Edit/MultiEdit cagirma. AskUserQuestion (Faz 4 spec onayi) acmaya kalkma.
ILK IS: Tek soru sor (one-question-at-a-time) VEYA SILENT-ASSUME ozet uret.
Sonra: Bash mcl_audit_log ile asama-1-question-N veya summary-confirm-approve audit i emit et.
Audit i seed eden Bash + Read/Glob/Grep/LS aracilari serbest. Mutating tools KILITLI.
```

EN loud variant da var (`ASAMA 1 MANDATORY` + `FORBIDDEN: emitting a spec`).

Phase=2/3/4'te audit boş bile olsa loud mode fire etmez (model muhtemelen orta-akışta, panik enjeksiyonu zararlı). Phase=1 + audit boş = `first turn fast-skip detected` heuristic.

#### Out of Scope (kasıtlı)

- ❌ Stop hook spec-emission detection + decision:block — post-hoc, kullanıcı direktifine aykırı
- ❌ AskUserQuestion deny on Faz 4 askq when items-declared missing (Aşama 10 değil bu, çakışma yok ama yine de skip)
- ❌ Prose `📋 Spec:` text detection in tool inputs — nadir vaka, belirsiz fayda
- ❌ Plain-text approval enforcement (model "onaylıyorum" yazınca audit-skip kontrolü) — post-hoc

#### Verification

- bash -n: 4 hook + dsi.sh clean
- 18 yeni unit test (`tests/cases/test-v1305-deterministic-gates.sh`) — L1×3, L2×4, L3×7 + edge case'ler
- Test baseline: 317 → **335 passed** / 24 failed (değişmedi) / 2 skipped — sıfır regresyon
- Production failure scenario simulated:
  1. Empty session, Write attempt → enriched MCL LOCK fires with "Sirayla yap: (1) Asama 1..."
  2. Even if model emits prose spec, AskUserQuestion for spec approval blocked by L2 gate (precision-audit missing)
  3. DSI banner her turn'de phase=1+empty-audit'i loud forbidden-list ile vurur

#### Realistic determinism estimate

v13.0.4 ~92-96% → v13.0.5 ~96-98%. Prose-spec gap (model markdown text olarak `📋 Spec:` yazarsa hiçbir hook yakalamaz) mimari sınır olarak kalır — bu pure prompt katmanın LLM instruction-following ceiling'i. %100 fiziksel olarak mümkün değil; en yakın yer burası.

## [13.0.4] - 2026-05-07

### Dynamic Status Injection (DSI) — focused per-turn phase status

v13.0.2 PHASE SCRIPT extension model'e tüm 22 fazı her turda gösteriyordu (uzun, generic). Model bunu re-parse etmek zorunda; cognitive load yüksek. **DSI bu sorunu çözer:** her UserPromptSubmit'te `mcl-activate.sh` mevcut faz durumunu dinamik olarak çıkarıp focused notice inject eder ("şu anda Aşama N'desin, şu kaldı, bu turda şunu emit et").

**Mimari:** Pre-hoc prompt-time injection — tool/stop time müdahale yok, kullanıcının "pre-hoc %100, post-hoc gerekmesin" direktifiyle uyumlu.

**Sınırsız-soru bölümleri için kritik (Aşama 10, 19):** risk/impact sayısı baştan bilinmez. `asama-10-items-declared count=K` audit'i K'yı sabitler. DSI K eksikse **MANDATORY directive** emit eder ("K bilinmeden dialog başlayamaz"). K varsa M/K progress + current pointer + next item audit name dinamik gösterir. Pointer = `max(resolved indices) + 1` audit-derived (state.json pointer carry yok, single source of truth = audit.log).

#### Yeni dosyalar

- **`hooks/lib/mcl-dsi.sh`** — Read-only Python helper. CLI-testable: `bash mcl-dsi.sh --cli --phase N --audit <log> --spec <json> --lang tr|en`. 6 gate type için ayrı renderer (single, section, list, iterative, substep, self-check). Fail-open: helper crash → tek satırlık diagnostic, hook hata vermez.
- **`tests/cases/test-v1304-dsi.sh`** — 26 unit test (T1-T14). Sınırsız-soru handling kritik: T3 (K missing → MANDATORY), T4 (K=8/0 → '#1'), T5 (K=8/4 → '#5'), T6 (K=8/8 → completed), T14 (K extension via re-emit).

#### Değişen dosyalar

- **`hooks/mcl-activate.sh`** — `DSI_NOTICE` block generation (line 1005 öncesi); FULL_CONTEXT chain'ine eklenir. Resolution chain: `$REPO_LIB/mcl-dsi.sh` → `$(dirname $0)/lib/mcl-dsi.sh`. Aşama 1-4 için minimal mode (cognitive overhead düşük), Aşama 5+ için full DSI. Partial spec recovery override: `state.partial_spec=true` → tüm faz status suspend.
- **VERSION** 13.0.3 → **13.0.4**, banner refs synced.

#### Per-phase rendering format

| Phase type | Format örneği |
|---|---|
| single (5/8/21) | "Bu turun zorunlu çıktısı: asama-5-skipped ya da asama-5-complete" |
| section (15-18/20) | "Bu turun zorunlu çıktısı: asama-15-end-green" |
| list (10/19) | "3/8 resolved, 5 pending. Şu anda görüşülen: #4. Bu turun zorunlu çıktısı: asama-10-item-4-resolved" |
| iterative (11-14) | "Scan: 3 issue → Fixed: 2/3 → Rescan due. Bu turun zorunlu çıktısı: asama-11-issue-3-fixed" |
| substep (9) | "AC 1/3: red ✓ green ✓ refactor ✗. Bu turun zorunlu çıktısı: asama-9-ac-1-refactor" |
| self-check (22) | "20/21 phases verified, 1 missing. Bu turun zorunlu çıktısı: deep-dive Aşama 21" |

#### Hard-enforce semantiği

Plan'da Q1 = hard onaylanmıştı. **Hard-enforce DSI'nin MANDATORY directive'iyle pre-hoc sağlanır** — PreToolUse deny eklenmedi. Gerekçe: tool-time deny post-hoc safety net, kullanıcı direktifine aykırı. DSI prompt-time mesajı yeterince prominent (ilk satır, ZORUNLU prefix, ne emit edileceği literal).

#### Out of Scope (kasıtlı)

- ❌ PreToolUse deny on Aşama 10/19 askq when items-declared missing — post-hoc, skip
- ❌ Tool whitelisting per phase — v13.1
- ❌ 14 dilli label tablosu (şu an sadece TR + EN; diğerleri EN fallback) — v13.1
- ❌ Multi-model verification subagent — v13.2 (eğer DSI yetersiz kalırsa)

#### Verification

- bash -n: 4 hook + dsi.sh clean
- 26 yeni unit test PASS
- Test baseline: 292 → **317 passed** / 24 failed (unchanged) / 2 skipped — zero regression
- Smoke: Aşama 10 K=8/3 → DSI block doğru render; total prompt 54266 chars (+184 vs v13.0.3)

## [13.0.3] - 2026-05-07

### Doc/spec sync — align all reference files with MCL_Pipeline.md (canonical 22-phase architecture)

`MCL_Pipeline.md` is the canonical source-of-truth for the phase
pipeline (22 phases since v12.0). Reference files had drifted:
- `skills/my-claude-lang.md` was stuck on v10/v11 numbering with
  duplicate `Aşama 8` headers and an obsolete `v11 # | v10 #`
  migration table
- `README.md` / `README.tr.md` had downstream prose still using
  pre-v11 phase numbers (`Aşama 6a/6b/6c`, `Aşama 8 risk`,
  `Aşama 10 impact`, `Aşama 11 verification`)
- `FEATURES.md` top function-model diagram listed only 12 phases
- User-facing hook strings (`REASON=`, `mcl-update` notice)
  surfaced old phase numbers to the developer

#### Changes

- **`skills/my-claude-lang.md`** — full 22-phase rewrite:
  function model 12 → 22, section headers retitled (`Aşama 6 UI Build`,
  `Aşama 7 UI Review`, `Aşama 8 DB Design`, `Aşama 9 TDD`,
  `Aşama 10 Risk`, `Aşama 11–18 Quality+Tests`, `Aşama 19 Etki`,
  `Aşama 20 Verify`, `Aşama 21 Localized`, `Aşama 22 Completeness`).
  Removed `v11 # | v10 # | sub-step` dual-numbering migration table.
- **`README.md` / `README.tr.md`** — downstream prose aligned
  (`Aşama 6a/6b/6c` UI sub-phase split → `Aşama 6 / 7 + Aşama 9
  backend wiring`; gate references `8 risk → 10 risk`,
  `10 impact → 19 impact`, `11 verify → 20 verify`)
- **`FEATURES.md`** — top function-model diagram regenerated;
  section headers retitled; inline rewrites for current behavior
  (Pattern Matching feeds Aşama 9 TDD; risk/impact dialog described
  with `asama-N-items-declared` audit-emit pattern; phase_review_state
  lifecycle clarified as Aşama 10/19 dialog gate)
- **`hooks/mcl-pre-tool.sh`** — pattern-scan REASON now references
  `Aşama 9 TDD`; scope-guard REASON now suggests `Aşama 10 risk`
- **`hooks/mcl-activate.sh`** — `mcl-update` notice now refers
  generically to `any of Aşama 1–22` (future-proof)
- **VERSION** 13.0.2 → **13.0.3**, banner refs synced

#### Out of Scope (kasıtlı)

- ❌ Internal hook comments referring to historical `Aşama 7+ TodoWrite`
  etc. (describe codebase history, not user-facing) — defer to v13.1
- ❌ `asama9-execute.md` / `asama9-tdd.md` consolidation — both files
  are complementary (execute discipline vs TDD cycle mechanics),
  intentional dual-file design
- ❌ Adding dedicated `Aşama 21` and `Aşama 22` sections to FEATURES.md
  body — function-model diagram + skill files cover them; deferred to
  doc-completion pass (v13.1)

#### Verification

- bash -n: 4 hook files clean
- Phase numbering grep: zero occurrences of `Aşama 6a/6b/6c`,
  `Aşama 7 — Kod`, `Aşama 8 — Risk`, `Aşama 10 — Etki`,
  `Aşama 11 — Doğrulama`, `Aşama 12 — Lokalize`, `Aşama 13 — Tam`
  in any of: README.md, README.tr.md, FEATURES.md,
  skills/my-claude-lang.md
- All H2/H3 phase headers (1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
  11–18, 19, 20, 21, 22) match MCL_Pipeline.md ordering

## [13.0.2] - 2026-05-07

### Pre-hoc PHASE SCRIPT extension — Aşama 5–22 explicit blocks + NO MID-PIPELINE STOP

v13.0/0.1'de model Aşama 5'ten sonra "kod yazdım, bitti" diyerek Aşama 6–22'yi atlayabiliyordu — activate hook PHASE SCRIPT Aşama 5+'ı tek paragrafta ad-listesi olarak veriyordu, görev direktifi/emit pattern/skip koşulu yoktu.

**Mimari karar (kullanıcı direktifi):** Pre-hoc katmanı %100 — post-hoc Stop hook block-on-incomplete safety net **kasıtlı olarak yok**. Prompt'un kendisi her fazın görevini, audit emit pattern'ini ve "Aşama 22'ye kadar STOP YOK" direktifini içeriyor.

#### Changes

**`hooks/mcl-activate.sh` STATIC_CONTEXT — PHASE SCRIPT genişletmesi:**
- Mevcut "Aşama 5+ — Execute" tek paragrafı **17 ayrı faz bloğuna** dönüştürüldü.
- Her blok: `━━━ Aşama N — <name> ━━━` başlık + skill file path + 1-2 satır görev + emit pattern + skip koşulu + sonraki faz direktifi.
- TOP-LEVEL DİREKTİF: `🛑 NO MID-PIPELINE STOP RULE` — Aşama 4 spec onayından sonra Aşama 22 tamamlanana kadar pipeline ortasında durmak yasak. AskUserQuestion gate'leri (Faz 7/10/19) doğal stop; diğerleri auto-progress.

**`hooks/mcl-activate.sh` — yeni `<mcl_constraint name="no-mid-pipeline-stop">`:**
- Constraint block PHASE SCRIPT'in TOP-LEVEL DİREKTİF'ini reinforces — `Kod bitti` / `test yazdım` / `review tamam` diyerek bitirmek = phase skip = quality regression.

**`hooks/mcl-activate.sh` self-critique constraint — 6. soru:**
- Mevcut 5 soruluk loop'a Aşama 5–22 için 6. soru eklendi: "Bu turun sonunda mevcut fazın gate-spec audit'i emit edildi mi? Bir sonraki fazın başlangıcı yapıldı mı?"
- AskUserQuestion turn'lerinde fire etmez (doğal stop).
- Aşama 1-4'te fire etmez (spec-approval gate yeterli).

#### Out of Scope (kasıtlı)

- ❌ **Stop hook block-on-incomplete enforcement.** Pre-hoc %100 hedefi — post-hoc fallback eklenirse pre-hoc'a güvensizlik sinyali olur. Kullanıcı direktifi.
- ❌ Skill MD migrations (Faz 11-14 scan/rescan emit'leri vs.) — v13.1
- ❌ Hard deny on `asama-N-complete` model emit — v13.1
- ❌ Test suite v12-era audit name güncellemeleri — v13.0.3

#### Verification

- bash -n: 5 hook clean
- Prompt content smoke: 24/24 markers (`━━━ Aşama 5..22 —`, NO MID-PIPELINE STOP, asama-N-skipped reason, asama-9-ac-, asama-10-items-declared, asama-11-rescan, asama-22-complete) + 4/4 new constraint markers
- tests/run-tests.sh: **292/24/2** baseline tutuldu (yeni test eklenmedi — sadece prompt değişti, davranışsal pre-hoc katman; runtime testleri etkilenmez)

#### Risks

- **LLM prompt instruction-following degrade** — uzun prompt instruction following oranını düşürebilir. Mitigation: TOP-LEVEL DİREKTİF prompt'un başına yakın yerleştirildi; her faz bloğu kısa (1-2 satır görev).
- **Token cost artışı** — ~5 KB ek per UserPromptSubmit. Mitigation: skill detayları skill dosyalarında kaldı; PHASE SCRIPT sadece "ne emit, ne sonra" iskeleti.
- **gate-spec.json ↔ PHASE SCRIPT senkronizasyon riski** — iki kaynak. Mitigation: emit pattern'leri gate-spec.json'dan birebir referans alındı.

Banner: MCL 13.0.1 → **MCL 13.0.2**.

## [13.0.1] - 2026-05-07

### Faz 2 conditional auto-complete — handles "no GATE questions" path

v13.0.0 cutover'da Faz 2'nin "tüm boyutlar SILENT-ASSUME, hiç GATE sorusu
yok" path'i stuck kalıyordu: AskUserQuestion atlanıyor → `asama-2-complete`
audit hiç emit edilmiyor → gate engine `incomplete` döndürüyor. v13.0
legacy fallback ile çalışıyordu (model `asama-2-complete` direkt emit
edebilir) ama v13.1 hard cutover'da fallback kalkar → kırılır.

#### Fix

Mevcut `precision-audit | asama2 | core_gates=N stack_gates=M ... skipped=<bool>`
audit'inin payload'ını parse et, conditional auto-complete uygula. Yeni
audit ismi YOK (yön tartışmasında "yeni precision-audit-no-gates audit'i"
yerine bu yol seçildi — daha temiz, deny exception gerekmiyor, tek kaynak).

#### Changes

**`hooks/lib/mcl-gate.sh`** — `single` evaluator'a iki opsiyonel field
desteği:
- `auto_complete_audit` — bakılacak audit ismi (örn. `precision-audit`)
- `auto_complete_check` — named check identifier

Mantık: önce `required_audits[_any]` kontrolü; complete dönmezse
`auto_complete_audit` payload'ını parse + named check çalıştır; check
geçerse complete.

İlk named check: `no_gates_or_skipped` — payload'ta `core_gates+stack_gates==0`
VEYA `skipped=true` ise true döner. Gelecek fazlar (Faz 5 pattern-skip,
Faz 8 db-skip) için kütüphane genişletilebilir.

**`skills/my-claude-lang/gate-spec.json`** — Faz 2 entry:
```json
"2": {
  "type": "single",
  "required_audits": ["asama-2-complete"],
  "auto_complete_audit": "precision-audit",
  "auto_complete_check": "no_gates_or_skipped"
}
```

**`tests/cases/test-v13-gate-spec.sh`** — 3 yeni test case:
- core_gates=0 stack_gates=0 → complete (Türkçe oturum, all SILENT-ASSUME)
- skipped=true → complete (English session safety valve)
- core_gates>0 + no asama-2-complete → incomplete (negative)

Hepsi PASS. Test baseline: v13.0.0 289/24/2 → v13.0.1 **292/24/2** (+3 PASS, 0 regression).

#### Smoke

- `bash -n hooks/lib/mcl-gate.sh` clean
- `python3 -c "import json; json.load(...)"` valid
- `bash tests/run-tests.sh` 292/24/2

#### Etkilenmeyen

- `required_audits` kontrolü hâlâ önce çalışır — `asama-2-complete` zaten
  emit edilmişse auto-complete dalı hiç çalışmaz, çakışma yok
- Faz 1, 3, 4, 5, 6, 7, 8 vb. diğer `single` faz'lar değişmedi
  (auto_complete_audit field'ı yoksa ek logic devreye girmez)
- v12 legacy fallback hâlâ aktif

Banner: MCL 13.0.0 → **MCL 13.0.1**.

## [13.0.0] - 2026-05-07

### Universal deterministic gate engine — v13.0 groundwork release

v13.0 introduces the **gate-spec engine**: a centralized state-machine
spec (`gate-spec.json`) + universal hook engine (`hooks/lib/mcl-gate.sh`)
that decides phase completeness from audit-log signals. Stop hook now
runs a **universal completeness loop** that walks `current_phase`
forward and auto-emits `asama-N-complete` + `phase_transition` when the
gate criteria for phase N are met. Pre-tool hook gains a **soft deny**
on model-emitted `phase_transition` and `asama-N-progression-from-emit`
(model can still emit `asama-N-complete` during the v13.0 bridge — full
hardening lands in v13.1 once skill MD migrations complete).

#### What's in v13.0

- **`skills/my-claude-lang/gate-spec.json`** — 22-phase spec with 6 gate
  types: `single`, `section`, `list`, `iterative`, `substep` (Faz 9
  TDD), `self-check` (Faz 22). Faz 6/7 corrected to `single-or-skip`
  (matches v12.0.0 file structure; brief's section interpretation
  rejected because v11.0.0 R1 had already collapsed 6a/6b/6c).
- **`hooks/lib/mcl-gate.sh`** — universal `_mcl_gate_check <phase>`
  function. Reads gate-spec, scans audit.log for required signals,
  returns `complete | incomplete | skipped`. Includes legacy v12
  fallback (any `asama-N-complete` audit triggers complete) so existing
  skill files keep working through the bridge.
- **`hooks/mcl-stop.sh`** — universal completeness loop replaces the
  hardcoded asama-8/9/10/11/12 progression blocks (v11/v12 era). Walks
  current_phase forward up to 22 iterations, auto-emits per-phase
  complete + phase_transition + state advance.
- **`hooks/mcl-pre-tool.sh`** — soft deny on `phase_transition` and
  `asama-N-progression-from-emit` model emits. `asama-N-complete` model
  emits remain ALLOWED in v13.0 (legacy bridge).
- **`tests/cases/test-v13-gate-spec.sh`** — 19 unit tests covering all
  6 gate types. New baseline: 289/24/2 (v12.0.0 was 270/24/2 — net +19
  passes, 0 new failures).

#### What's NOT in v13.0 (deferred)

- **Skill MD migrations to new emit patterns.** Faz 4
  (`asama-4-ac-count`), Faz 9 (RED/GREEN/REFACTOR triples), Faz 10/19
  (`items-declared` + per-item-resolved), Faz 11-14 (scan +
  issue-fixed + rescan): documented in gate-spec.json BUT skill files
  still emit legacy `asama-N-complete`. Gate engine handles via legacy
  fallback. Full migration → v13.1.
- **Hard deny on `asama-N-complete`.** v13.1 hardens once all skill
  MDs have migrated.
- **Test suite v13 audit name updates.** ~24 pre-existing failures
  unchanged. v13.0.1 cleanup release.
- **`risk_review_state` / `quality_review_state` removal.** Fields
  remain in state schema as deprecated/unused. v13.2 cleanup.

#### Bridge guarantees

1. **Existing v12 sessions continue to work.** Legacy `asama-N-complete`
   model emits remain valid; gate engine accepts them via fallback.
2. **Universal loop is idempotent.** If `asama-N-complete` already
   exists, hook skips re-emit (state still advances).
3. **Soft deny does not block legitimate flows.** Only `phase_transition`
   and `asama-N-progression-from-emit` are denied — model never had a
   reason to emit these directly.

#### Smoke verification

- `bash -n` clean across 4 modified hooks + new mcl-gate.sh
- `python3 -c "import json; json.load(open('skills/my-claude-lang/gate-spec.json'))"` valid
- `bash tests/cases/test-v13-gate-spec.sh` → 19/19 PASS
- End-to-end: state.current_phase=1 + summary-confirm-approve audit →
  stop hook auto-emits `asama-1-complete` → state advances to 2 → trace
  logs `phase_transition 1 2`. Verified.

#### Plan reference

`~/.claude/plans/g-zel-bi-plan-yap-iridescent-star.md` (v13.0 plan).
Brief: `MCL_v13_brief.md` (repo root).

Banner: MCL 12.0.1 → **MCL 13.0.0**.

## [12.0.0] - 2026-05-05

### v12.0 cutover — 22-phase pipeline with new Aşama 8 (DB design)

Insert a dedicated **Aşama 8 (DB Design)** phase between v11's
Aşama 7 (UI Inspection) and v11's Aşama 8 (TDD execute). Aşama 8+
shifts +1 across the entire pipeline; final phase becomes
**Aşama 22 (Completeness Audit, audits 1–21)**. Single-release
cutover — no v11 audit aliases (in-progress sessions start a fresh
session after upgrade, per the precedent set by v11.0.0).

#### Why a new DB design phase?

v11.0.0 systematic check kapsamı yeterliydi ama Aşama 12 (Performance)
ve Aşama 13 (Security) DB-specific concerns'i sadece N+1 / SQL-injection
seviyesinde tarıyordu. Index strategy / query plan / normalization is a
DESIGN concern that belongs BEFORE TDD writes queries, not AFTER as a
quality fix. v12 elevates DB design to a top-level phase that runs after
UI approval and before TDD.

#### Mapping (v11 → v12)

| v11 phase | v12 phase | File rename |
|---|---|---|
| Aşama 1–7 | Aşama 1–7 | unchanged |
| — | **Aşama 8 (NEW)** | `asama8-db-design.md` (new file) |
| Aşama 8 (TDD execute) | Aşama 9 | `asama8-tdd.md` → `asama9-tdd.md`, `asama8-execute.md` → `asama9-execute.md` |
| Aşama 9 (Risk Review) | Aşama 10 | `asama9-risk-review.md` → `asama10-risk-review.md` |
| Aşama 10 (Code Review) | Aşama 11 | `asama10-code-review.md` → `asama11-code-review.md` |
| Aşama 11 (Simplify) | Aşama 12 | `asama11-simplify.md` → `asama12-simplify.md` |
| Aşama 12 (Performance) | Aşama 13 | `asama12-performance.md` → `asama13-performance.md` |
| Aşama 13 (Security) | Aşama 14 | `asama13-security.md` → `asama14-security.md` |
| Aşama 14 (Unit) | Aşama 15 | `asama14-unit-tests.md` → `asama15-unit-tests.md` |
| Aşama 15 (Integration) | Aşama 16 | `asama15-integration-tests.md` → `asama16-integration-tests.md` |
| Aşama 16 (E2E) | Aşama 17 | `asama16-e2e-tests.md` → `asama17-e2e-tests.md` |
| Aşama 17 (Load) | Aşama 18 | `asama17-load-tests.md` → `asama18-load-tests.md` |
| Aşama 18 (Impact) | Aşama 19 | `asama18-impact-review.md` → `asama19-impact-review.md` |
| Aşama 19 (Verify+Mock) | Aşama 20 | `asama19-verify-report.md` → `asama20-verify-report.md` |
| Aşama 20 (Localized) | Aşama 21 | `asama20-localized-report.md` → `asama21-localized-report.md` |
| Aşama 21 (Completeness) | Aşama 22 | `asama21-completeness.md` → `asama22-completeness.md` |

15 file renames + 1 new file (`asama8-db-design.md`).

#### New skill — asama8-db-design.md

- **When it runs:** after Aşama 7 UI approval, before Aşama 9 TDD.
- **Soft-applicability:** skipped silently when no DB in scope
  (CLI tool, static site, no `prisma/`/`drizzle/`/`migrations/`,
  spec mentions no persistence). Audits emit
  `asama-8-not-applicable | reason=no-db-in-scope`.
- **Procedure:** 5 steps — read entity declarations from spec;
  3NF schema design with denormalization justified inline; index
  strategy by query pattern; ORM migration generation (detected
  by stack: Prisma/Drizzle/TypeORM/Django/AR/Alembic/SQL); query
  plan estimates for spec hot paths.
- **Forbidden:** application code, production data writes, schema
  decisions absent from spec, indexing every column.
- **Audit emit:** `asama-8-start`, `asama-8-end`,
  `asama-8-not-applicable`.

#### Hook updates

- `hooks/lib/mcl-state.sh:108` — validation widened `<= 21` → `<= 22`.
- `hooks/mcl-stop.sh` — audit name scanners shifted +1 across
  the board (asama-9-complete → asama-10-complete; asama-10-end
  → asama-11-end; asama-13-{ambiguous,resolved,autofix} →
  asama-14-*; etc.).
- `hooks/mcl-activate.sh` — `<mcl_core>` PHASE SCRIPT's
  `Aşama 7+ — Execute` block is now `Aşama 5+ — Execute` and
  lists the v12 phase chain (1–22) with the new Aşama 8 DB
  design callout.

#### What does NOT change

- mcl-askq-scanner.py classification — unchanged.
- Aşama 1–7 — unchanged (file names, audit names).
- Aşama 4 SPEC enforcement (📋 Spec block detection,
  asama-2-complete + spec-approve audit chain).
- Banner format / audit timestamp / state schema version (v3).

#### Bridge artifacts

- v10/v11-numbered tests reference older audit names; pre-existing
  baseline failures unrelated to v12. Future patch retires them as
  `test-v12-*`.
- README/README.tr.md historical sections (UI Build/Review
  Sub-Phases) reference the old 6a/6b/6c split; preserved as
  historical context.
- CHANGELOG entries before this one preserve their v11 (and earlier)
  phase numbers.

Banner: MCL 11.0.1 → **MCL 12.0.0**.

## [11.0.0] - 2026-05-05

### v11.0 cutover — 21-phase architecture is now the default

Eighth and final step of the v11.0 migration plan
(`~/.claude/plans/g-zel-bi-plan-yap-iridescent-star.md`). The v10
audit-name aliases that R5 and R6 introduced as a backward-compat
bridge are removed; the active hook scanners are migrated to v11
audit names; the banner everywhere becomes `MCL 11.0.0`. This is a
**major release** — semantic versioning's MAJOR bump. In-progress
v10.1.x sessions should start a fresh session after upgrade.

#### Architecture shift (recap)

| Pipeline phase | v10 | v11.0.0 |
|---|---|---|
| Gather | Aşama 1 | Aşama 1 |
| Precision audit | Aşama 2 | Aşama 2 |
| Translate | Aşama 3 | Aşama 3 |
| Spec emit | Aşama 4 | Aşama 4 |
| Pattern matching | Aşama 5 | Aşama 5 |
| UI build (dummy data) | Aşama 6a | Aşama 6 |
| UI inspection | Aşama 6b | Aşama 7 |
| TDD execute (+ backend wiring) | Aşama 6c + Aşama 7 | Aşama 8 |
| Risk review | Aşama 8 | Aşama 9 |
| Code review (auto-fix) | Aşama 9.1 | Aşama 10 |
| Simplify | Aşama 9.2 | Aşama 11 |
| Performance check | Aşama 9.3 | Aşama 12 |
| Security check (whole project) | Aşama 9.4 | Aşama 13 |
| Unit + TDD tests | Aşama 9.5 | Aşama 14 |
| Integration tests | Aşama 9.6 | Aşama 15 |
| E2E tests | Aşama 9.7 | Aşama 16 |
| Load tests | Aşama 9.8 | Aşama 17 |
| Impact review | Aşama 10 | Aşama 18 |
| Verification report + mock cleanup | Aşama 11 | Aşama 19 |
| Localized report | Aşama 12 | Aşama 20 |
| Completeness audit (audits 1–20) | Aşama 13 | Aşama 21 |

#### v10 audit aliases REMOVED (R5/R6 dual-emit lines deleted)

Each new quality skill file (`asama10-code-review.md` through
`asama17-load-tests.md`) and each renamed delivery skill file
(`asama9-risk-review.md`, `asama18-impact-review.md`,
`asama19-verify-report.md`, `asama20-localized-report.md`,
`asama21-completeness.md`) previously dual-emitted v11 audit names
alongside v10 alias names during the bridge period. R8 cutover
removes the v10 alias emit line from every skill file. Audits now
emit ONLY v11 names:

| Phase | v11 audit (kept) | v10 alias (removed) |
|---|---|---|
| Aşama 9 (Risk Review) | `asama-9-complete` | `asama-8-complete` |
| Aşama 10 (Code Review) | `asama-10-{start,end,not-applicable,ambiguous}` | `asama-9-1-*` |
| Aşama 11 (Simplify) | `asama-11-*` | `asama-9-2-*` |
| Aşama 12 (Performance) | `asama-12-*` | `asama-9-3-*` |
| Aşama 13 (Security) | `asama-13-{start,end,ambiguous,resolved,autofix}` | `asama-9-4-*` |
| Aşama 14 (Unit) | `asama-14-*` | `asama-9-5-*` |
| Aşama 15 (Integration) | `asama-15-*` | `asama-9-6-*` |
| Aşama 16 (E2E) | `asama-16-*` | `asama-9-7-*` |
| Aşama 17 (Load) | `asama-17-*` | `asama-9-8-*` and the cumulative `asama-9-complete` |
| Aşama 18 (Impact Review) | `asama-18-complete` | `asama-10-complete` |
| Aşama 19 (Verification Report) | `asama-19-complete` | `asama-11-complete` |
| Aşama 20 (Localized Report) | `asama-20-complete` | `localize-report` |
| Aşama 21 (Completeness Audit) | `asama-21-complete` | `asama-13-complete` |

Final grep across skill files confirms zero v10 alias emit lines
remain.

#### Hook scanner migration

`hooks/mcl-stop.sh` `_mcl_asama_9_substeps_complete` helper
(line 877+) now scans v11 audit names (`asama-10-end` ..
`asama-17-end`, plus the `not-applicable` variants) instead of the
v10 sub-step names (`asama-9-1-end` .. `asama-9-8-end`). The
helper still emits `asama-9-complete` as the cumulative signal;
this signal name is reused — it now means "Risk Review (v11)
complete" instead of "Quality+Tests cumulative (v10)" — but
existing v10.1.5 progression-from-emit logic at line 1015 keys on
the same name and continues to operate.

#### Banner everywhere → MCL 11.0.0

VERSION file, README.md, README.tr.md, FEATURES.md, skills/my-claude-lang.md
Activation Indicator + AskUserQuestion prefix + Schema-V banner +
Function Model section, and hooks/mcl-activate.sh PHASE SCRIPT
inline body — all updated together.

#### What does NOT change

- mcl-state.sh `current_phase` schema. Still bounded `<= 21`
  (R4 widening) and still uses coarse buckets (1, 4, 7, 11). The
  documented phase numbers shifted; the integer storage stayed.
- Spec block detection (`📋 Spec:` line-anchored token) and the
  Aşama 4 SPEC enforcement at PreToolUse / Stop hook.
- Aşama 1 summary-confirm-approve flow and Aşama 2 closing
  precision-confirm askq (R5 of v10.1.14 plan; both still gate
  the same way).
- Audit emit timestamps (UTC ISO 8601 since v10.1.13).
- AskUserQuestion classification (`spec-approve`, `precision-confirm`,
  `summary-confirm`, `ui-review`, `other`). All five still operate.

#### Bridge artifacts that survive in v11.0.0

- Hook source comments mentioning sub-step names (`asama-9-1`,
  `asama-9-4-ambiguous`, etc.) still describe enforcement helpers
  in terms of v10 names where the helper code happened to keep
  v10 names as scan keys. These are documentation-only and have
  no runtime impact.
- README/README.tr.md "UI Build / Review Sub-Phases (since 6.2.0)"
  prose describing the old 6a/6b/6c three-way split is preserved
  as historical context. The v11 vision diagram at the top of the
  README is the canonical pipeline.
- v10-named test files (`tests/cases/test-v10-*.sh`) remain;
  they will be retired or rewritten as `test-v11-*` in a future
  patch release.

Banner: MCL 10.1.23 → **MCL 11.0.0**.

## [10.1.23] - 2026-05-05

### v11.0 migration R7 — Aşama 19 mock-cleanup logic activates

Seventh step of the v11.0 migration. The mock-data cleanup that v10
embedded inside Aşama 6c (BACKEND_INTEGRATION) and that R2 fenced as
inert prose inside `asama8-tdd.md` is now **active in
`asama19-verify-report.md`**. Aşama 19 (Verification Report) is the
v11 architecture's natural location for the cleanup — per the v11
vision pipeline diagram in README.md, "Mock data is removed from
the project" right after the verification table.

#### Changes

- `skills/my-claude-lang/asama8-tdd.md` — the fenced `<!-- v11:
  will move to Aşama 19 -->` block (originally migrated from
  asama6c-backend.md:72-84 in R2) is removed. Replaced with a
  short marker noting that the cleanup is now active in
  asama19-verify-report.md.
- `skills/my-claude-lang/asama19-verify-report.md` — new
  "Mock Data Cleanup" section appended at the end. Sections:
  - **Detection** — three indices (path-based via `find
    __fixtures__/` / `mocks/`, symbol-based via `grep MOCK_/mock_`,
    state-toggle index via `grep useSearchParams.*state` /
    `<select.*mock`).
  - **Per-fixture handling** — for each candidate fixture, grep
    importers; zero importers = safe delete; test-only importers
    = KEEP; component importers remaining = STOP and surface as
    Aşama 21 Open Issue (means Aşama 8 backend wiring was
    incomplete).
  - **What to KEEP** (never delete) — types under `src/types/**`,
    test-imported fixtures, test-only `__fixtures__/` dirs.
  - **What to DELETE** — `?state=...` URL-param hooks,
    `<select>` mock-state toggles, orphan `__fixtures__/*.fixture.*`,
    truly orphan `MOCK_*` / `mock_*` consts.
  - **Audit emit** — three new audits
    `asama-19-mock-cleanup-started`,
    `asama-19-mock-cleanup-end`,
    `asama-19-mock-cleanup-skipped`. Audit-only — `mcl-pre-tool.sh`
    does NOT gate any tool on these audits in v10.1.23 (advisory).

#### Why advisory only in this release

The detection logic is non-trivial — `grep` for importers can
miss dynamic imports, the path conventions vary across stacks, and
the state-toggle index is heuristic. R7 lands the prose and the
audit shape; v10.2.x or v11.x can upgrade to hard enforcement once
production sessions validate the detection accuracy. Audit-only
landing means a session that fails to clean up shows the gap in
Aşama 21 Open Issues but doesn't block tool execution.

#### What does NOT change

- mcl-pre-tool.sh — no new path gates.
- mcl-stop.sh — no new audit-emit auto-progression. The new audits
  are recorded but not used for state transitions.
- The cleanup is purely a developer-visible report item; if the
  model skips it, only Aşama 21 Open Issues surfaces the miss.

Banner: MCL 10.1.22 → MCL 10.1.23.

## [10.1.22] - 2026-05-05

### v11.0 migration R6 — tail rename (Impact, Verify, Localized, Completeness) → Aşama 18/19/20/21

Sixth step of the v11.0 migration. The four delivery-side phases at
the end of the pipeline rename to their v11 numbers; each renamed
file gains a v10-audit-name dual-emit so existing v10 enforcement
keeps working through the bridge. Aşama 9 (Risk Review) also picks
up dual-emit at this release so its `asama-8-complete` v10 emit is
joined by `asama-9-complete` (R4 only renamed the file; R6 adds
the audit alias).

#### Renames

| v10 file | v11 file | v11 phase number |
|---|---|---|
| `asama10-impact-review.md` | `asama18-impact-review.md` | Aşama 18 |
| `asama11-verify-report.md` | `asama19-verify-report.md` | Aşama 19 |
| `asama12-translate.md` | `asama20-localized-report.md` | Aşama 20 |
| `asama13-completeness.md` | `asama21-completeness.md` | Aşama 21 |

mcl_phase tags + bulk path replace across 10 referencing files
(hooks/mcl-activate.sh PHASE SCRIPT, mcl-stop.sh comments, umbrella,
mcl-finish.md, asama8-tdd.md, plus the renamed files themselves and
two test cases).

#### Audit dual-emit added (v10 alias preserved during bridge)

Each renamed file now emits BOTH the v11 audit name and the v10 alias:

| Phase | v11 audit | v10 alias |
|---|---|---|
| Aşama 9 (Risk Review) | `asama-9-complete` | `asama-8-complete` |
| Aşama 18 (Impact Review) | `asama-18-complete` | `asama-10-complete` |
| Aşama 19 (Verification Report) | `asama-19-complete` | `asama-11-complete` |
| Aşama 20 (Localized Report) | `asama-20-complete` | `localize-report` |
| Aşama 21 (Completeness Audit) | `asama-21-complete` | `asama-13-complete` |

The v10 aliases keep mcl-stop.sh's existing progression-from-emit
helpers (lines 1034, 1041, 1048) operating during the bridge.

#### Self-phase header updates inside renamed files

- `# Aşama 10: Post-Risk Impact Review` → `# Aşama 18: Post-Risk
  Impact Review (was Aşama 10 in v10)`
- `# Aşama 11: Verification Report` → `# Aşama 19: Verification
  Report (was Aşama 11 in v10)`
- `# Aşama 12: Localize Report` → `# Aşama 20: Localized Report
  (was Aşama 12 in v10)`
- `# Aşama 13: Completeness Audit` → `# Aşama 21: Completeness
  Audit (was Aşama 13 in v10) — audits phases 1–20`

#### What does NOT change

- mcl-stop.sh logic — the existing progression-from-emit helpers
  scan v10 audit names, which still appear via the dual-emit. R8
  cutover migrates the helpers to scan v11 names only.
- `mcl_get_active_phase()` mapping — still returns v10 numbers
  ("11" for verify, "12" for localize). R8 cutover updates this to
  return v11 numbers.
- The `asama-13-skipped-warn` enforcement (the existing
  Aşama 13 skip-block helper) still scans `asama-13-complete`. The
  dual-emit ensures that audit name appears whenever the renamed
  Aşama 21 file emits its completion.

#### Tail-end namespace clears in this release

Before R6, the `asama10-*`, `asama11-*`, `asama12-*`, `asama13-*`
prefixes had two file occupants each (R5's quality phases under v11
numbering, plus the v10 delivery phases). After R6, each prefix has
only one occupant (the v11 quality phase). Namespace coexistence
that R5 introduced is now resolved.

Banner: MCL 10.1.21 → MCL 10.1.22.

## [10.1.21] - 2026-05-05

### v11.0 migration R5 — Quality phase split (Aşama 9.x → Aşama 10–17)

Fifth step of the v11.0 migration. The most structurally significant
release before R8 cutover: the monolithic `asama9-quality-tests.md`
skill (274 lines) is split into 8 dedicated phase skill files, one
per quality concern, matching the v11 vision pipeline diagram.
Backward-compat aliases protect in-progress sessions.

#### Strategy

Each new skill file (`asama10-code-review.md` through
`asama17-load-tests.md`) is **self-contained**: its own audit emit
instructions, its own soft-applicability rules. To preserve v10
hook compatibility (mcl-stop.sh's `asama-9-complete` auto-emit
helper, the `asama-9-4-ambiguous` / `asama-9-4-resolved`
must-resolve gate at line 1115+), each new file emits BOTH the v11
audit name AND the v10 alias. R8 cutover removes the v10 emit
lines and migrates hook code to scan v11 names only.

#### New skill files (8)

| Phase | File | Replaces | Scope difference vs v10 |
|---|---|---|---|
| Aşama 10 | `asama10-code-review.md` | sub-step 9.1 | unchanged scope |
| Aşama 11 | `asama11-simplify.md` | sub-step 9.2 | unchanged |
| Aşama 12 | `asama12-performance.md` | sub-step 9.3 | unchanged |
| Aşama 13 | `asama13-security.md` | sub-step 9.4 | **scope widens** — runs on whole project (v10 ran on changed files only); per the v11 vision pipeline |
| Aşama 14 | `asama14-unit-tests.md` | sub-step 9.5 | unchanged |
| Aşama 15 | `asama15-integration-tests.md` | sub-step 9.6 | unchanged |
| Aşama 16 | `asama16-e2e-tests.md` | sub-step 9.7 | unchanged |
| Aşama 17 | `asama17-load-tests.md` | sub-step 9.8 | unchanged + emits the cumulative `asama-9-complete` v10 alias at end of pipeline |

#### Audit aliases ADDED (per skill file dual-emit)

For phase N in 10..17 (v11) ↔ sub-step (N-9) in 9.1..9.8 (v10):

```
mcl_audit_log "asama-N-start"           ↔  mcl_audit_log "asama-9-(N-9)-start"
mcl_audit_log "asama-N-end"             ↔  mcl_audit_log "asama-9-(N-9)-end"
mcl_audit_log "asama-N-not-applicable"  ↔  mcl_audit_log "asama-9-(N-9)-not-applicable"
mcl_audit_log "asama-N-ambiguous"       ↔  mcl_audit_log "asama-9-(N-9)-ambiguous"
```

Special for Aşama 13 (security):
```
mcl_audit_log "asama-13-resolved"  ↔  mcl_audit_log "asama-9-4-resolved"
mcl_audit_log "asama-13-autofix"   ↔  mcl_audit_log "asama-9-4-autofix"
```

Special for Aşama 17 (last phase): the cumulative `asama-9-complete`
v10 emit happens once at the end of the pipeline, so existing v10
hook enforcement (mcl-stop.sh:867+ auto-emit helper, mcl-stop.sh:974+
progression-from-emit transition) continues to operate.

#### Deleted

- `skills/my-claude-lang/asama9-quality-tests.md` (274 lines —
  content distributed across the 8 new files).

#### Other changes

- `skills/my-claude-lang.md` (umbrella) — section "Aşama 9: Quality
  + Tests" rewritten as "Aşama 10–17: Quality + Tests pipeline
  (split into 8 dedicated phases in v11.0 R5)" with a v10↔v11
  mapping table pointing to the 8 new skill files.
- `tests/cases/test-v10-1-5-asama-9-progression-pilot.sh:162` —
  test's `_skill=...asama9-quality-tests.md` updated to point at
  `asama17-load-tests.md`, which is now the file that mandates the
  v10 cumulative `asama-9-complete` emit. Test continues to assert
  the same invariant; comment notes R8 will retire this test.

#### What does NOT change

- mcl-stop.sh logic. The `asama-9-complete` auto-emit (line 916–918),
  the `asama-9-progression-from-emit` transition (line 1015), and the
  open-severity must-resolve gate (line 1115+) all keep operating —
  the v10 alias dual-emit ensures the audit names they scan still
  appear in the audit log.
- mcl-pre-tool.sh enforcement. Skip-block codes still keyed on
  `asama-N-skip` family; no change.
- Existing tests that scan for `asama-9-N-*` audit lines keep
  passing because dual-emit produces those lines.

#### Bridge-period notes

- During R5 → R7, every quality-phase audit log entry will appear
  TWICE — once with the v11 name, once with the v10 alias. This
  doubles the audit.log size for those phases but preserves
  enforcement. R8 cutover halves it back by removing the alias
  emits.
- Hook source comments mentioning sub-steps `9.1`, `9.2`, etc.
  (mcl-stop.sh, mcl-pre-tool.sh) still describe the underlying
  enforcement logic accurately because the dual-emit still
  produces `asama-9-N-*` audits. R8 retitles those comments.
- Aşama 8 risk-dialog escalation pattern: when a security finding
  is ambiguous in Aşama 13, the model escalates back to Aşama 9
  (Risk Review). Today this re-opens `risk_review_state="running"`
  and the existing dialog runs. No code change needed in R5 — the
  enum state still maps via the bucket integer (current_phase=7).

Banner: MCL 10.1.20 → MCL 10.1.21.

## [10.1.20] - 2026-05-05

### v11.0 migration R4 — State machine widening + Aşama 8 (Risk Review) → Aşama 9

Fourth step of the v11.0 migration. First release that touches
**executable hook code** (R1-R3 were skill-file-only). Two coupled
changes that share a release:

1. **State machine widening.** `mcl-state.sh` now accepts
   `current_phase` integers in `[1, 21]` instead of `[1, 11]`.
   The integer remains a **coarse bucket** (1, 4, 7, 11 today —
   GATHER, SPEC_REVIEW, EXECUTE, DELIVER); the widening just
   makes future bucket additions (R5-R7) representable without
   another schema bump.
2. **Risk Review skill rename.** `asama8-risk-review.md` →
   `asama9-risk-review.md` to match the v11 numbering.

#### Changes

- `hooks/lib/mcl-state.sh:108` — `assert 1 <= obj["current_phase"]
  <= 11` becomes `<= 21`.
- `hooks/lib/mcl-state.sh:13-21` — schema-v3 comment block notes
  the v11 widening and points at the migration plan.
- `hooks/lib/mcl-state.sh:386-401` — `mcl_get_active_phase`
  comment block updated to reflect the v11 bucket map (the
  function logic itself is unchanged; comments now show what each
  bucket maps to in v11 numbering).
- `skills/my-claude-lang/asama8-risk-review.md` →
  `skills/my-claude-lang/asama9-risk-review.md`.
- Self-phase header inside the renamed file: `# Aşama 8:
  Post-Code Risk Review` → `# Aşama 9: Post-Code Risk Review
  (was Aşama 8 in v10)`. The "When Aşama 8 Runs" section
  retitled "When Aşama 9 Runs" and reframed for the v11 phase
  chain.
- mcl_phase tag inside the renamed file: `name="asama8-risk-review"`
  → `name="asama9-risk-review"` (handled by bulk path replace).
- Bulk path replace `asama8-risk-review` → `asama9-risk-review`
  across 8 referencing files: hooks/mcl-activate.sh (PHASE
  SCRIPT prompt body), skills/my-claude-lang.md umbrella,
  asama3-translator.md, all-mcl.md (STEP catalog),
  mcl-tag-schema.md, check-up.md,
  tests/cases/test-v10-1-5-asama-8-progression-pilot.sh.

#### Smoke tests for state widening

Boundary tests via `_mcl_state_valid`:

| Input `current_phase` | Expected | Actual |
|---|---|---|
| 1 | OK | OK |
| 11 | OK | OK |
| 21 | OK | OK (v11 widening confirmed) |
| 22 | FAIL | FAIL |
| 0 | FAIL | FAIL |

#### What does NOT change

- The integer in state.json is still 1, 4, 7, or 11 in practice
  (no v11 bucket fills 12-21 yet — those land in R5-R7).
- Hook enforcement keyed on phase integer — `current_phase=7`
  still means EXECUTE; no logic shift.
- Audit names. `asama-8-*` audits (precision-audit-block,
  asama-8-emit-missing, asama-8-complete) still emit under the
  same names. R5/R6 add aliases that map them to v11 numbers;
  R8 removes the v10 names.
- The `risk_review_state` field. Its enum (`null` → `running`
  → `pending` → `complete`) stays as-is; only the prose
  describing it inside the skill file moved from "Aşama 8" to
  "Aşama 9" framing.

#### Bridge-period notes

- Hook source comments mentioning "Aşama 8" (mcl-stop.sh,
  mcl-pre-tool.sh) still describe the risk-review enforcement.
  These will be retitled when their code paths are touched in
  R5 (quality split — same hooks).
- The renamed `asama9-risk-review.md` still has many "Aşama 8"
  references in its body (lines beyond the header). Those refer
  to the phase's own historic name and will be flushed in R8
  cutover when the v10 alias removal happens. The header and
  "When Aşama 9 Runs" block are correct for v11; the rest is
  honest historical documentation.

Banner: MCL 10.1.19 → MCL 10.1.20.

## [10.1.19] - 2026-05-05

### v11.0 migration R3 — Aşama 7 (TDD execute) → Aşama 8 rename

Third step of the v11.0 migration. Renames the TDD execute skill
files from the v10 number 7 to the v11 number 8, clearing the
`asama7-*` namespace that R1 left in mixed state. Path-only rename
plus first-line phase-header updates inside the renamed files.
Audit names unchanged — `asama-8-complete` audit already matched
v11 Aşama 8 in v10's flow because the integer `current_phase=7`
was always the coarse "code+TDD" bucket; only the documented
phase number shifts.

#### Changes

- `skills/my-claude-lang/asama7-execute.md` →
  `skills/my-claude-lang/asama8-execute.md`
- `skills/my-claude-lang/asama7-tdd.md` →
  `skills/my-claude-lang/asama8-tdd.md`
- mcl_phase tag inside each renamed file: `asama7-execute` →
  `asama8-execute`, `asama7-tdd` → `asama8-tdd`.
- Bulk path replace of `asama7-execute` → `asama8-execute` and
  `asama7-tdd` → `asama8-tdd` across 6 referencing files
  (skills/my-claude-lang.md umbrella, asama11-verify-report.md,
  asama7-ui-review.md, asama6-ui-build.md, plus the two renamed
  files themselves).
- Self-phase-label updates inside the renamed files:
  `asama8-execute.md`: title `# Aşama 7: ...` → `# Aşama 8: ...`,
  flow-split prose updated to describe Aşama 8 as the merging
  phase. `asama8-tdd.md`: title `# Aşama 7 TDD: ...` →
  `# Aşama 8 TDD: ...`, opening paragraph reframed for v11
  numbering. **Deeper internal references to "Aşama 7" inside
  these files (lines 21, 51, 65, 71, 209, 217, 234, 276, 299,
  311 of asama8-tdd.md) intentionally left alone — they are
  about the phase's own internal mechanics and will be rewritten
  in R4 when the state machine is widened. Adjusting them in R3
  would have produced semantic drift at the boundary with
  asama8-risk-review.md (currently still numbered Aşama 8 in
  v10; becomes Aşama 9 in R4).**
- Umbrella section header `## Aşama 7: Code + TDD` →
  `## Aşama 8: Code + TDD (was Aşama 7 in v10 architecture)`
  with a pointer noting that asama8-tdd.md Step 5 absorbs the
  v10 Aşama 6c backend wiring.

#### What does NOT change

- mcl-state.sh `current_phase` enum still bounded `<= 11`. The
  integer mapping is unchanged (bucket 7 is still "code+TDD",
  whether it documents Aşama 7 or Aşama 8). Widening to 21
  happens in R4.
- mcl-stop.sh, mcl-pre-tool.sh, mcl-activate.sh logic. Audit
  names stay the same; SKIP-BLOCK keys stay the same.
- All v10 tests keyed on `asama-8-complete`,
  `asama-8-emit-missing` etc. continue to operate against the
  renamed v11 files because audit names didn't shift.

#### Bridge-period notes (v11 plan R4 forward)

- `asama8-risk-review.md` is currently the v10 Aşama 8 (Risk
  Review) skill file. After R3 completes, the directory listing
  shows: asama8-execute.md (TDD execute, v11), asama8-tdd.md
  (TDD overlay, v11), asama8-risk-review.md (Risk Review,
  v10) — three files starting with `asama8-` but only two
  describe the same v11 phase. R4 renames asama8-risk-review.md
  → asama9-risk-review.md to clear this.
- `asama8-tdd.md` Step 5 (Backend Wiring) still references
  "Aşama 7" in its body prose ("inherits all of asama7-execute.md
  discipline"). The cross-reference path was sed-updated to
  asama8-execute.md, but a few "Aşama 7" labels remain because
  they refer to the phase's own historic name; they will be
  flushed when R4 reorders the state machine bucket map.

Banner: MCL 10.1.18 → MCL 10.1.19.

## [10.1.18] - 2026-05-05

### v11.0 migration R2 — Aşama 6c → Aşama 8 fold (skill-content merge)

Second step of the v11.0 architecture migration. Moves the
backend-wiring responsibility (formerly its own Aşama 6c skill
file) into the TDD execute phase (`asama7-tdd.md`). The fold is
content-only: no audit names change, no hook behavior modified,
no state machine touched. The `ui_sub_phase=BACKEND` enum value
is preserved — `mcl-pre-tool.sh` still lifts the UI-BUILD path
restriction at the same gate; only the documentation describing
that gate moves location.

#### Changes

- Deleted `skills/my-claude-lang/asama6c-backend.md`.
- Appended a new `## Step 5 — Backend Wiring (UI Flow Path)`
  section to `skills/my-claude-lang/asama7-tdd.md` containing
  the migrated body: entry condition, path discipline change,
  procedure (grep + swap + env), type contract preservation,
  phase behavior notes (Aşama 11 must-test items, downstream
  Aşama 8 / 10 / 11 chain).
- **Mock-cleanup section fenced.** The "Remove Dev-Only Bits"
  block from `asama6c-backend.md:72-84` is wrapped in an HTML
  comment marked `<!-- v11: will move to Aşama 19, do not
  execute here -->`. The prose stays in the file as a parking
  spot; R7 will move it into the Aşama 19 verification report
  skill where it actually executes. The fence prevents the model
  from running these deletions during Aşama 7/8.
- Updated `skills/my-claude-lang.md` (umbrella) — removed the
  `Aşama 6c BACKEND: read asama6c-backend.md` pointer, replaced
  the "Aşama 6c (BACKEND)" bullet in the UI-flow narrative with
  a "Backend wiring — folded into asama7-tdd.md Step 5" note.
- Updated `skills/my-claude-lang/asama7-execute.md` — the
  sub-phase list no longer points at the deleted file; describes
  the fold inline.
- Updated `skills/my-claude-lang/asama7-ui-review.md` — dispatch
  table "Approve" row, "Visual-Inspect Loop" closing line, and
  "Exit" section all updated to reference the merged backend
  wiring step instead of the deleted Aşama 6c.
- Updated `skills/my-claude-lang/asama6-ui-build.md` — UI-BUILD
  LOCK deny reason describes the new gate location.
- Updated `skills/my-claude-lang/all-mcl.md` STEP-40b entry —
  exits to "TDD execute backend wiring" instead of Aşama 6c.

#### What does NOT change

- `mcl-state.sh` schema and validation are untouched. The
  `ui_sub_phase` field still flows `null → BUILD_UI → REVIEW →
  BACKEND`; only the prose explanation of `BACKEND` moved.
- `mcl-stop.sh` and `mcl-pre-tool.sh` enforcement is identical.
  Comments in those files that say "Aşama 6c" describe the
  enum behavior and stay accurate (the enum is still `BACKEND`);
  they will be retitled when those code paths are touched in
  R3 / R4.
- Audit names. No audit was emitted by an Aşama 6c step in v10
  except via the generic Aşama 7 audit chain; that chain
  continues to operate.
- Tests — `test-v10-1-asama8-9-enforcement.sh`,
  `test-v10-1-5-asama-8-progression-pilot.sh` and other v10
  Aşama-7-keyed tests still pass because audit names are
  unchanged.

#### Bridge-period notes (v11 plan R3 forward)

- `asama7-tdd.md` now contains both TDD methodology (its
  original duty) and backend-wiring procedure (formerly
  Aşama 6c). When R3 renames the file to `asama8-tdd.md`, both
  duties land under v11 Aşama 8 as designed.
- The umbrella's UI-flow section still uses v10 phase numbers
  in places (e.g., "Aşama 7 UI_REVIEW" — currently a v11 label
  pinned in v10 territory because R1 already renamed). When R3
  resolves the asama7-* namespace, the umbrella will get a
  pass to settle remaining inconsistencies.
- The mock-cleanup fence in `asama7-tdd.md` is the explicit
  parking spot R7 will pick up. Until then, mock cleanup
  remains the developer's responsibility (per the v10
  manual-enumerate convention) — exactly the same UX as v10.

Banner: MCL 10.1.17 → MCL 10.1.18.

## [10.1.17] - 2026-05-05

### v11.0 migration R1 — UI sub-phase rename (skill files only)

First step of the v11.0 architecture migration plan
(see `~/.claude/plans/g-zel-bi-plan-yap-iridescent-star.md` and
the v11.0 vision sections of README.md / README.tr.md). This
release is **skill-file-rename only** — no audit names change,
no state machine touched, no hook behavior modified. R1 is
intentionally the smallest, safest first step.

#### Changes

- `skills/my-claude-lang/asama6a-ui-build.md` →
  `skills/my-claude-lang/asama6-ui-build.md`
- `skills/my-claude-lang/asama6b-ui-review.md` →
  `skills/my-claude-lang/asama7-ui-review.md`
- Sibling directories renamed in lockstep:
  `asama6a-ui-build/` → `asama6-ui-build/`
  `asama6b-ui-review/` → `asama7-ui-review/`
- `<mcl_phase name="asama6a-ui-build">` →
  `<mcl_phase name="asama6-ui-build">` (and the 6b counterpart)
- Visible labels in renamed skill files: `Aşama 6a` → `Aşama 6`,
  `Aşama 6b` → `Aşama 7`. Ditto in the umbrella
  `skills/my-claude-lang.md` UI sub-phase pointer block and in
  `asama7-execute.md`'s cross-reference list.
- `ui_sub_phase` enum value `BUILD_UI`/`REVIEW`/`BACKEND`
  unchanged — those are code-level identifiers, not phase
  numbers. State machine behaves identically.
- `asama6c-backend.md` left intact — folds into Aşama 8 in R2.

#### Bridge-period notes

- `skills/my-claude-lang/asama7-execute.md` and
  `skills/my-claude-lang/asama7-tdd.md` (current Aşama 7 = TDD
  execute) coexist alongside the newly-renamed
  `asama7-ui-review.md` for one release. Both point at the same
  numerical phase from different vintages: v11 says Aşama 7 =
  UI inspection; v10 still has Aşama 7 = TDD execute. The
  umbrella file documents both during this bridge window. R3
  resolves the conflict by renaming `asama7-execute.md` /
  `asama7-tdd.md` to `asama8-*`.
- README/README.tr.md/FEATURES.md still have a "UI Build /
  Review Sub-Phases (since 6.2.0)" section that describes the
  old 6a/6b/6c three-way split. The v11 vision diagram at the
  top of each README contradicts that section; both are present
  during the bridge. R2 (folding 6c into Aşama 8) is the
  natural place to drop the old sub-phase description; not
  changed in this release to keep R1's diff minimal.
- Hook comments in mcl-stop.sh, mcl-pre-tool.sh, and
  mcl-stack-detect.sh that mention "Aşama 6a / Aşama 6b" are
  unchanged — they describe code paths keyed on `ui_sub_phase`
  enum values, which still operate identically. Comments will
  be updated when their underlying logic is touched in R3/R4.

#### What does NOT change

- `mcl_audit_log "asama-N-..."` audit names — none renamed.
- `current_phase` integer in state.json — still bounded
  `1 <= current_phase <= 11`. Widening to 21 happens in R4.
- Skip-block enforcement, AskUserQuestion intent classification,
  spec-approval gate — all keyed on audit names that didn't
  change, so behavior is identical to v10.1.16.

Banner: MCL 10.1.16 → MCL 10.1.17.

## [10.1.16] - 2026-05-03

### Critical: Stop hook unbound-variable crash fixes

A real-world v10.1.15 test session surfaced two `set -u` violations
in `hooks/mcl-stop.sh` that caused the Stop hook to fail on every
turn. Symptoms: phase state never advanced past whatever it was at
the moment of the bug, repeated assistant text blocks appeared in
the UI (Claude Code retries on Stop hook error), and downstream
phase-skip enforcement misfired against the wrong phase context.

#### Bug 1 — `TRANSCRIPT_PATH` used before assignment

`mcl-stop.sh:223` called `_mcl_spec_presence_audit "$TRANSCRIPT_PATH"`
but `TRANSCRIPT_PATH` was assigned at line 231 (parsed from
`RAW_INPUT`). With `set -u` (line 21), the unbound reference
triggered every Stop hook invocation. The two-line ordering must
have been correct in an earlier version and got swapped during a
later refactor — no single commit obviously responsible, the order
was wrong by the time it surfaced in production.

Fix: moved the spec-presence-audit call (lines 223-227) to AFTER
the `RAW_INPUT` and `TRANSCRIPT_PATH` assignment block. Same logic,
correct ordering. Added a comment marking the v10.1.16 fix.

#### Bug 2 — `_PR_PHASE` referenced but never set

`mcl-stop.sh:616` formatted the `phase-review-pending` audit detail
using `${_PR_PHASE}` but no such variable existed in the file —
typo for `_PR_ACTIVE_PHASE` (set at line 568). Pure rename bug;
fix is a single substitution.

#### Why the user-visible symptoms were severe

When the Stop hook crashes, Claude Code does NOT advance phase
state, does NOT update `risk_review_state`, does NOT advance
`current_phase`. Every subsequent turn begins with stale state.
The Aşama 8 SKIP-BLOCK gate (since v10.1.7) reads `risk_review_state`
to decide whether to fire — with the hook crashing, the gate
fired against the wrong phase context. In the user's session, this
manifested as `MCL ASAMA 8 SKIP-BLOCK` firing during what was
behaviorally an Aşama 6b UI revision, with confusing recovery
prompts.

Fixing the crash does NOT alone resolve the broader question of
"how should MCL handle follow-up edits after the full pipeline
completed?" — that is a separate design discussion (one-spec-per-task
boundary detection). The crash fix is a precondition: until the
Stop hook runs cleanly, no phase-context reasoning has a chance.

#### Smoke test

Mock `{"transcript_path":"/tmp/nonexistent","session_id":"smoke-1"}`
piped to `bash hooks/mcl-stop.sh` now exits 0 with no stderr
output. Pre-fix: crashed with two unbound-variable errors.

Banner: MCL 10.1.15 → MCL 10.1.16.

## [10.1.15] - 2026-05-03

### Preventive layer — activate hook prompt rewrite with canonical phase script

A second real-world test exposed a different class of bug than v10.1.14
addressed. With v10.1.14 deployed, the developer (Ümit) ran the same
backoffice prompt. The model now passed Aşama 2's deterministic gate
(`asama-2-complete` fired correctly), but emitted the SPEC body in
Turkish — Aşama 3 (Translate) was skipped entirely. v10.1.14's gate
caught the wrong-process-1 (no Aşama 2 confirm) but not wrong-process-2
(Aşama 3 skipped, body in dev's language).

Ümit's diagnosis was sharp:

> "ya herşeyi sonradan kontrol etmeye odaklanıyorsun. baştan sorun
>  çıkmayacak şekilde düzelt."

i.e. "stop fixing things post-hoc; fix them so the problem doesn't
arise in the first place." This is the framing every prior fix
violated — v10.1.7 (spec-approval-block), v10.1.12 (Aşama 1 skip-block),
v10.1.14 (asama-2-complete) — they were all detection-and-block at
mutation time. The model would still drift; the hook would just catch
the drift later.

#### Root cause (preventive frame)

The activate hook's `<mcl_core>` inline prompt was the leverage point
all along. The current prompt:

- Used non-canonical legacy labels (`PHASE 1.5`, `PHASE 1.7`) that
  did not match the skill files (`asama2-precision-audit.md`,
  `asama3-translator.md`).
- Buried Aşama 2, Aşama 3, and Aşama 4 inside one giant rule (rule 5)
  that ran 800+ words.
- Did NOT name Aşama 3 at the same visual level as the others; the
  "Engineering Brief" was a sub-paragraph of rule 5.
- Did NOT explicitly state "SPEC BODY IS ENGLISH" as a top-level
  directive — only implied via "translate then spec".
- Did NOT give explicit closing-askq title prefixes per phase (only
  "MCL <ver> | " was specified, not "Faz 1 — Niyet özeti onayı:" /
  "Faz 2 — Precision-audit niyet onayı:" / "Faz 4 — Spec onayı:").

The model invented its own labels (`Faz 1 — Niyet`, `Faz 2 — Belirsizlik
Taraması`, `Faz 3 — Spec`, `Faz 4 — Spec İncelemesi`) because the
prompt did not enforce the canonical numbering. With the model's
custom labeling, Aşama 3 had no slot — and so it was skipped.

#### Fix

**`hooks/mcl-activate.sh`** — `<mcl_core>` rules block fully rewritten.
The new structure:

- Rule 1: Banner. Unchanged.
- Rule 2: Language. Tightened: code is English; communication, section
  headers, and AskUserQuestion bodies are dev-language.
- Rule 3: PHASE SCRIPT — the canonical Aşama 1 → 2 → 3 → 4 sequence
  rendered as four visually-separated blocks (`━━━ Aşama N — <name>`).
  Each block lists: skill file to read, what to do, the exact closing
  AskUserQuestion title prefix, the audit emitted on approve, and
  what is forbidden. Aşama 3 is now its own visible block with the
  explicit "OUTPUT IS ENGLISH" directive at top — impossible to miss
  or merge with another phase.
- Rule 4: PHASE LABEL DISCIPLINE — explicit list of canonical phase
  labels in 14 languages (Faz/Phase/Fase/Étape/フェーズ/단계/阶段/
  مرحلة/שלב/चरण/Tahap/Этап/...) and prohibition on inventing labels.
- Rule 5: All code English / all communication dev-language; refers
  back to Aşama 1's disambiguation triage.

The prompt is ~1000 chars longer net, but each phase is visually
distinct and the canonical numbering is at the top of each block.
The model cannot drift because the script tells it exactly what to
emit, with what title, in what order.

**`skills/my-claude-lang/asama1-gather.md`** — closing askq title
prefix template now includes the explicit `Faz 1 — Niyet özeti onayı:`
form (TR calibration) with parallel EN/ES translations and a note
about the parser dependency.

**`skills/my-claude-lang/asama3-translator.md`** — new "Why this phase
exists (preventive frame)" section explaining the dependency chain:
Aşama 3 is the only phase that converts dev-language parameters into
the English parameter set Aşama 4 emits as the SPEC body. Skipping
Aşama 3 is the most common failure mode that puts the SPEC body in
the wrong language. No detection-only enforcement — the preventive
contract is in the prompt itself.

**`skills/my-claude-lang/asama4-spec.md`** — Rules section rewritten:
new explicit "SPEC BODY IS ENGLISH — non-negotiable" directive (rule
4); closing askq title prefix template now lists `Faz 4 — Spec onayı:`
(TR) / `Phase 4 — Spec approval:` (EN) / equivalent; added the
asama-2-complete + spec-approve audit chain as a precondition for
Aşama 7 advance.

#### Why this is preventive, not detective

Hook detection (PreToolUse blocks, Stop-hook audits) catches drift
AFTER the model has already produced wrong output. The user sees the
wrong output; the hook then refuses the next mutation. Cycle of bad
UX.

Prompt-level instruction shaping prevents drift BEFORE it happens.
The model reads the canonical phase script at the top of every turn,
sees explicit closing-askq titles, sees the English-body directive
named explicitly, and produces correct output the first time. The
hook layer (asama-2-complete gate, spec-approval-block) becomes a
safety net for residual model error — not the primary mechanism.

This is what MCL fundamentally is: prompt engineering as model
behavior shaping. v10.1.7 / v10.1.12 / v10.1.14 lost sight of that.
v10.1.15 brings it back.

Banner: MCL 10.1.14 → MCL 10.1.15.

## [10.1.14] - 2026-05-03

### Aşama 2 deterministic gate — `asama-2-complete` audit replaces v10.1.12 OR-list

Real-world test session exposed a structural gap in the
v10.1.12 Aşama 1 SKIP-BLOCK design. The user (Ümit) ran a
fresh greenfield project request through MCL: the model emitted
"Faz 1 — Niyet Tespiti" as a plain-text paragraph, jumped to
"Faz 2 — GATE Soruları" with ad-hoc gate questions, and emitted
"Faz 3 — Mühendislik Şartnamesi" with a `📋 Spec:` block. The
developer typed `onay`. v10.1.12 SKIP-BLOCK fired correctly at
Write time but only because none of the three OR-list audits
(`summary-confirm-approve`, `precision-audit`, `asama-1-complete`)
existed yet. The deeper observation, made by the developer,
was that `📋 Spec:` is an MCL classifier-reserved token and
should not have been emitable at all before Aşama 2's
precision audit ran.

#### Root cause

Two layers stacked:

1. **Model behavior:** Aşama 1's closing summary-confirm
   AskUserQuestion was skipped — model wrote a plain-text
   intent paragraph and jumped to Aşama 2-style gate
   questions in the same turn.
2. **Hook permissiveness:** the v10.1.12 SKIP-BLOCK accepted
   any of three audits as evidence of intent gathering. This
   was too loose — none of the three independently proves the
   precision audit ran. The model could legitimately emit
   `precision-audit` (Aşama 2 entry) without ever reaching the
   closing dimension scan, and SPEC would unblock.

The deterministic-GATE design principle (per Ümit) requires
exactly one audit to gate SPEC emission: one that fires only
when the developer has explicitly approved the precision-
audited intent at the end of Aşama 2. Per the canonical phase
chain (Aşama 1 → Aşama 2 → Aşama 3 → Aşama 4), this single
audit implicitly proves Aşama 1 also ran.

#### Fix

**`hooks/lib/mcl-askq-scanner.py`**:

- New `precision-confirm` intent classification.
- New `PRECISION_CONFIRM_TOKENS` list (14 languages) anchored
  on `Precision-audit` as a fixed MCL technical token (same
  convention as `MCL`, `Spec`, `GATE`, `Faz N`).
- Classification order: ui-review → spec-approve →
  **precision-confirm** → summary-confirm → fallbacks.

**`hooks/mcl-stop.sh`**:

- New detection branch parallel to `summary-confirm`: when
  `ASKQ_INTENT=precision-confirm` and the developer's
  selection is approve-family, emit
  `asama-2-complete | stop | selected=<option>`.

**`hooks/mcl-pre-tool.sh`**:

- Replaced the v10.1.12 OR-list with a single-audit check.
  When `SPEC_APPROVED=true` and `asama-2-complete` audit is
  absent, deny mutating tool calls with reason
  `MCL ASAMA 2 SKIP-BLOCK (since v10.1.14)`.
- `REASON_KIND` renamed `asama-1-skip` → `asama-2-skip`;
  loop-breaker shape unchanged (3 consecutive blocks → fail-open).

**`skills/my-claude-lang/asama2-precision-audit.md`**:

- New "Closing AskUserQuestion" section documenting the
  mandatory askq title prefix
  `MCL <ver> | Faz 2 — Precision-audit niyet onayı:` and
  body structure.
- Question Flow updated: dimension scan → precision-audit
  audit emit → closing AskUserQuestion → wait for approve →
  Aşama 3.
- English-language sessions: dimension scan still skipped,
  but the closing askq is required (one-line confirmation).
  Determinism is the principle — no language-conditional
  skips of the gate itself.

#### Why the OR-list was wrong

Determinism means one audit, not three. An OR-list lets the
model produce ANY of the three signals to unblock SPEC, which
allows partial-Aşama-2 traversal: the model can emit a
`precision-audit` audit at the start of Aşama 2 (or via the
recovery hatch) without ever asking the dimensions or
running the GATE classifications. SPEC then unblocks despite
no real precision audit happening. The single-audit model
tied to user approval makes the gate impossible to fake
behaviorally — the audit only fires on a real approve-family
selection in the closing askq.

Banner: MCL 10.1.13 → MCL 10.1.14.

## [10.1.13] - 2026-05-03

### Critical timestamp-format-mismatch fix — recovery hatches now actually work

A real-world v10.1.12 deployment exposed a critical hidden bug
that had been silently degrading every Layer 2/3 scanner since the
session-boundary filter was introduced. The user's session showed:

1. v10.1.7 spec-approval-block fired correctly
2. Model attempted recovery via `asama-4-complete` Bash audit emit
3. Audit emit succeeded (file written)
4. Pre-tool re-checked → block STILL fired ("escape hatch did not escape")
5. Model added another audit; still blocked
6. v10.1.12 asama-1-skip-block fired with "no Aşama 1 evidence"
   even though `summary-confirm-approve` was in the audit file

#### Root cause

`mcl_trace_append` writes UTC ISO 8601: `2026-05-03T13:42:30Z`.
`mcl_audit_log` was writing local-tz with space: `2026-05-03 13:42:30`.

Scanner filter:
```python
ts = line.split("|", 1)[0].strip()
if session_ts and ts < session_ts:
    continue
```

Lexicographic comparison of `"2026-05-03 13:42:30"` vs
`"2026-05-03T13:42:30Z"` at character 10: `' '` (0x20) < `'T'` (0x54).
Result: every audit entry was filtered as "stale" (before session)
even when emitted seconds AFTER session_start. Recovery emits never
reached the scanner; phase-progression scanners couldn't see their
own targets; loop-breaker counters always read 0.

The bug was masked by tests that used the same format
(`date '+%Y-%m-%d %H:%M:%S'`) for both fixture session_start and
audit entries — string comparison there is consistent. Real
sessions had the format mismatch and silently broke.

#### Fix

**`hooks/lib/mcl-state.sh`**:

1. `mcl_audit_log` now uses `date -u '+%Y-%m-%dT%H:%M:%SZ'` —
   matches `mcl_trace_append` format. New sessions have all-ISO
   audit logs. String comparison works correctly for new sessions.

2. `_mcl_audit_emitted_in_session` and `_mcl_loop_breaker_count`
   helpers gained `_norm(ts)` Python helper that parses BOTH
   formats (UTC ISO and legacy local space) into epoch seconds via
   `datetime.fromisoformat` / `datetime.strptime`. This makes the
   fix robust against transition sessions where audit.log has
   mixed-format entries (pre-v10.1.13 and post-v10.1.13).

**`hooks/mcl-stop.sh`**:

3. Removed the duplicate inline definitions of
   `_mcl_loop_breaker_count` and `_mcl_audit_emitted_in_session`
   that shadowed the lib versions. Stop hook now uses the
   normalized lib helpers via the existing `source` of mcl-state.sh.
   Replaced with reference comments pointing at lib.

#### Why this affects EVERYTHING

Every gate that uses session_ts filtering was affected:
- v10.1.5/v10.1.6: phase-progression detection (Aşama 4/8/9/10/11/12)
- v10.1.7: spec-approval recovery via asama-4-complete
- v10.1.8: Aşama 8/9 skip-block recovery via asama-N-complete
- v10.1.10: Aşama 13 audit scanning (deep-dive depth)
- v10.1.11: Aşama 9 auto-complete (substep counting)
- v10.1.12: Aşama 1 skip-block evidence detection

All of these silently filtered out their target audits. Recovery
hatches existed in code but didn't actually escape because the
scanner couldn't see the recovery emit. v10.1.13 makes the
existing protective architecture actually work as designed.

#### Tests

294 passing (+6 in `test-v10-1-13-timestamp-format-fix.sh`):
- mcl_audit_log emits ISO UTC format
- lib helpers normalize timestamps (no naive string compare)
- pure-ISO session: audit detected correctly
- Legacy stop.sh duplicates removed (lib version takes effect)
- mcl_audit_log date format check

Banner: MCL 10.1.12 → MCL 10.1.13.

## [10.1.12] - 2026-05-03

### Aşama 1 skip-block — close the highest-severity gap

The "model unutursa" review identified Aşama 1 (intent gathering with
user-confirmed parameter summary) as the only ✗ HIGH severity gap.
Model could jump from prompt directly to spec-emit + spec-approval
without parameter verification → spec built on assumed parameters →
wrong code regardless of how many downstream gates pass.

v10.1.12 closes this gap with the same v10.1.7/v10.1.8 pattern:
real pre-tool block when SPEC_APPROVED=true but no Aşama 1 evidence,
recovery via Bash audit emit, 3-strike loop-breaker fail-open.

#### Aşama 1 evidence (any of these in current session)

- `summary-confirm-approve` audit (Stop hook detected an Aşama 1
  summary askq with approve-family tool_result — the canonical
  signal)
- `precision-audit asama2` audit (Aşama 2 ran — Aşama 1 must have
  run first by the phase ordering)
- `asama-1-complete` audit (explicit Bash emit recovery hatch)

#### Implementation

**`hooks/mcl-pre-tool.sh`** — new branch after Aşama 8/9 skip-block:

```bash
if [ -z "$REASON" ] && [ "$SPEC_APPROVED" = "true" ]; then
  _A1_HIT_SC="$(_mcl_audit_emitted_in_session "summary-confirm-approve")"
  _A1_HIT_PA="$(_mcl_audit_emitted_in_session "precision-audit")"
  _A1_HIT_AC="$(_mcl_audit_emitted_in_session "asama-1-complete")"
  if [ "${_A1_HIT_SC}${_A1_HIT_PA}${_A1_HIT_AC}" = "000" ]; then
    REASON="MCL ASAMA 1 SKIP-BLOCK ..."
    REASON_KIND="asama-1-skip"
  fi
fi
```

Decision logic — extended the v10.1.8 phase-skip elif branch to also
handle `asama-1-skip` (same loop-breaker shape, same recovery pattern).

#### Recovery message

The block REASON instructs the model on three recovery options:
- **(A) Re-run Aşama 1 properly** — gather intent / constraints /
  success_criteria / context, then summary-confirm askq for user
  approval.
- **(B) Bash audit emit** for cases where Aşama 1 happened verbally
  outside MCL: `mcl_audit_log asama-1-complete mcl-stop "params=
  intent+constraints+success+context confirmed"`.
- **(C) 3-strike fail-open** — after 3 consecutive blocks the gate
  releases with `asama-1-skip-loop-broken` audit recorded so the
  bypass is visible.

#### Test fallout

Several v10.1.6/v10.1.7/v10.1.8 tests had artificial setups that
set `state.spec_approved=true` directly without the corresponding
Aşama 1 audit (real flow has `summary-confirm-approve` recorded
before spec approval). v10.1.12 correctly catches these as Aşama 1
skips. Tests updated to seed audit.log with `summary-confirm-approve`
where they simulate post-Aşama-4 scenarios — better real-flow fidelity.

#### Combined v10.1.0–v10.1.12 effect

Phase contract is now end-to-end enforceable:
- spec_approved=false (v10.1.7) → spec-approval-block
- spec_approved=true + no Aşama 1 evidence (v10.1.12) → asama-1-skip-block
- code written + asama-{8,9}-emit-missing (v10.1.8) → skip-block
- All four with classifier-independent Bash recovery emits + 3-strike fail-open

The "model unutursa" review's only ✗ entry is now ✓.

#### Tests

288 passing (+16 in `test-v10-1-12-asama1-skip-block.sh`):
- Block fires when SPEC_APPROVED=true + no Aşama 1 evidence
- Each evidence source unblocks (summary-confirm-approve / precision-
  audit / asama-1-complete)
- 3-strike loop-breaker → 4th allows + asama-1-skip-loop-broken audit
- Read-only tools not blocked
- spec-approval-block has priority when SPEC_APPROVED=false
- Hook contract checks

Banner: MCL 10.1.11 → MCL 10.1.12.

## [10.1.11] - 2026-05-03

### Two grom-case fixes: Aşama 9 auto-complete + UI autodetect coverage

The grom backoffice retrospective surfaced two related bugs in
real-world v10.1.10 deployment:

1. **Aşama 9 visible-skip when sub-steps actually ran**: All 8
   sub-step audits (`asama-9-{1..4}-end` + `asama-9-{5..8}-not-
   applicable`) fired correctly, but model forgot the final
   `asama-9-complete` summary emit. Result: trace.log missed
   `phase_transition 9 10`, Aşama 11 Process Trace appeared to skip
   Aşama 9, developer concluded the most-important phase was
   atlanmış even though every sub-step executed.

2. **UI autodetect false negative on raw-Node frontends**: grom's
   stack (Express + EJS + Bootstrap + raw `public/js/*.js`)
   returned `ui_capable=false` because the heuristic only checked
   for React/Vue/Svelte/Next markers + `src/components`. Raw
   server-rendered patterns (Express EJS, Flask Jinja, Go-with-
   static) slipped through. Compounded by autodetect being one-shot
   at session_start — projects that started bare and grew a UI
   surface mid-session never re-evaluated.

#### Implementation

**`hooks/mcl-stop.sh`** (Aşama 9 auto-complete):
- New `_mcl_asama_9_substeps_complete` helper scans audit.log for
  `asama-9-{1..8}-end` OR `asama-9-{1..8}-not-applicable` per
  sub-step.
- When all 8 are present AND `asama-9-complete` is missing, Stop
  auto-emits `asama-9-complete | mcl-stop-auto | substeps_done=8`
  with the `mcl-stop-auto` caller marking it as auto-emitted (vs
  model-emitted). Existing v10.1.5 progression scanner picks it up
  next, transitioning `quality_review_state` to complete normally.
- `mcl_trace_append asama_9_auto_complete 8/8` recorded for
  forensics.

**`hooks/lib/mcl-stack-detect.sh`** (UI autodetect heuristic):
- `views/` directory with `*.ejs` / `*.hbs` / `*.handlebars` /
  `*.pug` / `*.twig` / `*.html` → ui_capable=true.
- `public/` directory with `*.html` / `*.css` / `*.js` →
  ui_capable=true (server-rendered + static asset bundle pattern).
- Bare-template fallback: `templates/`, `app/templates/`,
  `resources/views/` with `*.html`/`*.ejs`/etc. → ui_capable=true.
- All checks scan up to maxdepth 4 (covers nested asset
  directories like `public/js/components/`).

**`hooks/mcl-post-tool.sh`** (UI re-evaluation):
- New post-tool branch: when ui_flow_active=false and a Write/
  Edit/MultiEdit/NotebookEdit creates a UI-pattern file
  (`public/*.{html,css,js}`, `views/*.{ejs,hbs,pug,twig,html}`,
  root `*.{ejs,hbs,pug,twig}`, `templates/*.{html,ejs}`), bump
  ui_flow_active=true.
- Emits `ui-flow-reevaluated | post-tool | trigger=<filename> prev=
  false now=true` audit + `mcl_trace_append ui_flow_reevaluated
  <filename>` trace.
- Catches sessions that started empty (autodetect correctly false)
  but grew a UI surface mid-session — exactly the grom case.

#### Why both at once

Both bugs surfaced in the same grom retrospective and both prevent
the developer from seeing what actually happened. Aşama 9 visible-
skip hides a phase that ran; UI autodetect false negative hides
that the project IS frontend-bearing. Combined fix gives the
developer accurate visibility into what's been done and what
applies.

#### Tests

272 passing (+12 in `test-v10-1-11-asama9-and-ui-fixes.sh`):
- Aşama 9 substeps complete detection (all-8 vs partial)
- Hook contract: helper exists, audit emit format
- UI heuristic: views/*.ejs, public/{js,css}, empty, pure backend,
  bare templates
- UI re-eval: post-tool ui-flow-reevaluated audit emit
- Real integration: post-tool run flips ui_flow_active false → true
  on Write to public/js/app.js

Banner: MCL 10.1.10 → MCL 10.1.11.

## [10.1.10] - 2026-05-03

### Aşama 13 — Completeness Audit (new phase)

Pipeline gains a 13th phase that runs after Aşama 12 (or after
Aşama 11 in English sessions where Aşama 12 is no-op). Reads the
session's `.mcl/audit.log` + `.mcl/state.json` + `.mcl/trace.log`
and renders a machine-verifiable summary of which phases 1-12
actually completed end-to-end. Two mandatory deep dives surface
the highest-leverage compliance questions:

1. **Aşama 7 — Test-First**: counts `tdd-test-write` (T) vs
   `tdd-prod-write` (P) events, reports `state.tdd_compliance_score`,
   checks `state.tdd_last_green` for the most recent test_command
   result. Verdict: ✓ if 100% AND last result GREEN, ⚠️ partial,
   ✗ anti-TDD (P>0 AND T=0).
2. **Aşama 9 — Quality+Tests sub-steps**: for each N in 1..8 scans
   for `asama-9-N-start` + `asama-9-N-end` + `asama-9-N-not-applicable`
   + `asama-9-4-resolved` audits. Per sub-step verdict ✓ if start/end
   both present, ✓ if not-applicable (soft skip with reason), ⚠️ if
   start without end (incomplete), ✗ if no start AND no not-applicable
   (sub-step skipped without audit — Aşama 9 contract violation).

Output ends with an Open Issues section (omitted per empty-section-
omission rule when all phases ✓) so non-✓ verdicts surface as
actionable line items, not buried in a long table.

#### Why this matters

Across v10.1.5–v10.1.9 the protective chain became progressively
harder to bypass, but the developer still had no single place to
read "what actually completed in this session." Aşama 11 covers
spec compliance (per requirement); Aşama 13 covers PHASE compliance
(per phase). The two are complementary.

The grom backoffice case (May 2026) was the canonical example:
Aşama 11 emitted, model claimed completion, but Aşama 8 + Aşama 9
were skipped (visible in audit as `asama-{8,9}-emit-missing`).
A retroactive Aşama 13 on that session would have surfaced exactly
those two ✗ verdicts before the developer trusted the output.

#### Implementation

- **`skills/my-claude-lang/asama13-completeness.md`** (new) —
  full skill file with phase-completion signal table, Aşama 7 +
  Aşama 9 deep dive specifications, output format, anti-patterns,
  and skip-detection note (Layer 3).
- **`hooks/mcl-activate.sh`** — STATIC_CONTEXT carries the Aşama 13
  directive between asama11-verify-report and rule-capture phases
  so the rule is loaded on every prompt.
- **`skills/my-claude-lang.md`** — main skill index gains an
  Aşama 13 pointer per the project rule "every phase skill file
  needs a pointer line."
- **`FEATURES.md`, `README.md`, `README.tr.md`** — pipeline
  diagrams updated with the 13th step.

No hook code changes — Aşama 13 is a behavioral phase backed by
audit emit (`asama-13-complete`). Layer 3 skip-detection for
Aşama 13 itself can be added in a future release if real-world data
shows skip patterns.

#### Tests

260 passing (+15 in `test-v10-1-10-asama13-completeness.sh`):
skill file structure (sections, mcl_phase tag, sub-step references,
emit instruction), STATIC_CONTEXT inclusion, main skill index
pointer, pipeline diagram in FEATURES + both READMEs.

Banner: MCL 10.1.9 → MCL 10.1.10.

## [10.1.9] - 2026-05-03

### Inline-spec askq fallback hash — classifier coverage fix

Driven by a real-world v10.1.8 deployment where a model embedded
spec content directly inside the AskUserQuestion question body
(bullet-form parameters) instead of emitting a preceding `📋 Spec:`
block. The classifier correctly identified spec-approve intent (the
`spec onay` token matched the question body) but `_compute_spec_hash`
returned empty because no `📋 Spec:` line was found in plain assistant
text. The JIT askq advance condition `-n "$JIT_SPEC_HASH"` then
refused to fire, blocking writes despite correct intent detection —
classic developer friction: "I approved, why is it still blocked?"

#### Implementation

**`hooks/lib/mcl-askq-scanner.py`** — added inline-spec fallback at
the end of `scan()`:

```python
if intent == "spec-approve" and not spec_hash and last_question_body:
    spec_hash = "inline-" + hashlib.sha256(
        last_question_body.encode("utf-8")
    ).hexdigest()[:12]
```

The synthetic hash is prefixed with `inline-` so downstream drift
detection can distinguish it from block-derived hashes. Only fires
when intent is already classified as `spec-approve` (so generic
non-spec askq's don't accidentally promote).

#### Why this is safe

- **No false positives**: fallback gated by `intent == "spec-approve"`.
  Non-spec askq's (color picker, summary confirm, UI review) don't
  get a synthetic hash.
- **Drift visibility preserved**: `inline-` prefix marks synthetic.
  Future drift detection can compare prefix and warn if a fresh
  block-derived spec emit doesn't match the inline-approved version.
- **Audit trail intact**: state.spec_hash records what was approved,
  even if the format was non-canonical.
- **No behavioral changes for the canonical path**: when model emits
  `📋 Spec:` block normally, `_compute_spec_hash` returns the
  block-derived hash and the fallback is skipped.

#### Combined v10.1.0–v10.1.9 effect

- v10.1.0–v10.1.4: enforcement primitives + checklists + audit trails
- v10.1.5–v10.1.6: audit-driven phase progression (Layer 1/2/3)
- v10.1.7: spec-approval real block + asama-4-complete escape hatch
- v10.1.8: Aşama 8/9 skip-block (Layer 3 → hard enforcement)
- **v10.1.9: classifier inline-spec fallback (this release)**

The protective chain now handles the most common real-world friction
pattern: model approves the right thing, classifier identifies the
right intent, but spec format was non-canonical → user no longer
locked out.

#### Tests

245 passing (+11 in `test-v10-1-9-inline-spec-fallback.sh`):
- Spec block present → block-derived hash (no fallback, existing
  behavior preserved)
- Inline-spec askq → `inline-<12-char-sha>` synthetic hash
- Non-spec, non-approve askq → no hash (no false positive)
- summary-confirm intent → no hash (fallback gated to spec-approve)
- Hook contract: scanner has fallback comment + uses inline- prefix

Banner: MCL 10.1.8 → MCL 10.1.9.

## [10.1.8] - 2026-05-03

### Aşama 8/9 skip-block — soft visibility → hard enforcement

Driven by independent real-world data. The grom backoffice case
(v10.1.7 deployment, May 2026) showed:

- Model emitted `asama-4-complete` correctly (Layer 1+2 working)
- Model wrote 29 production files BUT zero test files
- Model did not run Aşama 8 risk review or Aşama 9 quality+tests
- Layer 3 skip-detection correctly emitted `asama-8-emit-missing`
  and `asama-9-emit-missing`
- An independent security audit then found 7 issues (2 HIGH +
  5 MEDIUM) — exactly the categories v10.1.1's stack-aware MUST
  checklist would have caught (rate-limit beyond /login, CSRF
  timing-safe, password-change rate-limit, logging hygiene)

Conclusion: soft visibility was insufficient. The skip was visible
but the security gaps still landed. v10.1.8 turns the
`asama-{8,9}-emit-missing` audit into an actionable pre-tool block
on the next mutating tool call.

#### Implementation

**`hooks/mcl-pre-tool.sh`** — new branch after the spec-approval
block:

1. **Skip-block trigger** — when SPEC_APPROVED=true AND
   `asama-{8,9}-emit-missing` is present in current session AND the
   matching `asama-{8,9}-complete` has NOT been emitted yet, set
   REASON with recovery instructions and REASON_KIND=`asama-N-skip`.
2. **Sequential enforcement** — checks 8 first, 9 second. Once 8 is
   resolved (model emits asama-8-complete), the next block fires for
   9 if it's still missing. Forces the correct ordering.
3. **3-strike loop-breaker** — same shape as v10.1.7 spec-approval-
   block. After 3 consecutive blocks, fail-open with
   `asama-N-skip-loop-broken` audit + trace. Prevents developer
   lockout when classifier consistently fails AND model can't
   self-recover.

**`hooks/lib/mcl-state.sh`** — `_mcl_audit_emitted_in_session`
helper moved into shared lib (was inline in mcl-stop.sh). Both
hooks can now use it. Stop hook keeps its local copy for backward-
compat.

#### Why this is the right fix

The ROOT cause exposed by grom: `asama-N-emit-missing` audit was
informational only. Model could ignore the skill instruction to
emit `asama-N-complete`, Layer 3 would record the skip, and writes
would continue unimpeded. Three layers of defense became one
visibility log.

v10.1.8 connects the visibility audit to enforcement: the SAME
audit that records the skip now ALSO triggers a real block on the
next turn. Recovery is the same Bash audit emit pattern v10.1.7
used for asama-4-complete — model emits the missing complete to
clear the block.

The 3-strike fail-open is intentional: if model genuinely cannot
recover (skill instruction unclear, prompt ambiguous, etc.), the
developer is not permanently locked out. The bypass is recorded
in audit so it remains visible.

#### Combined v10.1.0–v10.1.8 effect

- v10.1.0: Aşama 8/9 hard-enforced (Stop hook)
- v10.1.1: Stack-aware security MUST checklist
- v10.1.2: M/H findings must-resolve invariant
- v10.1.3: Aşama 7 title fix (test-first emphasis)
- v10.1.4: TDD compliance ratio audit
- v10.1.5: Audit-driven progression — Aşama 8 + 9 (PILOT)
- v10.1.6: Audit-driven progression — full coverage + Layer 3 skip-detection
- v10.1.7: Spec-approval real block + asama-4-complete escape hatch
- **v10.1.8: Aşama 8/9 skip-block — Layer 3 → hard enforcement (this release)**

The phase-completion contract is now end-to-end enforceable:
spec_approved=false (v10.1.7) AND asama-{4,8,9}-emit-missing
(v10.1.8) all trigger real pre-tool denies with classifier-
independent recovery paths.

#### Tests

234 passing (+17 in `test-v10-1-8-skip-block.sh`, integration-style
with real pre-tool):
- Cases: asama-8 trigger, asama-8 cleared → asama-9 cascading,
  both cleared → no block, 3-strike loop-breaker, read-only tool
  not blocked, spec-approval priority when SPEC_APPROVED=false,
  hook + lib contract checks

Banner: MCL 10.1.7 → MCL 10.1.8.

## [10.1.7] - 2026-05-02

### Spec-approval gate restored (Option 3) + escape hatch (Option 1)

The MUST-have follow-up to v10.1.6. The herta investigation surfaced
the real root cause: state freeze was the SYMPTOM; the underlying
contract violation was that **writes happened at `spec_approved=false`
because pre-tool was advisory** (v10.0.0 decision:approve replaced
decision:block for "tüm MCL kilitlerini kaldır"). v10.1.5/v10.1.6
made progression more reliable but never closed the actual write gate.
Without this gate, "MCL koruyor" is theater — vulnerable code can
still ship while state machine is perfectly tracked.

#### Implementation

**`hooks/mcl-pre-tool.sh`** — two surgical changes around the
existing spec_approved check:

1. **Layer 4 escape hatch (Option 1)** — before the spec-approval
   block fires, scan audit.log for `asama-4-complete` emit (mandated
   by skills/asama4-spec.md since v10.1.6). When found in current
   session, force-progress `spec_approved=true`,
   `current_phase=7`, `phase_name=EXECUTE` inline at PreToolUse
   (not just at Stop). This means model can recover from a
   classifier miss WITHOUT waiting for end-of-turn — the next
   mutating tool call after the emit succeeds. Audit + trace get
   `asama-4-progression-from-emit` from pre-tool.

2. **Real spec-approval block (Option 3)** — when `spec_approved=
   false` after both JIT askq advance AND escape hatch attempts,
   pre-tool now returns `permissionDecision: "deny"` (was "allow"
   advisory in v10.0.0+). REASON message instructs the model on
   three recovery options: re-emit AskUserQuestion, run the
   `asama-4-complete` Bash audit emit, or wait for 3-strike fail-
   open. Other denial sources (UI path, pattern scan, scope guard)
   STAY ADVISORY — only the spec-approval gate is reverted.

3. **3-strike loop-breaker** — if `spec-approval-block` audit
   already fired ≥3 times in the current session, fail-open with
   `spec-approval-loop-broken` audit + trace. Prevents developer
   lockout when classifier consistently fails AND model can't
   self-recover via the emit path.

**`hooks/lib/mcl-state.sh`** — `_mcl_loop_breaker_count` helper moved
from mcl-stop.sh into the shared lib so both hooks can use it. Stop
hook keeps its local copy for backward-compat (lib version overrides
when sourced first).

#### Why Option 3 was the must-have

The herta v10.1.4 audit log showed 70+ `deny-tool` events but every
single mutating write succeeded — because the decision was "allow"
with a denial REASON for advisory purposes. The model wrote 36 prod
files at `spec_approved=false` despite MCL's stated contract that
spec approval is required first. v10.1.5/v10.1.6 made that violation
TRACKABLE (skip-detection audit) but didn't STOP it. v10.1.7 stops
it.

Why Option 3 alone wasn't enough: classifier coverage gaps mean
spec_approved can stay false even when developer clicked Onayla.
Hard-block alone would lock the developer out. Option 1 (asama-4-
complete escape hatch from v10.1.6, now active in pre-tool too) is
the recovery path. The 3-strike loop-breaker is the final fail-safe.

#### Combined v10.1.0–v10.1.7 effect

- v10.1.0: Aşama 8/9 hard-enforced
- v10.1.1: Stack-aware security MUST checklist
- v10.1.2: M/H findings must-resolve invariant
- v10.1.3: Aşama 7 title fix (test-first emphasis)
- v10.1.4: TDD compliance ratio audit
- v10.1.5: Audit-driven progression — Aşama 8 + 9 (PILOT)
- v10.1.6: Audit-driven progression — full coverage + Layer 3 skip-detection
- **v10.1.7: Spec-approval real block + asama-4-complete escape hatch + 3-strike loop-breaker (this release)**

The spec-approval contract is now actually enforced. herta v10.1.4-
type silent-bypass cannot recur.

#### Tests

180 passing (16 new in `test-v10-1-7-spec-approval-block.sh`,
integration-style — runs actual mcl-pre-tool.sh against synthetic
fixtures, asserts permissionDecision in JSON output, asserts state
side effects, asserts loop-breaker fires after 3 strikes).

Banner: MCL 10.1.6 → MCL 10.1.7.

## [10.1.6] - 2026-05-02

### Audit-driven phase progression — full coverage + skip-detection

Continuation of the v10.1.5 PILOT (Aşama 8 + 9). v10.1.6 extends the
classifier-independent fallback to ALL persisted/transient phases AND
adds Layer 3 skip-detection that surfaces missing emits as audit
warnings. Closes the herta-type "frozen at phase 4" scenario observed
under v10.1.4: state machine no longer depends solely on askq
classifier intent recognition.

#### Implementation

**`hooks/mcl-stop.sh`** — five new scanners + one skip-detector:

- `_mcl_precision_audit_emitted` — scans for the existing
  `precision-audit asama2` audit (mandated by skills/asama2-precision-
  audit.md). Sets `precision_audit_done=true` when found in current
  session. Previously the field was reset to false on restart but
  NEVER set to true — the field was effectively dead. Emits
  `asama-2-progression-from-emit` audit + `phase_transition 1 2`
  trace.
- Aşama 4 progression — `_mcl_asama_4_complete_emitted` + force-
  progression of `spec_approved=true`, `current_phase=7`,
  `phase_name=EXECUTE`. Emits `asama-4-progression-from-emit`
  audit + `phase_transition 4 7` trace.
- `_mcl_audit_emitted_in_session` (generic helper) — scans audit.log
  for `<event>` in current session with optional idempotency marker
  to prevent duplicate progression writes when Stop fires multiple
  times.
- Aşama 10 — explicit `asama-10-complete` emit detection. Emits
  `asama-10-progression-from-emit` + `phase_transition 10 11` trace.
- Aşama 11 — explicit `asama-11-complete` emit detection. Emits
  `asama-11-progression-from-emit` + `phase_transition 11 12` trace.
- Aşama 12 — reuses existing `localize-report asama12` audit
  (mandated by skills/asama12-translate.md). Emits
  `asama-12-progression-from-emit` + `phase_transition 12 done`
  trace.
- `_mcl_skip_detection` (Layer 3) — when `tdd-prod-write` audit
  events are present in current session but the corresponding
  `asama-{4,8,9}-complete` emit is missing, write
  `asama-N-emit-missing | stop | skip-detect prod-write-without-emit`
  audit + `phase_emit_missing N` trace. Pure visibility, no block,
  no decision change. Idempotent — re-runs skip phases already
  flagged.

**Skill instructions added to:**
- `skills/my-claude-lang/asama4-spec.md` — emit `asama-4-complete`
  with `spec_hash=<H> approver=user` after AskUserQuestion approve
  tool_result and BEFORE writing any Aşama 7 code.
- `skills/my-claude-lang/asama10-impact-review.md` — emit
  `asama-10-complete` with `impacts=N resolved=R` at end of impact
  review (or when omitted because no impacts surfaced).
- `skills/my-claude-lang/asama11-verify-report.md` — emit
  `asama-11-complete` with `covered=N must_test=K trace_lines=L`
  after all three Verification Report sections are written.

**No skill changes for Aşama 2 / 12** — both already mandate
existing audits (`precision-audit`, `localize-report`) that v10.1.6
reuses as completion markers.

#### Why this is the root-cause fix (not just a patch)

The herta investigation surfaced the architectural root cause: phase
progression was OPTIMISTIC. State writes only occurred when the
askq-classifier detected a specific intent in transcript text. Any
classifier coverage gap (off-language wording, dropped prefix,
free-form text instead of AskUserQuestion option choice) silently
froze state at phase 4 even when the model proceeded behaviorally.

Three layers of fix in v10.1.5/v10.1.6:

- **Layer 1 (skill behavior):** every phase emits an explicit
  `asama-N-complete` Bash audit at end of run.
- **Layer 2 (hook scanner):** Stop hook scans audit.log per session
  and force-progresses state independently of classifier output.
- **Layer 3 (skip-detection):** when activity signals (tdd-prod-write)
  appear without the matching emit, hook writes
  `asama-N-emit-missing` so the bypass is visible retroactively in
  /mcl-checkup.

Layers 1+2 ensure progression DOES happen when the model complies.
Layer 3 ensures non-compliance is VISIBLE so the developer knows when
the contract was bypassed. Together they close the herta-type freeze
without resorting to brittle classifier improvements.

#### Combined v10.1.0–v10.1.6 effect

- v10.1.0: Aşama 8/9 hard-enforced (no fast-path skip)
- v10.1.1: Stack-aware security MUST checklist
- v10.1.2: M/H findings must-resolve invariant
- v10.1.3: Aşama 7 title fix (test-first emphasis)
- v10.1.4: TDD compliance ratio audit
- v10.1.5: Audit-driven progression — Aşama 8 + 9 (PILOT)
- **v10.1.6: Audit-driven progression — full coverage + Layer 3 skip-detection (this release)**

#### Tests

154 passing (24 new across 3 files):
- `test-v10-1-6-asama-4-progression.sh` — 8 tests (emit detection +
  state side effects + skill contract)
- `test-v10-1-6-phase-progressions.sh` — 8 tests (precision-audit /
  asama-10 / idempotency / asama-12 / hook + skill contracts)
- `test-v10-1-6-skip-detection.sh` — 8 tests (all-missing / partial /
  all-present / no-code-no-flag / idempotent / hook contract)

Banner: MCL 10.1.5 → MCL 10.1.6.

## [10.1.5] - 2026-05-02

### Audit-driven phase progression (PILOT — Aşama 8 + 9)

Real-use diagnosis: the herta project completed Aşama 1–12 end-to-end
yet `state.json` showed `risk_review_state=null`,
`quality_review_state=null`, `tdd_compliance_score=null`. Phase
progression depended on the askq-classifier detecting the right
intent, and any classifier coverage gap (off-language wording, missing
prefix, dropped tool_result) silently froze state at phase 4 even
when the full pipeline ran behaviorally.

v10.1.5 introduces a classifier-independent fallback: each phase
emits an explicit `asama-N-complete` audit at end of run. Stop hook
scans audit.log per session and force-progresses the corresponding
state field. Pilot scope: Aşama 8 + 9 only. Remaining phases (1→2,
4→7, 10/11/12) ship in v10.1.6.

#### Implementation

- **`hooks/mcl-stop.sh`** — two new helpers + scanners:
  - `_mcl_asama_8_complete_emitted` — scans audit.log since
    session_start for `asama-8-complete` events. When found AND
    `risk_review_state != "complete"`, force-progresses state, emits
    `asama-8-progression-from-emit` audit, writes
    `phase_transition 8 9` to trace.
  - `_mcl_asama_9_complete_emitted` — symmetric logic for
    `quality_review_state`, emits `phase_transition 9 10`.
- **`skills/my-claude-lang/asama8-risk-review.md`** — new "## Audit
  Emit on Completion" section. Mandates a Bash audit emit at end of
  Aşama 8 with severity counts (`h_count=N m_count=M l_count=K
  resolved=R`), even when Aşama 8 was OMITTED (no risks worth
  surfacing).
- **`skills/my-claude-lang/asama9-quality-tests.md`** — new "## Audit
  Emit on Completion" section. Mandates a Bash audit emit at end of
  Aşama 9 with sub-step counts (`applied=A skipped=S ambiguous=B
  na=N`). Notes that the v10.1.2 MEDIUM/HIGH must-resolve invariant
  remains independent — audit-driven progression unblocks the state
  field, not the severity gate.

#### Why pilot, not full rollout

Aşama 8 and 9 are the two phases where state-vs-behavior divergence
hurts most: `risk_review_state` and `quality_review_state` directly
gate the v10.1.0 hard-enforcement and the v10.1.2 must-resolve
invariant. Empty values here mean those gates fail open. The remaining
phase transitions (1→2 precision audit, 4→7 spec approve,
10/11/12) are less load-bearing for hard-blocks; they ship next once
the pilot pattern is verified in production use.

#### Combined v10.1.0–v10.1.5 effect

- v10.1.0: Aşama 8/9 hard-enforced (no fast-path skip)
- v10.1.1: Stack-aware security MUST checklist
- v10.1.2: M/H findings must-resolve invariant
- v10.1.3: Aşama 7 title fix (test-first emphasis)
- v10.1.4: TDD compliance ratio audit
- **v10.1.5: Audit-driven phase progression — Aşama 8 + 9 (this release)**

#### Tests

130 passing (13 new across `test-v10-1-5-asama-8-progression-pilot.sh`
and `test-v10-1-5-asama-9-progression-pilot.sh`: 3 emit-detection +
1 stale-session + 1 substring-confusion + 3 hook-contract checks per
phase, 3 of which are shared).

Banner: MCL 10.1.4 → MCL 10.1.5.

## [10.1.4] - 2026-05-02

### Layer 1 TDD compliance audit (cheapest path)

Real-use question: *"TDD'nin gerçekten çalıştığını nasıl
doğrularız?"* — how to verify TDD compliance? v10.1.4 adds the
cheapest verification layer: file-classifier + session compliance
ratio. Pure audit, no block, no developer friction.

#### Implementation

- **`hooks/mcl-post-tool.sh`** — new path classifier inserted
  before regression-guard logic. On every Write/Edit/MultiEdit/
  NotebookEdit, the file path is matched against:
  - **Skip patterns** (`node_modules/`, `dist/`, `build/`,
    `.next/`, `.nuxt/`, `.cache/`, `coverage/`, `.git/` — at start
    or after `/`) → no audit emit
  - **Test patterns** (`__tests__/`, `tests?/`, `specs?/`,
    `.test.{ts,tsx,js,...}`, `.spec.{ts,tsx,js,...}`,
    `_test.{go,py}`, `_spec.rb`, `test_*.py`) → emit
    `tdd-test-write | file=<path>`
  - **Source extensions** (`.ts/.tsx/.js/.py/.go/.rb/.java/.kt/
    .rs/.cpp/.cs/.php/.swift/.lua/.vue/.svelte` etc.) → emit
    `tdd-prod-write | file=<path>`
- **`hooks/mcl-stop.sh`** — new `_mcl_tdd_compliance` helper at
  Stop time scans session audit.log for `tdd-*-write` events.
  Computes: `score = (prod_writes_with_preceding_test_write /
  total_prod_writes) * 100`. Emits `tdd-compliance | score=N%
  preceded=K prod=M` audit + writes to state
  (`tdd_compliance_score`).
- **`hooks/lib/mcl-state.sh`** — new default field
  `tdd_compliance_score: null`.

#### Heuristic limits (intentional, cheapest layer)

- **Path-based, not behavior-based:** detects whether a test file
  was touched in the same session as prod files; does NOT verify
  RED→GREEN cycle (that's Layer 2).
- **"Any test before any prod" heuristic:** counts prod-writes
  that have ANY preceding test-write in session. Doesn't match
  test-to-prod-file pairs (that would require richer state).
- **Audit only, no block:** pure visibility. /mcl-checkup surfaces
  the score; developer decides if intervention needed.

#### Combined v10.1.0–v10.1.4 effect

- v10.1.0: Aşama 8/9 hard-enforced (no fast-path skip)
- v10.1.1: Stack-aware security MUST checklist
- v10.1.2: M/H findings must-resolve invariant
- v10.1.3: Aşama 7 title fix (test-first emphasis)
- **v10.1.4: TDD compliance ratio audit (this release)**

#### Tests

117 passing (23 new in `test-v10-1-4-tdd-compliance.sh`: 7 test-
pattern, 5 prod-pattern, 5 skip-pattern, 3 ratio scenarios + 3
hook contract checks).

Banner: MCL 10.1.3 → MCL 10.1.4.

## [10.1.3] - 2026-05-02

### Aşama 7 başlığı düzeltildi — TDD test-first vurgusu

Real-use feedback: Aşama 7 başlığı *"Kod yazılıyor"* ("Code gets
written") TDD prensibinin tersini ima ediyor — TDD'de önce test
yazılır, sonra kod. Body doğru tarif ediyordu (RED→GREEN→refactor)
ama başlık yanıltıcıydı.

#### Fix

- `README.md` Aşama 7 paragrafı yeniden yazıldı: *"Test-first
  development (TDD). For each acceptance criterion: write the
  failing test FIRST (RED), then the minimum production code to
  make it pass (GREEN), then refactor."*
- `README.tr.md` Aşama 7 paragrafı yeniden yazıldı: *"Test-first
  geliştirme (TDD). Her kabul kriteri için ÖNCE failing test
  yazılıyor (RED), SONRA onu geçecek minimum production kod
  (GREEN), ardından refactor. Test her zaman production kodun
  önünde gelir — 'kod yaz sonra test ekle' değil, gerçek TDD."*
- `skills/my-claude-lang/asama7-execute.md` başlık + naming
  clarification eklendi.

Banner: MCL 10.1.2 → MCL 10.1.3.

## [10.1.2] - 2026-05-02

### MEDIUM/HIGH must-resolve invariant

Closing the security gap loop: v10.1.0 hard-enforced Aşama 8 + 9
ran; v10.1.1 added the explicit MUST checklist; v10.1.2 ensures
no Aşama 11 advance while ANY HIGH or MEDIUM finding is still
unresolved.

#### Implementation

- **`hooks/lib/mcl-state.sh`** — new default field
  `open_severity_count: 0`.
- **`hooks/mcl-stop.sh`** — new `_mcl_open_severity_count()` helper:
  scans audit.log within current session boundary
  (`session_start` in trace.log) for `asama-9-4-ambiguous` events
  matched against `asama-9-4-resolved` events. The set difference
  is the open count. Helper updates state every Stop pass:
  `mcl_state_set open_severity_count <n>`.
- **Stop hook block:** when `quality_review_state="complete"` AND
  `open_severity_count > 0`, emit `decision:block` with the
  must-resolve reason text — Aşama 11 cannot fire until the count
  hits 0. The model resolves each finding by:
  1. Running it through Aşama 8 risk-dialog (developer decides via
     AskUserQuestion: apply fix / accept with rule-capture / cancel)
  2. Writing `mcl_audit_log "asama-9-4-resolved" "stop" "rule=<id>
     file=<f>:<l> status=fixed|accepted"` to mark it resolved.
- **Loop-breaker:** 3 consecutive `open-severity-block` events →
  `open-severity-loop-broken` audit + fail-open. Preserves the
  v9.0.1 fail-open contract.

#### Aşama 11 Verify Report — new "Açık Yüksek/Orta Bulgular" section

If the loop-breaker fired (fail-open path), Aşama 11 emits an
explicit "Açık Yüksek/Orta Bulgular" section listing every still-
open finding from the audit log. Even when MCL gives up enforcing
(loop-broken), the developer sees what was left unresolved.

#### Combined v10.1.0–v10.1.2 effect on real-use audit gaps

| Gap | Caught by |
|---|---|
| Brute-force protection missing | Aşama 8 §2b auth checklist [HIGH] |
| `localStorage` token storage | Aşama 8 §2b frontend [HIGH] |
| JWT revocation missing | Aşama 8 §2b backend [HIGH] |
| Default admin creds | Aşama 8 §2b auth [HIGH] |
| helmet missing | Aşama 8 §2b backend [HIGH] |
| **CSP missing** | Aşama 8 §2b frontend [HIGH] |
| Password policy weak | Aşama 8 §2b auth [HIGH] |
| bcrypt cost = 10 | Aşama 8 §2b backend [MEDIUM] |
| CORS regex too broad | Aşama 8 §2b backend [MEDIUM] |
| RBAC missing | Aşama 8 §2b auth [MEDIUM] |
| Audit log missing | Aşama 8 §2b backend [MEDIUM] |
| Aşamalar 8/9 hiç çalışmamış | v10.1.0 hard-enforcement |
| Açık M/H bulgular ile Aşama 11 fire | v10.1.2 must-resolve invariant |

#### Tests

94 passing (8 new in `test-v10-1-2-must-resolve.sh`: 4 counter
scenarios + hook contract checks + state schema check).

Banner: MCL 10.1.1 → MCL 10.1.2.

## [10.1.1] - 2026-05-02

### Stack-aware security MUST checklist (CSP, JWT, RBAC, audit, etc.)

Real-use audit identified 11 specific OWASP gaps. v10.1.0 added
hard-enforcement for Aşama 8/9 phases; v10.1.1 fills in the
content — the explicit checklist that those phases scan against.

#### Aşama 8 — `asama8-risk-review.md` §2b Stack-Aware Security MUST Checklist

5 stack-aware MUST groups, each entry tagged HIGH or MEDIUM:

- **Backend** (express/fastify/nest/koa/next-api/django/rails/fastapi):
  helmet, rate-limit, bcrypt cost ≥ 12, JWT lifecycle (revocation +
  short-lived access + refresh rotation), cookie flags
  (httpOnly+Secure+SameSite=strict), CORS whitelist, audit log,
  logging hygiene, parameterized queries.
- **Frontend** (react-frontend/vue-frontend/svelte-frontend/html-static):
  Content-Security-Policy (no unsafe-inline/eval), HSTS,
  X-Frame-Options, X-Content-Type-Options, Referrer-Policy,
  Permissions-Policy, Subresource Integrity, Trusted Types, token
  storage NEVER in localStorage, CSRF tokens, raw-HTML insertion
  API review.
- **Auth & Identity:** password schema (zod min(8) + complexity OR
  zxcvbn≥3), default credentials warning, RBAC matrix even for
  single-role, IDOR protection, session fixation defense,
  brute-force lockout.
- **Data & Secrets:** `.env*` in gitignore, weak `JWT_SECRET`
  placeholder detection, file-upload validation.
- **Dependency hygiene:** `npm audit --audit-level=moderate` clean,
  no abandoned/unmaintained packages.

#### Aşama 9.4 — `asama9-quality-tests.md` Security sub-step rewrite

- **Automatic tooling dispatch** at start of 9.4 (Bash invocation,
  not model behavior prior):
  - `bash mcl-semgrep.sh scan <touched-files>`
  - `npm audit --audit-level=moderate --omit=dev`
  - Stack-specific security linters (eslint-plugin-security, bandit,
    gosec, brakeman)
- **Per-finding disposition:**
  - HIGH/MEDIUM with unambiguous autofix → apply silently +
    `state.open_severity_findings.append({status:fixed})`
  - HIGH/MEDIUM ambiguous → **ESCALATE to Aşama 8 dialog** (no
    longer skip — prepares v10.1.2 must-resolve invariant)
  - LOW → suppress
- **Mirror of §2b checklist** — every MUST verified in code; absent
  → `open_severity_findings` entry + escalation.

#### Trade-off

Skill content is heavier (richer checklist) but no behavioral
breakage: existing 86 tests pass. Aşama 9.4 ambiguous-skip path is
gone (replaced with escalation), aligning with v10.1.2 invariant.

Banner: MCL 10.1.0 → MCL 10.1.1.

## [10.1.0] - 2026-05-02

### Aşama 8 + 9 hard-enforcement (real-use security gap fix)

Real-use audit (developer's npm-audit + manual review of test10
backoffice prototype): MCL produced code with multiple OWASP Top 10
gaps (no rate-limit, localStorage tokens, JWT revocation missing,
default admin creds, no helmet, weak password policy, bcrypt cost=10,
no RBAC, no audit log, **no CSP**) that should have been caught by
Aşama 8 risk dialog and Aşama 9 quality+tests pipeline. Neither phase
ran. Cause: v10.0.0 advisory mode swapped Aşama 8's
`phase-review-pending` block from `decision:block` to
`decision:approve`, and Aşama 9 never had hook enforcement at all.

#### Fixes

1. **Aşama 8 block re-enabled** — `mcl-stop.sh` line 724:
   `decision: "approve"` → `"block"`. Existing 3-strike loop-breaker
   (`phase-review-loop-broken`) preserved.

2. **Aşama 9 hard-block added** — new check in `mcl-stop.sh`:
   when `risk_review_state="complete"` AND
   `quality_review_state ≠ "complete"`, emit `decision:block` with
   the 8-sub-step requirements list (9.1 code review, 9.2 simplify,
   9.3 performance, 9.4 security with auto-semgrep + npm audit,
   9.5 unit, 9.6 integration, 9.7 E2E, 9.8 load). Each sub-step must
   write `asama-9-N-start` and `asama-9-N-end` audit entries (skip
   detection control). 3-strike loop-breaker
   (`quality-review-loop-broken`).

3. **STATIC_CONTEXT no-fast-path constraint** — new
   `<mcl_constraint name="asama-8-9-no-fast-path">`:
   *"Once code has been written in Aşama 7 (or any UI sub-phase),
   Aşama 8 AND Aşama 9 MUST both run. Skipping is impossible —
   'task is small', 'prototype only', 'just a UI tweak', 'obvious
   change' are NOT exceptions. Only when no code was written
   (Read/Grep/Glob only) are they skipped."*

#### Trade-off

v10.0.0's advisory mode is partially walked back: now 3 hard-blocks
total (Aşama 6b + 8 + 9). All three follow the same pattern:
state-flag triggered (timing-safe), 3-strike loop-breaker fail-open
(no infinite trap). Other gates (plugin-gate, secret-scan,
spec-presence, scope-guard, etc.) remain advisory.

#### Tests

86 passing (6 new in `test-v10-1-asama8-9-enforcement.sh`: contract
checks for both phases + STATIC_CONTEXT constraint + counter logic).

Banner: MCL 10.0.4 → MCL 10.1.0.

## [10.0.4] - 2026-05-02

### Fix v10.0.3 timing bug — spec-presence enforcement moves to Stop hook audit

Real-use feedback (developer's exact diagnosis): *"konuşmaları takip
etme konusunda bi eksik var bence. MCL herşeyi önceden kaydetmeli
bence. önceden yazarsa bütün tool'ların baktığı yerler güncel
olur."* — there's a gap in conversation tracking; MCL should record
things upfront so all hooks see current state.

#### Root cause

v10.0.3's pre-tool spec-presence block read `transcript.jsonl` at
PreToolUse fire time and scanned for 📋 Spec: in the current turn's
assistant text. **The current turn's assistant text is NOT yet
flushed to transcript when pre-tool fires.** Claude Code persists
assistant content blocks at message-completion time, not
incrementally. Result: even when the model DID emit a spec block
right before its Edit tool call, pre-tool's transcript scan returned
"no spec found" and blocked the Edit. The block then re-fired
multiple times because each retry hit the same timing wall.

#### Fix — move enforcement to Stop hook audit

- `hooks/mcl-pre-tool.sh` — REVERT v10.0.3's pre-tool spec-presence
  block + loop-breaker. Pre-tool no longer enforces spec presence.
- `hooks/mcl-stop.sh` — NEW `_mcl_spec_presence_audit` helper called
  at turn end (transcript fully flushed). Scans the latest assistant
  message: if it contains an Edit/Write/MultiEdit/NotebookEdit
  tool_use block, walks blocks in order, checks whether a 📋 Spec:
  text block precedes the first tool_use. If not, writes
  `spec-required-warn` to audit.log. Visible via `/mcl-checkup`.
- `STATIC_CONTEXT` no-spec-fast-path constraint updated:
  hard-block language replaced with audit-warn description.
- `asama4-spec.md` and `anti-patterns.md` updated to reflect the
  audit-not-block enforcement model.

#### Trade-off (acknowledged)

- **Lost:** mechanical pre-tool block that prevents Edit/Write
  without spec. Model can technically still skip the spec — and
  the audit-warn surfaces it after the fact, not before damage.
- **Gained:** correctness. v10.0.3's block was firing on legitimate
  spec emissions because of the transcript timing wall. v10.0.4's
  audit fires only when the spec is genuinely absent in the
  completed assistant message.

This is consistent with v10.0.0's advisory-mode philosophy: only
Aşama 6b retains a hard-block (and that one works because the
trigger is a state field set at end of prior turn, not in-progress
text). Spec-presence joins the audit-only enforcement tier.

#### Tests

80 passing (8 new test-v10-spec-required assertions for v10.0.4
architecture: hook contract checks (stop has audit, pre-tool no
longer blocks) + 3 detector verdicts (Edit with preceding spec=ok,
Edit without spec=warn, Edit with post-hoc spec=warn).

Banner: MCL 10.0.3 → MCL 10.0.4.

## [10.0.3] - 2026-05-02

### Aşama 4 spec-presence enforcement (MCL-wide rule)

Real-use feedback: in a small-tweak follow-up turn ("remove these
buttons, auto-apply on second pick"), the model called Edit directly
without emitting a 📋 Spec: block — fast-path rationalization based
on perceived task size. The developer asked the model "did you give
the spec to Claude Code in English?" and the model honestly admitted
it had skipped. The developer requested this rule be embedded in MCL
itself, not just in their personal `CLAUDE.md`.

#### Implementation

Three layers — STATIC_CONTEXT (prompt), skill files (documentation),
hook (mechanical enforcement):

1. **STATIC_CONTEXT** — new `<mcl_constraint name="no-spec-fast-path">`
   block: "Every assistant turn that calls Write / Edit / MultiEdit /
   NotebookEdit MUST include a visible 📋 Spec: block emitted BEFORE
   the tool call in the same turn. There is no 'too small' exception.
   Mid-task continuation turns count as new turns."

2. **`hooks/mcl-pre-tool.sh`** — new check inserted before secret-scan:
   when tool is Edit/Write/MultiEdit/NotebookEdit, scan the current
   turn's transcript (assistant text events after the latest user
   message) for 📋 Spec: line via the tolerant SPEC_LINE_RE. If
   absent → return `decision:block` with the required-actions reason
   text + brief-spec template. 3-strike loop-breaker
   (`spec-required-loop-broken` audit) preserves v9.0.1 fail-open.

3. **Skill files** — `asama4-spec.md` gains a "NO FAST-PATH RULE"
   section explaining the brief-spec shape acceptable for follow-up
   turns (Changes / Behavioral contract / Out of scope) so models
   can comply quickly without writing a full Aşama 4 ceremony each
   time. `anti-patterns.md` adds explicit anti-pattern entry.

#### Brief-spec shape (acceptable for follow-up turns)

```
📋 Spec:
Changes:
- file:path — what changes and why
Behavioral contract:
- the observable invariant the change preserves or introduces
Out of scope:
- explicitly excluded behaviors
```

Original full template (Objective / MUST / SHOULD / Acceptance / Edge
Cases / Technical Approach / Out of Scope) still applies for the
FIRST spec of each new task.

#### Tests

81 passing (7 new test-v10-spec-required assertions: counter logic,
hook source contract, transcript SPEC_RE detector positive/negative).

Banner: MCL 10.0.2 → MCL 10.0.3.

## [10.0.2] - 2026-05-02

### Aşama 6b hard enforcement (narrow re-introduction)

Real-use feedback (test10 backoffice prototype): even with v10.0.1's
strengthened STATIC_CONTEXT, the model wrote the entire stack
(frontend + backend + Prisma + Auth.js) in one turn, started the dev
server, ran curl checks, emitted Aşama 11 verify report — and never
asked the developer "do you approve the design?". v10.0.0 advisory
mode + v10.0.1 imperative prompt strengthening were not enough.

The strictest narrow option (A in the developer's last decision):
hook-level enforcement on Aşama 6b only. The model literally cannot
end a turn that wrote UI files in 6a without emitting an
AskUserQuestion this turn. Loop-breaker after 3 strikes preserves
the v9.0.1 "fail-open instead of trap" guarantee.

#### Implementation

- `hooks/mcl-stop.sh` — new check after the active-phase regex (which
  was also remapped from legacy `(4|4a|4b|4c|3.5)` to v9 numbering
  `(5|6a|6b|6c|7)`):
  - When `_PR_ACTIVE_PHASE = "6a"` AND `_PR_CODE = "true"` AND
    `_PR_ASKUQ != "true"`:
    - Increment `ui-review-skip-block` audit count for this session.
    - If count < 3 → return `decision: block` with localized reason
      including the required actions: dev server start, browser
      auto-open, AskUserQuestion shape (prefix, options, bare-verb
      approve label), STOP rule.
    - If count ≥ 3 → fail-open: write `ui-review-loop-broken` audit,
      force `ui_reviewed=true` and `ui_sub_phase=BACKEND` so
      downstream phases unblock.

#### Why narrow

This is the ONLY hard-block reintroduced after v10.0.0 advisory mode.
All other locks (plugin-gate, spec_approved, precision-audit,
phase-review-pending, scope-guard, etc.) remain advisory. The 6b
enforcement is the most one-step-recoverable enforcement in MCL —
the model only needs to call AskUserQuestion ONCE; it cannot fail
multiple times for unrelated reasons. Narrow scope keeps the test10
loop risk minimal.

#### Tests

74 passing (4 new test-v10-asama6b-enforcement assertions covering
loop-breaker counter behavior + hook source contract checks).

## [10.0.1] - 2026-05-02

### UI flow remap miss + auto-run + 6b AskUserQuestion strengthened

Real-use feedback: model wrote UI files but did NOT auto-run the dev
server, did NOT auto-open the browser, did NOT call the Aşama 6b
AskUserQuestion ("did you like it?"). Three causes:

1. **Numbering remap miss** — STATIC_CONTEXT `ui-flow-discipline`
   said *"Aşama 7 MUST split into 4a/4b/4c"* (still legacy). The
   `UI_FLOW_NOTICE` advisory injected on every turn said the same.
   Skill files `asama6a-ui-build.md` and `asama6c-backend.md` had
   `current_phase = 4` (legacy EXECUTE = old Phase 4). All carried
   stale numbering from the v9.0.0 mass-sed pass.
2. **Auto-run + 6b ASKQ underweighted** — instructions buried in
   one short sentence ("Auto-open the browser. STOP. ... present
   AskUserQuestion"). With v10.0.0 advisory mode, no hook enforces
   the sequence; the model treated it as suggestion.
3. **Imperative weakened** — original phrasing was passive
   ("Provide the dev-server run command when done"). Real-use
   showed model interpreted "provide" as "type out the command in
   prose for the developer to copy" rather than "execute it".

#### Fixes

- `hooks/mcl-activate.sh` STATIC_CONTEXT `ui-flow-discipline` rule
  rewritten with REQUIRED ACTIONS list (write configs FIRST → write
  components → npm install → run_in_background dev server → sleep
  3s → `open`/`xdg-open` browser → emit localized URL prose →
  STOP). Numbering migrated to 6a/6b/6c. Aşama 6b AskUserQuestion
  shape spelled out (prefix, options, approve label).
- `hooks/mcl-activate.sh` `UI_FLOW_NOTICE` (per-turn advisory)
  rewritten with the same REQUIRED ACTIONS sequence. Numbering
  migrated to 6a/6b/6c.
- `skills/my-claude-lang/asama6a-ui-build.md` entry condition
  `current_phase = 4` → `7`.
- `skills/my-claude-lang/asama6c-backend.md` entry condition
  `current_phase = 4` → `7`.

68/68 tests pass.

## [10.0.0] - 2026-05-02

### BREAKING — All MCL tool blocks removed (advisory mode)

After repeated real-use friction (test10 prototype-backoffice session
hit the same MCL LOCK loop 4× across v9.0.0 and v9.0.1 — even after
classifier fallback, regex tolerance, and 3-fail loop-breakers landed),
the developer ruled the contract too brittle for daily use and asked
to remove every MCL-side tool lock.

v10.0.0 makes MCL **advisory**:

- `hooks/mcl-pre-tool.sh` — every `decision: "block"` is now
  `decision: "approve"`, every `permissionDecision: "deny"` is now
  `permissionDecision: "allow"`. Affected gates: plugin-gate,
  TodoWrite Aşama 1-3, Task → phase dispatch, plan-critique
  substance, ExitPlanMode plan-critique, Bash → state.json write,
  secret-scan, UI-build sub-phase, pattern-scan-pending, scope-guard,
  spec_approved gate.
- `hooks/mcl-stop.sh` — every `decision: "block"` is now
  `decision: "approve"`. Affected enforcements: precision-audit
  (Aşama 2), phase-review-pending (Aşama 8), Aşama 11 verify-report
  skip detection.
- The hooks **still run** — state machine transitions, audit log
  entries, trace events, JIT askq advance, partial-spec recovery,
  /mcl-restart, /mcl-update, /mcl-finish, plugin orchestration —
  everything that was advisory before remains. Only the **tool
  blocking** is disabled.
- Banner: `🌐 MCL 9.0.1` → `🌐 MCL 10.0.0`.

### Trade-off (accepted)

- **Lost:** the contract guarantee that the model cannot write code
  without spec approval, cannot write code without precision audit,
  cannot ship without risk review, etc. Model behavior priors in
  STATIC_CONTEXT and skill files still teach the pipeline, but no
  hook prevents the model from skipping any step.
- **Gained:** zero MCL-LOCK loop risk. The framework is now purely
  documentary — it shapes model output through context injection
  but never blocks tool execution.

### Migration notes

Existing audit log entries with `... | block-* | ...` /
`... | *-block | ...` / `... | deny-tool | ...` event names remain
in `.mcl/audit.log` as historical record. New audit entries from
v10.0.0 use the same names — they record what MCL **would have
blocked** under the v9.x contract, useful for retrospective
diagnostics via `/mcl-checkup` even though no actual block fires.

### Tests

68/68 still passing. No test relied on tool-blocking behavior; all
tests exercise state transitions and audit emission, which v10.0.0
preserves.

## [9.0.1] - 2026-05-02

### Real-use bug fixes — JIT advance, scanner classifier, loop-breakers

Real-use test10 prototype-backoffice session exposed three failure
modes that combined into an infinite "MCL LOCK — spec_approved=false"
loop. v9.0.1 closes all three layers.

#### A. Scanner classifier expansion (`mcl-askq-scanner.py`)

The model emitted spec-approve questions using Turkish "Şartname"
(specification) instead of "Spec":
`MCL 9.0.0 | Şartname yukarıdaki gibi. Onaylıyor musun?`. The strict
`SPEC_APPROVE_TOKENS` list only knew "spec'i onayl"/"spec onay" and
returned `intent="other"` → JIT askq advance skipped → state stuck at
phase=1 → Write blocked.

Fixes:
- `SPEC_APPROVE_TOKENS` expanded across 14 languages (English
  spec/specification, Turkish şartname variants, Spanish
  especificación, Japanese 仕様, Korean 명세서, Chinese 规范, etc.).
- New `APPROVE_VERBS` list — generic approve-family verbs in 14
  languages (onayla, evet, kabul, aprueb, approuv, genehmig, 承認,
  승인, 批准, موافق, אשר, स्वीकार, setuju, aprovar, одобр, ...).
- `_classify_intent` now accepts question body, options list,
  selected option, and `has_spec` flag. Fallback heuristic: if no
  strict token matches but a `📋 Spec:` block exists in the
  transcript AND an approve-family verb appears in question body OR
  any option label OR the selected option, classify as
  `spec-approve`. Decouples classification from exact wording.
- PREFIX_RE strict match relaxed to fallback: when the model drops
  the `MCL X.Y.Z | ` prefix, scanner falls back to raw question
  text. Combined with the approve+spec heuristic, false positives
  are still ruled out by the spec presence requirement.

#### B. STATIC_CONTEXT hardening (`mcl-activate.sh` + `mcl-stop.sh`)

The model conflated "no GATE questions to ask" with "skip the
Aşama 2 audit emit step". Spec emitted without audit → Stop hook
hard-block → recovery loop.

Fixes:
- Aşama 2 instruction text in STATIC_CONTEXT made explicit: "emit one
  audit entry UNCONDITIONALLY ... THIS AUDIT EMIT IS MANDATORY EVEN
  WHEN ALL DIMENSIONS CLASSIFY AS SILENT-ASSUME — 'no GATE questions
  to ask' does NOT mean 'skip the audit'."
- Stop hook block reason text updated with the same clarification +
  audit emit example uses `asama2` caller (was `phase1-7` legacy
  string) + transition target text "Aşama 1→4" (was 1→2).

#### C. Loop-breakers (`mcl-stop.sh`)

When A and B both fail (e.g., model uses an unrecognized wording AND
fails to emit the audit), the user was trapped in an infinite block
loop. v9.0.1 adds a session-scoped 3-strike counter:

- New `_mcl_loop_breaker_count <event>` helper counts how many times
  the named audit event fired AFTER the most recent `session_start`
  in trace.log.
- Aşama 2 (`precision-audit-block`): on the 4th attempt, fail-open
  with `precision-audit-loop-broken` audit + `precision_audit_done`
  stays false (visible in `/mcl-checkup`).
- Aşama 8 (`phase-review-pending`): on the 4th sticky-pending turn,
  fail-open with `phase-review-loop-broken` audit + mark
  `risk_review_state=complete` so downstream Aşama 9/10/11 can
  proceed.

Trade-off: trades hard contract for soft contract on the
4th-attempt-onwards. The model gets 3 chances to recover (matching
the model's typical recovery latency); after that, the developer
is unblocked rather than trapped.

#### Tests

5 new synthetic tests (68 total, 0 failed):
- `test-v9-classifier-fallback.sh` — 5 scenarios: Şartname-fallback,
  explicit token, no-spec→summary-confirm, no-spec generic approve,
  Japanese 仕様 spec-approve.
- `test-v9-loop-breaker.sh` — 5 counter scenarios: zero baseline,
  under-threshold, threshold, session boundary, different event name.

#### Banner

- `🌐 MCL 9.0.0` → `🌐 MCL 9.0.1` everywhere.

## [9.0.0] - 2026-05-02

### Major rewrite — flat 12-stage pipeline (BREAKING)

MCL phase numbering migrates from fractional (Phase 1, 1.5, 1.7, 2, 3,
3.5, 4, 4.5, 4.6, 5, 5.5) to flat 12-stage (Aşama 1–12). State schema
v3 is incompatible with prior versions; existing `.mcl/state.json` is
reset to default on first activation under v9.0.0 (no backward-compat
migration). All skill files, hook code, audit log keys, and docs use
the new numbering.

#### New 12-stage pipeline

```
Aşama 1: Parameter gathering (was Phase 1)
Aşama 2: 7-dimension precision audit + hard enforcement (was Phase 1.7, NOW VISIBLE)
Aşama 3: Translator (was Phase 1.5; UPGRADE-TRANSLATOR for verb upgrades)
Aşama 4: Spec emit + your-language explanation + AskUserQuestion approval (was Phase 2+3 fused)
Aşama 5: Pattern Matching (was Phase 3.5, NOW VISIBLE)
Aşama 6: UI flow split (conditional, when ui_flow_active=true)
  Aşama 6a BUILD_UI / 6b UI_REVIEW / 6c BACKEND
Aşama 7: Code + TDD (was Phase 4)
Aşama 8: Risk Review — interactive AskUserQuestion dialog (was Phase 4.5 dialog parts)
Aşama 9: Quality + Tests — sequential auto-fix pipeline (was Phase 4.5 lenses + comprehensive tests)
  Aşama 9.1 code review / 9.2 simplify / 9.3 performance / 9.4 security
  Aşama 9.5 unit / 9.6 integration / 9.7 E2E / 9.8 load tests
  NO AskUserQuestion — auto-detect + auto-fix
  Soft applicability: not-applicable cases write audit + skip (yumuşak katılık)
Aşama 10: Impact Review — interactive AskUserQuestion dialog (was Phase 4.6)
Aşama 11: Verify Report (was Phase 5)
Aşama 12: Translate report EN → user_lang (was Phase 5.5)
```

#### State schema v3

- `current_phase` integer remap: `{1→1, 2→4, 4→7, 5→11}`. Validation
  range: `1 ≤ phase ≤ 11`.
- `phase_review_state` SPLIT into `risk_review_state` (Aşama 8) +
  `quality_review_state` (Aşama 9). All hook usages migrated.
- New flag: `precision_audit_done` (Aşama 2 visibility marker).
- Trace events renamed: `phase_review_pending` → `risk_review_pending`.
- Schema version bumped to 3. Old `state.json` → fresh init (no
  migration). Backup at `.mcl/state.json.pre-v9-backup`.

#### Files

- DELETED: `skills/my-claude-lang/phase3-verify.md` (Phase 3 fused into
  Aşama 4).
- RENAMED 11 skill files: `phaseN-*.md` → `asamaN-*.md`. Includes UI
  flow subdirs `phase4a-ui-build/` → `asama6a-ui-build/`.
- SPLIT: `phase4-5-risk-review.md` → `asama8-risk-review.md` (dialog) +
  `asama9-quality-tests.md` (auto-fix pipeline).
- NEW: `asama5-pattern-matching.md` (extracted from inline activate.sh
  logic into a dedicated skill artifact).

#### Hooks

- `hooks/lib/mcl-state.sh` — schema v3, validation `1 ≤ phase ≤ 11`,
  fresh init on schema mismatch, `precision_audit_done` /
  `risk_review_state` / `quality_review_state` fields, removed v1→v2
  migration, removed legacy `phase_review_state` field.
- `hooks/mcl-activate.sh` — STATIC_CONTEXT rewritten for 12-aşama
  numbering, banner version `MCL 9.0.0`, all phase references migrated.
- `hooks/mcl-pre-tool.sh` — `current_phase` integer comparisons remapped,
  JIT askq advance updated, scope guard + pattern guard reference
  Aşama 5/8.
- `hooks/mcl-stop.sh` — phase transitions {1→4, 4→7, 7→...},
  `risk_review_state` replaces `phase_review_state`, Aşama 11 skip
  detection updated, hard enforcement audit keys aligned to new
  numbering.
- `hooks/lib/mcl-askq-scanner.py`, `mcl-dispatch-audit.sh`,
  `mcl-phase-review-guard.py`, `mcl-spec-paths.py`, etc. — phase number
  refs remapped.

#### Aşama 9 — new auto-fix behavior (no dialog)

Replaces Phase 4.5 step 2 (lenses) + step 4 (comprehensive test
coverage). Eight sequential sub-steps run without AskUserQuestion:
detect issues, apply unambiguous auto-fixes, write audit entries
(`asama-9-N-start` / `asama-9-N-end findings=N fixes=M`). Soft
applicability: when a sub-step doesn't apply (E2E for CLI, load test
for calculator), audit `asama-9-N-not-applicable | reason=<why>` and
skip silently.

#### Hard enforcements (preserved)

- Aşama 2 (precision audit): Stop hook blocks Aşama 1→4 transition
  unless audit entry exists in this session.
- Aşama 8 (risk review): Stop hook blocks session-end after Aşama 7
  code if `risk_review_state ≠ complete`.
- Aşama 11 (verify report): Stop hook detects skip and forces
  Verification Report emission.

Loop-breakers (3-fail fail-open) tracked separately in v9.0.1.

#### Documentation

- `README.md`, `README.tr.md` — pipeline diagram replaced with 12-stage
  Aşama version, banner refs `MCL 9.0.0`, all Phase X references
  remapped to Aşama Y.
- `FEATURES.md` — 12-aşama feature catalog, v9.0.0 sürüm.
- `CLAUDE.md` (project) — captured rules updated to reference Aşama
  numbering.
- All 14 phase skill files internal content rewritten for new
  numbering.

#### Test

Existing 21 tests pass under v9.0.0.

### Breaking — no backward compatibility

- Old `state.json` (schema v1/v2) is reset to v3 default on first
  activation under v9.0.0. Backup written to
  `.mcl/state.json.pre-v9-backup`. In-progress task state from older
  MCL is discarded.
- Audit log entries from older MCL retain their original `phase-...`
  prefixes; new entries use `asama-...` / `risk_review_*` /
  `quality_review_*`. Mixed history is expected and acceptable.

## [8.4.5] - 2026-05-02

### Kaldırıldı — Pasif "yeni sürüm mevcut" bildirimi

`mcl-activate.sh` her turda banner'a `(⚠️ <latest> mevcut — mcl-update yaz)` lokalize uyarısını ekleyen UPDATE_NOTICE bloğunu enjekte ediyordu. Bu bildirim kaldırıldı; banner artık sadece `🌐 MCL <version>` formatında.

#### Hook
- `hooks/mcl-activate.sh` — `UPDATE_AVAILABLE` semver karşılaştırması, `UPDATE_NOTICE` enjeksiyon bloğu ve FULL_CONTEXT'teki `${UPDATE_NOTICE}` referansı silindi. LATEST_VERSION fetch + 24h cache mekanizması korundu — `/mcl-update` keyword'ünün upstream-latest raporlaması için hâlâ kullanılıyor.

#### Dokümanlar
- `README.md`, `README.tr.md` — "Updating" / "Güncelleme" bölümünden pasif kontrol paragrafı ve örnek banner çıkarıldı; `/mcl-update` self-update talimatı korundu.
- `skills/my-claude-lang/mcl-tag-schema.md` — `<mcl_audit>` kullanım örneğinden "Hook UPDATE_NOTICE prefix" maddesi silindi.

### Değişmedi
- `/mcl-update` keyword'ü tamamen aynen çalışıyor: blocking fetch ile upstream sürümü raporluyor, `git pull --ff-only && bash setup.sh` çalıştırıyor.

## [8.4.4] - 2026-05-02

### Kaldırıldı — `current_phase < 4` mutating tool bloğu

`hooks/mcl-pre-tool.sh`'in mutating-tool gate'inde iki kontrol vardı: faz numarası (`current_phase < 4`) ve onay boolean'ı (`spec_approved != true`). İki kontrol normal akışta aynı pencereyi kapatıyordu — Phase 1/2/3 ⇒ `spec_approved=false`. Faz numarası kontrolü kaldırıldı; `spec_approved` boolean'ı tek başına spec öncesi kod yazımını engellemeye yetiyor.

#### Değişiklik
- `hooks/mcl-pre-tool.sh` — `if [ "$CURRENT_PHASE" -lt 4 ]` branch'i silindi; `elif [ "$SPEC_APPROVED" != "true" ]` artık `if` olarak tek başına kalıyor.

#### Trade-off (kabul edildi)
- **Kayıp:** Defense-in-depth — `spec_approved=true` ama `current_phase<4` durumunda (state corruption / yarış) artık ikinci bir koruma yok. Hata mesajı da "current_phase=N (PHASE_NAME)" yerine sadece "spec_approved=false" gösteriyor.
- **Kazanç:** Daha sade gate — tek invariant (`spec_approved=true ⇒ Phase 4`) tüm yazma yetkisini yönetiyor.

### Banner
- Tüm `MCL 8.4.3` referansları (`🌐` banner ve `AskUserQuestion` prefix'leri) `MCL 8.4.4` olarak güncellendi.

## [8.4.3] - 2026-05-01

### Kaldırıldı — `superpowers` plugin tamamen MCL'den çıkarıldı

`superpowers` plugin'i MCL'in curated required setinde olduğu için, kurulu değilken MCL kendini kilitliyordu (mutating tool'lar bloke). Artık `superpowers` MCL'in herhangi bir parçası değil — required listesinde yok, dispatch path'lerinde yok, hook block'larında yok, dokümantasyonda yok.

#### Hook'lar
- `hooks/lib/mcl-plugin-gate.sh` — `mcl_plugin_gate_required_plugins()` artık `superpowers` döndürmüyor. Curated tier-A required = sadece `security-guidance` + stack-detected LSP plugin'leri.
- `hooks/mcl-pre-tool.sh` — `superpowers:brainstorming` Skill bloğu kaldırıldı. TodoWrite Phase 1-3 bloğunun reason metni "superpowers:brainstorming interference" referansından arındırıldı.
- `hooks/lib/mcl-dispatch-audit.sh` — Phase 4.5 code-review prefix tuple'ından `superpowers:code-reviewer` çıkarıldı. Artık sadece `pr-review-toolkit` ve `code-review` aranıyor.
- `hooks/mcl-activate.sh` STATIC_CONTEXT — `<mcl_constraint name="superpowers-scope">` bloğu tamamen silindi; sub-agent-phase-discipline ve dispatch-audit constraint'lerinden `superpowers` örnekleri çıkarıldı.

#### Skill'ler
- `skills/my-claude-lang/plugin-orchestration.md` — curated set tablosundan `superpowers` satırı silindi; phase dispatch tablosundan "Ambient" sütunu kaldırıldı; install-suggestion bloğundan ve tier-2 outcome notundan `superpowers` referansları çıkarıldı; "Out of scope" listesinden ambient methodology maddesi silindi; Phase 4.5 manifest tablosundan `superpowers:code-reviewer` çıkarıldı.
- `skills/my-claude-lang/plugin-gate.md` — curated tier-A enumeration `(security-guidance)` olarak kısaltıldı.
- `skills/my-claude-lang/plugin-suggestions.md` — orchestration-set listesinden `superpowers` çıkarıldı.
- `skills/my-claude-lang.md` — curated plugin listesinden ve "always-on ambient methodology layer" paragrafından `superpowers` referansları çıkarıldı.
- 12 phase skill dosyası (`phase1-rules`, `phase2-spec`, `phase3-verify`, `phase4-execute`, `phase4-tdd`, `phase4-5-risk-review`, `phase4-6-impact-review`, `phase4a-ui-build`, `phase4b-ui-review`, `phase4c-backend`, `phase5-review`) — her birindeki `**\`superpowers\` (tier-A, ambient):**` bullet'ı silindi.

#### Dokümanlar
- `README.md`, `README.tr.md` — Step 1 kurulum metninden `superpowers` ve `obra/superpowers-marketplace` çıkarıldı.
- `FEATURES.md` — Hook Dominance tablosundan ve listesinden `superpowers:brainstorming` satırı silindi.
- `CLAUDE.md` (proje) — devtime plan critique notundan `superpowers:code-reviewer` parantezli açıklaması çıkarıldı.
- `install-claude-plugins.sh`, `install-claude-plugins.ps1` — `obra/superpowers-marketplace` marketplace ekleme satırı ve `superpowers` install komutu kaldırıldı.

#### Test
- `tests/cases/test-plugin-gate-no-superpowers.sh` — regression: `mcl_plugin_gate_required_plugins` çıktısının `superpowers` içermediğini ve `security-guidance`'ın hâlâ listede olduğunu assert eder.

#### Banner
- Tüm `MCL 8.4.2` referansları (`🌐` banner ve `AskUserQuestion` prefix'leri) `MCL 8.4.3` olarak güncellendi.

### Geriye dönük uyumluluk

Bu kaldırma kırıcı bir değişiklik değildir — `superpowers` MCL tarafından zaten zorunlu kılınıyordu, çıkarılması mevcut MCL kullanıcıları için yalnızca bir kilit kaldırma anlamına geliyor. `superpowers`'ı manuel olarak yüklemiş olanlar için davranış değişmiyor: MCL artık onu hiçbir şekilde dispatch etmiyor veya gate'lemiyor.

## [8.4.2] - 2026-04-29

### Düzeltildi — Real-use test'in açtığı 3 kalibrasyon sapması

8.4.1 sonrası "kullanıcı listele" prompt'u ile uçtan uca (Phase 1 → 1.7 → 1.5 → 2 → 4.5) synthetic transcript simülasyonunda 4 sapma noktası tespit edildi. Bu patch ilk 3'ünü skill düzeyinde düzeltir; 4. (domain-shape coverage gap) gelecek real-use test prompt önerisi olarak kayıt altına alındı.

#### `skills/my-claude-lang/phase1-5-engineering-brief.md`
- **GATE × default çakışması çözüldü.** Yeni alt bölüm: *"Phase 1.7 GATE answers override implicit defaults"*. Phase 1.7 GATE'i bir verb'ün implicit default'unu override ettiğinde (örn. `paginate` default'u `[default: cursor pagination, changeable]` ama react-frontend GATE'i "page-numbered" cevabı aldıysa) marker `[default: ..., changeable]` yerine `[confirmed: ...]` olur. Phase 3 Scope Changes Callout `[confirmed]` marker'ını reviewable default olarak değil, geliştirici tarafından açıkça onaylanmış parametre olarak gösterir. 2 kalibrasyon örneği eklendi.
- **Implicit layer addition sınır vakası açıklandı.** Calibration Examples tablosuna 2 yeni satır: aynı prompt ("kullanıcı listele") iki Phase 1 context'iyle. Mevcut React + FastAPI context'i ile backend layer mention'ı **allowed** (zaten Phase 1 context'inde); boş context ile **forbidden** (yeni layer eklemiş olur). Boundary açık: layer mention'ı yalnızca Phase 1 confirmed context'inde varsa allowed.

#### `skills/my-claude-lang/phase1-7-precision-audit.md`
- **Sequential GATE asking explicit hale getirildi.** Question Flow step 4 strengthened: birden fazla dimension GATE classify ederse queue'lanır ve **turn'ler arası sırayla** sorulur — aynı response'ta iki GATE sorusu (madde işareti veya numaralı liste ile bile) batch'lenmez. Her GATE cevabı confirm edilip parameter set'e işaretlenmeden sıradaki GATE evaluate edilmez. Mevcut "exactly one question" + "no list of multiple questions" satırı multi-GATE durumunu açıkça kapsıyor şimdi.

### Bilinen sınır (kabul edilmiş, gelecek real-use test'e devredildi)

8.4.1 stack-detect 3 yeni domain-shape tag (cli, data-pipeline, ml-inference) ekledi ama "kullanıcı listele" prompt'u admin panel olduğu için bu tag'leri exercise etmedi. Coverage doğrulaması için 3 ek real-use test prompt'u önerildi:

- **ml-inference test:** *"csv'deki sıralanmamış müşteri tweet'lerini sentiment'a göre etiketle, model `models/sentiment.pkl`"* → `*.pkl` artifact + Python project → `[python, ml-inference]` beklenir.
- **data-pipeline test:** *"günlük satış verisini Snowflake'e taşıyan dbt pipeline'ı kur"* → `dbt_project.yml` veya dependencies'te dbt-core → `[python, data-pipeline]` beklenir.
- **cli test:** *"projedeki TODO yorumlarını listeleyen `find-todos` adında bir CLI yap, npm üzerinden çalışsın"* → `package.json` `bin` field'ı + Phase 4 sonrası → `[typescript, cli]` beklenir.

Bu prompt'lar bir sonraki manuel kalibrasyon turunda (8.4.x) çalıştırılacak; otomatik test fixture'larına dönüştürme şu an scope dışı.

### Updated files
- `skills/my-claude-lang/phase1-5-engineering-brief.md` (GATE override section + 2 calibration örneği)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (Question Flow step 4 strengthened)
- `VERSION` (8.4.1 → 8.4.2)
- `FEATURES.md` (sürüm bumpı)
- `CHANGELOG.md` (bu giriş)

## [8.4.1] - 2026-04-29

### Eklendi — Stack-detect kapsam genişletme

Phase 1.7 stack add-on tarafının coverage'ı genişletildi. Önceki sürümde TS/JS/React tek başlık altındaydı, framework spesifik dimensions yoktu. Backend/system dilleri (Java, C#, Ruby, PHP, C++, Lua) ve domain-shape (cli/data-pipeline/ml-inference) `mcl-stack-detect.sh` tarafından otomatik tespit edilmiyordu.

#### `hooks/lib/mcl-stack-detect.sh`
- **3 yeni domain-shape detect tag** eklendi (dil tag'lerinden ayrı, içerik tabanlı):
  - `cli` — `package.json` içinde `bin` field, `pyproject.toml` içinde `[project.scripts]` veya `[tool.poetry.scripts]`, `Cargo.toml` içinde `[[bin]]`, `go.mod + cmd/`, dolu `bin/` dizini.
  - `data-pipeline` — `airflow.cfg`, `dags/`, `dbt_project.yml`, `prefect.yaml/toml`, ya da `requirements*.txt` içinde apache-beam/pyspark/dagster/dask/luigi.
  - `ml-inference` — `*.pkl/*.onnx/*.pt/*.h5/*.safetensors/*.pb` model artifact'leri, `mlflow/` veya `mlruns/` dizinleri, `model_card.md` / `MODEL.md`, ya da requirements/pyproject içinde torch/tensorflow/transformers/scikit-learn/xgboost/lightgbm/bentoml/mlflow.
- False positive kabul edilmiş risk: domain-shape tag'leri Phase 1.7 dimensions için heuristic — yanlış tetiklendiğinde dimensions hâlâ general enough olduğu için spec kırılmaz.

#### `skills/my-claude-lang/phase1-7-precision-audit.md`
- `### typescript / javascript / react` başlığı `### typescript / javascript` olarak rename edildi (yalnızca web base: modül sistemi, async pattern, package manager, deployment target).
- **10 yeni stack add-on bölümü** yazıldı; her biri 3-5 delta dimension içeriyor:
  - **Frontend frameworks (dedicated):** `react-frontend` (hooks/suspense/RSC/state mgmt), `vue-frontend` (Composition API/Pinia/SFC/SSR), `svelte-frontend` (stores vs runes/server islands/$:/compiler opts), `html-static` (asset bundling/SEO/accessibility/deployment).
  - **Backend dilleri:** `java` (framework/build tool/reactive vs blocking/persistence/version), `csharp` (framework/async pattern/DI/ORM/runtime), `ruby` (framework/ORM/jobs/mode/test framework), `php` (framework/ORM/jobs/version).
  - **Sistem dilleri:** `cpp` (standard/build/memory/concurrency/platform), `lua` (runtime/coroutines/modules/C interop).
- Multi-tag union pattern: React projesi `[typescript, react-frontend]` olarak tespit edilir; framework deltas TS/JS base'inin **üzerine** uygulanır (replace değil).
- Domain-shape add-on'larının TODO comment'leri kaldırıldı — artık `mcl-stack-detect.sh` 8.4.1 ile otomatik tetikliyor.
- Solid/Angular/Qwik ve kotlin-mobile vs kotlin-backend ayrımı gelecek genişleme için TODO olarak işaretlendi.

#### `skills/my-claude-lang/all-mcl.md`
- STEP-64 description'ı 8.4.1 stack coverage genişlemesi notunu içerecek şekilde güncellendi.

### Test
- T1 phase1-7 skill'inde 13+ `### ` başlık (en az 11 add-on + 2 yapısal) PASS
- T2 stack-detect.sh içinde `_mcl_is_cli/_mcl_is_dp/_mcl_is_ml=1` flag'leri PASS
- T3 TS/JS başlığı rename edildi PASS
- T4 Tier 1 sections (vue/svelte/react-frontend/java/csharp/ruby) mevcut PASS
- T5 Tier 2 sections (php/cpp/lua/html-static) mevcut PASS
- T6 mevcut suite: 19 pass, 0 fail, 2 skip — regresyonsuz
- T7 fixture: `package.json` `"bin"` field → `cli` + `javascript` tag (multi-tag union doğrulandı) PASS
- T8 fixture: `requirements.txt` `torch==2.1.0` → `ml-inference` + `python` tag PASS
- T9 fixture: `dbt_project.yml` → `data-pipeline` tag PASS

### Updated files
- `hooks/lib/mcl-stack-detect.sh` (csharp detect block sonrasına 3 domain-shape detect bloğu eklendi)
- `skills/my-claude-lang/phase1-7-precision-audit.md` (TS/JS rename + 10 yeni section)
- `skills/my-claude-lang/all-mcl.md` (STEP-64 description)
- `VERSION` (8.4.0 → 8.4.1)
- `FEATURES.md` (Stack add-on'lar listesi 8.4.1 genişletmesini yansıtıyor)
- `CHANGELOG.md` (bu giriş)

## [8.4.0] - 2026-04-29

### Değişti — Phase 1.5 contract (BREAKING)
- **Phase 1.5 artık upgrade-translator.** 8.3.x'e kadar Phase 1.5'in tek görevi user_lang → İngilizce sadık çeviriydi (`do NOT add scope, do NOT subtract scope`). 8.4.0'da bu sözleşme bilinçli olarak gevşetildi: brief artık vague verb'leri (`list`, `listele`, `show`, `göster`, `manage`, `yönet`, `process`, `işle`, `build`, `yap`, `handle`, `update`, ...) surgical English verb'lere yükseltir (`render a paginated table`, `expose CRUD operations`, `implement`, `transform`, vb.). Verb-implied standart default'lar `[default: X, changeable]` marker'larıyla annotate edilir.
- **Mission rationale:** ana hedef "İngilizce bilmeyen geliştiriciyi senior İngilizce seviyesine çıkarmak". Approach A (Phase 1.7'ye 8th dimension) ve Approach B (Phase 1.5 upgrade-translator) trade-off değerlendirmesinden sonra B seçildi — kullanıcıyı her vague verb için soruyla yormak yerine çıktıyı senior precision'a otomatik yükseltmek hedefe daha doğrudan hizmet ediyor.

### Eklendi — Hallucination guards (3 katmanlı)
- **Skill calibration:** [`phase1-5-engineering-brief.md`](skills/my-claude-lang/phase1-5-engineering-brief.md) tamamen yeniden yazıldı. Allowed Upgrades tablosu (14-dil verb mapping), Forbidden Additions hard prohibitions listesi, 13 calibration example (allowed vs forbidden upgrade çiftleri).
- **Phase 3 Scope Changes Callout:** [`phase3-verify.md`](skills/my-claude-lang/phase3-verify.md) güncellendi. `engineering-brief audit upgraded=true` olduğunda Phase 3 prose'unda zorunlu callout — geliştirici kendi dilinde her upgrade'i görür, "edit" ile düzeltebilir. Format Türkçe örnek + 14-dil localizable.
- **Phase 4.5 Lens (e) Brief-Phase-1 Scope Drift:** [`phase4-5-risk-review.md`](skills/my-claude-lang/phase4-5-risk-review.md) güncellendi. Mevcut 4 lens (Code Review/Simplify/Performance/Security) yanına 5. lens eklendi. `upgraded=true` olduğunda zorunlu çalışır: Phase 4 implementation'ın her elementi Phase 1 confirmed parameter'a izlenebilir mi VEYA `[default: X, changeable]` marker'ı taşıyor mu kontrol; izlenemeyen + marker'sız element `[Brief-Drift]` risk olarak risk-dialog'a surface — geliştirici 3 seçenekten birini seçer (remove / mark-as-default / rule-capture).

### Audit format extension
- `engineering-brief | phase1-5 | lang=<...> skipped=<...> retries=<...> clarification=<...> upgraded=<true|false> verbs_upgraded=<count>` — yeni alanlar `upgraded` (en az bir verb upgrade edildi mi) ve `verbs_upgraded` (kaç verb).

### Updated files
- `skills/my-claude-lang/phase1-5-engineering-brief.md` — major rewrite (faithful → upgrade-translator)
- `skills/my-claude-lang/phase4-5-risk-review.md` — Lens (e) eklendi
- `skills/my-claude-lang/phase3-verify.md` — Scope Changes Callout eklendi
- `hooks/mcl-activate.sh` STATIC_CONTEXT — Phase 1.5 prose'u upgrade-translator olarak güncellendi (JSON-safe escape: backtick yerine literal backtick kullanıldı, embedded double quotes kaldırıldı)
- `skills/my-claude-lang/all-mcl.md` — STEP-58 audit format ve description'ı güncellendi
- `FEATURES.md` — Phase 1.5 contract change bölümü eklendi

### Test
- T1 skill `phase1-5-engineering-brief.md` Allowed/Forbidden/Calibration sections var PASS
- T2 skill `phase4-5-risk-review.md` Lens (e) + Brief-Drift label var PASS
- T3 skill `phase3-verify.md` Scope Changes Callout + trigger var PASS
- T4 STATIC_CONTEXT 8.4.0 upgrade-translator instruction var PASS
- T5 STEP-58 audit format `upgraded=` ve `verbs_upgraded=` field'larını içeriyor PASS
- T6 mevcut suite: 19 pass, 0 fail, 2 skip — regresyonsuz (JSON validity testleri kritikti; STATIC_CONTEXT prose'unda embedded `"Scope Changes"` literal quote'ları JSON parse'i kırıyordu, kaldırıldı — `Scope-Changes callout` formatına geçildi)

### Bilinen sınırlar (kabul edilmiş, CHANGELOG'a kayıt)
- **Phase 5.5 asimetri:** input-side upgrade (1.5) ama output-side faithful (5.5). Phase 5 raporunun geliştirici diline geri çevirisinde teknik kelime kaybı olabilir; spec ve audit trail surgical İngilizce'de korunur. Phase 4.5 Lens (e) gerçek scope drift'i yakalar.
- **Determinist disiplin değil:** upgrade kararı model semantic judgment'ına bağlı. Hedefin "deterministic AI discipline" yarısıyla değil, "senior precision" yarısıyla uyumlu. 3 katmanlı hallucination guard bu trade-off'u dengeleme amaçlı.
- **Hallucination edge cases:** "build login page" gibi eşik durumlar — skill calibration table boundary'i çiziyor ama her olası prompt için açıkça listelenmiyor. Phase 4.5 Lens (e) post-hoc safety net.
- **Behavioral test:** real-use validation manual (T7 spawn'lanmamış); sonraki sessionda gerçek prompt'la doğrulanacak.

## [8.3.3] - 2026-04-29

### Eklendi
- **Plan critique substance validation — subagent-driven gate (Gap #5).** 8.2.10 plan-critique gate Task çağrısının şeklini kontrol ediyordu (subagent_type=general-purpose + model=sonnet); `Task(prompt="say hi")` bypass'a açıktı. 8.3.3 niyet doğrulamasıyla bu açığı kapatır:
  - **`agents/mcl-intent-validator.md` (yeni)** — strict gate-keeper subagent. Sonnet 4.6 ile çalışır, prompt'u değerlendirir, single-line JSON `{"verdict":"yes"|"no","reason":"..."}` döner. Default bias: NO unless evidence is clear. Reversal pattern, trivial request, off-topic content tespit edilir.
  - **`hooks/mcl-pre-tool.sh`** — Task gate (8.2.10 shape check) substance-aware oldu: general-purpose+sonnet Task yakalandığında transcript'i tarayıp en son `Task(subagent_type=*mcl-intent-validator*)` çağrısının tool_result'ını parse eder. JSON verdict'ine göre 4 yol: `yes` → allow + state=true; `no` → `decision:block` + reason aktarımı; validator çağrılmamış → `decision:block` + "dispatch validator first" talimatı; malformed output → fail-open + `intent-validator-parse-error` audit warn.
  - **Recursion-safety:** validator agent kendi `subagent_type`'ını kullandığı için pre-tool'un general-purpose gate'i ile çakışmaz. Validator'ın Task çağrısı pre-tool'dan geçer, sonsuz loop yok.
  - **`setup.sh`** — yeni install adımı: `agents/mcl-*.md` → `~/.claude/agents/`. Sadece MCL prefix'li agent'lar kopyalanır (user agent çakışmasını önlemek için).
  - **STATIC_CONTEXT (`mcl-activate.sh`)** — `PLAN_CRITIQUE_PENDING_NOTICE` metnine 8.3.3 talimatı eklendi: "Before general-purpose plan critique Task, dispatch `Task(subagent_type='mcl-intent-validator', prompt=<same>)` first."
  - **STEP-65** — `all-mcl.md`'ye yeni: signal/pass/skip detayları, 4 audit event tipi (`plan-critique-done | intent_validated`, `plan-critique-substance-fail | intent=no|validator=not-called`, `intent-validator-parse-error`).

### Failure modes (kasıtlı tasarım)
- **Validator agent yüklü değil:** Claude Code "agent not found" → tool_result error → parse-error → fail-open. mcl check-up audit pattern'i ile yakalanır, kullanıcı setup tetikler.
- **Validator çağrılmamış:** fail-CLOSED, deterministic block (gate amacı bu).
- **Validator verdict=no:** fail-CLOSED, reason kullanıcıya iletildi.
- **Validator malformed JSON output:** fail-OPEN, audit warn. Runtime gürültüsünde kullanıcıyı kilitleme.

### Test
- T1 validator yes verdict → general-purpose Task allowed, state=true, audit `intent_validated` PASS
- T2 validator no verdict → `decision:block` + reason carried + state=false PASS
- T3 no validator call (boş transcript) → `decision:block` + `validator=not-called` audit PASS
- T4 validator returned malformed JSON → fail-open: state=true, `intent-validator-parse-error` audit, no block PASS
- T5 validator returned `{"verdict":"yes"}` (reason field eksik) → allow (verdict yeterli) PASS
- T6 iki sıralı validator (eski no, yeni yes) → en son yes alınır, allow PASS
- T7 mevcut suite: 19 pass, 0 fail, 2 skip — regresyonsuz

### Bilinen sınır
- **Setup gereksinimi:** `~/.claude/agents/` altına agent kopyalanmadıysa (setup.sh çalıştırılmamış) ilk plan-critique fail-open path'inden geçer; mcl check-up ile farkedilir. Acceptable v1 davranışı.
- **Sonnet self-leniency:** validator strict bias verilse de %100 değil. Adversarial coordinated bypass teorik mümkün; cost-benefit analizi pahalı bypass'ı düşük olasılık yapıyor.
- **Tek-tur akış:** validator + general-purpose Task aynı turda sıralı dispatch edilmeli; multi-turn akışlar henüz desteklenmiyor.

## [8.3.2] - 2026-04-29

### Değişti
- **Phase 1.7 Precision Audit hard-enforced (Phase 4.5 tier).** 8.3.0'da skip-detection-only olarak çıkmıştı (audit-only warn). Determinist AI disiplini hedefini doğrudan etkilediği için decision:block enforcement'a yükseltildi:
  - `mcl-stop.sh` `case 1)` (Phase 1→2 transition) branch'inde, `📋 Spec:` block emit edildi AND audit log'da current session içinde `precision-audit` entry yoksa: state mutation atlanır (transition rewind), `decision:block` JSON stdout'a yazılır, hook çıkar. Claude aynı response içinde Phase 1.7'i çalıştırıp spec'i precision-enriched parametrelerle yeniden emit etmek zorunda.
  - İki audit event yazılır: `precision-audit-skipped-warn | mcl-stop.sh | summary-confirmed-but-no-audit` (8.3.0 backward compat) + `precision-audit-block | mcl-stop.sh | summary-confirmed-but-no-audit; transition-rewind` (yeni 8.3.2 enforcement).
  - **English-language safety valve:** detected language English ise `mcl_audit_log "precision-audit" "phase1-7" "core_gates=0 stack_gates=0 assumes=0 skipmarks=0 stack_tags= skipped=true"` emit edilir → block clear olur. STATIC_CONTEXT'te ve skill dosyasında prose ile İngilizce yolu belgelendi.
  - **Recovery:** false-positive durumunda `/mcl-restart` ile state temizlenir; `mcl-pre-tool.sh` zaten direct state.json bash yazımlarını blokluyor (state-machine bypass yok).

### Test
- T1 spec emit + audit yok + non-English → `decision:block` fire, state phase=1 kaldı, her iki audit event yazıldı PASS
- T2 spec emit + `precision-audit ... skipped=false` audit + non-English → block YOK, transition phase=2 PASS
- T3 KRİTİK: spec emit + `skipped=true` audit (English skip path) → block YOK, transition gerçekleşti, ne skip-warn ne block audit yazıldı PASS — İngilizce kullanıcılar block görmüyor doğrulandı
- T4 already-phase-2 (re-emit spec same session) → case 1) fire etmez, block path atlanır PASS
- T5 mevcut test suite: 19 pass, 0 fail, 2 skip — regresyonsuz

### Güncellenen dosyalar
- `hooks/mcl-stop.sh` — case 1) branch'ine block emit + audit + exit eklendi
- `skills/my-claude-lang/phase1-7-precision-audit.md` — "Enforcement (since 8.3.2)" + "Recovery" bölümleri
- `skills/my-claude-lang/all-mcl.md` — STEP-64 güncellendi: hard-enforcement açıklaması, English safety valve, iki audit event signal
- `hooks/mcl-activate.sh` STATIC_CONTEXT — Phase 1.7 prose'u "stop hook will block-and-rewind otherwise" + İngilizce safety valve cümlesi eklendi

## [8.3.1] - 2026-04-29

### Dokümantasyon
- **Phase 1.7 skill dosyasına "Scope and Extensibility" bölümü eklendi.** Stack add-on listesindeki spesifik dil/framework isimleri (TypeScript, Python, Go, Rust, Swift, Kotlin, vb.) örnektir — kapsamlı değildir. MCL evrensel bir araçtır: 7 core dimension her projede sabit kalır, stack add-on katmanı `mcl-stack-detect.sh` tag'lerine göre veri-odaklı genişler. Yeni stack tag eklendiğinde bu dosyaya yeni section eklenir; classification engine logic değişmez. Mevcut listeler korundu, sadece çerçeveleme netleştirildi.

## [8.3.0] - 2026-04-29

### Eklendi
- **Phase 1.7 — Precision Audit (yeni faz, ana misyon).** Phase 1'in "completeness" disiplinini "precision" ile tamamlar. Senior İngilizce geliştiricinin analitik düşünme davranışını sistemleştirir: confirmed Phase 1 parametreleri için 7 core boyut + stack-detect-driven add-on boyutları walk edilir.
  - **Core 7 boyut:** Permission/access, algorithmic failure modes, out-of-scope boundaries, PII handling, audit/observability, performance SLA, idempotency/retry. UX state'ler (empty/loading/error UI) **core'da DEĞİL** — UI stack add-on'larında.
  - **3 sınıflandırma:** SILENT-ASSUME (`[assumed: X]`), **SKIP-MARK** (yeni 3. kategori — `[unspecified: X]`, şu an yalnızca Performance SLA için), GATE (tek soru sor, one-question-at-a-time rule).
  - **Stack add-on'lar:** typescript/javascript/react, python, go/rust, cli, data-pipeline, mobile, ml-inference. Vue/Svelte/Angular ayrımı v1'de tek TS/JS/React başlığı altında — skill dosyasında TODO comment ile gelecek genişleme işaretli.
  - **English session skip:** `skipped=true` audit ile no-op (behavioral prior yeterli kabul).
  - **Detection control:** `mcl-stop.sh` Phase 1→2 transition'ında audit'te `precision-audit` yoksa `precision-audit-skipped-warn` yazar.
- **Files:** `skills/my-claude-lang/phase1-7-precision-audit.md` (yeni skill, 7 core dim + 7 stack add-on + sample questions); `skills/my-claude-lang.md` (pointer satırı); `skills/my-claude-lang/all-mcl.md` (STEP-64); `hooks/mcl-activate.sh` STATIC_CONTEXT (Phase 1 → 1.7 → 1.5 → 2 sıralaması); `hooks/mcl-stop.sh` (skip-detection bloğu Phase 1→2 case branch'inde).

### Test
- Skill dosyası mevcut, 7 core dim + 7 stack section + SKIP-MARK + Vue/Svelte TODO PASS
- Pointer line `skills/my-claude-lang.md`'de PASS
- STEP-64 `all-mcl.md`'de PASS
- Skip-detection: spec emit + audit boş → `precision-audit-skipped-warn` yazıldı PASS
- Skip-detection: spec emit + `precision-audit` audit var → warn yazılmadı PASS
- English session skip: `skipped=true` audit → warn yazılmadı PASS
- Stack tag listesi (7 add-on) skill dosyasında doğrulandı PASS
- Mevcut test suite: 19 pass, 0 fail, 2 skip — regresyonsuz

### Out of scope (gelecek iterasyonlar)
- `PRECISION_AUDIT_PENDING_NOTICE` activate hook injection — v1'de behavioral + audit detection yeterli kabul edildi. Gerekirse v2'de eklenir.
- `precision_audit_done` state field — v1'de behavioral phase, audit-driven detection. Yeni state field eklenmedi.
- Per-project dimension override (`.mcl/precision-config.json`) — v1: skill dosyası tek truth source.
- Vue/Svelte/Angular framework-specific stack add-on'ları — TODO comment skill dosyasında.

## [8.2.13] - 2026-04-29

### Düzeltildi
- **`/mcl-restart` JIT defeat bug.** Aynı session içinde `/mcl-restart` çağrıldığında JIT promote (pre-tool 482-485), transcript'te hâlâ duran pre-restart spec-approve askq'sini bularak state'i `phase=4, spec_approved=true, spec_hash=<old>` olarak geri alıyordu. Stop hook "askq-idempotent" branch'inde sessiz kaldığı için düzeltme yapmıyordu. Sonuç: developer'ın restart kararı görsel olarak başarılı, gerçekte etkisiz.
- **Çözüm — `restart_turn_ts` filter:**
  - `hooks/lib/mcl-state.sh`: default state'e `restart_turn_ts: null` field eklendi.
  - `hooks/mcl-activate.sh`: `/mcl-restart` branch'i `restart_turn_ts=$(date +%s)` yazıyor; session boundary reset listesine `restart_turn_ts null` eklendi.
  - `hooks/lib/mcl-askq-scanner.py`: opsiyonel ikinci CLI argv'i (`min_ts_epoch`) eklendi. Transcript entry'sinin `timestamp` ISO 8601 alanı parse edilip epoch'a çevrilir; min_ts'ten önce olan girişler atlanır. Defansif: timestamp parse edilemezse entry korunur.
  - `hooks/mcl-pre-tool.sh` JIT bloğu + `hooks/mcl-stop.sh` askq scanner çağrısı `restart_turn_ts` değerini scanner'a geçirir.

### Test
- T1 `/mcl-restart` → `state.restart_turn_ts` epoch integer set PASS
- T2 Scanner direct: pre-restart askq + min_ts > entry ts → `intent=""` (filtrelendi) PASS
- T3 E2E: pre-restart askq + `/mcl-restart` + Write → JIT mutate etmedi, state phase=1 kaldı, Write phase gate ile bloklandı (`deny-tool`), `askq-advance-jit` audit YOK PASS
- T4 E2E: pre-restart askq + `/mcl-restart` + FRESH spec + FRESH approve askq + Write → JIT fresh askq'yi seçti (post-restart timestamp), promote edildi, audit'te `askq-advance-jit` VAR PASS
- T5 Mevcut suite: 19 pass, 0 fail, 2 skip — regresyonsuz PASS

### Bilinen takip — out of scope
- **Stop hook plaintext-approve fallback bug.** `mcl-stop.sh` 244-294 satırlarındaki "plaintext approve fallback" kodu transcript'in son user mesajını okur ve `onayla/yes/approve` gibi free-text approve word geçiyorsa askq olmadan da `ASKQ_INTENT=spec-approve` synthesize eder. Bu kod yolu scanner kullanmıyor — `restart_turn_ts` filter etkilemiyor. `/mcl-restart` sonrası user yeni bir mesajda "approve" derse veya eski yapay-onay metnini içeren bir mesaj zincirleme tespit edilirse aynı defeat yaşanabilir. Ayrı fix gerektirir; bu release'in scope'unda değil. (Takip için spawn_task açıldı.)

## [8.2.12] - 2026-04-29

### Dokümantasyon
- **Bilinen sınırlama: post-tool hook race in parallel tool batches.** Claude Code resmi hook lifecycle belgesine göre `PreToolUse` hook'ları serileşik fire eder (race yok), ancak `PostToolUse` hook'ları async ve non-deterministic sırada fire eder — paralel tool batch'inde 2+ post-tool süreci aynı anda `state.json` yazabilir. `mcl-state.sh::_mcl_state_write_raw` tmp+rename atomik ama field-level merge yapmaz, dolayısıyla `mcl-post-tool.sh`'in yazdığı `last_write_ts` ve `regression_block_active` alanları için race noktası mevcut.
- **Etki seviyesi düşük-orta:** `last_write_ts` kaybı yalnızca regression-guard smart-skip'i etkiler (perf, korrektlik değil); `regression_block_active=false` kaybı `mcl-stop.sh`'in regression-guard re-evaluation'ı ile sonraki turda telafi edilir (eventual consistency).
- **Mitigasyon kasıtlı eklenmedi.** flock veya field-merge complexity > value değerlendirildi. Kaynak: [code.claude.com/docs/en/hooks.md](https://code.claude.com/docs/en/hooks.md).
- **`FEATURES.md`'ye "Bilinen Sınırlamalar / Known Limitations" bölümü eklendi** — race senaryosu somut bir örnekle dokümante edildi (paralel `Write` + `Bash` GREEN), etki analizi ve mitigasyon kararı kayıt altına alındı.

## [8.2.11] - 2026-04-29

### Eklendi
- **Session Context Bridge — cross-session bilgi köprüsü (`mcl-stop.sh`, `mcl-activate.sh`, `all-mcl.md`):**
  - **Hook (`mcl-stop.sh`):** `trap EXIT` ile her Stop'ta (early-exit'ler dahil) `.mcl/session-context.md` yazılır. Markdown 4-6 satır: aktif faz + spec hash kısa hex, son commit SHA + subject (60 char trim), state-driven sıradaki adım (`phase_review_state`/`pattern_scan_due`/`plan_critique_done`/phase numarası kural tablosu), opsiyonel yarım plan veya Phase 4.5 başlatılmamış uyarısı. Atomic write (tmp + rename). Git project dir'de çalıştırılır (`CLAUDE_PROJECT_DIR` veya cwd) — non-git projelerde commit satırı omit edilir.
  - **Auto-display (`mcl-activate.sh`):** Session boundary'de (`SESSION_ID != plugin_gate_session`) `.mcl/session-context.md` okunur ve `SESSION_CONTEXT_NOTICE` olarak `<mcl_audit name="session-context">` bloğuyla `additionalContext`'e enjekte edilir. Aynı session içinde re-inject yok. JSON-safe escape (`\\\"` + `\\n`).
  - **STEP-63:** `skills/my-claude-lang/all-mcl.md`'ye `session-context-bridge` adımı eklendi. `audit.log`'da `session-context-injected` event ile pass koşulu doğrulanır.

### Test
- Stop → `.mcl/session-context.md` oluşturulur (trap EXIT) PASS
- Phase 4 + spec hash → "Aktif iş: Phase 4 (EXECUTE) — spec abc12345" satırı PASS
- `phase_review_state="pending"` → "Sıradaki adım: Phase 4.5 risk review başlat" + "Yarım iş: Phase 4.5 başlatılmadı" satırları PASS
- Plan dosyası + `plan_critique_done=false` → "Yarım plan: .claude/plans/myplan.md — critique pending" satırı PASS
- Yeni session boundary → `SESSION_CONTEXT_NOTICE` enjekte edildi PASS
- Aynı session devam → notice yok (boundary-only) PASS
- Mevcut test suite: 19 pass, 0 fail, 2 skip — regresyonsuz

## [8.2.10] - 2026-04-29

### Eklendi
- **Gap 3 — Plan critique subagent enforcement trinity (`mcl-state.sh`, `mcl-pre-tool.sh`, `mcl-activate.sh`, `mcl-stop.sh`):**
  - **State schema:** `plan_critique_done: false` alanı eklendi (`mcl-state.sh` default state). Session boundary'de `mcl-activate.sh` resetler.
  - **Hook (`mcl-pre-tool.sh`):** İki intercept eklendi: (a) `Task` çağrısı `subagent_type=*general-purpose*` + `model=*sonnet*` ise `plan_critique_done=true` set edilir; (b) `ExitPlanMode` çağrısı `plan_critique_done=false` durumundayken `decision:block` ile reddedilir, audit `plan-critique-block | tool=ExitPlanMode plan_critique_done=false` yazılır. Block reason'ı Claude'a `Task(general-purpose, sonnet)` çağırmasını söyler.
  - **Reset on plan-file Write/Edit:** `mcl-pre-tool.sh` end-of-flow'a yeni blok eklendi — Write/Edit/MultiEdit `*/.claude/plans/*.md` veya `.claude/plans/*.md` patterni'ne uyduğunda `plan_critique_done=false` resetlenir. Plan içeriği değiştiyse yeni critique gerekir.
  - **Auto-display (`mcl-activate.sh`):** Her turda `.claude/plans/*.md` dosyası varsa ve `plan_critique_done!=true` ise `PLAN_CRITIQUE_PENDING_NOTICE` enjekte edilir. Pre-tool gate'in proaktif sinyali — Claude'a critique yapmadan ExitPlanMode'un bloklanacağı önceden bildirilir.
  - **Meta-control (`mcl-stop.sh`):** Eğer son assistant turda `ExitPlanMode` tool_use var VE state hâlâ `plan_critique_done=false` ise audit'e `plan-critique-skipped-warn | tool=ExitPlanMode plan_critique_done=false` yazılır. Pre-tool blokladıysa state değişmemiş olur — defense-in-depth.

### Test
- ExitPlanMode + plan_critique_done=false → `decision:block` + audit PASS
- Task(general-purpose, sonnet) → state=true → ExitPlanMode passes PASS
- Plan exists + state=false → `PLAN_CRITIQUE_PENDING_NOTICE` injected PASS
- Plan exists + state=true (same session) → notice yok PASS
- Write to .claude/plans/foo.md (Phase 4) → state false'a resetlenir + audit PASS
- Stop ExitPlanMode + state=false → `plan-critique-skipped-warn` audit PASS
- Stop ExitPlanMode + state=true → audit warn yok PASS
- Block decision JSON valid + activate JSON valid PASS
- Mevcut test suite (19 pass, 0 fail, 2 skip) regresyonsuz

## [8.2.9] - 2026-04-29

### Eklendi
- **Gap 2 expansion — Root cause chain enforcement all-mode scope (`mcl-activate.sh`, `mcl-stop.sh`, `all-mcl.md`):**
  - **Activate user-message trigger:** 14 dilli heuristik keyword seti (`neden`, `çalışmıyor`, `bug`, `why`, `broken`, `error`, vb. — TR/EN/ES/FR/DE/JA/KO/ZH/AR/HE/HI/ID/PT/RU) `PROMPT_NORM` içinde substring match edilir. Eşleşirse `ROOT_CAUSE_DISCIPLINE_NOTICE` enjekte edilir. Plan-mode tetikleyici varsa o kazanır (yeni blok `[ -z "$ROOT_CAUSE_DISCIPLINE_NOTICE" ]` guard'ı ile atlanır) — tek audit, tek inject. Yeni audit detail: `source=user-message`.
  - **Stop always-on scan:** `mcl-stop.sh`'a Gap 2 ExitPlanMode bloğunun yanında ikinci scan eklendi. Her turda transcript'ten son user mesajı + son assistant text+tool inputs okunur. User mesajında trigger varsa assistant 3 keyword çifti için (EN/TR) taranır; eksikse audit `root-cause-chain-skipped-warn | source=all-mode missing=<list>`. Trigger yoksa scan atlanır (no audit). 8.2.8 ExitPlanMode bloğu bit-for-bit korundu — iki blok aynı turda fire edebilir, `source=` alanıyla ayırt edilir, auto-display her ikisini de yakalar.
  - **STEP-62 güncellendi:** Phase satırı `Plan-mode (devtime) + Any turn (user-message trigger, since 8.2.9)`. Signal/Pass/Skip bölümleri yeni `source=user-message` ve `source=all-mode` audit alanlarıyla detaylandırıldı.

### Test
- TR trigger user-message (`bu neden çalışmıyor`) → notice + `source=user-message` audit PASS
- EN trigger user-message (`the login is broken`) → notice PASS
- Plan file + user trigger aynı anda → tek audit, plan-mode kazanır PASS
- Nötr prompt → notice/audit yok PASS
- Stop always-on: TR trigger + 3 check eksik → `source=all-mode missing=...` audit PASS
- Stop always-on: trigger + 3 EN check var → warn yok PASS
- Stop always-on: trigger yok → scan atlanır, warn yok PASS
- Gap 2 ExitPlanMode bloğu regression: hala `missing=...` (source field yok) yazıyor PASS
- Activate JSON valid (4 case: no notice / user-msg / plan-mode / both) PASS
- Mevcut test suite: 19 pass, 0 fail, 2 skip (regresyonsuz)

### Bilinen risk (kabul edilmiş)
- Common-word false positives (`fail`, `error`, `bug`, `issue` EN'de çok yaygın): notice non-blocking olduğundan kabul edildi.

## [8.2.8] - 2026-04-29

### Eklendi
- **Gap 2 — Root cause chain enforcement trinity (`mcl-activate.sh`, `mcl-stop.sh`, `all-mcl.md`):**
  - **Hook (`mcl-activate.sh`):** `.claude/plans/*.md` dosyalarından biri current session içinde (son `session_start` event'inden sonra) modify edildiyse `ROOT_CAUSE_DISCIPLINE_NOTICE` `additionalContext`'e enjekte edilir. Notice metni Claude'a plan turn'unda 3 check'i (visible process / removal test / falsification) görünür şekilde yazmasını söyler.
  - **Meta-control (`mcl-stop.sh`):** Son assistant turun'da `ExitPlanMode` tool_use varsa, turun text content'i + tool input'ları case-insensitive olarak üç keyword çifti için taranır (EN OR TR per pair): `removal test` / `kaldırma testi`, `falsification` / `yanlışlama`, `visible process` / `görünür süreç`. Bir çiftin ne EN ne TR formu bulunamazsa audit'e `root-cause-chain-skipped-warn | mcl-stop.sh | missing=<list>` yazılır.
  - **Auto-display (`mcl-activate.sh`):** Audit log'da current session içinde `root-cause-chain-skipped-warn` entry'si varsa `ROOT_CAUSE_CHAIN_WARN_NOTICE` enjekte edilir — Claude'a planı yeniden 3 check'le birlikte emit etmesini söyler.
  - **STEP-62:** `skills/my-claude-lang/all-mcl.md`'ye `root-cause-chain-discipline` adımı eklendi.

### Test
- Plan file mtime + activate hook → ROOT_CAUSE_DISCIPLINE_NOTICE PASS
- ExitPlanMode + keyword yok → audit warn PASS
- ExitPlanMode + EN keyword'lar → warn yok PASS
- ExitPlanMode + TR keyword'lar → warn yok (TR pattern eşleşiyor) PASS
- Activate JSON valid + WARN notice present (audit fired) PASS
- Mevcut test suite (19 pass, 0 fail, 2 skip) regresyonsuz

## [8.2.7] - 2026-04-29

### Eklendi
- **Gap 1 — Phase 5 skip detection trinity (`mcl-stop.sh`, `mcl-activate.sh`, `all-mcl.md`):**
  - **Hook (`mcl-stop.sh`):** Stop hook her turda `phase_review_state` kontrol eder. State `running` ise ve bu turda MCL prefix'li AskUserQuestion çalışmamışsa (`ASKQ_INTENT` boş — Phase 4.5/4.6 dialog'u devam etmemiş), audit'e `phase5-skipped-warn | mcl-stop.sh | phase_review_state=running` yazar. State-driven tespit (transcript taraması yok) → anormal session exit'lerinde de skip yakalanır.
  - **Meta-control (4 hook):** `mcl-stop.sh`, `mcl-activate.sh`, `mcl-pre-tool.sh`, `mcl-post-tool.sh` her başarılı çalışmada `.mcl/hook-health.json`'a kendi alanını (`stop`, `activate`, `pre_tool`, `post_tool`) epoch timestamp olarak yazar. Atomic write (tmp + rename). `mcl check-up` STEP-61 eksik veya 24 saatten eski bir alan görürse WARN — hook'un settings.json'dan düşmüş veya sessizce başarısız olduğunu yakalar.
  - **Auto-display (`mcl-activate.sh`):** `audit.log`'da current session (son `session_start` event'inden sonra) `phase5-skipped-warn` entry'si varsa `PHASE5_SKIP_NOTICE` `additionalContext`'e enjekte edilir. Pattern `REGRESSION_BLOCK_NOTICE`'a benzer — Claude bir sonraki turda Phase 5 Doğrulama Raporu'nu çalıştırmaya yönlendirilir.
  - **STEP-60 + STEP-61:** `skills/my-claude-lang/all-mcl.md`'ye iki yeni adım: `phase5-skip-detection` (Stop fazında) ve `hook-health-check` (mcl check-up fazında).

### Test
- `phase_review_state="running"` set + `mcl-stop.sh` → audit `phase5-skipped-warn` PASS
- `phase_review_state=null` set + `mcl-stop.sh` → audit warn yok PASS
- `hook-health.json` sil + 4 hook çalıştır → tüm 4 alan yazılı PASS
- `mcl-activate.sh` JSON çıktısı geçerli (clean + audit warn aktif) PASS
- Mevcut test suite (19 pass, 0 fail, 2 skip) regresyonsuz

## [8.2.6] - 2026-04-28

### Değişti
- **`mcl_get_active_phase()` migration — 4 çift-okuma noktası:**
  - `mcl-stop.sh:374-376`: Phase Review Guard'daki `current_phase` + `spec_approved` çift okuması kaldırıldı, `mcl_get_active_phase()` ile değiştirildi
  - `mcl-stop.sh:474`: Pattern scan early clearance'daki `current_phase` okuması kaldırıldı
  - `mcl-stop.sh:802`: Pattern scan late fallback'deki `current_phase` okuması kaldırıldı
  - `mcl-activate.sh:353-354`: Respec Guard'daki `spec_approved + current_phase >= 4` Python inline okuması kaldırıldı
  - Tüm noktalar `grep -qE '^(4|4a|4b|4c|4\.5|3\.5)$'` koşuluyla helper sonucunu kullanıyor
  - Mevcut state field'lar dokunulmadı (extension over modification)

## [8.2.5] - 2026-04-28

### Değişti
- **Devtime Plan Critique — 10 lens + model seçimi:** Lens listesi 5'ten 10'a genişledi: halüsinasyon kontrolü, mevcut özelliklerle çakışma, extension over modification, kullanıcı görünürlüğü, test edilebilirlik eklendi. Subagent modeli `claude-sonnet-4-6` extended thinking olarak explicit belirtildi — ana oturum (Opus 4.7) ile farklı model, gerçek ikinci göz bias çeşitliliği; critique reasoning için ideal, ~5x daha ucuz.

## [8.2.4] - 2026-04-28

### Eklendi
- **Devtime Plan Critique (CLAUDE.md):** MCL geliştirme oturumlarında plan üretildiğinde otomatik olarak `superpowers:code-reviewer` subagent açılır ve planı 5 lens ile eleştirir: (1) kök sebep derinliği, (2) yan etki tahmini, (3) boş/eksik durumlar, (4) disambiguation eksiği, (5) plan belirsizliği. Critique plan'la birlikte sunulur; Ümit kabul/red eder. Sadece devtime — runtime'da tetiklenmez.

## [8.2.3] - 2026-04-28

### Eklendi
- **`mcl_get_active_phase()` helper (`mcl-state.sh`):** `current_phase` + `spec_approved` + `phase_review_state` + `ui_sub_phase` + `pattern_scan_due` + `spec_hash` okuyarak tek bir effective phase string döndürür: `"1"`, `"2"`, `"3"`, `"3.5"`, `"4"`, `"4a"`, `"4b"`, `"4c"`, `"4.5"`, `"4"` (pending), `"?"`. Extension over modification — mevcut state field'lar dokunulmaz. Hook'lardaki çift-okuma noktaları bu helper'ı kullanabilir.
  - Phase 3 phantom: `current_phase=2` + `spec_hash` set → `"3"` olarak türetilir, yeni state field gerektirmez.
  - `pending → running` geçişi: AskUQ-bağımlı tasarım doğru — Phase 4.5 her zaman AskUserQuestion ile başlıyor, `pending`'de kalma yanlış dala düşürme riski yok.
  - 4.5 vs 4.6 ayrımı: her ikisi de `phase_review_state="running"` — state'ten ayırt edilemiyor, transcript analizi gerekiyor (helper `"4.5"` döndürüyor, callers notlandırıldı).

## [8.2.2] - 2026-04-28

### Eklendi
- **`docs/root-cause-discipline.en.md`:** Root Cause Discipline tam İngilizce çevirisi (9 bölüm). MCL iç dili İngilizce olduğu için operasyonel referans bu dosya; Türkçe versiyon insan referansı olarak kalıyor.

### Değişti
- **CLAUDE.md:** Root Cause Discipline referansı `.en.md`'ye güncellendi.
- **`mcl-rollback.md`:** Hardcoded Türkçe çıktı kaldırıldı. Satır 12 (checkpoint yok mesajı) ve satır 19-29 (rollback template) artık developer'ın algılanan diline göre üretiliyor. Teknik tokenlar (git komutları, SHA) İngilizce kalıyor.

## [8.2.1] - 2026-04-28

### Değişti
- **Phase 3.5 kademeli arama (boş pattern_summary fix):** `mcl-pattern-scan.py` tek seviyeden 4 seviyeli cascade'e dönüştürüldü.
  - **Level 1 (mevcut):** scope_paths sibling dosyaları
  - **Level 2 (yeni):** sibling yoksa proje genelinde aynı uzantılı dosyalar, en son değiştirilen 8 tane
  - **Level 3 (yeni):** proje dosyası yoksa ekosistem standardı (TypeScript strict, Python PEP 8, Go idiomatic, vb.) — `mcl-activate.sh` build-in knowledge'dan PATTERN SUMMARY yazar
  - **Level 4 (yeni):** ekosistem tespit edilemezse kullanıcıya tek soru
- `mcl-stop.sh`: exit code 3 → Level 3/4 dallanması; `pattern_level` ve `pattern_ask_pending` state'e yazılır
- `mcl-activate.sh`: PATTERN_MATCHING_NOTICE level'a göre farklılaştı — Level 1/2 dosya listesi, Level 3 ekosistem direktifi, Level 4 kullanıcıya sor
- `mcl-state.sh`: `pattern_level` ve `pattern_ask_pending` schema'ya eklendi

## [8.2.0] - 2026-04-28

### Eklendi
- **`docs/root-cause-discipline.md`:** Root Cause Discipline tam spesifikasyonu. 9 bölüm: temel düstur, zincir ilerleyişi, halka başına 3 check (görünür süreç → removal test → falsification; sıralı, paralel değil), halka geçişi sonucu, edge case, müdahale noktası seçimi (sıfır yan etki halkası), kök sebep + çözüm raporu, kapsam, özet.

### Değişti
- **CLAUDE.md — Root Cause Discipline:** Hem devtime hem runtime kuralları `docs/root-cause-discipline.md` referansıyla güncellendi. 3 check sıralı, sıfır yan etki halkası, kök sebep + çözüm + doğrulama, tıkanırsa şeffaflık kuralları eklendi.
- **`mcl-activate.sh` Root Cause Chain direktifi:** 3 check (görünür süreç, removal test, falsification), müdahale noktası (sıfır yan etki halkası), risk item formatı (kök sebep + önerilen çözüm + çözüm doğrulama), zincir tıkanınca şeffaflık kuralları eklendi.

## [8.1.9] - 2026-04-28

### Eklendi
- **Root Cause Discipline (CLAUDE.md):** İki yeni kural `## Root Cause Discipline` başlığı altında.
  - *Devtime:* "Bu neden böyle?" sorusunu tekrarla — cevap geldiğinde tekrar sor. En alttaki sebebi bul. Bazen tek sebep tüm ağı çözer.
  - *Runtime (Root Cause Chain):* Phase 4.5 Root Cause Lens tek seviyeden çok seviyeli zincire dönüştürüldü. Bir sebep bulununca durmaz; "bu sebebin de kök sebebi var mı?" diye tekrar sorgular. En yapısal sebebi risk item olarak raporlar. Anti-sycophancy gibi temel: atlanması yasak.
- **`mcl-activate.sh` Root Cause Chain direktifi:** `pattern-compliance` bloğundaki "Root Cause Lens" metni "Root Cause Chain" olarak güncellendi. Çok seviyeli iniş, en derin yapısal sebep hedefi ve "Phase 4.5 tamamlanmış sayılmaz" zorunluluğu eklendi.

## [8.1.8] - 2026-04-28

### Eklendi
- **Phase 1.5 Failure Path:** Brief, Phase 1 onaylı parametrelerle çelişirse sessiz fallback yasak. Her denemede yaklaşım değiştirilerek retry; eksik bilgi kaynaksa geliştiriciye tek soru sorulur. Tutarlılık kriterleri belgelendi. Audit kaydına `retries` ve `clarification` alanları eklendi.
- **Phase 4.6 "apply fix" semantiği:** "Apply fix" seçeneğinin Phase 4.6 içinde in-place patch anlamına geldiği, Phase 4'e geri dönüş olmadığı belgelendi. Çok büyük fix için next-session yönlendirmesi eklendi.
- **CLAUDE.md — runtime kural:** Bozulma tespit edildiğinde sessiz fallback yasak; yaklaşım değiştirerek retry, eksik bilgiyse tek soru.
- **CLAUDE.md — devtime kural:** MCL geliştirirken tur başına tek soru — "tek adım per tur" kuralının soru dizileri için daha katı versiyonu.

## [8.1.7] - 2026-04-28

### Eklendi
- **Phase 1.5 — Engineering Brief:** `skills/my-claude-lang/phase1-5-engineering-brief.md` oluşturuldu. Phase 1 onayı sonrası, Phase 2 öncesinde dahili İngilizce Engineering Brief üretilir. Geliştirici görmez; Phase 2 spec'in üzerine inşa ettiği anlam köprüsüdür. Kaynak dil İngilizce ise sessizce atlanır. Her iki durumda da `engineering-brief` audit kaydı düşer.
- **Phase 5.5 — Localize Report:** `skills/my-claude-lang/phase5-5-localize-report.md` oluşturuldu. Phase 5 Doğrulama Raporu üretildikten sonra, emisyon öncesinde tüm geliştirici-facing metin (bölüm başlıkları, hüküm kelimeleri, prose) geliştiricinin diline çevrilir. Teknik token'lar İngilizce kalır. Kaynak dil İngilizce ise atlanır. `localize-report` audit kaydı her durumda düşer.
- **STEP-58 ve STEP-59:** `all-mcl.md`'e eklendi — her iki yeni fazın checkup adımı tanımlandı.
- **`skills/my-claude-lang.md`:** Phase 1.5 ve Phase 5.5 pointer satırları eklendi; Phase 1 açıklaması Phase 1.5'e yönlendirildi.

### Değişti
- **CLAUDE.md — test dili:** "14 dilde test et" kuralı "Türkçe'de test et" olarak güncellendi. Dil *desteği* 14 dili kapsar; dil *testi* yalnızca Türkçe kullanır.
- **CLAUDE.md — behavioral → dedicated kuralı:** Behavioral olarak çalışan her MCL özelliğinin dedicated faz/skill/hook olması gerektiği, mümkün değilse atlama tespit eden kontrol eklenmesi gerektiği prensip olarak eklendi.

## [8.1.6] - 2026-04-28

### Düzeltme
- **Regression Guard akıllı atlama — staleness kontrolü:** 8.1.5'te `age < 120s` yeterliydi ama green-verify sonrası aynı turda Write/Edit/MultiEdit/NotebookEdit çağrıldıysa state eskimiş sayılır. `mcl-post-tool.sh` Write grubu araçlarda `last_write_ts` (unix epoch) state'e yazar. Skip koşulu artık ikili: `tdd_last_green.ts > last_write_ts` VE `age < 120s`. İkisi birlikte sağlanırsa atlama yapar, biri bozulursa tam suite koşar.

## [8.1.5] - 2026-04-28

### Eklendi
- **Regression Guard akıllı atlama:** TDD'nin son `green-verify` sonucu `state.tdd_last_green`'e (`ts` + `result`) yazılır. Regression Guard tetiklenirken bu değeri okur: `green-verify` GREEN ve 120 saniyeden taze ise suite tekrar koşulmaz (`regression-guard-skipped` audit kaydıyla). 120 saniyeden eski veya hiç çalışmamışsa tam suite koşulur.
- **self-critique.md:** Pressure resistance / Human Authority ayrımına tek satır örnek eklendi — "X yapma" → Human Authority (karar kapanır), "X yanlış" kanıtsız → Pressure resistance (pozisyon korunur).

## [8.1.4] - 2026-04-27

### Eklendi
- **İnsan Yetkisi — Karar Kapanışı:** `self-critique.md`'e "Human Authority — Decision Closure" bölümü eklendi. Geliştirici bir kararı açıkça verdikten sonra (ret, seçim, riski kabul, tekrarlanan seçim) MCL o kararı tekrar açmaz; işlevsel eşdeğer önermez, aynı itirazı yeniden çerçevelemez. İstisna: daha önce bilinmeyen yeni kritik bilgi — bir kez, etiketlenerek sunulur.
- `phase1-rules.md`'e çapraz referans eklendi: explicit decision → human authority rule → see self-critique.md.
- Anti-sycophancy ile tamamlayıcı ilişki belgelendi: pressure resistance (kanıtsız baskıya direnç) ≠ human authority (verilen kararın kapanması).

## [8.1.3] - 2026-04-27

### Eklendi
- **Root Cause Prensibi (Boris Cherny):** Phase 4 Scope Discipline'e Rule 3 eklendi: "Fix the cause, not the symptom. If a patch only makes the test pass without addressing why it failed, surface it as a Phase 4.5 risk item."
- **Phase 4.5 Root Cause Lens:** `pattern-compliance` mcl_audit bloğuna Root Cause Lens direktifi eklendi. Band-aid kalıpları listelenir: hataları catch/swallow etmek, type constraint genişletmek, test girdilerini özel-case'lemek, failure mode düzeltilmeden retry. Her biri risk item olarak raporlanır.
- Mekanizma: flag sistemi yok — lens Phase 4.5'te bağımsız tarar.

## [8.1.2] - 2026-04-27

### Eklendi
- **Kapsam Disiplini:** Phase 4'te her turda `SCOPE_DISCIPLINE_NOTICE` enjekte edilir. İki kural:
  - **Rule 1 — SPEC-ONLY:** Spec'in MUST/SHOULD'larında olmayan hiçbir şey yapılmaz. Yasak: spec'te olmayan performans iyileştirmesi, "fırsattan istifade" refactor, style fix, fazladan test, "ileride lazım olur" API eklentisi. Fark edilirse Phase 4.5/4.6 itemi olarak kaydedilir, düzeltilmez.
  - **Rule 2 — FILE SCOPE:** Yalnızca spec'in Technical Approach'unda geçen dosyalar değiştirilir. `scope_paths` doluysa pre-tool hook zaten bloke eder; boşsa bu behavioral notice kapsar.
- Scope Guard block mesajı güncellendi: Rule 1 ve Rule 2 referanslarıyla ihlal bağlamı netleştirildi.

## [8.1.1] - 2026-04-27

### Değişti
- **Phase 3.5 derinleşti:** Özet artık zorunlu 3 başlık formatında — `**Naming Convention:**`, `**Error Handling Pattern:**`, `**Test Pattern:**`. "Enforced" ibaresi ile kurallar Phase 4 boyunca `PATTERN_RULES_NOTICE` olarak her turda context'te tutulur.
- **stop hook:** `PATTERN_SUMMARY` early exit'ten önce parse edilir (`mcl-stop.sh`'de yeni erken clearance bloğu). Phase 3.5 turu spec/AskUQ içermediği için eski geç clearance hiç çalışmıyordu.
- **Phase 4.5 compliance:** `phase_review_state=running`'da `PATTERN_RULES_NOTICE`'e compliance check direktifi eklenir — hangi dosya, hangi kural, ne bulundu vs beklenen.
- `state.pattern_summary` şemaya eklendi; session sınırında sıfırlanır.

## [8.1.0] - 2026-04-27

### Değişti
- `ROLLBACK_NOTICE` artık her Phase 4 turunda değil, yalnızca ilk turda gösteriliyor (`rollback_notice_shown` flag). 5-10 turluk görevlerde aynı SHA tekrar etmez.
- `/mcl-rollback` komutu eklendi: flag'ı sıfırlar, bir sonraki turda notice yeniden görünür; full SHA + reset komutu + atomic commit önerisi gösterir.
- `state.rollback_notice_shown` şemaya eklendi; session sınırında sıfırlanır.

## [8.0.9] - 2026-04-27

### Eklendi
- **Rollback checkpoint:** Spec onayı anında `git rev-parse HEAD` çalıştırılır, SHA `state.rollback_sha`'ya kaydedilir. Phase 4 boyunca her turda `ROLLBACK_NOTICE` context'e enjekte edilir — tam SHA ve `git reset --hard <sha>` komutuyla. Git repo yoksa sessizce geçilir.
- **Atomic commit hint:** Phase 4.5/4.6/5 çalışırken (`phase_review_state=running`) `ATOMIC_COMMIT_NOTICE` enjekte edilir: `git add <scope_paths>` + `git commit -m "feat: <spec objective>"` komutu hazır olarak sunulur. Auto-commit yok — Claude komutu çalıştırır, developer onaylar.
- **state.rollback_sha:** Şemaya eklendi (default null); session sınırında temizlenir.

## [8.0.8] - 2026-04-27

### Eklendi
- **Güvenlik refleksleri — `mcl-secret-scan.py`:** Tüm fazlarda Write/Edit/MultiEdit/NotebookEdit çağrıları credential ve secret taramasından geçer.
  - **Tier 1 (hassas dosya yolu):** `.env`, `*.pem`, `*.key`, `credentials.json`, `service-account.json` vb. gerçek değer içeriyorsa block. `.env.example` ve `*.template` muaf.
  - **Tier 2 (bilinen secret pattern):** `sk-...` (OpenAI/Anthropic), `ghp_...` (GitHub), `AKIA...` (AWS), `AIza...` (Google), `xoxb-...` (Slack), PEM header, JWT vb.
  - **Tier 3 (high-entropy assignment):** `SECRET/PASSWORD/API_KEY = <entropy≥3.5, len≥20>` — `os.environ` referansları ve placeholder değerler muaf.
- Tarama faz kapısından önce çalışır — Phase 1-3'te bile credential yazımı bloke edilir.

## [8.0.7] - 2026-04-27

### Eklendi
- **Phase 3.5 — Pattern Matching:** Spec onayı → Phase 4 geçişinde, `scope_paths`'e göre mevcut sibling dosyaları `mcl-pattern-scan.py` ile tespit eder. İlk Phase 4 turunda Write/Edit bloke edilir; `PATTERN_MATCHING_NOTICE` Claude'a hangi dosyaları okuyacağını ve ne çıkaracağını (import stili, naming convention, error handling, test yapısı) söyler. Tur tamamlanınca blok otomatik kalkar.
- **mcl-pattern-scan.py:** scope_paths'ten sibling dosya referansları bulur; dizin başına max 3, toplam max 10 dosya; glob-aware.
- **state alanları:** `pattern_scan_due` (bool), `pattern_files` (list) — session sınırında sıfırlanır.

## [8.0.6] - 2026-04-27

### Eklendi
- **Scope Guard (mcl-pre-tool.sh):** Phase 4'te Write/Edit/MultiEdit/NotebookEdit çağrıları onaylanmış spec'te bildirilen dosya yollarıyla kısıtlanır. `scope_paths` boşsa kısıtlama yoktur (spec açık yol listesi içermiyorsa dormant).
- **mcl-spec-paths.py:** Spec metninden dosya yolu token'larını çıkarır. Backtick, bold ve düz metin yollarını destekler; `src/auth/*.ts`, `tests/**/*.test.ts` gibi glob pattern'leri tanır.
- **scope_paths state alanı:** Spec onayında `mcl-stop.sh` yolları çıkarıp `state.scope_paths`'e yazar; session sınırında `mcl-activate.sh` sıfırlar.

## [8.0.5] - 2026-04-27

### Düzeltme
- `mcl-stop.sh`: `_MCL_HOOK_DIR` sabitlendi — `mcl-test-runner.sh` kaynaklanınca `SCRIPT_DIR`'i `lib/` dizinine çekiyordu, tüm `$SCRIPT_DIR/lib/` referansları bozuluyordu. `_MCL_HOOK_DIR` ile sabitledi; `mcl-phase-review-guard.py`, `mcl-partial-spec.sh`, `mcl-spec-save.sh` vb. doğru konumdan çalışıyor.
- `mcl-state.sh` allowlist: `mcl-post-tool.sh` yetkili yazıcılar listesine eklendi. Eksikliği Regression Guard clearance'ını susturuyordu — "✅ Tests: GREEN" sonrası `regression_block_active` temizlenemiyor, blok kalıcı hale geliyordu.

## [8.0.4] - 2026-04-26

### Eklendi
- **Regression Guard:** Phase 4 kodu yazıldıktan sonra, Phase 4.5 başlamadan önce tam test suite çalıştırılır. Suite kırmızıysa (`regression_block_active=true`) Phase 4.5 bloke edilir; `mcl-activate.sh` `REGRESSION_BLOCK_NOTICE` enjekte eder. Geliştirici hatayı düzeltip "✅ Tests: GREEN" çıktısı aldığında `mcl-post-tool.sh` bloğu otomatik temizler.

### Düzeltme
- `mcl-pre-tool.sh` state.json koruma regex'i: eski geniş regex (komut içinde `state.json` VE herhangi bir `>>` yeterliydi) false-positive'lere yol açıyordu. Yeni regex `>>?` yakalamalarının doğrudan hedefini kontrol eder; Python betikleri veya yorum satırları artık tetiklemez.

## [8.0.3] - 2026-04-27

## [8.0.2] - 2026-04-27

### Düzeltme
- `Skill`, `TodoWrite` ve `Task` blokları `mcl-pre-tool.sh`'deki fast-path'ten önce taşındı. Önceki konumlarında fast-path onları `exit 0` ile geçiriyordu; bloklar hiç çalışmıyordu.
- Her bloğun sonuna non-matching case için `exit 0` eklendi — `feature-dev:code-explorer` gibi meşru Task çağrıları ve `superpowers:code-reviewer` gibi izinli Skill çağrıları artık doğru şekilde geçiyor.

---

## [8.0.1] - 2026-04-27

### Eklendi
- **TodoWrite blok (Phase 1-3):** `mcl-pre-tool.sh` Phase 1-3'te `TodoWrite` çağrılarını `decision:block` ile engelliyor. Phase 4+ serbest.
- **Task dispatch blok (Phase 4.5/4.6/5):** Phase 4.5 (Risk Review), Phase 4.6 (Impact Review), Phase 5 (Verification Report) sub-agent'a devredilmeye çalışılırsa bloke ediliyor. Bu fazlar yalnızca ana MCL oturumunda çalışabilir.

### Değişti
- `superpowers-scope` behavioral kısıtı STATIC_CONTEXT'ten kaldırıldı — hook referans notuna indirgendi.

---

## [8.0.0] - 2026-04-27

### Düzeltme
- `superpowers:brainstorming` artık `mcl-pre-tool.sh` hook'unda `decision:block` ile engelleniyor. 7.9.9'daki behavioral kural (`superpowers:using-superpowers`'ın "ABSOLUTELY MUST" talimatı tarafından override ediliyordu) yetersiz kaldığından hook-level blok eklendi.

---

## [7.9.9] - 2026-04-27

### Düzeltme
- STATIC_CONTEXT'e `superpowers-scope` kısıtı eklendi: `superpowers:brainstorming` yasak, MCL faz takibi için `TodoWrite` yasak, visual companion teklifi yasak. (Sonradan 8.0.0'da hook-level blok ile güçlendirildi.)

---

## [7.9.8] - 2026-04-27

### Düzeltme
- **Çoklu spec sorunu:** Kullanıcı AskUserQuestion butonuna basmak yerine chat input'a "onaylıyorum" yazdığında stop hook onayı algılayamıyor ve phase=2'de kalıyordu. `mcl-stop.sh`'e plain-text approval fallback eklendi.
- **"Devam etmek için bir mesaj gönderin" yasağı:** `spec-approval-discipline` kısıtıyla bu cümle ve tüm dil eşdeğerleri yasaklandı.
- Session başına 1 spec kuralı, hook dosyası debug yasağı, self-narration yasağı eklendi.

---

## [7.9.7] - 2026-04-26

### Eklendi
- **Kod tasarım ilkeleri** STATIC_CONTEXT'e eklendi: Composition over inheritance, SOLID, extension over modification, design pattern sadece gerçek problem için. `~/.claude/CLAUDE.md`'ye de global kural olarak yazıldı.

---

## [7.9.6] - 2026-04-26

### Düzeltme
- `vite.config.*`, `next.config.*`, `nuxt.config.*` Phase 4a'da engellenen backend path listesinden çıkarıldı. Bu dosyalar olmadan `npm run dev` çalışmıyor, kullanıcı UI'ı göremeden onay isteniyordu.
- `phase4a-ui-build.md` prosedürüne "build config dosyalarını önce yaz" adımı eklendi.

---

## [7.9.5] - 2026-04-26

### Eklendi
- **Plugin Dispatch Audit:** Phase 4.5 çalışırken `mcl-activate.sh` her turda `trace.log`'u kontrol ediyor. `code-review` sub-agent ve `semgrep` çalışmadıysa `PLUGIN_MISS_NOTICE` enjekte ediliyor ve Phase 4.6/5'e geçiş engelleniyor.
- `hooks/lib/mcl-dispatch-audit.sh` yeni dosya — manifest + audit fonksiyonu.
- `mcl-semgrep.sh`'e başarılı scan sonrası `semgrep_ran` trace eventi eklendi.

---

## [7.9.4] - 2026-04-26

### Değişti
- `(mcl-oz)` inline tag yeniden adlandırıldı: `/mcl-self-q`. Kullanımda fark yok — mesaj içinde yazılınca o yanıt için self-critique görünür hale gelir.
