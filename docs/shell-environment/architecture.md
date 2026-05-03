# Shell Architecture

The framework's shell configuration is organized around two principles:
**file-purpose clarity** (every shell startup file has exactly one job)
and **fragment composability** (the actual configuration lives in
small, numbered files that load in order).

## File layout

```
~/.zshenv                     -> dotfiles/zsh/zshenv
~/.profile                    -> dotfiles/profile

~/.config/zsh/
├── .zshenv                   -> dotfiles/zsh/.zshenv
├── .zprofile                 -> dotfiles/zsh/.zprofile
├── .zshrc                    -> dotfiles/zsh/.zshrc
├── .zlogout                  -> dotfiles/zsh/.zlogout
└── conf.d/
    ├── 05-environment.zsh    OS detection, container/IDE/CI flags
    ├── 10-path.zsh           Deterministic PATH with typeset -U
    ├── 20-completion.zsh     compinit with 24h cache
    ├── 25-tool-cache.zsh     Version-hashed cache for tool init/completions
    ├── 30-history.zsh        100k entries, aggressive dedup
    ├── 40-options.zsh        Shell behavior
    ├── 50-keybinds.zsh       emacs mode + WORDCHARS tweak
    ├── 60-aliases.zsh        Core cross-cutting aliases
    ├── 61-git-extensions.zsh Git rebase/checkout flow
    ├── 62-ruby-aliases.zsh   Ruby/Rails/Bundler
    ├── 63-python-aliases.zsh uv/pytest/jupyter
    ├── 64-js-aliases.zsh     bun/biome/tsc
    ├── 66-data-functions.zsh csvsplit, jq helpers
    ├── 67-devloop.zsh        tmux, tree-trunk, serve
    ├── 68-diagnostics.zsh    check-cert, claude-sync-path
    ├── 70-tools.zsh          mise / rv / direnv hooks (Tier 1)
    └── 80-functions.zsh      Core utility functions
```

The split between `~/.zshenv` (a thin shim at the home directory) and
`~/.config/zsh/` (the actual configuration) is the **XDG-compliant
arrangement**. The home-directory `~/.zshenv` exists only because zsh
unconditionally reads it before honoring `ZDOTDIR`; everything it does
is set `ZDOTDIR=~/.config/zsh` and source the real config from there.

## Why fragments instead of one big .zshrc

Three reasons that earn their keep daily:

**Composability.** Each fragment can be added, removed, or skipped
independently. New tooling (a new aliases file for a new language, a
new diagnostics function) drops in as a new file without modifying any
other.

**Conditional loading.** Fragments can guard their entire content with
a single check at the top — `[[ -n $TMUX ]] || return 0` for a
tmux-only fragment, `(( $+commands[mise] )) || return 0` for a
mise-dependent fragment. The shell remains fast and the fragment
contributes nothing when its preconditions aren't met.

**Diff-friendliness.** A change to ruby aliases shows up as a change
to `62-ruby-aliases.zsh`, not as a 5-line diff in the middle of a
500-line `.zshrc`. Code review and `git blame` work better.

## Boot sequence

When you start an interactive login shell:

1. **`/etc/zshenv`** (system-level, rarely customized).
2. **`~/.zshenv`** — the framework's thin shim, sets `ZDOTDIR`.
3. **`$ZDOTDIR/.zshenv`** — XDG variables, tool environment paths.
4. **`/etc/zprofile`** (system-level).
5. **`$ZDOTDIR/.zprofile`** — login-shell PATH finalization.
6. **`/etc/zshrc`** (system-level).
7. **`$ZDOTDIR/.zshrc`** — the interactive orchestrator. Sources every
   `conf.d/*.zsh` fragment in numeric order.
8. **`/etc/zlogin`** (system-level).
9. **`$ZDOTDIR/.zlogin`** (rarely used).

For interactive non-login shells (the common case after the first
session), step 4 and the system files at 4 and 5 are skipped, but
everything else runs.

## XDG state directories

The framework redirects every tool that supports `$XDG_STATE_HOME` and
`$XDG_DATA_HOME` to use them, keeping `$HOME` clean of dot-directories
that should be cache or state.

| Path | Purpose |
|------|---------|
| `~/.config/<tool>/` | Configuration |
| `~/.local/share/<tool>/` | Data the user generates (databases, projects) |
| `~/.local/state/<tool>/` | Runtime state (logs, history, sockets) |
| `~/.cache/<tool>/` | Cache that can be deleted at any time |

Examples in the framework:

- vim writes undo files to `~/.local/state/vim/undo/`
- zsh history goes to `~/.local/state/zsh/history`
- The tool-cache fragment writes to `~/.cache/zsh/`

This is not just aesthetics. Tools that respect XDG can have their
state migrated, backed up, or wiped predictably. A `find ~ -maxdepth 1
-type d` on a framework-configured machine returns a short list, not a
forest of legacy dot-directories.

## What the framework deliberately doesn't have

**Plugin managers.** No oh-my-zsh, prezto, zinit, antigen. Plugin
managers add load-time overhead, depend on remote sources, and most
engineers import 90% of features they never use. The `conf.d/` pattern
provides composability without the dependency.

**Default-installed prompt frameworks.** No starship, powerlevel10k,
spaceship as a default. The framework's prompt is small zsh that shows
git status and exit code. Engineers who want a fancier prompt add it
themselves; default-installing one is opinionated about something
users genuinely have preferences on.

**Programmatic environment-variable mutation in shells.** The
framework's hard rule is that every shell fragment must be a no-op for
shells where its tooling isn't present. A `.zshrc` that fails to load
in a container missing some tool is a broken dotfile.
