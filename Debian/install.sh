#!/bin/bash
# ============================================================================
# Debian 12 (bookworm) workstation installer — github.com/teleportboy/Linux
#
# Fresh netinstall -> full i3 + dev environment in one run. Idempotent.
# Usage:  bash install.sh          (NOT `sh install.sh`)
# Docs:   docs/spec_install.md, docs/install_usage.md, plan_linux.md
# ============================================================================

# POSIX guard: everything below needs bash (dash dies on ${BASH_SOURCE[0]})
if [ -z "${BASH_VERSION:-}" ]; then
    echo "ERROR: run it with bash:  bash install.sh" >&2
    exit 1
fi

set -o errexit -o errtrace -o pipefail
SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------- section flags ---------------------------------
INSTALL_DESKTOP=1        # GUI apps: qbittorrent, zathura, okular, filezilla...
INSTALL_DEV_BASE=1       # cmake, ninja, meld/kdiff3, python tooling
INSTALL_DEV_EMBEDDED=1   # ARM toolchain, CAN, serial terminals, J-Link
INSTALL_DEV_QT=1         # QtCreator + Qt5 dev
INSTALL_YOCTO_DEPS=1     # Yocto/buildroot host dependencies
INSTALL_RUST=1           # rustup + rustlings
INSTALL_NODE=1           # nvm + node
INSTALL_SERVER=1         # openssh-server, postgresql, nfs client
INSTALL_NFS_SERVER=0     # Debix NFS exports; set NFS_SUBNET to your LAN first
INSTALL_FLATPAK_SNAP=1   # flatpak: Flameshot, Telegram; snap: android-studio, postman
INSTALL_EXTRA_APPS=1     # Chrome, Opera, VS Code, Antigravity, bcompare, discord...

GIT_NAME="teleportboy"
GIT_EMAIL="be.a.satori@gmail.com"
NFS_SUBNET="192.168.1.0/24"   # placeholder — set your real subnet before enabling
NVM_VERSION="v0.40.3"
NODE_VERSION="22"
LOG_FILE="$HOME/install-linux.log"

# ------------------------------- helpers ------------------------------------
SKIPPED=()

log()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[WARN] %s\033[0m\n' "$*"; SKIPPED+=("$*"); }
# Best-effort wrapper: network/third-party steps must not kill the run.
# NOTE: errexit is OFF inside functions called via try — chain steps with &&
# or `|| return 1` so a mid-function failure can't fake success.
try()  { "$@" || warn "skipped: $*"; }

apt_install() {
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

# Generic ".deb from URL" installer, skips if already installed.
install_deb() {
    local name="$1" url="$2"
    dpkg -s "$name" > /dev/null 2>&1 && return 0
    curl -fsSL "$url" -o "/tmp/$name.deb" && apt_install "/tmp/$name.deb"
}

trap 'echo "[FAIL] line $LINENO: $BASH_COMMAND" >&2' ERR

# ------------------------------- guards -------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: run as a regular user, the script calls sudo itself" >&2
    exit 1
fi
if ! grep -q '^12\.' /etc/debian_version 2> /dev/null; then
    echo "WARNING: this is not Debian 12 ($(cat /etc/debian_version 2> /dev/null))," >&2
    echo "         the script is only tested on bookworm. Ctrl+C to abort, Enter to continue." >&2
    read -r < /dev/tty || { echo "non-interactive run, aborting" >&2; exit 1; }
fi
# netinstall with a non-empty root password does NOT install sudo / add the
# user to sudoers — catch it here with a clear way out
if ! command -v sudo > /dev/null 2>&1; then
    echo "ERROR: sudo is not installed. Run as root:" >&2
    echo "    su -c 'apt-get install -y sudo && /usr/sbin/usermod -aG sudo $USER'" >&2
    echo "then log out, log back in and re-run this script." >&2
    exit 1
fi
if ! sudo -v; then
    echo "ERROR: user $USER has no sudo rights. Run as root:" >&2
    echo "    su -c '/usr/sbin/usermod -aG sudo $USER'" >&2
    echo "then log out, log back in and re-run this script." >&2
    exit 1
fi

exec > >(tee -a "$LOG_FILE") 2>&1
VIRT="$(systemd-detect-virt 2> /dev/null || true)"
log "Start: virt=$VIRT, log=$LOG_FILE, repo=$SCRIPT_PATH"

# NOPASSWD first: long apt sections outlive the 15-min sudo ticket, and an
# expired ticket means the run stops at a password prompt forever
setup_sudo_nopasswd() {
    log "sudo NOPASSWD for $USER (no more password prompts)"
    local tmp
    tmp="$(mktemp)"
    echo "$USER ALL=(ALL) NOPASSWD: ALL" > "$tmp"
    if sudo visudo -cf "$tmp" > /dev/null; then
        sudo install -m 0440 "$tmp" "/etc/sudoers.d/90-$USER-nopasswd"
    else
        warn "sudoers file failed visudo check — NOPASSWD not installed"
    fi
    rm -f "$tmp"
}

# --------------------------- apt: sources + base ----------------------------
setup_apt() {
    log "APT: sources.list (contrib + non-free) + upgrade"
    [ -f /etc/apt/sources.list.bak ] || sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    sudo cp "$SCRIPT_PATH/etc/apt/sources.list" /etc/apt/sources.list
    # tolerant update: on re-runs a dead third-party repo must not kill the run;
    # if the main Debian mirror is down, the next apt_install fails loudly anyway
    sudo apt-get update || warn "apt update: some repos unreachable"
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade
}

install_base() {
    log "Base: X, i3, urxvt, polybar, fonts, audio, CLI tools"
    apt_install \
        xinit xserver-xorg x11-utils xsel xclip arandr \
        i3 dex polybar rxvt-unicode \
        curl wget git build-essential htop psmisc lsof usbutils \
        apt-transport-https ca-certificates gnupg \
        zenity xautolock baobab doublecmd-qt \
        ripgrep nnn p7zip-full vim colordiff socat netcat-traditional inetutils-telnet \
        pulseaudio pulseaudio-utils \
        keyboard-configuration console-setup \
        fonts-jetbrains-mono fonts-noto-cjk fonts-open-sans \
        breeze-cursor-theme libfuse2
    # mscorefonts separately: its postinst downloads .exe files from SourceForge
    # mirrors and dies/hangs when they are down — must not kill the whole run.
    # (No EULA preseed needed: the Debian package has no such debconf template.)
    try apt_install ttf-mscorefonts-installer
    sudo fc-cache -f > /dev/null
    sudo update-alternatives --set x-cursor-theme /etc/X11/cursors/Breeze_Snow.theme
}

# --------------------------- hardware branches ------------------------------
setup_network_manager() {
    apt_install network-manager network-manager-gnome
    # Hand interfaces over to NM: ifupdown-managed ifaces are ignored by it
    if awk '$1 ~ /^(auto|allow-hotplug|iface)$/ && $2 != "lo" {found=1} END {exit !found}' \
        /etc/network/interfaces 2> /dev/null; then
        sudo cp /etc/network/interfaces /etc/network/interfaces.bak
        printf 'auto lo\niface lo inet loopback\n' | sudo tee /etc/network/interfaces > /dev/null
    fi
    sudo systemctl enable NetworkManager
}

setup_hardware() {
    case "$VIRT" in
        vmware)
            log "Hardware: VMware guest"
            apt_install open-vm-tools open-vm-tools-desktop
            ;;
        none)
            log "Hardware: bare metal — firmware, microcode, NetworkManager"
            if grep -qi GenuineIntel /proc/cpuinfo; then
                apt_install intel-microcode iucode-tool
            elif grep -qi AuthenticAMD /proc/cpuinfo; then
                apt_install amd64-microcode
            fi
            # all three wifi families: cheaper to install extra than be offline
            apt_install firmware-linux firmware-misc-nonfree \
                firmware-iwlwifi firmware-realtek firmware-atheros
            apt_install bluez blueman
            if compgen -G '/sys/class/power_supply/BAT*' > /dev/null; then
                apt_install tlp tlp-rdw acpid brightnessctl
                sudo systemctl enable tlp
            fi
            setup_network_manager
            ;;
        *)
            log "Hardware: virt=$VIRT — no hardware-specific packages"
            ;;
    esac
}

# ----------------------------- system config --------------------------------
configure_system() {
    log "System: locales, timezone, keyboard (us,ru Win+Space), groups, udev"
    sudo sed -i \
        -e 's/^# *\(en_US\.UTF-8 UTF-8\)/\1/' \
        -e 's/^# *\(ru_RU\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
    sudo locale-gen > /dev/null
    sudo update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en
    try sudo timedatectl set-timezone Asia/Bishkek

    sudo cp "$SCRIPT_PATH/etc/default/keyboard" /etc/default/keyboard
    try sudo udevadm trigger --subsystem-match=input --action=change

    sudo usermod -aG dialout,plugdev,netdev,audio,video "$USER"

    sudo cp "$SCRIPT_PATH/etc/udev/rules.d/99-usb-serial.rules" /etc/udev/rules.d/
    sudo udevadm control --reload-rules
}

# ------------------------------- sections -----------------------------------
install_desktop_apps() {
    log "Desktop apps"
    apt_install qbittorrent filezilla okular zathura zathura-pdf-poppler
}

install_dev_base() {
    log "Dev base"
    apt_install cmake ninja-build bc meld kdiff3 gitg diffstat sharutils \
        python3-pip python3-venv python-is-python3 python3-pexpect
    try pip3 install --user --break-system-packages openpyxl
}

install_jlink() {
    dpkg -s jlink > /dev/null 2>&1 && return 0
    # SEGGER requires accepting the license — POST field does exactly that
    curl -fsSL -X POST -d 'accept_license_agreement=accepted' \
        https://www.segger.com/downloads/jlink/JLink_Linux_x86_64.deb -o /tmp/jlink.deb \
        && apt_install /tmp/jlink.deb
}

install_dev_embedded() {
    log "Embedded: ARM toolchain, CAN, serial, J-Link"
    apt_install gcc-arm-none-eabi libnewlib-arm-none-eabi binutils-arm-none-eabi \
        gdb-multiarch device-tree-compiler can-utils binwalk evtest \
        minicom picocom cutecom gtkterm putty \
        libqt5serialbus5 libqt5serialbus5-dev dfu-util liblz4-tool
    try install_jlink
    # NXP LinkServer/MCU-Link/lpcscrypt/pemicro: MCUXpressoInstaller only (NXP login)
}

install_dev_qt() {
    log "Qt dev"
    apt_install qtcreator qtbase5-dev qt5-qmake libgl1-mesa-dev mesa-common-dev
}

install_yocto_deps() {
    log "Yocto/buildroot host dependencies"
    apt_install gawk diffstat unzip texinfo gcc-multilib chrpath socat cpio \
        python3-pexpect xz-utils debianutils iputils-ping libsdl1.2-dev \
        xterm xvfb flex bison liblz4-tool libgmp-dev libmpfr-dev libmpc-dev
}

install_extra_apps() {
    log "Third-party repos + apps: VS Code, Opera, bcompare, Antigravity, yandex-music"
    sudo install -d -m 0755 /etc/apt/keyrings
    sudo install -m 0644 "$SCRIPT_PATH/etc/apt/keyrings/microsoft.gpg" /usr/share/keyrings/microsoft.gpg
    sudo install -m 0644 \
        "$SCRIPT_PATH/etc/apt/keyrings/antigravity-repo-key.gpg" \
        "$SCRIPT_PATH/etc/apt/keyrings/cucumber-space.key.gpg" \
        "$SCRIPT_PATH/etc/apt/keyrings/DEB-GPG-KEY-scootersoftware.asc" \
        /etc/apt/keyrings/
    sudo install -m 0644 "$SCRIPT_PATH"/etc/apt/trusted.gpg.d/opera.archive.key.*.gpg /etc/apt/trusted.gpg.d/
    sudo cp "$SCRIPT_PATH"/etc/apt/sources.list.d/*.list "$SCRIPT_PATH"/etc/apt/sources.list.d/*.sources \
        /etc/apt/sources.list.d/
    # one dead third-party repo must cost one package, not the rest of the run
    sudo apt-get update || warn "apt update: some third-party repos unreachable"
    local p
    for p in code antigravity bcompare yandex-music opera-stable mono-complete; do
        try apt_install "$p"
    done
    # Chrome .deb registers its own repo for future updates
    try install_deb google-chrome-stable \
        "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
    try install_deb discord "https://discord.com/api/download?platform=linux&format=deb"
    try install_deb gitkraken "https://release.gitkraken.com/linux/gitkraken-amd64.deb"
}

install_flatpak_snap() {
    log "Flatpak (Flameshot, Telegram) + snap (android-studio, postman)"
    apt_install flatpak plasma-discover plasma-discover-backend-flatpak
    try sudo flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    try sudo flatpak install -y --noninteractive flathub \
        org.flameshot.Flameshot org.telegram.desktop
    apt_install snapd
    # snap can hang forever on a flaky store connection — cap every call
    try timeout 600 sudo snap wait system seed.loaded
    try timeout 1800 sudo snap install android-studio --classic
    try timeout 1800 sudo snap install postman --channel=v11/stable
}

install_server() {
    log "Server: ssh, postgresql, nfs client"
    apt_install openssh-server nfs-common
    sudo systemctl enable ssh
    apt_install postgresql postgresql-contrib libpq-dev postgresql-server-dev-all
    sudo systemctl enable postgresql
}

install_nfs_server() {
    log "NFS server: Debix exports for $NFS_SUBNET"
    apt_install nfs-kernel-server
    sudo mkdir -p /nfs/nfs_debix /nfs/nfs_debix_6122
    local dir
    for dir in /nfs/nfs_debix /nfs/nfs_debix_6122; do
        if ! grep -qs "^$dir " /etc/exports; then
            echo "$dir $NFS_SUBNET(rw,sync,no_subtree_check,no_root_squash)" \
                | sudo tee -a /etc/exports > /dev/null
        fi
    done
    sudo exportfs -ra
}

# --------------------------- shell + dotfiles -------------------------------
setup_omz() {
    [ -d "$HOME/.oh-my-zsh" ] && return 0
    # download to a file first: `sh -c "$(failed curl)"` is a silent no-op
    curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
        -o /tmp/omz-install.sh \
        && RUNZSH=no CHSH=no sh /tmp/omz-install.sh --unattended \
        && [ -d "$HOME/.oh-my-zsh" ]
}

setup_zsh() {
    log "zsh + oh-my-zsh (unattended) + powerline"
    apt_install zsh powerline
    try setup_omz
    sudo chsh -s /usr/bin/zsh "$USER"
}

deploy_dotfiles() {
    log "Dotfiles from repo -> \$HOME (overwrites, repo is the source of truth)"
    cp -a "$SCRIPT_PATH/home/." "$HOME/"
    chmod +x "$HOME/.config/polybar/launch.sh" "$HOME/bin/telega.sh"
}

# ------------------------------ user tools ----------------------------------
setup_rust() {
    if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
        curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
            | sh -s -- -y --no-modify-path || return 1
    fi
    [ -f "$HOME/.cargo/env" ] || return 1
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
    [ -x "$HOME/.cargo/bin/rustlings" ] || cargo install rustlings
}

setup_node() {
    if [ ! -d "$HOME/.nvm" ]; then
        # PROFILE=/dev/null: .zshrc from the repo already has the nvm block
        curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" \
            -o /tmp/nvm-install.sh || return 1
        PROFILE=/dev/null bash /tmp/nvm-install.sh || return 1
    fi
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install "$NODE_VERSION"
}

setup_claude() {
    # PATH check alone re-downloads on every rerun before relogin
    [ -x "$HOME/.local/bin/claude" ] && return 0
    command -v claude > /dev/null 2>&1 && return 0
    curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh \
        && bash /tmp/claude-install.sh
}

install_lazygit() {
    command -v lazygit > /dev/null 2>&1 && return 0
    local d ver rc=0
    d="$(mktemp -d)"
    {
        ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
            | grep -Po '"tag_name": *"v\K[^"]*')" \
        && curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_x86_64.tar.gz" \
            -o "$d/lazygit.tgz" \
        && tar -xzf "$d/lazygit.tgz" -C "$d" lazygit \
        && sudo install -m 0755 "$d/lazygit" /usr/local/bin/lazygit
    } || rc=1
    rm -rf "$d"
    return "$rc"
}

install_nvim() {
    if [ ! -x /opt/nvim/nvim ]; then
        # download first, install atomically: a partial file would poison the guard
        curl -fsSL \
            https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage \
            -o /tmp/nvim.appimage || return 1
        sudo install -D -m 0755 /tmp/nvim.appimage /opt/nvim/nvim
    fi
    if [ ! -d "$HOME/.config/nvim" ]; then
        git clone https://github.com/LazyVim/starter "$HOME/.config/nvim" || return 1
        rm -rf "$HOME/.config/nvim/.git"
    fi
}

install_repo_tool() {
    [ -x "$HOME/bin/repo" ] && return 0
    mkdir -p "$HOME/bin"
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /tmp/repo.dl \
        || return 1
    install -m 0755 /tmp/repo.dl "$HOME/bin/repo"
}

install_user_tools() {
    log "User tools: rust, node, claude, lazygit, nvim+LazyVim, repo, git config"
    if [ "$INSTALL_RUST" = 1 ]; then try setup_rust; fi
    if [ "$INSTALL_NODE" = 1 ]; then try setup_node; fi
    try setup_claude
    try install_lazygit
    try install_nvim
    try install_repo_tool
    git config --global user.name > /dev/null 2>&1 || git config --global user.name "$GIT_NAME"
    git config --global user.email > /dev/null 2>&1 || git config --global user.email "$GIT_EMAIL"
}

# ------------------------------- summary ------------------------------------
print_summary() {
    log "DONE"
    if [ "${#SKIPPED[@]}" -gt 0 ]; then
        printf '\n\033[1;33mSkipped steps (redo by hand or re-run the script):\033[0m\n'
        printf '  - %s\n' "${SKIPPED[@]}"
    fi
    cat << 'EOF'

Manual steps left:
  1. reboot                      # groups, microcode, NetworkManager
  2. login -> startx             # layout toggle: Win+Space
  3. wifi: nmtui                 # bare metal only
  4. copy from the old machine:
       ~/.ssh (then: chmod 700 ~/.ssh && chmod 600 ~/.ssh/*)
       ~/WORKSHOP  /opt/kobus9  /opt/serverKobus
       /opt/aarch64-buildroot-linux-gnu_sdk-buildroot  ~/bin/GitExtensions
  5. NXP tools: MCUXpressoInstaller from nxp.com (needs NXP account)
  6. Cursor AppImage + RustRover tarball -> ~/apps
EOF
}

# -------------------------------- main --------------------------------------
setup_sudo_nopasswd
setup_apt
install_base
setup_hardware
configure_system
if [ "$INSTALL_DESKTOP" = 1 ]; then install_desktop_apps; fi
if [ "$INSTALL_DEV_BASE" = 1 ]; then install_dev_base; fi
if [ "$INSTALL_DEV_EMBEDDED" = 1 ]; then install_dev_embedded; fi
if [ "$INSTALL_DEV_QT" = 1 ]; then install_dev_qt; fi
if [ "$INSTALL_YOCTO_DEPS" = 1 ]; then install_yocto_deps; fi
if [ "$INSTALL_EXTRA_APPS" = 1 ]; then install_extra_apps; fi
if [ "$INSTALL_FLATPAK_SNAP" = 1 ]; then install_flatpak_snap; fi
if [ "$INSTALL_SERVER" = 1 ]; then install_server; fi
if [ "$INSTALL_NFS_SERVER" = 1 ]; then install_nfs_server; fi
setup_zsh
deploy_dotfiles
install_user_tools
print_summary
