# $ZDOTDIR/.zshenv
# ─────────────────────────────────────────────────────────────────────
# Sourced for every zsh invocation — interactive, non-interactive,
# login, and subshell. Keep fast and side-effect-free.
# ─────────────────────────────────────────────────────────────────────

# XDG base directories (re-export for subshells that inherit a clean env)
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:=$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:=$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:=$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:=$HOME/.cache}"

# ── Tool XDG redirects ──────────────────────────────────────────────
# Set here only; do not also set in tool config files.
#
# mise is XDG-native — documented here for reference, no override needed:
#   config:  ${XDG_CONFIG_HOME}/mise/config.toml
#   data:    ${XDG_DATA_HOME}/mise
#   shims:   ${XDG_DATA_HOME}/mise/shims
#   state:   ${XDG_STATE_HOME}/mise
#   cache:   ${XDG_CACHE_HOME}/mise

# Rust / cargo
export CARGO_HOME="${XDG_DATA_HOME}/cargo"
export RUSTUP_HOME="${XDG_DATA_HOME}/rustup"

# Go
export GOPATH="${XDG_DATA_HOME}/go"

# npm (fallback for legacy Node tooling; prefer bun)
export NPM_CONFIG_USERCONFIG="${XDG_CONFIG_HOME}/npm/npmrc"
export NPM_CONFIG_CACHE="${XDG_CACHE_HOME}/npm"

# less
export LESSHISTFILE="${XDG_STATE_HOME}/less/history"
export LESSKEY="${XDG_CONFIG_HOME}/less/lesskey"

# wget
export WGETRC="${XDG_CONFIG_HOME}/wget/wgetrc"

# GnuPG
export GNUPGHOME="${XDG_DATA_HOME}/gnupg"

# Docker (CLI config only; daemon config is system-scoped)
export DOCKER_CONFIG="${XDG_CONFIG_HOME}/docker"

# ── Editor defaults ─────────────────────────────────────────────────
export EDITOR="vim"
export VISUAL="${EDITOR}"
export PAGER="less"
export LESS="-R --quit-if-one-screen --no-init"

# ── Locale ──────────────────────────────────────────────────────────
# Explicit UTF-8 locale prevents encoding issues in scripts and pipes.
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
