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
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        local backup="${target}.bak"
        log_warn "Fazendo backup de $target para $backup"
        rm -rf "$backup"
        mv "$target" "$backup"
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

    # 1. Copiar pastas e arquivos que vão para ~/.config/
    for item in "$dotfiles_src"/*; do
        [ -e "$item" ] || continue
        local name
        name=$(basename "$item")

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
    )
    for dir in "${target_dirs[@]}"; do
        if [ -d "$dir" ]; then
            # grep -rl: lista apenas arquivos que contêm o padrão (sem imprimir linhas)
            # xargs sed -i: substitui in-place em cada arquivo encontrado
            grep -rl --null "/home/wanderson" "$dir" 2>/dev/null \
                | xargs -0 --no-run-if-empty sed -i "s|/home/wanderson|${user_home}|g"
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

    if [ ! -d "$cfg_dir" ]; then
        log_warn "Diretório de config do Niri não encontrado ($cfg_dir) — pulando seleção de shell."
        return 0
    fi

    if [ "$choice" = "noctalia" ]; then
        log_info "Configurando o Niri para usar o Noctalia Shell..."
        [ -f "$autostart" ] && sed -i 's|autostart-dms\.kdl|autostart-noctalia.kdl|g' "$autostart"
        [ -f "$keybinds" ]  && sed -i 's|keybinds-dms\.kdl|keybinds-noctalia.kdl|g'   "$keybinds"
        log_success "Niri apontado para os configs do Noctalia (autostart + keybinds)."
    else
        log_info "Configurando o Niri para usar o DankMaterialShell (DMS)..."
        # Garante o estado DMS mesmo se os arquivos vierem de uma execução anterior com Noctalia.
        [ -f "$autostart" ] && sed -i 's|autostart-noctalia\.kdl|autostart-dms.kdl|g' "$autostart"
        [ -f "$keybinds" ]  && sed -i 's|keybinds-noctalia\.kdl|keybinds-dms.kdl|g'   "$keybinds"
        log_success "Niri apontado para os configs do DMS (autostart + keybinds)."
    fi

    # Ajustar propriedade (caso rodando via sudo)
    local real_user
    real_user=$(detect_user)
    chown "$real_user":"$real_user" "$autostart" "$keybinds" 2>/dev/null || true
}
