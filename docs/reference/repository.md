# Repository Structure

The dotfiles repository is the canonical source for all framework
configuration. Everything is plain files — no package manager, no
build step for the dotfiles themselves (MkDocs is only for the docs
site).

## Layout

```
dotfiles/                    # lives at ~/development/personal/repos/dotfiles
├── LICENSE                  GPLv3-or-later, Bill Woika 2026
├── README.md                Layer-1 short-form intro
├── mkdocs.yml               MkDocs Material site config
├── bootstrap.sh             Idempotent filesystem installer
├── bin/mise                 Vendored, version-pinned mise launcher
│                            (mise generate bootstrap — no curl | sh)
├── profile                  ~/.profile — POSIX shim
├── .editorconfig            Editor formatting rules
├── .editorconfig.example    Template for projects
├── .gitignore               Repo-level ignores
├── gitignore.example        Template for projects
│
├── docs/                    MkDocs source (Layer 2)
│   ├── index.md
│   ├── requirements.txt     Pinned MkDocs dependencies
│   ├── shell-environment/   Shell architecture and configuration
│   ├── tools/               Toolchain, package managers, editors
│   ├── git/                 Git configuration and practices
│   ├── operations/          Secrets, SSH, environment
│   ├── handbook/            Design opinions and patterns
│   └── reference/           Customization, test suite, this page
│
├── zsh/                     Zsh configuration (22 files)
│   ├── zshenv               ~/.zshenv bootstrap (thin shim)
│   ├── .zshenv              $ZDOTDIR/.zshenv (environment)
│   ├── .zprofile            Login shell PATH finalization
│   ├── .zshrc               Interactive orchestrator
│   ├── .zlogout             Cleanup on login shell exit
│   └── conf.d/              Numbered fragments (05-80)
│
├── mise/                    mise configuration
│   ├── config.toml          User-scope config: [tools], [settings],
│   │                        [dotfiles], global tasks
│   ├── miserc.toml          Early-init settings (auto_env) — decides
│   │                        WHICH configs load, so lives outside them
│   ├── config.linux.toml    [bootstrap.packages] via dnf/apt
│   ├── config.macos.toml    [bootstrap.packages] via brew/brew-cask
│   ├── mise.lock            Resolved versions + URLs for every [tools]
│   │                        entry (settings.lockfile = true); mise
│   │                        writes it here through the ~/.config/mise
│   │                        symlink. Refresh with `mise lock -g`
│   └── *.mise.toml.example  Per-profile seeds, copied to
│                            ~/development/{personal,work,opensource}/
├── direnv/direnvrc          1Password / Vault / sops helpers
│
├── git/                     Git configuration
│   ├── config               Main config (include local + includeIf profiles)
│   ├── ignore               Global gitignore
│   ├── attributes           Global gitattributes
│   ├── local.config.example # user.name (copied, not symlinked)
│   ├── work.config.example
│   ├── personal.config.example
│   ├── opensource.config.example
│   └── allowed_signers.example
│
├── ssh/config.example       SSH config template
├── tmux/tmux.conf           tmux configuration
├── vim/vimrc                Minimal vim configuration
│
├── vscode/                  Reference templates
│   ├── settings.json.example
│   ├── extensions.json.example
│   └── launch.json.example
│
├── jetbrains/               Run configurations
│   ├── README.md
│   └── runConfigurations/
│
├── devcontainer/            Reference devcontainer templates
│   ├── devcontainer.json
│   ├── Dockerfile.dev
│   ├── compose.yml.example
│   ├── post-create.sh
│   └── README.md
│
├── macos/                   macOS-specific setup
│   └── setup-file-associations.sh
├── linux/README.md          Linux-specific notes
│
├── sh/tests/                POSIX test suite
│   └── profile_test.sh
│
├── _drafts/                 Unpublished content
├── archive/                 Frozen Word manuscript snapshots
└── .github/workflows/       CI (docs build + deploy)
```

## bootstrap.sh

The bootstrap script is the framework's installer. It is written in
POSIX sh (no bashisms) so it runs on a freshly-provisioned machine
before any zsh framework is active.

It prepares the filesystem; software installation is mise's job
(`bin/mise bootstrap`). What it does:

1. **Creates directories** — the XDG tree (`~/.config/zsh/conf.d`,
   `~/.config/mise`, `~/.config/direnv`, `~/.config/git`,
   `~/.config/tmux`, `~/.local/share`, `~/.local/state/zsh`,
   `~/.cache/zsh`, `~/.local/bin`), security-sensitive dirs with 0700
   (`~/.ssh/control`, `$XDG_DATA_HOME/gnupg`), and the profile tree
   `~/development/{personal,work,opensource}/repos`
2. **Symlinks configuration files** — zsh, mise, direnv, git, tmux,
   vim into their XDG-compliant locations. This includes the mise
   files that mise's own `[dotfiles]` pass cannot self-apply because
   they decide what mise loads: `miserc.toml` (early-init `auto_env`)
   and the per-OS `config.linux.toml` / `config.macos.toml`
3. **Copies editable seeds** — git profiles (local, work, personal,
   opensource, allowed_signers), SSH config, and the per-profile
   `mise.toml` files under `~/development/` (then `mise trust`s them).
   *Copied* not symlinked, so users edit them locally without dirtying
   the dotfiles repo
4. **Detects optional apps** — creates CLI wrappers for TextMate and
   MarkEdit if they're installed
5. **Audits shell startup files** — scans for rogue tool-installer
   injections from nvm, volta, pyenv, etc.

Usage:

```sh
sh bootstrap.sh               # install
sh bootstrap.sh --dry-run     # preview what would be done
sh bootstrap.sh --audit-only  # run only the rogue-injection audit
sh bootstrap.sh --help        # show usage
```

## What's symlinked vs. copied

| Pattern | Symlinked | Copied |
|---------|-----------|--------|
| Shared config (zsh, mise, direnv, git core, tmux, vim) | Yes | |
| Identity templates (git profiles, SSH config, allowed_signers) | | Yes (first run only) |
| Per-profile mise seeds (`~/development/*/mise.toml`) | | Yes (first run only) |
| Project templates (.editorconfig, .gitignore, vscode, jetbrains, devcontainer) | | Manual copy per project |

The distinction: symlinked files are managed by the framework and
update when you pull. Copied files are personalized per machine and
per project — the framework provides the template, you own the
instance.
