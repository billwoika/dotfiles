# XDG and POSIX Compliance

The XDG Base Directory Specification defines a set of well-known
environment variables that applications should use to locate
user-specific files, rather than scattering them across `$HOME`. The
practical outcome is a `$HOME` directory with a handful of dotfiles
instead of dozens, and a predictable directory hierarchy that backup
tools, sync clients, and dotfiles managers can reason about.

mise is XDG-native by default — unlike many CLI tools, it does not
require overrides to respect `XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
`XDG_CACHE_HOME`, and `XDG_STATE_HOME`. This eliminates a class of
toolchain-specific boilerplate that was previously necessary for proto
(`PROTO_HOME`), volta (`VOLTA_HOME`), and similar managers.

## XDG variable definitions

| Variable | Default | Holds |
|----------|---------|-------|
| `XDG_CONFIG_HOME` | `~/.config` | User-specific config files — read/write by user, not programs |
| `XDG_DATA_HOME` | `~/.local/share` | User-specific data files — application-generated, persistent |
| `XDG_STATE_HOME` | `~/.local/state` | Persistent but non-critical state: history, logs, layout |
| `XDG_CACHE_HOME` | `~/.cache` | Non-essential cached data — safe to delete at any time |
| `XDG_RUNTIME_DIR` | Set by PAM/systemd | Runtime files: sockets, fifos, named pipes — 0700, cleared on logout |

Zsh does not read `XDG_CONFIG_HOME` by default — it always looks in
`$HOME` for `.zshenv`, `.zprofile`, `.zshrc`, `.zlogin`. The bridge is
`ZDOTDIR`: when set, zsh looks for its dotfiles in that directory
instead of `$HOME`. The challenge is that `ZDOTDIR` must be set
*before* zsh reads any user dotfile — which means it must be set in a
file that zsh reads unconditionally: `/etc/zshenv` or `~/.zshenv`
(still in `$HOME`, read before `ZDOTDIR` takes effect). The
`~/.zshenv` bootstrap solves this.

## The bootstrap file (~/.zshenv)

This is the only file that lives in `$HOME`. Its sole responsibility
is to set `ZDOTDIR` and then immediately hand off to the XDG-located
`.zshenv`. It contains nothing else — no PATH manipulation, no
aliases, no conditionals beyond the `ZDOTDIR` redirect. Keep this
file under ten lines.

```sh
# ~/.zshenv
# ─────────────────────────────────────────────────────────────────────
# Bootstrap only. Redirects zsh to the XDG config directory.
# All further configuration lives in $ZDOTDIR.
# ─────────────────────────────────────────────────────────────────────

# Establish XDG base directories with POSIX-compliant defaults.
# Use := assignment: set only if unset or empty (idempotent).
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:=$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:=$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:=$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:=$HOME/.cache}"

# Point zsh at its XDG config directory.
# Subsequent files (.zshrc, .zprofile, etc.) are resolved from here.
export ZDOTDIR="${XDG_CONFIG_HOME}/zsh"
```

!!! note "System-level alternative"

    On systems where you have root access (e.g., a personal workstation
    or managed team machine), you can set `ZDOTDIR` in `/etc/zsh/zshenv`
    instead, which eliminates the need for a `~/.zshenv` bootstrap file
    entirely. The per-user bootstrap approach shown here works without
    root and is suitable for both personal machines and shared/managed
    environments.

## Directory structure

The full XDG-compliant zsh config tree:

```
~/.zshenv                           # Bootstrap only — sets ZDOTDIR

~/.config/zsh/                      # $ZDOTDIR — all zsh config lives here
├── .zshenv                         # Env vars, XDG tool redirects, PATH seeds
├── .zprofile                       # Login-shell PATH finalization
├── .zshrc                          # Interactive shell settings, sources conf.d/
├── .zlogout                        # Cleanup on login shell exit
└── conf.d/                         # Modular fragments, loaded in sorted order
    ├── 10-path.zsh
    ├── 20-completion.zsh
    ├── 25-tool-cache.zsh
    ├── 30-history.zsh
    ├── 40-options.zsh
    ├── 50-keybinds.zsh
    ├── 60-aliases.zsh
    ├── 61-git-extensions.zsh
    ├── 62-ruby-aliases.zsh
    ├── 63-python-aliases.zsh
    ├── 64-js-aliases.zsh
    ├── 66-data-functions.zsh
    ├── 67-devloop.zsh
    ├── 68-diagnostics.zsh
    ├── 70-tools.zsh                # mise, direnv, rv, ssh-agent (Tier 1)
    └── 80-functions.zsh

~/.config/mise/                     # mise global config
└── config.toml                     # User-scope tool/env/task defaults

~/.local/share/mise/                # mise state — installs, shims, plugins
├── shims/                          # Shims used by non-interactive subprocesses
└── installs/                       # Installed tool versions

~/.local/state/zsh/                 # Runtime state — NOT in config directory
└── history

~/.cache/zsh/                       # Caches — safe to delete
└── zcompdump
```

!!! tip "Why number the conf.d fragments?"

    Numeric prefixes enforce deterministic load order without relying on
    filesystem inode ordering (which varies by OS and filesystem). The
    gaps (10, 20, 30...) leave room to insert new fragments without
    renaming existing ones. Use two-digit prefixes — the sort order of
    `10` vs. `9` is alphabetic, so `09` sorts before `10` correctly, but
    single digits do not.
