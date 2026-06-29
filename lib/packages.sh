#!/usr/bin/env bash
# Biblioteca de instalação de pacotes para Fedora e Arch Linux
# Melhorias inspiradas no donarch:
#   - Pacotes organizados em arquivos .txt por categoria
#   - Separação automática de pacotes oficiais vs AUR
#   - Uso do AUR helper detectado pelo checks.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ─────────────────────────────────────────────────────────────
# UTILITÁRIO: Instalar lista de pacotes a partir de arquivo .txt
# Separa automaticamente pacotes oficiais (pacman) de AUR
# ─────────────────────────────────────────────────────────────
install_package_list() {
    local package_file="$1"
    local description="${2:-pacotes}"

    if [ ! -f "$package_file" ]; then
        log_error "Arquivo de pacotes não encontrado: $package_file"
        return 1
    fi

    # Ler pacotes do arquivo, ignorando linhas em branco e comentários
    local packages=()
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        packages+=("$line")
    done < "$package_file"

    if [ ${#packages[@]} -eq 0 ]; then
        log_warn "Nenhum pacote encontrado em $package_file"
        return 0
    fi

    log_info "Instalando $description (${#packages[@]} pacotes)..."

    # Separar pacotes oficiais dos pacotes AUR
    local official=()
    local aur=()

    for pkg in "${packages[@]}"; do
        if pacman -Si "$pkg" &>/dev/null 2>&1; then
            official+=("$pkg")
        else
            aur+=("$pkg")
        fi
    done

    # Instalar pacotes oficiais com pacman
    if [ ${#official[@]} -gt 0 ]; then
        log_info "Instalando ${#official[@]} pacotes oficiais via pacman..."
        sudo pacman -S --needed --noconfirm "${official[@]}" || {
            log_error "Falha ao instalar alguns pacotes oficiais."
            return 1
        }
    fi

    # Instalar pacotes AUR com o helper detectado
    if [ ${#aur[@]} -gt 0 ]; then
        if [ "${AUR_HELPER:-none}" = "none" ]; then
            log_warn "Pacotes AUR ignorados (sem AUR helper): ${aur[*]}"
        else
            log_info "Instalando ${#aur[@]} pacotes AUR via $AUR_HELPER..."
            local failed=()
            for pkg in "${aur[@]}"; do
                log_info "  AUR: $pkg"
                if ! "$AUR_HELPER" -S --needed --noconfirm "$pkg"; then
                    log_warn "  Falha ao instalar AUR: $pkg"
                    failed+=("$pkg")
                else
                    log_success "  $pkg instalado"
                fi
            done
            if [ ${#failed[@]} -gt 0 ]; then
                log_warn "Pacotes AUR que falharam: ${failed[*]}"
                log_warn "Instalação continuando — algumas funcionalidades podem estar ausentes."
            fi
        fi
    fi

    log_success "$description instalados com sucesso."
    return 0
}

# ─────────────────────────────────────────────────────────────
# FEDORA — Repositórios COPR
# ─────────────────────────────────────────────────────────────
setup_fedora_repos() {
    if prompt_yes_no "Deseja adicionar os repositórios COPR necessários (dms, ghostty e zen-browser)?" "S"; then
        log_info "Instalando dnf-plugins-core..."
        sudo dnf install -y dnf-plugins-core

        log_info "Habilitando COPR avengemedia/dms (DankMaterialShell)..."
        sudo dnf copr enable -y avengemedia/dms

        log_info "Habilitando COPR scottames/ghostty (Ghostty terminal)..."
        sudo dnf copr enable -y scottames/ghostty

        log_info "Habilitando COPR sneexy/zen-browser (Zen Browser)..."
        sudo dnf copr enable -y sneexy/zen-browser
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────
# FEDORA — Instalação principal
# ─────────────────────────────────────────────────────────────
install_fedora_packages() {
    setup_fedora_repos

    if prompt_yes_no "Deseja instalar os pacotes essenciais do ambiente no Fedora?" "S"; then
        log_info "Instalando pacotes essenciais via DNF..."

        local packages=(
            niri
            dms
            fuzzel
            cava
            alacritty
            ghostty
            fish
            micro
            btop
            fastfetch
            ripgrep
            rsync
            playerctl
            git
            util-linux-user
            google-noto-sans-fonts
            google-noto-color-emoji-fonts
            abattis-cantarell-fonts
            power-profiles-daemon
            bluez
            NetworkManager
            gnome-disk-utility
            mpv
            keepassxc
            flatpak
            ufw
            gnome-text-editor
            nautilus
            firefox
            zen-browser
            # Audio base (vital em instalações limpas/mínimas)
            pipewire
            wireplumber
            pipewire-pulseaudio
            pipewire-alsa
            pavucontrol
            xdg-utils
            libsecret
            xdg-desktop-portal
            xdg-desktop-portal-gtk
            polkit-gnome
            gstreamer1-plugin-libav
            gstreamer1-plugins-good
            gstreamer1-plugins-bad-free
            gstreamer1-plugins-ugly-free
            ffmpeg-free
            gnome-keyring
            seahorse
            ffmpegthumbnailer
            tumbler
            poppler-glib
            wl-clipboard
            shared-mime-info
            libappindicator-gtk3
        )

        # Adicionar pacotes do SDDM
        packages+=(
            sddm
            sddm-x11
            qt5-qtgraphicaleffects
            qt5-qtquickcontrols2
            qt5-qtvirtualkeyboard
            qt6-qtsvg
            qt6-qtvirtualkeyboard
            qt6-qtmultimedia
            qt6-qt5compat
        )

        sudo dnf install -y --skip-broken --setopt=strict=False "${packages[@]}"
    fi

    if prompt_yes_no "Deseja instalar a fonte Meslo Nerd Font para evitar ícones quebrados?" "S"; then
        install_meslo_font
    fi
}

# ─────────────────────────────────────────────────────────────
# ARCH — Repositórios CachyOS (opcional)
# ─────────────────────────────────────────────────────────────
setup_arch_repos() {
    # Evitar reinstalar se já estiver configurado
    if grep -q "^\[cachyos\]" /etc/pacman.conf 2>/dev/null; then
        log_info "Repositórios do CachyOS já configurados no pacman.conf."
        return 0
    fi

    if prompt_yes_no "Deseja adicionar os repositórios otimizados do CachyOS? (Recomendado para Arch puro)" "S"; then
        log_info "Adicionando repositórios do CachyOS..."
        local temp_dir
        temp_dir=$(mktemp -d)
        if curl -fLo "$temp_dir/cachyos-repo.tar.xz" "https://mirror.cachyos.org/cachyos-repo.tar.xz"; then
            tar -xf "$temp_dir/cachyos-repo.tar.xz" -C "$temp_dir"
            (
                cd "$temp_dir/cachyos-repo"
                sudo ./cachyos-repo.sh
            )
            rm -rf "$temp_dir"
            sudo pacman -Syu --noconfirm
        else
            log_error "Falha ao baixar script do repositório CachyOS."
            rm -rf "$temp_dir"
            return 1
        fi
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────
# ARCH — Instalação principal usando arquivos .txt por categoria
# ─────────────────────────────────────────────────────────────
install_arch_packages() {
    local repo_dir="$1"
    local pkg_dir="$repo_dir/packages"

    setup_arch_repos

    log_success "Gerenciador de pacotes: pacman | AUR helper: ${AUR_HELPER:-none}"

    log_info "Sincronizando a base de dados do pacman..."
    sudo pacman -Sy

    if prompt_yes_no "Deseja instalar os pacotes essenciais do ambiente no Arch Linux?" "S"; then
        # 1. Pacotes base do ambiente
        install_package_list "$pkg_dir/arch-base.txt" "Ambiente base (Niri + Apps)"

        # 2. Display Manager (SDDM)
        install_package_list "$pkg_dir/arch-sddm.txt" "SDDM e dependências Qt"
    fi

    # 3. Fontes
    if prompt_yes_no "Deseja instalar as fontes do ambiente (Noto, Cantarell, Meslo Nerd)?" "S"; then
        install_package_list "$pkg_dir/arch-fonts.txt" "Fontes"
    fi

    # 4. Apps opcionais — apresentar menu de escolha
    install_optional_apps_arch "$pkg_dir/arch-optional.txt"
}

# ─────────────────────────────────────────────────────────────
# ARCH — Seleção interativa de apps opcionais
# Inspirado no donarch — o usuário escolhe o que quer instalar
# ─────────────────────────────────────────────────────────────
install_optional_apps_arch() {
    local optional_file="$1"

    if [ ! -f "$optional_file" ]; then
        return 0
    fi

    # Ler apps disponíveis do arquivo (ignorando comentários e linhas em branco)
    local available=()
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        available+=("$line")
    done < "$optional_file"

    if [ ${#available[@]} -eq 0 ]; then
        return 0
    fi

    echo ""
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${YELLOW}Aplicativos Opcionais${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo "Selecione os aplicativos que deseja instalar"
    echo "(números separados por espaço, ou Enter para pular):"
    echo ""

    local i=1
    for app in "${available[@]}"; do
        echo "  $i) $app"
        ((i++))
    done
    echo ""

    read -p "Sua escolha (ex: '1 2' ou Enter para pular): " choices

    local selected=()
    for choice in $choices; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#available[@]}" ]; then
            selected+=("${available[$((choice-1))]}")
        else
            log_warn "Opção inválida ignorada: $choice"
        fi
    done

    if [ ${#selected[@]} -eq 0 ]; then
        log_info "Nenhum aplicativo opcional selecionado."
        return 0
    fi

    log_info "Instalando aplicativos opcionais selecionados..."
    for app in "${selected[@]}"; do
        log_info "Instalando: $app"
        if pacman -Si "$app" &>/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm "$app" && log_success "$app instalado" || log_warn "Falha ao instalar $app"
        elif [ "${AUR_HELPER:-none}" != "none" ]; then
            "$AUR_HELPER" -S --needed --noconfirm "$app" && log_success "$app instalado" || log_warn "Falha ao instalar AUR: $app"
        else
            log_warn "$app é um pacote AUR e nenhum AUR helper está disponível. Pulando."
        fi
    done
}

# ─────────────────────────────────────────────────────────────
# UTILITÁRIO: Instalar Meslo Nerd Font manualmente (fallback)
# ─────────────────────────────────────────────────────────────
install_meslo_font() {
    log_info "Baixando e instalando a fonte Meslo Nerd Font manualmente..."
    local font_dir
    font_dir="$(get_user_home)/.local/share/fonts"
    mkdir -p "$font_dir"

    local temp_dir
    temp_dir=$(mktemp -d)
    local url_font="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.tar.xz"

    if curl -fLo "$temp_dir/Meslo.tar.xz" "$url_font"; then
        log_info "Extraindo fonte..."
        if tar -xf "$temp_dir/Meslo.tar.xz" -C "$temp_dir"; then
            find "$temp_dir" -name "*Meslo*.ttf" -exec cp {} "$font_dir/" \;
            log_info "Atualizando cache de fontes..."
            fc-cache -fv &>/dev/null
            log_success "Meslo Nerd Font instalada com sucesso!"
            rm -rf "$temp_dir"
            return 0
        fi
    fi
    log_error "Erro ao baixar ou extrair a fonte Meslo Nerd Font."
    rm -rf "$temp_dir"
    return 1
}
