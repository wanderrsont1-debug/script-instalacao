# Script de Instalação — Niri

![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white)
![Fedora](https://img.shields.io/badge/Fedora-51A2DA?style=for-the-badge&logo=fedora&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)

Script de instalação automatizada para recriar um ambiente Wayland completo em Arch Linux / CachyOS / Fedora e derivados.

---

## 🖥️ Ambientes Suportados

| Ambiente | Compositor | Desktop Shell | Distros |
|---|---|---|---|
| **Niri** | Niri (Wayland) | **DankMaterialShell (DMS)** *ou* **Noctalia Shell (beta 5.x)** — escolha no início | Arch, CachyOS, Fedora |

No começo da instalação você escolhe o shell:

- **DMS** (`dms-shell`) — estável, padrão do projeto.
- **Noctalia** (beta 5.x) — instalado de `noctalia` (repo CachyOS) ou, como fallback, `noctalia-git` (AUR). Os keybinds/autostart do Niri são ajustados automaticamente para o shell escolhido.

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
| Shell de Desktop | `dms-shell` **ou** `noctalia`/`noctalia-git` (escolha), `matugen` |
| Terminais | `alacritty`, `ghostty` |
| Launcher | `fuzzel` |
| Shell | `fish` |
| Editor | `micro` |
| Monitor / Fetch | `btop`, `fastfetch`, `cava` |
| Áudio | `pipewire`, `pipewire-pulse`, `pipewire-alsa`, `wireplumber`, `pavucontrol` |
| Bluetooth | `bluez`, `bluez-utils` |
| Rede | `networkmanager` |
| Multimídia | `mpv`, `ffmpeg`, `gst-plugins-*` |
| Apps GUI | `nautilus`, `keepassxc`, `gnome-disk-utility`, `flatpak` |
| Fontes | `noto-fonts`, `noto-fonts-emoji`, `cantarell-fonts`, `ttf-meslo-nerd` |
| Display Manager | `sddm` (com tema SilentSDDM) |
| Segurança | `polkit-gnome`, `gnome-keyring`, `seahorse`, `ufw` |
| Navegadores (menu) | `firefox`, `zen-browser-bin`, `helium-browser-bin`, `brave-bin`, `librewolf-bin`, `mullvad-browser-bin` — seleção múltipla |
| Codecs (opt-in) | `gst-plugins-*`, `x264`/`x265`, `dav1d`, `aom`, `svt-av1`, `opus`, `flac`, `lame`, `libva-utils`, … |
| Bibliotecas (opt-in) | `man-db`, `bash-completion`, `7zip`, `unrar`, `gvfs*`, `ntfs-3g`, `exfatprogs`, `usbutils`, `reflector`, … |
| Opcionais | `anki`, `calibre` |

---



## 🔒 Segurança

- Backup automático de `~/.config` com timestamp antes de qualquer alteração
- Nunca executa como root
- Falhas em pacotes AUR individuais não abortam a instalação
- Instalação de pacotes cai para modo "um a um" se a transação em lote falhar (não perde válidos como o `sddm`)
- **SDDM garantido em múltiplas camadas**: transação dedicada com retry (`ensure_sddm_installed`), auto-reparo na verificação final e habilitação forçada da unit
- **Snapshot do sistema antes de instalar** (snapper ou timeshift)
- **Firewall UFW** habilitado com política segura (nega entrada, permite saída)
- Conflitos de dotfiles tratados com `--restow`

## ⚙️ Configurações de sistema aplicadas

- **Snapshot pré-instalação** — snapper (`-c root`) ou timeshift, criado antes das mudanças
- **Mirrors otimizados** — `reflector` (20 mais rápidos, HTTPS) com backup do mirrorlist (Arch)
- **Grupos do usuário** — adiciona a `video`, `input`, `wheel`, `storage`, `audio`, `network` (só os existentes)
- **Flatpak + Flathub** — remote Flathub adicionado automaticamente
- **UFW** — `deny incoming` / `allow outgoing`, ativo e habilitado no boot

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
│   ├── dotfiles.sh             (deploy de dotfiles Niri + seleção de shell)
│   ├── greeter.sh              (configuração SDDM + garantia do SDDM)
│   └── system.sh               (snapshot, mirrors, UFW, Flathub, grupos)
│
├── packages/                   ← Listas de pacotes por distro/ambiente
│   ├── arch-base.txt
│   ├── arch-sddm.txt
│   ├── arch-fonts.txt
│   ├── arch-browsers.txt       ← Navegadores (menu de seleção múltipla)
│   ├── arch-codecs.txt         ← Codecs multimídia (opt-in)
│   ├── arch-libs.txt           ← Bibliotecas/utilitários essenciais (opt-in)
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
