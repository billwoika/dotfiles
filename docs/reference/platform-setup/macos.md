# macOS Setup

macOS development machines in most organizations arrive with an MDM
profile applied. FileVault is on, the firewall is enabled, software
updates are enforced, and system extensions are gated. This page
covers what MDM does *not* handle: the developer-specific system
configuration that makes the machine productive for terminal-heavy,
polyglot engineering work.

If your machine has no MDM (personal laptop, freelance work), the
"Verify MDM coverage" section tells you what to enable manually.

## Verify MDM coverage

Check that these are already handled. If they are not (no MDM, or a
minimal profile), enable them before proceeding:

```sh
# FileVault (full-disk encryption)
fdesetup status                     # should say "FileVault is On"

# Firewall
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
# should say "enabled"

# Gatekeeper
spctl --status                      # should say "assessments enabled"

# Software updates
softwareupdate --list               # should show nothing pending, or install them
```

If any of these are off on a personal machine:

```sh
# Enable firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

# Enable FileVault (prompts for recovery key setup)
sudo fdesetup enable

# Enable automatic updates
sudo softwareupdate --schedule on
```

## Xcode Command Line Tools

Required before anything else — git, clang, make, and system headers
all live here:

```sh
xcode-select --install
```

This is a ~1.5GB download. Wait for it to complete before proceeding.
Do not install the full Xcode app unless you are doing iOS/macOS native
development — it is 12GB+ and the CLI tools are sufficient for
everything this framework needs.

## Homebrew

Homebrew is the package manager for macOS system-level tools. The
framework uses it only for things that cannot be installed via mise
(system libraries, GUI apps, tools that need system integration):

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After installation, add to PATH (the installer prints this, but for
Apple Silicon it is not automatic):

```sh
# Apple Silicon (default since M1)
eval "$(/opt/homebrew/bin/brew shellenv)"

# Intel
eval "$(/usr/local/bin/brew shellenv)"
```

The framework's `conf.d/70-tools.zsh` handles this automatically once
bootstrap has run. The manual step here is only for the pre-bootstrap
shell session.

### What to install via Homebrew

```sh
# Core developer tools (not available via mise)
brew install \
  coreutils findutils gnu-sed gnu-tar \
  direnv \
  jq bat fd ripgrep fzf \
  ShellCheck \
  podman

# Terminal emulator
brew install --cask iterm2
# Or: wezterm, kitty, alacritty — the framework is emulator-agnostic

# Optional GUI apps
brew install --cask textmate markedit
```

Why GNU coreutils: macOS ships BSD versions of `sed`, `tar`, `find`,
etc. with different flags than the GNU versions that Linux uses and
that most documentation assumes. Installing GNU coreutils (prefixed
with `g` by default: `gsed`, `gtar`) prevents script portability
surprises. The framework does not shadow the system tools — it uses
the `g`-prefixed versions explicitly when needed.

### What NOT to install via Homebrew

- **Language runtimes** (Node, Python, Ruby) — mise manages these.
  Homebrew versions conflict with mise's version switching.
- **Language-specific tools** (prettier, rubocop, ruff) — install via
  the language package manager (bun, rv, uv) so they track the
  project's pinned version.
- **Docker Desktop** — the framework recommends Podman. If you need
  Docker Desktop for a specific reason, install it directly from
  Docker's site, not via `brew install --cask docker`.

## Rosetta 2 (Apple Silicon only)

Some tools still ship x86_64-only binaries. Rosetta translates them
transparently but must be installed first:

```sh
softwareupdate --install-rosetta --agree-to-license
```

This is a one-time operation. Most modern development tools ship
universal or arm64 binaries, but Rosetta is needed for:

- Older native extensions during Ruby gem compilation
- Some commercial CLI tools (VPN clients, vendor SDKs)
- x86_64 container images when running under Podman/Docker on Apple
  Silicon (emulated via QEMU, slow but functional)

## System preferences for developers

These settings affect daily development workflows. They are not
cosmetic preferences — they change how fast you can type, navigate,
and respond to the machine.

### Keyboard

```sh
# Key repeat rate (fastest)
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Disable press-and-hold for accent characters (enables key repeat everywhere)
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Full keyboard access (Tab navigates all controls, not just text fields)
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
```

For Caps Lock as Ctrl: System Settings > Keyboard > Keyboard Shortcuts
> Modifier Keys. This matches the framework's emacs-mode keybinding
stance and puts Ctrl under the left pinky without reaching.

### Finder

```sh
# Show all file extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show hidden files
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show path bar and status bar
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true

# Default to list view
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Disable .DS_Store on network and USB volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
```

### Dock

```sh
# Auto-hide (reclaim screen real estate)
defaults write com.apple.dock autohide -bool true

# Remove show/hide animation delay
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.4

# Don't rearrange Spaces based on most recent use
defaults write com.apple.dock mru-spaces -bool false
```

### Screenshots

```sh
# Save to ~/Desktop/Screenshots (not Desktop root)
mkdir -p ~/Desktop/Screenshots
defaults write com.apple.screencapture location ~/Desktop/Screenshots

# Default format PNG (lossless, better for documentation)
defaults write com.apple.screencapture type -string "png"

# Disable shadow on window captures
defaults write com.apple.screencapture disable-shadow -bool true
```

### Apply changes

Most `defaults write` changes require restarting the affected process:

```sh
killall Finder
killall Dock
killall SystemUIServer
```

## Network configuration

### DNS

macOS uses a scoped resolver model via `configd`. For development, set
explicit resolvers rather than relying on DHCP-assigned DNS:

System Settings > Network > (your interface) > DNS > add:

- `1.1.1.1` (Cloudflare, primary)
- `1.0.0.1` (Cloudflare, secondary)

Or via command line:

```sh
# Wi-Fi interface (adjust for Ethernet: "Ethernet" or "USB 10/100/1000 LAN")
networksetup -setdnsservers Wi-Fi 1.1.1.1 1.0.0.1
```

See the [DNS page](../../operations/dns.md) for the full rationale on
resolver selection and encrypted DNS configuration.

### mDNS and local development

macOS has Bonjour (mDNS) enabled by default. `.local` domains resolve
via multicast, which means `anything.local` in `/etc/hosts` or
development URLs using `.local` TLD can behave unpredictably. Use
`.localhost` (RFC 6761, guaranteed loopback) or `.test` for local
development domains.

## Podman on macOS

Podman runs a Linux VM on macOS (same as Docker Desktop, but without
the licensing constraints):

```sh
# Initialize the Podman machine (downloads a Fedora CoreOS VM image)
podman machine init

# Start it
podman machine start

# Verify
podman info
podman run --rm hello-world
```

For VS Code devcontainers and other tools that expect a Docker socket:

```sh
# Set DOCKER_HOST to Podman's socket
export DOCKER_HOST="unix://$HOME/.local/share/containers/podman/machine/podman.sock"
```

The framework's `conf.d/` shell configuration handles this
automatically after bootstrap.

## After this page

Proceed to the [Onboarding Runbook](../onboarding.md) for framework
installation (`bootstrap.sh`, mise, SSH keys, git identity).
