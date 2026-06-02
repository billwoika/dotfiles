# POSIX Profile

Zsh does not read `~/.profile` — it is a POSIX/Bourne convention. But
non-zsh subprocesses are common: Homebrew's installer requires
`/bin/bash`, `rustup` writes PATH entries to `~/.profile`, Makefile
recipes execute under `/bin/sh`, Python's
`subprocess.Popen(shell=True)` spawns a POSIX shell, and macOS
LaunchAgents inherit a bare-sh environment. If these processes cannot
find mise, cargo, or uv on their PATH, installations silently write
to the wrong location or fail entirely.

The solution is to maintain a minimal `~/.profile` that mirrors the
same XDG variables and PATH priority order as the zsh configuration,
written in strict POSIX sh syntax. It is a compatibility shim — not a
duplication of the full zsh config. The small overlap in variable
definitions is intentional: these two files serve different process
trees and must not depend on each other.

## The file

```sh
# ~/.profile
# ─────��───────────────────────────────────────────────────────────────
# POSIX sh / bash login profile. Read by non-zsh subprocesses,
# install scripts, cron, LaunchAgents, and anything that spawns
# /bin/sh or /bin/bash as a login shell.
#
# SYNTAX: POSIX sh only. No [[ ]], no arrays, no typeset.
# Must parse under dash, ash, and bash.
# ────────────────────────���────────────────────────────────────────────

# XDG base directories (same values as zsh bootstrap)
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Tool locations
# mise is XDG-native; the paths below are for reference only. No override
# needed unless you want non-standard locations.
export CARGO_HOME="${XDG_DATA_HOME}/cargo"
export RUSTUP_HOME="${XDG_DATA_HOME}/rustup"
export GOPATH="${XDG_DATA_HOME}/go"

# Editor / locale
export EDITOR="vim"
export VISUAL="${EDITOR}"
export LANG="en_US.UTF-8"

# PATH baseline — same priority order as zsh conf.d/10-path.zsh.
# POSIX-portable dedup via case pattern instead of typeset -U.
#
# The loop prepends each iterated directory, so the LAST one iterated
# ends up FIRST in PATH. To match the zsh path priority (mise shims
# wins for runtime version resolution), iterate from lowest priority
# to highest:
for _dir in \
  "${HOME}/.local/bin" \
  "${GOPATH}/bin" \
  "${CARGO_HOME}/bin" \
  "${XDG_DATA_HOME}/mise/shims" \
; do
  if [ -d "$_dir" ]; then
    case ":${PATH}:" in
      *":${_dir}:"*) ;;  # already present
      *) PATH="${_dir}:${PATH}" ;;
    esac
  fi
done
unset _dir
export PATH
```

!!! warning "Do not source zsh files from here"

    It is tempting to source `~/.config/zsh/.zshenv` to avoid
    duplicating XDG definitions. Do not — that file may contain
    zsh-specific syntax (`typeset`, `[[ ]]`, glob qualifiers) that will
    break under `dash` or older `bash`. Accept the small duplication.
    The `.profile` is a compatibility shim, not a DRY exercise.

## When ~/.profile is read

| Shell | Reads `~/.profile`? | Condition |
|-------|---------------------|-----------|
| zsh | Never | Zsh has its own file hierarchy (`.zshenv`, `.zprofile`, `.zshrc`) |
| bash | Fallback | `~/.bash_profile` and `~/.bash_login` must both be absent |
| sh (POSIX) | Yes | Login shells read `~/.profile` unconditionally |
| dash | Yes | Login shells read `~/.profile` (`dash` is `/bin/sh` on Debian/Ubuntu) |
| cron | No | No login shell; use env vars in crontab or wrapper scripts |
| LaunchAgent (macOS) | No | Inherits environment from `launchd`; use `EnvironmentVariables` key |
| systemd user service | No | Does not spawn a login shell; use `Environment=` directives in the unit file or `~/.config/environment.d/*.conf` |
| ssh `ForceCommand` | Varies | Depends on whether a login shell is spawned |

Critically, an interactive login bash reads the first of
`~/.bash_profile`, `~/.bash_login`, `~/.profile` that exists — so it
reads `~/.profile` **only when neither `~/.bash_profile` nor
`~/.bash_login` exists**. If you have a `~/.bash_profile` (or
`~/.bash_login`) from a previous bash-era configuration, bash reads
that and ignores `~/.profile` entirely.
The cleanest migration path is to delete `~/.bash_profile` and
`~/.bash_login` so bash falls through to `~/.profile` consistently.
You are not a bash user — these files are cruft.

## The test suite

The framework includes a 30-test POSIX test suite that validates the
profile's behavior: XDG variable defaults, tool location paths, PATH
construction priority, idempotency (sourcing twice produces the same
PATH), non-existent directory skipping, and variable cleanup. The test suite validates POSIX compliance, XDG defaults, PATH
construction, idempotency, and variable cleanup.

```sh
# Run the suite
sh sh/tests/profile_test.sh

# Multi-shell sweep (dash, bash --posix, busybox)
sh sh/tests/profile_test.sh --multi
```
