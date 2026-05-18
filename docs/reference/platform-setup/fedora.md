# Fedora Workstation Setup

This page covers the machine-level setup that makes a fresh Fedora
Workstation installation ready for development work. It is the
prerequisite to the [Onboarding Runbook](../onboarding.md) — everything
here happens before `bootstrap.sh` runs.

The goal is a fast, secure, well-configured workstation with firmware
current, codecs installed, dnf optimized, and system services tuned for
a developer's workflow. None of this is framework-specific; it is the
base that any development environment needs.

## Post-install checklist (first boot)

Run these immediately after a fresh Fedora Workstation install, before
doing anything else:

```sh
# 1. System update (reboot after — kernel and firmware)
sudo dnf upgrade --refresh
sudo reboot

# 2. Enable RPM Fusion (free + nonfree)
sudo dnf install \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# 3. Firmware updates via fwupd
sudo fwupdmgr get-devices
sudo fwupdmgr refresh --force
sudo fwupdmgr get-updates
sudo fwupdmgr update
```

## dnf configuration

Fedora's package manager is conservative by default. These settings
make it faster and more informative without sacrificing correctness.

Edit `/etc/dnf/dnf.conf`:

```ini
[main]
gpgcheck=True
installonly_limit=3
clean_requirements_on_remove=True
best=False
skip_if_unavailable=True

# Performance
max_parallel_downloads=10
fastestmirror=True
deltarpm=True

# Informational
defaultyes=True
countme=False
```

Key choices:

- **`max_parallel_downloads=10`** — saturates modern connections.
  Default of 3 is a relic of slower networks.
- **`fastestmirror=True`** — measures mirror latency on first use and
  prefers the fastest. Small upfront cost, significant ongoing gain.
- **`deltarpm=True`** — downloads binary diffs instead of full packages
  during updates. Saves bandwidth on incremental updates.
- **`best=False`** — allows dnf to skip packages with broken
  dependencies rather than failing the entire transaction. Prevents
  the "one broken COPR package blocks all updates" problem.
- **`countme=False`** — disables the anonymous weekly request that
  Fedora uses for usage statistics.

## Multimedia codecs

Fedora ships without patent-encumbered codecs. After enabling RPM
Fusion:

```sh
# GStreamer codecs (covers most media playback needs)
sudo dnf install \
  gstreamer1-plugins-{bad-\*,good-\*,base} \
  gstreamer1-plugin-openh264 \
  gstreamer1-libav \
  --exclude=gstreamer1-plugins-bad-free-devel

# Hardware-accelerated video decode (Intel/AMD)
sudo dnf install libva-utils intel-media-driver   # Intel
sudo dnf install libva-utils mesa-va-drivers      # AMD

# OpenH264 from Cisco (fedora-cisco-openh264 repo, enabled by default)
sudo dnf install mozilla-openh264
```

## Filesystem and storage

### Enable fstrim for SSDs

Most Fedora installs on SSDs benefit from periodic TRIM. The systemd
timer is included but not always enabled:

```sh
sudo systemctl enable --now fstrim.timer
```

This runs weekly. For heavy I/O workloads (large git repos, container
builds), weekly is sufficient — continuous TRIM (`discard` mount
option) adds write amplification.

### Btrfs considerations

Fedora defaults to Btrfs on Workstation installs. Relevant settings
for development:

```sh
# Check current subvolume layout
sudo btrfs subvolume list /

# Disable copy-on-write for VM images and database files
# (CoW causes fragmentation and write amplification on large files)
chattr +C ~/VMs
chattr +C ~/.local/share/containers
```

The `+C` attribute applies to new files in the directory, not
retroactively to existing ones. Set it before populating these paths.

!!! note "Snapshots"

    Btrfs snapshots are cheap and useful for pre-upgrade safety nets.
    However, this framework does not prescribe a snapshot management
    tool (Timeshift, snapper, btrbk) — choose one, automate it, and
    test restore before depending on it.

## SELinux

Fedora ships with SELinux enforcing. **Leave it enforcing.** Disabling
SELinux to "fix" a development problem is the container equivalent of
running everything as root — it works until it doesn't, and the habits
it builds are actively harmful in production.

Common developer interactions with SELinux:

```sh
# Check current mode
getenforce                        # should say "Enforcing"

# See recent denials
sudo ausearch -m avc -ts recent

# Temporary permissive mode for a specific domain (debugging only)
sudo semanage permissive -a httpd_t

# Generate a local policy module from denials
sudo ausearch -m avc -ts recent | audit2allow -M my_local_fix
sudo semodule -i my_local_fix.pp

# Restore file contexts after moving files
sudo restorecon -Rv /path/to/moved/files
```

### Container-specific SELinux

Podman with SELinux requires the `:z` or `:Z` suffix on bind mounts:

```sh
# :z — shared label (multiple containers can access)
podman run -v ~/project:/app:z my-image

# :Z — private label (only this container can access)
podman run -v ~/secrets:/run/secrets:Z my-image
```

Without these suffixes, SELinux denies the container access to
host-mounted paths. This is the single most common "it works with
Docker Desktop but not Podman" complaint — Docker Desktop's VM does
not enforce host SELinux policy on bind mounts.

## Firewall

Fedora uses `firewalld` with zone-based rules. The default zone
(`FedoraWorkstation`) allows SSH inbound and blocks everything else,
which is correct for a development machine.

```sh
# View current state
sudo firewall-cmd --state
sudo firewall-cmd --list-all

# Common developer additions:
# Allow a dev server to be reachable from other devices on the LAN
sudo firewall-cmd --add-port=3000/tcp              # transient (until reboot)
sudo firewall-cmd --add-port=3000/tcp --permanent  # survives reboot
sudo firewall-cmd --reload                         # apply permanent rules

# Allow mDNS/Avahi (useful for device testing)
sudo firewall-cmd --add-service=mdns --permanent

# Remove when done
sudo firewall-cmd --remove-port=3000/tcp --permanent
sudo firewall-cmd --reload
```

The framework's position: open ports deliberately and close them when
done. Do not disable the firewall to make a dev server reachable — add
the specific port, test, remove it.

## Systemd services for development

### SSH agent as a user service

The [Onboarding Runbook](../onboarding.md) covers the full ssh-agent
systemd service. Ensure it starts on login:

```sh
systemctl --user enable --now ssh-agent
```

### Podman socket (for Docker-compatible tooling)

Some tools expect a Docker-compatible socket. Podman provides one via
a systemd user service:

```sh
systemctl --user enable --now podman.socket

# Verify
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"
docker info   # should work (via podman's compatibility API)
```

This avoids the manual socket symlink documented on the
[Containers](../../tools/containers.md) page and integrates with systemd's
socket activation (zero idle resource use).

### Journal size management

Systemd's journal grows unbounded by default. On a development
workstation, 500M is more than sufficient for debugging and prevents
the journal from consuming disk during long-running builds:

```sh
sudo journalctl --vacuum-size=500M
```

To make the limit permanent, edit `/etc/systemd/journald.conf`:

```ini
[Journal]
SystemMaxUse=500M
```

## GNOME desktop tuning

Fedora Workstation ships GNOME. These are not cosmetic preferences —
they are settings that affect developer productivity.

### Keyboard and input

```sh
# Key repeat speed (default is sluggish for terminal work)
gsettings set org.gnome.desktop.peripherals.keyboard delay 200
gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 25

# Caps Lock as additional Ctrl (matches the framework's emacs-mode stance)
gsettings set org.gnome.desktop.input-sources xkb-options "['caps:ctrl_modifier']"

# Disable hot corner (accidental Activities trigger)
gsettings set org.gnome.desktop.interface enable-hot-corners false
```

### Window management

```sh
# Focus-follows-mouse (useful for tiling workflows)
gsettings set org.gnome.desktop.wm.preferences focus-mode 'sloppy'

# Attach modal dialogs (prevents lost dialogs on multi-monitor)
gsettings set org.gnome.mutter attach-modal-dialogs true

# Workspaces on all displays
gsettings set org.gnome.mutter workspaces-only-on-primary false
```

### Font rendering

```sh
# Enable subpixel antialiasing (crisper text on LCD displays)
gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'
gsettings set org.gnome.desktop.interface font-hinting 'slight'
```

### Night Light

```sh
# Reduce blue light on schedule (reduces eye strain for late sessions)
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 3500
```

## Power management (laptops)

For Fedora on laptops, power management is the difference between a
productive mobile session and a three-hour battery life:

```sh
# Install TLP (advanced power management, replaces power-profiles-daemon)
sudo dnf install tlp tlp-rdw
sudo systemctl enable --now tlp
sudo systemctl mask power-profiles-daemon  # conflicts with TLP

# Verify
sudo tlp-stat -s
```

TLP's defaults are sane for most hardware. For ThinkPads, the
additional `kernel-devel` and `akmod-acpi_call` packages enable
battery charge thresholds:

```sh
# ThinkPad-specific: limit charge to 80% (extends battery lifespan)
sudo dnf install kernel-devel akmod-acpi_call
echo 80 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold
```

## Developer prerequisites

These packages should be installed before running `bootstrap.sh`.
They provide the system-level dependencies that the framework and its
tools expect:

```sh
sudo dnf install \
  zsh git curl wget \
  gcc gcc-c++ make cmake \
  openssl-devel zlib-devel readline-devel \
  libffi-devel libyaml-devel \
  sqlite-devel postgresql-devel \
  fd-find ripgrep fzf jq bat \
  direnv \
  libsecret \
  podman podman-compose buildah skopeo \
  ShellCheck
```

Why each group:

- **zsh, git, curl, wget** — framework hard dependencies.
- **gcc, make, cmake, openssl-devel, etc.** — build toolchain for
  native extensions (Ruby gems, Python C extensions, Node native
  addons). Without these, `rv install` and `uv sync` fail on packages
  that compile from source.
- **fd-find, ripgrep, fzf, jq, bat** — the modern CLI tools the
  framework's aliases and functions expect.
- **direnv** — already wired in `conf.d/70-tools.zsh`.
- **libsecret** — provides `secret-tool`, used by the `keychain_get`
  shell function.
- **podman, podman-compose, buildah, skopeo** — the full container
  toolchain. `buildah` for image building, `skopeo` for registry
  inspection without pulling.
- **ShellCheck** — static analysis for shell scripts. Used by the
  framework's lefthook pre-commit configuration.

## Flatpak considerations

Fedora ships with Flatpak and Flathub pre-configured. For GUI
applications (browsers, communication tools, media players), Flatpak
is fine. For development tools, avoid Flatpak versions — they run in
a sandbox that restricts filesystem access, cannot see host toolchains,
and break assumptions about `$PATH` and socket access.

Specifically: do **not** install VS Code, JetBrains IDEs, or terminal
emulators as Flatpaks for development work. Use the native RPM
packages or upstream tarballs.

```sh
# VS Code (Microsoft's repo)
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | \
  sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
sudo dnf install code

# Or JetBrains Toolbox (manages all JetBrains IDEs)
# Download from https://www.jetbrains.com/toolbox-app/ and extract to ~/.local/bin
```

## After this page

Once the machine is configured per the guidance above, proceed to the
[Onboarding Runbook](../onboarding.md) to install the framework itself.
The onboarding page handles `bootstrap.sh`, mise, SSH key generation,
and git identity configuration — the framework-specific steps that
build on top of the system-level setup documented here.
