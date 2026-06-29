#!/usr/bin/env bash
# Biblioteca de implantação de dotfiles (via links simbólicos)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Fazer backup de arquivo/diretório original se existir e não for link
backup_item() {
    local target="$1"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        local backup="${target}.bak"
        log_warn "Fazendo backup de $target para $backup"
        rm -rf "$backup"
        mv "$target" "$backup"
    fi
}

# Criar link simbólico
create_symlink() {
    local source="$1"
    local target="$2"
    
    # Criar diretório pai do destino se não existir
    local target_parent_dir
    target_parent_dir=$(dirname "$target")
    mkdir -p "$target_parent_dir"
    
    # Fazer backup se o destino já existir e for arquivo real/diretório real
    backup_item "$target"
    
    # Remover link simbólico antigo se houver
    if [ -L "$target" ]; then
        rm -f "$target"
    fi
    
    # Criar o link simbólico
    log_info "Vinculando $(basename "$source") -> $target"
    ln -sf "$source" "$target"
}

# Implantar todos os dotfiles do repositório
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
    
    # 1. Vincular pastas e arquivos que vão para ~/.config/
    for item in "$dotfiles_src"/*; do
        [ -e "$item" ] || continue
        local name
        name=$(basename "$item")
        
        # Ignorar arquivos que vão para a raiz do $HOME
        if [[ "$name" != .bashrc && "$name" != .zshrc && "$name" != .bash_profile && "$name" != .Xresources ]]; then
            create_symlink "$item" "$config_dir/$name"
        fi
    done
    
    # 2. Vincular arquivos que vão para a raiz do $HOME
    for file in .bashrc .zshrc .bash_profile .Xresources; do
        if [ -f "$dotfiles_src/$file" ]; then
            create_symlink "$dotfiles_src/$file" "$user_home/$file"
        fi
    done
    
    # 3. Definir o Shell padrão como fish se ele estiver instalado
    if command -v fish &> /dev/null; then
        local fish_path
        fish_path=$(command -v fish)
        local real_user
        real_user=$(detect_user)   # garante que o chsh seja para o usuário correto
        if [ "$SHELL" != "$fish_path" ]; then
            log_info "Definindo fish como shell padrão para o usuário $real_user..."
            sudo chsh -s "$fish_path" "$real_user"
            log_success "Shell padrão alterado para fish."
        fi
    fi
    
    # 4. Habilitar o serviço do DMS no systemd do usuário para iniciar com a sessão do Niri
    # Nota: em instalações mínimas sem DE, o systemctl --user pode não funcionar
    # porque não há sessão D-Bus ativa (ex: rodando via TTY/SSH)
    if systemctl --user list-unit-files 2>/dev/null | grep -q "^dms.service" 2>/dev/null; then
        log_info "Habilitando o serviço do dms para o usuário (systemd --user)..."
        systemctl --user enable dms.service &>/dev/null || true
    else
        log_warn "Serviço dms.service não encontrado ou systemd --user indisponível. Será habilitado automaticamente ao iniciar o Niri."
    fi
    
    # 5. Corrigir caminhos hardcoded no DankMaterialShell (json não suporta $HOME nativamente)
    for json_file in "$config_dir/DankMaterialShell/settings.json" "$config_dir/DankMaterialShell/plugin_settings.json"; do
        if [ -f "$json_file" ]; then
            log_info "Ajustando caminho do usuário em $(basename "$json_file")..."
            sed -i "s|/home/wanderson|$user_home|g" "$json_file"
        fi
    done
    
    log_success "Dotfiles implantados com sucesso via links simbólicos!"
}
