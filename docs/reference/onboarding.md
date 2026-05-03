# Onboarding Runbook

Step-by-step setup for a new machine. This runbook assumes macOS with
Apple Silicon; Linux steps differ only for Homebrew paths and Keychain
references.

## Prerequisites

- macOS with Command Line Tools (`xcode-select --install`)
- A GitHub account with SSH key access
- 1Password (recommended, not required)

## Step-by-step setup

### Step 1: Clone the dotfiles

```sh
git clone https://github.com/billwoika/dotfiles ~/dotfiles
```

### Step 2: Bootstrap

```sh
sh ~/dotfiles/bootstrap.sh
```

This creates XDG directories, symlinks configuration files, copies
identity templates, and audits for rogue shell injections. Review the
output — anything marked `[rogue]` needs cleanup.

### Step 3: Install mise

```sh
curl https://mise.run | sh
```

### Step 4: Install rv (Ruby manager)

```sh
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/spinel-coop/rv/releases/latest/download/rv-installer.sh | sh
```

### Step 5: Reload the shell

```sh
exec zsh
```

### Step 6: Install user-scope runtimes

```sh
mise install
```

This installs the tools declared in `~/.config/mise/config.toml`.

### Step 7: Generate SSH keys

```sh
# Work key
ssh-keygen -t ed25519 \
  -C "dev@springbig.com (work, $(hostname), $(date +%Y-%m))" \
  -f ~/.ssh/id_ed25519_work

# Personal key
ssh-keygen -t ed25519 \
  -C "you@billwoika.com (personal, $(hostname), $(date +%Y-%m))" \
  -f ~/.ssh/id_ed25519_personal
```

### Step 8: Edit identity templates

```sh
$EDITOR ~/.config/git/work.config
$EDITOR ~/.config/git/personal.config
$EDITOR ~/.config/git/allowed_signers
$EDITOR ~/.ssh/config
```

Fill in your actual email addresses, signing key paths, and host
aliases.

### Step 9: Register SSH keys

Add both keys to GitHub (Settings > SSH and GPG keys):
- Once as "Authentication Key"
- Once as "Signing Key"

Load keys into the agent:

```sh
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_work
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_personal
```

### Step 10: Validate

```sh
# POSIX profile test suite
sh ~/dotfiles/sh/tests/profile_test.sh

# Verify git identity
cd ~/work && git config user.email    # should show work email
cd ~/personal && git config user.email # should show personal email

# Verify SSH
ssh -T git@github.com-work
ssh -T git@github.com-personal

# Verify mise
mise doctor
```

## Optional steps

### Install Homebrew packages

```sh
brew install --cask iterm2 textmate markedit
# Re-run bootstrap to create CLI wrappers
sh ~/dotfiles/bootstrap.sh
```

### Install direnv

```sh
brew install direnv
# Already wired in conf.d/70-tools.zsh
```

### Configure file associations (macOS)

```sh
brew install duti
sh ~/dotfiles/macos/setup-file-associations.sh
```

### Add mise shims to system PATH (for GUI IDEs)

```sh
echo "$HOME/.local/share/mise/shims" | \
  sudo tee /etc/paths.d/mise > /dev/null
# Takes effect after logout/login
```

## Cloning a project

After the machine is set up, the per-project workflow:

```sh
cd ~/work
git clone <repo-url>
cd <project>

# One-time project setup (if mise.toml defines a setup task)
mise trust
mise run setup

# Or manually
mise install          # install project-pinned tools
rv clean-install      # Ruby dependencies (if Ruby project)
uv sync               # Python dependencies (if Python project)
bun install           # JS dependencies (if JS project)
docker compose up -d  # local services (if compose.yml exists)
```
