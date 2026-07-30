#!/usr/bin/env bash
# Biblioteca de instalação de pacotes para Arch Linux
# Melhorias inspiradas no donarch:
#   - Pacotes organizados em arquivos .txt por categoria
#   - Separação automática de pacotes oficiais vs AUR
#   - Uso do AUR helper detectado pelo checks.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ═════════════════════════════════════════════════════════════
# BACKEND DE PACOTES — Arch Linux / CachyOS
#
# Formato aceito nas listas .txt (packages/*.txt):
#   nome                        → pacote nativo (pacman)
#   flatpak:<app-id>            → Flatpak vindo do Flathub
#   curl:<url>                  → instalador oficial do próprio programa
# ═════════════════════════════════════════════════════════════

# O pacote existe no repositório nativo?
pkg_available() {
    pacman -Si "$1" &>/dev/null
}

# Instalar um ou mais pacotes pelo gerenciador nativo.
pkg_install() {
    sudo pacman -S --needed --noconfirm "$@"
}

# O pacote está instalado?
pkg_installed() {
    pacman -Q "$1" &>/dev/null
}

# Instalar um app do Flathub.
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
    esac

    # ── Pacote nativo ────────────────────────────────────────
    if pkg_available "$app"; then
        # Distinguir falha por CONFLITO de uma falha comum: ex.: no
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

    # Não existe nativamente: pode ser AUR.
    if [ "${AUR_HELPER:-none}" != "none" ]; then
        "$AUR_HELPER" -S --needed --noconfirm $(aur_noninteractive_flags) "$app"
        return $?
    fi

    log_warn "  '$app' não está disponível (nem nos repositórios, nem via AUR helper)."
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

# ═════════════════════════════════════════════════════════════
# ARCH — Repositório [multilib] (bibliotecas 32-bit)
#
# Sem ele, 'steam' e qualquer 'lib32-*' simplesmente NÃO EXISTEM para o pacman.
# E isso não produzia um erro claro: pkg_available() falhava, install_entry()
# concluía "não é nativo, então é AUR" e mandava o helper compilar um 'steam'
# que não existe no AUR — o usuário via uma pilha de erros de build sem nenhuma
# relação com a causa real. O comentário em packages/arch-optional.txt avisava
# do requisito, mas o script não fazia nada a respeito.
# ═════════════════════════════════════════════════════════════
multilib_enabled() {
    grep -qE '^[[:space:]]*\[multilib\]' /etc/pacman.conf 2>/dev/null
}

enable_multilib_arch() {
    if multilib_enabled; then
        log_info "Repositório [multilib] já habilitado."
        return 0
    fi

    if ! grep -qE '^[[:space:]]*#[[:space:]]*\[multilib\]' /etc/pacman.conf 2>/dev/null; then
        log_warn "Seção [multilib] não encontrada em /etc/pacman.conf — habilite-a manualmente."
        return 1
    fi

    log_info "Habilitando o repositório [multilib] em /etc/pacman.conf..."
    sudo cp -a /etc/pacman.conf "/etc/pacman.conf.bak-$(date +%Y%m%d_%H%M%S)"

    # awk, e não o 'sed -i "/\[multilib\]/,+1 s/^#//"' que circula pela internet:
    # aquele descomenta a linha SEGUINTE seja ela qual for e, num pacman.conf
    # editado à mão, a linha seguinte costuma ser um comentário explicativo —
    # que viraria diretiva inválida e quebraria o pacman inteiro. Aqui só o
    # cabeçalho [multilib] e o primeiro 'Include' DELE são alterados.
    local tmp
    tmp=$(mktemp)
    awk '
        /^[[:space:]]*#[[:space:]]*\[multilib\][[:space:]]*$/ && !seen {
            print "[multilib]"; in_ml = 1; seen = 1; next
        }
        # Chegou noutra seção sem ter achado o Include — parar de procurar.
        in_ml && /^[[:space:]]*#?[[:space:]]*\[/ { in_ml = 0 }
        in_ml && /^[[:space:]]*#[[:space:]]*Include[[:space:]]*=/ {
            sub(/^[[:space:]]*#[[:space:]]*/, ""); print; in_ml = 0; next
        }
        { print }
    ' /etc/pacman.conf > "$tmp"

    if ! grep -qE '^[[:space:]]*\[multilib\]' "$tmp" \
        || ! grep -qE '^[[:space:]]*Include' "$tmp"; then
        log_warn "Não foi possível habilitar o [multilib] automaticamente — pacman.conf inalterado."
        rm -f "$tmp"
        return 1
    fi

    sudo install -m 644 -o root -g root "$tmp" /etc/pacman.conf
    rm -f "$tmp"

    log_info "Sincronizando a base de dados com o [multilib]..."
    sudo pacman -Syu --noconfirm || log_warn "Falha ao sincronizar após habilitar o [multilib]."
    log_success "Repositório [multilib] habilitado."
    return 0
}

# ═════════════════════════════════════════════════════════════
# ARCH — Drivers de vídeo e aceleração por hardware
#
# O único pacote relacionado nas listas era 'vulkan-icd-loader'
# (arch-libs.txt), que é só o CARREGADOR: sem um ICD (vulkan-radeon /
# vulkan-intel / nvidia-utils) ele não tem o que carregar. Numa instalação
# realmente limpa isso significava Vulkan indisponível e decodificação de
# vídeo por hardware inativa — num ambiente cuja premissa inteira é um
# compositor Wayland acelerado.
# ═════════════════════════════════════════════════════════════

# Retorna um texto com os fornecedores de GPU encontrados (amd/intel/nvidia).
detect_gpu_vendors() {
    local out=""

    if command -v lspci &>/dev/null; then
        out=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)
    fi

    # Sem lspci não dá para desistir: 'pciutils' é opt-in (arch-libs.txt) e numa
    # instalação mínima ainda não está presente justamente quando esta função
    # roda. Fallback: ler os IDs de fornecedor direto do sysfs (classe 0x03 =
    # display controller), que existe em qualquer kernel.
    if [ -z "$out" ]; then
        local dev class vendor
        for dev in /sys/bus/pci/devices/*; do
            [ -r "$dev/class" ] || continue
            class=$(cat "$dev/class" 2>/dev/null || echo "")
            [[ "$class" == 0x03* ]] || continue
            vendor=$(cat "$dev/vendor" 2>/dev/null || echo "")
            case "$vendor" in
                0x1002|0x1022) out+=" amd" ;;
                0x8086)        out+=" intel" ;;
                0x10de)        out+=" nvidia" ;;
            esac
        done
    fi

    printf '%s' "$out"
}

# Dos nomes pedidos, quais existem de fato nos repositórios?
#
# Filtrar é obrigatório e não cosmético: nomes de pacote de driver mudam com o
# tempo (por exemplo 'libva-mesa-driver' e 'mesa-vdpau' foram absorvidos pelo
# próprio 'mesa'). Passar um nome extinto direto ao pacman faz ele abortar a
# transação INTEIRA com "target not found", levando junto os drivers que
# realmente existem — a mesma classe de falha em lote já tratada em
# install_package_list().
_filter_available_pkgs() {
    local p
    for p in "$@"; do
        if pacman -Si "$p" &>/dev/null; then
            printf '%s\n' "$p"
        else
            log_info "  (ignorando '$p' — não existe nos repositórios)" >&2
        fi
    done
}

install_gpu_drivers_arch() {
    local gpu_info
    gpu_info=$(detect_gpu_vendors)

    if [ -z "$gpu_info" ]; then
        log_warn "Nenhuma GPU detectada — drivers de vídeo não serão instalados."
        return 0
    fi

    local is_amd=false is_intel=false is_nvidia=false
    grep -qiE 'amd|ati|radeon' <<< "$gpu_info" && is_amd=true
    grep -qi  'intel'          <<< "$gpu_info" && is_intel=true
    grep -qi  'nvidia'         <<< "$gpu_info" && is_nvidia=true

    local pkgs=(mesa vulkan-icd-loader libva-utils)
    if $is_amd; then
        log_info "  GPU AMD/ATI detectada."
        pkgs+=(vulkan-radeon libva-mesa-driver mesa-vdpau)
    fi
    if $is_intel; then
        log_info "  GPU Intel detectada."
        pkgs+=(vulkan-intel intel-media-driver libva-intel-driver)
    fi

    local available=()
    mapfile -t available < <(_filter_available_pkgs "${pkgs[@]}")

    if [ ${#available[@]} -gt 0 ]; then
        log_info "Instalando drivers de vídeo: ${available[*]}"
        sudo pacman -S --needed --noconfirm "${available[@]}" \
            || log_warn "Falha ao instalar parte dos drivers de vídeo."
    fi

    # Equivalentes 32-bit — sem eles, Steam e Wine caem para renderização por
    # software mesmo com o driver 64-bit correto instalado.
    if multilib_enabled; then
        local lib32=(lib32-mesa)
        $is_amd   && lib32+=(lib32-vulkan-radeon)
        $is_intel && lib32+=(lib32-vulkan-intel)

        local lib32_ok=()
        mapfile -t lib32_ok < <(_filter_available_pkgs "${lib32[@]}")
        if [ ${#lib32_ok[@]} -gt 0 ]; then
            log_info "Instalando drivers 32-bit (multilib): ${lib32_ok[*]}"
            sudo pacman -S --needed --noconfirm "${lib32_ok[@]}" \
                || log_warn "Falha ao instalar os drivers 32-bit."
        fi
    fi

    if $is_nvidia; then
        install_nvidia_driver_arch
    fi

    log_success "Drivers de vídeo configurados."
    return 0
}

# NVIDIA fica FORA do caminho automático de propósito: a escolha entre
# nvidia-open-dkms / nvidia-dkms / nvidia (e o -headers do kernel certo) depende
# do modelo da placa e do kernel instalado, e o pacote errado deixa a máquina
# sem vídeo no próximo boot — exatamente o oposto do que este instalador existe
# para garantir. Por isso é opt-in explícito, com padrão "não".
install_nvidia_driver_arch() {
    log_warn "GPU NVIDIA detectada — o driver proprietário NÃO é instalado automaticamente."
    log_info "  Placas GTX 900 ou mais novas: 'nvidia-open-dkms'."
    log_info "  Placas mais antigas (Kepler/Maxwell 1ª geração): 'nvidia-dkms'."

    if ! prompt_yes_no "Deseja instalar agora o driver aberto da NVIDIA (nvidia-open-dkms)?" "N"; then
        log_info "Driver NVIDIA ignorado. Instale depois com: sudo pacman -S nvidia-open-dkms nvidia-utils"
        return 0
    fi

    # O DKMS precisa dos headers do kernel EM USO. Descobrir o pacote do kernel
    # pelo dono do vmlinuz do kernel corrente cobre linux, linux-lts, linux-zen
    # e os kernels do CachyOS sem manter uma lista fixa que envelheceria.
    local kernel_pkg headers_pkg
    kernel_pkg=$(pacman -Qqo "/usr/lib/modules/$(uname -r)/vmlinuz" 2>/dev/null | head -n1 || true)
    headers_pkg="${kernel_pkg:+${kernel_pkg}-headers}"
    [ -z "$headers_pkg" ] && headers_pkg="linux-headers"

    local nvidia_pkgs=("$headers_pkg" nvidia-open-dkms nvidia-utils egl-wayland libva-nvidia-driver)
    local available=()
    mapfile -t available < <(_filter_available_pkgs "${nvidia_pkgs[@]}")

    if [ ${#available[@]} -eq 0 ]; then
        log_warn "Nenhum pacote NVIDIA disponível nos repositórios — pulando."
        return 1
    fi

    log_info "Instalando: ${available[*]}"
    if sudo pacman -S --needed --noconfirm "${available[@]}"; then
        log_success "Driver NVIDIA instalado."
        # Wayland em NVIDIA exige o modeset do DRM. Versões recentes do
        # nvidia-utils já o ativam por padrão, mas verificar é barato e a falha
        # (sessão Wayland que não inicia) é cara de diagnosticar depois.
        if ! grep -rqs 'nvidia_drm.modeset=1\|options nvidia_drm modeset=1' /etc/modprobe.d /etc/default/grub /etc/kernel 2>/dev/null; then
            log_warn "  Se a sessão Wayland não iniciar, ative o modeset do DRM:"
            log_info  "    echo 'options nvidia_drm modeset=1' | sudo tee /etc/modprobe.d/nvidia.conf"
            log_info  "    sudo mkinitcpio -P   # (ou o gerador de initramfs da sua distro)"
        fi
        return 0
    fi

    log_warn "Falha ao instalar o driver NVIDIA — o sistema seguirá com o driver 'nouveau'."
    return 1
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
                sudo ./cachyos-repo.sh || log_warn "Falha ao executar o script do CachyOS."
            )
            rm -rf "$temp_dir"
            # '|| log_warn': sem a guarda, uma falha aqui dispara o 'set -e' e
            # aborta install_arch_packages() ANTES do SDDM — o cenário que o
            # resto deste arquivo trabalha para evitar.
            sudo pacman -Syu --noconfirm || log_warn "Falha ao atualizar após adicionar os repositórios do CachyOS."
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

    # IMPORTANTE: usar -Syu (nunca apenas -Sy). Um 'pacman -Sy' seguido de instalação
    # é um "partial upgrade" e pode quebrar o sistema (libs novas contra sistema antigo),
    # especialmente em instalações recém-feitas/mínimas.
    #
    # O chaveiro é atualizado IMEDIATAMENTE antes deste -Syu, e não em outro
    # ponto do script: refresh_arch_keyring() usa '-Sy' (única exceção à regra
    # acima), então qualquer coisa instalada entre as duas chamadas seria um
    # partial upgrade. Manter as duas linhas coladas é o que torna isso seguro.
    log_info "Sincronizando a base de dados e atualizando o sistema (evita partial upgrade)..."
    if declare -f refresh_arch_keyring &>/dev/null; then
        refresh_arch_keyring || log_warn "Seguindo com o chaveiro atual."
    fi
    if ! sudo pacman -Syu --noconfirm; then
        log_warn "O 'pacman -Syu' falhou na primeira tentativa."
        log_info  "  Causa mais comum: chaveiro/assinaturas. Reconstruindo e tentando de novo..."
        sudo pacman-key --init     &>/dev/null || true
        sudo pacman-key --populate &>/dev/null || true
        sudo pacman -Syu --noconfirm \
            || log_warn "Atualização do sistema falhou — a instalação segue, mas pacotes podem faltar."
    fi

    # Só DEPOIS de o sistema estar atualizado e com chaveiro válido vale a pena
    # adicionar repositório de terceiros: o script do CachyOS instala pacotes.
    setup_arch_repos

    log_success "Gerenciador de pacotes: pacman | AUR helper: ${AUR_HELPER:-none}"

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
    fi

    # 2b. Drivers de vídeo — antes de fontes/navegadores/opcionais de propósito:
    # sem driver DRM/Mesa funcional o compositor Wayland não sobe, e todo o
    # resto do ambiente fica irrelevante. Fora do 'if' dos essenciais pelo mesmo
    # motivo de install_shell_packages(): numa reinstalação o usuário responde
    # "não" aos essenciais e ficaria sem esta etapa.
    if prompt_yes_no "Deseja detectar a GPU e instalar os drivers de vídeo/aceleração?" "S"; then
        install_gpu_drivers_arch || log_warn "Drivers de vídeo podem não ter sido instalados."
    fi

    # 3. Desktop Shell escolhido (DMS ou Noctalia beta) — FORA do 'if' acima.
    # Motivo: ao reinstalar só para trocar de shell, o caminho natural é
    # responder "não" aos essenciais (já estão instalados). Quando esta chamada
    # ficava dentro do 'if', o shell novo nunca era instalado, embora as configs
    # do Niri já tivessem sido apontadas para ele — resultado: sessão sem shell.
    # É idempotente graças ao '--needed' do pacman.
    install_shell_packages || log_warn "Shell (${SHELL_CHOICE:-dms}) pode não ter sido instalado."

    # 3. Fontes
    if prompt_yes_no "Deseja instalar as fontes do ambiente (Noto, Cantarell, Meslo Nerd)?" "S"; then
        install_package_list "$pkg_dir/arch-fonts.txt" "Fontes"
    fi

    # Tema de cursor declarado em dotfiles/niri/cfg/misc.kdl.
    install_cursor_theme || true

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

    # 7. Ferramentas de empacotamento (AppImage / deb / rpm / pacman).
    # Opt-in: só faz sentido para quem BUILDA programas nesta máquina.
    if prompt_yes_no "Deseja instalar as ferramentas para empacotar programas (AppImage, deb, rpm, pacman)?" "S"; then
        install_package_list "$pkg_dir/arch-devtools.txt" "Ferramentas de empacotamento"
    fi

    # 8. Apps opcionais — apresentar menu de escolha
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
        # Remover espaços em branco nas pontas.
        # Feito com expansão do próprio bash, e não com 'xargs': o xargs
        # interpreta aspas e apóstrofos do texto. Um rótulo em português como
        # "Editor do usuário's" era truncado para "Editor do", e aspas sem par
        # chegavam a fazer o xargs falhar — corrompendo silenciosamente o nome
        # do pacote ou o rótulo exibido no menu.
        pkg="${pkg#"${pkg%%[![:space:]]*}"}"       ; pkg="${pkg%"${pkg##*[![:space:]]}"}"
        label="${label#"${label%%[![:space:]]*}"}" ; label="${label%"${label##*[![:space:]]}"}"

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

    local choices
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

    # Alguns itens SÓ existem no repositório [multilib] (32-bit). Habilitar sob
    # demanda, em vez de perguntar antes: quem nunca escolhe Steam/Wine não
    # ganha um prompt a mais, e quem escolhe não recebe o erro confuso de
    # "compilar steam do AUR" descrito em enable_multilib_arch().
    if ! multilib_enabled; then
        local needs_multilib=false
        for app in "${selected[@]}"; do
            case "$app" in
                steam|lib32-*|wine|wine-*|winetricks|lutris|bottles) needs_multilib=true ;;
            esac
        done
        if $needs_multilib; then
            log_info "Item selecionado requer bibliotecas 32-bit — habilitando o [multilib]..."
            enable_multilib_arch || log_warn "  Sem o [multilib], esse item não poderá ser instalado."
        fi
    fi

    # A instalação de cada item é delegada a install_entry(), que resolve o
    # prefixo (nativo / flatpak: / curl:).
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

# ─────────────────────────────────────────────────────────────
# UTILITÁRIO: Instalar o tema de cursor (padrão: Bibata-Original-Amber)
#
# O nome do tema vem de $CURSOR_THEME (lib/utils.sh) — não escreva o nome
# à mão aqui, veja lá o histórico de divergência entre os configs.
#
# Origens, em ordem de preferência:
#   1. AUR 'bibata-cursor-theme-bin' — recomendado pelo próprio projeto: são
#      cursores pré-compilados, então instala em segundos. O 'bibata-cursor-
#      theme' (sem -bin) renderiza os SVGs na hora, o que leva MUITOS minutos
#      e puxa toolchain de build — péssimo dentro de um instalador.
#   2. AUR 'bibata-cursor-theme' — fallback se o -bin não estiver disponível.
#   3. Tarball do release oficial no GitHub (ful1e5/Bibata_Cursor), para quem
#      não tem AUR helper. Mesmo padrão de install_meslo_font().
#
# Os pacotes do AUR instalam TODAS as variantes de uma vez em
# /usr/share/icons (Modern/Original × Amber/Classic/Ice, + as '-Right');
# o tarball traz só a variante pedida, para ~/.local/share/icons.
# ─────────────────────────────────────────────────────────────
install_cursor_theme() {
    local theme="${CURSOR_THEME:-Bibata-Original-Amber}"
    local icons_dir
    icons_dir="$(get_user_home)/.local/share/icons"

    if [ -d "$icons_dir/$theme" ] || [ -d "/usr/share/icons/$theme" ]; then
        log_info "Tema de cursor $theme já presente."
        return 0
    fi

    # Preferir o pacote AUR (recebe atualização junto com o sistema).
    if [ "${AUR_HELPER:-none}" != "none" ]; then
        local aur_pkg
        for aur_pkg in bibata-cursor-theme-bin bibata-cursor-theme; do
            log_info "Instalando o tema de cursor $theme via AUR ($aur_pkg)..."
            if "$AUR_HELPER" -S --needed --noconfirm $(aur_noninteractive_flags) "$aur_pkg"; then
                # Confirmar que a VARIANTE pedida veio junto: os pacotes trazem
                # o conjunto completo, mas se um dia isso mudar, é melhor cair
                # para o tarball do que declarar sucesso e ficar sem o tema.
                if [ -d "/usr/share/icons/$theme" ]; then
                    log_success "Tema de cursor $theme instalado via AUR ($aur_pkg)."
                    return 0
                fi
                log_warn "  '$aur_pkg' instalado, mas a variante $theme não apareceu em /usr/share/icons."
            fi
            log_warn "  Falha com '$aur_pkg'."
        done
        log_warn "  Nenhum pacote AUR funcionou — tentando o tarball oficial."
    fi

    log_info "Instalando o tema de cursor $theme (release oficial)..."
    local temp_dir
    temp_dir=$(mktemp -d)
    # 'releases/latest/download' segue sempre a versão mais recente, sem fixar
    # um número de versão que envelheceria dentro do repositório.
    local url="https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/${theme}.tar.xz"

    if curl -fLo "$temp_dir/cursor.tar.xz" "$url" && tar -xf "$temp_dir/cursor.tar.xz" -C "$temp_dir"; then
        mkdir -p "$icons_dir"
        cp -a "$temp_dir/$theme" "$icons_dir/"
        rm -rf "$temp_dir"
        log_success "Tema de cursor $theme instalado em $icons_dir."
        return 0
    fi

    rm -rf "$temp_dir"
    log_warn "Falha ao instalar o tema de cursor — o sistema usará o cursor padrão."
    return 1
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
