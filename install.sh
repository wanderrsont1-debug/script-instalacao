#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# Instalador Unificado de Ambiente — Arch Linux / Fedora
# Ambientes suportados:
#   - Niri (DankMaterialShell)
#   - Hyprland (Jules3182/dotfiles — Lua 0.55+)
#
# Melhorias baseadas no donarch (GitLab):
#   - checks.sh dedicado (detecção de distro, AUR helper, pacotes base)
#   - Backup automático de ~/.config antes dos dotfiles
#   - Seleção interativa de apps opcionais
#   - detect_user() para suporte correto a sudo
# ═══════════════════════════════════════════════════════════════

set -e          # Interrompe imediatamente se qualquer comando falhar
set -o pipefail # Propaga falhas em pipes

# Obter diretório do repositório
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source das bibliotecas modulares
source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/checks.sh"
source "$REPO_DIR/lib/packages.sh"
source "$REPO_DIR/lib/dotfiles.sh"
source "$REPO_DIR/lib/greeter.sh"
source "$REPO_DIR/lib/hyprland.sh"

# ─────────────────────────────────────────────────────────────
# Tela de boas-vindas
# ─────────────────────────────────────────────────────────────
show_welcome() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       Instalador Unificado de Ambiente           ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  Suporta: Arch Linux / CachyOS / Fedora          ║${NC}"
    echo -e "${CYAN}║  Ambientes: Niri (DMS) | Hyprland (Lua 0.55+)    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    if ! prompt_yes_no "Deseja continuar com a instalação?" "S"; then
        log_info "Instalação cancelada pelo usuário."
        exit 0
    fi
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Seleção do ambiente a instalar
# ─────────────────────────────────────────────────────────────
select_environment() {
    echo ""
    echo -e "${BLUE}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│        Selecione o ambiente a instalar:          │${NC}"
    echo -e "${BLUE}├──────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│  1) Niri   — DankMaterialShell (dms-shell)       │${NC}"
    echo -e "${CYAN}│  2) Hyprland — Jules3182/dotfiles (Lua 0.55+)    │${NC}"
    echo -e "${CYAN}│  3) Ambos  — instalar Niri e Hyprland            │${NC}"
    echo -e "${CYAN}│  0) Sair                                         │${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────┘${NC}"
    echo ""

    local choice
    read -rp "  Digite sua escolha [0-3]: " choice

    case "$choice" in
        1)
            export INSTALL_ENV="niri"
            log_info "Ambiente selecionado: Niri"
            ;;
        2)
            export INSTALL_ENV="hyprland"
            log_info "Ambiente selecionado: Hyprland"
            ;;
        3)
            export INSTALL_ENV="both"
            log_info "Ambientes selecionados: Niri + Hyprland"
            ;;
        0)
            log_info "Instalação cancelada pelo usuário."
            exit 0
            ;;
        *)
            log_warn "Opção inválida. Selecionando Hyprland como padrão."
            export INSTALL_ENV="hyprland"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────
# Seleção do Display Manager (para Niri)
# ─────────────────────────────────────────────────────────────
select_display_manager() {
    echo ""
    echo -e "${BLUE}Selecione o Display Manager para o ambiente Niri:${NC}"
    echo -e "  ${CYAN}1)${NC} SDDM (Silent)"
    echo -e "  ${CYAN}2)${NC} greetd + tuigreet"
    echo ""

    local dm_choice
    read -rp "  Digite sua escolha [1-2]: " dm_choice

    case "$dm_choice" in
        1) export DM_CHOICE="sddm" ;;
        2) export DM_CHOICE="greetd" ;;
        *)
            log_warn "Opção inválida. Usando SDDM como padrão."
            export DM_CHOICE="sddm"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────
# MAIN — Ponto de entrada
# ─────────────────────────────────────────────────────────────
main() {
    # Verificações iniciais
    check_not_root || exit 1
    check_distro   || exit 1

    # Boas-vindas
    show_welcome

    # Selecionar ambiente
    select_environment

    # ── Instalar Niri ────────────────────────────────────────
    if [[ "$INSTALL_ENV" == "niri" || "$INSTALL_ENV" == "both" ]]; then
        select_display_manager
        # A instalação do Niri usa as funções já existentes no repo
        # (packages.sh, dotfiles.sh, greeter.sh)
        log_info "Iniciando instalação do ambiente Niri..."

        if [ "${DISTRO}" = "arch" ]; then
            detect_aur_helper || log_warn "AUR helper não encontrado — pacotes AUR serão ignorados."
            install_package_list "$REPO_DIR/packages/arch-base.txt" "pacotes base Arch" || true
        elif [ "${DISTRO}" = "fedora" ]; then
            setup_fedora_repos "$DM_CHOICE"
            install_package_list "$REPO_DIR/packages/fedora-base.txt" "pacotes base Fedora" || true
        fi

        # Aplicar dotfiles Niri
        if [ -d "$REPO_DIR/dotfiles" ]; then
            deploy_dotfiles "$REPO_DIR/dotfiles"
        fi

        # Configurar greeter/DM
        if declare -f setup_greeter &>/dev/null; then
            setup_greeter "$DM_CHOICE"
        fi

        log_success "Ambiente Niri instalado."
    fi

    # ── Instalar Hyprland ────────────────────────────────────
    if [[ "$INSTALL_ENV" == "hyprland" || "$INSTALL_ENV" == "both" ]]; then
        install_hyprland_environment
    fi

    echo ""
    log_success "Instalação concluída! Reinicie o sistema para aplicar as mudanças."
    echo ""
}

main "$@"
