# Script de Instalação — Niri & Hyprland

![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white)
![Fedora](https://img.shields.io/badge/Fedora-51A2DA?style=for-the-badge&logo=fedora&logoColor=white)
![Hyprland](https://img.shields.io/badge/Hyprland-58E1FF?style=for-the-badge&logo=hyprland&logoColor=000)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)

Script de instalação automatizada e interativa para recriar ambientes Wayland completos em Arch Linux / CachyOS / Fedora e derivados.

---

## 🖥️ Ambientes Suportados

| Ambiente | Compositor | Dotfiles | Distros |
|---|---|---|---|
| **Niri** | Niri (Wayland) | DankMaterialShell (dms-shell) | Arch, CachyOS, Fedora |
| **Hyprland** | Hyprland 0.55+ (Lua) | Jules3182/dotfiles (incluídos) | Arch, CachyOS, Fedora |

---

## 🚀 Uso Rápido

```bash
git clone https://github.com/wanderrsont1-debug/script-instalacao
cd script-instalacao
bash install.sh
```

Ao executar, um menu interativo pergunta qual ambiente instalar:

```
┌──────────────────────────────────────────────────┐
│        Selecione o ambiente a instalar:          │
├──────────────────────────────────────────────────┤
│  1) Niri   — DankMaterialShell (dms-shell)       │
│  2) Hyprland — dotfiles Lua 0.55+                │
│  3) Ambos  — instalar Niri e Hyprland            │
│  0) Sair                                         │
└──────────────────────────────────────────────────┘
```

> ⚠️ **Não execute como root.** O script pede `sudo` internamente quando necessário.

---

## ✅ Testar Antes de Instalar (dry-run)

Para validar o script sem instalar nada (recomendado antes de usar em um novo sistema):

```bash
bash test_hyprland.sh
```

O script de testes verifica **10 categorias** sem tocar no sistema:
- Sintaxe de todos os `.sh`
- Presença de todos os arquivos e módulos de dotfiles
- Estrutura compatível com GNU Stow
- Pacotes essenciais nas listas
- Todas as funções definidas
- Simulação de backup em `/tmp`
- Simulação de GNU Stow em `/tmp`

Resultado esperado: **0 FAIL → pronto para produção**.

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
| Display Manager | `sddm` (com tema SilentSDDM) **ou** `greetd` + `tuigreet` |
| Segurança | `polkit-gnome`, `gnome-keyring`, `seahorse`, `ufw` |
| Opcionais | `zen-browser-bin` (perguntado na instalação) |

---

## 📦 O que é instalado (Hyprland — Arch)

| Categoria | Pacotes |
|---|---|
| Compositor | `hyprland`, `xdg-desktop-portal-hyprland` |
| Barra | `waybar-git` (compilado via paru) |
| Launcher | `wofi` |
| Notificações | `swaync` |
| Widgets | `eww` |
| Terminal | `ghostty` |
| Áudio | `pipewire`, `wireplumber`, `pavucontrol` |
| Bluetooth | `bluez`, `bluez-utils` |
| GPU AMD | `mesa`, `vulkan-radeon`, `libva-mesa-driver` |
| Display Manager | `sddm` |
| Dotfiles | GNU Stow (incluídos no repo) |

> Para Fedora, os mesmos pacotes são instalados via `dnf` + COPR `solopasha/hyprland`.

---

## 🔗 Dotfiles Hyprland (incluídos no repositório)

Os dotfiles estão em `dotfiles-hyprland/` — **sem dependência de repositório externo**.

```
dotfiles-hyprland/
├── hyprland/      → ~/.config/hypr/        (config + scripts Lua)
├── waybar/        → ~/.config/waybar/      (barra superior e inferior)
├── wofi/          → ~/.config/wofi/        (launcher de aplicativos)
├── swaync/        → ~/.config/swaync/      (central de notificações)
├── eww/           → ~/.config/eww/         (widgets: calendário, power menu)
├── ghostty/       → ~/.config/ghostty/     (terminal)
├── btop/          → ~/.config/btop/        (monitor de sistema)
├── fastfetch/     → ~/.config/fastfetch/   (system fetch)
└── wallpapers/    → ~/.dotfiles-hyprland/wallpapers/
```

Aplicados com **GNU Stow** (symlinks) — edite os arquivos em `~/.dotfiles-hyprland/` e rode `stow <módulo>` para atualizar.

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
├── install.sh                  ← Instalador principal interativo
├── test_hyprland.sh            ← Validação dry-run (sem instalar nada)
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
│   ├── greeter.sh              (configuração SDDM/greetd)
│   └── hyprland.sh             (instalação completa Hyprland)
│
├── packages/                   ← Listas de pacotes por distro/ambiente
│   ├── arch-base.txt
│   ├── arch-sddm.txt
│   ├── arch-greetd.txt
│   ├── arch-fonts.txt
│   ├── arch-optional.txt
│   ├── hyprland-arch.txt       ← Pacotes Hyprland (Arch)
│   └── hyprland-fedora.txt     ← Pacotes Hyprland (Fedora)
│
├── dotfiles/                   ← Dotfiles do ambiente Niri
│   └── niri/
│
├── dotfiles-hyprland/          ← Dotfiles do ambiente Hyprland
│   ├── hyprland/
│   ├── waybar/
│   ├── wofi/
│   ├── swaync/
│   ├── eww/
│   ├── ghostty/
│   ├── btop/
│   ├── fastfetch/
│   └── wallpapers/
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

- Dotfiles Hyprland baseados em [Jules3182/dotfiles](https://github.com/Jules3182/dotfiles)
- Estrutura modular inspirada no [donarch](https://gitlab.com/don_albert/donarch)
