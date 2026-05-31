# Onboarding Runbook

Step-by-step setup for a new machine. The core workflow is identical
on macOS and Linux. Platform-specific steps (prerequisites, SSH agent,
optional GUI tools) are presented in tabbed sections.

## Prerequisites

=== "macOS"

    - macOS with Command Line Tools (`xcode-select --install`)
    - A GitHub account with SSH key access
    - 1Password (recommended, not required)

=== "Debian / Ubuntu"

    - Install core dependencies:

        ```sh
        sudo apt install zsh git curl
        ```

    - Set zsh as the default shell:

        ```sh
        chsh -s $(which zsh)
        ```

    - A GitHub account with SSH key access
    - 1Password (recommended, not required)

=== "Fedora / RHEL"

    - Complete the [Fedora setup page](platform-setup/fedora.md)
      first — it covers system update, dnf configuration, developer
      packages (including `zsh`, `git`, and `util-linux-user`), and
      setting zsh as the default shell.
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

### Step 3: Verify zsh is the login shell

The platform setup page covers changing the default shell. Verify
it took effect before continuing:

```sh
echo $SHELL
# Must print /usr/bin/zsh (Linux) or /bin/zsh (macOS)
# If it still shows bash, log out and back in first
```

If you are in a bash session and need to continue immediately,
start zsh manually:

```sh
zsh
```

### Step 4: Install mise

```sh
curl https://mise.run | sh
```

Reload the shell so mise is available on `$PATH`:

```sh
exec zsh
```

Verify mise is working:

```sh
mise --version
```

### Step 5: Install the usage CLI

mise's shell completions depend on the `usage` CLI. Without it,
the completion script has broken quoting that produces errors on
shell startup.

```sh
mise install usage
mise use -g usage
```

### Step 6: Install rv (Ruby manager)

```sh
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/spinel-coop/rv/releases/latest/download/rv-installer.sh | sh
```

### Step 7: Install user-scope runtimes

```sh
mise install
```

This installs the tools declared in `~/.config/mise/config.toml`.

### Step 8: Generate SSH keys

```sh
# Work key
ssh-keygen -t ed25519 \
  -C "dev@zftadvancements.com (work, $(hostname), $(date +%Y-%m))" \
  -f ~/.ssh/id_ed25519_work

# Personal key
ssh-keygen -t ed25519 \
  -C "you@billwoika.com (personal, $(hostname), $(date +%Y-%m))" \
  -f ~/.ssh/id_ed25519_personal
```

### Step 9: Edit identity templates

```sh
$EDITOR ~/.config/git/work.config
$EDITOR ~/.config/git/personal.config
$EDITOR ~/.config/git/allowed_signers
$EDITOR ~/.ssh/config
```

Fill in your actual email addresses, signing key paths, and host
aliases.

### Step 10: Register SSH keys

Add both keys to GitHub (Settings > SSH and GPG keys):
- Once as "Authentication Key"
- Once as "Signing Key"

Load keys into the agent:

=== "macOS"

    ```sh
    ssh-add --apple-use-keychain ~/.ssh/id_ed25519_work
    ssh-add --apple-use-keychain ~/.ssh/id_ed25519_personal
    ```

    The `--apple-use-keychain` flag stores the passphrase in macOS
    Keychain so the key is available across reboots without re-entry.

=== "Linux (GNOME — Fedora, Ubuntu)"

    GNOME Keyring provides an SSH agent automatically. Verify it is
    running:

    ```sh
    echo $SSH_AUTH_SOCK
    # Should print something like: /run/user/1000/keyring/ssh
    ```

    Then add your keys:

    ```sh
    ssh-add ~/.ssh/id_ed25519_work
    ssh-add ~/.ssh/id_ed25519_personal
    ```

    With `AddKeysToAgent yes` in `~/.ssh/config`, keys are added
    automatically on first use for the duration of the session.

=== "Linux (non-GNOME — Sway, i3, etc.)"

    Without a desktop agent, create a systemd user service:

    ```sh
    mkdir -p ~/.config/systemd/user
    cat > ~/.config/systemd/user/ssh-agent.service <<'EOF'
    [Unit]
    Description=SSH key agent

    [Service]
    Type=simple
    ExecStart=/usr/bin/ssh-agent -D -a %t/ssh-agent.socket

    [Install]
    WantedBy=default.target
    EOF

    systemctl --user enable --now ssh-agent
    ```

    The framework's `~/.profile` detects the agent socket
    automatically. Verify after restarting the shell:

    ```sh
    echo $SSH_AUTH_SOCK
    # Should print: /run/user/<uid>/ssh-agent.socket
    ```

    Then add your keys:

    ```sh
    ssh-add ~/.ssh/id_ed25519_work
    ssh-add ~/.ssh/id_ed25519_personal
    ```

    With `AddKeysToAgent yes` in `~/.ssh/config`, keys are added
    automatically on first use for the duration of the session.

### Step 11: Validate

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

=== "macOS"

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

    ### Configure file associations

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

=== "Debian / Ubuntu"

    ### Install system packages

    ```sh
    sudo apt install direnv libsecret-tools fd-find ripgrep fzf
    ```

    `direnv` is already wired in `conf.d/70-tools.zsh`. `libsecret-tools`
    provides `secret-tool`, used by the `keychain_get` shell function.

    ### SSH agent persistence

    See the systemd user service in Step 10 above. On GNOME desktops,
    `gnome-keyring` can also serve as the SSH agent — it is enabled
    by default in most GNOME-based distributions.

    ### Add mise shims to system PATH (for GUI IDEs)

    ```sh
    mkdir -p ~/.config/environment.d
    echo 'PATH=$HOME/.local/share/mise/shims:$PATH' > \
      ~/.config/environment.d/mise.conf
    # Takes effect after logout/login (systemd-based distros)
    ```

=== "Fedora / RHEL"

    System packages (`direnv`, `fd-find`, `ripgrep`, `fzf`, etc.)
    are covered in the
    [Fedora setup page](platform-setup/fedora.md#developer-prerequisites).
    If that page was followed, these are already installed.

    ### SSH agent persistence

    See the systemd user service in Step 10 above. On GNOME desktops,
    `gnome-keyring` can also serve as the SSH agent — it is enabled
    by default in Fedora Workstation.

    ### Add mise shims to system PATH (for GUI IDEs)

    ```sh
    mkdir -p ~/.config/environment.d
    echo 'PATH=$HOME/.local/share/mise/shims:$PATH' > \
      ~/.config/environment.d/mise.conf
    # Takes effect after logout/login (systemd-based distros)
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
docker compose up -d  # local services (podman-docker on Fedora)
```
