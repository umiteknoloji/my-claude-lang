# MyCL — my-claude-lang 1.0.37

Claude Code üstüne anlam-doğrulama katmanı. MyCL 22 fazlı bir
geliştirme boru hattı dayatır, audit zincirleriyle disiplini sıkar
ve fail-open YAPMAZ. **Oturum başına opt-in** — `/mycl` yazılana
kadar sessiz (1.0.5+). Pure Python 3.8+, AI agent framework yok,
MCP server yok.

> English: [README.md](README.md)

## MyCL nedir (ne değildir)

MyCL **şudur**: altı Python kanca (`UserPromptSubmit`, `PreToolUse`,
`PostToolUse`, `Stop`, `SubagentStop`, `PreCompact`) ki **`/mycl` ile
aktive edildikten sonra**:

- Aktif fazı `.mycl/state.json`'da takip eder
- Her fazı `.mycl/audit.log`'da bir audit ile mühürler
- Faz başına izin verilen tool listesini dayatır (`gate_spec.json`)
  — fail-closed
- Spec bloklarını line-anchored regex ile tespit eder, hash'ler ve
  geliştirici onayına bağlı downstream tool kapısı tutar
- Her tur faz-spesifik bağlam enjekte eder
  (`<mycl_active_phase_directive>`, `<mycl_phase_status>`,
  `<mycl_phase_allowlist_escalate>`)
- TR + EN çift dil konuşur (etiket yok, boş satır ayrılı)

**Aktivasyon öncesi** (varsayılan, her yeni oturumda): altı kanca da
no-op — banner, deny, audit, snapshot, hiçbiri çalışmaz. Claude Code
MyCL kurulu değilmiş gibi davranır.

MyCL **şu değildir**:

- AI agent framework (Claude Code'u yeniden yazmıyoruz)
- LangGraph veya state-machine kütüphanesi (22 faz `gate_spec.json`'da
  *veri*)
- MCP server (Plugin Kural C `.mcp.json` içeren her plugin'i eler)

## Hızlı kurulum

```bash
git clone https://github.com/YZ-LLM/my-claude-lang.git
cd my-claude-lang
bash setup.sh
```

Kurulum:
1. Python 3.8+ kontrol eder
2. Repo'yu `~/.claude/mycl/` altına kopyalar
3. `mycl.md` skill'ini `~/.claude/skills/`'e tanıtır
4. Veri dosyalarını `~/.claude/data/`'ya bırakır
5. 6 kancayı `~/.claude/settings.json`'a MERGE eder (idempotent —
   tekrar çalıştırılabilir)
6. Smoke test (py_compile + lib import)

## Aktivasyon (1.0.5+)

MyCL **Claude Code oturumu başına opt-in**'dir. Kurulumdan sonra:

```
> /mycl                  # çıplak aktivasyon — MyCL pipeline'ı açar
> /mycl todo app yap     # aktivasyon + ilk niyet tek promptta
```

Herhangi bir promptta `/mycl` tespit edilince aktif session ID
`.mycl/active_session.txt`'e yazılır ve MyCL o oturum boyunca açık
kalır. Claude Code kapanınca yeni oturum yeni ID alır → tekrar
açıldığında MyCL `/mycl` yazılana kadar sessiz.

`/mycl` token'ı, model kullanıcının asıl mesajını görmeden önce
prompt'tan sıyrılır; model bunun yerine sıyrılmış mesajı bir
`<mycl_activation_note>` bloğunda görür.

**Neden opt-in?** Çoğu oturumun 22-fazlı pipeline'a ihtiyacı yok
(hızlı edit, keşif, küçük script). MyCL yalnızca açıkça istendiğinde
devreye girer.

## 22 faz

| # | Faz | Ne yapar |
|---|---|---|
| 1 | Niyet Toplama | Kullanıcı niyetini netleştir — tek soru/tur, özet + askq onay |
| 2 | Hassasiyet Denetimi | 7 boyutta niyet doğrula (auth, hata modları, kapsam, PII, audit, SLA, idempotency) |
| 3 | Mühendislik Özeti | Niyeti İngilizce mühendislik diline çevir — sessiz faz |
| 4 | Spec + Onay | 📋 Spec bloğu (Objective/MUST/SHOULD/AC/Edge/Technical/OOS) + askq onay |
| 5 | Desen Eşleştirme | Mevcut koddan naming/error/test desen öğren (greenfield → skip) |
| 6 | UI Yapımı | Sahte verili frontend, dev server + tarayıcı auto-open (UI yoksa skip) |
| 7 | UI İncelemesi | Deferred — free-form intent classify (approve/revise/cancel/sen-de-bak) |
| 8 | Veritabanı Tasarımı | 3NF schema, covering index, reversible migration (DB yoksa skip) |
| 9 | TDD Yürütme | Her AC için RED → GREEN → REFACTOR; sonda tam suite YEŞİL |
| 10 | Risk İncelemesi | 4 mercek paralel + sınırsız askq |
| 11 | Kod İncelemesi | Doğruluk/mantık/hata yakalama/ölü kod auto-fix |
| 12 | Sadeleştirme | Erken soyutlama / duplikat / gereksiz pattern kaldır |
| 13 | Performans | N+1 / blokayan I/O / sızıntı / allocation auto-fix |
| 14 | Güvenlik (proje genelinde) | semgrep + npm/pip/cargo audit + secret scanner |
| 15 | Birim Testler | Aşama 9 AC'lerinin ötesinde kod-kapsama testi |
| 16 | Entegrasyon Testleri | Modüller arası gerçek akış (testcontainers, in-memory DB) |
| 17 | E2E Testler | Playwright headless (UI yoksa skip) |
| 18 | Yük Testleri | k6/locust spec NFR'ye karşı (NFR yoksa skip) |
| 19 | Etki İncelemesi | Downstream etki (importer, contract, schema, cache) |
| 20 | Doğrulama + Mock Temizliği | Spec coverage tablosu + otomasyon bariyerleri + process trace |
| 21 | Yerelleştirilmiş Rapor | Aşama 20'yi kullanıcı diline çevir (atlanabilir) |
| 22 | Tamlık Denetimi | HOOK yazar; kapsanmamış MUST'ları yüzeye çıkarır |

Her faz için: `skills/mycl/asama<NN>-*.md`.

## Mimari

```
KULLANICI  ←→  MyCL (anlam doğrulama)  ←→  CLAUDE CODE (model + tools)
                  │
                  ├─ 6 kanca (Claude Code çağırır)
                  ├─ state.json (current_phase, spec_approved, ...)
                  ├─ audit.log (append-only olay kaydı)
                  ├─ 22 faz veri olarak (gate_spec.json)
                  └─ her faz için skill dosyası
```

Kancalar **dolaylı** iletişim kurar — `state.json` + `audit.log`
üzerinden. Birbirini import etmez. Altı kanca da `hooks/lib/*`
modüllerini kullanır (state, audit, gate, askq, spec_detect,
transcript, bilingual, dsi, plugin, …).

## Plugin Kuralları

- **Kural A** — yerel `.git/` zorunlu. İlk aktivasyon **bir kez**
  sorar (uzak repo eklenmez, push yapılmaz, otomatik commit atılmaz).
  Karar `.mycl/config.json`'a kalıcı.
- **Kural B** — curated plugin'ler **sessizce** çalışır, bulgular
  `(dosya, satır, kural-eşdeğeri)` üzerinden dedupe edilir. Plugin
  anlaşmazlığı → Aşama 10 risk maddesi.
- **Kural C** — `.mcp.json` içeren plugin curation anında elenir.
  `Bash` üzerinden çağrılan ikili CLI'lar (semgrep, linter,
  compiler) MCP DEĞİLDİR ve izinlidir.

## Çift dil çıktı

Tüm kanca mesajları, askq prompt'ları, manifesto framing'i, faz-sonu
bildirimleri **iki blok** olarak gelir:

```
[Türkçe blok — kullanıcı için]

[İngilizce blok — modelin çalışma dili]
```

Boş satır ayraç, etiket yok. Dosya yolları, audit isimleri, CLI
komutları, code identifier'ları çevrilmez.

## STRICT mode (fail-open YOK)

Veri yetersiz veya belirsiz olduğunda MyCL **DENY** döner —
default-allow değil. Aynı türden 5 ardışık deny sonrası
`*-escalation-needed` audit yazılır; block kalır, geliştirici
müdahalesi gerekir. Otomatik tiebreak yok, "N strike'tan sonra geç"
yok, graceful degradation yok.

## Test

```bash
python3 -m pytest tests/ -v
```

808 test lib birimlerini, her kancayı (subprocess zinciri) ve smoke
matrix'i (state × tool, STRICT no-fail-open, state lock,
completeness loop, DSI integration, PreCompact snapshot, reinforcement
reminder, Agent tool globally allowed, stale-emit sessiz) kapsar.

## Devre dışı bırakma

`~/.claude/settings.json`'daki `hooks` dizisinden `mycl` prefixli
girişleri sil. MyCL state dosyaları (`.mycl/`) proje başına yaşar
ve ayrı silinebilir.

## Anthropic Resmi Plugin'leri ile Birlikte Kullanım

MyCL, Anthropic'in curated plugin dizini (`anthropics/claude-plugins-official`)
ile **birlikte çalışacak** şekilde tasarlandı. 22-faz pipeline'ı
tamamlayan seçili resmi plugin'ler:

- **`security-guidance`** — Edit/Write/MultiEdit için `PreToolUse`
  kanca; Aşama 14 (Güvenlik) için inline pattern uyarıları ekler.
  Çakışma yok — `pre_tool.py` ile yan yana çalışır.
- **`anthropics/claude-code-security-review`** (ayrı repo) — manuel
  `/code-review` ile PR bazlı derin güvenlik denetimi. Aşama 14
  taraması sonrası repo geneli inceleme için.
- **`code-review`** / **`code-simplifier`** — manuel slash command'lar;
  Aşama 11 ve 12 için opsiyonel ikinci geçiş.
- **`session-report`** — manuel `/session-report` token / cache
  istatistiği. Aşama 22 tamlık denetimini **değil tamamlar** (yer
  almaz, ayrı kapsam: istatistik vs MUST kapsanma).

### ⚠️ Kanca çakışma uyarısı

`hookify` plugin'i (topluluk) **4 event'e** (UserPromptSubmit,
PreToolUse, PostToolUse, Stop) bağlanır — MyCL kanca zinciriyle
çakışır ve faz geçişlerini kesintiye uğratabilir. **MyCL ile birlikte
`hookify` install etmeyin.** Kural-tabanlı eylem önleme için MyCL
captured-rules'u `CLAUDE.md`'ye eklemek yeterli.

## İlham + Topluluk Referansları

MyCL olgun Claude Code topluluk projelerinin omuzlarında durur:

- **[Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec)** —
  spec-driven development framework; MyCL Aşama 4 spec blok formatı
  kavramsal olarak uyumlu.
- **[obra/superpowers](https://github.com/obra/superpowers)** — TDD
  methodology + spec-first workflow; MyCL Aşama 9 TDD döngüsü için
  referans.
- **[Playwright agents](https://github.com/topics/playwright-agent)** —
  Aşama 17 E2E test orchestration için.
- **[komunite/kalfa](https://github.com/komunite/kalfa)** — Türkçe
  Claude Code OS (10 agent, 22 komut, 993 skill); MyCL'in Türkçe
  niyet katmanı + Aşama 21 yerel rapor ilham kaynağı.
- **[Anthropic Issue #53223](https://github.com/anthropics/claude-code/issues/53223)** —
  "CLAUDE.md instruction compliance is architecturally unenforced"
  resmi tespiti; MyCL'in faz-bazlı PreToolUse enforcement +
  PreCompact reminder = Anthropic'in önerdiği deterministik
  counter-measure'ın doğrudan implementasyonu.

## Lisans

MIT — `LICENSE` dosyasına bakın.
