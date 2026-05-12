---
name: mycl-asama14-guvenlik
description: MyCL Aşama 14 — Güvenlik (Kalite Pipeline 4/4) TÜM proje genelinde. SQL injection, auth bypass, XSS, CSRF, hardcoded secret, sızıntı. semgrep SAST + npm audit (stack equivalent) otomatik. HIGH/MEDIUM Aşama 10'a escalate edilebilir. Çıktı asama-14-rescan count=0.
---

# Aşama 14 — Güvenlik (Kalite Pipeline 4/4)

## Amaç

**TÜM proje genelinde** güvenlik açıklarını tara + düzelt. Diğer
kalite fazlarından farklı: scope yeni dosyalar değil, **tüm proje**.

## Aşama 14 mercek

| Sorun | Örnek |
|---|---|
| SQL injection | String concat query, ORM'siz raw query |
| Auth bypass | Missing middleware, wrong check order |
| XSS | Unescaped user input rendered as HTML |
| CSRF | Missing CSRF token, SameSite cookie eksik |
| Hardcoded secret | API key, password, token in source |
| Bilgi sızıntısı | Stack trace exposure, debug log production |

## Otomatik araçlar

```bash
# Static analysis (SAST)
semgrep --config p/security-audit --json

# Dependency vulnerabilities
npm audit            # Node
pip-audit            # Python
cargo audit          # Rust
bundle audit         # Ruby
go list -json -m -u  # Go

# Secret scanner
truffleHog .
gitleaks detect
```

## Pipeline (3-step döngü)

1. **Tara** → semgrep + audit + secret scanner çalıştır, JSON output
   parse et
2. **Düzelt** → HIGH/MEDIUM otomatik fix:
   - SQL inj → parametrized query
   - XSS → escape / textContent / sanitize
   - Hardcoded secret → env var + .env.example template
   - Vulnerable dep → bump version
3. **Yeniden tara** → K=0 olana kadar tekrar

**Araç kurulu değilse:** `asama-14-not-applicable reason=tool-not-installed`
emit edip devam et. Tek araç eksikse en az bir alternatif denenir
(örn. semgrep yoksa stack-spesifik linter; pip-audit yoksa
`pip list --outdated`). Hiç araç yoksa skip; bu durum Aşama 22
tamlık denetiminde "Açık Konular"'a düşer.

## Aşama 10 ile bağlantı

HIGH/MEDIUM bulgular **otomatik fix edilir**; ancak çözüm belirsizse
**Aşama 10 risk dialog'a escalate** edilebilir:
- "Bu auth bypass'a otomatik fix uygulayamam — geliştirici kararına
  bırakıyorum" → Aşama 10'a yeni risk eklenir

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Çıktı (audit)

> **Model:** `asama-14-complete` (rescan count=0 olduktan sonra) cevap metninde düz yazıyla.
> **Hook:** `asama-14-scan` (semgrep+audit+secret), `asama-14-issue-N-fixed`, `asama-14-rescan` (tarayıcı/fixer döngüsünde hook yazar).
> **Detay:** ana skill "Audit emission kanalı" sözleşmesi.

```
asama-14-scan count=K (semgrep+audit+secret)
asama-14-issue-N-fixed (her bulgu)
asama-14-rescan count=0
asama-14-complete
```

### Hook enforcement (1.0.27)

Aşama 14, 1.0.27 itibarıyla **Aşama 11-13 ile aynı generic text-trigger
kanalını kullanır**. Eski tasarım `subagent_orchestration: true`
bayrağıyla `mycl-phase-runner` subagent'ına yönlendiriyordu; ancak
subagent read-only (`Read/Glob/Grep/AskUserQuestion`) — `Bash`
çalıştıramadığı için semgrep/npm audit/secret scanner fiilen
çağrılamıyordu. Şu an:

- Model ana context'te semgrep/npm audit/gitleaks'i `Bash` ile koşar
- JSON çıktısını parse eder
- HIGH/MEDIUM bulguları auto-fix uygular
- Her bulgu için `asama-14-issue-M-fixed` text-trigger yazar
- Tarama döngüsü için `asama-14-scan count=K` + `asama-14-rescan count=K`
- Bitişte model `asama-14-complete` yazar; hook bunu mevcut text-trigger
  kanalında yakalar (hook auto-emit YAPMAZ)

## Plugin Kural B (gelecek tur)

Curated security plugin'lerin (snyk, sonarqube CLI vb.) sessizce
dispatch'i şu an **enforce edilmiyor** — `hooks/lib/plugin.py` curated
plugin query API'sini sağlıyor ama dispatch döngüsü hiçbir hook'tan
çağrılmıyor. Skill, model davranış önceliği olarak bu plugin'leri
dikkate alabilir ama otomatik orkestrasyon ileri tur konusu
(captured-rule: "behavioral feature without hook enforcement is
incomplete").

## Anti-pattern

- ❌ "Güvenlik audit yapmadık, çünkü internal tool" — internal tool
  da supply chain saldırısı kurban olabilir
- ❌ npm audit FIXED ile patch etmeden geçme — major version bump
  gerektirenleri Aşama 10'a taşı
- ❌ Hardcoded secret bulundu → .gitignore'a ekleyip "tamam" deme —
  git history'den de temizle (`git filter-branch` veya BFG); secret
  rotate

---

# Phase 14 — Security (Quality Pipeline 4/4)

## Goal

Project-wide security audit + auto-fix. Unlike other quality phases,
scope is **the entire project**, not just changed files.

## Lenses

SQL injection, auth bypass, XSS (unescaped HTML rendering of user
input), CSRF, hardcoded secrets, info leakage.

## Automated tools

`semgrep --config p/security-audit`, `npm audit` / `pip-audit` /
`cargo audit` / `bundle audit`, `truffleHog` / `gitleaks`.

## Pipeline

Scan (parse JSON) → auto-fix HIGH/MEDIUM (parametrized queries, XSS
escape/sanitize, env var migration, dep bumps) → rescan until K=0.

## Phase 10 escalation

When auto-fix is unsafe, surface as a Phase 10 risk dialog item.

## Allowed tools

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Audit output

> **Model:** `asama-14-complete` (after rescan count=0) plain text in reply.
> **Hook:** `asama-14-scan` (semgrep+audit+secret), `asama-14-issue-N-fixed`, `asama-14-rescan` (scanner/fixer cycle).
> **Details:** see "Audit emission channel" contract in main skill.

`asama-14-scan count=K` → `asama-14-issue-N-fixed` →
`asama-14-rescan count=0` → `asama-14-complete`.

### Hook enforcement (1.0.27)

Phase 14 now uses the **same generic quality text-trigger channel as
Phases 11-13**. The old `subagent_orchestration: true` flag routed
execution to `mycl-phase-runner`, but that subagent is read-only
(`Read/Glob/Grep/AskUserQuestion` — no `Bash`), making
semgrep/npm-audit/gitleaks impossible. Now the model runs scanners
via `Bash` in the main context, parses JSON output, auto-fixes
HIGH/MEDIUM findings, and emits the standard quality pipeline
text-triggers (`asama-14-scan / issue-M-fixed / rescan / complete`).
Hook does NOT auto-emit `asama-14-complete` or `asama-14-escalation-
needed` (boundary preserved from 1.0.26).

## Plugin Rule B (deferred)

Curated security plugin dispatch (snyk, sonarqube CLI, etc.) is **not
enforced** yet — `hooks/lib/plugin.py` provides curated-plugin query
APIs but no hook calls a dispatch loop. Skill prose may treat these
as model behavioral guidance, but automatic orchestration is a future
release (captured rule: "behavioral feature without hook enforcement
is incomplete").

## Anti-patterns

- Skipping audit ("internal tool").
- `npm audit fix` without checking major bumps (escalate to Phase 10).
- Adding `.gitignore` after secret leak without history scrub +
  rotate.
