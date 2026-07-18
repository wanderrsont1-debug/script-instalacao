#!/usr/bin/env bash
# Wrapper para direcionar o instalador antigo do Arch para o novo instalador modular unificado

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
exec bash "$SCRIPT_DIR/install.sh"
