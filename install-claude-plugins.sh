#!/usr/bin/env bash
# ============================================================================
# Claude Code — Plugin + LSP Binary Install Script
# ============================================================================
# Bu script hem Claude Code plugin'lerini hem de LSP binary'lerini kurar.
#
# Desteklenen platformlar: macOS (brew), Linux (apt/dnf), Windows (WSL)
#
# Ön gereksinimler:
#   - claude CLI (Claude Code yüklü)
#   - node/npm
#   - Projen için uygun runtime'lar (go, rustup, dotnet, java vs. opsiyonel)
#
# Kullanım:
#   chmod +x install-claude-plugins-full.sh
#   ./install-claude-plugins-full.sh
# ============================================================================

set -e

# ----- Renkler -----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# ----- Yardımcı fonksiyonlar -----
log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()   { echo -e "${RED}[✗]${NC} $1"; }
log_step()  { echo -e "\n${YELLOW}═══ $1 ═══${NC}"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ----- Platform tespiti -----
OS=""
PKG_MGR=""

detect_platform() {
    case "$(uname -s)" in
        Darwin*)
            OS="macos"
            if has_cmd brew; then
                PKG_MGR="brew"
            else
                log_err "Homebrew bulunamadı. https://brew.sh adresinden kurun."
                exit 1
            fi
            ;;
        Linux*)
            OS="linux"
            if has_cmd apt-get; then
                PKG_MGR="apt"
            elif has_cmd dnf; then
                PKG_MGR="dnf"
            elif has_cmd pacman; then
                PKG_MGR="pacman"
            else
                log_warn "Bilinen paket yöneticisi bulunamadı. Bazı LSP'ler manuel kurulmalı."
                PKG_MGR="unknown"
            fi
            ;;
        *)
            log_err "Desteklenmeyen platform: $(uname -s)"
            exit 1
            ;;
    esac
    log_info "Platform: $OS, Paket yöneticisi: $PKG_MGR"
}

install_pkg() {
    # $1: brew_name   $2: apt_name   $3: dnf_name
    local name="$1"
    case "$PKG_MGR" in
        brew)    brew install "$1" 2>/dev/null || brew upgrade "$1" 2>/dev/null || true ;;
        apt)     sudo apt-get install -y "$2" ;;
        dnf)     sudo dnf install -y "$3" ;;
        pacman)  sudo pacman -S --noconfirm "$2" ;;
        *)       log_warn "$name manuel kurulmalı" ;;
    esac
}

# ============================================================================
# BAŞLA
# ============================================================================

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Claude Code — Plugin + LSP Full Installer   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"

detect_platform

# claude CLI kontrolü
if ! has_cmd claude; then
    log_err "claude CLI bulunamadı. Önce Claude Code'u kurun: https://claude.com/download"
    exit 1
fi
log_ok "claude CLI bulundu"

# ============================================================================
# BÖLÜM 1: Plugin'leri Kur
# ============================================================================

log_step "1. Marketplace'ler"
claude plugin marketplace add anthropics/claude-plugins-official || true
claude plugin marketplace add obra/superpowers-marketplace || true

log_step "2. Proje Başlangıcı & Kurulum"
claude plugin install claude-code-setup@claude-plugins-official
claude plugin install claude-md-management@claude-plugins-official

log_step "3. Geliştirme Öncesi Planlama"
claude plugin install feature-dev@claude-plugins-official

log_step "4. Aktif Geliştirme"
claude plugin install frontend-design@claude-plugins-official
claude plugin install agent-sdk-dev@claude-plugins-official
claude plugin install plugin-dev@claude-plugins-official
claude plugin install skill-creator@claude-plugins-official

log_step "5. Kod Kalitesi & Refactoring"
claude plugin install code-simplifier@claude-plugins-official
claude plugin install hookify@claude-plugins-official
claude plugin install security-guidance@claude-plugins-official

log_step "6. Commit & PR Süreci"
claude plugin install commit-commands@claude-plugins-official
claude plugin install pr-review-toolkit@claude-plugins-official
claude plugin install code-review@claude-plugins-official

log_step "7. İteratif İyileştirme + Superpowers"
claude plugin install ralph-loop@claude-plugins-official
claude plugin install superpowers@superpowers-marketplace

# ============================================================================
# BÖLÜM 2: LSP Plugin'lerini + Binary'lerini Kur
# ============================================================================

log_step "8. LSP Plugin'leri + Binary'leri"

# --- TypeScript / JavaScript ---
log_info "TypeScript/JavaScript..."
claude plugin install typescript-lsp@claude-plugins-official
if has_cmd npm; then
    npm install -g typescript typescript-language-server
    log_ok "typescript-language-server kuruldu"
else
    log_warn "npm yok — typescript-language-server atlandı"
fi

# --- Python (Pyright) ---
log_info "Python (Pyright)..."
claude plugin install pyright-lsp@claude-plugins-official
if has_cmd npm; then
    npm install -g pyright
    log_ok "pyright kuruldu"
else
    log_warn "npm yok — pyright atlandı"
fi

# --- Go (gopls) ---
log_info "Go (gopls)..."
claude plugin install gopls-lsp@claude-plugins-official
if has_cmd go; then
    go install golang.org/x/tools/gopls@latest
    log_ok "gopls kuruldu (PATH: $(go env GOPATH)/bin)"
else
    log_warn "go yok — gopls atlandı (Go'yu https://go.dev/dl adresinden kurun)"
fi

# --- Rust (rust-analyzer) ---
log_info "Rust (rust-analyzer)..."
claude plugin install rust-analyzer-lsp@claude-plugins-official
if has_cmd rustup; then
    rustup component add rust-analyzer
    log_ok "rust-analyzer kuruldu"
elif has_cmd cargo; then
    log_warn "rustup yok ama cargo var. rustup önerilir: https://rustup.rs"
else
    log_warn "rust yok — rust-analyzer atlandı"
fi

# --- C / C++ (clangd) ---
log_info "C/C++ (clangd)..."
claude plugin install clangd-lsp@claude-plugins-official
if ! has_cmd clangd; then
    install_pkg "llvm" "clangd" "clang-tools-extra"
    log_ok "clangd kuruldu"
else
    log_ok "clangd zaten var"
fi

# --- PHP (Intelephense) ---
log_info "PHP (Intelephense)..."
claude plugin install php-lsp@claude-plugins-official
if has_cmd npm; then
    npm install -g intelephense
    log_ok "intelephense kuruldu"
else
    log_warn "npm yok — intelephense atlandı"
fi

# --- Swift (sadece macOS) ---
log_info "Swift..."
claude plugin install swift-lsp@claude-plugins-official
if [ "$OS" = "macos" ]; then
    if has_cmd sourcekit-lsp; then
        log_ok "sourcekit-lsp zaten var (Xcode ile gelir)"
    else
        log_warn "sourcekit-lsp bulunamadı. Xcode Command Line Tools kurun: xcode-select --install"
    fi
else
    log_warn "Swift LSP öncelikle macOS içindir. Linux için Swift toolchain kurun: https://swift.org/download"
fi

# --- Kotlin ---
log_info "Kotlin..."
claude plugin install kotlin-lsp@claude-plugins-official
log_warn "kotlin-lsp binary'sini manuel kurun: https://github.com/Kotlin/kotlin-lsp/releases"
log_warn "İndirdikten sonra 'kotlin-lsp' komutunun PATH'te olduğundan emin olun"

# --- C# ---
log_info "C# (csharp-ls)..."
claude plugin install csharp-lsp@claude-plugins-official
if has_cmd dotnet; then
    if dotnet tool install -g csharp-ls 2>/dev/null || dotnet tool update -g csharp-ls 2>/dev/null; then
        log_ok "csharp-ls kuruldu"
    else
        log_warn "csharp-ls kurulamadı (NuGet paketi bozuk olabilir) — atlandı"
    fi
else
    log_warn "dotnet yok — csharp-ls atlandı (https://dotnet.microsoft.com/download)"
fi

# --- Java (jdtls) ---
log_info "Java (jdtls)..."
claude plugin install jdtls-lsp@claude-plugins-official
if ! has_cmd jdtls; then
    install_pkg "jdtls" "jdtls" "jdtls"
    log_ok "jdtls kurulum denendi"
else
    log_ok "jdtls zaten var"
fi

# --- Lua ---
log_info "Lua..."
claude plugin install lua-lsp@claude-plugins-official
if ! has_cmd lua-language-server; then
    install_pkg "lua-language-server" "lua-language-server" "lua-language-server"
    log_ok "lua-language-server kurulum denendi"
else
    log_ok "lua-language-server zaten var"
fi

# ============================================================================
# BİTİŞ
# ============================================================================

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Kurulum tamamlandı!                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo "Kontrol komutları:"
echo "  claude plugin list                      # Plugin'leri listele"
echo "  which typescript-language-server        # LSP binary'lerini kontrol et"
echo "  which pyright-langserver                # (hangisini kurduysan)"
echo ""
log_warn "Bazı LSP'ler (Go, Rust, .NET) PATH güncellemesi gerektirebilir."
log_warn "Terminal'i yeniden başlatmayı veya shell'inizi reload etmeyi unutmayın."
