#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# Instalador Unificado de Ambiente — Arch Linux / Fedora
# Ambientes suportados:
#   - Niri (DankMaterialShell)
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

# ─────────────────────────────────────────────────────────────
# Tela de boas-vindas
# ─────────────────────────────────────────────────────────────
show_welcome() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       Instalador Unificado de Ambiente           ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  Suporta: Arch Linux / CachyOS / Fedora          ║${NC}"
    echo -e "${CYAN}║  Ambiente: Niri (DMS)                            ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    if ! prompt_yes_no "Deseja continuar com a instalação?" "S"; then
        log_info "Instalação cancelada pelo usuário."
        exit 0
    fi
    echo ""
}



# ─────────────────────────────────────────────────────────────
# MAIN — Ponto de entrada
# ─────────────────────────────────────────────────────────────
main() {
    # Verificações iniciais
    run_all_checks || exit 1

    # Boas-vindas
    show_welcome

    # ── Instalar Niri ────────────────────────────────────────
    # A instalação do Niri usa as funções já existentes no repo
    # (packages.sh, dotfiles.sh, greeter.sh)
    log_info "Iniciando instalação do ambiente Niri..."

    if [ "${DISTRO}" = "arch" ]; then
        install_arch_packages "$REPO_DIR" || true
    elif [ "${DISTRO}" = "fedora" ]; then
        install_fedora_packages || true
    fi

    # Aplicar dotfiles Niri
    if [ -d "$REPO_DIR/dotfiles" ]; then
        backup_existing_configs
        deploy_dotfiles "$REPO_DIR"
    fi

    # Configurar greeter/DM
    if declare -f setup_greeter &>/dev/null; then
        setup_greeter
    fi

    log_success "Ambiente Niri instalado."

    # Executar verificações finais de integridade do ambiente
    if declare -f verify_niri_environment &>/dev/null; then
        verify_niri_environment "$REPO_DIR" || log_warn "Problemas detectados no ambiente Niri."
    fi
    if declare -f verify_display_manager &>/dev/null; then
        verify_display_manager "$REPO_DIR" || log_warn "Problemas detectados no Display Manager."
    fi

    echo ""
    log_success "Instalação concluída! Reinicie o sistema para aplicar as mudanças."
    echo ""
}

main "$@"
