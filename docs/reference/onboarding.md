# Onboarding Runbook

Step-by-step setup for a new machine. The core workflow is identical
on macOS and Linux. Platform-specific steps (prerequisites, SSH agent,
optional GUI tools) are presented in tabbed sections.

## Prerequisites

=== "macOS"

    - macOS with Command Line Tools (`xcode-select --install`)
    - A GitHub account with SSH key access
    - 1Password (optional). If you want it for GitHub passkey
      authentication or SSH commit signing, install it before
      bootstrapping:

        ```sh
        brew install --cask 1password
        brew install 1password-cli
        ```

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
    - 1Password (optional). If you want it for GitHub passkey
      authentication or SSH commit signing, add the 1Password apt
      repository before bootstrapping, then install the desktop app and
      the `op` CLI from it:

        ```sh
        curl -sS https://downloads.1password.com/linux/keys/1password.asc \
          | sudo gpg --dearmor \
            --output /usr/share/keyrings/1password-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" \
          | sudo tee /etc/apt/sources.list.d/1password.list
        sudo apt update && sudo apt install 1password 1password-cli
        ```

=== "Fedora / RHEL"

    - Complete the [Fedora setup page](platform-setup/fedora.md)
      first — it covers system update, dnf configuration, developer
      packages (including `zsh`, `git`, and `util-linux-user`), and
      setting zsh as the default shell.
    - A GitHub account with SSH key access
    - 1Password (optional). If you want it for GitHub passkey
      authentication or SSH commit signing, add the 1Password dnf
      repository before bootstrapping, then install the desktop app and
      the `op` CLI from it:

        ```sh
        sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
        sudo sh -c 'echo -e "[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=\"https://downloads.1password.com/linux/keys/1password.asc\"" > /etc/yum.repos.d/1password.repo'
        sudo dnf install 1password 1password-cli
        ```

## Step-by-step setup

### Step 1: Clone the dotfiles

Clone over **HTTPS**, not SSH. This is deliberate: the repository is
public, so an HTTPS clone needs no credentials — and at this point you
have none. Your SSH keys do not exist yet (Step 8), and the GitHub
passkey in 1Password is not wired up for git either. Cloning over SSH
here would fail with `Permission denied (publickey)`. You will switch
this clone's remote to SSH in Step 10, once the keys exist.

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
# Should print the path zsh was installed at: /usr/bin/zsh or
# /bin/zsh on Linux (distro-dependent), /bin/zsh on macOS.
# If it still shows bash, log out and back in first.
```

If you are in a bash session and need to continue immediately,
start zsh manually:

```sh
zsh
```

Then confirm no leftover bash startup files remain. If
`~/.bash_profile` or `~/.bash_login` exists, bash reads it instead
of the framework's `~/.profile`, and the POSIX shim that supplies
environment variables to cron, systemd user services, and other
non-zsh subprocesses never loads:

```sh
ls -la ~/.bash_profile ~/.bash_login ~/.bashrc 2>/dev/null
# Expected: no such files. If any exist, remove them:
rm -f ~/.bash_profile ~/.bash_login ~/.bashrc
```

The platform setup pages cover this in their shell-change step;
this check catches the case where a file was re-created (for
example by a tool installer) after that step. See [when
`~/.profile` is
read](../shell-environment/posix-profile.md#when-profile-is-read).

!!! warning "Run the remaining steps in a framework shell"

    Every step from here on installs or first-runs a tool, and several
    of those tools place their state based on an environment variable
    the framework sets — `CARGO_HOME`, `RUSTUP_HOME`, `GNUPGHOME`,
    `GOPATH`. If you run them from the original bash login session, those
    variables are not set, and the tools fall back to `~/.cargo`,
    `~/.rustup`, `~/.gnupg`, and `~/go` in your home directory instead of
    their XDG locations.

    Confirm you are in a shell that has loaded the framework environment
    before continuing:

    ```sh
    echo "$CARGO_HOME"
    # Should print: <your XDG_DATA_HOME>/cargo  (e.g. ~/.local/share/cargo)
    # If it prints nothing, start a framework shell first: exec zsh
    ```

    This will not stop the genuinely unrelocatable directories
    (`~/.mozilla`, `~/.pki`) from appearing — those honor no such
    variable and no framework lever moves them. `~/.vim` is not in that
    category: it is a deliberate config placement, not a leak. See
    [directories that escape
    XDG](../shell-environment/xdg-and-posix.md#directories-that-escape-xdg)
    for which leaks are preventable, which are the cost of the tool, and
    why Vim is neither.

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

`usage` is already pinned in the framework's `~/.config/mise/config.toml`,
so Step 7 (`mise install`) would install it anyway. Install it now, on
its own, so completions work the next time the shell reloads — before
the full toolchain install:

```sh
mise install usage
```

Do **not** run `mise use -g usage`. That command rewrites the global
config file to add the pin — but the framework already ships that pin,
and the file is a symlink back into your dotfiles repo, so the rewrite
would dirty your working tree (or clobber the symlink). The declaration
lives in version control; you only need to materialize the binary.

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

Run these from a framework shell so `$EDITOR` is set (it is exported by
the zsh startup chain — if `$EDITOR` expands to nothing, you are not in a
framework shell yet; run `exec zsh` first, or substitute `vim`):

```sh
$EDITOR ~/.config/git/local.config       # user.name (shared across profiles)
$EDITOR ~/.config/git/work.config
$EDITOR ~/.config/git/personal.config
$EDITOR ~/.config/git/opensource.config
$EDITOR ~/.config/git/allowed_signers
$EDITOR ~/.ssh/config
```

`local.config` holds `user.name` only — bootstrap copies it from
`git/local.config.example` (placeholder `Your Name`). Email, signing
keys, and host aliases stay in the path-based profile files.
`opensource.config` applies to repos cloned under `~/opensource/`; if
you do not use that directory you can leave it, but note it ships with
placeholder identity, so a repo cloned there would otherwise commit
under the template email.

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

    On GNOME 46+ (Fedora 40+, Ubuntu 24.04+), the SSH agent is no
    longer part of `gnome-keyring`. GNOME 46 deprecated that component
    and moved it to **`gcr-ssh-agent`** (the `gcr-4` package), whose
    systemd user socket lives at `$XDG_RUNTIME_DIR/gcr/ssh`. On a
    default Fedora Workstation this is already enabled — verify:

    ```sh
    echo $SSH_AUTH_SOCK
    # GNOME 46+ : /run/user/<uid>/gcr/ssh
    # (older    : /run/user/<uid>/keyring/ssh — pre-GNOME-46)
    ```

    If `$SSH_AUTH_SOCK` is empty, the gcr agent socket is not active.
    Enable it and re-login (or set the variable for the current shell):

    ```sh
    systemctl --user enable --now gcr-ssh-agent.socket
    # current shell, until next login:
    export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/gcr/ssh"
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

#### Switch the dotfiles remote to SSH

Now that your keys exist and are registered, point the dotfiles clone
(cloned over HTTPS in Step 1) at your SSH host alias so future pulls and
pushes use the key. Use the host alias you defined in `~/.ssh/config`
(Step 9) — `github.com-personal` here, assuming the dotfiles are a
personal repo:

```sh
cd ~/dotfiles
git remote set-url origin git@github.com-personal:billwoika/dotfiles
git remote -v   # confirm origin now shows the SSH URL
```

### Step 11: Validate

```sh
# POSIX profile test suite
sh ~/dotfiles/sh/tests/profile_test.sh

# Verify mise
mise doctor
```

**Verify SSH authentication to GitHub.** This requires that you finished
Step 10 — both the host aliases in your edited `~/.ssh/config` and the
keys registered at GitHub. The success message is GitHub greeting you by
username (it then closes the connection — GitHub does not allow shell
access, so "does not provide shell access" is the expected, healthy
result):

```sh
ssh -T git@github.com-work
ssh -T git@github.com-personal
# Expected: "Hi <your-username>! You've successfully authenticated, but
#            GitHub does not provide shell access."
# "Permission denied (publickey)" means the key is not registered, or
# the host alias is missing from ~/.ssh/config.
```

**Verify git identity.** The framework selects your work vs. personal
identity by directory, using `includeIf "gitdir:..."` rules — and those
rules only fire **inside a git repository** under `~/work` or
`~/personal`. On a fresh machine those directories are still empty, so
checking identity there shows the global default, not the work/personal
email. Verify it properly after your first clone:

```sh
cd ~/work
git clone git@github.com-work:your-org/some-repo   # any work repo
cd some-repo
git config user.email    # NOW shows your work email
```

### Step 12: Re-check for regenerated bash startup files

The Fedora setup page had you delete `~/.bashrc`, `~/.bash_profile`, and
`~/.bash_login` before bootstrapping. But several tools installed *during*
this runbook — `mise`, `rv`, and other `curl | sh` installers — append to
or re-create `~/.bashrc` (or `~/.bash_profile`) as part of their setup,
*after* you deleted it. A regenerated `~/.bash_profile` silently shadows
the framework's `~/.profile` again: bash reads the bash file and never
falls through to `~/.profile`, so the POSIX subprocess shim stops loading
for cron and systemd user services.

Run this **last**, once every tool above is installed, to catch anything
that came back:

```sh
# List any bash startup files that reappeared
ls -la ~/.bashrc ~/.bash_profile ~/.bash_login 2>/dev/null

# Remove any that did. (You are not a bash user under this framework;
# these are installer cruft that re-shadows ~/.profile.)
rm -f ~/.bashrc ~/.bash_profile ~/.bash_login
```

Then re-run the bootstrap audit, which scans the remaining startup files
for rogue installer-injected `PATH` lines (it reports them but does not
delete — that part is on you):

```sh
sh ~/dotfiles/bootstrap.sh
```

If an installer re-injected a `PATH` export into `~/.profile` or a zsh
startup file, the audit flags it `[rogue]`. Remove those lines and rely
on `conf.d/10-path.zsh` instead.

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
    # New login shells (any new Terminal window) pick this up
    # immediately via path_helper in /etc/zprofile. GUI apps launched
    # from Finder/Dock see it only after the next logout/login.
    ```

=== "Debian / Ubuntu"

    ### Install system packages

    ```sh
    sudo apt install direnv libsecret-tools fd-find ripgrep fzf
    ```

    `direnv` is already wired in `conf.d/70-tools.zsh`. `libsecret-tools`
    provides `secret-tool`, used by the `keychain_get` shell function.

    ### SSH agent persistence

    See the systemd user service in Step 10 above. On GNOME 46+
    desktops (Ubuntu 24.04+), the SSH agent is provided by
    `gcr-ssh-agent`, not `gnome-keyring` — its socket is
    `$XDG_RUNTIME_DIR/gcr/ssh`, normally already active.

    ### Add mise shims to system PATH (for GUI IDEs)

    ```sh
    mkdir -p ~/.config/environment.d
    echo 'PATH=$HOME/.local/share/mise/shims:$PATH' > \
      ~/.config/environment.d/mise.conf
    # Reaches systemd user services immediately; GUI apps after
    # logout/login. Terminals get it via conf.d/10-path.zsh already.
    ```

=== "Fedora / RHEL"

    System packages (`direnv`, `fd-find`, `ripgrep`, `fzf`, etc.)
    are covered in the
    [Fedora setup page](platform-setup/fedora.md#developer-prerequisites).
    If that page was followed, these are already installed.

    ### SSH agent persistence

    See the systemd user service in Step 10 above. On Fedora
    Workstation (GNOME 46+), the SSH agent is provided by
    `gcr-ssh-agent`, not `gnome-keyring` — its socket is
    `$XDG_RUNTIME_DIR/gcr/ssh`, enabled by default.

    ### Add mise shims to system PATH (for GUI IDEs)

    ```sh
    mkdir -p ~/.config/environment.d
    echo 'PATH=$HOME/.local/share/mise/shims:$PATH' > \
      ~/.config/environment.d/mise.conf
    # Read by the systemd user manager: reaches user services right
    # away, GUI apps after the next logout/login. (Terminals already
    # get the shims via conf.d/10-path.zsh.)
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
docker compose up -d  # local services
```

On Fedora the `docker` command is supplied by `podman-docker` (an
alias to Podman), but that package does **not** provide `compose`.
For `docker compose` / `podman compose` to work you also need a
compose provider — install `podman-compose` (it is already in the
Fedora developer-prerequisites list):

```sh
podman compose up -d   # requires podman-compose to be installed
```
