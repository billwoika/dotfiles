#!/bin/sh
# sh/tests/profile_test.sh
# ─────────────────────────────────────────────────────────────────────
# POSIX sh test suite for the dotfiles ~/.profile.
#
# Validates that ~/.profile:
#   1. Parses under POSIX sh (no bashisms)
#   2. Sets XDG variables correctly with proper defaults
#   3. Sets tool location variables (CARGO_HOME, GOPATH)
#   4. Sets editor and locale defaults
#   5. Constructs PATH in the correct priority order
#   6. Is idempotent (sourcing twice produces the same PATH)
#   7. Skips non-existent directories
#   8. Cleans up private variables
#
# Emits TAP (Test Anything Protocol) output for harness compatibility.
#
# Usage:
#   dash    sh/tests/profile_test.sh
#   bash    sh/tests/profile_test.sh --posix
#   sh      sh/tests/profile_test.sh --multi     # sweep dash/bash/busybox
# ─────────────────────────────────────────────────────────────────────

set -u

# ── Config ──────────────────────────────────────────────────────────
PROFILE="$(cd "$(dirname "$0")/../.." && pwd)/profile"

test_count=0
pass_count=0
fail_count=0

# ── TAP helpers ─────────────────────────────────────────────────────
ok() {
  test_count=$((test_count + 1))
  pass_count=$((pass_count + 1))
  printf "ok %d - %s\n" "$test_count" "$1"
}
not_ok() {
  test_count=$((test_count + 1))
  fail_count=$((fail_count + 1))
  printf "not ok %d - %s\n" "$test_count" "$1"
  [ -n "${2:-}" ] && printf "# %s\n" "$2"
}
assert() {
  # assert <description> <condition-command...>
  desc=$1; shift
  if "$@"; then ok "$desc"; else not_ok "$desc"; fi
}
assert_eq() {
  # assert_eq <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    not_ok "$1" "expected [$2], got [$3]"
  fi
}
assert_contains() {
  # assert_contains <description> <haystack> <needle>
  case "$2" in
    *"$3"*) ok "$1" ;;
    *)      not_ok "$1" "[$2] does not contain [$3]" ;;
  esac
}

# ── Multi-shell sweep ───────────────────────────────────────────────
if [ "${1:-}" = "--multi" ]; then
  overall=0
  for sh_cmd in "dash" "bash --posix" "busybox sh"; do
    bin="$(printf '%s\n' "$sh_cmd" | awk '{print $1}')"
    if command -v "$bin" >/dev/null 2>&1; then
      echo "══ Running under: $sh_cmd ══"
      if $sh_cmd "$0"; then
        echo "══ $sh_cmd: PASS ══"
      else
        echo "══ $sh_cmd: FAIL ══"
        overall=1
      fi
      echo
    else
      echo "── Skipping $sh_cmd (not installed) ──"
    fi
  done
  exit "$overall"
fi

# ── Sanity: profile file exists ─────────────────────────────────────
if [ ! -f "$PROFILE" ]; then
  echo "Bail out! Profile not found at $PROFILE"
  exit 1
fi

printf "# Testing: %s\n" "$PROFILE"
printf "# Shell:   %s (pid %d)\n" "$(basename "$0")" "$$"

# ─────────────────────────────────────────────────────────────────────
# GROUP 1 — Syntax validation
# ─────────────────────────────────────────────────────────────────────
assert "profile sources without error" sh -c ". $PROFILE"
# Strip comment lines before checking for bashisms — the profile contains
# POSIX-syntax comments that mention forbidden constructs by name.
if ! grep -vE '^\s*#' "$PROFILE" | grep -qE '(\[\[|typeset|local +[A-Za-z_]+=)'; then
  ok "no bashisms in profile"
else
  not_ok "no bashisms in profile" "found [[/typeset/local in non-comment lines"
fi
assert "profile has no shebang" sh -c "! head -1 $PROFILE | grep -q '^#!'"

# ─────────────────────────────────────────────────────────────────────
# GROUP 2 — XDG variable defaults
# ─────────────────────────────────────────────────────────────────────
HOME_SAVE=$HOME
HOME=/tmp/_prof_test_home
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME

. "$PROFILE"
assert_eq "XDG_CONFIG_HOME defaults to HOME/.config" \
  "$HOME/.config" "$XDG_CONFIG_HOME"
assert_eq "XDG_DATA_HOME defaults to HOME/.local/share" \
  "$HOME/.local/share" "$XDG_DATA_HOME"
assert_eq "XDG_STATE_HOME defaults to HOME/.local/state" \
  "$HOME/.local/state" "$XDG_STATE_HOME"
assert_eq "XDG_CACHE_HOME defaults to HOME/.cache" \
  "$HOME/.cache" "$XDG_CACHE_HOME"

# Preserve pre-set values
export XDG_CONFIG_HOME=/custom/config
. "$PROFILE"
assert_eq "XDG_CONFIG_HOME preserved if already set" \
  "/custom/config" "$XDG_CONFIG_HOME"
unset XDG_CONFIG_HOME

# ─────────────────────────────────────────────────────────────────────
# GROUP 3 — Tool location variables
# ─────────────────────────────────────────────────────────────────────
unset CARGO_HOME RUSTUP_HOME GOPATH
. "$PROFILE"
assert_eq "CARGO_HOME derives from XDG_DATA_HOME" \
  "$XDG_DATA_HOME/cargo" "$CARGO_HOME"
assert_eq "RUSTUP_HOME derives from XDG_DATA_HOME" \
  "$XDG_DATA_HOME/rustup" "$RUSTUP_HOME"
assert_eq "GOPATH derives from XDG_DATA_HOME" \
  "$XDG_DATA_HOME/go" "$GOPATH"
if ! grep -q 'MISE_HOME\|MISE_DATA_DIR' "$PROFILE"; then
  ok "no MISE_HOME override (mise is XDG-native)"
else
  not_ok "no MISE_HOME override (mise is XDG-native)"
fi

# ─────────────────────────────────────────────────────────────────────
# GROUP 4 — Editor and locale
# ─────────────────────────────────────────────────────────────────────
. "$PROFILE"
assert_eq "EDITOR is set"  "vim" "$EDITOR"
assert_eq "VISUAL equals EDITOR" "$EDITOR" "$VISUAL"
assert_contains "LANG is UTF-8" "$LANG" "UTF-8"

# ─────────────────────────────────────────────────────────────────────
# GROUP 5 — PATH construction (real directories required)
# ─────────────────────────────────────────────────────────────────────
# Create the directories the profile expects, so PATH entries stick.
mkdir -p "$XDG_DATA_HOME/mise/shims" \
         "$CARGO_HOME/bin" \
         "$GOPATH/bin" \
         "$HOME/.local/bin"

PATH=/usr/bin:/bin
. "$PROFILE"

assert_contains "mise shims dir in PATH" "$PATH" "$XDG_DATA_HOME/mise/shims"
assert_contains "CARGO_HOME/bin in PATH"  "$PATH" "$CARGO_HOME/bin"
assert_contains "GOPATH/bin in PATH"      "$PATH" "$GOPATH/bin"
assert_contains "HOME/.local/bin in PATH" "$PATH" "$HOME/.local/bin"
assert_contains "original PATH preserved" "$PATH" "/usr/bin"

# Priority: mise shims must come before CARGO_HOME/bin
case "$PATH" in
  *"$XDG_DATA_HOME/mise/shims"*"$CARGO_HOME/bin"*) \
    ok "mise shims appears before CARGO_HOME/bin" ;;
  *) not_ok "mise shims appears before CARGO_HOME/bin" "PATH: $PATH" ;;
esac

# ─────────────────────────────────────────────────────────────────────
# GROUP 6 — Idempotency
# ─────────────────────────────────────────────────────────────────────
PATH=/usr/bin:/bin
. "$PROFILE"
PATH_FIRST="$PATH"
. "$PROFILE"
PATH_SECOND="$PATH"
. "$PROFILE"
PATH_THIRD="$PATH"

assert_eq "sourcing twice produces identical PATH"  "$PATH_FIRST" "$PATH_SECOND"
assert_eq "sourcing thrice produces identical PATH" "$PATH_FIRST" "$PATH_THIRD"

# ─────────────────────────────────────────────────────────────────────
# GROUP 7 — Non-existent directories skipped
# ─────────────────────────────────────────────────────────────────────
HOME=/tmp/_prof_test_empty_home
rm -rf "$HOME"
mkdir -p "$HOME"
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
unset CARGO_HOME RUSTUP_HOME GOPATH

PATH=/usr/bin:/bin
. "$PROFILE"

case "$PATH" in
  *"$HOME/.local/bin"*) not_ok "missing HOME/.local/bin NOT in PATH" ;;
  *) ok "missing HOME/.local/bin NOT in PATH" ;;
esac
case "$PATH" in
  *"$CARGO_HOME/bin"*) not_ok "missing CARGO_HOME/bin NOT in PATH" ;;
  *) ok "missing CARGO_HOME/bin NOT in PATH" ;;
esac

# ─────────────────────────────────────────────────────────────────────
# GROUP 8 — Variable cleanup
# ─────────────────────────────────────────────────────────────────────
. "$PROFILE"
if [ -z "${_dir:-}" ]; then
  ok "_dir loop variable is unset after sourcing"
else
  not_ok "_dir loop variable is unset after sourcing" "_dir = [$_dir]"
fi

# PATH must be exported
if env | grep -q '^PATH='; then
  ok "PATH is exported"
else
  not_ok "PATH is exported"
fi

# ─────────────────────────────────────────────────────────────────────
# GROUP 9 — POSIX portability markers
# ─────────────────────────────────────────────────────────────────────
assert "printf works"            sh -c 'printf "%s" test >/dev/null'
assert "command -v works"        sh -c 'command -v sh >/dev/null'
assert "parameter expansion :-"  sh -c ': "${UNSET_VAR:-default}"'

# ── Restore HOME ────────────────────────────────────────────────────
HOME=$HOME_SAVE
rm -rf /tmp/_prof_test_home /tmp/_prof_test_empty_home 2>/dev/null || true

# ── Summary ─────────────────────────────────────────────────────────
printf "1..%d\n" "$test_count"
if [ "$fail_count" -eq 0 ]; then
  printf "# All %d tests passed\n" "$test_count"
  exit 0
else
  printf "# %d of %d tests failed\n" "$fail_count" "$test_count"
  exit 1
fi
