#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# Instalador Unificado de Ambiente — Arch Linux / CachyOS
# Ambientes suportados:
#   - Niri (DMS ou Noctalia)
#   - Hyprland (Noctalia, config Lua)
#
# Melhorias baseadas no donarch (GitLab):
#   - checks.sh dedicado (detecção de distro, AUR helper, pacotes base)
#   - Backup automático de ~/.config antes dos dotfiles
#   - Seleção interativa de apps opcionais
#   - detect_user() para suporte correto a sudo
# ═══════════════════════════════════════════════════════════════

set -e          # Interrompe imediatamente se qualquer comando falhar
set -E          # Faz o trap ERR valer também dentro de funções e subshells
set -u          # Erro ao usar variável não definida (pega typo em nome de variável)
set -o pipefail # Propaga falhas em pipes

# Obter diretório do repositório
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source das bibliotecas modulares
source "$REPO_DIR/lib/utils.sh"

# ── Arquivo de log da instalação ─────────────────────────────
# Toda a saída (tela + erros) é duplicada para um arquivo em logs/,
# com os códigos de cor removidos. Em caso de problema, basta enviar
# o log mais recente para diagnóstico.
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d_%H%M%S).log"

# Um ÚNICO 'tee', sem substituição de processo aninhada.
#
# Antes era 'tee >(sed -u ... >> LOG)': o sed rodava num segundo processo
# filho que era encerrado junto com o script, com saída ainda em buffer.
# Medido: de 501 linhas geradas, só 158 chegavam ao arquivo — o log terminava
# no meio da instalação, justamente escondendo o resumo final das verificações.
# Com um tee só, o 'wait' no EXIT garante que tudo seja gravado; os códigos de
# cor são removidos no fim, de uma vez.
exec > >(tee -a "$LOG_FILE") 2>&1

# NUNCA morrer em silêncio: se o 'set -e' for interromper o instalador, é
# preciso dizer exatamente onde e por quê. Antes disso, uma falha inesperada
# encerrava o script sem NENHUMA mensagem — parecia que ele tinha "terminado",
# mas etapas inteiras (shell escolhido, tema, SDDM) nunca rodavam.
#
# MAS o trap ERR não pode ser quem imprime "FALHA FATAL": com 'set -E' ele
# dispara no instante do erro, ANTES de o '|| log_warn' do chamador resolver —
# e este instalador guarda quase todas as etapas com '|| log_warn' de propósito
# (veja main()). Resultado da versão anterior: um único pacote AUR que falhou,
# e foi devidamente tratado, gerava uma mensagem de falha fatal idêntica à de um
# erro que realmente aborta o script. Isso treina o leitor do log a ignorar o
# aviso justamente quando ele é verdadeiro.
#
# Agora o ERR apenas ANOTA onde ocorreu o último erro; quem decide se foi fatal
# é o EXIT, que só grita se o instalador estiver de fato saindo com status != 0.
_ERR_LOCATION=""
_ERR_COMMAND=""
trap '_ERR_LOCATION="${BASH_SOURCE[0]##*/}:${LINENO}"; _ERR_COMMAND="${BASH_COMMAND}"' ERR

_on_exit() {
    local rc=$?

    if [ "$rc" -ne 0 ]; then
        log_error "FALHA FATAL em ${_ERR_LOCATION:-local desconhecido} — comando: ${_ERR_COMMAND:-desconhecido}"
        log_error "A instalação foi INTERROMPIDA aqui. Etapas seguintes NÃO foram executadas."
        log_error "Log completo salvo em: ${LOG_FILE}"
    fi

    # Fechar os descritores faz o tee ver EOF; o wait dá a ele tempo de gravar.
    exec 1>&- 2>&-
    wait 2>/dev/null || true
    sed -i $'s/\x1b\\[[0-9;?]*[A-Za-z]//g' "$LOG_FILE" 2>/dev/null || true
}
trap _on_exit EXIT
source "$REPO_DIR/lib/checks.sh"
source "$REPO_DIR/lib/packages.sh"
source "$REPO_DIR/lib/dotfiles.sh"
source "$REPO_DIR/lib/greeter.sh"
source "$REPO_DIR/lib/system.sh"

# ─────────────────────────────────────────────────────────────
# Tela de boas-vindas
# ─────────────────────────────────────────────────────────────
show_welcome() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       Instalador Unificado de Ambiente           ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  Suporta: Arch Linux / CachyOS                   ║${NC}"
    echo -e "${CYAN}║  Compositor: Niri ou Hyprland                    ║${NC}"
    echo -e "${CYAN}║  Shell: DMS ou Noctalia                          ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    if ! prompt_yes_no "Deseja continuar com a instalação?" "S"; then
        log_info "Instalação cancelada pelo usuário."
        exit 0
    fi
    echo ""
}



# ─────────────────────────────────────────────────────────────
# MAIN — Ponto de entrada
# ─────────────────────────────────────────────────────────────
main() {
    log_info "Registrando toda a instalação em: $LOG_FILE"
    echo ""

    # Verificações iniciais
    run_all_checks || exit 1

    # Boas-vindas
    show_welcome

    # Escolha do Compositor Wayland (Niri ou Hyprland) — define COMPOSITOR_CHOICE
    select_compositor

    # Escolha do Desktop Shell (DMS ou Noctalia beta) — define SHELL_CHOICE
    # (para Hyprland, é fixado em Noctalia automaticamente — veja select_shell)
    select_shell

    # Snapshot do sistema ANTES de qualquer instalação pesada (item 6)
    create_pre_install_snapshot || log_warn "Snapshot pré-instalação falhou — continuando."

    # ── Instalar o compositor escolhido ──────────────────────
    # A instalação usa as funções já existentes no repo
    # (packages.sh, dotfiles.sh, greeter.sh). O compositor (Niri/Hyprland) é
    # escolhido por select_compositor() e os pacotes/dotfiles são selecionados
    # condicionalmente conforme COMPOSITOR_CHOICE.
    local compositor_label="Niri"
    [ "${COMPOSITOR_CHOICE:-niri}" = "hyprland" ] && compositor_label="Hyprland"
    log_info "Iniciando instalação do ambiente ${compositor_label}..."

    # NOTA: a instalação é guardada com '|| log_warn' de propósito. Sem isso, com
    # 'set -e' ativo, a falha de UM pacote abortaria todo o script ANTES de habilitar
    # o SDDM e o graphical.target — deixando o sistema preso no TTY no próximo boot.
    # As verificações finais (verify_*) apontam o que ficou faltando.
    install_arch_packages "$REPO_DIR" || log_warn "Alguns pacotes falharam — continuando para configurar o ambiente."

    # Aplicar dotfiles (compositor escolhido + apps comuns)
    # Guardas '|| log_warn': nenhuma falha de dotfile pode impedir as etapas
    # críticas seguintes (configuração do SDDM e habilitação do boot gráfico).
    if [ -d "$REPO_DIR/dotfiles" ]; then
        backup_existing_configs "$REPO_DIR" || log_warn "Backup das configs existentes falhou — continuando."
        deploy_dotfiles "$REPO_DIR" || log_warn "Falha ao implantar dotfiles — revise os avisos acima."

        # Ajustes do shell que independem do compositor (agente polkit e, no
        # caso do Noctalia, a config base em ~/.local/state/noctalia).
        apply_shell_common "$REPO_DIR" || log_warn "Falha ao aplicar ajustes do shell escolhido."

        # Sincronizar o tema de cursor em TODOS os mecanismos (niri, hyprland,
        # environment.d, Xresources, GTK). Roda depois do deploy porque
        # reescreve os arquivos que acabaram de ser copiados.
        apply_cursor_theme || log_warn "Falha ao aplicar o tema de cursor."

        # Modo escuro do sistema (GTK/Qt) — ver lib/dotfiles.sh:apply_dark_mode().
        # Roda depois do cursor porque edita os MESMOS arquivos settings.ini.
        apply_dark_mode || log_warn "Falha ao aplicar o modo escuro do sistema."

        # Apontar o Niri para o shell escolhido (DMS ou Noctalia).
        # Específico do Niri (troca de includes .kdl); o Hyprland usa um único
        # arquivo Lua já cabeado para o Noctalia, sem seleção de includes.
        if [ "${COMPOSITOR_CHOICE:-niri}" = "niri" ]; then
            apply_shell_config || log_warn "Falha ao apontar o Niri para o shell escolhido."
        fi
    fi

    # Configurar greeter/DM — etapa mais crítica: garante boot gráfico.
    if declare -f setup_greeter &>/dev/null; then
        setup_greeter || log_warn "Configuração do SDDM terminou com avisos — veja a verificação final."
    fi

    log_success "Ambiente ${compositor_label} instalado."

    # Configurações finais do sistema (grupos, Flathub, firewall UFW)
    if declare -f configure_system_post &>/dev/null; then
        configure_system_post || log_warn "Configurações finais do sistema tiveram falhas."
    fi

    # Executar verificações finais de integridade do ambiente (por compositor)
    if [ "${COMPOSITOR_CHOICE:-niri}" = "hyprland" ]; then
        if declare -f verify_hyprland_environment &>/dev/null; then
            verify_hyprland_environment "$REPO_DIR" || log_warn "Problemas detectados no ambiente Hyprland."
        fi
    else
        if declare -f verify_niri_environment &>/dev/null; then
            verify_niri_environment "$REPO_DIR" || log_warn "Problemas detectados no ambiente Niri."
        fi
    fi
    if declare -f verify_display_manager &>/dev/null; then
        verify_display_manager "$REPO_DIR" || log_warn "Problemas detectados no Display Manager."
    fi

    echo ""
    log_success "Instalação concluída! Reinicie o sistema para aplicar as mudanças."
    log_info "Log completo desta instalação: $LOG_FILE"
    echo ""
}

main "$@"
