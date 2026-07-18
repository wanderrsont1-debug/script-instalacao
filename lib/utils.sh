#!/usr/bin/env bash
# Utilitários gerais do instalador

# Cores para mensagens
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Funções de logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERRO]${NC} $1" >&2
}

# Prompt de Sim ou Não
prompt_yes_no() {
    local prompt_msg="$1"
    local default_val="$2" # "S" ou "N"
    local reply

    if [ "$default_val" = "S" ]; then
        prompt_msg="$prompt_msg [S/n]: "
    else
        prompt_msg="$prompt_msg [s/N]: "
    fi

    read -p "$prompt_msg" reply
    reply=${reply:-$default_val}

    if [[ "$reply" =~ ^[SsYy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────
# Escolha do Desktop Shell: DankMaterialShell (DMS) ou Noctalia (beta)
# Exporta SHELL_CHOICE=dms|noctalia (padrão: dms).
# ─────────────────────────────────────────────────────────────
select_shell() {
    echo ""
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${YELLOW}          Escolha do Desktop Shell${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo -e "  ${GREEN}1${NC}) DankMaterialShell (DMS)  — estável, padrão do projeto"
    echo -e "  ${GREEN}2${NC}) Noctalia Shell (BETA 5.x) — via repo cachyos ou AUR (noctalia-git)"
    echo ""
    local reply
    read -p "Sua escolha [1]: " reply
    reply=${reply:-1}

    case "$reply" in
        2|noctalia|Noctalia|n|N)
            export SHELL_CHOICE="noctalia"
            log_info "Shell selecionado: Noctalia Shell (beta)."
            ;;
        *)
            export SHELL_CHOICE="dms"
            log_info "Shell selecionado: DankMaterialShell (DMS)."
            ;;
    esac
}

# Detectar o usuário real (mesmo quando executado via sudo)
# Inspirado no donarch — garante que dotfiles sejam do usuário correto
detect_user() {
    if [ -n "${SUDO_USER:-}" ]; then
        echo "$SUDO_USER"
    else
        echo "$USER"
    fi
}

# Obter o diretório home do usuário real
get_user_home() {
    local user
    user=$(detect_user)
    getent passwd "$user" | cut -d: -f6
}

# Fazer backup completo de ~/.config com timestamp antes de implantar dotfiles
# Inspirado no donarch — evita perda de configurações existentes
# Mantém apenas os 3 backups mais recentes para não acumular disco
# indefinidamente, já que reinstalar (rodar install.sh de novo) é o
# fluxo de atualização recomendado deste projeto.
backup_existing_configs() {
    local user_home
    user_home=$(get_user_home)
    local config_dir="$user_home/.config"
    local backup_dir="$user_home/.config.backup-$(date +%Y%m%d_%H%M%S)"
    local max_backups=3

    if [ -d "$config_dir" ]; then
        log_info "Criando backup completo de ~/.config em: $backup_dir"
        cp -a "$config_dir" "$backup_dir"
        log_success "Backup criado em: $backup_dir"

        # Remover backups antigos além do limite (mantém os mais recentes)
        local old_backups
        mapfile -t old_backups < <(find "$user_home" -maxdepth 1 -type d -name '.config.backup-*' | sort -r | tail -n +$((max_backups + 1)))
        if [ "${#old_backups[@]}" -gt 0 ]; then
            log_info "Removendo ${#old_backups[@]} backup(s) antigo(s) de ~/.config (mantendo os $max_backups mais recentes)..."
            for old in "${old_backups[@]}"; do
                rm -rf "$old"
            done
        fi
        return 0
    else
        log_warn "Diretório ~/.config não encontrado, backup ignorado."
        return 0
    fi
}

# Verificação de conectividade com a internet
# Testa contra múltiplos alvos para evitar falso negativo por bloqueio de um servidor.
# Em ambientes mínimos/TTY o binário 'curl' pode não estar presente ainda (ele é
# instalado só depois, em check_base_packages_*), então há fallback para ping e,
# por último, para o /dev/tcp do próprio bash — evitando falso "sem internet".
check_internet() {
    log_info "Verificando conectividade com a internet..."
    local targets=("archlinux.org" "fedoraproject.org" "1.1.1.1")

    for target in "${targets[@]}"; do
        # 1. curl (se disponível)
        if command -v curl &>/dev/null; then
            if curl -s --max-time 5 --head "https://${target}" > /dev/null 2>&1; then
                log_success "Conexão com a internet confirmada."
                return 0
            fi
        fi
        # 2. ping (fallback quando curl não está instalado)
        if command -v ping &>/dev/null; then
            if ping -c 1 -W 3 "$target" &>/dev/null; then
                log_success "Conexão com a internet confirmada (ping)."
                return 0
            fi
        fi
        # 3. /dev/tcp do bash (último recurso, sem depender de binários externos)
        if timeout 3 bash -c "exec 3<>/dev/tcp/${target}/443" &>/dev/null; then
            log_success "Conexão com a internet confirmada (tcp)."
            return 0
        fi
    done

    log_error "Sem conexão com a internet. Verifique sua rede antes de continuar."
    log_error "Em ambientes mínimos sem desktop, execute: sudo systemctl start NetworkManager"
    return 1
}
