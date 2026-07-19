# ~/.profile
# ─────────────────────────────────────────────────────────────────────
# POSIX sh / bash login profile. Read by non-zsh subprocesses,
# install scripts, cron, LaunchAgents, and anything that spawns
# /bin/sh or /bin/bash as a login shell.
#
# SYNTAX: POSIX sh only. No [[ ]], no arrays, no typeset.
# Must parse under dash, ash, and bash.
# ─────────────────────────────────────────────────────────────────────

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

# SSH agent socket (Linux only)
# On GNOME 46+ desktops, gcr-ssh-agent (not gnome-keyring) provides the
# SSH agent and exports SSH_AUTH_SOCK itself (at $XDG_RUNTIME_DIR/gcr/ssh).
# We only fill it in when unset — e.g. non-GNOME setups using a custom
# systemd ssh-agent.service, whose socket lives at the path below. The
# -z guard means we never override a value the desktop already set.
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  for _ssh_sock in \
    "${XDG_RUNTIME_DIR:-}/gcr/ssh" \
    "${XDG_RUNTIME_DIR:-}/ssh-agent.socket" \
  ; do
    if [ -S "$_ssh_sock" ]; then
      export SSH_AUTH_SOCK="$_ssh_sock"
      break
    fi
  done
  unset _ssh_sock
fi

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

# Only source cargo's env shim if cargo was actually installed (e.g. via
# rustup) — this file does not exist by default, and the framework does
# not require Rust.
if [ -f "${HOME}/.cargo/env" ]; then
  . "${HOME}/.cargo/env"
fi
