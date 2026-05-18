# Debian / Ubuntu Setup

This page covers machine-level setup for Debian-based distributions —
primarily Ubuntu (the most common developer-facing Debian derivative)
with notes for vanilla Debian where behavior differs. It is the
prerequisite to the [Onboarding Runbook](../onboarding.md).

Ubuntu's defaults are more developer-friendly out of the box than
Fedora's (codecs are offered during install, drivers are detected
automatically), but its snap strategy creates friction that this page
addresses directly.

## Post-install checklist (first boot)

```sh
# 1. System update
sudo apt update && sudo apt upgrade -y

# 2. Install basic tools immediately (needed for everything else)
sudo apt install -y curl wget git software-properties-common

# 3. Firmware updates (Ubuntu)
sudo fwupdmgr get-devices
sudo fwupdmgr refresh --force
sudo fwupdmgr get-updates
sudo fwupdmgr update

# 4. Reboot (kernel updates, firmware)
sudo reboot
```

## apt configuration

apt's defaults are reasonable. Two additions improve the developer
experience:

### Parallel downloads

Create `/etc/apt/apt.conf.d/99parallel`:

```
Acquire::Queue-Mode "host";
Acquire::http::Pipeline-Depth "10";
```

### Automatic security updates

Ubuntu enables `unattended-upgrades` for security by default. Verify
it is active:

```sh
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

On vanilla Debian, this is not enabled by default — install and
configure it explicitly.

### Backports (Debian only)

Vanilla Debian's stable repositories ship older tool versions. Enable
backports for access to newer packages without switching to testing:

```sh
# /etc/apt/sources.list.d/backports.list
echo "deb http://deb.debian.org/debian $(lsb_release -cs)-backports main" | \
  sudo tee /etc/apt/sources.list.d/backports.list
sudo apt update
```

Install specific packages from backports with:

```sh
sudo apt install -t $(lsb_release -cs)-backports <package>
```

## The snap problem

Ubuntu ships Firefox, Thunderbird, and increasingly other GUI
applications as snaps. For development tools, snaps introduce three
problems:

1. **Startup latency** — snap applications decompress on launch. First
   launch of a snap app after boot takes 3-10 seconds.
2. **Sandbox restrictions** — snaps cannot access arbitrary host paths
   without manual interface connections. This breaks tools that need to
   see `~/.config`, `/tmp`, or project directories outside `$HOME`.
3. **PATH and socket isolation** — snap-installed tools cannot see mise
   shims, the Podman socket, or SSH agent sockets without per-snap
   configuration.

The framework's position: **remove snap versions of developer tools
and install native .deb packages or upstream binaries.**

### Replacing snap Firefox (Ubuntu)

```sh
# Remove snap Firefox
sudo snap remove firefox

# Install Mozilla's official PPA
sudo add-apt-repository ppa:mozillateam/ppa

# Pin PPA version over snap
echo '
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
' | sudo tee /etc/apt/preferences.d/mozilla-firefox

# Prevent apt from re-installing the snap transitional package
echo 'Package: firefox*
Pin: release o=Ubuntu
Pin-Priority: -1
' | sudo tee -a /etc/apt/preferences.d/mozilla-firefox

sudo apt update
sudo apt install firefox
```

### Preventing snap reinstallation

Ubuntu's `ubuntu-desktop` metapackage can pull snap packages back in
during upgrades. Create a preference that blocks the snap transitional
packages:

```sh
# Prevent snap transitional packages from being installed
sudo apt-mark hold firefox snap
```

!!! note "Pragmatism over purity"

    This framework does not advocate removing snapd entirely. Snap is
    fine for consumer applications (Slack, Spotify, Discord) where
    sandbox isolation is a benefit. The guidance is specific:
    development tools that need host integration should not be snaps.

## Multimedia codecs

Ubuntu offers restricted extras during installation. If skipped:

```sh
# Ubuntu
sudo apt install ubuntu-restricted-extras

# Debian
sudo apt install libavcodec-extra
```

For hardware-accelerated video:

```sh
# Intel
sudo apt install intel-media-va-driver-non-free

# AMD
sudo apt install mesa-va-drivers

# NVIDIA (if using proprietary driver)
sudo apt install nvidia-vaapi-driver
```

## Filesystem and storage

### Enable fstrim for SSDs

```sh
sudo systemctl enable --now fstrim.timer
```

### ext4 considerations

Ubuntu defaults to ext4 (not Btrfs like Fedora). ext4 is stable and
fast with no special developer-facing tuning needed. If using Btrfs
(Debian installer offers it, Ubuntu does not by default), see the
Fedora page's Btrfs section — the same `chattr +C` guidance for
container storage applies.

## Firewall

Ubuntu ships with `ufw` (Uncomplicated Firewall) — a frontend to
iptables/nftables. It is installed but **not enabled by default** on
desktop Ubuntu. Enable it:

```sh
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Verify
sudo ufw status verbose
```

Common developer additions:

```sh
# Allow a dev server from LAN
sudo ufw allow 3000/tcp

# Allow SSH (if doing remote development on this machine)
sudo ufw allow ssh

# Remove when done
sudo ufw delete allow 3000/tcp

# Check rules
sudo ufw status numbered
```

On vanilla Debian, `ufw` is available but not pre-installed:

```sh
sudo apt install ufw
```

## AppArmor

Ubuntu uses AppArmor (not SELinux) as its mandatory access control
framework. Like the Fedora page's SELinux guidance: **leave it
enabled.** Do not disable AppArmor to fix a development problem.

```sh
# Check status
sudo aa-status

# See recent denials
sudo dmesg | grep -i apparmor

# Set a profile to complain mode (logging without enforcement)
sudo aa-complain /usr/bin/some-program

# Re-enable enforcement
sudo aa-enforce /usr/bin/some-program
```

Container interaction: Podman on Ubuntu works with AppArmor's default
policies. Unlike SELinux's `:z`/`:Z` suffix requirement on Fedora,
bind mounts in Podman on Ubuntu/Debian work without special labeling
in most cases.

## Systemd services for development

### SSH agent as a user service

Identical to the Fedora setup — see the
[Onboarding Runbook](../onboarding.md) for the full systemd unit.

```sh
systemctl --user enable --now ssh-agent
```

### Podman socket

```sh
systemctl --user enable --now podman.socket
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"
```

### Journal size management

```sh
sudo journalctl --vacuum-size=500M
```

Edit `/etc/systemd/journald.conf`:

```ini
[Journal]
SystemMaxUse=500M
```

## GNOME desktop tuning

Ubuntu ships GNOME (with modifications). The same tuning as Fedora
applies:

```sh
# Key repeat speed
gsettings set org.gnome.desktop.peripherals.keyboard delay 200
gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 25

# Caps Lock as Ctrl
gsettings set org.gnome.desktop.input-sources xkb-options "['caps:ctrl_modifier']"

# Disable hot corner
gsettings set org.gnome.desktop.interface enable-hot-corners false

# Font rendering
gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'
gsettings set org.gnome.desktop.interface font-hinting 'slight'
```

### Ubuntu-specific: minimize button

Ubuntu's GNOME adds a minimize button by default. If using a
tiling workflow or keyboard-driven window management, remove it:

```sh
gsettings set org.gnome.desktop.wm.preferences button-layout 'close:'
```

## Power management (laptops)

```sh
# TLP for advanced power management
sudo apt install tlp tlp-rdw
sudo systemctl enable --now tlp

# Ubuntu uses power-profiles-daemon by default; TLP replaces it
sudo systemctl mask power-profiles-daemon
```

For ThinkPads:

```sh
sudo apt install tp-smapi-dkms acpi-call-dkms
```

## Developer prerequisites

Install before running `bootstrap.sh`:

```sh
sudo apt install \
  zsh git curl wget \
  build-essential cmake pkg-config \
  libssl-dev zlib1g-dev libreadline-dev \
  libffi-dev libyaml-dev \
  libsqlite3-dev libpq-dev \
  fd-find ripgrep fzf jq bat \
  direnv \
  libsecret-tools \
  podman buildah skopeo \
  shellcheck
```

!!! note "fd and bat binary names on Debian/Ubuntu"

    Due to naming conflicts with other packages, Debian/Ubuntu ship
    `fd` as `fdfind` and `bat` as `batcat`. The framework's shell
    configuration creates aliases (`fd=fdfind`, `bat=batcat`) in
    `conf.d/` to normalize this. No manual symlinking needed.

Why each group:

- **zsh, git, curl, wget** — framework hard dependencies.
- **build-essential, cmake, pkg-config, lib*-dev** — build toolchain
  for native extensions. Without these, compiling Ruby, Python C
  extensions, and Node native addons fails.
- **fd-find, ripgrep, fzf, jq, bat** — modern CLI tools the
  framework's aliases and functions expect.
- **direnv** — already wired in `conf.d/70-tools.zsh`.
- **libsecret-tools** — provides `secret-tool`, used by the
  `keychain_get` shell function.
- **podman, buildah, skopeo** — container toolchain. Note: on older
  Ubuntu (22.04), Podman may need the Kubic repository for a current
  version.
- **shellcheck** — shell script static analysis for pre-commit hooks.

### Podman version (Ubuntu 22.04)

Ubuntu 22.04's default Podman package is old (3.4.x). For rootless
networking and compose support, install from the Kubic repo:

```sh
# Only needed on Ubuntu 22.04; 24.04+ ships current Podman
. /etc/os-release
echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/unstable/xUbuntu_${VERSION_ID}/ /" | \
  sudo tee /etc/apt/sources.list.d/podman.list
curl -fsSL "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/unstable/xUbuntu_${VERSION_ID}/Release.key" | \
  sudo gpg --dearmor -o /etc/apt/keyrings/podman.gpg
sudo apt update
sudo apt install podman
```

Ubuntu 24.04 and later ship Podman 4.x+ from the default repositories
— no additional configuration needed.

## VS Code installation

Do not use the snap version of VS Code. Install from Microsoft's apt
repository:

```sh
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
  gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] \
  https://packages.microsoft.com/repos/code stable main" | \
  sudo tee /etc/apt/sources.list.d/vscode.list

sudo apt update
sudo apt install code
```

## After this page

Proceed to the [Onboarding Runbook](../onboarding.md) for framework
installation (`bootstrap.sh`, mise, SSH keys, git identity).
