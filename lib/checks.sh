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

# ─────────────────────────────────────────────────────────────
# Relógio do sistema
#
# Data/hora errada é uma das causas mais frequentes — e mais mal
# diagnosticadas — de falha logo no início de uma instalação limpa: o pacman e
# o dnf recusam assinaturas válidas com mensagens que apontam para o pacote
# ("invalid or corrupted package", "signature is from the future"), nunca para
# o relógio. Em máquina recém-instalada, dual boot com Windows ou bateria de
# CMOS fraca isso acontece o tempo todo.
#
# Não é fatal: só avisa e tenta ligar a sincronização automática.
# ─────────────────────────────────────────────────────────────
check_system_clock() {
    if ! command -v timedatectl &>/dev/null; then
        return 0
    fi

    local synced
    synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo "")

    if [ "$synced" = "yes" ]; then
        log_success "Relógio sincronizado por NTP: OK"
        return 0
    fi

    log_warn "O relógio do sistema NÃO está sincronizado por NTP."
    log_info "  Hora atual do sistema: $(date '+%d/%m/%Y %H:%M %Z')"
    log_info "  Ativando a sincronização automática (timedatectl set-ntp true)..."
    sudo timedatectl set-ntp true &>/dev/null || true

    # A sincronização não é instantânea — dar alguns segundos antes de desistir.
    local i
    for i in $(seq 1 10); do
        sleep 1
        synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo "")
        [ "$synced" = "yes" ] && break
    done

    if [ "$synced" = "yes" ]; then
        log_success "Relógio sincronizado: $(date '+%d/%m/%Y %H:%M %Z')"
    else
        log_warn "Não foi possível sincronizar o relógio automaticamente."
        log_info "  Se a hora acima estiver errada, corrija ANTES de continuar — senão a"
        log_info "  instalação vai falhar com erros de assinatura sem relação aparente:"
        log_info "    sudo timedatectl set-time \"AAAA-MM-DD HH:MM:SS\""
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────
# Chaveiro (keyring) do pacman — Arch e derivadas
#
# Numa ISO antiga ou numa instalação mínima parada há meses, as chaves de
# assinatura dos repositórios já expiraram. O primeiro 'pacman -Syu' então
# falha inteiro — e, como install_arch_packages() é chamado com '|| log_warn'
# (de propósito, para nunca abortar antes do SDDM), a instalação SEGUIA e
# falhava em absolutamente tudo depois, sem que a causa raiz aparecesse.
# ─────────────────────────────────────────────────────────────

# Quais chaveiros esta instalação usa? Em derivadas (CachyOS, EndeavourOS,
# Manjaro) o chaveiro próprio é tão essencial quanto o do Arch: atualizar só o
# 'archlinux-keyring' deixaria os pacotes do repo da distro ainda recusados.
arch_keyring_packages() {
    local candidates=(archlinux-keyring cachyos-keyring endeavouros-keyring manjaro-keyring)
    local found=()
    local k
    for k in "${candidates[@]}"; do
        pacman -Q "$k" &>/dev/null && found+=("$k")
    done
    # Instalação sem nenhum chaveiro registrado: o do Arch é o mínimo viável.
    [ ${#found[@]} -eq 0 ] && found=(archlinux-keyring)
    printf '%s\n' "${found[@]}"
}

# Atualiza o chaveiro e, se preciso, o reconstrói localmente.
#
# ATENÇÃO ao chamar: esta função usa '-Sy' (sem 'u'), que normalmente é
# proibido neste projeto por causar partial upgrade. Atualizar o chaveiro é a
# exceção documentada pelo próprio Arch — ele precisa vir ANTES do '-Syu',
# senão o upgrade inteiro é recusado na verificação de assinatura. Por isso
# o chamador é OBRIGADO a executar um '-Syu' logo em seguida, sem instalar
# mais nada no meio, para não deixar janela de partial upgrade.
refresh_arch_keyring() {
    [ "${DISTRO:-arch}" = "fedora" ] && return 0

    local keyrings=()
    mapfile -t keyrings < <(arch_keyring_packages)

    log_info "Atualizando o chaveiro do pacman (${keyrings[*]})..."
    if sudo pacman -Sy --needed --noconfirm "${keyrings[@]}"; then
        log_success "Chaveiro do pacman atualizado."
        return 0
    fi

    log_warn "Falha ao atualizar o chaveiro — reconstruindo-o localmente."
    sudo pacman-key --init    &>/dev/null || true
    sudo pacman-key --populate &>/dev/null || true

    if sudo pacman -Sy --needed --noconfirm "${keyrings[@]}"; then
        log_success "Chaveiro reconstruído e atualizado."
        return 0
    fi

    log_warn "Não foi possível atualizar o chaveiro do pacman."
    log_info "  Se a instalação falhar com erros de assinatura, rode manualmente:"
    log_info "    sudo pacman-key --init && sudo pacman-key --populate"
    log_info "    sudo pacman -Sy --needed archlinux-keyring && sudo pacman -Syu"
    return 1
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
        if sudo pacman -S --needed --noconfirm "${missing[@]}"; then
            log_success "Pacotes base instalados."
            return 0
        fi

        # Esta é a PRIMEIRA operação do pacman em toda a instalação, e falha
        # aqui é quase sempre chaveiro vencido (ISO antiga / sistema parado há
        # meses) — não pacote inexistente. Reparar e tentar de novo evita
        # abortar a instalação inteira na etapa de verificação.
        # O retry usa '-Syu' porque refresh_arch_keyring() acabou de rodar um
        # '-Sy': completar o upgrade fecha a janela de partial upgrade.
        log_warn "Falha ao instalar os pacotes base — tentando reparar o chaveiro do pacman."
        refresh_arch_keyring || true
        if sudo pacman -Syu --needed --noconfirm "${missing[@]}"; then
            log_success "Pacotes base instalados após reparo do chaveiro."
            return 0
        fi
        log_error "Não foi possível instalar os pacotes base: ${missing[*]}"
        return 1
    fi

    log_success "Pacotes base presentes: OK"
    return 0
}

# Otimizar o dnf.conf para downloads mais rápidos (Fedora)
#
# Antes isto vivia DENTRO do 'if' de pacotes ausentes em
# check_base_packages_fedora(): num sistema que já tivesse git/curl/tar/unzip/
# fontconfig instalados, a otimização nunca era aplicada. Agora é uma função
# própria, chamada sempre.
#
# NOTA: 'defaultyes=True' foi deliberadamente REMOVIDO daqui. Ele alterava o
# padrão de TODO comando dnf do sistema, para sempre — inclusive os que o
# usuário rodasse manualmente depois, onde um 'dnf remove' distraído passaria
# a assumir "sim". O instalador já passa '-y' explicitamente onde precisa.
optimize_dnf_conf() {
    if grep -q "^max_parallel_downloads=10" /etc/dnf/dnf.conf 2>/dev/null; then
        return 0
    fi

    log_info "Otimizando dnf.conf para downloads mais rápidos..."
    sudo sh -c 'grep -q "^max_parallel_downloads" /etc/dnf/dnf.conf && sed -i "s/^max_parallel_downloads.*/max_parallel_downloads=10/" /etc/dnf/dnf.conf || echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf'
    sudo sh -c 'grep -q "^fastestmirror" /etc/dnf/dnf.conf && sed -i "s/^fastestmirror.*/fastestmirror=False/" /etc/dnf/dnf.conf || echo "fastestmirror=False" >> /etc/dnf/dnf.conf'
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

    check_not_root     || return 1
    check_internet     || return 1
    # Relógio ANTES de qualquer operação de pacote: hora errada faz o
    # gerenciador recusar assinaturas válidas e culpar o pacote.
    check_system_clock || true
    check_distro       || return 1

    # Verificações específicas por distro
    if [ "${DISTRO:-}" = "arch" ]; then
        check_base_packages_arch || return 1

        # Detectar e exportar AUR helper
        AUR_HELPER=$(detect_aur_helper)

        # Sem helper? No CachyOS o paru existe como pacote binário no repo
        # oficial — dá para instalar via pacman, sem compilar nada.
        if [ "$AUR_HELPER" = "none" ] && pacman -Si paru &>/dev/null; then
            if prompt_yes_no "Nenhum AUR helper encontrado. Instalar o 'paru' agora via pacman (repo CachyOS)?" "S"; then
                if sudo pacman -S --needed --noconfirm paru; then
                    AUR_HELPER="paru"
                    log_success "paru instalado — pacotes AUR habilitados."
                else
                    log_warn "Falha ao instalar o paru."
                fi
            fi
        fi

        export AUR_HELPER
        if [ "$AUR_HELPER" = "none" ]; then
            log_warn "Continuando sem AUR helper. Pacotes AUR serão ignorados."
        fi
    elif [ "${DISTRO:-}" = "fedora" ]; then
        # Otimizar o dnf ANTES de qualquer download, sempre — inclusive quando
        # os pacotes base já estão todos presentes.
        optimize_dnf_conf
        check_base_packages_fedora || return 1
    fi

    echo -e "${BLUE}===============================================${NC}"
    log_success "Todas as verificações passaram!"
    echo -e "${BLUE}===============================================${NC}"
    echo ""
    return 0
}
