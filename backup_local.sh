#!/usr/bin/env bash
set -e

# Detectar o diretório do repositório dinamicamente
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$REPO_DIR/dotfiles"
mkdir -p "$REPO_DIR/system"

# Copy .config folders
for folder in niri DankMaterialShell alacritty ghostty fuzzel cava micro environment.d fish; do
    if [ -d "$HOME/.config/$folder" ]; then
        echo "Copying ~/.config/$folder..."
        mkdir -p "$REPO_DIR/dotfiles/$folder"
        rsync -av --exclude='.git' --exclude='*cache*' "$HOME/.config/$folder/" "$REPO_DIR/dotfiles/$folder/" || true
    fi
done

# Copy home files
for file in .bashrc .zshrc .bash_profile .Xresources; do
    if [ -f "$HOME/$file" ]; then
        echo "Copying ~/$file..."
        cp "$HOME/$file" "$REPO_DIR/dotfiles/"
    fi
done

# Copy system configurations
mkdir -p "$REPO_DIR/system/etc"
mkdir -p "$REPO_DIR/system/etc/sddm.conf.d"
if [ -f /etc/sddm.conf ]; then
    cp /etc/sddm.conf "$REPO_DIR/system/etc/"
fi
if [ -f /etc/sddm.conf.d/virtualkbd.conf ]; then
    cp /etc/sddm.conf.d/virtualkbd.conf "$REPO_DIR/system/etc/sddm.conf.d/"
fi

# Backup SilentSDDM theme configurations and videos if present
if [ -d /usr/share/sddm/themes/silent ]; then
    echo "Copying SilentSDDM theme configurations and videos..."
    mkdir -p "$REPO_DIR/system/usr/share/sddm/themes/silent"
    cp /usr/share/sddm/themes/silent/metadata.desktop "$REPO_DIR/system/usr/share/sddm/themes/silent/" 2>/dev/null || true
    rsync -av /usr/share/sddm/themes/silent/configs/ "$REPO_DIR/system/usr/share/sddm/themes/silent/configs/" 2>/dev/null || true
    rsync -av /usr/share/sddm/themes/silent/backgrounds/ "$REPO_DIR/system/usr/share/sddm/themes/silent/backgrounds/" 2>/dev/null || true
fi

# Save explicitly installed packages
echo "Saving package list..."
if command -v pacman &> /dev/null; then
    pacman -Qqe > "$REPO_DIR/packages.txt"
elif command -v dnf &> /dev/null; then
    dnf repoquery --userinstalled --queryformat "%{name}" > "$REPO_DIR/packages.txt"
else
    echo "Warning: No supported package manager found to export package list."
fi

echo "Local config extraction completed successfully!"

