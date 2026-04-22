# ============================================================================
# Claude Code — Plugin Install Script (PowerShell)
# ============================================================================
# Windows kullanıcıları için PowerShell versiyonu.
#
# Kullanım:
#   1) PowerShell'i açın
#   2) Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   3) .\install-claude-plugins.ps1
# ============================================================================

$ErrorActionPreference = "Continue"

Write-Host "=== Claude Code Plugin Installer ===" -ForegroundColor Blue
Write-Host ""

# ---------------------------------------------------------------------------
# 0) Marketplace'leri ekle
# ---------------------------------------------------------------------------
Write-Host "[0/7] Marketplace'ler ekleniyor..." -ForegroundColor Yellow
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add obra/superpowers-marketplace
Write-Host ""

# ---------------------------------------------------------------------------
# 1) Proje Başlangıcı & Kurulum
# ---------------------------------------------------------------------------
Write-Host "[1/7] Proje Başlangıcı & Kurulum..." -ForegroundColor Yellow
claude plugin install claude-code-setup@claude-plugins-official
claude plugin install claude-md-management@claude-plugins-official
Write-Host ""

# ---------------------------------------------------------------------------
# 2) Geliştirme Öncesi Planlama
# ---------------------------------------------------------------------------
Write-Host "[2/7] Geliştirme Öncesi Planlama..." -ForegroundColor Yellow
claude plugin install feature-dev@claude-plugins-official
Write-Host ""

# ---------------------------------------------------------------------------
# 3) Aktif Geliştirme
# ---------------------------------------------------------------------------
Write-Host "[3/7] Aktif Geliştirme Araçları..." -ForegroundColor Yellow
claude plugin install frontend-design@claude-plugins-official
claude plugin install agent-sdk-dev@claude-plugins-official
claude plugin install plugin-dev@claude-plugins-official
claude plugin install skill-creator@claude-plugins-official
Write-Host ""

# ---------------------------------------------------------------------------
# 4) Kod Kalitesi & Refactoring
# ---------------------------------------------------------------------------
Write-Host "[4/7] Kod Kalitesi & Refactoring..." -ForegroundColor Yellow
claude plugin install code-simplifier@claude-plugins-official
claude plugin install hookify@claude-plugins-official
claude plugin install security-guidance@claude-plugins-official
Write-Host ""

# ---------------------------------------------------------------------------
# 5) Commit & PR Süreci
# ---------------------------------------------------------------------------
Write-Host "[5/7] Commit & PR Süreci..." -ForegroundColor Yellow
claude plugin install commit-commands@claude-plugins-official
claude plugin install pr-review-toolkit@claude-plugins-official
claude plugin install code-review@claude-plugins-official
Write-Host ""

# ---------------------------------------------------------------------------
# 6) İteratif İyileştirme + Superpowers
# ---------------------------------------------------------------------------
Write-Host "[6/7] İteratif İyileştirme & Superpowers..." -ForegroundColor Yellow
claude plugin install ralph-loop@claude-plugins-official
claude plugin install superpowers@superpowers-marketplace
Write-Host ""

# ---------------------------------------------------------------------------
# 7) LSP Plugin'leri
# ---------------------------------------------------------------------------
Write-Host "[7/7] Language Server Plugin'leri kuruluyor..." -ForegroundColor Yellow
Write-Host "Not: LSP binary'lerini (typescript-language-server, pyright vs.)" -ForegroundColor Blue
Write-Host "     sisteminize ayrıca kurmanız gerekir." -ForegroundColor Blue
Write-Host ""

claude plugin install typescript-lsp@claude-plugins-official
claude plugin install pyright-lsp@claude-plugins-official
claude plugin install gopls-lsp@claude-plugins-official
claude plugin install rust-analyzer-lsp@claude-plugins-official
claude plugin install clangd-lsp@claude-plugins-official
claude plugin install php-lsp@claude-plugins-official
claude plugin install swift-lsp@claude-plugins-official
claude plugin install kotlin-lsp@claude-plugins-official
claude plugin install csharp-lsp@claude-plugins-official
claude plugin install jdtls-lsp@claude-plugins-official
claude plugin install lua-lsp@claude-plugins-official

Write-Host ""
Write-Host "=== Kurulum tamamlandı! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Yüklü plugin'leri kontrol etmek için:  claude plugin list"
Write-Host "Bir plugin'i devre dışı bırakmak için:  claude plugin disable <plugin-adı>"
Write-Host "Güncelleme için:                        claude plugin update <plugin-adı>"
