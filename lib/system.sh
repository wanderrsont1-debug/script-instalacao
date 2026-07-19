#!/usr/bin/env bash
# Configurações de sistema pós/pré-instalação:
#   - Snapshot antes de instalar (snapper/timeshift)
#   - Otimização de mirrors (reflector, Arch)
#   - Firewall UFW
#   - Flatpak + Flathub
#   - Grupos do usuário

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ─────────────────────────────────────────────────────────────
# (6) Snapshot do sistema ANTES de instalar
# Detecta snapper (comum no CachyOS/btrfs) e cai para timeshift.
# Roda cedo no fluxo, antes das grandes instalações.
# ─────────────────────────────────────────────────────────────
create_pre_install_snapshot() {
    if ! prompt_yes_no "Deseja criar um snapshot do sistema antes de instalar (recomendado)?" "S"; then
        log_info "Snapshot pré-instalação ignorado."
        return 0
    fi

    local desc
    desc="pre-niri-install $(date +%Y-%m-%d_%H:%M)"

    # 1. snapper com config 'root' (padrão em btrfs no CachyOS)
    if command -v snapper &>/dev/null && sudo snapper -c root list &>/dev/null; then
        log_info "Criando snapshot com snapper (config 'root')..."
        if sudo snapper -c root create --description "$desc"; then
            log_success "Snapshot snapper criado: \"$desc\""
            return 0
        fi
        log_warn "Falha no snapper — tentando timeshift."
    fi

    # 2. timeshift (instala se o usuário quiser)
    if ! command -v timeshift &>/dev/null; then
        if prompt_yes_no "timeshift não está instalado. Deseja instalá-lo para criar o snapshot?" "S"; then
            if [ "${DISTRO:-arch}" = "fedora" ]; then
                sudo dnf install -y timeshift || { log_warn "Falha ao instalar timeshift — snapshot ignorado."; return 0; }
            elif pacman -Si timeshift &>/dev/null 2>&1; then
                sudo pacman -S --needed --noconfirm timeshift || { log_warn "Falha ao instalar timeshift — snapshot ignorado."; return 0; }
            elif [ "${AUR_HELPER:-none}" != "none" ]; then
                "$AUR_HELPER" -S --needed --noconfirm timeshift || { log_warn "Falha ao instalar timeshift — snapshot ignorado."; return 0; }
            else
                log_warn "timeshift indisponível (sem repo/AUR) — snapshot ignorado."
                return 0
            fi
        else
            log_info "Snapshot ignorado (nenhuma ferramenta disponível)."
            return 0
        fi
    fi

    if command -v timeshift &>/dev/null; then
        log_info "Criando snapshot com timeshift (pode demorar no modo rsync)..."
        if sudo timeshift --create --comments "$desc" --scripted; then
            log_success "Snapshot timeshift criado."
        else
            log_warn "Falha ao criar snapshot com timeshift."
            log_info "  → O timeshift precisa estar configurado (destino/tipo). Configure-o e rode novamente se quiser o snapshot."
        fi
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────
# (2) Otimização de mirrors com reflector (Arch/CachyOS)
# Roda ANTES das instalações grandes para acelerar downloads.
# ─────────────────────────────────────────────────────────────
optimize_mirrors_arch() {
    [ "${DISTRO:-arch}" = "fedora" ] && return 0

    if ! prompt_yes_no "Deseja otimizar a lista de mirrors do pacman com o reflector (downloads mais rápidos)?" "S"; then
        log_info "Otimização de mirrors ignorada."
        return 0
    fi

    if ! command -v reflector &>/dev/null; then
        log_info "Instalando reflector..."
        sudo pacman -S --needed --noconfirm reflector || {
            log_warn "Falha ao instalar reflector — mantendo mirrors atuais."
            return 0
        }
    fi

    log_info "Gerando melhores mirrors (isto pode levar alguns segundos)..."
    # Backup do mirrorlist antes de sobrescrever
    sudo cp -a /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak 2>/dev/null || true
    if sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist; then
        log_success "Mirrors otimizados (backup em /etc/pacman.d/mirrorlist.bak)."
    else
        log_warn "Falha ao rodar reflector — restaurando backup do mirrorlist."
        sudo cp -a /etc/pacman.d/mirrorlist.bak /etc/pacman.d/mirrorlist 2>/dev/null || true
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────
# (1) Firewall UFW — política padrão + habilitar
# ─────────────────────────────────────────────────────────────
configure_firewall() {
    if ! command -v ufw &>/dev/null; then
        log_info "ufw não instalado — pulando configuração de firewall."
        return 0
    fi

    if ! prompt_yes_no "Deseja habilitar o firewall UFW com política segura (nega entrada, permite saída)?" "S"; then
        log_info "Configuração do firewall ignorada."
        return 0
    fi

    log_info "Configurando UFW (deny incoming / allow outgoing)..."
    sudo ufw default deny incoming  >/dev/null 2>&1 || true
    sudo ufw default allow outgoing >/dev/null 2>&1 || true
    # --force evita o prompt interativo do ufw
    sudo ufw --force enable || log_warn "Falha ao habilitar o UFW."

    # Habilitar o serviço para persistir após reboot
    if systemctl list-unit-files 2>/dev/null | grep -q '^ufw.service'; then
        sudo systemctl enable ufw.service &>/dev/null || true
    fi

    # LC_ALL=C é obrigatório: a saída do ufw é traduzida por gettext. Num sistema
    # em pt_BR o status sai como "Status: ativo", o grep por 'Status: active'
    # nunca casava e o script avisava que o UFW podia estar inativo — mesmo com
    # o firewall ativo e habilitado no boot (falso positivo visto no log).
    if sudo LC_ALL=C ufw status 2>/dev/null | grep -qi 'Status: active'; then
        log_success "UFW ativo e habilitado no boot."
    else
        log_warn "UFW pode não estar ativo — verifique com: sudo ufw status"
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────
# (3) Flatpak + repositório Flathub
# ─────────────────────────────────────────────────────────────
setup_flatpak() {
    if ! command -v flatpak &>/dev/null; then
        log_info "flatpak não instalado — pulando configuração do Flathub."
        return 0
    fi

    log_info "Adicionando o repositório Flathub (se ainda não existir)..."
    if sudo flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo; then
        log_success "Flathub configurado. (Instale apps com: flatpak install flathub <app>)"
    else
        log_warn "Falha ao adicionar o Flathub."
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────
# (4) Grupos do usuário — acesso a hardware e sudo
# Adiciona apenas aos grupos que existem no sistema.
# ─────────────────────────────────────────────────────────────
configure_user_groups() {
    local real_user
    real_user=$(detect_user)

    local wanted=(video input wheel storage audio network)
    local to_add=()

    for grp in "${wanted[@]}"; do
        # grupo existe no sistema?
        getent group "$grp" &>/dev/null || continue
        # usuário já está no grupo?
        if id -nG "$real_user" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp"; then
            continue
        fi
        to_add+=("$grp")
    done

    if [ ${#to_add[@]} -eq 0 ]; then
        log_info "Usuário '$real_user' já pertence aos grupos necessários."
        return 0
    fi

    log_info "Adicionando '$real_user' aos grupos: ${to_add[*]}"
    local joined
    joined=$(IFS=,; echo "${to_add[*]}")
    if sudo usermod -aG "$joined" "$real_user"; then
        log_success "Grupos adicionados. (Efetivo após novo login.)"
    else
        log_warn "Falha ao adicionar grupos ao usuário $real_user."
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────
# Agregador — configurações de sistema PÓS-instalação
# ─────────────────────────────────────────────────────────────
configure_system_post() {
    echo ""
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${GREEN}      Configurações Finais do Sistema          ${NC}"
    echo -e "${BLUE}===============================================${NC}"
    configure_user_groups
    setup_flatpak
    configure_firewall
}
