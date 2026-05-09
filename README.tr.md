# MyCL — my-claude-lang 1.0.0

Claude Code üstüne anlam-doğrulama katmanı. MyCL 22 fazlı bir
geliştirme boru hattı dayatır, audit zincirleriyle disiplini sıkar
ve fail-open YAPMAZ. Pure Python 3.8+, AI agent framework yok, MCP
server yok.

> English: [README.md](README.md)

## MyCL nedir (ne değildir)

MyCL **şudur**: dört Python kanca (`UserPromptSubmit`, `PreToolUse`,
`PostToolUse`, `Stop`) ki:

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
5. 4 kancayı `~/.claude/settings.json`'a MERGE eder (idempotent —
   tekrar çalıştırılabilir)
6. Smoke test (py_compile + lib import)

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
                  ├─ 4 kanca (Claude Code çağırır)
                  ├─ state.json (current_phase, spec_approved, ...)
                  ├─ audit.log (append-only olay kaydı)
                  ├─ 22 faz veri olarak (gate_spec.json)
                  └─ her faz için skill dosyası
```

Kancalar **dolaylı** iletişim kurar — `state.json` + `audit.log`
üzerinden. Birbirini import etmez. Dört kanca da `hooks/lib/*`
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

521 test lib birimlerini, her kancayı (subprocess zinciri) ve smoke
matrix'i (state × tool, STRICT no-fail-open, state lock,
completeness loop, DSI integration) kapsar.

## Devre dışı bırakma

`~/.claude/settings.json`'daki `hooks` dizisinden `mycl` prefixli
girişleri sil. MyCL state dosyaları (`.mycl/`) proje başına yaşar
ve ayrı silinebilir.

## Lisans

MIT — `LICENSE` dosyasına bakın.
