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

## Directories that escape XDG

XDG compliance is not total, and pretending otherwise sets a false
expectation. Two different things put dot-directories back in `$HOME`,
and they have different fixes.

**Tools the framework relocates — but only once its environment is
loaded.** These honor an environment variable, and the framework sets
it. If the tool runs before that variable is exported — in a bash
session, or in a shell that has not yet sourced the zsh chain or
`~/.profile` — the tool falls back to its default `$HOME` location and
the directory leaks:

| Directory in `$HOME` | Relocated by | To |
|----------------------|--------------|-----|
| `~/.cargo` | `CARGO_HOME` | `$XDG_DATA_HOME/cargo` |
| `~/.rustup` | `RUSTUP_HOME` | `$XDG_DATA_HOME/rustup` |
| `~/.gnupg` | `GNUPGHOME` | `$XDG_DATA_HOME/gnupg` |
| `~/go` | `GOPATH` | `$XDG_DATA_HOME/go` |
| `~/.viminfo` | `set viminfofile` in `vimrc` | `$XDG_STATE_HOME/vim/viminfo` |

Seeing one of these in `$HOME` means the tool ran with a stale
environment, not that relocation failed. The fix is ordering: ensure
the framework environment is active before installing or first running
the tool (see the [onboarding runbook](../reference/onboarding.md)). If
the directory already leaked, it is safe to remove the empty stub once
the correctly-located one exists — but inspect first, because a tool
that already wrote real data (gpg keys, cargo credentials) to the
`$HOME` path will not find it at the XDG path.

**Tools that ignore XDG entirely — the accepted-holdout list.** These
hardcode a `$HOME` path and honor no usable environment variable, so
the framework cannot redirect them. This is the canonical list of
entries the framework considers *expected* in `$HOME`. Anything here is
known cruft to be left alone; anything in `$HOME` that is **not** here
(and not a framework symlink) is worth investigating as rogue.

| Entry in `$HOME` | Created by | Why it cannot move |
|------------------|------------|--------------------|
| `~/.mozilla` | Firefox | Profile root is hardcoded; no XDG support upstream |
| `~/.pki` | NSS / Chromium / some TLS clients | NSS database path is hardcoded |
| `~/.claude.json` | Claude Code | Top-level config file path is fixed to `$HOME`; no override variable (upstream feature request open) |

For `~/.mozilla` and `~/.pki` there is no framework lever at all; they
are the cost of running a browser. Do not spend effort trying to
relocate these.

`~/.claude.json` deserves a precise note, because it is half-movable
and easy to get wrong. The Claude Code **config directory** —
`~/.claude/` (settings, skills, agents, memory) — does honor
`CLAUDE_CONFIG_DIR`, and the framework works with that directory
directly. The top-level **`~/.claude.json`** file is the part that
stays: as of this writing it is written to `$HOME` with no documented
way to relocate it. So the directory can move and the file cannot —
treat the file as a holdout and leave it.

This table is documentation, not enforcement. There is deliberately no
script that deletes or relocates these — the framework states what is
expected and stops there. If a future home-directory audit is added, it
should read this list as its allowlist rather than hard-coding the
entries a second time; keep this table the single source of truth.

### Vim is a deliberate placement, not a holdout

Vim is the opposite case, and worth calling out because it is easy to
miscategorize. Vim is fully redirectable. `VIMINIT` controls the config
entry point, and from there `'runtimepath'`, `'undodir'`,
`'directory'`, `'backupdir'`, and `viminfofile` move every piece of
state Vim writes. Vim 9.1+ goes further and reads
`$XDG_CONFIG_HOME/vim/vimrc` natively when no `~/.vimrc` or `~/.vim/`
exists. Nothing about Vim forces anything into `$HOME`.

The framework already uses this. The shipped `vimrc` redirects undo,
swap, backup, and `viminfo` into `$XDG_STATE_HOME/vim/` (see
[editors](../tools/editors.md)), so none of Vim's runtime state lands
in your home directory. What remains is `~/.vim/` as the **config
home** — and that is a deliberate choice: `bootstrap.sh` symlinks the
config to `~/.vim/vimrc` because that path works identically on every
Vim version the framework targets, whereas the native
`$XDG_CONFIG_HOME/vim/` path requires Vim 9.1+. It is a compatibility
decision, not a limitation. A user who only runs Vim 9.1+ can move the
config under `$XDG_CONFIG_HOME/vim/` and drop `~/.vim` entirely.

Acknowledging the genuine holdouts (`~/.mozilla`, `~/.pki`,
`~/.claude.json`) honestly is
better than a config that claims a clean `$HOME` it cannot deliver —
but do not pad that list with tools like Vim that are configurable and
that the framework has, in fact, already configured.
