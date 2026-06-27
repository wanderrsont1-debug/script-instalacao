#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# test_hyprland.sh — Teste de validação do instalador Hyprland
# Modo dry-run: simula todas as etapas sem instalar nada
# ═══════════════════════════════════════════════════════════════

set -o pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─────────────────────────────────────────────────────────────
# Cores e contadores
# ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0
TOTAL=0

# ─────────────────────────────────────────────────────────────
# Funções de resultado
# ─────────────────────────────────────────────────────────────
pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; ((PASS++)); ((TOTAL++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); ((TOTAL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }
section() {
    echo ""
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│  $1$(printf '%*s' $((55 - ${#1})) '')│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
}

# ─────────────────────────────────────────────────────────────
# TESTE 1: Sintaxe dos scripts
# ─────────────────────────────────────────────────────────────
section "1. SINTAXE DOS SCRIPTS"

for script in \
    "$REPO_DIR/install.sh" \
    "$REPO_DIR/lib/hyprland.sh" \
    "$REPO_DIR/lib/utils.sh" \
    "$REPO_DIR/lib/checks.sh" \
    "$REPO_DIR/lib/packages.sh" \
    "$REPO_DIR/lib/dotfiles.sh"
do
    name=$(basename "$script")
    if bash -n "$script" 2>/dev/null; then
        pass "$name — sintaxe OK"
    else
        fail "$name — ERRO de sintaxe:"
        bash -n "$script"
    fi
done

# ─────────────────────────────────────────────────────────────
# TESTE 2: Estrutura de arquivos obrigatórios
# ─────────────────────────────────────────────────────────────
section "2. ESTRUTURA DE ARQUIVOS"

required_files=(
    "$REPO_DIR/install.sh"
    "$REPO_DIR/lib/hyprland.sh"
    "$REPO_DIR/lib/utils.sh"
    "$REPO_DIR/lib/checks.sh"
    "$REPO_DIR/lib/packages.sh"
    "$REPO_DIR/lib/dotfiles.sh"
    "$REPO_DIR/lib/greeter.sh"
    "$REPO_DIR/packages/hyprland-arch.txt"
    "$REPO_DIR/packages/hyprland-fedora.txt"
)

for f in "${required_files[@]}"; do
    if [ -f "$f" ]; then
        pass "$(realpath --relative-to="$REPO_DIR" "$f") existe"
    else
        fail "$(realpath --relative-to="$REPO_DIR" "$f") NÃO encontrado"
    fi
done

# ─────────────────────────────────────────────────────────────
# TESTE 3: Módulos de dotfiles
# ─────────────────────────────────────────────────────────────
section "3. MÓDULOS DE DOTFILES (dotfiles-hyprland/)"

modules=(hyprland waybar wofi swaync eww ghostty btop fastfetch wallpapers)
dotfiles_dir="$REPO_DIR/dotfiles-hyprland"

if [ -d "$dotfiles_dir" ]; then
    pass "Pasta dotfiles-hyprland/ existe"
    for mod in "${modules[@]}"; do
        if [ -d "$dotfiles_dir/$mod" ]; then
            count=$(find "$dotfiles_dir/$mod" -type f | wc -l)
            pass "Módulo '$mod' encontrado ($count arquivo(s))"
        else
            fail "Módulo '$mod' NÃO encontrado"
        fi
    done
else
    fail "Pasta dotfiles-hyprland/ NÃO existe — dotfiles ausentes"
fi

# ─────────────────────────────────────────────────────────────
# TESTE 4: Estrutura Stow dos módulos (verifica .config/)
# ─────────────────────────────────────────────────────────────
section "4. ESTRUTURA GNU STOW (módulos .config/)"

# Módulos que devem ter estrutura .config/<nome>
config_modules=(hyprland waybar wofi swaync eww ghostty btop fastfetch)

for mod in "${config_modules[@]}"; do
    mod_dir="$dotfiles_dir/$mod"
    if [ ! -d "$mod_dir" ]; then
        warn "Módulo '$mod' ausente — pulando verificação Stow"
        continue
    fi
    # GNU Stow espera estrutura: modulo/.config/nome/
    if find "$mod_dir" -maxdepth 3 -name "*.conf" \
            -o -name "*.css" \
            -o -name "*.json" \
            -o -name "*.jsonc" \
            -o -name "*.lua" \
            -o -name "*.yuck" \
            -o -name "*.toml" \
            -o -name "config" 2>/dev/null | grep -q .; then
        pass "Módulo '$mod' tem arquivos de config válidos"
    else
        warn "Módulo '$mod' sem arquivos de config reconhecidos"
    fi
done

# wallpapers é especial — não vai para .config/
if [ -d "$dotfiles_dir/wallpapers" ]; then
    count=$(find "$dotfiles_dir/wallpapers" -type f | wc -l)
    pass "wallpapers/ tem $count arquivo(s) de imagem"
fi

# ─────────────────────────────────────────────────────────────
# TESTE 5: Lista de pacotes Arch
# ─────────────────────────────────────────────────────────────
section "5. LISTA DE PACOTES — ARCH (hyprland-arch.txt)"

pkg_file="$REPO_DIR/packages/hyprland-arch.txt"
if [ -f "$pkg_file" ]; then
    total_pkgs=$(grep -v "^#" "$pkg_file" | grep -v "^$" | wc -l)
    pass "Arquivo encontrado com $total_pkgs pacotes"

    # Verificar pacotes essenciais (waybar não está aqui — é instalado via build_waybar com waybar-git)
    essential=(hyprland wofi sddm pipewire wireplumber stow git ghostty)
    for pkg in "${essential[@]}"; do
        if grep -q "^$pkg$" "$pkg_file"; then
            pass "  Pacote essencial presente: $pkg"
        else
            fail "  Pacote essencial AUSENTE: $pkg"
        fi
    done

    # waybar é compilado via paru waybar-git — verificar na função build_waybar
    if grep -q 'waybar-git' "$REPO_DIR/lib/hyprland.sh"; then
        pass "  waybar-git referenciado em build_waybar() (instalado via paru)"
    else
        fail "  waybar-git NÃO encontrado em lib/hyprland.sh"
    fi

    # Verificar drivers AMD (Ryzen 5 5600GT)
    amd_pkgs=(mesa vulkan-radeon libva-mesa-driver)
    for pkg in "${amd_pkgs[@]}"; do
        if grep -q "$pkg" "$pkg_file"; then
            pass "  Driver AMD presente: $pkg"
        else
            warn "  Driver AMD não encontrado: $pkg"
        fi
    done
else
    fail "hyprland-arch.txt não encontrado"
fi

# ─────────────────────────────────────────────────────────────
# TESTE 6: Lista de pacotes Fedora
# ─────────────────────────────────────────────────────────────
section "6. LISTA DE PACOTES — FEDORA (hyprland-fedora.txt)"

pkg_file_fed="$REPO_DIR/packages/hyprland-fedora.txt"
if [ -f "$pkg_file_fed" ]; then
    total_fed=$(grep -v "^#" "$pkg_file_fed" | grep -v "^$" | wc -l)
    pass "Arquivo encontrado com $total_fed pacotes"
    essential_fed=(hyprland waybar wofi sddm pipewire wireplumber stow git ghostty)
    for pkg in "${essential_fed[@]}"; do
        if grep -q "^$pkg$" "$pkg_file_fed"; then
            pass "  Pacote essencial presente: $pkg"
        else
            warn "  Pacote '$pkg' não encontrado (pode ter nome diferente no Fedora)"
        fi
    done
else
    fail "hyprland-fedora.txt não encontrado"
fi

# ─────────────────────────────────────────────────────────────
# TESTE 7: Funções do hyprland.sh
# ─────────────────────────────────────────────────────────────
section "7. FUNÇÕES DEFINIDAS EM lib/hyprland.sh"

expected_functions=(
    "ensure_paru"
    "backup_config"
    "install_hyprland_packages_arch"
    "install_hyprland_packages_fedora"
    "build_waybar"
    "setup_sddm"
    "setup_bluetooth"
    "ensure_stow"
    "deploy_hyprland_dotfiles"
    "setup_starship"
    "hyprland_post_install_message"
    "install_hyprland_environment"
)

for fn in "${expected_functions[@]}"; do
    if grep -q "^${fn}()" "$REPO_DIR/lib/hyprland.sh"; then
        pass "Função '$fn' definida"
    else
        fail "Função '$fn' NÃO encontrada"
    fi
done

# ─────────────────────────────────────────────────────────────
# TESTE 8: Integração — hyprland.sh carregado no install.sh
# ─────────────────────────────────────────────────────────────
section "8. INTEGRAÇÃO COM install.sh"

if grep -q 'source.*lib/hyprland.sh' "$REPO_DIR/install.sh"; then
    pass "lib/hyprland.sh é carregado no install.sh"
else
    fail "lib/hyprland.sh NÃO está sendo carregado no install.sh"
fi

if grep -q 'install_hyprland_environment' "$REPO_DIR/install.sh"; then
    pass "install_hyprland_environment() é chamado no install.sh"
else
    fail "install_hyprland_environment() NÃO é chamado no install.sh"
fi

if grep -q 'select_environment' "$REPO_DIR/install.sh"; then
    pass "Menu de seleção de ambiente presente no install.sh"
else
    fail "Menu de seleção de ambiente NÃO encontrado"
fi

# ─────────────────────────────────────────────────────────────
# TESTE 9: Simulação de backup (sem escrever em ~/.config real)
# ─────────────────────────────────────────────────────────────
section "9. SIMULAÇÃO DE BACKUP"

tmp_home=$(mktemp -d)
mkdir -p "$tmp_home/.config/hypr"
echo "source = main.conf" > "$tmp_home/.config/hypr/hyprland.conf"

# Simular a lógica do backup_config()
timestamp=$(date +"%Y%m%d_%H%M%S")
backup_dest="$tmp_home/.config-backup-hyprland-$timestamp"

if cp -r "$tmp_home/.config" "$backup_dest" 2>/dev/null; then
    pass "Lógica de backup funciona (simulado em $tmp_home)"
    if [ -f "$backup_dest/hypr/hyprland.conf" ]; then
        pass "Arquivo de config preservado no backup"
    else
        fail "Arquivo de config NÃO preservado no backup"
    fi
else
    fail "Falha na simulação de backup"
fi

rm -rf "$tmp_home"

# ─────────────────────────────────────────────────────────────
# TESTE 10: Simulação GNU Stow (sem tocar em ~/.config real)
# ─────────────────────────────────────────────────────────────
section "10. SIMULAÇÃO GNU STOW"

if command -v stow &>/dev/null; then
    tmp_target=$(mktemp -d)
    tmp_stow=$(mktemp -d)

    # Criar estrutura fake igual ao módulo wofi
    mkdir -p "$tmp_stow/wofi/.config/wofi"
    echo "width=600" > "$tmp_stow/wofi/.config/wofi/config"

    if stow --dir="$tmp_stow" --target="$tmp_target" --simulate wofi 2>/dev/null; then
        pass "GNU Stow funcionando (--simulate OK)"
    else
        # stow --simulate pode não existir em versões antigas
        if stow --dir="$tmp_stow" --target="$tmp_target" wofi 2>/dev/null; then
            pass "GNU Stow funcionando (aplicação real OK)"
            [ -L "$tmp_target/.config/wofi/config" ] && pass "Symlink criado corretamente"
        else
            fail "GNU Stow falhou na simulação"
        fi
    fi

    rm -rf "$tmp_target" "$tmp_stow"
else
    warn "GNU Stow não instalado neste sistema — será instalado pelo script"
    info "  No Arch: sudo pacman -S stow"
fi

# ─────────────────────────────────────────────────────────────
# RESULTADO FINAL
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}╔═════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              RESULTADO DOS TESTES                      ║${NC}"
echo -e "${BLUE}╠═════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  ✅ Passaram : $PASS$(printf '%*s' $((43 - ${#PASS})) '')║${NC}"
echo -e "${YELLOW}║  ⚠️  Avisos  : $WARN$(printf '%*s' $((43 - ${#WARN})) '')║${NC}"
echo -e "${RED}║  ❌ Falharam : $FAIL$(printf '%*s' $((43 - ${#FAIL})) '')║${NC}"
echo -e "${BLUE}╠═════════════════════════════════════════════════════════╣${NC}"

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}║  🎉 SCRIPT PRONTO PARA USO EM ARCH LINUX!              ║${NC}"
else
    echo -e "${RED}║  ⛔ CORRIJA OS ERROS ANTES DE USAR EM PRODUÇÃO         ║${NC}"
fi

echo -e "${BLUE}╚═════════════════════════════════════════════════════════╝${NC}"
echo ""

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
