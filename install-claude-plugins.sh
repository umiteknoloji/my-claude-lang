#!/usr/bin/env bash
# ============================================================================
# Claude Code — Plugin Install Script
# ============================================================================
# Resmi (claude-plugins-official) marketplace Claude Code ile zaten hazır gelir.
# Superpowers için ayrıca obra/superpowers-marketplace eklenir.
#
# Kullanım:
#   1) chmod +x install-claude-plugins.sh
#   2) ./install-claude-plugins.sh
#
# Not: `claude` CLI'nin PATH'te olması gerekir (Claude Code yüklü olmalı).
# ============================================================================

set -e  # Hata olursa dur

# Renkler
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No color

echo -e "${BLUE}=== Claude Code Plugin Installer ===${NC}"
echo ""

# ---------------------------------------------------------------------------
# 0) Marketplace'leri ekle
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[0/4] Marketplace'ler ekleniyor...${NC}"
# Resmi marketplace zaten default gelir, yine de idempotent olsun diye ekleyelim.
claude plugin marketplace add anthropics/claude-plugins-official || true
# Superpowers için topluluk marketplace'i
claude plugin marketplace add obra/superpowers-marketplace || true
echo ""

# ---------------------------------------------------------------------------
# 1) Proje Başlangıcı & Kurulum
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[1/6] Proje Başlangıcı & Kurulum...${NC}"
claude plugin install claude-code-setup@claude-plugins-official
claude plugin install claude-md-management@claude-plugins-official
echo ""

# ---------------------------------------------------------------------------
# 2) Geliştirme Öncesi Planlama
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[2/6] Geliştirme Öncesi Planlama...${NC}"
claude plugin install feature-dev@claude-plugins-official
echo ""

# ---------------------------------------------------------------------------
# 3) Aktif Geliştirme
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[3/6] Aktif Geliştirme Araçları...${NC}"
claude plugin install frontend-design@claude-plugins-official
claude plugin install agent-sdk-dev@claude-plugins-official
claude plugin install plugin-dev@claude-plugins-official
claude plugin install skill-creator@claude-plugins-official
echo ""

# ---------------------------------------------------------------------------
# 4) Kod Kalitesi & Refactoring
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[4/6] Kod Kalitesi & Refactoring...${NC}"
claude plugin install code-simplifier@claude-plugins-official
claude plugin install hookify@claude-plugins-official
claude plugin install security-guidance@claude-plugins-official
echo ""

# ---------------------------------------------------------------------------
# 5) Commit & PR Süreci
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[5/6] Commit & PR Süreci...${NC}"
claude plugin install commit-commands@claude-plugins-official
claude plugin install pr-review-toolkit@claude-plugins-official
claude plugin install code-review@claude-plugins-official
echo ""

# ---------------------------------------------------------------------------
# 6) İteratif İyileştirme + Superpowers
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[6/6] İteratif İyileştirme & Superpowers...${NC}"
claude plugin install ralph-loop@claude-plugins-official
claude plugin install superpowers@superpowers-marketplace
echo ""

# ---------------------------------------------------------------------------
# LSP Plugin'leri (opsiyonel — dilediğinizi kurun)
# ---------------------------------------------------------------------------
echo -e "${YELLOW}[LSP] Language Server Plugin'leri kuruluyor...${NC}"
echo -e "${BLUE}Not: LSP plugin'leri sadece Claude Code tarafındaki konfigürasyonu ekler.${NC}"
echo -e "${BLUE}      Asıl LSP binary'lerini (typescript-language-server, pyright vs.)${NC}"
echo -e "${BLUE}      sisteminize ayrıca kurmanız gerekir.${NC}"
echo ""

# Hepsini kurmak isterseniz:
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

echo ""
echo -e "${GREEN}=== Kurulum tamamlandı! ===${NC}"
echo ""
echo "Yüklü plugin'leri kontrol etmek için:  claude plugin list"
echo "Bir plugin'i devre dışı bırakmak için:  claude plugin disable <plugin-adı>"
echo "Güncelleme için:                        claude plugin update <plugin-adı>"
