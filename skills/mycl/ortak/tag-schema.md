---
name: mycl-tag-schema
description: MyCL'in modele enjekte ettiği XML tag'lerinin vocabulary'si. activate.py her UserPromptSubmit'te bu tag'leri additionalContext'e koyar; pre_tool/post_tool/stop hook'ları audit log'a tag-bağımlı kayıtlar yazar. Tag isimleri sabit — yeni tag eklemek değil var olanları kullanmak esas.
---

# XML Tag Vocabulary

MyCL hook'ları model bağlamına yapılandırılmış sinyaller koyar. Tüm
tag'ler `<mycl_*>` prefix'iyle başlar. Tag adları büyük/küçük harf
duyarlı; sabit tutulur — yeni tag eklemek değil mevcutları
kullanmak esastır.

## Aktif faz mesajları (DSI — activate.py)

### `<mycl_active_phase_directive>`

Her tur başı; aktif fazın görevi + emit edilmesi gereken audit +
"şu an ne yapmalısın" özeti. İçeriği `phase_meta.json`'dan TR + EN
ikilisi olarak gelir.

### `<mycl_phase_status>`

ASCII pipeline + faz tamamlanma özeti. Glyph'ler:

```
[1✅]→[2✅]→[3✅]→[4⏳]→[5 ]→[6 ]→...→[22 ]
```

- `✅` complete (audit yazılmış)
- `⏳` aktif faz
- ` ` (boş) bekliyor
- `↷` skipped (örn. greenfield → Aşama 5)

### `<mycl_phase_allowlist_escalate>`

5 strike spec-approval-block veya Layer B block sonrası — sadece audit
log'da `*-escalation-needed` varsa emit edilir. Geliştirici müdahalesi
isteği. Hook bu sinyalden sonra otomatik açma yapmaz; kullanıcı kararı.

### `<mycl_token_visibility>`

Her tur sonu (turn tokens > 0): "Bu tur ~12K token, oturum toplamı
~80K token." Para tutarı YOK (Disiplin #7).

## Plugin orkestrasyonu (activate.py)

### `<mycl_git_init_consent_request>`

İlk-açılış git init onay askq prompt'u. Plugin Kural A bootstrap
istisnası bu mesajla başlar; onay `.mycl/config.json`'a kalıcı yazılır,
asla tekrar sorulmaz.

## Hook iç audit isimleri (audit.log içinde)

XML tag değil — audit.log'da satır olarak görünür, ama tag adlarıyla
karışmaması için referans:

```
asama-N-complete            # Faz N tamamlandı
asama-N-skipped             # Faz N atlandı (skip_reason gerekli)
phase-advance               # current_phase ilerlemesi
spec-hash-stored            # Aşama 4 spec hash kaydedildi
spec-approval-block         # pre_tool spec onayı engeli
phase-allowlist-tool        # Layer B tool engeli
phase-allowlist-path        # Layer B yol engeli
state-mutation-attempt      # Bash kanalından state.set deneme
phase-transition-illegal-emit-attempt  # Bash kanalından phase_transition deneme
*-escalation-needed         # 5 strike eşik aşımı
regression-clear            # test runner GREEN → block clear
session_start               # ilk tur (trace.log'a)
```

## Sözleşmeler

- **Tag içeriği boş ise tag emit edilmez** — gürültü engelleme.
- **Bilingual:** Her DSI tag içeriği `TR\n\nEN` formatında. Etiket yok.
- **XML escape:** İçerik `<`, `>`, `&` içerse escape edilmez —
  Claude Code additionalContext düz metin gibi işler.
- **Tag oversight:** Hook'lar yeni tag uyduramaz. Tag listesi bu
  dosyada — değişiklik PR + skill update gerektirir.

---

# XML Tag Vocabulary

MyCL hooks inject structured signals into the model's context. All
tags start with `<mycl_*>`. Names are case-sensitive and stable —
the rule is to *use* existing tags, not invent new ones.

## Active phase signals (DSI — activate.py)

- `<mycl_active_phase_directive>` — current phase task + required
  audit name + "what to do now", from `phase_meta.json` (TR + EN).
- `<mycl_phase_status>` — ASCII pipeline (`[N✅]→[N+1⏳]→…`) with
  glyphs: ✅ complete, ⏳ active, (blank) pending, ↷ skipped.
- `<mycl_phase_allowlist_escalate>` — emitted only when audit log
  contains a `*-escalation-needed` event (5-strike threshold);
  developer intervention requested.
- `<mycl_token_visibility>` — per-turn + session token count, no
  currency (Discipline #7).

## Plugin orchestration

- `<mycl_git_init_consent_request>` — first-run plugin Rule A
  bootstrap consent askq prompt.

## Audit log identifiers

Not XML tags — they appear as lines in `audit.log` but are listed
here for cross-reference: `asama-N-complete`, `asama-N-skipped`,
`phase-advance`, `spec-hash-stored`, `spec-approval-block`,
`phase-allowlist-tool`, `phase-allowlist-path`,
`state-mutation-attempt`, `phase-transition-illegal-emit-attempt`,
`*-escalation-needed`, `regression-clear`, `session_start`.

## Contracts

- Empty content → tag is not emitted (noise prevention).
- Bilingual: each DSI tag content is `TR\n\nEN` with blank-line
  separator and no labels.
- No XML escaping for content.
- The tag vocabulary is fixed; new tags require a PR + skill update.
