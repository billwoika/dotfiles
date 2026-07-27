# Repository Structure

The dotfiles repository is the canonical source for all framework
configuration. Everything is plain files — no package manager, no
build step for the dotfiles themselves (MkDocs is only for the docs
site).

## Layout

```
dotfiles/
├── LICENSE                  GPLv3-or-later, Bill Woika 2026
├── README.md                Layer-1 short-form intro
├── CLAUDE.md                Claude Code guidance
├── mkdocs.yml               MkDocs Material site config
├── bootstrap.sh             Idempotent symlink installer
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
├── mise/config.toml         User-scope mise config
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

What it does:

1. **Creates XDG directories** — `~/.config/zsh/conf.d`,
   `~/.config/mise`, `~/.config/direnv`, `~/.config/git`,
   `~/.config/tmux`, `~/.local/share`, `~/.local/state/zsh`,
   `~/.cache/zsh`, `~/.ssh/control`, `~/.local/bin`
2. **Symlinks configuration files** — zsh, mise, direnv, git, tmux,
   vim into their XDG-compliant locations
3. **Copies templates** — git profiles (work, personal,
   allowed_signers) and SSH config are *copied* not symlinked, so
   users can edit them locally without dirtying the dotfiles repo
4. **Detects optional apps** — creates CLI wrappers for TextMate and
   MarkEdit if they're installed
5. **Audits shell startup files** — scans for rogue tool-installer
   injections from nvm, volta, pyenv, etc.

Usage:

```sh
sh bootstrap.sh              # install
sh bootstrap.sh --dry-run    # preview what would be done
sh bootstrap.sh --help       # show usage
```

## What's symlinked vs. copied

| Pattern | Symlinked | Copied |
|---------|-----------|--------|
| Shared config (zsh, mise, direnv, git core, tmux, vim) | Yes | |
| Identity templates (git profiles, SSH config, allowed_signers) | | Yes (first run only) |
| Project templates (.editorconfig, .gitignore, vscode, jetbrains, devcontainer) | | Manual copy per project |

The distinction: symlinked files are managed by the framework and
update when you pull. Copied files are personalized per machine and
per project — the framework provides the template, you own the
instance.
