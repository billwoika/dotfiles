# $ZDOTDIR/conf.d/80-functions.zsh
# ─────────────────────────────────────────────────────────────────────
# Core utility functions. Domain-specific functions (git extensions,
# csvsplit, aws-ssh, tree-trunk, check-cert, etc.) live in fragments 61-68.
# ─────────────────────────────────────────────────────────────────────

# ── mkcd: create a directory and cd into it ─────────────────────────
mkcd() {
  [[ $# -eq 1 ]] || { echo "usage: mkcd <dir>" >&2; return 1; }
  mkdir -p "$1" && cd "$1"
}

# ── up: cd up N directories ─────────────────────────────────────────
up() {
  local n="${1:-1}"
  local target="$PWD"
  for ((i = 0; i < n; i++)); do target="${target%/*}"; done
  [[ -n "$target" ]] && cd "$target" || cd /
}

# ── path_add: safely add a directory to PATH at runtime ─────────────
path_add() {
  [[ -d "$1" && ":$PATH:" != *":$1:"* ]] && export PATH="$1:$PATH"
}

# ── mise_pin: convenience wrapper for pinning a tool to the project ──
mise_pin() {
  [[ $# -eq 2 ]] || { echo "usage: mise_pin <tool> <version>" >&2; return 1; }
  mise use "$1@$2"
  echo "Pinned $1 $2 in $(pwd)/mise.toml"
}

# ── mise_tasks: list tasks defined in the current project ───────────
mise_tasks() {
  mise tasks ls --hidden
}

# ── envdiff: show env vars added/changed by mise.toml + .envrc ──────
envdiff() {
  local before
  before=$(env | sort)
  mise exec -- env | sort > /tmp/_envdiff_after
  diff <(echo "$before") /tmp/_envdiff_after
  rm -f /tmp/_envdiff_after
}

# ── extract: unpack any common archive format ───────────────────────
extract() {
  if [[ -f "$1" ]]; then
    case "$1" in
      *.tar.bz2) tar xjf "$1"  ;;
      *.tar.gz)  tar xzf "$1"  ;;
      *.tar.xz)  tar xJf "$1"  ;;
      *.tar.zst) tar --zstd -xf "$1" ;;
      *.bz2)     bunzip2 "$1"  ;;
      *.gz)      gunzip "$1"   ;;
      *.tar)     tar xf "$1"   ;;
      *.zip)     unzip "$1"    ;;
      *.7z)      7z x "$1"     ;;
      *)         echo "Unknown archive: $1" >&2; return 1 ;;
    esac
  else
    echo "File not found: $1" >&2; return 1
  fi
}

# ── port_kill: kill the process listening on a given port ───────────
port_kill() {
  [[ $# -eq 1 ]] || { echo "usage: port_kill <port>" >&2; return 1; }
  local pid
  pid=$(lsof -ti tcp:"$1" 2>/dev/null)
  if [[ -n "$pid" ]]; then
    kill -9 "$pid" && echo "Killed PID $pid on port $1"
  else
    echo "No process on port $1" >&2
  fi
}

# ── timeshell: benchmark zsh startup time ───────────────────────────
timeshell() {
  local n="${1:-10}"
  for ((i = 0; i < n; i++)); do /usr/bin/time zsh -lic exit; done 2>&1 |
    awk '/real/ { sum += $2; count++ } END {
      printf "avg: %.3fs over %d runs\n", sum/count, count
    }'
}

# ── keychain_get: cross-platform secret lookup ──────────────────────
# macOS Keychain or Linux Secret Service, as appropriate.
keychain_get() {
  [[ $# -eq 1 ]] || { echo "usage: keychain_get <service-name>" >&2; return 1; }
  if [[ "$(uname)" == "Darwin" ]]; then
    security find-generic-password -a "$USER" -s "$1" -w 2>/dev/null
  else
    secret-tool lookup service "$1" account "$USER" 2>/dev/null
  fi
}
