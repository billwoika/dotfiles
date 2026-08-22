# Developer Environment Framework

A small, opinionated set of dotfiles and configuration patterns for engineers
who want their development environment to be reproducible across machines,
honest about its choices, and quick to recover when something breaks.

> **Status:** Personal project. Free to use, fork, and adapt. Licensed
> [GPLv3-or-later](LICENSE).

---

## What this is

A working set of dotfiles and a written framework that explains why each
piece is the way it is. The dotfiles are real configuration that runs on
this engineer's laptop and several other machines; the framework document
explains the design decisions that produced them.

The full framework — currently a 200+ page manuscript covering shell
architecture, toolchain orchestration, git, SSH, terminal multiplexing,
containers, editors and IDEs, secrets management, and the rest — is being
migrated from a Word document into [the docs site][docs].

This README is the **short version**: enough to install the dotfiles, get
oriented, and decide whether the rest is worth your time.

[docs]: https://devdocs.billwoika.com

## What's in the box

| Concern | Tool | Why this one |
|---------|------|--------------|
| Shell | zsh, emacs-mode keybindings | More featureful than bash; emacs-mode matches every other text widget on the system |
| Toolchain version management | [mise](https://mise.jdx.dev) | Replaces asdf, nvm, rbenv, pyenv, and several others with one tool. Polyglot, fast, and honest about its own limits |
| Python | [uv](https://github.com/astral-sh/uv) | The fastest Python package and project manager. Replaces pip, virtualenv, pip-tools, pipx, and poetry for most projects |
| Ruby | [rv](https://github.com/spinel-coop/rv) | Modern Ruby version + gem manager; uv-influenced design, faster than rbenv and bundler |
| JavaScript | [bun](https://bun.com) (package manager) + Node (runtime) | bun for installs and lockfile (10-100x faster than npm); Node as the runtime for ecosystem compatibility with native bindings |
| Build orchestration | [mise tasks](https://mise.jdx.dev/tasks/) + Make wrapper | mise tasks for the project's actual build logic; a thin Makefile for `make test` universal recognition |
| Git multi-identity | per-directory `includeIf` rules | Work and personal commits use different signing keys, automatically, based on which directory the repo lives in |
| Terminal | iTerm2 (macOS), WezTerm / Kitty / Alacritty (Linux) + tmux | Native terminal emulator per platform, tmux for session persistence and multi-host work |
| Containers | [Podman](https://podman.io) (preferred), Docker / Colima / OrbStack where required | Rootless, daemonless, always free; CLI-compatible with Docker so all commands transfer |
| Editors | vim (`$EDITOR`), VS Code, JetBrains, plus native GUI editors (macOS: TextMate, MarkEdit) | Multi-editor reality, with the framework ensuring all of them participate in the same reproducibility contract |
| Secrets | 1Password CLI, with Vault and sops as alternatives | Credentials live in vaults, never on disk; the shell pulls them via `op read` references in `.envrc` |

## What's not in the box

- AI-assisted coding tools. They have their own document covering both
  technical configuration and guardrails — kept separate because the
  considerations include policy, not just config.
- Anything OS-specific to Windows. The framework targets macOS and Linux.
- Project management, ticketing, communication tools. These are
  team-level concerns, not personal-environment concerns.
- Any tool the framework hasn't actually used in production for at
  least a few months. Recommendations are opinions backed by
  experience, not hot takes from a blog post.

## Installing

The dotfiles are designed to be cloned, inspected, and run.

```sh
# 1. Clone — into the profile tree, where the repo's own git identity
#    and mise profile apply to it like any other personal repo
export DOTFILES="$HOME/development/personal/repos/dotfiles"
git clone https://github.com/billwoika/dotfiles.git "$DOTFILES"
cd "$DOTFILES"

# 2. Read what bootstrap.sh will do (it's a shell script; read it first)
less bootstrap.sh

# 3. Run it (filesystem only: symlinks, directories, seed copies)
sh bootstrap.sh

# 4. Provision everything else with mise. bin/mise is vendored and
#    version-pinned — no `curl | sh` anywhere in this flow. This is the
#    step that installs software, and its first move is a sudo package
#    install from [bootstrap.packages]; run it deliberately.
bin/mise bootstrap

# 5. Restart your shell
exec zsh -l
```

The bootstrap script:
- Symlinks the configuration files into `~/.config/`, `~/.zshenv`, `~/.profile`, etc.
- Creates the XDG state directories and the
  `~/development/{personal,work,opensource}/repos` profile tree.
- Copies the editable seeds: git identity templates, per-profile
  `mise.toml` files, SSH config.
- Auto-detects TextMate and MarkEdit (macOS) and creates their CLI shortcuts if installed.
- Audits your existing shell startup files for rogue mutations and warns about them.
- Skips anything already correctly linked. Re-running it is safe.

It does **not**:
- Install software via Homebrew, `apt`, or any other package manager.
- Modify any system-wide configuration.
- Run with `sudo`.
- Touch files outside your home directory.

The framework's stance: a bootstrap script that silently touches system
state is a bootstrap script you can't run on a borrowed machine, can't
trust on a fresh machine, and can't easily reverse if something goes
wrong. Software installation is a separate, **declarative** concern:
`mise bootstrap` reads the committed config — `[bootstrap.packages]`
for the handful of system packages (zsh, libsecret, ffmpeg), `[tools]`
for everything else — so the one command that does escalate is
explicit, inspectable in version control, and runs only when you
invoke it. Under the hood the modern managers do the work: `uv tool
install` for Python CLIs, `bun` for npm-backed tools, `cargo-binstall`
for crates.

### Reference templates

After bootstrap, several reference templates are available to copy into
individual project repositories. They are explicitly **not** symlinked
into your home directory — each project owns its own copy.

```sh
# Project-level .editorconfig — cross-editor formatting conventions
cp "$DOTFILES/.editorconfig.example" <project>/.editorconfig

# Project-level .gitignore — IDE state, language artifacts, secrets patterns
cat "$DOTFILES/gitignore.example" >> <project>/.gitignore

# VS Code workspace templates
cp "$DOTFILES/vscode/settings.json.example"   <project>/.vscode/settings.json
cp "$DOTFILES/vscode/extensions.json.example" <project>/.vscode/extensions.json
cp "$DOTFILES/vscode/launch.json.example"     <project>/.vscode/launch.json

# JetBrains shared run configurations
cp "$DOTFILES/jetbrains/runConfigurations/"*.xml <project>/.idea/runConfigurations/

# Devcontainer template
cp -r "$DOTFILES/devcontainer/" <project>/.devcontainer/
```

### macOS-specific opt-in steps

Three optional things the bootstrap output mentions and you can run later:

```sh
# Interactive file-association setup (TextMate / MarkEdit / VS Code).
# duti itself is declarative — mise bootstrap installed it from
# mise/config.macos.toml.
sh "$DOTFILES/macos/setup-file-associations.sh"

# Add mise shims to GUI app PATH (so VS Code, JetBrains see mise tools
# even when launched from Finder, not the terminal)
echo "$HOME/.local/share/mise/shims" | sudo tee /etc/paths.d/mise > /dev/null
# Effect takes hold after the next login.
```

### Linux-specific opt-in steps

```sh
# Ensure zsh is the default shell (if not already; zsh and libsecret
# are installed declaratively by mise bootstrap via mise/config.linux.toml)
chsh -s $(which zsh)

# Add mise shims to GUI app PATH (systemd-based distros)
mkdir -p ~/.config/environment.d
echo 'PATH=$HOME/.local/share/mise/shims:$PATH' > \
  ~/.config/environment.d/mise.conf
# Effect takes hold after the next login.
```

## Getting oriented

The framework is split across three layers, each serving a different
purpose:

### Layer 1 — this README

You're reading it. Short-form overview, install instructions, and
pointers to the deeper material. If this is enough for you, great.

### Layer 2 — the docs site

The full framework, organized for navigation. Topic-based pages
covering each tool and pattern in depth. **This is where to look if
you have a specific question** — "how does the multi-identity git
setup work?" or "what's the relationship between mise tasks and Make?"

The site is at [devdocs.billwoika.com][docs]. Or run
`mkdocs serve` from this directory for local browsing.

### Layer 3 — runbooks alongside the code

Long-running operational knowledge — how a specific service is
deployed, how to rotate a specific credential, how to recover from a
specific class of failure — lives in the project repos that own those
operations, not here. The framework provides the patterns (see the
[operations docs](https://devdocs.billwoika.com)); the runbooks
instantiate them.

## Customization

The framework's source uses a small set of placeholder strings that
should be substituted when forking. They were chosen to be distinctive
enough to grep without colliding with unrelated content.

| Placeholder | Substitute with |
|-------------|-----------------|
| `zftadvancements` (org name) | Your organization's slug |
| `zftadvancements.com` (org domain) | Your organization's domain |
| `zftadvancements.internal` (internal infra) | Your internal-network suffix |
| `bastion.zftadvancements.internal` | Your bastion host |
| `billwoika.com` (personal domain) | Your personal domain |
| `dev@zftadvancements.com` (work email) | Your work email |
| `you@billwoika.com` (personal email) | Your personal email |
| `your-username` | Your GitHub / SSH username |

A blanket `sed` pass after cloning gets most of the way:

```sh
grep -rl 'zftadvancements\|billwoika\|your-username' . | \
  xargs sed -i \
    -e 's/zftadvancements/your-org/g' \
    -e 's/billwoika/your-domain/g' \
    -e 's/your-username/your-user/g'
```

Then audit the result. The placeholder strings are deliberately
distinctive (real org name, real personal domain) so they don't show
up unexpectedly in unrelated content; the substitution should be clean.

## What this framework deliberately does not have

Worth being explicit about, because frameworks of this kind tend to
accumulate cruft.

**Plugin managers for zsh** (oh-my-zsh, prezto, etc.) — They add
load-time overhead, depend on remote sources, and most engineers
import 90% of features they never use. The framework's `conf.d/`
pattern provides composability without the dependency.

**Powerline / starship-style prompts by default** — The framework's
prompt is a small bit of zsh that includes git status and exit code
and that's it. Engineers who want a fancier prompt add it themselves
via `aliases.local.zsh`. Default-installing one is opinionated about
something users genuinely have preferences on.

**Zsh frameworks that "manage" your dotfiles** — chezmoi, yadm, and
similar are powerful but introduce a layer of templating and
conditional logic between you and your config. The framework prefers
plain symlinks that are obvious about what they do. (mise's
`[dotfiles]` section is used as a declarative *applier* of those same
plain symlinks — desired state in version control — not as a
templating layer.)

**Programmatic environment-variable mutation in shells of any kind** —
The framework's hard rule (covered in the docs) is that every shell
fragment must be a no-op for shells where its tooling isn't present.
A `.zshrc` that fails to load in a container missing some tool is a
broken dotfile.

**Fish, nushell, or other non-POSIX-derived shells** — The framework's
`profile` (POSIX `~/.profile`) ensures any subprocess that gets a
shell gets a working PATH and environment. Switching to a non-POSIX
shell as the primary shell breaks this story; the framework targets
zsh as the interactive shell precisely because it's POSIX-compatible
enough to keep the subprocess story simple.

## Repository layout

```
dotfiles/
├── LICENSE                  GPLv3-or-later
├── README.md                You are here
├── mkdocs.yml               Docs site configuration
├── docs/                    Layer-2 documentation source (deployed to devdocs.billwoika.com)
├── archive/                 Archived earlier versions of the framework
├── _drafts/                 Work-in-progress content, excluded from site
│
├── bootstrap.sh             Idempotent filesystem installer
├── bin/                     Vendored, version-pinned mise launcher
├── profile                  ~/.profile — POSIX shim for non-zsh subprocesses
│
├── zsh/                     Zsh configuration (XDG-compliant)
├── mise/                    mise config: tools, settings, [dotfiles],
│                            per-OS bootstrap packages, profile seeds
├── direnv/                  direnvrc with 1Password / Vault / sops helpers
├── git/                     Git config with includeIf profile rules
├── ssh/                     SSH client config templates
├── tmux/                    tmux config (emacs-mode, F12 nested escape)
├── vim/                     Minimal sensible-defaults vimrc
│
├── vscode/                  VS Code workspace templates (settings, extensions, launch)
├── jetbrains/               JetBrains reference templates and runConfigurations
├── macos/                   macOS-specific opt-in helpers
├── linux/                   Linux-specific opt-in helpers
├── devcontainer/            Reference templates for project devcontainers
│
├── .editorconfig.example    Cross-editor formatting reference
├── gitignore.example        Reference project-level .gitignore
│
└── sh/tests/                POSIX sh test suite for ~/.profile
```

## Versioning

The framework is versioned via the docs site, not the dotfiles. Dotfile
changes that break compatibility get noted in the relevant docs page;
otherwise the dotfiles are continuously developed on `master`.

Earlier framework versions (when the manuscript was a Word document)
are preserved in [archive/](archive/). The most recent of those is
v2.7-snapshot.docx, frozen at the start of the MkDocs migration.

## Contributing

This is a personal artifact, not a community project. Issues and PRs
are welcome but won't always be accepted — the framework reflects one
engineer's specific opinions, and the rejection of suggestions is part
of how it stays coherent.

If you fork it for your own use: substitute the placeholder strings,
adapt the patterns to your stack, and own the result. The GPLv3
license requires that any distributed derivative remain GPLv3, but
internal use within an organization (no distribution) is unrestricted.

## License

Copyright © 2026 Bill Woika.

Licensed under the GNU General Public License, version 3, or any
later version. See [LICENSE](LICENSE) for the full text.

GPLv3 was chosen deliberately. It ensures that anyone who builds on
this work and distributes the result preserves the same freedoms it
was distributed under. For an organization adopting these patterns
internally, GPLv3's distribution clause is not triggered — internal
use is unrestricted.
