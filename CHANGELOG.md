# Changelog

All notable changes to MyCL.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.31] — 2026-05-13

### Düzeltilen / Fixed

- **Aşama 21 (Yerelleştirilmiş Rapor) belge tutarsızlıkları** —
  Subagent (Sonnet 4.6, 10 lens) **kod değişikliği gerekmediğini**
  doğruladı: phase-21-spesifik hook kodu yok, mevcut generic kanallar
  (complete trigger + 1.0.21 extended trigger) zaten audit'leri
  yakalıyor. Ancak iki belge tutarsızlığı + bir detection control
  eksikliği tespit etti:

  1. `gate_spec.json` Aşama 21 `allowed_tools: ["Write"]`, ama skill
     dosyası `Write, Edit, MultiEdit, Bash, AskUserQuestion`
     listeliyordu — sıkı çevirmen rolü için tek `Write` yeterli;
     runtime'da skill geniş tool listesi yanıltıcıydı (gate gerçekten
     `Edit/Bash` çağrılarını reddederdi).
  2. `MyCL_Pseudocode.md` Aşama 21 çıktısı sadece `asama-21-complete`
     yazıyor, `asama-21-skipped reason=already-english` eksikti.
  3. Aşama 21 dil tespiti tamamen modelin sorumluluğunda; **silent
     skip riski** vardı (model unutursa hiçbir audit yazılmaz).
     Detection control yoktu.

### Değiştirilen / Changed

- **`skills/mycl/asama21-yerel-rapor.md`**:
  - `allowed_tools` listesi `Write` tek satıra daraltıldı (TR + EN);
    gate_spec ile hizalı.
  - "Audit capture kanalı (1.0.31)" bölümü TR + EN; phase-21 spesifik
    hook kodu olmadığı ve generic kanalların yeterli olduğu açıkça
    belgelendi.
- **`MyCL_Pseudocode.md`**: Aşama 21 çıktı satırına `asama-21-skipped
  reason=already-english` eklendi.
- **`skills/mycl/asama22-tamlik.md`**: "Aşama 21 skip doğrulama"
  detection control lens maddesi eklendi (TR + EN). Aşama 22 audit
  log'da Aşama 21 için ya `complete` ya `skipped` audit'i bulamazsa
  "silent skip" olarak Açık Konular'a düşer.

### Boundary

- Hook kodu değişikliği YOK (kasıtlı). Aşama 21'in tek "fonksiyonel"
  sorumluluğu çeviri; bu pure model davranışı. Generic complete +
  extended trigger zaten audit'leri yakalıyor.
- Aşama 22 lens maddesi davranışsal değil — Aşama 22 tamlık raporu
  zaten audit log'u iter ediyor; bu lens sadece "Aşama 21'in kontrol
  kategorisi" netleştirmesi.

### Sürüm bilgisi / Version

- `VERSION` 1.0.30 → 1.0.31, `.claude-plugin/plugin.json` 1.0.31.
- `README.md` + `README.tr.md` test sayısı 737 → 742.
- 5 yeni test: `tests/test_phase21_refactor.py` (gate_spec sanity:
  required_audits, allowed_tools minimal, skippable; smoke: complete
  trigger generic yakalama, skipped trigger extended regex yakalama).

## [1.0.30] — 2026-05-13

### Düzeltilen / Fixed

- **Aşama 20 (Doğrulama Raporu + Sahte Veri Temizliği) 4 boşluk** —
  Subagent (Sonnet 4.6, 10 lens) tespit etti:
  1. `asama-20-spec-coverage-rendered` audit'i skill kontratında var
     ama hiçbir yerde üretilmiyordu; `spec_must` modülü `must_ids()`
     ve `uncovered_musts()` API'leriyle hazır olduğu hâlde
     kullanılmıyordu.
  2. `gate_spec.json` `required_audits_any` (OR) — sadece
     `asama-20-mock-cleanup-resolved` tek başına kapıyı geçiyordu;
     spec coverage raporu hiç üretilmeden faz ilerleyebilir
     **gate bypass riski** vardı.
  3. `asama-20-mock-cleanup-resolved` text-trigger yakalanmıyordu
     (Aşama 11/14 ile aynı declared-but-not-implemented deseni).
  4. Skill dosyası `subagent_rubber_duck: true (gate_spec.json)` diye
     yanlış belge — gate_spec'te böyle flag yoktu.

### Eklenen / Added

- **`hooks/stop.py::_maybe_emit_phase_20_spec_coverage`**: `spec_must`
  API ile deterministik sayım. `must_total = len(must_ids())`,
  `must_green = must_total - len(uncovered_musts())`. Side_audit emit
  `asama-20-spec-coverage-rendered must_total=N must_green=M`.
  Idempotent. cp == 20 guard.
- **`hooks/stop.py::_PHASE_20_MOCK_CLEANUP_RE`** + `_detect_phase_20_mock_cleanup`:
  model text-trigger yakalama, idempotent audit emit.

### Değiştirilen / Changed

- **`data/gate_spec.json` Aşama 20**:
  - `required_audits_any` (OR) → `required_audits_all` (AND).
    Üç audit de zorunlu: `complete`, `spec-coverage-rendered`,
    `mock-cleanup-resolved`.
  - `side_audits: ["asama-20-spec-coverage-rendered"]` — hook
    auto-emit semantiği belgeli.
  - `allowed_tools` genişletildi: `Edit`, `MultiEdit`,
    `AskUserQuestion` eklendi (skill ile tutarlı; mock cleanup
    inline düzenleme + geliştirici onayı için).
  - `_note` ile gate bypass kapanışı ve yeni semantik belgelendi.
- **`skills/mycl/asama20-dogrulama.md`**: yanlış
  `subagent_rubber_duck: true` claim'i silindi; "Hook enforcement
  (1.0.30)" bölümü TR + EN eklendi (gate semantiği, hook auto-emit
  sınırı, spec_must API kullanımı).

### Sözleşme korunumu / Boundary

- Hook auto-emit istisnası: `asama-20-spec-coverage-rendered` purely
  aritmetik — model creativity riski sıfır. Diğer fazlarda
  "hook captures, model speaks" sınırı korunuyor.
- `asama-20-complete` ve `asama-20-mock-cleanup-resolved` modelin
  sorumluluğunda (1.0.26+ sözleşmesi).

### Sürüm bilgisi / Version

- `VERSION` 1.0.29 → 1.0.30, `.claude-plugin/plugin.json` 1.0.30.
- `README.md` + `README.tr.md` test sayısı 725 → 737.
- 12 yeni test: `tests/test_phase20_refactor.py` (spec coverage
  must_total/must_green sayımı, boş spec_must_list, tüm kapsanmış,
  idempotency, phase guard, mock-cleanup text-trigger, gate_spec
  required_audits_all + side_audits + allowed_tools doğrulamaları,
  subagent_rubber_duck yokluğu).

## [1.0.29] — 2026-05-13

### Düzeltilen / Fixed

- **Aşama 19 (Etki İncelemesi) `mid_pipeline_reconfirm` bayrağı
  fiilen çalışmıyordu** — Subagent (Sonnet 4.6, 10 lens) tespit etti:
  `gate_spec.json` Aşama 19'da `mid_pipeline_reconfirm: true`,
  skill dosyası "hook etki listesi 10+ olunca askq açar" diyor, ama
  hiçbir hook bu flag'i okumuyordu. Aşama 14 ile aynı declared-but-
  not-implemented deseni.
- **`state.open_impact_count` alanı yoktu** — Aşama 22 tamlık
  denetimi Aşama 19 etki sayısını okuyacak ama veri yazılmıyordu.
  Aşama 10'un `open_severity_count` alanına paralel.

### Eklenen / Added

- **`hooks/lib/state.py::_DEFAULT_STATE`**: `open_impact_count: 0`
  yeni alan. Aşama 19 items-declared count=K'dan yazılır.
- **`hooks/stop.py::_maybe_emit_mid_reconfirm`**: audit log'da
  `asama-19-item-M-resolved` sayısı 10'a ulaşırsa idempotent
  `asama-19-mid-reconfirm-needed` audit emit eder. Yalnızca Aşama 19'da
  (current_phase == 19 guard).
- **`hooks/stop.py::_detect_mid_reconfirm_acked`**: model
  `asama-19-mid-reconfirm-acked` text-trigger yazınca yakalar; audit
  emit (idempotent).
- **`hooks/stop.py::_PHASE_19_MID_RECONFIRM_ACKED_RE`**: word-boundary
  regex.
- **`hooks/stop.py::_PHASE_19_RECONFIRM_THRESHOLD = 10`**: skill
  belgelendirmesine göre sabit (hardcoded; gelecekte int gate_spec
  alanı olarak okunabilir).
- **`hooks/lib/dsi.py::render_mid_reconfirm_notice`**: needed audit
  var ve acked yoksa modele bilingual askq açma yönlendirmesi
  enjekte eder; acked sonrası susar. Soft guidance (deny değil).
- **`render_full_dsi`** çağırıyor — direktif paketin parçası.

### Sözleşme / Contract

- **Sayım kanalı: audit log** (transcript değil). `asama-19-item-M-
  resolved` audit'lerinin sayısı kalıcı; her tur tekrar sayım.
- **Soft guidance**: hook askq açmak için PreToolUse deny eklemez;
  direktif suggest, model context'i bilir.
- **Hook auto-emit yok**: `asama-19-complete`, `escalation-needed`,
  `mid-reconfirm-acked` (text-trigger'a dayalı) sorumluluğu modelde.

### Aspirational flag'ler (kapsam dışı, doc-truth)

- `self_critique_required: true` ve `public_commitment_required: true`
  Aşama 19'da set edilmiş ama hâlâ enforce edilmiyor (Aşama 14
  _note'undaki durumla aynı). skill dosyasında "gelecek tur" olarak
  belgelendi. `hooks/lib/selfcritique.py` modülü mevcut ama hook
  bağlantısı yok; ileri tur ayrı kapsam.

### Sürüm bilgisi / Version

- `VERSION` 1.0.28 → 1.0.29, `.claude-plugin/plugin.json` 1.0.29.
- `README.md` + `README.tr.md` test sayısı 712 → 725.
- 13 yeni test: `tests/test_phase19_refactor.py` (items-declared →
  open_impact_count, mid-reconfirm threshold/idempotency/scope,
  mid-reconfirm-acked text-trigger, DSI direktifi koşulları, full_dsi
  entegrasyonu, Aşama 19 dışı no-op).

## [1.0.28] — 2026-05-13

### Düzeltilen / Fixed

- **Aşama 15-18 Test Boru Hattı text-trigger zinciri bağlandı** —
  Subagent (Sonnet 4.6, 10 lens) Aşama 15-18'in `scan count=K` ve
  `test-M-added` trigger'larının `_PHASE_QUALITY_PHASES = {11,12,13,14}`
  scope dışında kaldığını; ayrıca **`asama-18-scenario-N-passed` ve
  `asama-18-target-missed`** trigger'larının skill dosyalarında
  açıkça belgelenmiş ama hiç implement edilmediğini tespit etti.
  Aşama 11/14 ile aynı "declared but not implemented" deseni.
- **`asama-18-target-missed`** — NFR ölçümü hedefi karşılamadığında
  yakalanır; **reentry mantığı model sorumluluğunda** (hook yalnızca
  audit yazar). Skill kontratı reentry'i Aşama 13'e bırakır.

### Eklenen / Added

- **`hooks/stop.py::_PHASE_TESTING_PHASES = frozenset({15, 16, 17, 18})`**
  + 3 yeni regex:
  - `_PHASE_TEST_ADDED_RE`: `asama-N-test-M-added` (Aşama 15-17)
  - `_PHASE_SCENARIO_PASSED_RE`: `asama-N-scenario-M-passed` (Aşama 18)
  - `_PHASE_TARGET_MISSED_RE`: `asama-N-target-missed` (Aşama 18)
  - `_PHASE_SCAN_TRIGGER_RE` paylaşılır (Quality Pipeline ile),
    scope filter yeni helper içinde.
- **`hooks/stop.py::_detect_phase_testing_triggers`** — idempotent
  audit emit; hiçbir auto-emit yok (`complete`, `not-applicable`,
  `end-green`, `end-target-met`, `target-missed` tetikleyicisi model
  narrative'ı kalır).
- **`skills/mycl/asama15-birim-test.md` "Hook enforcement (1.0.28)"**
  bölümü TR + EN. Aşama 16, 17, 18 skill'lerinde Aşama 15'e referans.
- **Aşama 18 skill ek not**: `scenario-M-passed` ile `test-M-added`
  farkı, hook'un `target-missed`'i kaydedip reentry'i tetiklemediği
  açıkça belgelendi.

### Boundary korunumu / Boundary

- Aşama 18 `test-M-added` kullanmaz; helper Aşama 18 için bu trigger'ı
  YAKALAMAZ (regex jenerik, scope filtre {15,16,17} ile sınırlı).
- end-* trigger'lar 1.0.21 extended trigger'da yakalanmaya devam eder;
  yeni helper onlara dokunmaz.
- Hook auto-emit yok (1.0.26+1.0.27 sözleşmesi).

### Sürüm bilgisi / Version

- `VERSION` 1.0.27 → 1.0.28, `.claude-plugin/plugin.json` 1.0.28.
- `README.md` + `README.tr.md` test sayısı 699 → 712.
- 13 yeni test: `tests/test_phase15_refactor.py` (Aşama 15 scan/test,
  Aşama 16/17 generic, Aşama 18 scenario/target-missed, Aşama 18'in
  test-M-added kullanmadığı, Aşama 11/14'ün scope dışı kaldığı,
  idempotency, full zincir).

## [1.0.27] — 2026-05-13

### Düzeltilen / Fixed

- **Aşama 14 (Güvenlik) declared-but-not-implemented bayrağı** —
  Subagent (Sonnet 4.6, 10 lens) Aşama 14'ün `subagent_orchestration:
  true` bayrağıyla `mycl-phase-runner`'a yönlendirildiğini, ama bu
  subagent'ın allowed_tools listesinde `Read/Glob/Grep/AskUserQuestion`
  dışında bir şey olmadığını (özellikle `Bash` yok) tespit etti. Sonuç:
  semgrep / npm audit / pip-audit / gitleaks / truffleHog'un hiçbiri
  subagent altında çalıştırılamıyordu; bayrak 1.0.16'da eklenmişti ve
  o günden beri Aşama 14 fiilen "model zorunlu olarak boş subagent
  döngüsüne giriyor, ya `error:` ya `complete:` döndürüyor" durumundaydı.

### Değiştirilen / Changed

- **`data/gate_spec.json` Aşama 14**:
  - `subagent_orchestration: true` KALDIRILDI.
  - `allowed_tools`'tan `"Task"` çıkarıldı (Edit/MultiEdit/Write/Bash
    kaldı — semgrep ana context'te `Bash` ile koşulur).
  - `_note` güncellendi: 1.0.16 kararının gerekçe revizyonu ve
    `self_critique_required: true` ile Plugin Kural B'nin şu an
    enforce edilmediği açık şekilde belgelendi.
- **`hooks/stop.py::_PHASE_QUALITY_PHASES`**: `{11, 12, 13}` →
  `{11, 12, 13, 14}`. Aşama 11-13'le aynı generic text-trigger zinciri
  Aşama 14 için de çalışır. Hook auto-emit yine YOK
  (`asama-14-complete` ve `escalation-needed` modelin sorumluluğunda).
- **`skills/mycl/asama14-guvenlik.md`**: "Hook enforcement (1.0.27)"
  bölümü TR + EN; "Araç kurulu değilse `asama-14-not-applicable
  reason=tool-not-installed`" davranışı eklendi; Plugin Kural B'nin
  şu an aspirational olduğu doc-truth ile yansıtıldı (eski "sessizce
  çalıştırılır" ifadesi tarihsel olarak yanıltıcıydı).
- **`tests/test_phase11_refactor.py`**: `test_phase_14_outside_scope_no_audit`
  testi → `test_phase_14_inside_quality_scope` (assertion tersine).
- **`tests/test_orchestrator.py`**: `test_orchestration_enabled_phase_14`
  testi → `test_orchestration_disabled_phase_14` (assertion tersine).

### Sürüm bilgisi / Version

- `VERSION` 1.0.26 → 1.0.27, `.claude-plugin/plugin.json` 1.0.27.
- `README.md` + `README.tr.md` başlık sürümü güncellendi.
- Toplam test sayısı: 699 (yeni test eklenmedi; iki mevcut test
  davranışsal olarak tersine çevrildi).

## [1.0.26] — 2026-05-13

### Düzeltilen / Fixed

- **Aşama 11-13 Kalite Boru Hattı text-trigger zinciri bağlandı** —
  Subagent (Sonnet 4.6, 10 lens) Aşama 11'in Aşama 9'la birebir aynı
  "declared but not implemented" deseninde olduğunu doğruladı: skill
  ve audit kontratı tam tasarlı (`scan / issue-fixed / rescan /
  escalation-needed`) ama hook'larda hiç text-trigger yakalanmıyordu.
  Pseudocode satır 354-386'da Aşama 11-14 ortak 3-step döngü
  tanımlı; subagent generic regex yaklaşımını onayladı.

### Eklenen / Added

- **`hooks/stop.py` 4 yeni text-trigger regex'i** — generic, Aşama 11,
  12, 13 ortak (Aşama 14 `subagent_orchestration` kanalıyla geldiği
  için scope dışı, double-emit önlemek):
  - `_PHASE_SCAN_TRIGGER_RE`: `asama-N-scan count=K`
  - `_PHASE_ISSUE_FIXED_TRIGGER_RE`: `asama-N-issue-M-fixed`
  - `_PHASE_RESCAN_TRIGGER_RE`: `asama-N-rescan count=K`
  - `_PHASE_ESCALATION_TRIGGER_RE`: `asama-N-escalation-needed`
- **`hooks/stop.py::_detect_phase_quality_triggers`** — dört trigger
  için idempotent audit emit. Scope: phase ∈ {11, 12, 13}; diğer
  fazlar filtrelenir.
- **`skills/mycl/asama11-kod-inceleme.md` "Hook enforcement (1.0.26)"
  bölümü** — TR + EN. Aşama 12 ve 13 skill dosyalarında kısa referans
  (Aşama 11'e işaret).

### Sorumluluk sınırı / Boundary

- **Hook auto-emit YOK** — subagent kritiği gereği `asama-N-complete`
  ve `asama-N-escalation-needed` audit'leri model sorumluluğunda kalır.
  Savunmacı "5 rescan aşılırsa hook escalation auto-yazar" davranışı
  bilerek eklenmedi (STRICT mode bypass-as-reward riski; v13.1.3
  felsefesi).
- **Yeni state alanı YOK** — `quality_phase_N_green` veya
  `quality_rescan_count_phase_N` bool/int alanları eklenmedi
  (duplikasyon kaçınma; Aşama 22 tamlık denetimi audit log'u
  iterate eder).
- **gate_spec.json değişikliği YOK** — Aşama 11/12/13
  `required_audits_any` zaten temizdi (`{n}` template literal yok).

### Sürüm bilgisi / Version

- `VERSION` 1.0.25 → 1.0.26, `.claude-plugin/plugin.json` 1.0.26.
- `README.md` + `README.tr.md` test sayısı 686 → 699.
- 13 yeni test: `tests/test_phase11_refactor.py` (scan/issue/rescan/
  escalation audit emission, Aşama 12 ve 13 generic regex davranışı,
  Aşama 14 scope dışı doğrulaması, idempotency, full zincir, state
  mutation yok kontrolü, gate_spec template temizliği).

## [1.0.25] — 2026-05-13

### Düzeltilen / Fixed

- **Aşama 10 (Risk İncelemesi) + Aşama 19 (Etki İncelemesi) item
  trigger zincirini bağladı — 4 boşluk** — Subagent (Sonnet 4.6, 10
  lens): pseudocode + skill + Aşama 22 tamlık denetimi item-resolved
  audit'lerini bekliyor, ama hook hiç yakalamıyordu:

  1. **`asama-10-items-declared count=K` parse yok** —
     `state.open_severity_count` hiç yazılmıyor; Aşama 22 risk
     kapsanma raporu boş veri okuyor.
  2. **`asama-10-item-M-resolved decision=apply|skip|rule` trigger yok**
     — askq classifier her madde için audit yazıyordu ama model
     text-trigger ile özet bildirimi yapsa hook görmüyordu.
  3. **Rule Capture (`decision=rule`) implement edilmemiş** —
     CLAUDE.md captured-rules için kalıcı kanıt audit'i (`asama-10-rule-capture-M`)
     yazılmıyor.
  4. **`gate_spec.json` Aşama 10 + 19 `required_audits_any` `{n}`
     template literali** — `gate.py` placeholder çözmüyor; sadece
     `asama-10-complete` tek başına kapıyı geçiriyor → gate bypass
     riski (item denetimi fiilen yok).

### Eklenen / Added

- **`hooks/stop.py::_PHASE_ITEMS_DECLARED_RE` + `_PHASE_ITEM_RESOLVED_RE`**
  — generic regex (Aşama 10 ve 19 ortak): word-boundary, line anchor
  yok, diğer trigger regex'leriyle tutarlı.
- **`hooks/stop.py::_detect_phase_items_triggers`** — items-declared
  count=K → audit yazılır + Aşama 10 için `state.open_severity_count = K`.
  item-M-resolved decision=apply|skip|rule → audit emit; **decision=rule**
  ek olarak `asama-10-rule-capture-M` audit yazar. Idempotent.

### Değiştirilen / Changed

- **`data/gate_spec.json` Aşama 10**: `required_audits_any` artık
  yalnızca `["asama-10-complete"]`. Eski `asama-10-item-{n}-resolved`
  template literal kaldırıldı — item denetimi text-trigger zinciri
  ile yapılır, gate listesinde değil.
- **`data/gate_spec.json` Aşama 19**: aynı temizlik — yalnızca
  `["asama-19-complete"]`.
- **`skills/mycl/asama10-risk.md`**: "Hook enforcement (1.0.25)"
  bölümü TR + EN — text-trigger sözleşmesi + idempotency + Aşama 19
  ile ortak regex notu.

### Sürüm bilgisi / Version

- `VERSION` 1.0.24 → 1.0.25, `.claude-plugin/plugin.json` 1.0.25.
- `README.md` + `README.tr.md` başlık sürümü 1.0.7 (drift) → 1.0.25;
  test sayısı 675 → 686.
- 11 yeni test: `tests/test_phase10_refactor.py` (items-declared
  count parse + state.open_severity_count yazımı, decision=apply/skip/rule
  davranışı, rule-capture audit, Aşama 19 generic regex davranışı,
  state yazım kapsamı, idempotency, full zincir, gate_spec template
  temizlik doğrulaması, empty path no-op).

## [1.0.24] — 2026-05-12

### Düzeltilen / Fixed

- **Aşama 9 (TDD Yürütme) 6 implementation gap — en derin "declared
  but not implemented" örneği** — Subagent (Sonnet 4.6, 10 lens):
  pseudocode + tdd.py modülü + state şeması + Aşama 22 bağlantısı
  hepsi tasarımda var, ama 6 farklı yerde bağlantı kopuk:

  1. **tdd.py post_tool.py'den hiç çağrılmıyordu** → `tdd_compliance_score`
     hep `None`. Aşama 22 okuyacak ama sayacak veri yok.
  2. **`asama-9-ac-{i}-(red|green|refactor)` audit trigger yok** —
     mevcut `_PHASE_COMPLETE_TRIGGER_RE` ve 1.0.21 extended trigger
     bu özel format'ı kapsamıyor.
  3. **gate_spec `required_audits_any` template literal** — `{i}`
     placeholders gate.py tarafından çözülmüyor, sadece
     `asama-9-complete` kapıyı geçiriyor; AC audit'leri fiilen
     kontrol edilmiyor.
  4. **`regression_block_active=True` set edilmiyor** — sadece clear
     (GREEN) tarafı vardı. Test runner FAIL hiçbir zaman block aktif
     etmiyor.
  5. **`tdd_last_green` state hiç yazılmıyor** — Aşama 22 + Aşama 10
     TDD yeniden doğrulaması için anlamsız.
  6. **`spec_must_list` → AC sayısı bağlantısı kırık** — Aşama 22
     dinamik sayım yapacak; bu turda implement edilmedi (subagent
     kararı: Aşama 22 turunda birlikte).

### Eklenen / Added

- **`hooks/stop.py::_PHASE_9_AC_TRIGGER_RE` + `_detect_phase_9_ac_trigger`**
  — özel regex `\basama-9-ac-(\d+)-(red|green|refactor)\b` (word
  boundary, line anchor yok — diğer trigger regex'leriyle tutarlı).
  Idempotent audit emit + GREEN stage → `state.tdd_last_green` set.
- **`hooks/post_tool.py::_maybe_record_tdd_write`** — cp==9 + Write/
  Edit success → `tdd.record_write(path)` çağrısı → tdd-test-write
  veya tdd-prod-write audit + `tdd.update_compliance_score()` →
  `state.tdd_compliance_score` 0-100 güncellenir. Sadece Aşama 9
  davranışına özel (diğer fazlarda Write skor saymaz).
- **`hooks/post_tool.py::_maybe_clear_regression_block` genişletme**
  — Bash test runner success'a göre iki yön:
  - GREEN → `regression_block_active=False` + `regression-clear` audit
  - FAIL  → `regression_block_active=True` + `regression-fail` audit
  1.0.23 öncesi sadece clear tarafı vardı.

### Değişen / Changed

- **`data/gate_spec.json` Aşama 9** — `required_audits_any` `{i}`
  template literal'leri kaldırıldı, sadece `asama-9-complete`
  bırakıldı. AC kontrolü Aşama 22 dinamik sayımına devredildi.
  `subagent_rubber_duck` kaldırıldı (Aşama 1-8 tutarlı politika).
- **`skills/mycl/asama09-tdd.md`** — Hook enforcement bölümü eklendi
  (TR + EN: AC trigger, TDD compliance score, regression block).
  Task/Agent yasak notu (Aşama 1-8 pattern).

### Test

- 663 → 675 test (+12: `test_phase9_refactor.py` — AC trigger
  red/green/refactor full cycle, idempotent, empty transcript,
  TDD record cp==9/non-9/test path, regression fail/clear, gate_spec
  no template literals, subagent_rubber_duck removed).

### Pre-emptive yan etki taraması — yan etki yakalandı

`test_subagent_check.py::test_should_trigger_real_gate_spec`
Aşama 9 `subagent_rubber_duck=True` bekliyordu. 1.0.19 hot-fix
pattern'i tekrar (Aşama 4 turunda da olmuştu). Bu sefer aynı turda
yakalandı + düzeltildi → hot-fix gerekmedi.

### Süreç notu

Aşama 1-7'de "declared but not implemented" pattern her aşamada
ortalama 2-3 boşluk. Aşama 9 **6 boşluk** ile en derin örnek.
1.0.21 extended trigger generic fix bunların 2'sini (3 ve gözden
geçirme) önlemedi — Aşama 9 özel AC format'ı (`asama-9-ac-{i}-...`)
generic regex'e girmiyor. Aşama 9 turu en geniş kod ekleme
(~120 satır + 12 test).

[1.0.24]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.24

## [1.0.23] — 2026-05-12

### Değişen / Changed

- **Aşama 8 (Veritabanı Tasarımı) skill Task/Agent yasak notu** —
  Subagent VERDICT: **KORU** (tek küçük ek). Gate_spec sağlam,
  1.0.21 extended trigger `asama-8-end` ve `asama-8-not-applicable`'i
  yakalıyor, test geçiyor, DB scope detect modele bırakılmış
  (Aşama 6 UI detect ile tutarlı kasıtlı pattern).
  Sadece `skills/mycl/asama08-db.md`'ye Aşama 1/3/5/6/7 pattern'iyle
  tutarlı Task/Agent yasak notu eklendi (TR + EN).

### Ertelenmiş (subagent notu)

`asama-8-end tables=N indexes=M migrations=K` parametre parse'ı
**Aşama 22 turunda** yapılacak — tamlık denetimi DB sayımı ihtiyacı
netleşince state.py'ye field eklemek + stop.py parse helper birlikte.
Şimdi erken optimizasyon, ölü state alanı üretir.

### Test

- 663 test (değişmedi — sadece skill text, hiç kod değişikliği yok).

### Süreç gözlemi

Subagent ilk kez "REFAKTÖR" yerine "KORU" verdi. Aşama 1-7'de hep
"declared but not implemented" boşluklar vardı; Aşama 8'de motor +
gate_spec sağlam, sadece tutarlılık notu eksik. 1.0.21 extended
trigger generic fix bu turun kapsamını minimum tuttu — fayda
yansıyor.

[1.0.23]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.23

## [1.0.22] — 2026-05-12

### Düzeltilen / Fixed

- **Aşama 7 (UI İncelemesi — DEFERRED) 4 implementation gap** —
  Subagent (Sonnet 4.6, 10 lens): pseudocode tam, askq + cue'lar
  sağlam, ama stop hook'ta cp==7 için intent işleyici hiç yoktu.
  Aşama 5/6 pattern'i — "declared but not implemented".

  1. **Intent classification stop hook'ta çalışmıyordu** — kullanıcı
     "tamam" deyince `_detect_askq_intent` "approve" döner ama
     `_spec_approve_flow` cp!=4 no-op. `asama-7-complete` hiç emit
     yok → faz sonsuza dek bekler.
  2. **`ui_reviewed` state yazılmıyordu** — schema'da var, set
     edilmiyordu.
  3. **Aşama 6 skipped → Aşama 7 auto-skip yoktu** — 1.0.21
     extended trigger model emit'i yakalar ama otomatik türetme
     eksik.
  4. **`progress.py` deferred narration yok** — pseudocode v13.0.15
     "Aşama 7 daima görünür" kuralı ihlali, ASCII bar'da Aşama 7
     pending glyph (boş " ") gösteriyordu.

### Eklenen / Added

- **`hooks/stop.py::_phase7_ui_review_flow`** — cp==7'de intent
  classify sonucu:
  - `approve` → `state.ui_reviewed=True` + `asama-7-complete` audit
  - `cancel` → `asama-7-cancelled` soft halt audit
  - `revise`/`ambiguous` → no-op (revise 1.0.23'e ertelendi)
- **`hooks/stop.py::_check_phase7_auto_skip`** — cp==7 + `asama-6-skipped`
  + Aşama 7 audit yok → otomatik `asama-7-skipped reason=asama-6-skipped`.
- **`hooks/lib/progress.py::_derive_deferred_phases`** + `_glyph_for_phase`
  `deferred_phases` parametre — gate_spec'te `deferred: true` flag
  olan fazlar (Aşama 7) ASCII bar'da ⏸ glyph ile görünür kalır.
  Skipped/finished/active öncelik; aksi halde deferred.
- **`data/gate_spec.json` Aşama 7 `deferred: true`** flag.
- **`skills/mycl/asama07-ui-inceleme.md`** — Task/Agent yasak notu
  (Aşama 1/3/5/6 pattern).

### Subagent ile farkım — revise ertelendi

Subagent revise akışını kapsam içinde önerdi (cp=6 set, infinite loop
özel kontrol). Ama audit append-only invariant ile çelişki:
- revise → cp=6 set, Aşama 6 audit'ler geçerli → completeness loop
  hemen advance eder cp=7 → **infinite loop**.
- Doğru çözüm: `advance_requires_state` field gate_spec'e ek + Aşama 6
  advance koşulu `ui_reviewed=False` no-op → büyük refactor.
- **Anti-sycophancy**: subagent önerisi direkt kabul edilmedi, scope
  yönetimi. revise akışı 1.0.23 ayrı release'e ertelendi.

### Test

- 650 → 663 test (+13: `test_phase7_refactor.py` — approve/cancel/
  revise no-op/ambiguous, not cp 7, idempotent, auto-skip when 6
  skipped/no when resolved/only cp==7, gate_spec deferred flag,
  progress deferred glyph + active/skipped öncelik).

### Pre-emptive yan etki taraması

- `test_progress.py:83` `test_ascii_pipeline_pending_phases` —
  `[2 ]` ve `[22 ]` kontrol ediyor, Aşama 7 kontrol etmiyor → ✓
  etkilenmez
- `test_progress.py:67` `test_ascii_pipeline_skipped_phases` —
  skipped set'inde 7 → ↷ glyph (skipped öncelikli) ✓
- `test_askq.py` classify mevcut, değişmez
- `test_stop.py` askq intent flow mevcut, yeni path eklemiyor
- `test_dsi.py` Aşama 7 directive mevcut, etkilenmez

### Backward compat

- `ui_reviewed` schema'da, yeni set'in `_validate` impact yok
- `deferred` flag opsiyonel, eski gate_spec'lerde yoksa `_derive_deferred_phases`
  boş set döner — eski davranış (Aşama 7 pending glyph) korunur
- `asama-7-cancelled` yeni audit name — diğer aşamalar etkilenmez

[1.0.22]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.22

## [1.0.21] — 2026-05-12

### Düzeltilen / Fixed

- **Generic extended phase trigger — 6 aşamayı etkileyen kayıp text-
  trigger bug'ı (kritik keşif)** — mevcut `_PHASE_COMPLETE_TRIGGER_RE`
  regex sadece "complete" suffix yakalıyordu (`asama-(\d+)-complete`).
  Pseudocode'da tanımlı `asama-5-skipped`, `asama-6-end`, `asama-6-skipped`,
  `asama-8-end`, `asama-8-not-applicable`, `asama-15-end-green`,
  `asama-16-end-green`, `asama-17-end-green`, `asama-18-end-target-met`,
  Aşama 15-18 `not-applicable` audit'leri **hook'a hiç ulaşmıyordu**.
  Model emit etse bile text-trigger kanalı kayıp → audit log'da
  görünmez → `required_audits_any` gate fail riski.

  Düzeltme: yeni `_PHASE_EXTENDED_TRIGGER_RE` regex
  (`(end-target-met|end-green|skipped|not-applicable|end)`) + yeni
  `_detect_phase_extended_trigger` helper. main()'da
  `_detect_phase_complete_trigger`'dan sonra çağrılır. Longest match
  sırası (end-green/end-target-met ÖNCE end). Idempotent + sıralılık
  opsiyonel (extended trigger'lar yan kanal — `phase-skip-attempt`
  yazmaz, sessiz geçer; mevcut `_detect_phase_complete_trigger` sıralılık
  invariant'ı koruyor).

- **Aşama 6 `asama-6-end` parametre parse + browser warn** — pseudocode
  `asama-6-end server_started=true browser_opened=true` KATI mod
  sertifikası. 1.0.20'ya kadar parametre parse yoktu. `_check_phase6_browser`
  helper: `asama-6-end` detail field'ında `browser_opened=false` ise
  `asama-6-no-browser-warn` soft audit emit (görünür sinyal, hard deny
  değil — pseudocode "no hard gates except four" ilkesi).

### Değişen / Changed

- **`state.py` `ui_sub_phase` + `ui_build_hash` field'ları kaldırıldı**
  — declared but not implemented (1.0.0'dan beri ölü). Hiçbir hook
  okumuyor/yazmıyor (grep onayladı). CLAUDE.md "dedicated implementation"
  kuralı + minimum state şeması.
- **`skills/mycl/asama06-ui-yapim.md`** — Task/Agent yasak notu
  (Aşama 1/3/5 pattern'i). Emit format'ı net (3 seçenek + hook
  davranışı). `asama-6-no-browser-warn` mekanizması açıklandı.
- **`data/gate_spec.json` Aşama 6** — `_note` güncellendi (extended
  trigger + browser warn mekanizması).

### Test

- 637 → 650 test (+13: `test_phase6_refactor.py` — extended trigger
  Aşama 6 end/skipped/cert, Aşama 5 skipped now caught, Aşama 15
  end-green longest match, Aşama 18 end-target-met, Aşama 8
  not-applicable, idempotent, n!=cp silent skip, browser helper
  true/false, state default no ui_sub_phase/ui_build_hash).

### Pre-emptive yan etki taraması

- `grep "ui_sub_phase\|ui_build_hash" tests/ hooks/` → sadece state.py
  yorum referansı. Test'lerde kullanım yok → kaldırma güvenli.
- `test_post_tool.py:139-189` ui_flow_active testleri → etkilenmez
- `test_audit.py:151,166` `is_phase_complete("asama-6-end")` → audit
  name "asama-6-end" prefix kontrolü, hook artık emit edecek → True
  dönecek
- `test_stop_phase_trigger.py:122-144` `asama-6-complete` zincir →
  mevcut regex'e dokunmuyor (yeni regex paralel), etkilenmez
- `test_progress.py:103,120` `asama-6-end` log → progress.py emit ediyor
  (audit lifecycle ayrı), etkilenmez

### Generic feature yan etkisi (pozitif)

Extended trigger Aşama 6 dışındaki **5 aşamayı da kapsar**:
- Aşama 5: `asama-5-skipped` (greenfield) artık yakalanır
- Aşama 7: `asama-7-skipped` (Aşama 6 atlandıysa)
- Aşama 8: `asama-8-end`, `asama-8-not-applicable`
- Aşama 15-18: `asama-N-end-green`, `asama-N-end-target-met`,
  `asama-N-not-applicable`
- Aşama 21: `asama-21-skipped` (İngilizce session)

Bu aşamaların kendi turlarında detay refactor gerekmeyecek (text-trigger
kanalı zaten açık olacak), sadece audit semantiği kontrol edilecek.

### Backward compat

- `ui_sub_phase`/`ui_build_hash` kaldırma: eski state.json dosyalarında
  field varsa `read()` merged dict default sıfırlar (mevcut pattern).
- Extended trigger regex paralel kanal — mevcut `_PHASE_COMPLETE_TRIGGER_RE`'e
  dokunmuyor. Aşama 1-4 davranışı değişmez.

[1.0.21]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.21

## [1.0.20] — 2026-05-12

### Düzeltilen / Fixed

- **Aşama 5 (Desen Eşleştirme) iki implementation gap'i** — Subagent
  (Sonnet 4.6, 10 lens) iki somut boşluk tespit etti. Skill iki dosyada
  ("hook pattern_summary'i state'e yazar" + "Aşama 9 DSI'da her turda
  hatırlatılır") dictat'ı vardı ama hiçbiri kodda yoktu.

  1. **`state.pattern_summary` yazımı eksikti** — skill diyordu "hook
     yazar" ama mekanizma yoktu. Behavioral öncü, hook enforcement yok.
     CLAUDE.md "dedicated implementation" kuralı ihlali.

  2. **Aşama 9 DSI pattern_rules hatırlatması yoktu** — skill diyordu
     "her tur başı DSI'da pattern_summary görünür" ama dsi.py emit
     etmiyordu. Aşama 5'in varoluş amacı (Aşama 9 TDD tutarlılığı)
     kayboluyor.

### Eklenen / Added

- **`hooks/stop.py::_extract_pattern_summary`** + `_PATTERN_SUMMARY_RE`
  regex — Aşama 5 text-trigger sonrası cevap metninde `pattern-summary:
  <özet>` satırı varsa `state.pattern_summary`'e yazar. Regex
  `^[ \t]*pattern-summary:[ \t]*(.+?)[ \t]*$` (MULTILINE + IGNORECASE);
  `\s*` newline yutma bug'ı `[ \t]*` ile düzeltildi (test bulgusu).
- **`data/gate_spec.json` Aşama 5 `side_audits: ["pattern-summary-stored"]`**
  — Aşama 2 pattern'i. Model `asama-5-complete` emit edince hook
  `pattern-summary-stored` yan audit'i otomatik emit eder.
- **`hooks/lib/dsi.py::render_pattern_rules_notice`** — `phase==9 +
  state.pattern_summary` set ise `<mycl_pattern_rules>` block emit
  eder (TR + EN bilingual). `render_full_dsi` Aşama 9'da bu render'ı
  çağırır.
- **`skills/mycl/asama05-desen.md`** — emit format'ı net (`pattern-summary:
  <camelCase|snake_case>, <error pattern>, <test framework>`) +
  Task/Agent yasak notu (Aşama 1/3 pattern'i).

### Test

- 629 → 637 test (+8: `test_phase5_refactor.py` — pattern_summary
  parse [pass/empty/no-line], phase 5 trigger side_audit + state yaz,
  gate_spec side_audits config, DSI pattern_rules phase 9/empty/non-9).

### Pre-emptive yan etki taraması (1.0.18+ süreç, 1.0.19 hot-fix'ten ders)

- `test_orchestrator.py:25,28` pattern_summary subagent prompt'a — etkilenmez (Aşama 5'te subagent yok)
- `test_dsi.py:31,142` Aşama 5 current_phase — etkilenmez (Aşama 9 yeni emit ayrı test'te)
- `test_state.py` — pattern_summary field zaten var (default None)
- `test_skill_loader.py` — skill içerik değişikliği load test'i etkilemez
- `test_subagent_check.py` — Aşama 5 rubber_duck yok zaten

### Backward compat

- `state.pattern_summary` field zaten mevcut (None default) — yeni field değil
- `side_audits` mevcut generic feature (1.0.17), Aşama 5'e yeni eklendi
- Aşama 5 davranışı greenfield path için aynı (`asama-5-skipped reason=greenfield`)
- Dead state field'lar (`pattern_scan_due`, `pattern_ask_pending`) hâlâ dokunulmadı — risk yok, ileri release'te temizleme

[1.0.20]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.20

## [1.0.19] — 2026-05-12

### Düzeltilen / Fixed

- **Aşama 4 spec format bug zinciri (PreToolUse hook enforcement)** —
  En kritik bug. Model `📋 Spec —` formatı yerine "Teknik Spec — ..."
  veya "Proje: ..." gibi özel başlık kullanıyor; ayrıca spec body'sini
  AskUserQuestion prompt'una gömüyordu (assistant text'inde değil).
  `spec_detect.contains` regex matchlemiyor → `spec_hash=null` →
  `_spec_approve_flow` no-op → `spec_approved=False` → Aşama 5+ Bash
  deny zinciri. 1.0.14'te skill anti-pattern eklendi ama model gözardı
  etti. Subagent (Sonnet 4.6, 10 lens) **PreToolUse deny** önerdi —
  PostToolUse zaten geç olur (askq çalıştı, kullanıcı cevapladı).

  Düzeltme: `hooks/pre_tool.py` `tool_name == "AskUserQuestion" +
  cp == 4` ise son assistant text'te `spec_detect.contains` False
  → **PreToolUse deny** + retry mesajı (`spec_missing_block`
  bilingual TR + EN). Hook deterministik enforcement; model'i doğru
  akışa zorlar. Skill talimatı + hook çift katmanlı koruma.

  `spec_detect` regex'i gevşetme **reddedildi** (CLAUDE.md captured
  rule: line-anchored MULTILINE regex invariant, v13.1.2 öğrenimi).
  Zeka subagent gateway **reddedildi** (parent → sub1 → parent → sub2
  yapısı pahalı + retry akışı model'e bağımlı). Hook PreToolUse 10x
  daha az kod, aynı enforcement etkisi.

### Değişen / Changed

- **gate_spec.json Aşama 4 `subagent_rubber_duck: true` kaldırıldı**
  — Aşama 1/2/3 ile tutarlı subagent dispatch politikası. Spec
  yazımı ana bağlamda Skill + AskUserQuestion + (global) Read ile
  yürütülür; bağlam şişmez.

### Eklenen / Added

- **`state.precision_audit_decisions: []` default field** — Aşama 2'den
  ertelenmişti (1.0.17). 7 boyut karar listesi
  (`{dim, decision, note}`) zemini. Aşama 4 spec yazımında
  `[assumed: X]` / `[unspecified: X]` etiketlerini Aşama 2 kararlarından
  türetmek için. Backward compat ✓ — mevcut state'lerde yok →
  default boş liste döner.

- **`spec_missing_block` bilingual mesaj** (`data/bilingual_messages.json`)
  — PreToolUse deny mesajı. Spec format hatası açıklaması + retry
  rehberi (TR + EN).

### Test

- 624 → 629 test (+5: `test_phase4_refactor.py` — precision_audit_decisions
  default/set/get, gate_spec phase 4 subagent_rubber_duck removed;
  `test_pre_tool.py` — Aşama 4 askq spec_present allow / spec_absent
  deny / cp!=4 spec guard tetiklenmez).

### Pre-emptive yan etki taraması (1.0.18'den itibaren süreç)

- `test_pre_tool.py:285` — mevcut `test_phase_4_allows_askuserquestion`
  spec_present + spec_absent + cp!=4 olarak **3 case'e split edildi**.
- `test_integration_smoke.py:107` — fixture zaten spec assistant text'te
  yazıyor, etkilenmez.
- `test_state.py` — yeni field optional, validate fonksiyonu impact yok.

### Ertelenmiş işler (subagent ile farkım, scope yönetimi)

- Aşama 2 → Aşama 4 spec entegrasyonu: state'te `precision_audit_decisions`
  saklanır, ama model'in Aşama 4 spec'ine `[assumed: X]` etiketleri
  olarak yansıtması **skill dayatması** olarak kalıyor. Tam hook
  enforcement (spec body'de assumed etiketleri kontrol et) ileri
  release'e bırakıldı — minimum scope, mevcut bug'a odaklan.

[1.0.19]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.19

## [1.0.18] — 2026-05-12

### Değişen / Changed

- **Aşama 3 (Mühendislik Özeti) iki incelik fix** — 1.0.14'teki
  silent_phase auto-emit sağlam çalışıyor, ama subagent (Sonnet 4.6,
  10 lens) iki incelik tespit etti:

  1. Skill "İzinli tool'lar: Yok" yetersiz çünkü
     `_global_always_allowed_tools` listesinde `Task` ve `Agent`
     var. Layer B Aşama 3'te Task'ı deny etmiyor. Model subagent
     çağırıp sahte "Bağlam Tarama" işi yapabiliyor (kullanıcı
     raporundaki davranış). **Skill explicit yasaklama eklendi**
     (TR + EN bilingual).

  2. `_silent_phase_auto_emit` idempotent guard `_all`/`_any`
     ayrıştırılmamıştı. Mevcut "for name in required: if name in
     existing: return" `_all` için yanlış (biri varsa dur, hepsi
     değil). Aşama 3'te sorun yok (sadece `_any` var), ama
     gelecek `silent_phase + _all` kombinasyonu (Aşama 22 vb.)
     için sessiz zaman bombası. **Guard ayrıştırıldı**: `_all`
     için "hepsi varsa dur, değilse eksikleri tek seferde yaz",
     `_any` için "biri varsa dur, değilse ilk audit'i yaz".

### Test

- 622 → 624 test (+2: `test_silent_phase_required_all_partial_emits_missing`,
  `test_silent_phase_required_all_full_existing_noop`).

### Pre-emptive yan etki taraması (1.0.18'den itibaren yeni süreç)

İmplementasyon öncesi etkilenen test'ler tarandı:
- `test_stop_silent_phase.py` mevcut 4 case → refactor sonrası geçer
  (mantık aynı sonuç, yol netleşir)
- `test_stop.py:331` Aşama 3 audit'i tohum → etkilenmez
- `test_audit.py:174` `engineering-brief False` beklentisi → korunur

Bu pre-emptive tarama 1.0.16/1.0.17 turlarında atlanmış reactive
fail'lerin önüne geçer — kullanıcı süreç iyileştirme önerisi.

### Backward compat

- Aşama 3 davranışı transparent (`_all` boş, sadece `_any` var) — fix
  Aşama 3'te tetiklenmiyor. Gelecek silent_phase + _all faz'ları için
  zemin hazırlandı.
- Skill ek dayatma model davranışını kırabilir (subagent çağırma
  alışkanlığı) — bu istenen sonuç.

[1.0.18]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.18

## [1.0.17] — 2026-05-12

### Değişen / Changed

- **Aşama 2 (Hassasiyet Denetimi) mimari fix** — `required_audits_any`
  (OR) → `required_audits_all` (AND). Eski mantıkta `asama-2-complete`
  veya `precision-audit` audit'inden **biri yeterliydi** — model
  sadece `asama-2-complete` yazıp 7 boyut taramasını atlayabiliyordu.
  AND zorunluluğu ile bypass kapatıldı. Subagent kararı (Sonnet 4.6,
  10 lens) doğrultusunda.

### Eklenen / Added

- **`required_audits_all` (AND) mantığı** (`hooks/stop.py::_is_phase_complete`)
  — `_all` öncelikli, `_any` fallback. Mevcut fazlar için backward
  compat ✓ (sadece Aşama 2 `_all` kullanır şu an, diğerleri `_any`).
- **`side_audits` generic feature** (`hooks/stop.py::_detect_phase_complete_trigger`)
  — fazın yan audit'leri text-trigger sonrası hook tarafından paralel
  emit edilir. Model yazmaz, hook yazar. Aşama 2'de `precision-audit`
  yan audit; gelecek fazlarda da kullanılabilir (Aşama 9 TDD'nin
  `red/green/refactor` audit'leri için zemin).
- **Aşama 2 multi-GATE skill açıklaması** (`asama02-hassasiyet.md`)
  — birden fazla boyut GATE çıkarsa **tek AskUserQuestion** içinde
  2-4 madde olarak sun (Anthropic native multi-question desteği).
  Ayrı askq turlarına bölme.

### Subagent ile farkım (ertelendi)

Subagent (Sonnet 4.6) `state.precision_audit_decisions` listesi
yazımı önerdi (Aşama 4 spec'e `[assumed: X]` etiketlemek için). Bu
büyük scope — Aşama 4 turunda `spec_must.py` refactor'la birlikte
daha doğal. **1.0.17'de ertelendi**, scope minimum tutuldu (Aşama 1
ile tutarlı).

### Test

- 615 → 622 test (+7: `test_phase2_refactor.py` — `required_audits_all`
  semantics [pass/partial fail], `side_audits` config, side audit emit
  on trigger, idempotent, gate_spec entry checks).

### Backward compat

- Mevcut fazlarda `_all` yok → `_any` fallback çalışır, etkilenmez.
- Mevcut açık oturumlarda Aşama 2 önceden geçilmişse `phase-advance`
  audit'i geçerli kalır (geçmiş ileri-akış korunur). Yeni Aşama 2
  geçişlerinde AND zorunluluğu aktif.

[1.0.17]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.17

## [1.0.16] — 2026-05-12

### Değişen / Changed

- **Aşama 1 (Niyet Toplama) over-engineering temizliği** — `Task`
  subagent dispatch (`mycl-phase-runner`) Aşama 1'den **kaldırıldı**.
  Pseudocode §3 "POC" notu 1.0.1'de "zorunlu" diye yanlış yorumlanmıştı.
  Niyet toplama küçük scope (kısa askq diyaloğu), bağlam şişmez —
  Anthropic doc'una göre subagent "büyük dosya içeriği / arama
  sonuçları" için. Ana bağlamda Skill + AskUserQuestion + (global)
  Read/Glob/Grep yeterli. Sonuç: 1 tur daha az, parsing-fail riski
  yok, daha hızlı.

  - `data/gate_spec.json` Aşama 1: `allowed_tools` `["Task",
    "AskUserQuestion"]` → `["AskUserQuestion"]`. `subagent_orchestration:
    true` field silindi. `_note` güncellendi.
  - `agents/mycl-phase-runner.md` Aşama 1 referansları kaldırıldı,
    "Phase 10/14 parallel review scope" olarak daraltıldı.
  - `skills/mycl/asama01-niyet.md` çelişki tarama kategorileri
    netleştirildi (state modeli / zaman modeli / veri tutarlılığı —
    exhaustive değil, ipucu listesi). Plus "`Task` Aşama 1'de yasak"
    notu eklendi.

### Eklenen / Added

- **Multi-askq audit guard (`pre_tool.py::_count_askq_in_last_assistant_turn`)**
  — Aşama 1 skill "tek soru per turn" dictat (pseudocode §3). Model
  tek mesajda paralel askq açarsa `multi-askq-attempt` audit yazılır.
  **Audit-only, deny YOK** — Claude Code parallel tool calls race
  condition oluşturur. Plan'da "deny + audit" denmişti, implementasyona
  geçince race risk fark edildi; audit-only güvenli. Görünürlük sinyali,
  bir sonraki sürümde sıkılaştırma için zemin.

- **Stuck state soft warning (`activate.py::_check_stuck_state`)** —
  Yeni oturumda `/mycl` ile aktive edilen state `current_phase >= 4 +
  spec_approved == False` ise `<mycl_stuck_state_warning>` blok emit
  edilir. Recovery yolu önerisi: `.mycl + .git` temizle veya manuel
  `audit.log_event('asama-4-complete', 'recovery')`. Hard deny YOK,
  soft guidance.

### Test

- 605 → 613 test (+8: `test_phase1_refactor.py` — allowed_tools, no
  subagent_orchestration, multi-askq count [single/multi/only-last],
  stuck state [phase>=4/phase<4/spec_approved]).

### Backward compat

- Mevcut açık oturum varsa (örn. `~/mycl_bo/.mycl/state.json` cp=5 +
  spec_approved=false) `/mycl` ile aktive olunca stuck warning görür,
  kullanıcı `.mycl + .git` temizleyip baştan başlamalı. Migration
  script yok (overkill); soft guidance ile manuel recovery yeterli.

[1.0.16]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.16

## [1.0.15] — 2026-05-12

### Düzeltilen / Fixed

- **Multi-subagent akışta `asama-N-complete` text-trigger kayıp
  sorunu — 15 aşamayı etkiliyordu** — model tipik akışta bir turda
  hem `asama-N-complete` trigger emit ediyor hem `Task` tool ile
  yeni `mycl-phase-runner` subagent dispatch ediyor. Claude Code'un
  `Stop` event'i fire eden koşul: model artık tool çağırmıyor →
  bu turda fire **etmez** (Task var). Sonuç: trigger kanalı
  kayboldu.

  22 aşamanın detaylı analizi (kullanıcı raporu): askq açan
  aşamalar (1, 2, 4, 7, 10, 19) `post_tool` stop-trigger kanalı
  ile kurtuluyor. Aşama 3 silent (1.0.14 fix). Aşama 6, 9
  mutating + askq karışık. Geriye kalan **15 aşama** (5, 8, 11-18,
  20-22) askq açmıyor, model emit ediyor → multi-subagent akışta
  kayıp. Ana semptom: state cp=2'de stuck + Aşama 4 spec onay
  askq'sının `_spec_approve_flow` cp==4 kontrolüne takılması →
  spec_approved=False → Bash deny.

  Düzeltme: `hooks/subagent_stop.py::main()` `SubagentStop` event'i
  her subagent dönüşünde fire ediyor → bu doğru tetik noktası.
  Stop hook'taki `_detect_phase_complete_trigger` +
  `_run_completeness_loop` mantığı paralel ek path olarak
  çağrılıyor. İdempotent: `existing audits` set check çift emit'i
  engeller (1.0.8'den beri pattern), Stop + SubagentStop iki
  kanaldan aynı audit yazılma riski no-op.

  Private function import (`from hooks.stop import ...`) bilinçli
  seçim — bu mantığı `hooks/lib/`'e taşımak büyük refactor,
  1.0.16+ değerlendirilebilir.

### Test

- 605 test (değişmedi — `_detect_phase_complete_trigger` 6 case +
  `_run_completeness_loop` silent_phase 4 case zaten kapsıyor;
  subagent_stop.py'da sadece import + iki fonksiyon çağrısı
  eklendi, pytest import doğrulamasıyla yeterli kapsam).

### Sonraki release'ler (gözlem)

- 1.0.16: Aşama 22 (Tamlık Denetimi) hook implementation — şu an
  silent_phase yok, ne model ne hook yazıyor (boşluk).
- 1.0.17: Model davranışı — orchestration olmayan aşamalarda
  model'in subagent dispatch'ten kaçınması için skill + DSI
  directive güçlendirme.

[1.0.15]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.15

## [1.0.14] — 2026-05-12

### Düzeltilen / Fixed

- **`silent_phase` implementation gap — Aşama 3 stuck'in kök sebebi**
  — `data/gate_spec.json::phases.3.silent_phase: true` flag tanımlıydı
  ama `grep silent_phase hooks/` tek tanımı (gate_spec.json) buluyordu;
  **hiçbir hook bu flag'i okumuyordu**. `asama03-ozet.md` skill diyor
  ki "hook universal completeness loop ile otomatik geçirir" ama
  implementation yoktu. Sonuç: Aşama 3 `required_audits_any`
  (`asama-3-complete`, `engineering-brief`) hiçbir yerden yazılmıyor
  → completeness loop break → state cp=3'te stuck → Aşama 4 spec
  onayı `_spec_approve_flow`'un `cp == 4` kontrolüne takılıyor →
  `spec_approved=False` → Bash deny zinciri.

  Düzeltme: `hooks/stop.py::_run_completeness_loop` her iterasyonda
  `phase_def.silent_phase` kontrolü yapar; True ise
  `_silent_phase_auto_emit` helper'ı çağrılır — `required_audits_any`
  listesindeki **ilk** audit'i (gate_spec.json'da semantic sıralı —
  Aşama 3 için `asama-3-complete`) hook kendisi emit eder. Idempotent
  guard mevcut audit'leri korur. CLAUDE.md sequential invariant'a
  uyumlu — sentinel atlama yok, `gate.advance()` normal akışla
  çalışır.

- **`asama04-spec.md` anti-pattern: özel başlık tuzağı** — model
  `📋 Spec — <title>:` şablonu yerine `Teknik Spec — Node.js Todo
  Uygulaması` gibi özel başlık yazdığında `spec_detect.contains`
  regex (`^[ \t]*(?:[-*][ \t]+)?(?:#+[ \t]+)?(?:\U0001F4CB[ \t]+)?Spec\b[^\n:]*:`)
  matchlemiyor (başında `Teknik ` prefix kelimesi pattern'de
  izinli değil). Skill anti-pattern bölümüne explicit yasak +
  regex açıklaması eklendi. Detection regex'i tasarım invariant'ı
  (CLAUDE.md captured rule) — gevşetme reddedildi, doğru çözüm
  skill'i sıkı dayatmak.

### Test

- 601 → 605 test (+4: `test_stop_silent_phase.py` — auto-emit,
  idempotent, non-silent-no-emit, empty-required-noop).

### Recovery (mevcut bozuk state için)

Eğer `.mycl/state.json` cp=3'te takılıysa: ya `.mycl/` + `.git/`
temizle ve baştan dene, ya da kurtarma yolu (`audit.log_event`)
ile elle `asama-3-complete` audit yaz; bir sonraki turda hook
universal completeness loop devam eder.

[1.0.14]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.14

## [1.0.13] — 2026-05-12

### Düzeltilen / Fixed

- **Multi-trigger zincirinde local `cp` ilerletilmiyordu** —
  `hooks/stop.py::_detect_phase_complete_trigger`: model tek cevapta
  `asama-5-complete asama-6-complete asama-7-complete` zinciri
  yazdığında **sadece ilki** audit'e yazılıyor, kalan ikisi
  `phase-skip-attempt` olarak işaretleniyordu çünkü `cp` lokal
  güncellenmiyordu (hep state'deki değerle karşılaştırılıyordu).
  Sonuç: completeness loop ilk advance'ten sonra break ediyor, DSI
  bir sonraki turda yanlış fazda kalıyor → model "kanca dondurmuş"
  sanıp self-debug moduna giriyor (kullanıcı raporunda 14m
  thinking, 42k token, `spec_detect.py` okuma).

  Düzeltme: matches dedupe + ascending sort + her başarılı emit
  sonrası `cp = n + 1` lokal advance. Idempotent durumda da `cp`
  ilerletilir ki zincirdeki sonraki trigger'lar düşmesin. Gerçek
  state advance hâlâ completeness loop'ta (`gate.advance()` audit-
  driven walk) — burası sadece sıralı emit garanti eder.

### Test

- 599 → 601 test (+2: `test_multi_trigger_chain_advances_locally`,
  `test_multi_trigger_dedupe_and_out_of_order`).

[1.0.13]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.13

## [1.0.12] — 2026-05-12

### Düzeltilen / Fixed

- **`.mycl/audit.log` redirect block mesajı yön gösterici değildi** —
  model `Bash(git init && mkdir -p .mycl && echo "..." > .mycl/audit.log
  && echo "..." >> .mycl/audit.log)` çağırdığında hook doğru engelliyor
  (H-5 state-mutation lock, 1.0.4'ten beri) ama mesaj sadece "yazılamaz
  — state hook'lar tarafından yönetilir" diyor; model ne yapması
  gerektiğini bilmiyor → bir sonraki turda doğru komutu kestirmek
  zorunda. `hooks/pre_tool.py`'daki **iki redirect block** mesajı
  (Write/Edit/MultiEdit + Bash redirect) iyileştirildi:
  1. `MyCL {version} | ` prefix (diğer block mesajlarıyla tutarlılık).
  2. Audit emit yöntemi açıkça yazıldı: "Cevap metnine `asama-N-complete`
     tetik kelimesini düz yazıyla yaz; stop hook bunu okuyup audit'i
     kendisi yazar."
  3. Bash redirect block'unda alternatif: "Bootstrap'i bu komutsuz
     tekrar dene: `git init && mkdir -p .mycl` yeterli." (compound
     bootstrap 1.0.11'de allow oldu).

  Davranış değişikliği yok — sadece UX/diagnostic netleştirme.
  Model'in `audit.log`'a manuel yazımı engellemesi (hook'ların state
  sahipliği invariantı) korunur.

### Test

- 599 test (değişmedi — sadece deny message string içeriği).

[1.0.12]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.12

## [1.0.11] — 2026-05-12

### Düzeltilen / Fixed

- **Compound bootstrap komutu spec-approval block tarafından deny
  ediliyordu** — model `Bash(git init && mkdir -p .mycl)` çağırdığında
  1.0.10'daki `_is_git_init_only` istisnası `^\s*git\s+init\s*$`
  regex'i ile sadece **tek başına `git init`**'i matchliyor, compound'u
  kaçırıyordu → spec-approval block `MyCL kilidi — spec onayı yok`
  deny veriyordu. Model'in tek turda hem repo init hem `.mycl/` setup
  yapması doğal akış. `_is_git_init_only` → `_is_bootstrap_command`
  rename + içerik genişletildi: compound separator'lar `&&` ve `;`
  desteklenir, her parça allowlist'ten birini matchlemeli (`git init`
  veya `mkdir [-p] .mycl[/sub]`). Pipe (`|`) ve OR (`||`)
  reddedilir — `git init && rm -rf /` allow olmaz.

### Test

- 599 test (değişmedi — helper davranışı genişledi, mevcut testler
  tek-komut bootstrap için hala geçer).

[1.0.11]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.11

## [1.0.10] — 2026-05-12

### Düzeltilen / Fixed

- **`git init` Aşama 1'de Layer B'de deny ediliyordu** — Plugin Kural
  A consent prompt'u UI'da gösterilse de model `Bash(git init <path>)`
  çağırınca `phase_allowlist_block` veriliyordu. `_is_git_init_only`
  istisnası sadece spec-approval block'ta vardı, Layer B
  (`gate.evaluate`) bunu bilmiyordu. `hooks/pre_tool.py`'a Layer
  B'den **önce** çalışan `4.5. git init bootstrap istisnası` bloğu
  eklendi: `tool_name == "Bash"` + `_is_git_init_only(bash_cmd)` →
  `_allow()` (consent state'inden bağımsız; `git init` zararsız —
  remote yok, push yok).
- **`set_git_init_consent` hiçbir hook'tan çağrılmıyordu** — kullanıcı
  consent prompt'unu onaylasa da `plugin.git_init_consent` hep `None`
  kalıyordu → `activate.py::should_ask_git_init_consent` her
  UserPromptSubmit'te yine `True` döndürüp prompt'u tekrar emit
  ediyordu (sonsuz sorma döngüsü). `hooks/post_tool.py`'a
  `_maybe_set_git_init_consent` helper eklendi: Bash + `git init`
  prefix'li komut başarıyla (`exit_code == 0`) tamamlanırsa
  `plugin.set_git_init_consent("approved")` çağrılır + audit
  (`git-init-consent-recorded`) yazılır. Sonraki turlarda prompt
  bir daha gösterilmez.

### Test

- 599 test (değişmedi — değişiklikler hook-level davranış; mevcut
  testler Layer B path-deny ve regression-clear akışlarını koruyor).

[1.0.10]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.10

## [1.0.9] — 2026-05-12

### Düzeltilen / Fixed

- **`ToolSearch` faz-allowlist'te eksikti** — Sonnet 4.6 ve diğer
  modeller `Task` (subagent dispatch) öncesi `ToolSearch` ile deferred
  tool schema yükleyebiliyor. Bu read-only meta-tool her fazda izinli
  olmalı; `data/gate_spec.json::_global_always_allowed_tools` listesine
  eklendi (`Agent`, `Skill`, `TodoWrite` ile aynı kategori — read-only
  global allow). 1.0.2'deki `Agent` global allow fix'i ile aynı
  desen.
- **Block mesajlarında MyCL sürümü görünmüyordu** — kullanıcı bir
  pre-tool deny aldığında hangi MyCL sürümünün çalıştığını
  anlayamıyordu (sadece askq prompt'larında `MyCL X.Y.Z | Aşama N`
  prefix vardı). 5 block template'ine `MyCL {version} | ` prefix
  eklendi: `phase_allowlist_block`, `phase_path_block`,
  `spec_approval_block`, `spec_approval_escalation`,
  `state_mutation_block`. `hooks/pre_tool.py::_bilingual_block`
  helper'ı `version=_MYCL_VERSION`'ı otomatik enjekte eder
  (`kwargs.setdefault`). `spec_approval_block` ve `state_mutation_block`'taki
  "MyCL kilidi"/"MyCL STATE LOCK" tekrar prefix'leri "Kilit"/"STATE
  LOCK" olarak kısaltıldı (çift `MyCL` kelimesini engellemek için).

### Test

- 599 test (değişmedi — template prefix string content extension; mevcut
  testler "yol yasak", "izin verilmez" gibi contains-check yapıyor,
  prefix etkilemiyor).

[1.0.9]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.9

## [1.0.8] — 2026-05-12

### Eklenenler / Added

- **`SubagentStop` hook** (`hooks/subagent_stop.py`) — Claude Code'un
  AGENTIC LOOP içindeki native `SubagentStop` event'ine bağlı. `Task`
  tool ile `mycl-phase-runner` subagent dispatch'i bittiğinde fire
  eder; transcript'ten son tool_result'ı okur, `orchestrator.parse_phase_output`
  ile parse eder, audit emit + `state.last_phase_output` set yapar.
  Hook listesi 5 → 6 (`settings.json` merge `SubagentStop` event'ini
  ekler).
- **`tests/test_subagent_stop.py`** — 8 case: complete, skipped,
  pending, error, idempotent re-fire, no-orchestration-phase,
  no-transcript-path, no-subagent-output.

### Tasarım kararları / Design

- **Open/Closed: Stop hook'taki subagent kanalı SİLİNMEDİ.** Mevcut
  `stop.py::_detect_subagent_phase_output` çalışıyor; SubagentStop
  paralel **ek path** olarak eklendi. İki kanal aynı audit'i
  yazmaya çalıştığında `existing audits` set check ile idempotent —
  ilk fire eden kazanır, ikincisi no-op. 1.0.9'da Stop kanalını
  silme kararı stabilite kanıtı sonrası ayrı release'de değerlendirilir.
- **`UserPromptExpansion` hook EKLENMEDİ.** `activate.py::extract_trigger`
  regex'i slash command sonrası prompt'taki `/mycl` prefix'ini zaten
  doğru yakalıyor; native event'in kazanımı sadece semantik temizlik,
  fonksiyonel değer marjinal. Invisible-feature anti-paternine
  yakın olduğu için ertelendi.
- **Halüsinasyon kontrolü kapatıldı:** Anthropic'in resmi hooks
  lifecycle diyagramı (`hooks-lifecycle.svg`) `SubagentStart` /
  `SubagentStop` event'lerinin AGENTIC LOOP içinde gerçek olduğunu
  teyit etti. Plan critique #6'nın doğrulama hook'u adımı gereksiz.

### Devtime plan critique

Sonnet 4.6 (extended thinking) + 10 lens ile plan kritik edildi.
3 bulgu kabul:
1. Open/Closed (#8) → Stop kanalı korundu.
2. Halüsinasyon (#6) → SVG ile doğrulandı.
3. Çift-aktivasyon riski (#7) → UserPromptExpansion erteleme ile
   problem yüzeyi sıfırlandı.

### Test

- 591 → 599 test (+8: `test_subagent_stop.py`).

[1.0.8]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.8

## [1.0.7] — 2026-05-12

### Eklenenler / Added

- **Opt-in `/mycl` session trigger (re-introduced)** — MyCL artık her
  promptta otomatik aktif değil. Oturum başına bir kez `/mycl`
  (veya `/mycl <prompt>`) ile etkinleştirilir; tüm hook'lar (banner,
  deny, audit, snapshot) o turdan sonra çalışır. Aktivasyon
  `.mycl/active_session.txt`'e session_id olarak yazılır; yeni
  Claude Code oturumu yeni session_id'ye sahip olduğu için pasif
  başlar. `/mycl` token'ı prompt'tan sıyrılır; sıyrılmış mesaj
  `<mycl_activation_note>` bloğunda model'e iletilir.
- **`commands/mycl.md` slash command dosyası** — 747591d'nin (1.0.5
  feat) **eksik parçası**. Claude Code slash command sistemi
  `~/.claude/commands/<name>.md` dosyası gerektirir; bu dosya
  olmadan `/mycl` "Unknown command" hatası veriyordu (8b16103
  revert nedeni). Template `/mycl $ARGUMENTS` — args slash sonrasına
  düşer, hook extract_trigger ile yakalar.
- **`hooks/lib/activation.py`** — `extract_trigger`, `activate_session`,
  `is_session_active`, `deactivate` API. Trigger regex `^\s*/mycl(?:\b|$)`
  (sadece prompt prefix'i, orta satırdaki `/mycl` sıyrılmaz).
- **`setup.sh` → `~/.claude/commands/` kopyalama bloğu** (`COMMANDS_DIR`
  değişkeni + 5.6. bölüm). Next-steps mesajları `/mycl <intent>`
  kullanımını anlatır (TR + EN).

### Değişen / Changed

- **5 hook erken-return** — `pre_tool.py`, `post_tool.py`, `stop.py`,
  `pre_compact.py`: session aktif değilse no-op. `activate.py`:
  trigger varsa session'ı aktif eder + sıyrılmış prompt'u
  `<mycl_activation_note>` ile iletir, aktif değilse silent.
- **`tests/conftest.py`** — autouse fixture `MYCL_TEST_FORCE_ACTIVE=1`
  env set eder, mevcut tüm hook test'leri eski semantikte kalır
  (test bypass; runtime'da set edilmez).
- **`README.md` + `README.tr.md`** — "Activation (1.0.5+)" /
  "Aktivasyon (1.0.5+)" bölümü, opt-in vurgusu, 587 → 591 test sayısı.
- **`.claude-plugin/plugin.json`** — version 1.0.5 → 1.0.7, description
  "opt-in" vurgusu, keywords `opt-in` + `slash-command` eklendi.

### Test

- 572 → 591 test (+19: `test_activation.py` 14 case [extract matrix,
  roundtrip, oturum-geçici semantik, force-active env bypass] +
  `test_activate.py` +5 case [trigger detect, activation note,
  inactive silent]).

### Why this isn't just 747591d redux

747591d (önceki 1.0.5 feat) "izinsiz + bozuk" gerekçesiyle 8b16103
ile revert edilmişti. "Bozuk" = `commands/mycl.md` slash command
dosyası yoktu → Claude Code "Unknown command: /mycl". 1.0.7 hem
o eksik dosyayı ekliyor hem setup.sh kopyalama bloğunu hem next-steps
talimatını içeriyor. Tasarım aynı; eksik parça tamamlandı.

[1.0.7]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.7

## [1.0.6] — 2026-05-12

### Düzeltilen / Fixed

- **`setup.sh` banner hardcoded sürüm** — kurulum tamamlama banner'ı
  ("✅ MyCL X kurulumu tamamlandı." / "✅ MyCL X installation complete.")
  her release'de `1.0.0` gösteriyordu; VERSION dosyası bump'lansa da
  banner güncellenmiyordu (1.0.4 H-4 ile aynı kategori bug — orada
  `activate.py` banner'ı düzeltilmişti, `setup.sh` banner'ı atlanmıştı).
  Düzeltme: `SCRIPT_DIR` tanımından sonra `MYCL_VERSION="$(tr -d
  '[:space:]' < "$SCRIPT_DIR/VERSION" 2>/dev/null || echo '?')"` yüklenir;
  banner echo'ları `$MYCL_VERSION` kullanır. VERSION dosyası yoksa `?`
  fallback. Help heredoc'taki (line 34) ve script-header yorumdaki
  (line 2) "MyCL 1.0.0" referansları script kimliği bağlamında — kasıtlı
  olarak dokunulmadı.

### Test

- 572 test (değişmedi — bash UX fix, pytest etkilenmez). Banner çıktısı
  `bash setup.sh --dry-run` ile doğrulandı: `✅ MyCL 1.0.5 kurulumu
  tamamlandı.` / `✅ MyCL 1.0.5 installation complete.`

[1.0.6]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.6

## [1.0.5] — 2026-05-12

### Düzeltilen / Fixed

- **Phase-advance trigger turn-shadow** —
  `hooks/stop.py::_detect_phase_complete_trigger`
  `last_assistant_text` kullanıyordu; bu sadece kronolojik son
  assistant text turn'üne bakar. Model phase-runner sonrası turn1'de
  `asama-N-complete` emit edip kullanıcı "devam et" deyince model
  turn2'de prose üretiyor (trigger yok). turn2 gölgeliyor → regex
  eşleşmiyor → audit yazılmıyor → `state.json` hiç oluşmuyor → faz
  hiç ilerlemiyor. Düzeltme: `find_last_assistant_text_matching`
  predicate-based scan trigger içeren en son turn'ü bulur; sonraki
  prose gölgeleyemez. Idempotent guard zaten korur.
  `_detect_and_store_spec` kasıtlı olarak `last_assistant_text`
  kullanmaya devam eder (spec son-turn semantiği).

### Test

- 568 → 572 test (+4: `test_stop_phase_trigger.py` —
  shadowed-by-prose, no-trigger, n>cp skip-attempt, idempotent
  re-emit).

[1.0.5]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.5

## [1.0.4] — 2026-05-12

### Düzeltilen / Fixed

- **H-1: `spec_must_list` extractor 0 öğe döndü** — başlık regex'i
  yalnızca "MUST" arıyordu; "MUST / SHOULD" yakalamıyordu. Liste-öğe
  regex'i `-`, `*`, `+`, `N.` şart koşuyor; girintili `MUST_1` text
  formatı yakalamıyordu. `hooks/lib/spec_detect.py::extract_must_list`'e
  inline fallback eklendi — başlığı olmayan freeform spec metinlerinde
  büyük harf `MUST`/`SHOULD`/`SHALL` satır kalıpları taranır.
- **H-2: düz "onay" metni `spec_approved` set etmedi** — onay tespiti
  yalnızca `AskUserQuestion` yapısal yanıtına bakıyordu; düz chat
  mesajını görmüyordu. `transcript.last_user_text()` eklendi;
  `stop.py::_detect_askq_intent` AskQ result yoksa düz user mesajını
  classify eder (ambiguous → no-op).
- **H-3: Aşama 1'de `AskUserQuestion` denied** —
  `data/gate_spec.json` Aşama 1 `allowed_tools` listesinde yalnızca
  `["Task"]` vardı; askq yoktu. Pseudocode §3 uyumlu olarak
  `"AskUserQuestion"` eklendi.
- **H-4: banner "MyCL 0.0.0" gösteriyor** — `setup.sh` VERSION
  dosyasını kopyalamıyordu; `activate.py` `_REPO_ROOT/VERSION` arayıp
  bulamayınca `0.0.0` default'una düşüyordu. Setup'a inline VERSION
  copy bloğu eklendi (dry-run / force / exists-skip kontrolleriyle).
- **H-5: spec-approval kilidi elle çözüldü** — blok mesajı oturum içi
  kurtarma yolu göstermiyordu, "state.json'ı elle düzelt" diyordu.
  `hooks/pre_tool.py` Adım 3.5'e `.mycl/state.json` + `.mycl/audit.log`
  özel koruma bloğu eklendi (Write/Edit/MultiEdit + Bash redirect
  `>`/`>>`/`tee`); spec/faz durumundan bağımsız her zaman aktif.
- **H-6: spec format kısıtı belgesiz** — `MUST_1 text` (list-marker'sız)
  formatının extractor tarafından okunmadığı kullanıcıya hiç
  bildirilmemişti. `data/static_context.md`'e "Spec Format Kısıtları /
  Spec Format Constraints" bölümü eklendi (TR + EN).
- **`setup.sh copy_file` ileri-referans** — H-4 fix'i
  `copy_file VERSION → $MYCL_DIR/VERSION` çağrısı eklemişti ama
  `copy_file` fonksiyon olarak 135. satırda tanımlı; bash ileri-referans
  desteklemediği için "command not found" veriyordu. İlgili satır
  inline `if/cp` bloğuyla değiştirildi (mantık eşdeğeri).
- **`stop.py` Pyright None-subscript** — `compute_hash` `Optional[str]`
  döndürürken `new_hash[:12]` None-subscript riski taşıyordu. Erken
  return guard eklendi; `_use, result = ...` → `_, result = ...`.

### Test

- 557 → 568 test (+11: H-1..H-6 regression coverage).

[1.0.4]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.4

## [1.0.3] — 2026-05-12

### Düzeltilen / Fixed

- **`phase-skip-attempt` false-positive (stale-emit)** —
  `hooks/stop.py::_detect_phase_complete_trigger` modelin son
  cevabındaki `asama-N-complete` etiketi için üç durum ayırt eder:
  N == cp → audit emit (idempotent), N > cp → gerçek atlama
  denemesi → `phase-skip-attempt` audit, N < cp → stale-emit
  (faz zaten geçilmiş, model özet/tekrar amaçlı eski etiketi
  yazmış) → SESSİZ no-op. Önceki davranış N != cp tüm farkları
  skip-attempt olarak işaretliyordu → 3 false-positive audit
  (`~/mycl_bo/.mycl/audit.log` örneğinde gözlendi:
  emit_phase=1 cur=2, emit_phase=2 cur=3, emit_phase=4 cur=5).

### Test

- 556 → 557 test (+1: `test_text_trigger_stale_emit_silent`).

[1.0.3]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.3

## [1.0.2] — 2026-05-11

### Düzeltilen / Fixed

- **Aşama 1 + tüm fazlarda `Agent` tool deny** —
  `data/gate_spec.json`'daki `_global_always_allowed_tools` listesine
  `Agent` eklendi. Host Claude Code'da `Task` tool ile birlikte `Agent`
  da subagent dispatch için kullanılıyor (/zeka self-critique sistemi,
  plugin validator, vb.). Subagent state'e dokunmaz → mutation
  invariant korunur. Bu fix öncesi /zeka Aşama 1'de fail-closed deny
  alıyordu.

### Test

- 555 → 556 test (+1: `test_real_repo_gate_spec_agent_globally_allowed`).

[1.0.2]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.2

## [1.0.1] — 2026-05-11

### Eklenenler / Added

- **`PreCompact` hook** (`hooks/pre_compact.py`) — Anthropic resmi
  event'i; context compaction öncesi MyCL state + son 10 audit + spec
  MUST listesi `.mycl/wip_snapshot.json`'a serileştirir; bilingual TR
  + EN reinforcement reminder döndürür. Anthropic Issue #53223
  ("CLAUDE.md instruction compliance is architecturally unenforced")
  referansı; mimari boşluğa karşı deterministik araç.
- **Reinforcement reminder pattern** (`hooks/activate.py`) —
  Anthropic resmi öneri (effective context engineering):
  `_build_context()` her aktivasyonun sonunda
  `<mycl_reinforcement_reminder>` bloğu emit eder. Bilingual TR + EN,
  4 madde (faz sırası, mutating tool kuralı, audit emission,
  fail-closed).
- **B feature: text trigger phase complete** (`hooks/stop.py`) —
  modelin son cevabında `asama-N-complete` regex'i; sıralı eşleşmede
  (N == current_phase) audit emit; atlama denemesinde
  `phase-skip-attempt` audit + reject.
- **Multi-agent orchestration POC** (Aşama 1) —
  `agents/mycl-phase-runner.md` + `hooks/lib/orchestrator.py`;
  senkron sıralı `Task` tool çağrısıyla subagent dispatch + handoff.
- **Anthropic resmi plugin coexistence dokümantasyonu** — README'de
  `security-guidance`, `code-review`, `code-simplifier`,
  `session-report` ile birlikte kullanım rehberi.
- **`hookify` plugin çakışma uyarısı** — README'de açık not.

### Değişen / Changed

- **README.md + README.tr.md** — Anthropic resmi plugin'lerle koexist
  bölümü + ilham/topluluk referansları (OpenSpec, obra/superpowers,
  Playwright agents, komunite/kalfa, Anthropic Issue #53223). Test
  sayısı 521 → 555. Hook sayısı 4 → 5.
- **plugin.json** — keywords, homepage, repository alanları eklendi;
  description güncellendi (22-phase pipeline + drift
  counter-measures).
- **setup.sh** — `PreCompact` hook kaydı eklendi (5 hook →
  settings.json merge).
- **agents/** — yeni dizin; plugin marketplace formatına uygun agent
  definition (`mycl-phase-runner.md`).
- **MYCL_DATA_DIR env var** — `gate.py` + `bilingual.py`'a override
  desteği (test/dev ortamı tutarlılığı için).

### Test

- 521 → 555 test (+34: 25 yeni dosya + 9 mevcut testlerin
  genişlemesi).
- Yeni dosyalar: `test_pre_compact.py` (8 test), `test_orchestrator.py`
  (17 test); mevcut genişlemeler: `test_activate.py` (+2 reinforcement
  + 3 subagent), `test_stop.py` (+4 text trigger).

[1.0.1]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.1

## [1.0.0] — 2026-05-09

### Yeni Başlangıç / Fresh Start

MyCL 1.0.0 sıfırdan yeniden inşa. Eski MCL (my-claude-lang) v13.x'in
~5000 satırlık Bash + Python heredoc karışımından **pure Python 3.8+**
ile çıkış. Pseudocode (22 faz) kanonik tasarım olarak korundu;
kod sıfırdan yazıldı. v13.x mekanizmaları **kavramsal aktarım**
ile geldi (kod değil).

MyCL 1.0.0 is a from-scratch rebuild. Migrating away from the legacy
MCL v13.x's ~5000-line Bash + Python heredoc mix to **pure Python
3.8+**. The pseudocode (22 phases) remained canonical; code was
rewritten. v13.x mechanisms transferred **conceptually** (not as
code).

### Eklenenler / Added

- **22-faz pipeline** (Aşama 1-22) — niyet toplamadan tamlık
  denetimine her adım skill dosyası ile detaylı belgelendi
- **4 hook** (Pure Python):
  - `activate.py` (UserPromptSubmit) — DSI + Plugin Kural A consent
  - `pre_tool.py` (PreToolUse) — 6 katmanlı STRICT karar
    (self-guard → phase-transition emit denylist → state-mutation
    lock → spec-approval block → Layer B → 5-strike escalation)
  - `post_tool.py` (PostToolUse) — reaktif state (last_write_ts,
    ui_flow_active, regression-clear) + askq sonrası stop trigger
  - `stop.py` (Stop) — spec hash + askq intent + Aşama 4 spec-approve
    + universal completeness loop
- **23 lib modülü** `hooks/lib/`:
  - state, audit, trace, transcript, spec_detect, askq, gate, plugin
  - dsi, bilingual, framing, progress, tokens, commitment,
    rationale, selfcritique, confidence, spec_must,
    subagent_check, post_mortem, skill_loader, tdd
- **22 skill dosyası** + 1 ana skill + 3 ortak (tag-schema,
  plugin-rules, reasons)
- **8 veri dosyası** `data/`: gate_spec, phase_meta, approve_cues,
  manifesto, static_context, bilingual_messages, commitment_template,
  spec_must_extractor — TR + EN ikilisi
- **521 birim + integration test** — pseudocode invariantları uçtan
  uca smoke matrix
- **`setup.sh`** — Python check, repo kopyala, settings.json
  idempotent merge, smoke test
- **STRICT mode** (v13.1.3 kazanımı korundu) — fail-open YOK,
  5-strike escalation, state mutation lock
- **TR + EN çift dil** — tüm hook mesajları, skill dosyaları, askq
  prompt'ları (boş satır ayrılı, etiketsiz)

### Değişen / Changed (vs MCL v13.x)

- **Stack**: Bash + Python heredoc → **Pure Python 3.8+ standard
  library** (json, re, hashlib, sys, os; dış bağımlılık yok)
- **Dil desteği**: 14 dil → **TR + EN** (askq cue'ları, narration,
  manifesto)
- **Versiyon**: 13.x patch döngüsü → **1.0.0 yeni başlangıç**
- **Klasör yapısı**: `mcl/` → `mycl/`, `.mcl/` → `.mycl/`, `MCL_*`
  → `MyCL_*`
- **State schema_version**: 3 → 1 (yeni başlangıç, eski state ile
  migration yok)
- **Hook isim formatı**: `mcl-pre-tool.sh` → `pre_tool.py`
  (snake_case Python)
- **Skill dosya isimleri**: `phase4_5-risk-review.md` →
  `asama04-spec.md` (Türkçe + tire ayraç)

### Reddedilen Yaklaşımlar / Rejected Approaches

- ❌ **AI agent / LangGraph** — Claude Code'u yeniden yazmak
  anlamsız; pseudocode 22 faz zaten state machine, framework
  gereksiz
- ❌ **MCP server** — Plugin Kural C `.mcp.json` filter
- ❌ **Drift detection** — v13.x'te yanlış-pozitif gürültüsü
  üretmişti; geliştirici doğal olarak spec'ten sapar
- ❌ **Fail-fast giriş kontrolleri** — kullanıcıyı pipeline'dan
  koparır; soft guidance tercih edildi
- ❌ **3-strike fail-open** — STRICT mode korundu (5-strike
  escalation, fail-open yok)
- ❌ **Para tutarı görünürlüğü** — token sayısı OK (objektif),
  USD tutarı YOK (negatif çağrışım)
- ❌ **Gamification puan toplama** — Goodhart's Law
- ❌ **secrets.py runtime pattern match** — Aşama 14 (Güvenlik)
  zaten semgrep + paket audit ile derin tarama yapıyor; pre-tool
  runtime overlap bakım yükü üretiyordu

### v13.x'ten Kavramsal Aktarım / Conceptual Transfer

Kod olarak silindi ama mekanizma korundu:

- Universal completeness loop (audit-driven phase walk)
- Layer B fail-closed allowlist (gate-spec eksikse mutating DENY)
- Persuasion manifesto framing (v13.0.16)
- Spec-approve audit chain + auto-fill (v13.0.14, v13.0.17)
- Audit-driven active phase resolver
- Devtime/runtime REASON split (v13.0.13)
- TDD compliance score
- DSI render (PHASE_META → mcl_active_phase_directive)
- AskUserQuestion sonrası stop manuel tetikleme (v13.1.1 Bug 2)
- STRICT mode (v13.1.3 — 5 strike escalation, fail-open yok)
- State mutation lock Bash'ten (v13.1.3)
- Compound `git init` regex (v13.1.2)
- Spec emoji opsiyonel regex (v13.1.2)

### Tag noktaları / Tag points

- `mcl-13.1.3-final` — eski sürüm sabit (commit `916c271`)
- `pre-mycl-rebuild` — clean slate snapshot (commit `dd15d9d`)
- `mycl-1.0.0` — bu release

[1.0.0]: https://github.com/YZ-LLM/my-claude-lang/releases/tag/mycl-1.0.0
