# Script de Instalação — Niri

![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white)
![Fedora](https://img.shields.io/badge/Fedora-51A2DA?style=for-the-badge&logo=fedora&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)

Script de instalação automatizada para recriar um ambiente Wayland completo em Arch Linux / CachyOS / Fedora e derivados.

---

## 🖥️ Ambientes Suportados

| Ambiente | Compositor | Dotfiles | Distros |
|---|---|---|---|
| **Niri** | Niri (Wayland) | DankMaterialShell (dms-shell) | Arch, CachyOS, Fedora |

---

## 🚀 Uso Rápido

```bash
git clone https://github.com/wanderrsont1-debug/script-instalacao
cd script-instalacao
bash install.sh
```

Ao executar, o script instalará e configurará o ambiente Niri com DankMaterialShell e SDDM automaticamente.

> ⚠️ **Não execute como root.** O script pede `sudo` internamente quando necessário.

---



## 📦 O que é instalado (Niri + DMS — Arch)

| Categoria | Pacotes |
|---|---|
| Compositor | `niri`, `xdg-desktop-portal`, `xdg-desktop-portal-gtk`, `xdg-desktop-portal-gnome` |
| Shell de Desktop | `dms-shell`, `matugen` |
| Terminais | `alacritty`, `ghostty` |
| Launcher | `fuzzel` |
| Shell | `fish` |
| Editor | `micro` |
| Monitor / Fetch | `btop`, `fastfetch`, `cava` |
| Áudio | `pipewire`, `pipewire-pulse`, `pipewire-alsa`, `wireplumber`, `pavucontrol` |
| Bluetooth | `bluez`, `bluez-utils` |
| Rede | `networkmanager` |
| Multimídia | `mpv`, `ffmpeg`, `gst-plugins-*` |
| Apps GUI | `nautilus`, `firefox`, `keepassxc`, `gnome-disk-utility`, `flatpak` |
| Fontes | `noto-fonts`, `noto-fonts-emoji`, `cantarell-fonts`, `ttf-meslo-nerd` |
| Display Manager | `sddm` (com tema SilentSDDM) |
| Segurança | `polkit-gnome`, `gnome-keyring`, `seahorse`, `ufw` |
| Opcionais | `zen-browser-bin` (perguntado na instalação) |

---



## 🔒 Segurança

- Backup automático de `~/.config` com timestamp antes de qualquer alteração
- Nunca executa como root
- Falhas em pacotes AUR individuais não abortam a instalação
- Conflitos de dotfiles tratados com `--restow`

---

## 📁 Estrutura do Repositório

```
script-instalacao/
├── install.sh                  ← Instalador principal
├── backup_local.sh             ← Backup do sistema atual
├── install_arch.sh             ← Wrapper Arch (legado)
├── install_fedora.sh           ← Wrapper Fedora (legado)
├── packages.txt                ← Lista de referência de pacotes
│
├── lib/                        ← Bibliotecas modulares
│   ├── utils.sh                (cores, logging, prompt)
│   ├── checks.sh               (detecção de distro, AUR helper)
│   ├── packages.sh             (instalação pacman/dnf/AUR)
│   ├── dotfiles.sh             (deploy de dotfiles Niri)
│   └── greeter.sh              (configuração SDDM)
│
├── packages/                   ← Listas de pacotes por distro/ambiente
│   ├── arch-base.txt
│   ├── arch-sddm.txt
│   ├── arch-fonts.txt
│   └── arch-optional.txt
│
├── dotfiles/                   ← Dotfiles do ambiente Niri
│   └── niri/
│

└── system/                     ← Arquivos de sistema (SDDM theme)
```

---

## 🖥️ Hardware Testado

| Componente | Especificação |
|---|---|
| CPU | AMD Ryzen 5 5600GT (vídeo integrado) |
| GPU | AMD Radeon (integrada) — mesa + vulkan-radeon |
| Distro principal | Arch Linux / CachyOS |

---

## 🙏 Créditos

- Estrutura modular inspirada no [donarch](https://gitlab.com/don_albert/donarch)
