#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# lib/hyprland.sh — Módulo de instalação do ambiente Hyprland
# Dotfiles: Jules3182/dotfiles (Hyprland 0.55+ com Lua)
# Suporte: Arch Linux / derivados | Fedora / derivados
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# URL do repositório dos dotfiles
readonly HYPRLAND_DOTFILES_REPO="https://github.com/Jules3182/dotfiles.git"
readonly HYPRLAND_DOTFILES_DIR="$HOME/.dotfiles-hyprland"

# Diretório de pacotes (relativo à raiz do repo)
readonly PACKAGES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/packages"

# ─────────────────────────────────────────────────────────────
# PARU — Verificar e instalar se necessário (Arch apenas)
# ─────────────────────────────────────────────────────────────
ensure_paru() {
    if command -v paru &>/dev/null; then
        log_success "paru já está instalado: $(paru --version | head -1)"
        return 0
    fi

    log_info "paru não encontrado. Instalando..."

    # Verificar dependências de build
    sudo pacman -S --needed --noconfirm base-devel git || {
        log_error "Falha ao instalar dependências base para o paru."
        return 1
    }

    local tmp_dir
    tmp_dir=$(mktemp -d)

    git clone https://aur.archlinux.org/paru.git "$tmp_dir/paru" || {
        log_error "Falha ao clonar o repositório do paru."
        rm -rf "$tmp_dir"
        return 1
    }

    (
        cd "$tmp_dir/paru"
        makepkg -si --noconfirm
    ) || {
        log_error "Falha ao compilar/instalar o paru."
        rm -rf "$tmp_dir"
        return 1
    }

    rm -rf "$tmp_dir"
    log_success "paru instalado com sucesso!"
}

# ─────────────────────────────────────────────────────────────
# BACKUP — Salvar ~/.config antes de qualquer alteração
# ─────────────────────────────────────────────────────────────
backup_config() {
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_dir="$HOME/.config-backup-hyprland-$timestamp"

    if [ -d "$HOME/.config" ]; then
        log_info "Fazendo backup de ~/.config em $backup_dir ..."
        cp -r "$HOME/.config" "$backup_dir" || {
            log_error "Falha ao criar backup de ~/.config."
            return 1
        }
        log_success "Backup criado: $backup_dir"
    else
        log_info "~/.config não encontrado — nenhum backup necessário."
    fi
}

# ─────────────────────────────────────────────────────────────
# PACOTES ARCH — Instalar via pacman + paru
# ─────────────────────────────────────────────────────────────
install_hyprland_packages_arch() {
    local pkg_file="$PACKAGES_DIR/hyprland-arch.txt"

    if [ ! -f "$pkg_file" ]; then
        log_error "Arquivo de pacotes não encontrado: $pkg_file"
        return 1
    fi

    log_info "Atualizando sistema antes da instalação..."
    sudo pacman -Syu --noconfirm || log_warn "Atualização com avisos — continuando..."

    local official=()
    local aur=()

    while IFS= read -r line; do
        # Ignorar linhas em branco e comentários
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        # Verificar se é pacote oficial ou AUR
        if pacman -Si "$line" &>/dev/null 2>&1; then
            official+=("$line")
        else
            aur+=("$line")
        fi
    done < "$pkg_file"

    # Instalar pacotes oficiais
    if [ ${#official[@]} -gt 0 ]; then
        log_info "Instalando ${#official[@]} pacotes oficiais via pacman..."
        sudo pacman -S --needed --noconfirm "${official[@]}" || {
            log_error "Falha ao instalar pacotes oficiais."
            return 1
        }
        log_success "Pacotes oficiais instalados."
    fi

    # Instalar pacotes AUR com paru
    if [ ${#aur[@]} -gt 0 ]; then
        log_info "Instalando ${#aur[@]} pacotes AUR via paru..."
        local failed=()
        for pkg in "${aur[@]}"; do
            log_info "  AUR → $pkg"
            if ! paru -S --needed --noconfirm "$pkg"; then
                log_warn "  Falha: $pkg"
                failed+=("$pkg")
            else
                log_success "  ✓ $pkg"
            fi
        done
        if [ ${#failed[@]} -gt 0 ]; then
            log_warn "Pacotes AUR que falharam: ${failed[*]}"
            log_warn "Instalação continuando — algumas funcionalidades podem estar ausentes."
        fi
    fi

    log_success "Pacotes Hyprland (Arch) instalados."
}

# ─────────────────────────────────────────────────────────────
# PACOTES FEDORA — Instalar via dnf + COPR
# ─────────────────────────────────────────────────────────────
install_hyprland_packages_fedora() {
    local pkg_file="$PACKAGES_DIR/hyprland-fedora.txt"

    if [ ! -f "$pkg_file" ]; then
        log_error "Arquivo de pacotes não encontrado: $pkg_file"
        return 1
    fi

    log_info "Adicionando repositório COPR solopasha/hyprland..."
    sudo dnf copr enable solopasha/hyprland -y || {
        log_warn "Falha ao adicionar COPR solopasha/hyprland. O Hyprland pode não estar disponível."
    }

    log_info "Atualizando sistema..."
    sudo dnf update -y || log_warn "Atualização com avisos — continuando..."

    local packages=()
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        packages+=("$line")
    done < "$pkg_file"

    if [ ${#packages[@]} -gt 0 ]; then
        log_info "Instalando ${#packages[@]} pacotes via dnf..."
        sudo dnf install -y "${packages[@]}" || {
            log_error "Falha ao instalar pacotes Fedora."
            return 1
        }
        log_success "Pacotes Hyprland (Fedora) instalados."
    fi
}

# ─────────────────────────────────────────────────────────────
# WAYBAR — Compilar da source (Arch) ou instalar via dnf (Fedora)
# ─────────────────────────────────────────────────────────────
build_waybar() {
    if [ "${DISTRO:-}" = "arch" ]; then
        log_info "Instalando waybar-git do AUR via paru (compilado da source)..."
        log_warn "Isso pode demorar alguns minutos — por favor aguarde."

        # Remover waybar oficial caso esteja instalado
        if pacman -Q waybar &>/dev/null 2>&1; then
            log_info "Removendo waybar oficial para instalar waybar-git..."
            sudo pacman -R --noconfirm waybar || true
        fi

        paru -S --needed --noconfirm waybar-git || {
            log_error "Falha ao compilar/instalar waybar-git."
            log_warn "Tentando instalar waybar oficial como fallback..."
            sudo pacman -S --needed --noconfirm waybar || true
        }

        log_success "waybar-git instalado."

    elif [ "${DISTRO:-}" = "fedora" ]; then
        log_info "Instalando waybar via dnf (Fedora)..."
        sudo dnf install -y waybar || log_warn "Falha ao instalar waybar no Fedora."
        log_success "waybar instalado."
    fi
}

# ─────────────────────────────────────────────────────────────
# SDDM — Instalar e habilitar como Display Manager
# ─────────────────────────────────────────────────────────────
setup_sddm() {
    log_info "Configurando SDDM como Display Manager..."

    if [ "${DISTRO:-}" = "arch" ]; then
        sudo pacman -S --needed --noconfirm sddm
    elif [ "${DISTRO:-}" = "fedora" ]; then
        sudo dnf install -y sddm
    fi

    # Habilitar o serviço SDDM
    sudo systemctl enable sddm.service || {
        log_warn "Não foi possível habilitar sddm.service automaticamente."
        log_info "Execute manualmente: sudo systemctl enable sddm"
    }

    log_success "SDDM instalado e habilitado."
}

# ─────────────────────────────────────────────────────────────
# BLUETOOTH — Habilitar serviço
# ─────────────────────────────────────────────────────────────
setup_bluetooth() {
    log_info "Habilitando serviço Bluetooth..."
    sudo systemctl enable --now bluetooth.service 2>/dev/null || \
        log_warn "Serviço bluetooth não encontrado — verifique se bluez está instalado."
    log_success "Bluetooth habilitado."
}

# ─────────────────────────────────────────────────────────────
# GNU STOW — Instalar se necessário
# ─────────────────────────────────────────────────────────────
ensure_stow() {
    if command -v stow &>/dev/null; then
        log_success "GNU Stow já está instalado."
        return 0
    fi

    log_info "Instalando GNU Stow..."
    if [ "${DISTRO:-}" = "arch" ]; then
        sudo pacman -S --needed --noconfirm stow
    elif [ "${DISTRO:-}" = "fedora" ]; then
        sudo dnf install -y stow
    fi

    log_success "GNU Stow instalado."
}

# ─────────────────────────────────────────────────────────────
# DOTFILES — Clonar e aplicar com GNU Stow
# ─────────────────────────────────────────────────────────────
deploy_hyprland_dotfiles() {
    ensure_stow || return 1

    log_info "Clonando dotfiles Hyprland de $HYPRLAND_DOTFILES_REPO ..."

    if [ -d "$HYPRLAND_DOTFILES_DIR" ]; then
        log_warn "Diretório $HYPRLAND_DOTFILES_DIR já existe."
        if prompt_yes_no "Deseja atualizar (git pull) os dotfiles existentes?" "S"; then
            git -C "$HYPRLAND_DOTFILES_DIR" pull || {
                log_error "Falha ao atualizar os dotfiles."
                return 1
            }
        else
            log_info "Usando dotfiles existentes."
        fi
    else
        git clone "$HYPRLAND_DOTFILES_REPO" "$HYPRLAND_DOTFILES_DIR" || {
            log_error "Falha ao clonar os dotfiles. Verifique sua conexão com a internet."
            return 1
        }
    fi

    log_success "Dotfiles clonados em: $HYPRLAND_DOTFILES_DIR"

    # Aplicar cada módulo de dotfiles com GNU Stow
    log_info "Aplicando dotfiles com GNU Stow..."

    local stow_modules=(
        "hyprland"
        "waybar"
        "wofi"
        "swaync"
        "eww"
        "ghostty"
        "btop"
        "fastfetch"
    )

    local failed_modules=()

    for module in "${stow_modules[@]}"; do
        local module_dir="$HYPRLAND_DOTFILES_DIR/$module"
        if [ -d "$module_dir" ]; then
            log_info "  Stow → $module"
            if stow --dir="$HYPRLAND_DOTFILES_DIR" --target="$HOME" "$module" 2>/dev/null; then
                log_success "  ✓ $module aplicado"
            else
                # Tentar com --adopt para resolver conflitos existentes
                log_warn "  Conflito em $module — tentando com --restow..."
                stow --dir="$HYPRLAND_DOTFILES_DIR" --target="$HOME" --restow "$module" 2>/dev/null \
                    || failed_modules+=("$module")
            fi
        else
            log_warn "  Módulo não encontrado: $module (ignorado)"
        fi
    done

    if [ ${#failed_modules[@]} -gt 0 ]; then
        log_warn "Módulos com falha no Stow: ${failed_modules[*]}"
        log_warn "Aplique manualmente: cd $HYPRLAND_DOTFILES_DIR && stow <módulo>"
    else
        log_success "Todos os dotfiles aplicados com sucesso!"
    fi
}

# ─────────────────────────────────────────────────────────────
# STARSHIP — Configurar prompt do terminal
# ─────────────────────────────────────────────────────────────
setup_starship() {
    if ! command -v starship &>/dev/null; then
        log_info "Instalando Starship..."
        if [ "${DISTRO:-}" = "arch" ]; then
            sudo pacman -S --needed --noconfirm starship
        elif [ "${DISTRO:-}" = "fedora" ]; then
            sudo dnf install -y starship
        fi
    fi

    # Adicionar ao bashrc/zshrc se ainda não estiver
    local shell_rc="$HOME/.bashrc"
    if [ -n "${SHELL:-}" ] && [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    fi

    if ! grep -q 'starship init' "$shell_rc" 2>/dev/null; then
        echo '' >> "$shell_rc"
        echo '# Starship prompt' >> "$shell_rc"
        echo 'eval "$(starship init bash)"' >> "$shell_rc"
        log_success "Starship configurado em $shell_rc"
    else
        log_info "Starship já configurado em $shell_rc"
    fi
}

# ─────────────────────────────────────────────────────────────
# MENSAGEM FINAL
# ─────────────────────────────────────────────────────────────
hyprland_post_install_message() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        ✅  Ambiente Hyprland instalado com sucesso!      ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  Dotfiles aplicados de: Jules3182/dotfiles               ║${NC}"
    echo -e "${CYAN}║  Localização local:  ~/.dotfiles-hyprland                ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║  Próximos passos:                                        ║${NC}"
    echo -e "${YELLOW}║  1. Reinicie o sistema para carregar o SDDM              ║${NC}"
    echo -e "${YELLOW}║  2. Selecione 'Hyprland' na tela de login                ║${NC}"
    echo -e "${YELLOW}║  3. Atalho inicial: SUPER + Q → abre o Ghostty           ║${NC}"
    echo -e "${YELLOW}║  4. Atalho launcher: SUPER + SPACE → abre o Wofi         ║${NC}"
    echo -e "${YELLOW}║  5. Para atualizar dotfiles: cd ~/.dotfiles-hyprland     ║${NC}"
    echo -e "${YELLOW}║     e depois: git pull                                   ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  Backup de ~/.config salvo com timestamp em ~/            ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# INSTALAÇÃO COMPLETA DO AMBIENTE HYPRLAND
# Função principal — chamada pelo install.sh
# ─────────────────────────────────────────────────────────────
install_hyprland_environment() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        🪟  Instalação do Ambiente Hyprland               ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  Dotfiles: Jules3182/dotfiles (Hyprland 0.55+ Lua)       ║${NC}"
    echo -e "${CYAN}║  Distro detectada: ${DISTRO:-desconhecida}$(printf '%*s' $((36 - ${#DISTRO:-desconhecida})) '')║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if ! prompt_yes_no "Deseja instalar o ambiente Hyprland com estes dotfiles?" "S"; then
        log_info "Instalação do Hyprland cancelada."
        return 0
    fi

    # ── Etapa 1: Backup ──────────────────────────────────────
    log_info "[ 1/8 ] Fazendo backup de ~/.config..."
    backup_config || return 1

    # ── Etapa 2: AUR helper (Arch apenas) ────────────────────
    if [ "${DISTRO:-}" = "arch" ]; then
        log_info "[ 2/8 ] Verificando AUR helper (paru)..."
        ensure_paru || return 1
    else
        log_info "[ 2/8 ] Fedora detectado — ignorando paru."
    fi

    # ── Etapa 3: Pacotes principais ───────────────────────────
    log_info "[ 3/8 ] Instalando pacotes Hyprland..."
    if [ "${DISTRO:-}" = "arch" ]; then
        install_hyprland_packages_arch || return 1
    elif [ "${DISTRO:-}" = "fedora" ]; then
        install_hyprland_packages_fedora || return 1
    else
        log_error "Distribuição não suportada para instalação Hyprland: ${DISTRO:-desconhecida}"
        return 1
    fi

    # ── Etapa 4: Waybar (source/git) ─────────────────────────
    log_info "[ 4/8 ] Instalando Waybar..."
    build_waybar || log_warn "Waybar com problemas — continue manualmente se necessário."

    # ── Etapa 5: SDDM ────────────────────────────────────────
    log_info "[ 5/8 ] Configurando SDDM..."
    setup_sddm || log_warn "SDDM com problemas — configure manualmente."

    # ── Etapa 6: Bluetooth ───────────────────────────────────
    log_info "[ 6/8 ] Habilitando Bluetooth..."
    setup_bluetooth

    # ── Etapa 7: Dotfiles (clone + stow) ─────────────────────
    log_info "[ 7/8 ] Clonando e aplicando dotfiles com GNU Stow..."
    deploy_hyprland_dotfiles || log_warn "Dotfiles com problemas — verifique manualmente."

    # ── Etapa 8: Starship ────────────────────────────────────
    log_info "[ 8/8 ] Configurando Starship..."
    setup_starship

    # ── Mensagem final ────────────────────────────────────────
    hyprland_post_install_message
}
