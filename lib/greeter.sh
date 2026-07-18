#!/usr/bin/env bash
# Biblioteca para configurar Display Managers (SDDM) e habilitar serviços no systemd

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ─────────────────────────────────────────────────────────────
# Garantir que o SDDM esteja REALMENTE instalado (problema recorrente)
#
# Motivo: quando o sddm é instalado junto de deps Qt/xorg numa única
# transação do pacman, a falha de QUALQUER pacote derruba a transação
# inteira e o sddm acaba não sendo instalado. Aqui ele é instalado numa
# transação DEDICADA (só o sddm), com retry e verificação por binário.
# Roda sempre — mesmo que o usuário tenha pulado a etapa de pacotes.
# ─────────────────────────────────────────────────────────────
ensure_sddm_installed() {
    log_info "Garantindo que o SDDM esteja instalado (verificação dedicada)..."

    local is_fedora=false
    [ "${DISTRO:-arch}" = "fedora" ] && is_fedora=true

    _sddm_present() {
        if $is_fedora; then
            rpm -q sddm &>/dev/null
        else
            pacman -Q sddm &>/dev/null
        fi
    }

    if _sddm_present && command -v sddm &>/dev/null; then
        log_success "SDDM já instalado ($(command -v sddm))."
        return 0
    fi

    log_warn "SDDM ausente — instalando em transação dedicada..."

    local attempt
    for attempt in 1 2 3; do
        if $is_fedora; then
            sudo dnf install -y sddm || true
        else
            # -S (sem -y): a base já foi sincronizada com -Syu antes. Na 2ª
            # tentativa forçamos um -Sy para o caso de a base estar defasada.
            # Na 3ª tentativa adicionamos --overwrite '*' — causa comum e
            # silenciosa de falha repetida é conflito de arquivo (ex.: sddm
            # tentando instalar um arquivo que já existe no sistema), que
            # --noconfirm sozinho NÃO resolve e faz o pacman abortar a
            # transação inteira sempre do mesmo jeito.
            if [ "$attempt" -ge 3 ]; then
                sudo pacman -Sy --needed --noconfirm --overwrite '*' sddm || true
            elif [ "$attempt" -ge 2 ]; then
                sudo pacman -Sy --needed --noconfirm sddm || true
            else
                sudo pacman -S --needed --noconfirm sddm || true
            fi
        fi

        if _sddm_present && command -v sddm &>/dev/null; then
            log_success "SDDM instalado com sucesso (tentativa $attempt)."
            # Backend gráfico é obrigatório para o SDDM desenhar a tela de login.
            if ! $is_fedora; then
                sudo pacman -S --needed --noconfirm xorg-server \
                    || log_warn "Falha ao instalar xorg-server — o SDDM pode não iniciar sem backend gráfico."
            fi
            return 0
        fi

        log_warn "Tentativa $attempt de instalar o SDDM falhou."
    done

    log_error "NÃO foi possível instalar o SDDM automaticamente."
    if $is_fedora; then
        log_error "  Instale manualmente:  sudo dnf install sddm"
    else
        log_error "  Instale manualmente:  sudo pacman -S sddm xorg-server"
    fi
    return 1
}

configure_display_manager() {
    local repo_dir="$1"
    local theme_dst="/usr/share/sddm/themes/silent"

    if prompt_yes_no "Deseja configurar o SDDM e instalar o tema Silent?" "S"; then
            log_info "Instalando e configurando o tema Silent no SDDM..."

            # Procurar uma cópia LOCAL do SilentSDDM antes de tentar baixar da
            # internet. Isso evita depender de rede/git (comum logo após instalar
            # em TTY) e resolve o bug de o diretório do tema ficar parcial/vazio
            # de uma tentativa anterior e nunca mais ser reparado (o antigo check
            # só olhava se o diretório existia, não se o tema estava completo).
            local silent_src=""
            local candidate
            for candidate in \
                "${SILENT_SDDM_SRC:-}" \
                "$(dirname "$repo_dir")/SilentSDDM-main" \
                "$(get_user_home)/Downloads/SilentSDDM-main" \
                "$(get_user_home)/SilentSDDM-main"
            do
                if [ -n "$candidate" ] && [ -f "$candidate/Main.qml" ]; then
                    silent_src="$candidate"
                    break
                fi
            done

            if [ -n "$silent_src" ]; then
                log_info "Usando cópia local do SilentSDDM em: $silent_src"
                sudo mkdir -p "$theme_dst"
                sudo cp -rf "$silent_src"/. "$theme_dst/"
            elif [ ! -f "$theme_dst/Main.qml" ]; then
                log_info "Cópia local não encontrada — clonando tema SilentSDDM do repositório oficial..."
                # Remove qualquer diretório parcial/quebrado de uma tentativa anterior
                # antes de clonar — 'git clone' falha se o destino já existir e não
                # estiver vazio.
                sudo rm -rf "$theme_dst"
                sudo git clone https://github.com/uiriansan/SilentSDDM.git "$theme_dst" || log_warn "Falha ao baixar o tema SilentSDDM."
            else
                log_info "O tema SilentSDDM já está instalado no sistema."
            fi

            # O tema só é considerado válido se o Main.qml existir. Sem isso, apontar
            # o sddm.conf para "Current=silent" resultaria em greeter quebrado no boot.
            local theme_ok=false
            [ -f "$theme_dst/Main.qml" ] && theme_ok=true

            # As fontes do tema (Red Hat Text) precisam ser copiadas para
            # /usr/share/fonts/ separadamente — sem isso o greeter carrega mas usa
            # uma fonte de fallback (o install.sh oficial do SilentSDDM faz o mesmo).
            if $theme_ok && [ -d "$theme_dst/fonts" ]; then
                log_info "Instalando fontes do tema SilentSDDM..."
                sudo cp -r "$theme_dst"/fonts/. /usr/share/fonts/ 2>/dev/null \
                    && command -v fc-cache &>/dev/null && sudo fc-cache -f &>/dev/null
            fi

            # Aplicar configurações do SDDM copiadas do diretório do script
            if [ -d "$repo_dir/system" ]; then
                log_info "Aplicando arquivos de configuração do SDDM..."
                if [ -f "$repo_dir/system/etc/sddm.conf" ]; then
                    if $theme_ok; then
                        sudo cp -r "$repo_dir/system/etc/sddm.conf" /etc/sddm.conf
                    else
                        log_warn "Tema Silent ausente/incompleto — NÃO apontando o sddm.conf para ele."
                        log_info "  O SDDM usará o tema padrão (login funcional). Rode o instalador de novo com internet para o tema Silent."
                    fi
                fi
                if [ -d "$repo_dir/system/etc/sddm.conf.d" ]; then
                    sudo mkdir -p /etc/sddm.conf.d
                    sudo cp -a "$repo_dir/system/etc/sddm.conf.d/." /etc/sddm.conf.d/
                fi
                
                # Restaurar customizações do tema SilentSDDM (vídeos, configs, metadata)
                # Só sobrepõe se o tema base existir — evita criar um diretório de tema
                # parcial (sem Main.qml) que o SDDM não conseguiria carregar.
                if $theme_ok && [ -d "$repo_dir/system/usr/share/sddm/themes/silent" ]; then
                    log_info "Restaurando configurações e vídeos customizados do tema SilentSDDM..."
                    sudo cp -a "$repo_dir/system/usr/share/sddm/themes/silent/." /usr/share/sddm/themes/silent/
                fi
                
                log_success "SDDM configurado com o tema Silent!"
            else
                log_warn "Diretório de configurações $repo_dir/system não encontrado."
            fi
        fi
}

enable_systemd_services() {
    # NOTA: Habilitação de serviços é obrigatória — sem DM habilitado o sistema
    # inicia no TTY (multi-user.target), que é exatamente o bug que queremos evitar.
    log_info "Habilitando serviços essenciais no systemd..."

    # Lista padrão de serviços que sempre devem ser ativados se existirem
    local services=(NetworkManager bluetooth power-profiles-daemon sddm)

    # DMs conhecidos que podem conflitar entre si
    local all_known_dms=(sddm greetd lightdm gdm ly lemurs emptty)

    # Desabilitar TODOS os DMs concorrentes para evitar conflitos
    local chosen_dm="sddm"

    if [ -n "$chosen_dm" ]; then
        for other_dm in "${all_known_dms[@]}"; do
            [ "$other_dm" = "$chosen_dm" ] && continue
            if systemctl is-enabled "${other_dm}.service" &>/dev/null; then
                log_info "Desabilitando ${other_dm}.service para evitar conflitos..."
                sudo systemctl disable "${other_dm}.service" &>/dev/null || true
            fi
        done
    fi

    # Habilitar os serviços instalados
    for service in "${services[@]}"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${service}.service"; then
            # Verificação do binário: remover prefixos especiais do systemd (-@+!)
            # '|| true' evita que um grep sem match (pipefail + set -e) aborte todo o
            # instalador justamente no passo que habilita o Display Manager.
            local service_bin
            service_bin=$(systemctl cat "${service}.service" 2>/dev/null \
                | grep -m1 '^ExecStart=' \
                | sed 's/^ExecStart=//;s/^[-@+!]*//' \
                | awk '{print $1}' || true)
            if [ -n "$service_bin" ] && ! command -v "$service_bin" &>/dev/null; then
                log_warn "Binário '$service_bin' do serviço '$service' não encontrado. Pulando habilitação."
                continue
            fi
            log_info "Habilitando serviço: ${service}..."
            sudo systemctl enable "${service}.service"

            # Verificação pós-habilitação
            if ! systemctl is-enabled "${service}.service" &>/dev/null; then
                log_error "Falha ao habilitar ${service}.service! Verifique manualmente."
            fi
        else
            log_warn "Serviço '${service}.service' não encontrado no systemd."
            # Se for o próprio SDDM, tentar instalar e habilitar na hora — a unit
            # só existe depois que o pacote sddm estiver presente.
            if [ "$service" = "sddm" ]; then
                log_info "  → Tentando instalar o SDDM para criar a unit..."
                if ensure_sddm_installed && systemctl list-unit-files 2>/dev/null | grep -q "^sddm.service"; then
                    sudo systemctl enable sddm.service \
                        && log_success "  → sddm.service habilitado." \
                        || log_error "  → Falha ao habilitar sddm.service."
                else
                    log_error "  → SDDM ainda ausente. Instale manualmente e rode: sudo systemctl enable sddm.service"
                fi
            else
                log_info "  Verifique se o pacote correspondente foi instalado."
            fi
        fi
    done

    # Garantir que o alvo padrão do systemd seja o modo gráfico para iniciar o Display Manager
    log_info "Definindo o alvo padrão do systemd como gráfico (graphical.target)..."
    sudo systemctl set-default graphical.target &>/dev/null || true

    # Confirmar que o target foi definido
    local current_target
    current_target=$(systemctl get-default 2>/dev/null)
    if [ "$current_target" != "graphical.target" ]; then
        log_error "Falha ao definir graphical.target! Target atual: $current_target"
    fi

    log_success "Serviços de sistema configurados com sucesso!"
}

# ─────────────────────────────────────────────────────────────
# Verificação completa do Display Manager antes de reiniciar
# Detecta problemas que impediriam o DM de iniciar no próximo boot
# ─────────────────────────────────────────────────────────────
verify_display_manager() {
    local repo_dir="$1"

    local dm_name="SDDM"
    local dm_service="sddm"

    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║   Verificação do Display Manager (${dm_name})${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    local errors=0
    local warnings=0

    # ── 1. Pacote instalado? ──────────────────────────────────
    log_info "1/6 — Verificando pacote ${dm_service}..."
    local pkg_installed=false
    if [ "${DISTRO:-arch}" = "fedora" ]; then
        rpm -q "$dm_service" &>/dev/null && pkg_installed=true
    else
        pacman -Q "$dm_service" &>/dev/null && pkg_installed=true
    fi

    if $pkg_installed; then
        log_success "Pacote $dm_service instalado."
    else
        log_error "Pacote $dm_service NÃO instalado! Tentando corrigir automaticamente..."
        if ensure_sddm_installed; then
            log_success "  → Correção: pacote $dm_service instalado."
        else
            log_error "  → Correção falhou. Instale manualmente antes de reiniciar."
            errors=$((errors + 1))
        fi
    fi

    # ── 2. Serviço habilitado? ────────────────────────────────
    log_info "2/6 — Verificando ${dm_service}.service..."
    if systemctl is-enabled "${dm_service}.service" &>/dev/null; then
        log_success "${dm_service}.service habilitado."
    else
        log_error "${dm_service}.service NÃO habilitado!"
        log_info "  → Tentando correção automática..."
        if sudo systemctl enable "${dm_service}.service" 2>/dev/null; then
            log_success "  → Correção: ${dm_service}.service habilitado."
        else
            log_error "  → Correção falhou. Execute manualmente: sudo systemctl enable ${dm_service}.service"
            errors=$((errors + 1))
        fi
    fi

    # ── 3. Target padrão ──────────────────────────────────────
    log_info "3/6 — Verificando target padrão do systemd..."
    local current_target
    current_target=$(systemctl get-default 2>/dev/null)
    if [ "$current_target" = "graphical.target" ]; then
        log_success "Target padrão: graphical.target"
    else
        log_error "Target: $current_target (esperado: graphical.target)"
        log_info "  → Corrigindo..."
        sudo systemctl set-default graphical.target &>/dev/null || true
        current_target=$(systemctl get-default 2>/dev/null)
        if [ "$current_target" = "graphical.target" ]; then
            log_success "  → Correção: graphical.target definido."
        else
            log_error "  → Falha ao corrigir target!"
            errors=$((errors + 1))
        fi
    fi

    # ── 4. DMs conflitantes ───────────────────────────────────
    log_info "4/6 — Verificando DMs conflitantes..."
    local all_dms=(sddm greetd lightdm gdm ly lemurs emptty)
    local found_conflict=false
    for other_dm in "${all_dms[@]}"; do
        [ "$other_dm" = "$dm_service" ] && continue
        if systemctl is-enabled "${other_dm}.service" &>/dev/null; then
            log_warn "DM conflitante ativo: ${other_dm}.service"
            sudo systemctl disable "${other_dm}.service" &>/dev/null || true
            found_conflict=true
        fi
    done
    if $found_conflict; then
        log_success "DMs conflitantes desabilitados."
        warnings=$((warnings + 1))
    else
        log_success "Nenhum DM conflitante."
    fi

    # ── 5. Verificações específicas ───────────────────────────
    # ── SDDM ──
        # 5a. Binário do SDDM
        log_info "5/6 — Verificando binário sddm..."
        if command -v sddm &>/dev/null; then
            log_success "Binário: $(command -v sddm)"
        else
            log_error "Binário sddm não encontrado no PATH!"
            errors=$((errors + 1))
        fi

        # 5b. Backend gráfico (Xorg ou Wayland)
        log_info "6/6 — Verificando backend gráfico para o SDDM..."
        local has_xorg=false
        local has_wl_greeter=false
        { [ -x "/usr/bin/Xorg" ] || [ -x "/usr/lib/Xorg" ]; } && has_xorg=true
        { [ -x "/usr/lib/sddm/sddm-wl-greeter" ] || [ -x "/usr/bin/sddm-greeter-qt6" ]; } && has_wl_greeter=true

        if $has_xorg; then
            log_success "Xorg disponível como backend."
        elif $has_wl_greeter; then
            log_success "Greeter Wayland disponível como backend."
        else
            log_error "Nenhum backend gráfico (Xorg/Wayland) encontrado!"
            log_info "  O SDDM precisa de xorg-server OU sddm-greeter-qt6 (Wayland) para exibir a tela de login."
            errors=$((errors + 1))

            # Oferecer instalação automática do xorg-server
            if prompt_yes_no "  Deseja instalar xorg-server agora para corrigir?" "S"; then
                if [ "${DISTRO:-arch}" = "fedora" ]; then
                    sudo dnf install -y xorg-x11-server-Xorg && {
                        log_success "  xorg-server instalado."
                        errors=$((errors - 1))
                    } || log_error "  Falha ao instalar xorg-server."
                else
                    sudo pacman -S --needed --noconfirm xorg-server && {
                        log_success "  xorg-server instalado."
                        errors=$((errors - 1))
                    } || log_error "  Falha ao instalar xorg-server."
                fi
            fi
        fi

        # 5c. Dependências Qt (Arch)
        if [ "${DISTRO:-arch}" != "fedora" ]; then
            log_info "    Verificando dependências Qt..."
            local qt_missing=()
            for dep in qt6-5compat qt6-svg qt6-virtualkeyboard qt6-multimedia; do
                pacman -Q "$dep" &>/dev/null || qt_missing+=("$dep")
            done
            if [ ${#qt_missing[@]} -gt 0 ]; then
                log_warn "  Deps Qt ausentes: ${qt_missing[*]}"
                log_info "  O tema SilentSDDM pode não renderizar corretamente."
                warnings=$((warnings + 1))
            else
                log_success "  Dependências Qt presentes."
            fi
        fi

        # 5d. Tema SilentSDDM
        if [ -d "/usr/share/sddm/themes/silent" ]; then
            log_success "  Tema SilentSDDM instalado."
            if [ -f "/etc/sddm.conf" ] && grep -q "Current=silent" /etc/sddm.conf 2>/dev/null; then
                log_success "  sddm.conf aponta para o tema Silent."
            else
                log_warn "  sddm.conf pode não estar apontando para o tema Silent."
                warnings=$((warnings + 1))
            fi
        else
            log_info "  Tema SilentSDDM não instalado (será usado o tema padrão do SDDM)."
        fi

    # ── Resultado final ───────────────────────────────────────
    echo ""
    echo -e "${BLUE}───────────────────────────────────────────────────${NC}"
    if [ "$errors" -gt 0 ]; then
        echo -e "${RED}  ✗ Verificação FALHOU: $errors erro(s), $warnings aviso(s)${NC}"
        log_error "O $dm_name pode NÃO funcionar após reinicialização."
        log_info "Corrija os erros acima antes de reiniciar o sistema."
        echo -e "${BLUE}───────────────────────────────────────────────────${NC}"
        return 1
    elif [ "$warnings" -gt 0 ]; then
        echo -e "${YELLOW}  ⚠ Verificação OK com $warnings aviso(s)${NC}"
        log_info "O $dm_name deve funcionar, mas revise os avisos acima."
        echo -e "${BLUE}───────────────────────────────────────────────────${NC}"
        return 0
    else
        echo -e "${GREEN}  ✓ $dm_name verificado e pronto para uso!${NC}"
        echo -e "${BLUE}───────────────────────────────────────────────────${NC}"
        return 0
    fi
}

# ─────────────────────────────────────────────────────────────
# Verificação completa do ambiente Niri + DMS antes de reiniciar
# Detecta problemas que impediriam o compositor ou o shell de
# funcionar corretamente após o reboot
# ─────────────────────────────────────────────────────────────
verify_niri_environment() {
    local repo_dir="$1"
    local user_home
    user_home=$(get_user_home)
    local niri_cfg_dir="$user_home/.config/niri"
    local shell_label="DMS"
    [ "${SHELL_CHOICE:-dms}" = "noctalia" ] && shell_label="Noctalia"

    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    printf "${YELLOW}║     Verificação do Ambiente Niri + %-13s ║${NC}\n" "$shell_label"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    local errors=0
    local warnings=0

    # ── 1. Binário do Niri ────────────────────────────────────
    log_info "1/7 — Verificando binário niri..."
    if command -v niri &>/dev/null; then
        log_success "niri encontrado: $(command -v niri)"
    else
        log_error "Binário 'niri' NÃO encontrado no PATH!"
        log_info "  → Instale com: sudo pacman -S niri  (Arch) | sudo dnf install niri  (Fedora)"
        errors=$((errors + 1))
    fi

    # ── 2. Binário do Shell escolhido (DMS ou Noctalia) ───────
    local shell_choice="${SHELL_CHOICE:-dms}"
    if [ "$shell_choice" = "noctalia" ]; then
        log_info "2/7 — Verificando binário noctalia..."
        if command -v noctalia &>/dev/null; then
            log_success "noctalia encontrado: $(command -v noctalia)"
        else
            log_error "Binário 'noctalia' NÃO encontrado!"
            log_info "  → Instale com: paru -S noctalia-git  (ou: sudo pacman -S noctalia)"
            errors=$((errors + 1))
        fi
    else
        log_info "2/7 — Verificando binário dms..."
        if command -v dms &>/dev/null; then
            log_success "dms encontrado: $(command -v dms)"
        else
            log_error "Binário 'dms' NÃO encontrado!"
            log_info "  → O DankMaterialShell não foi instalado corretamente."
            errors=$((errors + 1))
        fi
    fi

    # ── 3. Arquivos de configuração do Niri ───────────────────
    log_info "3/7 — Verificando configuração do Niri em $niri_cfg_dir..."
    local niri_config="$niri_cfg_dir/config.kdl"

    if [ -f "$niri_config" ] || [ -L "$niri_config" ]; then
        log_success "config.kdl encontrado."

        # ── 3a. Verificar includes KDL sem caminhos hardcoded ──
        log_info "      Verificando includes hardcoded no config.kdl..."
        local hardcoded_includes
        hardcoded_includes=$(grep -rn '/home/' "$niri_cfg_dir" 2>/dev/null || true)
        if [ -n "$hardcoded_includes" ]; then
            log_error "Encontrados caminhos hardcoded nos configs do Niri:"
            while IFS= read -r line; do
                log_warn "  → $line"
            done <<< "$hardcoded_includes"
            log_info "  Corrija usando include relativo, ex: include \"./keybinds-dms.kdl\""
            errors=$((errors + 1))
        else
            log_success "Nenhum caminho hardcoded encontrado nos includes."
        fi

        # ── 3b. Validar sintaxe via 'niri validate' ───────────
        if command -v niri &>/dev/null; then
            log_info "      Validando sintaxe do config.kdl com 'niri validate'..."
            local validate_out
            validate_out=$(niri validate --config "$niri_config" 2>&1) || true
            if echo "$validate_out" | grep -qi "error\|erro\|invalid\|inválid"; then
                log_error "Erros de sintaxe detectados no config.kdl:"
                while IFS= read -r vline; do
                    log_warn "  → $vline"
                done <<< "$validate_out"
                errors=$((errors + 1))
            else
                log_success "Sintaxe do config.kdl válida."
            fi
        fi
    else
        log_error "config.kdl NÃO encontrado em $niri_cfg_dir!"
        log_info "  → Os dotfiles podem não ter sido implantados corretamente."
        errors=$((errors + 1))
    fi

    # ── 4. Arquivos KDL de keybinds e autostart ───────────────
    log_info "4/7 — Verificando arquivos essenciais de configuração..."
    local shell_suffix="dms"
    [ "$shell_choice" = "noctalia" ] && shell_suffix="noctalia"
    local required_kdl=(
        "$niri_cfg_dir/cfg/keybinds.kdl"
        "$niri_cfg_dir/cfg/keybinds-${shell_suffix}.kdl"
        "$niri_cfg_dir/cfg/autostart.kdl"
        "$niri_cfg_dir/cfg/autostart-${shell_suffix}.kdl"
    )
    for kdl_file in "${required_kdl[@]}"; do
        if [ -f "$kdl_file" ] || [ -L "$kdl_file" ]; then
            log_success "  ✓ $(basename "$kdl_file")"
        else
            log_error "  ✗ Arquivo ausente: $kdl_file"
            errors=$((errors + 1))
        fi
    done

    # ── 5. Shell escolhido é iniciado com o Niri? ─────────────
    log_info "5/7 — Verificando se o shell (${shell_choice}) é iniciado com o Niri..."
    # 5a. O autostart.kdl aponta para o include do shell correto?
    local autostart_main="$niri_cfg_dir/cfg/autostart.kdl"
    if [ -f "$autostart_main" ] && ! grep -q "autostart-${shell_suffix}.kdl" "$autostart_main" 2>/dev/null; then
        log_warn "autostart.kdl não inclui 'autostart-${shell_suffix}.kdl' — o shell ${shell_choice} pode não iniciar."
        warnings=$((warnings + 1))
    fi
    # 5b. O spawn do shell está ativo no arquivo do shell?
    local autostart_shell="$niri_cfg_dir/cfg/autostart-${shell_suffix}.kdl"
    if [ -f "$autostart_shell" ] || [ -L "$autostart_shell" ]; then
        local real_autostart spawn_pattern
        real_autostart=$(readlink -f "$autostart_shell" 2>/dev/null || echo "$autostart_shell")
        if [ "$shell_choice" = "noctalia" ]; then
            spawn_pattern='^spawn-at-startup[[:space:]]*"noctalia"'
        else
            spawn_pattern='^spawn-at-startup[[:space:]]*"dms"'
        fi
        if grep -q "$spawn_pattern" "$real_autostart" 2>/dev/null; then
            log_success "spawn-at-startup do ${shell_choice} está ativo."
        else
            log_warn "spawn-at-startup do ${shell_choice} ausente/comentado em autostart-${shell_suffix}.kdl!"
            log_info "  → O ${shell_choice} não iniciará automaticamente com o Niri."
            warnings=$((warnings + 1))
        fi
    fi

    # ── 6. Binários opcionais recomendados ────────────────────
    log_info "6/7 — Verificando binários recomendados..."
    local optional_bins=(ghostty playerctl fuzzel)
    local missing_optional=()
    for bin in "${optional_bins[@]}"; do
        if command -v "$bin" &>/dev/null; then
            log_success "  ✓ $bin"
        else
            missing_optional+=("$bin")
            log_warn "  ⚠ $bin não encontrado (alguns atalhos podem não funcionar)"
        fi
    done
    if [ ${#missing_optional[@]} -gt 0 ]; then
        warnings=$((warnings + 1))
    fi

    # ── 7. Variáveis de ambiente Wayland ──────────────────────
    log_info "7/7 — Verificando configuração do ambiente Wayland..."
    if [ -d "$user_home/.config/environment.d" ] || [ -L "$user_home/.config/environment.d" ]; then
        log_success "Diretório environment.d presente."
    else
        log_warn "Diretório environment.d não encontrado em ~/.config/"
        log_info "  → Variáveis de ambiente Wayland podem não estar definidas."
        warnings=$((warnings + 1))
    fi

    # ── Resultado final ───────────────────────────────────────
    echo ""
    echo -e "${BLUE}───────────────────────────────────────────────────${NC}"
    if [ "$errors" -gt 0 ]; then
        echo -e "${RED}  ✗ Verificação do Niri FALHOU: $errors erro(s), $warnings aviso(s)${NC}"
        log_error "O ambiente Niri+${shell_label} pode NÃO funcionar após a reinicialização."
        log_info  "Corrija os erros acima antes de reiniciar o sistema."
        echo -e "${BLUE}───────────────────────────────────────────────────${NC}"
        return 1
    elif [ "$warnings" -gt 0 ]; then
        echo -e "${YELLOW}  ⚠ Verificação do Niri OK com $warnings aviso(s)${NC}"
        log_info "O Niri+${shell_label} deve funcionar, mas revise os avisos acima."
        echo -e "${BLUE}───────────────────────────────────────────────────${NC}"
        return 0
    else
        echo -e "${GREEN}  ✓ Ambiente Niri+${shell_label} verificado e pronto!${NC}"
        echo -e "${BLUE}───────────────────────────────────────────────────${NC}"
        return 0
    fi
}

# ─────────────────────────────────────────────────────────────
# Corrigir "duas topbars" do DMS no primeiro boot
#
# O DMS pode ser iniciado por DOIS mecanismos independentes:
#   1. dms.service  — unit de usuário do systemd que vem no pacote
#      dms-shell (WantedBy=graphical-session.target);
#   2. o niri, via  spawn-at-startup "dms" "run"  (autostart-dms.kdl).
#
# Em sessões já "assentadas" o DMS deduplica em runtime e sobe uma única
# instância. Mas no PRIMEIRO boot (cold start) os dois disparam quase ao
# mesmo tempo, cada um acha que não há instância, e ambos sobem → DUAS
# topbars. Isso desaparece em boots seguintes por diferença de timing.
#
# Solução (escolha do usuário): manter apenas o spawn-at-startup do niri
# — abordagem idiomática do DMS no niri — e desabilitar o dms.service,
# garantindo uma única instância de forma determinística.
# ─────────────────────────────────────────────────────────────
fix_dms_double_bar() {
    log_info "Definindo mecanismo único de inicialização do DMS (evita duas topbars no 1º boot)..."

    # Este é o único ponto do instalador que decide se o DMS deve subir via
    # dms.service (systemd --user) ou via spawn-at-startup do niri. Nunca
    # habilite dms.service em outro lugar do script — os dois mecanismos
    # rodando juntos é exatamente a causa das duas topbars.
    local user_home niri_autostart
    user_home=$(get_user_home)
    niri_autostart="$user_home/.config/niri/cfg/autostart-dms.kdl"
    local real_autostart
    real_autostart=$(readlink -f "$niri_autostart" 2>/dev/null || echo "$niri_autostart")

    # Serviços de usuário do systemd que também iniciam o DMS
    local dms_user_services=(dms.service dms-shell.service dankmaterialshell.service)

    if ! grep -q '^[[:space:]]*spawn-at-startup[[:space:]]*"dms"' "$real_autostart" 2>/dev/null; then
        # Niri não inicia o DMS sozinho — habilitar o serviço systemd como fallback
        # para não deixar o usuário sem nenhum mecanismo de autostart.
        log_warn "spawn-at-startup do DMS não encontrado no niri — habilitando dms.service como alternativa."
        local enabled_any=false
        for svc in "${dms_user_services[@]}"; do
            if systemctl --user list-unit-files 2>/dev/null | grep -q "^${svc}"; then
                log_info "Habilitando ${svc} (systemd --user)..."
                systemctl --user enable "$svc" &>/dev/null || true
                enabled_any=true
            fi
        done
        if [ "$enabled_any" = false ]; then
            log_warn "Nenhum serviço systemd do DMS encontrado. O DMS pode não iniciar automaticamente."
        fi
        return 0
    fi

    local disabled_any=false
    for svc in "${dms_user_services[@]}"; do
        if systemctl --user list-unit-files 2>/dev/null | grep -q "^${svc}"; then
            if systemctl --user is-enabled "$svc" &>/dev/null; then
                log_info "Desabilitando ${svc} (o niri já inicia o DMS via spawn-at-startup)..."
                systemctl --user disable "$svc" &>/dev/null || true
                disabled_any=true
            fi
        fi
    done

    if [ "$disabled_any" = true ]; then
        log_success "dms.service desabilitado — o DMS iniciará uma única vez pelo niri (uma topbar)."
    else
        log_success "Nenhum serviço systemd do DMS habilitado — nada a corrigir."
    fi
    return 0
}

# Função agregadora para configurar o greeter
setup_greeter() {
    local repo_dir
    repo_dir="$(cd "$SCRIPT_DIR/.." && pwd)"
    ensure_sddm_installed || log_warn "SDDM pode não estar instalado — revise os avisos acima."
    configure_display_manager "$repo_dir"
    enable_systemd_services
    # A correção de "duas topbars" é específica do DMS. Com Noctalia não se aplica.
    if [ "${SHELL_CHOICE:-dms}" = "dms" ]; then
        fix_dms_double_bar
    fi
}
