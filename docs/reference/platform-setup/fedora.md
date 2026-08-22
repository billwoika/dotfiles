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
doing anything else.

### Set the hostname

The installer may set a default hostname like `localhost` or
`fedora`. Set a meaningful hostname before configuring SSH keys,
git identity, or anything that embeds the machine name:

```sh
# Set the hostname (all three levels: static, pretty, transient)
sudo hostnamectl set-hostname fedora-workstation

# Verify
hostnamectl
```

Choose a hostname that identifies the machine — `thinkpad-t14`,
`desk-ryzen`, `fedora-dev` — not `localhost` or `fedora`. The
hostname appears in SSH key comments, shell prompts, and log
output.

### System update and RPM Fusion

```sh
# 1. System update (reboot after — kernel and firmware)
sudo dnf upgrade --refresh
sudo reboot
```

**The machine reboots here.** Log back in to the desktop, open a
terminal, and continue with the rest of this block — RPM Fusion and
firmware updates still need to run:

```sh
# 2. Enable RPM Fusion (free + nonfree)
sudo dnf install \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# 3. Firmware updates via fwupd (physical machines only — on a VM these
#    report "no supported devices" or fail to find updatable firmware,
#    which is expected; skip them)
sudo fwupdmgr get-devices
sudo fwupdmgr refresh --force
sudo fwupdmgr get-updates
sudo fwupdmgr update
```

## dnf configuration

Fedora's package manager is conservative by default. These settings
make it faster and more informative without sacrificing correctness.

Fedora 41+ ships **dnf5**, which validates the config strictly and
rejects some keys that dnf4 silently accepted. The set below is the
dnf5-correct one.

Open `/etc/dnf/dnf.conf` as root — it is a system file, so it needs
`sudo`. If you have no editor preference yet, `nano` ships on Fedora and
saves with `Ctrl-O`, exits with `Ctrl-X`:

```sh
sudo nano /etc/dnf/dnf.conf
```

The file already has a `[main]` section. **Merge** these keys into that
existing section — do not add a second `[main]`. Keys that are already
present should be updated in place; the rest are added under `[main]`:

```ini
[main]
gpgcheck=True
installonly_limit=3
clean_requirements_on_remove=True
best=False
max_parallel_downloads=10
defaultyes=True
countme=False
```

Key choices:

- **`max_parallel_downloads=10`** — saturates modern connections.
  Default of 3 is a relic of slower networks.
- **`best=False`** — allows dnf to skip packages with broken
  dependencies rather than failing the entire transaction. Prevents
  the "one broken COPR package blocks all updates" problem.
- **`countme=False`** — disables the anonymous weekly request that
  Fedora uses for usage statistics.

!!! warning "dnf5: dropped knobs"

    Two options that every older Fedora guide still lists are gone on
    dnf5 (Fedora 41+, so anything on **Fedora 44**):

    - **`deltarpm`** — the delta-RPM mechanism was removed from dnf5
      entirely. `deltarpm=True` does nothing; on a strict config it is
      flagged as unknown. Omit it.
    - **`fastestmirror` in `[main]`** — dnf5 treats `fastestmirror` as a
      *repo* option, and Fedora's metalink already returns a
      latency-sorted mirror list, so explicit tuning is rarely needed.
      If you do want it, set it through the supported interface rather
      than hand-editing the key. `config-manager` lives in the
      `dnf5-plugins` package, which a minimal install may lack:

        ```sh
        sudo dnf install dnf5-plugins        # provides config-manager
        sudo dnf config-manager setopt fastestmirror=True
        ```

    `skip_if_unavailable` is likewise a per-repo option on dnf5, not a
    `[main]` global — set it on the specific repo that needs it.

## Multimedia codecs

Fedora ships without patent-encumbered codecs. After enabling RPM
Fusion:

```sh
# GStreamer codecs (covers most media playback needs)
# Quote the wildcard package names: by this point your login shell may
# already be zsh, and zsh aborts the whole command on an unmatched glob
# ("no matches found: gstreamer1-plugins-bad-*"). Quoting passes the
# pattern to dnf literally in both bash and zsh.
sudo dnf install \
  'gstreamer1-plugins-bad-*' 'gstreamer1-plugins-good-*' gstreamer1-plugins-base \
  gstreamer1-plugin-openh264 \
  gstreamer1-libav \
  --exclude=gstreamer1-plugins-bad-free-devel

# Hardware-accelerated video decode (Intel/AMD)
# Run ONLY the line matching your GPU — do not run both. Check which you
# have first:
#   lspci | grep -E 'VGA|3D'
#
# Intel: the Fedora package is libva-intel-media-driver (the bare
# "intel-media-driver" name does not resolve). It provides the iHD
# driver for Broadwell (5th gen) and newer.
sudo dnf install libva-utils libva-intel-media-driver   # Intel (Gen5+) ONLY
sudo dnf install libva-utils mesa-va-drivers            # AMD ONLY

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

# Disable copy-on-write for VM images and container storage
# (CoW causes fragmentation and write amplification on large files)
# The +C attribute applies to NEW files only — set it before
# populating these directories.
mkdir -p ~/VMs
chattr +C ~/VMs

# Container storage — the +C flag only affects files created AFTER it is
# set, so this must run before podman ever writes here. If podman has
# already run (e.g. you ran `podman info` earlier), existing layers keep
# copy-on-write and the benefit is lost — in that case the clean fix is
# to stop podman, empty the directory, set +C, then let podman repopulate.
sudo mkdir -p /var/lib/containers
sudo chattr +C /var/lib/containers
```

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

On a fresh workstation you will not interact with SELinux at all — it
sits in the background and stays out of the way. You only reach for the
commands below once something is actually denied: a service won't start,
a container can't read a mounted path, a file moved into place is
suddenly unreadable. The workflow is always the same loop — confirm the
denial, read what it objected to, decide whether the *labels* are wrong
or the *policy* is, then fix the narrower of the two.

First, confirm SELinux is on and find out whether anything has actually
been denied:

```sh
# Check current mode — should say "Enforcing"
getenforce

# See recent denials. On a fresh machine this prints nothing,
# which is the expected and healthy result.
sudo ausearch -m avc -ts recent 2>/dev/null || echo "no denials"
```

If `ausearch` prints nothing, there is nothing to fix and you are done —
the rest of this section does not apply until you hit a real denial.

Once you *do* have a denial, the decision is whether it is a labeling
problem or a policy problem. Most developer-facing denials are labeling:
a file or directory was created or moved somewhere SELinux expects a
different context. The fix is to restore the correct context, not to
loosen policy:

```sh
# Restore the default file contexts for a path (fixes most denials
# caused by moving, copying, or extracting files into place)
sudo restorecon -Rv /path/to/moved/files
```

If restoring contexts does not resolve it, the access may be legitimate
but genuinely unanticipated by the shipped policy. The safe way to
investigate is to put the *single offending domain* into permissive mode
— not the whole system — so it logs what it would have blocked without
actually blocking it. Reproduce the failure, collect the denials it
logs, then turn the domain back to enforcing:

```sh
# Put one domain into permissive mode (example: the httpd domain).
# This logs denials for httpd_t only; everything else stays enforcing.
sudo semanage permissive -a httpd_t

# ... reproduce the failure so the denials get logged ...

# Turn the domain back to enforcing when you are done. Do not leave
# a domain permissive — that is the per-domain version of disabling
# SELinux, and it will quietly mask future problems.
sudo semanage permissive -d httpd_t
```

With the denials now logged, you can generate a local policy module
that allows exactly what was denied — and nothing more. Always read the
rules `audit2allow` proposes before installing them; it will happily
generate a module for a denial that was really a misconfiguration:

```sh
# Preview the policy audit2allow would generate (review this first)
sudo ausearch -m avc -ts recent | audit2allow

# If the rules are correct, build and install a named module
sudo ausearch -m avc -ts recent | audit2allow -M my_local_fix
sudo semodule -i my_local_fix.pp

# A module you installed can be removed by name if you change your mind
sudo semodule -r my_local_fix
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

### SSH agent

On Fedora Workstation (GNOME 46+, which is Fedora 40 onward), the SSH
agent is provided by `gcr-ssh-agent`, not `gnome-keyring` — GNOME 46
deprecated the keyring's SSH component and moved it to the `gcr-4`
package. It still starts with the desktop session automatically, so no
additional setup is required; only the socket path changed.

Verify it is running:

```sh
echo $SSH_AUTH_SOCK
# GNOME 46+ : /run/user/1000/gcr/ssh
# (older    : /run/user/1000/keyring/ssh)
ssh-add -l
# Should print "The agent has no identities." (not an error)
```

If `$SSH_AUTH_SOCK` is unset, enable the gcr socket and re-login:

```sh
systemctl --user enable --now gcr-ssh-agent.socket
```

For non-GNOME Fedora setups (Sway, i3, Fedora Server), the
[Onboarding Runbook](../onboarding.md) documents a custom systemd
ssh-agent user service as an alternative.

### Podman socket (for Docker-compatible tooling)

Some tools expect a Docker-compatible socket. Podman provides one via
a systemd user service. This requires the podman packages from
[Developer prerequisites](#developer-prerequisites) below — if you are
reading top to bottom and have not run that `dnf install` yet, install
it first or come back to this step (otherwise `podman.socket` is "not
found" and `podman info` is "command not found"):

```sh
systemctl --user enable --now podman.socket

# Verify
podman info
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

To make the limit permanent, edit `/etc/systemd/journald.conf` as root
and set `SystemMaxUse` under the existing `[Journal]` section (the line
is usually present but commented out as `#SystemMaxUse=` — uncomment it
and give it a value):

```sh
sudo nano /etc/systemd/journald.conf
```

```ini
[Journal]
SystemMaxUse=500M
```

Then reload so the new limit takes effect: `sudo systemctl restart
systemd-journald`.

## GNOME desktop tuning

Fedora Workstation ships GNOME. These are not cosmetic preferences —
they are settings that affect developer productivity.

!!! warning "Run these from inside your graphical GNOME session"

    Every `gsettings` command below needs the session D-Bus that only
    exists inside a running desktop session. Run them from a **graphical
    terminal** (a Terminal window on your GNOME desktop) — not from a
    text console (TTY), not over SSH, and not in the console right after
    the post-install reboot. Outside a session they fail with
    `Failed to connect to the session bus` / `Cannot autolaunch D-Bus`.

!!! note "We assume GNOME on Wayland — and why"

    The framework's Linux desktop guidance assumes **GNOME running on
    Wayland**, which is the default on both Fedora Workstation and Ubuntu
    (so it is what most readers get without choosing anything), exposes
    its settings through `gsettings`/`dconf` (scriptable, so the tuning
    below is reproducible rather than a click-path), and on GNOME 46+
    provides the modern `gcr-ssh-agent` Wayland-era secret/SSH stack the
    framework relies on elsewhere. To be clear about the terms: **GNOME
    is the desktop environment and Wayland is the display protocol** —
    they are not alternatives to each other. The framework is not "X11
    vs Wayland" — it targets the Wayland default and only notes X11
    where a tool genuinely differs (e.g. SSH `askpass`).

    **Where this is wrong for you:** if you run **KDE Plasma, Sway, i3,
    or another desktop**, the `gsettings org.gnome.*` commands below do
    not apply — they are GNOME-specific and silently no-op (or error)
    elsewhere. The *intent* of each (key-repeat rate, Caps-as-Ctrl,
    font hinting, focus-follows-mouse, night light) is portable, but the
    mechanism is not. KDE uses `kwriteconfig6`/System Settings; Sway/i3
    use their own config files and `input`/`xkb` directives. We do not
    document those equivalents here — supporting every Linux desktop is
    beyond a personal framework's remit — but the settings to look for
    are named above, and the SSH-agent guidance (`gcr-ssh-agent`) is the
    one piece that matters regardless of desktop.

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
productive mobile session and a three-hour battery life.

### The power management landscape on Fedora

Three tools compete for the same kernel power tunables (sysfs
nodes). They are mutually exclusive — running any two simultaneously
produces unpredictable behavior, often worse than either alone.

**tuned + tuned-ppd** is the Fedora default since Fedora 41.
`tuned` is a plugin-based power management daemon with many
profiles. `tuned-ppd` is a shim that exposes the same D-Bus API as
the older `power-profiles-daemon`, so GNOME's power settings panel
works without modification. This is the recommended approach for
most users.

There are two CLIs, and the distinction matters. `powerprofilesctl`
talks to the `tuned-ppd` shim and only sees the three
PPD-compatible profiles (`power-saver`, `balanced`, `performance`).
It is the right tool when all you want is to match what GNOME's
panel does:

```sh
# List the three PPD-compatible profiles and show the active one
powerprofilesctl list

# Switch profiles — GNOME's Settings panel sets the same three
powerprofilesctl set power-saver
powerprofilesctl set balanced
powerprofilesctl set performance
```

`tuned-adm` is `tuned`'s own CLI and the actually-installed tool.
It exposes the full profile set, not just the three the shim maps
to. Use it when one of the standard profiles does not fit — for
example, pinning a desktop to `throughput-performance`, or choosing
a more aggressive `powersave` than the shim's `power-saver` maps to:

```sh
# List every profile tuned ships (far more than the PPD three)
tuned-adm list

# Show the active profile and why it was chosen
tuned-adm active

# Switch to any profile by name
tuned-adm profile powersave
tuned-adm profile throughput-performance

# Let tuned pick a profile based on the hardware it detects
tuned-adm recommend
```

Setting a profile with `tuned-adm` is reflected in GNOME's panel
and in `powerprofilesctl` when it maps to one of the three; a
profile outside that set simply shows as the closest equivalent.
Pick one CLI per task — `powerprofilesctl` for the common
three-way toggle, `tuned-adm` when you need a profile it cannot
name.

**power-profiles-daemon (PPD)** was the Fedora default through
Fedora 40. It provided the same three profiles over D-Bus. Fedora
41+ replaced it with `tuned-ppd`, and the two packages conflict at
the RPM level — they own the same D-Bus service path. If upgrading
from Fedora 40 or earlier, `dnf` handles the replacement
automatically.

**TLP** provides the most granular control: per-device USB
autosuspend, PCIe ASPM policy, disk APM, WiFi power save, and
battery charge thresholds. However, TLP has no D-Bus API, so
GNOME's power settings panel will not work with it. TLP conflicts
with both `tuned`/`tuned-ppd` and `power-profiles-daemon`.

Stay on the `tuned` default unless you hit a specific limitation it
cannot address. Concrete reasons to switch to TLP:

- You need a tunable `tuned` does not expose — USB autosuspend
  allow/deny lists, per-device PCIe ASPM policy, or SATA link power
  management overrides for a device that misbehaves on the default.
- You want **persistent** battery charge thresholds managed by a
  daemon across reboots, rather than re-applying a sysfs write
  yourself (see the ThinkPad note below).
- Idle battery drain is still poor after trying `tuned-adm profile
  powersave`, and `powertop --auto-tune` confirms specific devices
  are not being suspended.

If none of those apply, the default stack is the better choice — it
keeps the GNOME panel working and needs no maintenance. If TLP's
granular control is genuinely needed, the installation must remove
the conflicting packages:

```sh
# Remove the default power management stack
sudo dnf remove tuned tuned-ppd

# Install TLP
sudo dnf install tlp tlp-rdw

# Mask rfkill services (TLP manages radio devices directly)
sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket

# Enable and start TLP
sudo systemctl enable --now tlp

# Verify
sudo tlp-stat -s
```

TLP's defaults are sane for most hardware.

For ThinkPad battery charge thresholds, no out-of-tree module is
needed on any kernel Fedora currently ships. Since Linux 5.17 the
in-tree `thinkpad_acpi` driver provides charge-threshold support
for ThinkPads back to the Sandy Bridge generation (2011), exposed
as the standard `charge_control_end_threshold` sysfs node. The old
`akmod-acpi_call` package is unmaintained and rebuilds on every
kernel update — do not install it on modern hardware.

A raw sysfs write works but does not survive a reboot:

```sh
# ThinkPad only. First confirm the sysfs node exists — on non-ThinkPad
# hardware it is usually absent and the write below fails with
# "No such file or directory":
ls /sys/class/power_supply/BAT0/charge_control_end_threshold

# Limit charge to 80% (extends battery lifespan) — NOT persistent;
# this is reset on every reboot. Use it only for a one-off test.
echo 80 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold
```

For a persistent threshold, let TLP manage it — that is one of the
reasons to run TLP in the first place. Set the thresholds in
`/etc/tlp.conf` and TLP re-applies them on every boot:

```sh
# /etc/tlp.conf — TLP applies these on every boot
# Start charging at 75%, stop at 80% (values are ThinkPad-specific)
START_CHARGE_THRESH_BAT0=75
STOP_CHARGE_THRESH_BAT0=80
```

```sh
# Apply the new config without rebooting, then confirm
sudo tlp start
sudo tlp-stat -b        # shows the active charge thresholds
```

For most development workstations, the recommendation is to stay
with the Fedora default (`tuned` + `tuned-ppd`). TLP is only worth
the friction if its per-device controls are specifically needed and
the loss of GNOME power panel integration is acceptable.

## Developer prerequisites

These packages must be installed before running `bootstrap.sh`.
They provide the system-level dependencies that the framework and
its tools expect.

```sh
sudo dnf install \
  zsh git curl wget util-linux-user \
  gcc gcc-c++ make cmake \
  openssl-devel zlib-devel readline-devel \
  libffi-devel libyaml-devel \
  sqlite-devel postgresql-devel \
  jq gh git-delta tree lsof \
  libsecret \
  podman podman-compose podman-docker buildah skopeo \
  ShellCheck
```

Why each group:

- **zsh, git, curl, wget** — framework hard dependencies.
- **util-linux-user** — provides `chsh` on Fedora. Without this
  package, changing the default shell fails with "command not found."
- **gcc, make, cmake, openssl-devel, etc.** — build toolchain for
  native extensions (Ruby gems, Python C extensions, Node native
  addons). Without these, `rv install` and `uv sync` fail on packages
  that compile from source.
- **jq, gh, git-delta, tree, lsof** — pre-mise CLI dependencies. `gh`
  is the GitHub CLI; its completions are wired in the shell startup
  chain. `git-delta` provides the `delta` binary that the framework's
  `git/config` sets as the pager (`pager = delta`) — without it, every
  paged `git` command (`diff`, `log`, `show`, `blame`) fails with
  "cannot run delta". `tree` backs the `tree-trunk` function and `lsof`
  backs the `port_kill` function and `listening` alias.
  (`bat`, `fd`, `ripgrep`, `fzf`, and `direnv` are deliberately NOT in
  this list — they are declared in mise's `[tools]` with aqua-backed
  resolution and arrive with `mise bootstrap`. All their shell wiring
  is `command -v` guarded, so nothing breaks before that.)
- **libsecret** — provides `secret-tool`, used by the
  `keychain_get` shell function. On Fedora the CLI ships in the
  base `libsecret` package; the `libsecret-tools` package name is
  Debian/Ubuntu-only and does not exist in Fedora's repos.
- **podman, podman-compose, podman-docker, buildah, skopeo** — the
  full container toolchain. `podman-docker` provides a `docker`
  command that wraps podman, enabling compatibility with tools that
  expect the Docker CLI. `buildah` for image building, `skopeo` for
  registry inspection without pulling.
- **ShellCheck** — static analysis for shell scripts. Used by the
  framework's lefthook pre-commit configuration.

!!! note "Deliberate overlap with mise `[tools]`"

    Several of these (`jq`, `gh`, `git-delta`, `ShellCheck`, `zsh`,
    `libsecret`) are *also* declared in the mise config and will be
    managed by mise after `mise bootstrap` runs — mise's shims sit
    earlier on `PATH`, so the mise-managed versions win from then on.
    The dnf copies exist for the window before mise does: `gh` in
    particular must be present *first*, because `gh auth login` raises
    the GitHub API limit from 60 to 5000 requests/hour — and mise's
    `github:` backend and attestation checks spend that budget during
    the bootstrap itself. `git-delta` covers git paging from the moment
    `bootstrap.sh` links the git config until mise delivers its own
    `delta`. This is sequencing, not drift.

## Set zsh as the default shell

Fedora ships with bash as the default login shell. The framework
requires zsh. This step must happen before running `bootstrap.sh`
because the bootstrap script symlinks zsh configuration files that
expect `$ZDOTDIR` to be set by the zsh startup chain.

```sh
# Change the login shell to zsh
chsh -s $(which zsh)
```

**This does not take effect in the current session.** The login
shell is read from `/etc/passwd` at login time. To activate zsh:

- **Option A (recommended):** Log out of the desktop session and
  log back in. Every new terminal will open zsh.
- **Option B (immediate, current terminal only):** Run `zsh` to
  start a zsh session inside the current bash session. This works
  for running `bootstrap.sh` and `mise install` immediately, but
  new terminal windows will still open bash until you log out and
  back in.

Verify the shell change took effect:

```sh
echo $SHELL
# Should print: /usr/bin/zsh

echo $0
# Should print: -zsh (login shell) or zsh
```

If `$SHELL` still shows `/bin/bash` after logging back in, verify
that `/etc/passwd` was updated:

```sh
grep $(whoami) /etc/passwd
# Should end with: /usr/bin/zsh
```

### Remove the bash startup files

Changing your login shell is not enough. Fedora ships a stock
`~/.bashrc` and `~/.bash_profile` (copied from `/etc/skel` when the
account was created), and these will silently shadow the
framework's `~/.profile` that `bootstrap.sh` installs.

The mechanism: an interactive login bash reads the first of
`~/.bash_profile`, `~/.bash_login`, `~/.profile` that exists, and
stops there. As long as `~/.bash_profile` is present, bash reads it
and **never reads `~/.profile`** — so the POSIX subprocess shim
(the environment variables relied on by cron, systemd user
services, and any non-zsh process) never loads. The full read-order
table is in the [POSIX profile
reference](../../shell-environment/posix-profile.md#when-profile-is-read).

You are not a bash user under this framework — these files are
cruft. Delete them so bash falls through to `~/.profile`
consistently:

```sh
# Remove the bash-era startup files that would shadow ~/.profile
rm -f ~/.bash_profile ~/.bash_login ~/.bashrc
```

Do this before running `bootstrap.sh`. The bootstrap audit will
also warn if any surviving startup file contains rogue
installer-injected PATH lines, but it does not delete these files
for you — removing the stock bash files is a manual step.

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
