#!/usr/bin/env bash
# Biblioteca de instalação de pacotes para Fedora e Arch Linux
# Melhorias inspiradas no donarch:
#   - Pacotes organizados em arquivos .txt por categoria
#   - Separação automática de pacotes oficiais vs AUR
#   - Uso do AUR helper detectado pelo checks.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ═════════════════════════════════════════════════════════════
# BACKEND DE PACOTES AGNÓSTICO DE DISTRO
#
# Antes, todo o motor de instalação (menus inclusive) estava cabeado em
# 'pacman -Si' e no AUR_HELPER, o que tornava as etapas interativas —
# navegadores, apps opcionais, libs — exclusivas do Arch. Estas funções
# isolam a diferença entre as distros num único lugar, para que o MESMO
# código de menu sirva aos dois casos.
#
# Formato aceito nas listas .txt (packages/*.txt):
#   nome                        → pacote nativo (pacman / dnf)
#   flatpak:<app-id>            → Flatpak vindo do Flathub
#   copr:<dono>/<projeto>:<pkg> → habilita o COPR e instala (só Fedora)
#   curl:<url>                  → instalador oficial do próprio programa
# ═════════════════════════════════════════════════════════════

# O pacote existe no gerenciador nativo desta distro?
pkg_available() {
    case "${DISTRO:-arch}" in
        fedora) dnf list "$1" &>/dev/null ;;
        *)      pacman -Si "$1" &>/dev/null ;;
    esac
}

# Instalar um ou mais pacotes pelo gerenciador nativo.
pkg_install() {
    case "${DISTRO:-arch}" in
        fedora) sudo dnf install -y "$@" ;;
        *)      sudo pacman -S --needed --noconfirm "$@" ;;
    esac
}

# O pacote está instalado?
pkg_installed() {
    case "${DISTRO:-arch}" in
        fedora) rpm -q "$1" &>/dev/null ;;
        *)      pacman -Q "$1" &>/dev/null ;;
    esac
}

# Instalar um app do Flathub. Usado para programas que não têm pacote nativo
# no Fedora (Obsidian, Spotify, alguns navegadores...).
flatpak_install() {
    local app_id="$1"
    if ! command -v flatpak &>/dev/null; then
        log_warn "  flatpak não está instalado — não é possível instalar $app_id."
        return 1
    fi
    # O Flathub é adicionado por setup_flatpak(), mas esta etapa pode rodar
    # antes dele; garantir aqui torna a função independente da ordem.
    sudo flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo &>/dev/null || true
    sudo flatpak install -y --noninteractive flathub "$app_id"
}

# Habilitar um repositório COPR (Fedora) e instalar o pacote indicado.
copr_install() {
    local spec="$1"              # <dono>/<projeto>:<pacote>
    local repo="${spec%%:*}"
    local pkg="${spec##*:}"

    if [ "${DISTRO:-arch}" != "fedora" ]; then
        log_warn "  Entrada COPR ignorada fora do Fedora: $spec"
        return 1
    fi
    log_info "  Habilitando COPR ${repo}..."
    sudo dnf copr enable -y "$repo" || { log_warn "  Falha ao habilitar o COPR ${repo}."; return 1; }
    sudo dnf install -y "$pkg"
}

# Instalar UMA entrada de lista, seja qual for o seu prefixo.
# Retorna 0 em sucesso, 1 em falha (o chamador decide o que logar).
install_entry() {
    local app="$1"

    case "$app" in
        curl:*)
            local url="${app#curl:}"
            log_info "  Instalador oficial: $url"
            # Baixar para um arquivo ANTES de executar, em vez de
            # 'curl ... | bash'. No pipe, o status final é o do bash: se o
            # download falhasse (404, DNS, rede), o bash recebia entrada vazia
            # e saía com 0 — a falha era reportada como sucesso. Baixar antes
            # permite checar o download e o conteúdo separadamente.
            local tmp_script rc
            tmp_script=$(mktemp)
            if ! curl -fsSL "$url" -o "$tmp_script"; then
                log_warn "  Falha ao baixar o instalador: $url"
                rm -f "$tmp_script"
                return 1
            fi
            if [ ! -s "$tmp_script" ]; then
                log_warn "  Instalador baixado veio vazio: $url"
                rm -f "$tmp_script"
                return 1
            fi
            bash "$tmp_script"
            rc=$?
            rm -f "$tmp_script"
            if [ "$rc" -eq 0 ]; then
                log_info "  Se o comando não for encontrado, abra um novo terminal (instala em ~/.local/bin ou similar)."
            fi
            return "$rc"
            ;;
        flatpak:*)
            local app_id="${app#flatpak:}"
            log_info "  Flatpak: $app_id"
            flatpak_install "$app_id"
            return $?
            ;;
        copr:*)
            copr_install "${app#copr:}"
            return $?
            ;;
    esac

    # ── Pacote nativo ────────────────────────────────────────
    if pkg_available "$app"; then
        if [ "${DISTRO:-arch}" = "fedora" ]; then
            sudo dnf install -y "$app"
            return $?
        fi
        # No Arch, distinguir falha por CONFLITO de uma falha comum: ex.: no
        # CachyOS o 'timeshift' conflita com o 'cachyos-snapper-support' e o
        # pacman aborta — antes isso poluía o log sem explicação.
        local _pac_out _rc
        _pac_out=$(mktemp)
        sudo pacman -S --needed --noconfirm "$app" 2>&1 | tee "$_pac_out"
        _rc=${PIPESTATUS[0]}
        if [ "$_rc" -ne 0 ] && grep -qiE 'estão em conflito|conflito de pacotes|are in conflict|package conflicts' "$_pac_out"; then
            log_warn "  $app NÃO instalado: conflita com um pacote já presente (pulando)."
            log_info  "    Ex.: no CachyOS o 'timeshift' conflita com o 'cachyos-snapper-support'."
            rm -f "$_pac_out"
            return 0   # conflito conhecido não conta como erro
        fi
        rm -f "$_pac_out"
        return "$_rc"
    fi

    # Não existe nativamente: no Arch pode ser AUR.
    if [ "${DISTRO:-arch}" != "fedora" ] && [ "${AUR_HELPER:-none}" != "none" ]; then
        "$AUR_HELPER" -S --needed --noconfirm $(aur_noninteractive_flags) "$app"
        return $?
    fi

    log_warn "  '$app' não está disponível nesta distro (e não há alternativa configurada)."
    return 1
}

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

    # ── Fedora ───────────────────────────────────────────────
    # Não existe a divisão oficial/AUR; entradas com prefixo (flatpak:, copr:,
    # curl:) vão uma a uma por install_entry(), e o resto é uma transação dnf
    # só — bem mais rápido que instalar pacote a pacote.
    if [ "${DISTRO:-arch}" = "fedora" ]; then
        local native=() special=()
        for pkg in "${packages[@]}"; do
            case "$pkg" in
                flatpak:*|copr:*|curl:*) special+=("$pkg") ;;
                *)                       native+=("$pkg") ;;
            esac
        done

        if [ ${#native[@]} -gt 0 ]; then
            sudo dnf install -y --skip-broken "${native[@]}" \
                || log_warn "Alguns pacotes de '$description' falharam."
            # Relatar o que o --skip-broken descartou silenciosamente.
            local missing=()
            for pkg in "${native[@]}"; do
                pkg_installed "$pkg" || missing+=("$pkg")
            done
            if [ ${#missing[@]} -gt 0 ]; then
                log_warn "Não instalados em '$description': ${missing[*]}"
            fi
        fi

        for pkg in "${special[@]}"; do
            log_info "  $pkg"
            install_entry "$pkg" || log_warn "  Falha: $pkg"
        done

        log_success "$description processados."
        return 0
    fi

    # ── Arch / CachyOS ───────────────────────────────────────
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
                if ! "$AUR_HELPER" -S --needed --noconfirm $(aur_noninteractive_flags) "$pkg"; then
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
# Fallback: compilar noctalia-git direto do AUR com makepkg
# (método "Non-AUR Helper" da documentação oficial do Noctalia).
# Usado quando não há AUR helper ou quando o helper falhou.
# ─────────────────────────────────────────────────────────────
install_noctalia_makepkg() {
    log_info "  Fallback: clonando AUR e compilando com makepkg (método oficial sem helper)..."
    local build_dir
    build_dir=$(mktemp -d)
    if git clone https://aur.archlinux.org/noctalia-git.git "$build_dir/noctalia-git" \
        && ( cd "$build_dir/noctalia-git" && makepkg -si --needed --noconfirm ); then
        rm -rf "$build_dir"
        return 0
    fi
    rm -rf "$build_dir"
    return 1
}

# ─────────────────────────────────────────────────────────────
# Instalar o Desktop Shell escolhido (DMS ou Noctalia beta)
# Depende de SHELL_CHOICE (dms|noctalia), definido por select_shell().
# ─────────────────────────────────────────────────────────────
install_shell_packages() {
    local choice="${SHELL_CHOICE:-dms}"

    if [ "${DISTRO:-arch}" = "fedora" ]; then
        if [ "$choice" = "noctalia" ]; then
            # O Noctalia 5.x ESTÁ nos repositórios oficiais do Fedora (updates),
            # como 'noctalia' — não precisa de COPR, AUR nem build manual.
            # O pacote instala /usr/bin/noctalia, exatamente o binário que os
            # dotfiles esperam ('noctalia --daemon' e 'noctalia msg <cmd>').
            log_info "Instalando Noctalia Shell (beta 5.x) no Fedora..."
            if sudo dnf install -y noctalia; then
                # O Noctalia usa o matugen para gerar o tema dinâmico a partir do
                # papel de parede. No caminho do DMS ele vem como dependência;
                # no do Noctalia, não — por isso é instalado explicitamente aqui.
                sudo dnf install -y matugen || log_warn "Falha ao instalar o matugen (tema dinâmico pode não funcionar)."
                log_success "Noctalia (beta 5.x) instalado via dnf."
                return 0
            fi
            log_error "Não foi possível instalar o Noctalia no Fedora."
            log_info  "  Verifique manualmente com: dnf info noctalia"
            return 1
        fi

        # DMS (padrão) — vem do COPR avengemedia/dms, já habilitado por setup_fedora_repos().
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
            "$AUR_HELPER" -S --needed --noconfirm $(aur_noninteractive_flags) noctalia-git \
                && { log_success "Noctalia (noctalia-git) instalado via AUR."; return 0; }
            log_warn "  Falha ao instalar noctalia-git via ${AUR_HELPER} — tentando makepkg direto."
        else
            log_warn "  Sem AUR helper — tentando compilar direto do AUR com makepkg."
        fi
        # 3ª opção: makepkg direto (não depende de helper nenhum).
        install_noctalia_makepkg \
            && { log_success "Noctalia (noctalia-git) instalado via makepkg."; return 0; }
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
        "$AUR_HELPER" -S --needed --noconfirm $(aur_noninteractive_flags) dms-shell \
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
# FEDORA — RPM Fusion + codecs multimídia
#
# Equivalente ao packages/arch-codecs.txt do lado Arch. No Fedora os codecs
# proprietários (H.264/H.265, AAC, etc.) NÃO estão nos repositórios oficiais
# por questões de patente: o Fedora envia apenas 'ffmpeg-free' e os plugins
# gstreamer livres. Sem o RPM Fusion, boa parte dos vídeos da web e dos
# arquivos .mp4/.mkv locais simplesmente não toca.
# ─────────────────────────────────────────────────────────────
setup_fedora_codecs() {
    if ! prompt_yes_no "Deseja instalar os codecs multimídia completos (RPM Fusion — necessário para H.264/H.265, MP4, etc.)?" "S"; then
        log_info "Codecs multimídia ignorados."
        return 0
    fi

    local fedora_ver
    fedora_ver=$(rpm -E %fedora)

    log_info "Habilitando os repositórios RPM Fusion (free e nonfree)..."
    if ! sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"
    then
        log_warn "Falha ao habilitar o RPM Fusion — codecs proprietários não serão instalados."
        return 0
    fi
    log_success "RPM Fusion habilitado."

    # Trocar o ffmpeg-free (livre, limitado) pelo ffmpeg completo do RPM Fusion.
    # '--allowerasing' é necessário: os dois pacotes se substituem mutuamente.
    log_info "Substituindo ffmpeg-free pelo ffmpeg completo..."
    sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing \
        || log_warn "Falha na troca do ffmpeg — o ffmpeg-free continua instalado."

    # Completar o grupo multimídia com as versões irrestritas dos plugins.
    # O PackageKit-gstreamer-plugin é excluído de propósito: ele dispara
    # instalação automática de codecs em background, o que conflita com a
    # instalação explícita feita aqui.
    log_info "Atualizando o grupo multimídia com os codecs irrestritos..."
    sudo dnf update -y @multimedia --setopt="install_weak_deps=False" \
        --exclude=PackageKit-gstreamer-plugin \
        || log_warn "Falha ao atualizar o grupo multimídia."

    log_info "Instalando plugins gstreamer adicionais..."
    sudo dnf install -y gstreamer1-plugins-bad-freeworld libavcodec-freeworld \
        || log_warn "Alguns plugins gstreamer extras não foram instalados."

    # ── Aceleração de vídeo por hardware (VA-API) ────────────
    # O driver correto depende da GPU; instalar o errado é inofensivo (fica
    # sem uso), mas detectar evita puxar pacote à toa.
    log_info "Detectando GPU para a aceleração de vídeo por hardware..."
    local gpu_info va_pkgs=()
    gpu_info=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)

    if grep -qi 'intel' <<< "$gpu_info"; then
        log_info "  GPU Intel detectada."
        va_pkgs+=(intel-media-driver)
    fi
    if grep -qiE 'amd|ati|radeon' <<< "$gpu_info"; then
        log_info "  GPU AMD detectada."
        va_pkgs+=(mesa-va-drivers-freeworld mesa-vdpau-drivers-freeworld)
    fi
    if grep -qi 'nvidia' <<< "$gpu_info"; then
        log_info "  GPU NVIDIA detectada — driver proprietário não é instalado por este script."
        log_info "  Se quiser, instale depois com: sudo dnf install akmod-nvidia"
    fi

    if [ ${#va_pkgs[@]} -gt 0 ]; then
        log_info "Instalando drivers VA-API: ${va_pkgs[*]}"
        sudo dnf install -y --skip-broken "${va_pkgs[@]}" \
            || log_warn "Falha ao instalar drivers VA-API — a decodificação por hardware pode não funcionar."
    fi
    sudo dnf install -y libva-utils || true

    log_success "Codecs multimídia configurados. (Verifique a aceleração com: vainfo)"
    return 0
}

# ─────────────────────────────────────────────────────────────
# FEDORA — Instalação principal
# ─────────────────────────────────────────────────────────────
install_fedora_packages() {
    local repo_dir="$1"
    local pkg_dir="$repo_dir/packages"

    setup_fedora_repos

    if prompt_yes_no "Deseja instalar os pacotes essenciais do ambiente no Fedora?" "S"; then
        log_info "Instalando pacotes essenciais via DNF..."

        local packages=(
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
            # NOTA: 'util-linux-user' NÃO existe mais no Fedora 44 — o 'chsh'
            # voltou para o pacote 'util-linux' (que já é base do sistema).
            # Manter o nome antigo fazia o --skip-broken descartá-lo em silêncio.
            util-linux
            # Geração de tema dinâmico a partir do papel de parede (DMS e Noctalia).
            matugen
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
            # firefox foi movido para o menu de navegadores
            # (packages/fedora-browsers.txt), igual ao lado Arch.
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
            # NOTA: 'polkit-gnome' NÃO existe no Fedora (é o nome usado no Arch).
            # Sem um agente polkit, nenhuma janela de autenticação aparece no
            # Niri — montar discos, mudar perfil de energia, etc. falham em
            # silêncio. 'mate-polkit' é o agente GTK equivalente no Fedora.
            mate-polkit
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

        # Compositor escolhido (Niri ou Hyprland) — veja select_compositor().
        # 'grim'/'slurp'/'jq' cobrem os atalhos de screenshot da config do Hyprland.
        if [ "${COMPOSITOR_CHOICE:-niri}" = "hyprland" ]; then
            packages+=(hyprland xdg-desktop-portal-hyprland grim slurp jq)
        else
            # Paridade com packages/arch-niri.txt: o Niri usa o portal do GNOME
            # para screencast/screenshot. Vinha apenas por dependência transitiva
            # — declarar explicitamente evita depender disso.
            packages+=(niri xdg-desktop-portal-gnome grim slurp jq)
        fi

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

        # O '--skip-broken' descarta pacotes inexistentes SEM erro e SEM aviso.
        # Foi assim que 'util-linux-user' e 'polkit-gnome' (nomes do Arch, que
        # não existem no Fedora) sumiram da instalação sem ninguém perceber —
        # o log terminava com "sucesso" e o sistema ficava sem agente polkit.
        # Este relatório torna qualquer descarte futuro visível no log.
        local not_installed=()
        for pkg in "${packages[@]}"; do
            [[ "$pkg" =~ ^# ]] && continue
            rpm -q "$pkg" &>/dev/null || not_installed+=("$pkg")
        done
        if [ ${#not_installed[@]} -gt 0 ]; then
            log_warn "Pacotes solicitados que NÃO ficaram instalados (${#not_installed[@]}):"
            for pkg in "${not_installed[@]}"; do
                log_warn "  • $pkg"
            done
            log_info "  Verifique o nome no Fedora com: dnf search <nome>"
        else
            log_success "Todos os ${#packages[@]} pacotes solicitados estão instalados."
        fi

        # Desktop Shell escolhido (DMS ou Noctalia)
        install_shell_packages || log_warn "Shell (${SHELL_CHOICE:-dms}) pode não ter sido instalado."
    fi

    if prompt_yes_no "Deseja instalar a fonte Meslo Nerd Font para evitar ícones quebrados?" "S"; then
        install_meslo_font
    fi

    # ── Etapas interativas, em paridade com o fluxo do Arch ──
    # A ordem espelha install_arch_packages(): navegadores, codecs, libs e,
    # por último, os apps opcionais.

    # Navegadores — menu de seleção múltipla.
    install_browsers_fedora "$pkg_dir/fedora-browsers.txt"

    # Codecs multimídia (RPM Fusion). Roda DEPOIS dos pacotes essenciais de
    # propósito: o 'dnf swap' precisa que o ffmpeg-free já esteja instalado
    # para poder substituí-lo. Também habilita o RPM Fusion nonfree, do qual
    # dependem o steam e o vlc do menu de apps opcionais — por isso vem antes.
    setup_fedora_codecs

    # Bibliotecas e utilitários essenciais.
    if prompt_yes_no "Deseja instalar bibliotecas e utilitários essenciais (arquivos, montagem, man, etc.)?" "S"; then
        install_package_list "$pkg_dir/fedora-libs.txt" "Bibliotecas e utilitários essenciais"
    fi

    # Apps opcionais — menu de seleção múltipla.
    install_optional_apps_fedora "$pkg_dir/fedora-optional.txt"
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
        # 1. Pacotes base comuns do ambiente (independentes do compositor)
        install_package_list "$pkg_dir/arch-base.txt" "Ambiente base (apps comuns)"

        # 1b. Compositor escolhido (Niri ou Hyprland) — veja select_compositor().
        if [ "${COMPOSITOR_CHOICE:-niri}" = "hyprland" ]; then
            install_package_list "$pkg_dir/arch-hyprland.txt" "Compositor Hyprland"
        else
            install_package_list "$pkg_dir/arch-niri.txt" "Compositor Niri"
        fi

        # 2. Display Manager (SDDM) — instalado ANTES do shell de propósito.
        # O Noctalia (AUR) pode falhar/travar numa build longa; se isso vier
        # primeiro e o usuário precisar interromper o script, o SDDM nunca
        # chegaria a ser instalado. Com o SDDM primeiro, o sistema já entra
        # em modo gráfico no próximo boot mesmo que o shell falhe depois.
        install_package_list "$pkg_dir/arch-sddm.txt" "SDDM e dependências Qt"

        # 3. Desktop Shell escolhido (DMS ou Noctalia beta)
        install_shell_packages || log_warn "Shell (${SHELL_CHOICE:-dms}) pode não ter sido instalado."
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

    # A instalação de cada item é delegada a install_entry(), que resolve o
    # prefixo (nativo / flatpak: / copr: / curl:) conforme a distro. É o que
    # permite este mesmo menu servir Arch e Fedora sem duplicar código.
    log_info "Instalando itens selecionados..."
    local failed=()
    for app in "${selected[@]}"; do
        log_info "Instalando: $app"
        if install_entry "$app"; then
            log_success "$app instalado"
        else
            log_warn "Falha ao instalar: $app"
            failed+=("$app")
        fi
    done

    if [ ${#failed[@]} -gt 0 ]; then
        log_warn "Itens que falharam (${#failed[@]}): ${failed[*]}"
        log_info "  A instalação continua — estes itens podem ser instalados manualmente depois."
    fi
    return 0
}

# Wrapper — menu de apps opcionais (compatibilidade com o restante do script)
install_optional_apps_arch() {
    select_and_install_menu "$1" "Aplicativos Opcionais"
}

# Wrapper — menu de navegadores (seleção múltipla)
install_browsers_arch() {
    select_and_install_menu "$1" "Navegadores (escolha um ou mais)"
}

# Wrappers do Fedora — mesmos menus, mesma função; só muda o arquivo de lista.
# É esta a razão de todo o backend ter sido tornado agnóstico de distro.
install_optional_apps_fedora() {
    select_and_install_menu "$1" "Aplicativos Opcionais"
}

install_browsers_fedora() {
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
