#!/usr/bin/env bash
# Biblioteca de implantação de dotfiles (via cópia real de arquivos)
# Não utiliza links simbólicos — a instalação é independente do repositório.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ─────────────────────────────────────────────────────────────
# Fazer backup de arquivo/diretório original se existir
# Ignora links simbólicos herdados de instalações anteriores
# ─────────────────────────────────────────────────────────────
backup_item() {
    local target="$1"
    local max_backups=3

    if [ -e "$target" ] && [ ! -L "$target" ]; then
        # Backup COM TIMESTAMP (antes era um '.bak' de nome fixo).
        # Com o nome fixo, reinstalar destruía o backup original: na 1ª execução
        # o .bashrc do usuário virava .bashrc.bak; na 2ª, o .bashrc JÁ SUBSTITUÍDO
        # pelo script sobrescrevia esse mesmo .bak e o original sumia para sempre.
        # Como reinstalar é o fluxo de atualização recomendado deste projeto,
        # isso acontecia na prática.
        local backup="${target}.bak-$(date +%Y%m%d_%H%M%S)"
        log_warn "Fazendo backup de $target para $backup"
        mv "$target" "$backup"

        # Rotação: não acumular um backup novo a cada reinstalação.
        #
        # O MAIS ANTIGO é preservado para sempre e nunca entra na rotação: ele
        # é o arquivo pristino, de antes de o instalador rodar pela primeira
        # vez — justamente o mais valioso para recuperar. Rotacionar por data
        # pura o eliminaria primeiro, que é o oposto do que se quer.
        # Dos demais, mantemos apenas os mais recentes.
        local all_backups
        mapfile -t all_backups < <(
            find "$(dirname "$target")" -maxdepth 1 -name "$(basename "$target").bak-*" 2>/dev/null | sort
        )
        if [ "${#all_backups[@]}" -gt "$max_backups" ]; then
            # Descarta o índice 0 (o pristino) e os (max_backups-1) mais novos;
            # o que sobra no meio é removido.
            local candidates=("${all_backups[@]:1}")
            local to_remove=("${candidates[@]:0:${#candidates[@]}-(max_backups-1)}")
            for old in "${to_remove[@]}"; do
                [ -n "$old" ] && rm -rf "$old"
            done
        fi
    elif [ -L "$target" ]; then
        # Remover link simbólico de instalação anterior sem aviso extra
        log_info "Removendo link simbólico legado: $target"
        rm -f "$target"
    fi
}

# ─────────────────────────────────────────────────────────────
# Copiar arquivo ou diretório para o destino
#   - Garante que o diretório pai existe
#   - Faz backup do destino se já existir como arquivo/dir real
#   - Remove link simbólico legado se houver
#   - Usa 'cp -a' para preservar permissões, timestamps e atributos
# ─────────────────────────────────────────────────────────────
copy_item() {
    local source="$1"
    local target="$2"

    # Criar diretório pai do destino se não existir
    local target_parent_dir
    target_parent_dir=$(dirname "$target")
    mkdir -p "$target_parent_dir"

    # Fazer backup/remover destino existente
    backup_item "$target"

    if [ -d "$source" ]; then
        # Copiar diretório inteiro preservando permissões e atributos
        log_info "Copiando diretório $(basename "$source") -> $target"
        cp -a "$source" "$target"
    else
        # Copiar arquivo simples preservando permissões e atributos
        log_info "Copiando arquivo $(basename "$source") -> $target"
        cp -a "$source" "$target"
    fi
}

# ─────────────────────────────────────────────────────────────
# Implantar todos os dotfiles do repositório (sem symlinks)
# ─────────────────────────────────────────────────────────────
deploy_dotfiles() {
    local repo_dir="$1"
    local user_home
    user_home=$(get_user_home)   # detect_user() garante o home correto mesmo via sudo
    local config_dir="$user_home/.config"

    log_info "Iniciando implantação de arquivos de configuração (dotfiles)..."

    local dotfiles_src="$repo_dir/dotfiles"
    if [ ! -d "$dotfiles_src" ]; then
        log_error "Diretório de dotfiles não encontrado em $repo_dir/dotfiles."
        return 1
    fi

    # Garantir que o diretório ~/.config existe
    mkdir -p "$config_dir"

    # Compositor escolhido — implantamos APENAS os dotfiles do compositor
    # selecionado (niri OU hypr), evitando poluir ~/.config com a config do outro.
    local compositor="${COMPOSITOR_CHOICE:-niri}"

    # 1. Copiar pastas e arquivos que vão para ~/.config/
    for item in "$dotfiles_src"/*; do
        [ -e "$item" ] || continue
        local name
        name=$(basename "$item")

        # Pular o diretório do compositor NÃO escolhido.
        if [ "$name" = "niri" ] && [ "$compositor" != "niri" ]; then
            continue
        fi
        if [ "$name" = "hypr" ] && [ "$compositor" != "hyprland" ]; then
            continue
        fi

        # Ignorar arquivos que vão para a raiz do $HOME (tratados no passo 2)
        if [[ "$name" != .bashrc && "$name" != .zshrc && "$name" != .bash_profile && "$name" != .Xresources ]]; then
            copy_item "$item" "$config_dir/$name"
        fi
    done

    # 2. Copiar arquivos que vão para a raiz do $HOME
    for file in .bashrc .zshrc .bash_profile .Xresources; do
        if [ -f "$dotfiles_src/$file" ]; then
            copy_item "$dotfiles_src/$file" "$user_home/$file"
        fi
    done

    # 3. Corrigir caminhos hardcoded nos arquivos de configuração copiados
    #    Busca recursiva por /home/wanderson em arquivos de texto (JSON, kdl, fish, etc.)
    #    e substitui pelo home real do usuário.
    log_info "Corrigindo caminhos hardcoded nos arquivos de configuração instalados..."
    local target_dirs=(
        "$config_dir/DankMaterialShell"
        "$config_dir/fish"
        "$config_dir/niri"
        "$config_dir/hypr"
    )
    for dir in "${target_dirs[@]}"; do
        if [ -d "$dir" ]; then
            # grep -rl: lista apenas arquivos que contêm o padrão (sem imprimir linhas)
            # xargs sed -i: substitui in-place em cada arquivo encontrado
            #
            # '|| true' é OBRIGATÓRIO: quando um diretório não contém nenhum
            # caminho hardcoded, o grep retorna 1 e — com 'set -e' + 'set -o
            # pipefail' ativos — o instalador inteiro MORRIA silenciosamente
            # aqui, antes de configurar o shell escolhido, o tema e o SDDM.
            # (Era exatamente este o bug do "SDDM nunca instala".)
            grep -rl --null "/home/wanderson" "$dir" 2>/dev/null \
                | xargs -0 --no-run-if-empty sed -i "s|/home/wanderson|${user_home}|g" || true
        fi
    done

    # 4. Definir o Shell padrão como fish se ele estiver instalado
    #    Comparação feita contra o shell registrado em /etc/passwd (não $SHELL,
    #    que reflete apenas o processo atual e pode estar desatualizado/errado
    #    se o script for executado de dentro de um shell aninhado).
    local real_user
    real_user=$(detect_user)

    if command -v fish &>/dev/null; then
        local fish_path current_shell
        fish_path=$(command -v fish)
        current_shell=$(getent passwd "$real_user" | cut -d: -f7)
        if [ "$current_shell" != "$fish_path" ]; then
            log_info "Definindo fish como shell padrão para o usuário $real_user..."
            if sudo chsh -s "$fish_path" "$real_user"; then
                log_success "Shell padrão alterado para fish."
            else
                log_warn "Falha ao alterar o shell padrão para fish. Rode manualmente: sudo chsh -s $fish_path $real_user"
            fi
        fi
    fi

    # 5. Ajustar propriedade dos arquivos copiados para o usuário correto
    #    (necessário quando o script é chamado via sudo — cp -a preserva o dono root)
    log_info "Ajustando propriedade dos arquivos para o usuário $real_user..."
    chown -R "$real_user":"$real_user" \
        "$config_dir/niri" \
        "$config_dir/hypr" \
        "$config_dir/DankMaterialShell" \
        "$config_dir/alacritty" \
        "$config_dir/cava" \
        "$config_dir/environment.d" \
        "$config_dir/fish" \
        "$config_dir/fuzzel" \
        "$config_dir/ghostty" \
        "$config_dir/micro" \
        2>/dev/null || true
    # Arquivos raiz do home
    for hfile in .bashrc .zshrc .bash_profile .Xresources; do
        [ -f "$user_home/$hfile" ] && chown "$real_user":"$real_user" "$user_home/$hfile" || true
    done

    log_success "Dotfiles implantados com sucesso (cópia real de arquivos)!"
    log_info  "O repositório clonado pode ser removido com segurança após a instalação."
}

# ─────────────────────────────────────────────────────────────
# Noctalia Shell (5.x) traz agente polkit próprio, ligado por padrão
# ([shell] polkit_agent = true em settings.toml — confirmado no
# settings.toml gerado por uma instalação real do Noctalia 5.0.0-beta.3).
# A documentação oficial (noctalia.dev/plugins/polkit-agent) é explícita:
# é preciso desativar qualquer outro agente polkit (polkit-gnome,
# mate-polkit, lxpolkit, ...) ou os dois disputam o mesmo nome D-Bus.
#
# Isso acontece de verdade neste projeto: o agente externo instalado nos
# essenciais (mate-polkit no Fedora, polkit-gnome no Arch) é iniciado
# automaticamente via /etc/xdg/autostart/*.desktop pelo systemd --user
# (xdg-desktop-autostart.target), na frente do agente do Noctalia. O
# resultado observado é o log do Noctalia repetindo, em loop:
#   "polkit agent disabled: ... An authentication agent already exists"
# — ou seja, o diálogo de autenticação que aparece é sempre o do agente
# externo (com tema/estilo inconsistente), nunca o do Noctalia, e depende
# de qual dos dois venceu a corrida no login.
#
# A correção não desinstala o pacote do agente externo (ele continua
# disponível como fallback fora de uma sessão Niri/Hyprland) — apenas
# desativa sua entrada de autostart por usuário, do jeito padrão do XDG:
# um .desktop de mesmo nome em ~/.config/autostart com Hidden=true.
#
# A detecção usa "Exec=.*polkit" (case-insensitive, cobrindo também
# "policykit") em vez de uma lista fixa de nomes de pacote — checado nos
# .rpm reais do Fedora 44, o nome do pacote quase nunca aparece no Exec=:
#   mate-polkit  -> arquivo polkit-mate-authentication-agent-1.desktop,
#                   Exec=/usr/libexec/polkit-mate-authentication-agent-1
#   lxpolkit     -> arquivo lxpolkit.desktop, Exec=lxpolkit
# Uma lista de nomes de pacote (ex.: "mate-polkit") não bateria com nenhum
# dos dois — o padrão genérico por "polkit"/"policykit" no Exec= cobre
# esses casos e qualquer outro agente (polkit-gnome no Arch, KDE, XFCE,
# LXQt) sem precisar manter uma lista.
# ─────────────────────────────────────────────────────────────
disable_external_polkit_agent() {
    local user_home="$1"
    local autostart_dir="$user_home/.config/autostart"
    local system_autostart="/etc/xdg/autostart"

    [ -d "$system_autostart" ] || return 0

    local disabled_any=0
    local desktop_file base
    for desktop_file in "$system_autostart"/*.desktop; do
        [ -f "$desktop_file" ] || continue
        base=$(basename "$desktop_file")
        if grep -qiE '^Exec=.*(polkit|policykit)' "$desktop_file" 2>/dev/null; then
            mkdir -p "$autostart_dir"
            {
                echo "[Desktop Entry]"
                echo "Hidden=true"
                echo "X-Niri-Installer-Note=Desativado automaticamente: o Noctalia Shell ja usa o proprio agente polkit (polkit_agent=true). Apague este arquivo para reativar."
            } > "$autostart_dir/$base"
            log_info "  Agente polkit externo desativado no autostart: $base (Noctalia usa o próprio)"
            disabled_any=1
        fi
    done

    if [ "$disabled_any" -eq 1 ]; then
        local real_user
        real_user=$(detect_user)
        chown -R "$real_user":"$real_user" "$autostart_dir" 2>/dev/null || true
    fi
}

# Reverte disable_external_polkit_agent(): remove só os overrides que NÓS
# criamos (identificados pela marca X-Niri-Installer-Note), preservando
# qualquer override manual do próprio usuário. Necessário para reinstalar
# trocando de Noctalia para DMS sem deixar o usuário sem agente polkit algum
# (DMS não teve o mesmo comportamento de agente embutido confirmado aqui).
enable_external_polkit_agent() {
    local user_home="$1"
    local autostart_dir="$user_home/.config/autostart"
    [ -d "$autostart_dir" ] || return 0

    local f
    for f in "$autostart_dir"/*.desktop; do
        [ -f "$f" ] || continue
        if grep -q "^X-Niri-Installer-Note=" "$f" 2>/dev/null; then
            log_info "  Reativando agente polkit externo (shell DMS selecionado): $(basename "$f")"
            rm -f "$f"
        fi
    done
}

# ─────────────────────────────────────────────────────────────
# Selecionar o Desktop Shell nos configs do Niri já implantados.
# O padrão dos dotfiles aponta para o DMS (includes "*-dms.kdl").
# Se o usuário escolheu Noctalia, trocamos os includes para "*-noctalia.kdl".
# Depende de SHELL_CHOICE (dms|noctalia).
# ─────────────────────────────────────────────────────────────
apply_shell_config() {
    local choice="${SHELL_CHOICE:-dms}"
    local user_home
    user_home=$(get_user_home)
    local cfg_dir="$user_home/.config/niri/cfg"
    local autostart="$cfg_dir/autostart.kdl"
    local keybinds="$cfg_dir/keybinds.kdl"

    if [ "$choice" = "noctalia" ]; then
        disable_external_polkit_agent "$user_home"
    else
        enable_external_polkit_agent "$user_home"
    fi

    if [ ! -d "$cfg_dir" ]; then
        log_warn "Diretório de config do Niri não encontrado ($cfg_dir) — pulando seleção de shell."
        return 0
    fi

    # Escrever o include diretamente (em vez de 'sed' sobre o conteúdo antigo):
    # funciona independente do estado anterior dos arquivos — mesmo se uma
    # execução passada tiver sido interrompida no meio e deixado o par
    # autostart/keybinds apontando para o shell errado.
    local suffix="dms"
    [ "$choice" = "noctalia" ] && suffix="noctalia"

    log_info "Configurando o Niri para usar o shell: ${choice}..."
    echo "include \"./autostart-${suffix}.kdl\"" > "$autostart"
    echo "include \"./keybinds-${suffix}.kdl\""  > "$keybinds"

    # Confirmar que os arquivos-alvo dos includes existem
    local missing=0
    for f in "$cfg_dir/autostart-${suffix}.kdl" "$cfg_dir/keybinds-${suffix}.kdl"; do
        if [ ! -f "$f" ]; then
            log_error "Arquivo de config do shell ausente: $f"
            missing=1
        fi
    done
    if [ "$missing" -eq 0 ]; then
        log_success "Niri apontado para os configs do ${choice} (autostart + keybinds)."
    fi

    # Ajustar propriedade (caso rodando via sudo)
    local real_user
    real_user=$(detect_user)
    chown "$real_user":"$real_user" "$autostart" "$keybinds" 2>/dev/null || true
    return 0
}
