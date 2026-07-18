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
        # Tenta em lote; se a transação falhar (um pacote ruim derruba tudo),
        # reinstala um a um para não perder os pacotes válidos — em especial o
        # sddm, que costumava sumir junto com uma dep Qt que falhava no lote.
        if ! sudo pacman -S --needed --noconfirm "${official[@]}"; then
            log_warn "Transação em lote falhou — reinstalando pacote a pacote (não perde válidos como o sddm)..."
            local failed_official=()
            for pkg in "${official[@]}"; do
                sudo pacman -S --needed --noconfirm "$pkg" || failed_official+=("$pkg")
            done
            if [ ${#failed_official[@]} -gt 0 ]; then
                log_warn "Pacotes oficiais que falharam individualmente: ${failed_official[*]}"
            fi
        fi
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
# Instalar o Desktop Shell escolhido (DMS ou Noctalia beta)
# Depende de SHELL_CHOICE (dms|noctalia), definido por select_shell().
# ─────────────────────────────────────────────────────────────
install_shell_packages() {
    local choice="${SHELL_CHOICE:-dms}"

    if [ "${DISTRO:-arch}" = "fedora" ]; then
        # No Fedora, o DMS vem do COPR (já habilitado). Noctalia não tem pacote
        # oficial no Fedora — avisamos e caímos para o DMS.
        if [ "$choice" = "noctalia" ]; then
            log_warn "Noctalia não tem pacote oficial no Fedora — instalando o DMS no lugar."
        fi
        log_info "Instalando DankMaterialShell (dms) no Fedora..."
        sudo dnf install -y dms || log_warn "Falha ao instalar o dms."
        return 0
    fi

    # ── Arch / CachyOS ──
    if [ "$choice" = "noctalia" ]; then
        log_info "Instalando Noctalia Shell (beta)..."
        # 1ª opção: pacote 'noctalia' no repo oficial (no CachyOS é a beta 5.x) — sem build.
        if pacman -Si noctalia &>/dev/null 2>&1; then
            log_info "  Encontrado 'noctalia' nos repos oficiais — instalando via pacman."
            sudo pacman -S --needed --noconfirm noctalia \
                && log_success "Noctalia (beta) instalado via pacman." \
                && return 0
            log_warn "  Falha via pacman — tentando AUR (noctalia-git)."
        fi
        # 2ª opção: AUR noctalia-git (versão de desenvolvimento, também beta 5.x).
        if [ "${AUR_HELPER:-none}" != "none" ]; then
            log_info "  Instalando 'noctalia-git' via ${AUR_HELPER}..."
            "$AUR_HELPER" -S --needed --noconfirm noctalia-git \
                && { log_success "Noctalia (noctalia-git) instalado via AUR."; return 0; }
            log_warn "  Falha ao instalar noctalia-git via AUR."
        else
            log_warn "  Sem AUR helper e 'noctalia' indisponível no repo — não foi possível instalar o Noctalia."
        fi
        log_error "Não foi possível instalar o Noctalia. Instale manualmente: paru -S noctalia-git"
        return 1
    fi

    # DMS (padrão)
    log_info "Instalando DankMaterialShell (dms-shell)..."
    if pacman -Si dms-shell &>/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm dms-shell \
            && { log_success "DMS instalado via pacman."; return 0; }
    fi
    if [ "${AUR_HELPER:-none}" != "none" ]; then
        "$AUR_HELPER" -S --needed --noconfirm dms-shell \
            && { log_success "DMS instalado via AUR."; return 0; }
    fi
    log_error "Não foi possível instalar o DMS (dms-shell)."
    return 1
}

# ─────────────────────────────────────────────────────────────
# FEDORA — Repositórios COPR
# ─────────────────────────────────────────────────────────────
setup_fedora_repos() {
    if prompt_yes_no "Deseja adicionar os repositórios COPR necessários (dms e ghostty)?" "S"; then
        log_info "Instalando dnf-plugins-core..."
        sudo dnf install -y dnf-plugins-core

        log_info "Habilitando COPR avengemedia/dms (DankMaterialShell)..."
        sudo dnf copr enable -y avengemedia/dms || log_warn "Falha ao ativar COPR do DMS"

        log_info "Habilitando COPR scottames/ghostty (Ghostty terminal)..."
        sudo dnf copr enable -y scottames/ghostty || log_warn "Falha ao ativar COPR do ghostty"
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

        # Desktop Shell escolhido (DMS ou Noctalia)
        install_shell_packages || log_warn "Shell (${SHELL_CHOICE:-dms}) pode não ter sido instalado."
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
                sudo ./cachyos-repo.sh || echo "Falha ao executar script do CachyOS."
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

    # Otimizar mirrors antes de baixar qualquer coisa (item 2) — se disponível.
    if declare -f optimize_mirrors_arch &>/dev/null; then
        optimize_mirrors_arch
    fi

    setup_arch_repos

    log_success "Gerenciador de pacotes: pacman | AUR helper: ${AUR_HELPER:-none}"

    # IMPORTANTE: usar -Syu (nunca apenas -Sy). Um 'pacman -Sy' seguido de instalação
    # é um "partial upgrade" e pode quebrar o sistema (libs novas contra sistema antigo),
    # especialmente em instalações recém-feitas/mínimas.
    log_info "Sincronizando a base de dados e atualizando o sistema (evita partial upgrade)..."
    sudo pacman -Syu --noconfirm

    if prompt_yes_no "Deseja instalar os pacotes essenciais do ambiente no Arch Linux?" "S"; then
        # 1. Pacotes base do ambiente
        install_package_list "$pkg_dir/arch-base.txt" "Ambiente base (Niri + Apps)"

        # 2. Desktop Shell escolhido (DMS ou Noctalia beta)
        install_shell_packages || log_warn "Shell (${SHELL_CHOICE:-dms}) pode não ter sido instalado."

        # 3. Display Manager (SDDM)
        install_package_list "$pkg_dir/arch-sddm.txt" "SDDM e dependências Qt"
    fi

    # 3. Fontes
    if prompt_yes_no "Deseja instalar as fontes do ambiente (Noto, Cantarell, Meslo Nerd)?" "S"; then
        install_package_list "$pkg_dir/arch-fonts.txt" "Fontes"
    fi

    # 4. Navegadores — menu de seleção múltipla
    install_browsers_arch "$pkg_dir/arch-browsers.txt"

    # 5. Codecs multimídia (recomendado para reproduzir áudio/vídeo)
    if prompt_yes_no "Deseja instalar os codecs multimídia (áudio/vídeo em qualquer formato)?" "S"; then
        install_package_list "$pkg_dir/arch-codecs.txt" "Codecs multimídia"
    fi

    # 6. Bibliotecas/utilitários que todo sistema precisa
    if prompt_yes_no "Deseja instalar bibliotecas e utilitários essenciais (arquivos, montagem, man, etc.)?" "S"; then
        install_package_list "$pkg_dir/arch-libs.txt" "Bibliotecas e utilitários essenciais"
    fi

    # 7. Apps opcionais — apresentar menu de escolha
    install_optional_apps_arch "$pkg_dir/arch-optional.txt"
}

# ─────────────────────────────────────────────────────────────
# ARCH — Menu genérico de seleção múltipla a partir de um arquivo .txt
# Usado tanto para navegadores quanto para apps opcionais.
# Aceita: números separados por espaço (ex: "1 3"), "todos"/"all", ou Enter (pular).
# Argumentos: $1 = arquivo .txt   $2 = título do menu
# ─────────────────────────────────────────────────────────────
select_and_install_menu() {
    local optional_file="$1"
    local menu_title="${2:-Aplicativos Opcionais}"

    if [ ! -f "$optional_file" ]; then
        return 0
    fi

    # Ler apps disponíveis do arquivo (ignorando comentários e linhas em branco).
    # Cada linha pode ter o formato "pacote | Rótulo amigável"; guardamos o nome
    # do pacote em 'pkgs' e o rótulo exibido em 'labels'.
    local pkgs=()
    local labels=()
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        local pkg label
        if [[ "$line" == *"|"* ]]; then
            pkg="${line%%|*}"
            label="${line#*|}"
        else
            pkg="$line"
            label="$line"
        fi
        # Remover espaços em branco nas pontas
        pkg="$(echo "$pkg" | xargs)"
        label="$(echo "$label" | xargs)"

        [ -z "$pkg" ] && continue
        pkgs+=("$pkg")
        labels+=("$label")
    done < "$optional_file"

    if [ ${#pkgs[@]} -eq 0 ]; then
        return 0
    fi

    echo ""
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${YELLOW}          ${menu_title}${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo "Escolha os itens que deseja instalar:"
    echo -e "  • números separados por espaço  (ex: ${CYAN}1 3${NC})"
    echo -e "  • ${CYAN}todos${NC} para instalar todos"
    echo -e "  • ${CYAN}Enter${NC} para pular"
    echo ""

    local i=1
    for label in "${labels[@]}"; do
        printf "  ${GREEN}%2d${NC}) %s\n" "$i" "$label"
        ((i++))
    done
    echo ""

    read -p "Sua escolha: " choices

    # Expandir "todos"/"all" para todos os índices
    local lower_choices
    lower_choices="$(echo "$choices" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower_choices" =~ (^|[[:space:]])(todos|all|t)($|[[:space:]]) ]]; then
        choices=$(seq 1 "${#pkgs[@]}")
    fi

    local selected=()
    for choice in $choices; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#pkgs[@]}" ]; then
            selected+=("${pkgs[$((choice-1))]}")
        else
            log_warn "Opção inválida ignorada: $choice"
        fi
    done

    if [ ${#selected[@]} -eq 0 ]; then
        log_info "Nenhum item selecionado."
        return 0
    fi

    log_info "Instalando itens selecionados..."
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

# Wrapper — menu de apps opcionais (compatibilidade com o restante do script)
install_optional_apps_arch() {
    select_and_install_menu "$1" "Aplicativos Opcionais"
}

# Wrapper — menu de navegadores (seleção múltipla)
install_browsers_arch() {
    select_and_install_menu "$1" "Navegadores (escolha um ou mais)"
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
