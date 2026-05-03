# $ZDOTDIR/conf.d/25-tool-cache.zsh
# ─────────────────────────────────────────────────────────────────────
# Version-hashed cache for deterministic shell-init output.
# Replaces eval "$(tool init zsh)" with cached file sources.
# Cache is auto-invalidated when a tool's --version output changes.
#
# See framework doc Appendix C for the full strategy.
# ─────────────────────────────────────────────────────────────────────

# ── Tool registry ───────────────────────────────────────────────────
# Map of cache-entry-key → command that emits zsh code.
# Multiple entries can point to the same binary (e.g., a tool's init
# is separate from its completion output).
typeset -gA _ZSHTOOL_CACHE_ENTRIES=(
  starship       "starship init zsh"
  zoxide         "zoxide init zsh --cmd cd"
  fzf            "fzf --zsh"
  mise-comp      "mise completion zsh"
  uv-comp        "uv generate-shell-completion zsh"
  uvx-comp       "uvx --generate-shell-completion zsh"
  bun-comp       "bun completions"
  gh-comp        "gh completion -s zsh"
  kubectl-comp   "kubectl completion zsh"
  rv-comp        "rv completions zsh"
  docker-comp    "docker completion zsh"
)

# Map of cache-entry-key → binary to check on PATH.
typeset -gA _ZSHTOOL_CACHE_BINARY=(
  starship      starship
  zoxide        zoxide
  fzf           fzf
  mise-comp     mise
  uv-comp       uv
  uvx-comp      uv
  bun-comp      bun
  gh-comp       gh
  kubectl-comp  kubectl
  rv-comp       rv
  docker-comp   docker
)

# ── Cache directory ─────────────────────────────────────────────────
_zshtool_cache_dir="${XDG_CACHE_HOME}/zsh/tool-injections"
[[ -d "$_zshtool_cache_dir" ]] || mkdir -p "$_zshtool_cache_dir"

# ── Loader ──────────────────────────────────────────────────────────
_zshtool_cache_load() {
  local key="$1" cmd="$2" bin="$3"
  command -v "$bin" >/dev/null 2>&1 || return 0

  # Pick a hasher; fall back to direct eval if neither is present.
  local hasher
  if command -v shasum >/dev/null 2>&1; then
    hasher="shasum"
  elif command -v sha1sum >/dev/null 2>&1; then
    hasher="sha1sum"
  else
    eval "$cmd" 2>/dev/null
    return 0
  fi

  local ver
  ver=$("$bin" --version 2>/dev/null | "$hasher" | cut -c1-12)
  [[ -z "$ver" ]] && { eval "$cmd" 2>/dev/null; return 0; }

  local cache_file="${_zshtool_cache_dir}/${key}.${ver}.zsh"
  if [[ ! -f "$cache_file" ]]; then
    # Stale or missing: clean older versions, regenerate.
    # The (N) glob qualifier suppresses errors on no match.
    local -a old=("${_zshtool_cache_dir}/${key}".*.zsh(N))
    [[ ${#old} -gt 0 ]] && rm -f "${old[@]}"
    eval "$cmd" > "$cache_file" 2>/dev/null
  fi
  source "$cache_file"
}

# ── Editor / terminal integration loader ────────────────────────────
# Static integration scripts shipped by host programs (iTerm2, WezTerm).
# Hash the script contents directly rather than a --version invocation.
_zshtool_editor_load() {
  local label="$1" gate="$2" script="$3"
  [[ -n "$gate" && -f "$script" ]] || return 0

  local hasher
  if command -v shasum >/dev/null 2>&1; then
    hasher="shasum"
  elif command -v sha1sum >/dev/null 2>&1; then
    hasher="sha1sum"
  else
    source "$script"
    return 0
  fi

  local ver
  ver=$("$hasher" "$script" 2>/dev/null | cut -c1-12)
  [[ -z "$ver" ]] && { source "$script"; return 0; }

  local cache_file="${_zshtool_cache_dir}/${label}.${ver}.zsh"
  if [[ ! -f "$cache_file" ]]; then
    local -a old=("${_zshtool_cache_dir}/${label}".*.zsh(N))
    [[ ${#old} -gt 0 ]] && rm -f "${old[@]}"
    cp "$script" "$cache_file"
  fi
  source "$cache_file"
}

# ── Run the registry ────────────────────────────────────────────────
for _zt_key in "${(@k)_ZSHTOOL_CACHE_ENTRIES}"; do
  _zshtool_cache_load \
    "$_zt_key" \
    "${_ZSHTOOL_CACHE_ENTRIES[$_zt_key]}" \
    "${_ZSHTOOL_CACHE_BINARY[$_zt_key]}"
done
unset _zt_key

# ── Editor / terminal integrations ──────────────────────────────────
# iTerm2 — only inside iTerm2 (LC_TERMINAL is set by the terminal).
_zshtool_editor_load "iterm2" \
  "${LC_TERMINAL:#iTerm2}" \
  "${XDG_CONFIG_HOME}/iterm2/shell_integration.zsh"

# WezTerm — emits OSC 7/133 helpers; useful in shells running under WezTerm.
_zshtool_editor_load "wezterm" \
  "${TERM_PROGRAM:#WezTerm}" \
  "${XDG_CONFIG_HOME}/wezterm/wezterm.sh"

# VS Code / Cursor: integration is auto-injected via VSCODE_INJECTION=1
# when the IDE setting is enabled. Detect it for downstream conditionals,
# but don't try to install integration ourselves.
[[ -n "${VSCODE_INJECTION}" ]] && export _IS_VSCODE_TERMINAL=1

# ── Public commands ─────────────────────────────────────────────────

# zshtool-cache-rebuild [<key>...]
# With no args: clears all cached injections; next shell rebuilds.
# With keys: clears only those entries.
zshtool-cache-rebuild() {
  if [[ $# -eq 0 ]]; then
    local -a all=("${_zshtool_cache_dir}"/*.zsh(N))
    [[ ${#all} -gt 0 ]] && rm -f "${all[@]}"
    echo "Cleared all cached injections in ${_zshtool_cache_dir}"
    echo "Next shell start will regenerate."
  else
    for key; do
      local -a old=("${_zshtool_cache_dir}/${key}".*.zsh(N))
      [[ ${#old} -gt 0 ]] && rm -f "${old[@]}"
      echo "Cleared cache for: $key"
    done
  fi
}

# zshtool-cache-status
# Print current cache state for debugging.
zshtool-cache-status() {
  echo "Cache dir: ${_zshtool_cache_dir}"
  echo ""
  if [[ -d "${_zshtool_cache_dir}" ]]; then
    ls -lh "${_zshtool_cache_dir}" 2>/dev/null
  else
    echo "(no cache directory)"
  fi
  echo ""
  echo "Registered tools:"
  for key in "${(@k)_ZSHTOOL_CACHE_ENTRIES}"; do
    local bin="${_ZSHTOOL_CACHE_BINARY[$key]}"
    if command -v "$bin" >/dev/null 2>&1; then
      printf "  [present]  %-15s -> %s\n" "$key" "$bin"
    else
      printf "  [skipped]  %-15s -> %s (not on PATH)\n" "$key" "$bin"
    fi
  done
}
