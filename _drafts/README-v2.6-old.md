# Dotfiles

Implementation of the Developer Environment Framework v2.6 —
XDG-compliant, mise-based, emacs-mode zsh configuration with git/ssh/tmux
support, a modular alias library, container reference templates, and
editor/IDE integration patterns.

See the framework document for the rationale behind every design decision.

---

## Contents

```
dotfiles/
├── bootstrap.sh                 Idempotent symlink installer
├── profile                      ~/.profile — POSIX shim for non-zsh subprocesses
├── gitignore.example            Reference project-level .gitignore (IDE state, etc.)
├── .editorconfig.example        Reference .editorconfig for new projects
├── zsh/
│   ├── zshenv                   Outer bootstrap (sets ZDOTDIR)
│   ├── .zshenv                  XDG redirects, tool locations
│   ├── .zprofile                Login-shell PATH finalization
│   ├── .zshrc                   Interactive orchestrator
│   ├── .zlogout                 Cleanup on login exit
│   └── conf.d/
│       ├── 05-environment.zsh   OSTYPE_SHORT, IS_CONTAINER, IS_VSCODE_TERMINAL flags
│       ├── 10-path.zsh          Deterministic PATH with typeset -U
│       ├── 20-completion.zsh    compinit with 24h cache
│       ├── 25-tool-cache.zsh    Version-hashed cache for tool init/completions
│       ├── 30-history.zsh       100k entries, aggressive dedup
│       ├── 40-options.zsh       Shell behavior
│       ├── 50-keybinds.zsh      emacs mode + WORDCHARS tweak
│       ├── 60-aliases.zsh       Core aliases
│       ├── 61-git-extensions.zsh    Git rebase/checkout flow
│       ├── 62-ruby-aliases.zsh      Ruby/Rails/Bundler
│       ├── 63-python-aliases.zsh    uv/pytest/jupyter
│       ├── 64-js-aliases.zsh        bun/biome/tsc
│       ├── 66-data-functions.zsh    csvsplit, jq helpers
│       ├── 67-devloop.zsh           tmux, tree-trunk, serve
│       ├── 68-diagnostics.zsh       check-cert, claude-sync-path
│       ├── 70-tools.zsh             Tier-1 hooks: mise/rv/direnv (Appendix C)
│       └── 80-functions.zsh         Core utility functions
├── mise/config.toml             User-scope tool + settings defaults
├── direnv/direnvrc              1Password / Vault / sops / keychain helpers
├── git/
│   ├── config                   Main git config with includeIf rules
│   ├── ignore                   Global gitignore
│   ├── attributes               Global gitattributes
│   ├── work.config.example      Work identity profile — COPY AND EDIT
│   ├── personal.config.example  Personal identity profile — COPY AND EDIT
│   └── allowed_signers.example  SSH signing-key registry — COPY AND EDIT
├── ssh/config.example           SSH client config — COPY AND EDIT
├── tmux/tmux.conf               emacs-mode, minimal plugins, F12 nested escape
├── vim/vimrc                    Minimal sensible-defaults vim config
├── vscode/                      Reference VS Code workspace templates
│   ├── settings.json.example    Workspace settings (formatters, exclusions)
│   ├── extensions.json.example  Recommended extensions list
│   └── launch.json.example      Multi-language debug configurations (Section 22.7)
├── jetbrains/                   Reference JetBrains templates
│   ├── README.md                What to commit, what to gitignore in .idea/
│   └── runConfigurations/       Sample shared run configs (RSpec, pytest)
├── macos/                       macOS-specific opt-in helpers
│   └── setup-file-associations.sh   Interactive duti-based file association setup
├── devcontainer/                Reference templates for project devcontainers
│   ├── devcontainer.json        Spec config — copy to <project>/.devcontainer/
│   ├── Dockerfile.dev           Slim Debian + mise + rv
│   ├── post-create.sh           Bootstraps dotfiles + project deps in container
│   └── compose.yml.example      Reference compose stack for local services
└── sh/tests/profile_test.sh     POSIX sh test suite for ~/.profile
```

## Installation

```sh
git clone git@github.com:YOU/dotfiles.git ~/dotfiles
cd ~/dotfiles
sh bootstrap.sh                 # preview with: sh bootstrap.sh --dry-run
exec zsh                         # reload the shell
```

### After bootstrap

1. **Install mise:**
   ```sh
   curl https://mise.run | sh
   ```

2. **Install rv (Ruby version and gem manager):**
   ```sh
   curl --proto '=https' --tlsv1.2 -LsSf \
     https://github.com/spinel-coop/rv/releases/latest/download/rv-installer.sh | sh
   ```

3. **Install runtimes declared in `~/.config/mise/config.toml`:**
   ```sh
   mise install
   ```

4. **Generate SSH keys** (replace placeholders):
   ```sh
   ssh-keygen -t ed25519 \
     -C "dev@zftadvancements.com (work, $(hostname -s), $(date +%Y-%m))" \
     -f ~/.ssh/id_ed25519_work

   ssh-keygen -t ed25519 \
     -C "you@billwoika.com (personal, $(hostname -s), $(date +%Y-%m))" \
     -f ~/.ssh/id_ed25519_personal
   ```

5. **Edit the profile templates** that `bootstrap.sh` copied in place:
   ```sh
   $EDITOR ~/.config/git/work.config
   $EDITOR ~/.config/git/personal.config
   $EDITOR ~/.config/git/allowed_signers
   $EDITOR ~/.ssh/config
   ```

6. **Register SSH public keys** with GitHub (Authentication and Signing Key
   types separately), and any other remote services.

7. **Validate** the POSIX profile:
   ```sh
   sh ~/dotfiles/sh/tests/profile_test.sh
   # Or sweep dash/bash/busybox:
   sh ~/dotfiles/sh/tests/profile_test.sh --multi
   ```

## Files copied (not symlinked)

`bootstrap.sh` copies rather than symlinks the files that require
per-user identity customization:

- `~/.config/git/work.config`
- `~/.config/git/personal.config`
- `~/.config/git/allowed_signers`
- `~/.ssh/config`

This lets you edit them locally without dirtying the shared dotfiles repo.
If you want to version-control your actual identity (private repo or
separate branch), convert them to symlinks afterwards:

```sh
ln -sfn ~/dotfiles/git/work.config ~/.config/git/work.config
```

## Machine-local overrides

Two locations are reserved for untracked per-machine customization
(loaded last by `~/.config/zsh/.zshrc` if present):

- `~/.config/zsh/aliases.local.zsh` — machine-specific aliases
- `~/.config/zsh/env.local.zsh` — machine-specific environment variables

Add these to the gitignore of any repo that syncs `~/.config/zsh/`.

## Updating

```sh
cd ~/dotfiles
git pull
sh bootstrap.sh                 # re-run after pulls; idempotent
exec zsh
```

New conf.d fragments added upstream are picked up automatically by
the glob in `bootstrap.sh`. Existing symlinks are left alone.

## Design rationale

See the Developer Environment Framework document (v2.2+) for:

- Why XDG layout (Section 3)
- Why mise over proto/asdf/rbenv/pyenv (Section 7)
- Why rv for Ruby specifically (Section 8.1)
- Why emacs mode everywhere (Section 4.8, 19.7.2)
- Why path-based git profiles (Section 17)
- Why IdentitiesOnly on every SSH host (Section 18)
- Why asciicast session logging (Section 19.4)
- Why 1Password + Vault + Keychain as distinct tiers (Appendix A)
