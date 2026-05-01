# ============================================================================
# Claude Code — Plugin + LSP Binary Install Script (PowerShell)
# ============================================================================
# Windows için — hem plugin'leri hem de LSP binary'lerini kurar.
#
# Ön gereksinimler:
#   - Claude Code (claude CLI)
#   - Node.js + npm
#   - winget (Windows 10+ ile gelir)
#   - İsteğe bağlı: scoop veya chocolatey
#
# Kullanım:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\install-claude-plugins-full.ps1
# ============================================================================

$ErrorActionPreference = "Continue"

# ----- Yardımcı fonksiyonlar -----
function Log-Info($msg)  { Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Log-Ok($msg)    { Write-Host "[✓] $msg" -ForegroundColor Green }
function Log-Warn($msg)  { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Log-Err($msg)   { Write-Host "[✗] $msg" -ForegroundColor Red }
function Log-Step($msg)  { Write-Host "`n═══ $msg ═══" -ForegroundColor Yellow }

function Test-Command($name) {
    $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

# ============================================================================
# BAŞLA
# ============================================================================

Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Blue
Write-Host "║   Claude Code — Plugin + LSP Full Installer   ║" -ForegroundColor Blue
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Blue

# claude CLI kontrolü
if (-not (Test-Command "claude")) {
    Log-Err "claude CLI bulunamadı. Önce Claude Code'u kurun: https://claude.com/download"
    exit 1
}
Log-Ok "claude CLI bulundu"

# winget kontrolü
$hasWinget = Test-Command "winget"
$hasScoop  = Test-Command "scoop"
$hasChoco  = Test-Command "choco"

if (-not ($hasWinget -or $hasScoop -or $hasChoco)) {
    Log-Warn "winget/scoop/choco yok. Bazı LSP'ler manuel kurulmalı."
}

# ============================================================================
# BÖLÜM 1: Plugin'leri Kur
# ============================================================================

Log-Step "1. Marketplace'ler"
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add obra/superpowers-marketplace

Log-Step "2. Proje Başlangıcı & Kurulum"
claude plugin install claude-code-setup@claude-plugins-official
claude plugin install claude-md-management@claude-plugins-official

Log-Step "3. Geliştirme Öncesi Planlama"
claude plugin install feature-dev@claude-plugins-official

Log-Step "4. Aktif Geliştirme"
claude plugin install frontend-design@claude-plugins-official
claude plugin install agent-sdk-dev@claude-plugins-official
claude plugin install plugin-dev@claude-plugins-official
claude plugin install skill-creator@claude-plugins-official

Log-Step "5. Kod Kalitesi & Refactoring"
claude plugin install code-simplifier@claude-plugins-official
claude plugin install hookify@claude-plugins-official
claude plugin install security-guidance@claude-plugins-official

Log-Step "6. Commit & PR Süreci"
claude plugin install commit-commands@claude-plugins-official
claude plugin install pr-review-toolkit@claude-plugins-official
claude plugin install code-review@claude-plugins-official

Log-Step "7. İteratif İyileştirme + Superpowers"
claude plugin install ralph-loop@claude-plugins-official
claude plugin install superpowers@superpowers-marketplace

# ============================================================================
# BÖLÜM 2: LSP Plugin'leri + Binary'leri
# ============================================================================

Log-Step "8. LSP Plugin'leri + Binary'leri"

# --- TypeScript / JavaScript ---
Log-Info "TypeScript/JavaScript..."
claude plugin install typescript-lsp@claude-plugins-official
if (Test-Command "npm") {
    npm install -g typescript typescript-language-server
    Log-Ok "typescript-language-server kuruldu"
} else {
    Log-Warn "npm yok — typescript-language-server atlandı (Node.js kurun)"
}

# --- Python (Pyright) ---
Log-Info "Python (Pyright)..."
claude plugin install pyright-lsp@claude-plugins-official
if (Test-Command "npm") {
    npm install -g pyright
    Log-Ok "pyright kuruldu"
} else {
    Log-Warn "npm yok — pyright atlandı"
}

# --- Go (gopls) ---
Log-Info "Go (gopls)..."
claude plugin install gopls-lsp@claude-plugins-official
if (Test-Command "go") {
    go install golang.org/x/tools/gopls@latest
    Log-Ok "gopls kuruldu (PATH: $(go env GOPATH)\bin)"
} else {
    Log-Warn "go yok — gopls atlandı. winget install GoLang.Go"
}

# --- Rust (rust-analyzer) ---
Log-Info "Rust (rust-analyzer)..."
claude plugin install rust-analyzer-lsp@claude-plugins-official
if (Test-Command "rustup") {
    rustup component add rust-analyzer
    Log-Ok "rust-analyzer kuruldu"
} else {
    Log-Warn "rustup yok — rust-analyzer atlandı. https://rustup.rs"
}

# --- C / C++ (clangd) ---
Log-Info "C/C++ (clangd)..."
claude plugin install clangd-lsp@claude-plugins-official
if (-not (Test-Command "clangd")) {
    if ($hasWinget) {
        winget install LLVM.LLVM
        Log-Ok "LLVM (clangd dahil) kuruldu"
    } elseif ($hasScoop) {
        scoop install llvm
    } else {
        Log-Warn "clangd manuel kurulmalı: https://releases.llvm.org"
    }
} else {
    Log-Ok "clangd zaten var"
}

# --- PHP (Intelephense) ---
Log-Info "PHP (Intelephense)..."
claude plugin install php-lsp@claude-plugins-official
if (Test-Command "npm") {
    npm install -g intelephense
    Log-Ok "intelephense kuruldu"
} else {
    Log-Warn "npm yok — intelephense atlandı"
}

# --- Swift (Windows için sınırlı destek) ---
Log-Info "Swift..."
claude plugin install swift-lsp@claude-plugins-official
Log-Warn "Swift LSP Windows'ta sınırlı desteklenir. https://swift.org/download adresinden toolchain kurun"

# --- Kotlin ---
Log-Info "Kotlin..."
claude plugin install kotlin-lsp@claude-plugins-official
Log-Warn "kotlin-lsp'yi manuel kurun: https://github.com/Kotlin/kotlin-lsp/releases"

# --- C# ---
Log-Info "C# (csharp-ls)..."
claude plugin install csharp-lsp@claude-plugins-official
if (Test-Command "dotnet") {
    dotnet tool install -g csharp-ls
    if ($LASTEXITCODE -ne 0) { dotnet tool update -g csharp-ls }
    Log-Ok "csharp-ls kuruldu"
} else {
    Log-Warn "dotnet yok. winget install Microsoft.DotNet.SDK.8"
}

# --- Java (jdtls) ---
Log-Info "Java (jdtls)..."
claude plugin install jdtls-lsp@claude-plugins-official
if (-not (Test-Command "jdtls")) {
    if ($hasScoop) {
        scoop install jdtls
        Log-Ok "jdtls kuruldu"
    } else {
        Log-Warn "jdtls'yi manuel kurun: https://download.eclipse.org/jdtls/milestones/"
    }
} else {
    Log-Ok "jdtls zaten var"
}

# --- Lua ---
Log-Info "Lua..."
claude plugin install lua-lsp@claude-plugins-official
if (-not (Test-Command "lua-language-server")) {
    if ($hasWinget) {
        winget install LuaLS.lua-language-server
        Log-Ok "lua-language-server kuruldu"
    } elseif ($hasScoop) {
        scoop install lua-language-server
    } else {
        Log-Warn "lua-language-server manuel kurulmalı: https://luals.github.io"
    }
} else {
    Log-Ok "lua-language-server zaten var"
}

# ============================================================================
# BİTİŞ
# ============================================================================

Write-Host ""
Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║          Kurulum tamamlandı!                   ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Kontrol komutları:"
Write-Host "  claude plugin list                # Plugin'leri listele"
Write-Host "  Get-Command typescript-language-server  # LSP binary kontrolü"
Write-Host ""
Log-Warn "Bazı LSP'ler (Go, Rust, .NET) PATH güncellemesi gerektirebilir."
Log-Warn "PowerShell'i kapatıp yeniden açın ki yeni PATH aktif olsun."
