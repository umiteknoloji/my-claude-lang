# Changelog

All notable changes to MyCL.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
