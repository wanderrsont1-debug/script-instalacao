#!/usr/bin/env bash
# Verificações de sistema pré-instalação
# Inspirado no donarch (GitLab), adaptado para suportar Arch + Fedora

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Verificar se não está rodando como root
check_not_root() {
    if [ "$EUID" -eq 0 ]; then
        log_error "Não execute este script como root (sudo)."
        log_info "Rode como usuário normal — o sudo será solicitado internamente quando necessário."
        return 1
    fi
    log_success "Verificação de root: OK"
    return 0
}

# Verificar distribuição suportada e exportar DISTRO
check_distro() {
    if [ ! -f /etc/os-release ]; then
        log_error "Arquivo /etc/os-release não encontrado. Sistema não suportado."
        return 1
    fi

    . /etc/os-release
    local os="$ID"
    local like="${ID_LIKE:-}"

    if [[ "$os" == "fedora" ]]; then
        log_success "Distribuição detectada: Fedora ($VERSION_ID)"
        export DISTRO="fedora"
    elif [[ "$os" == "arch" || "$os" == "cachyos" || "$like" == *"arch"* ]]; then
        log_success "Distribuição detectada: Arch Linux / CachyOS ($os)"
        export DISTRO="arch"
    else
        log_warn "Distribuição não suportada automaticamente: $os"
        if prompt_yes_no "Deseja forçar o modo Arch Linux?" "N"; then
            export DISTRO="arch"
        else
            log_error "Instalação abortada."
            return 1
        fi
    fi
    return 0
}

# Detectar AUR helper disponível (paru, yay, pikaur, pakku)
# IMPORTANTE: esta função "retorna" o nome do helper via stdout (capturado por
# AUR_HELPER=$(detect_aur_helper)). Por isso TODO log aqui vai para o stderr (>&2),
# senão o texto do log seria capturado junto e poluiria o valor de AUR_HELPER.
detect_aur_helper() {
    local helpers=("paru" "yay" "pikaur" "pakku")
    for helper in "${helpers[@]}"; do
        if command -v "$helper" &>/dev/null; then
            log_success "AUR helper detectado: $helper" >&2
            echo "$helper"
            return 0
        fi
    done

    log_warn "Nenhum AUR helper encontrado (paru, yay, pikaur, pakku)." >&2
    log_info "Alguns pacotes AUR não poderão ser instalados automaticamente." >&2
    log_info "Para instalar o paru (recomendado), execute:" >&2
    log_info "  sudo pacman -S --needed base-devel git" >&2
    log_info "  git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si" >&2
    echo "none"
    return 0
}

# Verificar pacotes base necessários (Arch)
check_base_packages_arch() {
    local missing=()
    local required=("git" "curl")

    for pkg in "${required[@]}"; do
        if ! pacman -Q "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    # base-devel é um grupo, não um pacote — pacman -Q falha sempre nele.
    # Verificar 'make' como proxy (membro essencial do grupo base-devel).
    if ! pacman -Q make &>/dev/null; then
        missing+=("base-devel")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "Pacotes base ausentes: ${missing[*]}"
        log_info "Instalando pacotes base necessários..."
        sudo pacman -S --needed --noconfirm "${missing[@]}"
        return $?
    fi

    log_success "Pacotes base presentes: OK"
    return 0
}

# Verificar pacotes base necessários (Fedora)
check_base_packages_fedora() {
    local missing=()
    local required=("git" "curl" "tar" "unzip" "fontconfig")

    for pkg in "${required[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "Pacotes base ausentes: ${missing[*]}"
        log_info "Instalando pacotes base necessários..."
        
        # Otimizar DNF globalmente antes da primeira instalação se não estiver otimizado
        if ! grep -q "^max_parallel_downloads=10" /etc/dnf/dnf.conf 2>/dev/null; then
            log_info "Otimizando dnf.conf para downloads mais rápidos..."
            sudo sh -c 'grep -q "^max_parallel_downloads" /etc/dnf/dnf.conf && sed -i "s/^max_parallel_downloads.*/max_parallel_downloads=10/" /etc/dnf/dnf.conf || echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf'
            sudo sh -c 'grep -q "^fastestmirror" /etc/dnf/dnf.conf && sed -i "s/^fastestmirror.*/fastestmirror=False/" /etc/dnf/dnf.conf || echo "fastestmirror=False" >> /etc/dnf/dnf.conf'
            sudo sh -c 'grep -q "^defaultyes" /etc/dnf/dnf.conf || echo "defaultyes=True" >> /etc/dnf/dnf.conf'
        fi

        sudo dnf install -y "${missing[@]}"
        return $?
    fi

    log_success "Pacotes base presentes: OK"
    return 0
}

# Executar todas as verificações em sequência
run_all_checks() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${GREEN}      Verificações de Sistema                  ${NC}"
    echo -e "${BLUE}===============================================${NC}"

    check_not_root   || return 1
    check_internet   || return 1
    check_distro     || return 1

    # Verificações específicas por distro
    if [ "${DISTRO:-}" = "arch" ]; then
        check_base_packages_arch || return 1

        # Detectar e exportar AUR helper
        AUR_HELPER=$(detect_aur_helper)
        export AUR_HELPER
        if [ "$AUR_HELPER" = "none" ]; then
            log_warn "Continuando sem AUR helper. Pacotes AUR serão ignorados."
        fi
    elif [ "${DISTRO:-}" = "fedora" ]; then
        check_base_packages_fedora || return 1
    fi

    echo -e "${BLUE}===============================================${NC}"
    log_success "Todas as verificações passaram!"
    echo -e "${BLUE}===============================================${NC}"
    echo ""
    return 0
}
