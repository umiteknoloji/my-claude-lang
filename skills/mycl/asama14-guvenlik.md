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

## Aşama 10 ile bağlantı

HIGH/MEDIUM bulgular **otomatik fix edilir**; ancak çözüm belirsizse
**Aşama 10 risk dialog'a escalate** edilebilir:
- "Bu auth bypass'a otomatik fix uygulayamam — geliştirici kararına
  bırakıyorum" → Aşama 10'a yeni risk eklenir

## İzinli tool'lar (Layer B)

`Write, Edit, MultiEdit, Bash, AskUserQuestion` + global readonly.

## Çıktı (audit)

```
asama-14-scan count=K (semgrep+audit+secret)
asama-14-issue-N-fixed (her bulgu)
asama-14-rescan count=0
asama-14-complete
```

## Plugin Kural B uygulaması

Curated security plugin'ler (semgrep dışında — örn. snyk, sonarqube
CLI) sessizce çalıştırılır. Bulgular dedupe edilir, conflict'ler
Aşama 10'a escalate.

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

`asama-14-scan count=K` → `asama-14-issue-N-fixed` →
`asama-14-rescan count=0` → `asama-14-complete`.

## Plugin Rule B

Curated security plugins (besides semgrep) dispatched silently;
findings dedup; conflicts → Phase 10 risk.

## Anti-patterns

- Skipping audit ("internal tool").
- `npm audit fix` without checking major bumps (escalate to Phase 10).
- Adding `.gitignore` after secret leak without history scrub +
  rotate.
