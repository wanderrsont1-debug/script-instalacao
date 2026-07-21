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

        # 'noctalia' NÃO vai para ~/.config: o Noctalia 5.x lê o settings.toml
        # de ~/.local/state/noctalia/. Copiar para cá criaria um diretório que
        # o shell nunca lê, dando a impressão de que a config foi aplicada.
        # Quem implanta esse arquivo é deploy_noctalia_config().
        if [ "$name" = "noctalia" ]; then
            continue
        fi

        # O DankMaterialShell só é relevante se o DMS for o shell escolhido.
        if [ "$name" = "DankMaterialShell" ] && [ "${SHELL_CHOICE:-dms}" != "dms" ]; then
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
    #
    #    A lista é derivada do próprio dotfiles/ em vez de ser fixa: antes, um
    #    diretório novo adicionado ao repositório era implantado mas ficava
    #    pertencendo ao root, e só se descobria quando o app não conseguia
    #    salvar a própria configuração.
    log_info "Ajustando propriedade dos arquivos para o usuário $real_user..."
    for item in "$dotfiles_src"/*; do
        [ -e "$item" ] || continue
        local dname
        dname=$(basename "$item")
        # 'noctalia' não vai para ~/.config (o Noctalia usa ~/.local/state);
        # quem cuida dele é deploy_noctalia_config().
        # 'if' explícito em vez de '[ ... ] && continue': na forma com && o
        # teste falso deixa a lista com status 1 e, sem o '|| log_warn' do
        # chamador, o 'set -e' abortaria o instalador aqui.
        if [ "$dname" = "noctalia" ]; then
            continue
        fi
        [ -e "$config_dir/$dname" ] || continue
        chown -R "$real_user":"$real_user" "$config_dir/$dname" 2>/dev/null || true
    done
    # Arquivos raiz do home
    for hfile in .bashrc .zshrc .bash_profile .Xresources; do
        [ -f "$user_home/$hfile" ] && chown "$real_user":"$real_user" "$user_home/$hfile" || true
    done

    log_success "Dotfiles implantados com sucesso (cópia real de arquivos)!"
    log_info  "O repositório clonado pode ser removido com segurança após a instalação."
}

# ═════════════════════════════════════════════════════════════
# AGENTE POLKIT — por que este código existe
#
# Os DOIS shells suportados trazem agente polkit próprio:
#   • Noctalia 5.x → "[shell] polkit_agent = true" no settings.toml, e um
#     painel dedicado ('noctalia msg panel-toggle polkit').
#   • DMS         → /usr/share/quickshell/dms/Services/PolkitService.qml.
# Rodar um agente externo em paralelo faz os dois disputarem o mesmo nome no
# D-Bus; o perdedor registra "An authentication agent already exists for the
# given subject" e o diálogo de senha que aparece passa a depender de quem
# venceu a corrida no login.
#
# CORREÇÃO DE DIAGNÓSTICO (versão anterior deste arquivo estava errada):
# afirmava-se aqui que o agente instalado nos essenciais (mate-polkit no
# Fedora, polkit-gnome no Arch) era iniciado automaticamente por
# /etc/xdg/autostart sob o Niri. Isso é FALSO no caso do Fedora: o
# .desktop do mate-polkit tem "OnlyShowIn=MATE" (o do lxpolkit, "OnlyShowIn=
# LXDE"), e com XDG_CURRENT_DESKTOP=niri o gerador XDG do systemd
# corretamente NÃO os inicia — verificável com
# 'systemctl --user list-units app-*@autostart.service'.
#
# A causa real de conflito observada foi um 'spawn-at-startup' de agente
# polkit adicionado à mão na config do niri, e o 'exec_cmd' fixo que existia
# no hyprland.lua (este último removido). Por isso:
#   1. os essenciais não instalam mais agente polkit externo algum;
#   2. verify_niri_environment() avisa se sobrar um spawn-at-startup desses;
#   3. a função abaixo cobre o caso restante — um agente de terceiros cujo
#      .desktop REALMENTE se aplique a esta sessão (sem OnlyShowIn, ou com
#      OnlyShowIn incluindo o nosso compositor).
# ═════════════════════════════════════════════════════════════

# Este .desktop de autostart seria executado no compositor alvo?
# Implementa as regras OnlyShowIn/NotShowIn da spec XDG Autostart.
_autostart_applies_to_desktop() {
    local file="$1"
    local desktop="$2"
    local only_show not_show

    only_show=$(grep -m1 '^OnlyShowIn=' "$file" 2>/dev/null | cut -d= -f2- || true)
    not_show=$(grep  -m1 '^NotShowIn='  "$file" 2>/dev/null | cut -d= -f2- || true)

    if [ -n "$only_show" ]; then
        printf '%s' "$only_show" | tr ';' '\n' | grep -qix "$desktop" || return 1
    fi
    if [ -n "$not_show" ]; then
        printf '%s' "$not_show" | tr ';' '\n' | grep -qix "$desktop" && return 1
    fi
    return 0
}

# Nome do compositor como ele aparece em XDG_CURRENT_DESKTOP.
_target_desktop_id() {
    if [ "${COMPOSITOR_CHOICE:-niri}" = "hyprland" ]; then
        echo "Hyprland"
    else
        echo "niri"
    fi
}

# Desativa, só para este usuário, agentes polkit de terceiros que de fato
# subiriam nesta sessão. Não desinstala nada: escreve um .desktop de mesmo
# nome em ~/.config/autostart com Hidden=true (mecanismo padrão do XDG).
disable_external_polkit_agent() {
    local user_home="$1"
    local autostart_dir="$user_home/.config/autostart"
    local system_autostart="/etc/xdg/autostart"
    local desktop_id
    desktop_id=$(_target_desktop_id)

    [ -d "$system_autostart" ] || return 0

    local disabled_any=0
    local desktop_file base
    for desktop_file in "$system_autostart"/*.desktop; do
        [ -f "$desktop_file" ] || continue

        # Detecta pelo Exec=, não por nome de pacote: nos .desktop reais do
        # Fedora 44 o nome do pacote não aparece no Exec= (mate-polkit instala
        # 'polkit-mate-authentication-agent-1.desktop' com
        # Exec=/usr/libexec/polkit-mate-authentication-agent-1).
        grep -qiE '^Exec=.*(polkit|policykit)' "$desktop_file" 2>/dev/null || continue

        # Se o próprio .desktop já se exclui desta sessão, não há o que fazer:
        # criar um override aqui só geraria arquivo inútil e a impressão falsa
        # de que algo foi corrigido.
        if ! _autostart_applies_to_desktop "$desktop_file" "$desktop_id"; then
            continue
        fi

        base=$(basename "$desktop_file")
        mkdir -p "$autostart_dir"
        {
            echo "[Desktop Entry]"
            echo "Hidden=true"
            echo "X-Niri-Installer-Note=Desativado pelo instalador: o shell escolhido ja traz agente polkit proprio. Apague este arquivo para reativar."
        } > "$autostart_dir/$base"
        log_info "  Agente polkit externo desativado no autostart: $base"
        disabled_any=1
    done

    if [ "$disabled_any" -eq 1 ]; then
        local real_user
        real_user=$(detect_user)
        chown -R "$real_user":"$real_user" "$autostart_dir" 2>/dev/null || true
    fi
    return 0
}

# Reverte disable_external_polkit_agent(): remove SÓ os overrides que este
# instalador criou (marcados com X-Niri-Installer-Note), preservando qualquer
# override manual do usuário.
enable_external_polkit_agent() {
    local user_home="$1"
    local autostart_dir="$user_home/.config/autostart"
    [ -d "$autostart_dir" ] || return 0

    local f
    for f in "$autostart_dir"/*.desktop; do
        [ -f "$f" ] || continue
        if grep -q "^X-Niri-Installer-Note=" "$f" 2>/dev/null; then
            log_info "  Removendo override de autostart criado pelo instalador: $(basename "$f")"
            rm -f "$f"
        fi
    done
    return 0
}

# ─────────────────────────────────────────────────────────────
# Implantar a configuração base do Noctalia.
#
# O Noctalia 5.x guarda o estado em ~/.local/state/noctalia/ — NÃO em
# ~/.config/noctalia (que fica vazio). Sem este passo, quem instalava pelo
# script caía no assistente inicial com barra/tema padrão, enquanto uma
# instalação manual "de verdade" já vinha ajustada: era a maior diferença
# entre os dois caminhos.
#
# NUNCA sobrescreve um settings.toml existente — reinstalar é o fluxo de
# atualização deste projeto e apagaria os ajustes feitos pela interface.
# ─────────────────────────────────────────────────────────────
deploy_noctalia_config() {
    local repo_dir="$1"
    local user_home="$2"
    local src="$repo_dir/dotfiles/noctalia/settings.toml"
    local state_dir="$user_home/.local/state/noctalia"
    local dst="$state_dir/settings.toml"

    [ -f "$src" ] || { log_warn "Config base do Noctalia não encontrada em $src"; return 0; }

    if [ -e "$dst" ]; then
        log_info "Config do Noctalia já existe ($dst) — preservada como está."
        return 0
    fi

    log_info "Implantando configuração base do Noctalia em $dst..."
    mkdir -p "$state_dir"
    cp -a "$src" "$dst"

    # Marca de "assistente inicial concluído": sem ela o Noctalia abre o
    # setup-wizard por cima da config que acabamos de aplicar.
    touch "$state_dir/.setup-complete"

    local real_user
    real_user=$(detect_user)
    chown -R "$real_user":"$real_user" "$state_dir" 2>/dev/null || true
    log_success "Configuração base do Noctalia aplicada."
    return 0
}

# ─────────────────────────────────────────────────────────────
# Ajustes de shell que valem para QUALQUER compositor.
#
# Fica separado de apply_shell_config() (que é específico do Niri, pois mexe
# em includes .kdl): com Hyprland o shell é sempre o Noctalia e estas mesmas
# providências continuam necessárias.
# ─────────────────────────────────────────────────────────────
apply_shell_common() {
    local repo_dir="$1"
    local user_home
    user_home=$(get_user_home)

    if [ "${SHELL_CHOICE:-dms}" = "noctalia" ]; then
        disable_external_polkit_agent "$user_home"
        deploy_noctalia_config "$repo_dir" "$user_home"
    else
        enable_external_polkit_agent "$user_home"
    fi
    return 0
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

    if [ ! -d "$cfg_dir" ]; then
        log_warn "Diretório de config do Niri não encontrado ($cfg_dir) — pulando seleção de shell."
        return 0
    fi

    # Escrever o include diretamente (em vez de 'sed' sobre o conteúdo antigo):
    # funciona independente do estado anterior dos arquivos — mesmo se uma
    # execução passada tiver sido interrompida no meio e deixado os includes
    # apontando para o shell errado.
    local suffix="dms"
    [ "$choice" = "noctalia" ] && suffix="noctalia"

    # Os três pares de include trocados por shell. 'shell-extra' foi acrescentado
    # para que os fragmentos gerados pelo DMS (dms/*.kdl) deixem de ser
    # carregados quando o shell escolhido é o Noctalia.
    local switchable=(autostart keybinds shell-extra)

    log_info "Configurando o Niri para usar o shell: ${choice}..."
    local base missing=0
    for base in "${switchable[@]}"; do
        echo "include \"./${base}-${suffix}.kdl\"" > "$cfg_dir/${base}.kdl"
        if [ ! -f "$cfg_dir/${base}-${suffix}.kdl" ]; then
            log_error "Arquivo de config do shell ausente: $cfg_dir/${base}-${suffix}.kdl"
            missing=1
        fi
    done

    if [ "$missing" -eq 0 ]; then
        log_success "Niri apontado para os configs do ${choice} (autostart + keybinds + fragmentos)."
    fi

    # Ajustar propriedade (caso rodando via sudo)
    local real_user
    real_user=$(detect_user)
    for base in "${switchable[@]}"; do
        chown "$real_user":"$real_user" "$cfg_dir/${base}.kdl" 2>/dev/null || true
    done
    return 0
}
