# Aliases and Functions Library

This is a curated library of aliases and shell functions organized by
domain. The core set in `conf.d/60-aliases.zsh` and the baseline
functions in `conf.d/80-functions.zsh` cover the universal cases; the
items below are domain-specific. They are meant to be sourced
selectively — not adopted wholesale. Pick the handful that pay for
themselves in your actual daily workflow; ignore the rest.

## Aliases vs. functions

The distinction matters. An alias is a text substitution; a function is
a program. The rule for choosing between them:

- **Aliases** for fixed abbreviations of a single command with no
  arguments. `alias gs='git status -sb'` is correct; `alias gc='git
  checkout $1'` is wrong (the `$1` is literal, not expanded).
- **Functions** for anything involving arguments, conditionals, loops,
  or error handling. If the thing you're defining has a verb followed
  by a parameter, it's a function.
- **Never both** — don't define an alias and a function with the same
  name, and don't alias a function name. The resolution order will
  surprise you.

!!! warning "Two safety rules"

    Never alias a destructive command in a way that changes its default
    semantics (`alias rm='rm -i'` creates inconsistency between
    interactive and scripted use). If you want interactive safety, bind
    it to a separate name (`alias rmi='rm -i'`).

    Never alias a command that runs over SSH or in subshells in a way
    that assumes your alias is present — aliases are only loaded in
    interactive shells.

## Core aliases (conf.d/60-aliases.zsh)

The core file covers cross-cutting concerns:

| Category | Examples | Notes |
|----------|----------|-------|
| Navigation | `..`, `...`, `....`, `-` | `cd` shortcuts |
| Listing | `l`, `ll`, `la`, `lt`, `lS` | Auto-detects GNU vs BSD `ls` |
| Safety | `cp -v`, `mv -v` | Verbose, not semantic-changing |
| Process | `psa`, `psg`, `killit` | Process inspection |
| Network | `myip`, `listening`, `ports` | Quick network checks |
| Git (core) | `g`, `gs`, `ga`, `gc`, `gp`, `gpl`, `gd`, `gl` | Short forms |
| mise | `m`, `mr`, `mx` | Task runner entry points |
| Ruby | `be`, `bi`, `bo`, `rvr`, `rvi` | Bundler and rv |
| Python | `uvr`, `uvs`, `uva` | uv commands |
| Bun | `br`, `bx` | Bun run/exec |
| System | `reload`, `path`, `now` | Shell management |
| direnv | `da`, `de`, `ds` | Allow/edit/status |

## Git extensions (conf.d/61-git-extensions.zsh)

Beyond the core aliases, the git extensions handle rebase flow, quick
checkouts, and branch hygiene — cases where fixed-text aliases aren't
enough.

```zsh
# Rebase against a remote branch (fetches first for safety)
git-rebase-remote() {
  [[ $# -eq 1 ]] || { echo "usage: git-rebase-remote <branch>" >&2; return 1; }
  git fetch origin "$1" && git rebase "origin/$1"
}
alias grm='git-rebase-remote main'
alias grs='git-rebase-remote staging'

# Interactive rebase on the last N commits
gir() {
  [[ $# -eq 1 ]] || { echo "usage: gir <N>" >&2; return 1; }
  git rebase -i "HEAD~$1"
}
alias gra='git rebase --abort'
alias grc='git rebase --continue'

# Commit with a message (positional, quoted automatically via "$*")
gcm() {
  [[ $# -ge 1 ]] || { echo "usage: gcm <message>" >&2; return 1; }
  git commit -m "$*"
}

# Checkout a new branch
gcrb() {
  [[ $# -eq 1 ]] || { echo "usage: gcrb <branch-name>" >&2; return 1; }
  git checkout -b "$1"
}

# Clean merged local branches, excluding main/master/develop
gclean() {
  git branch --merged | \
    grep -vE '^\*|^\s*(main|master|develop)\s*$' | \
    xargs -n 1 git branch -d
}
```

The `gcm` function uses `"$*"` rather than `"$1"` so you can write
`gcm fix login bug` without quoting the whole message. All functions
use argument validation because the most common shell-function bug is
invoking one without its positional argument and getting a silent,
wrong-feeling operation.

## Ruby and Rails (conf.d/62-ruby-aliases.zsh)

```zsh
alias be='bundle exec'
alias bi='bundle install'
alias rs='rails server'
alias rc='DISABLE_PRY_RAILS=1 rails console'
alias rake='bundle exec rake'
alias sidekiq='bundle exec sidekiq'
alias t-rspec='bundle exec rspec --format progress --color'
```

## Python / uv (conf.d/63-python-aliases.zsh)

```zsh
alias uvr='uv run'
alias uvs='uv sync'
alias uva='uv add'
alias pt='uv run pytest'
alias ptv='uv run pytest -v'
alias ptx='uv run pytest -x'
alias jn='uv run jupyter notebook'
alias jl='uv run jupyter lab'
```

## JavaScript / bun (conf.d/64-js-aliases.zsh)

```zsh
alias br='bun run'
alias bx='bun x'
alias bt='bun test'
alias bi='bun install'
alias biome='bun x biome'
```

## Data and text processing (conf.d/66-data-functions.zsh)

Functions for CSV splitting, jq helpers, and data inspection that
surface frequently in data-adjacent workflows.

## Development loop (conf.d/67-devloop.zsh)

tmux session management, `tree-trunk` for project tree visualization,
and `serve` for quick HTTP serving of the current directory.

## Diagnostics (conf.d/68-diagnostics.zsh)

TLS certificate checking (`check-cert`), Claude Code path
synchronization, and other system-level diagnostic functions.

## Core functions (conf.d/80-functions.zsh)

| Function | Usage | Purpose |
|----------|-------|---------|
| `mkcd <dir>` | `mkcd tmp/scratch` | Create and cd into a directory |
| `up [N]` | `up 3` | cd up N directories |
| `path_add <dir>` | `path_add ~/tools/bin` | Safely add to PATH at runtime |
| `mise_pin <tool> <ver>` | `mise_pin ruby 3.3.4` | Pin a tool in the project's mise.toml |
| `mise_tasks` | `mise_tasks` | List tasks including hidden ones |
| `envdiff` | `envdiff` | Show env vars added by mise.toml + .envrc |
| `extract <file>` | `extract archive.tar.gz` | Unpack any common archive format |
| `port_kill <port>` | `port_kill 3000` | Kill the process on a given port |
| `timeshell [N]` | `timeshell 10` | Benchmark zsh startup time (N runs) |
| `keychain_get <svc>` | `keychain_get github` | Cross-platform secret lookup (macOS Keychain / Linux Secret Service) |

## Machine-local overrides

The framework supports two untracked files for per-machine
customization without forking the shared `conf.d/` fragments:

- `$ZDOTDIR/aliases.local.zsh` — local aliases and overrides
- `$ZDOTDIR/env.local.zsh` — local environment variables

Both are sourced at the end of `.zshrc` if they exist, so they
override anything in `conf.d/`.

## Organizing aliases at scale

The framework's numbering convention keeps aliases organized:

| Range | Domain | Fragment |
|-------|--------|----------|
| 60 | Core cross-cutting | `60-aliases.zsh` |
| 61 | Git extensions | `61-git-extensions.zsh` |
| 62 | Ruby/Rails | `62-ruby-aliases.zsh` |
| 63 | Python/uv | `63-python-aliases.zsh` |
| 64 | JavaScript/bun | `64-js-aliases.zsh` |
| 66 | Data/text processing | `66-data-functions.zsh` |
| 67 | Development loop | `67-devloop.zsh` |
| 68 | Diagnostics | `68-diagnostics.zsh` |

New language-specific or domain-specific aliases go in a new numbered
fragment. The gaps between numbers exist precisely for this.

For **project-local aliases**, use mise tasks instead — they're
discoverable via `mise tasks ls`, shareable via `mise.toml`, and
don't pollute the global shell namespace.
