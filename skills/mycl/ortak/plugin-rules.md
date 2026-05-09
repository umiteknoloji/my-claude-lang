---
name: mycl-plugin-rules
description: MyCL'in dış plugin orkestrasyonu için üç sözleşmesi — Kural A (yerel git init onayı), Kural B (curated dispatch), Kural C (.mcp.json filter). Hook'lar bu kurallara göre plugin scope'unu daraltır; herhangi birinin ihlali plugin orkestrasyonunu kapatır.
---

# Plugin Kuralları (A / B / C)

MyCL kendi 22 fazlı boru hattını dayatır AMA dış plugin'lerle çoklu-açı
doğrulama yapar. Plugin orkestrasyonu üç kural altında:

## Kural A — Yerel `.git/` zorunluluğu

MyCL plugin orkestrasyonu **yerel git deposu** varsayar. Her ilk
aktivasyonda:

1. `.git/` mevcut mu kontrol et
2. Yoksa kullanıcıya **bir kez** sor (kullanıcının dilinde):
   "MyCL plugin orkestrasyonu için yerel `git init` çalıştırılsın mı?"
3. Onay → `git init` (no remote, no push, no commit)
4. Karar `.mycl/config.json`'a yazılır → asla tekrar sorulmaz

`pre_tool.py` `bare git init` komutunu spec-approval block'tan istisna
tutar — plugin bootstrap için zorunludur. Diğer git komutları (commit,
push, add, ...) normal mutating Bash kuralına tabi.

## Kural B — Curated dispatch (sessiz çalıştır)

Curated plugin set sessizce dispatch edilir, MyCL'in kendi faz
mantığıyla **kapsam örtüşmesi olsa bile**. Örtüşme fazlalık değil,
çok-açılı doğrulamadır.

Plugin bulguları MyCL faz prose'una `(file, line, rule-equivalent)`
üzerinden dedupe edilerek birleştirilir.

**Plugin'ler anlaşmazlığa düşerse:** çatışma, provenance (hangi plugin
ne dedi) + her iki gerekçeyle birlikte tek bir Aşama 8 risk maddesi
olarak yüzeye çıkar. Geliştirici AskUserQuestion ile karar verir;
otomatik tiebreaker uygulanmaz. Karar otomatik rule-capture tetikler.

## Kural C — `.mcp.json` filter

Hiçbir MCP-server tabanlı plugin çağrılmaz. Kaynak ağacında `.mcp.json`
bulunan herhangi bir plugin curated set'ten **curation anında** elenir.

`Bash` üzerinden çağrılan ikili CLI araçları (semgrep, linter,
formatter, derleyici) MCP **değildir** ve izinlidir — yerel çalışırlar,
MCP taşımacılığı içermezler.

İzin verilen tek ağ trafiği: projeden türetilmiş veri taşımayan
**statik kaynak indirmeleri** (örn. Semgrep kural paketleri).

## Uygulama (lib/plugin.py)

```python
plugin.is_git_repo(project_root)            → bool
plugin.should_ask_git_init_consent(...)     → bool
plugin.record_git_init_consent(decision)    → None
plugin.curated_plugins(scan_root)           → list[Path]   # Kural C filter
```

Hook'lar bu API'yi kullanır; doğrudan `.git/` veya `.mcp.json` taraması
hook satırına gömülmez (DRY + tek değişim noktası).

---

# Plugin Rules (A / B / C)

MyCL imposes its own 22-phase pipeline AND multi-angle validates with
external plugins. Plugin orchestration follows three rules:

## Rule A — local `.git/` required

On first activation per project, if no git repo: ask the user **once**
in their language whether MyCL may run a local `git init` (no remote,
no push, no commit). Decision persists in `.mycl/config.json`; never
re-asked. `pre_tool.py` exempts bare `git init` from the spec-approval
block for plugin bootstrap.

## Rule B — curated silent dispatch

Curated plugins dispatch silently even when their scope overlaps MyCL
phase logic. Findings are merged via `(file, line, rule-equivalent)`
dedup. On plugin disagreement: surface the conflict as a single
Phase-8 risk item with provenance + both rationales — developer
decides via AskUserQuestion (no auto-tiebreak).

## Rule C — `.mcp.json` filter

No MCP-server plugin is invoked. Any plugin source tree containing
`.mcp.json` is filtered out at curation time. Binary CLI tools via
`Bash` (semgrep, linters, formatters, compilers) are NOT MCP and
allowed — they run locally with no MCP transport. The only permitted
network traffic is downloading static resources (e.g. Semgrep rule
packs) with no project-derived payload.
