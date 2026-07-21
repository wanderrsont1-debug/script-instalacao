# Script de Instalação — Niri / Hyprland

![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white)
![Fedora](https://img.shields.io/badge/Fedora-51A2DA?style=for-the-badge&logo=fedora&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)

Script de instalação automatizada para recriar um ambiente Wayland completo em Arch Linux / CachyOS / Fedora e derivados.

---

## 🖥️ Ambientes Suportados

No começo da instalação você escolhe **o compositor** e, no caso do Niri, **o shell**:

| Compositor | Config | Desktop Shell | Distros |
|---|---|---|---|
| **Niri** | KDL (`~/.config/niri`) | **DankMaterialShell (DMS)** *ou* **Noctalia Shell (beta 5.x)** — escolha no início | Arch, CachyOS, Fedora |
| **Hyprland** | Lua (`~/.config/hypr/hyprland.lua`) | **Noctalia Shell** (fixado — a config incluída é cabeada para o Noctalia) | Arch, CachyOS, Fedora |

**1) Compositor** (`select_compositor`):

- **Niri** — compositor *scrollable-tiling* (padrão do projeto).
- **Hyprland** — compositor dinâmico, usando a config Lua (`hyprland.lua`) incluída, já cabeada para o Noctalia (autostart `noctalia --daemon` + atalhos via `noctalia msg`).

**2) Shell** (`select_shell`, apenas para o Niri):

- **DMS** (`dms-shell`) — estável, padrão do projeto.
- **Noctalia** (beta 5.x) — instalado de `noctalia` (repo CachyOS) ou, como fallback, `noctalia-git` (AUR). Os keybinds/autostart do Niri são ajustados automaticamente para o shell escolhido.

> Ao escolher **Hyprland**, o shell é fixado automaticamente em **Noctalia**, pois a config Lua fornecida usa o Noctalia (evita a combinação incoerente de DMS com keybinds do Noctalia).

---

## 🚀 Uso Rápido

```bash
git clone https://github.com/wanderrsont1-debug/script-instalacao
cd script-instalacao
bash install.sh
```

Ao executar, o script perguntará o compositor (Niri/Hyprland) e o shell, e então instalará e configurará o ambiente escolhido com SDDM automaticamente.

> ⚠️ **Não execute como root.** O script pede `sudo` internamente quando necessário.

---



## 📦 O que é instalado (Arch)

| Categoria | Pacotes |
|---|---|
| Base do Portal | `xdg-desktop-portal`, `xdg-desktop-portal-gtk` (comum aos dois compositores) |
| Compositor: **Niri** | `niri`, `xdg-desktop-portal-gnome` |
| Compositor: **Hyprland** | `hyprland`, `xdg-desktop-portal-hyprland`, `hyprland-qtutils`, `jq` (+ `grim`/`slurp` da base) |
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
| Segurança | `gnome-keyring`, `seahorse`, `ufw` (o agente polkit vem do próprio shell) |
| Navegadores (menu) | **Arch:** `firefox`, `zen-browser-bin`, `helium-browser-bin`, `brave-bin`, `librewolf-bin`, `mullvad-browser-bin` — seleção múltipla<br>**Fedora:** `firefox` (nativo), Zen e Helium (COPR), Brave (instalador oficial), LibreWolf e Vivaldi (repo do fornecedor) |
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
- **Navegadores nunca via Flatpak** — no Fedora cada navegador vem da origem nativa recomendada pelo próprio projeto (COPR, repositório do fornecedor ou instalador oficial), por decisão de projeto
- **UFW** — `deny incoming` / `allow outgoing`, ativo e habilitado no boot
- **Nenhum agente polkit avulso é instalado** — DMS e Noctalia já trazem o seu (`PolkitService.qml` no DMS; `polkit_agent = true` no Noctalia). Dois agentes na mesma sessão disputam o mesmo nome no D-Bus e um deles falha com *"An authentication agent already exists for the given subject"*. Por isso `polkit-gnome`/`mate-polkit` foram removidos das listas de pacotes, a verificação final avisa se sobrar um `spawn-at-startup` de agente polkit na config do Niri, e — como rede de segurança — o autostart XDG de agentes de terceiros é desativado via `~/.config/autostart` (apenas quando o `.desktop` de fato se aplicaria à sessão, respeitando `OnlyShowIn`/`NotShowIn`)

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
│   ├── dotfiles.sh             (deploy de dotfiles + seleção de shell; Niri/Hyprland)
│   ├── greeter.sh              (configuração SDDM + garantia do SDDM + verificações)
│   └── system.sh               (snapshot, mirrors, UFW, Flathub, grupos)
│
├── packages/                   ← Listas de pacotes por distro/ambiente
│   ├── arch-base.txt           ← Apps comuns (independentes do compositor)
│   ├── arch-niri.txt           ← Compositor Niri
│   ├── arch-hyprland.txt       ← Compositor Hyprland
│   ├── arch-sddm.txt
│   ├── arch-fonts.txt
│   ├── arch-browsers.txt       ← Navegadores (menu de seleção múltipla)
│   ├── arch-codecs.txt         ← Codecs multimídia (opt-in)
│   ├── arch-libs.txt           ← Bibliotecas/utilitários essenciais (opt-in)
│   ├── arch-optional.txt
│   │
│   ├── fedora-browsers.txt     ← Navegadores no Fedora (menu; sem Flatpak)
│   ├── fedora-libs.txt         ← Bibliotecas/utilitários essenciais (opt-in)
│   └── fedora-optional.txt     ← Apps opcionais (menu de seleção múltipla)
│
├── dotfiles/                   ← Dotfiles (o compositor não escolhido é ignorado)
│   ├── niri/                   ← Config do Niri (KDL)
│   │   ├── cfg/                ← Fragmentos; autostart/keybinds/shell-extra
│   │   │                         são trocados conforme o shell escolhido
│   │   └── dms/                ← Fragmentos gerados pelo DMS (só com DMS)
│   ├── hypr/                   ← Config do Hyprland (hyprland.lua)
│   └── noctalia/               ← settings.toml base do Noctalia (sanitizado);
│                                 vai para ~/.local/state/noctalia/
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
