# $ZDOTDIR/conf.d/20-completion.zsh
# ─────────────────────────────────────────────────────────────────────
# Completion system initialization and configuration.
# No plugins required — all settings use zsh built-ins.
# ─────────────────────────────────────────────────────────────────────

# ── Completion function paths ───────────────────────────────────────
# Add additional completion directories before calling compinit.
fpath=(
  "${ZDOTDIR}/completions"            # team/personal custom completions
  "${XDG_DATA_HOME}/zsh/completions"  # completions installed by tools
  "${XDG_DATA_HOME}/mise/completions" # mise-generated completions (if present)
  "${fpath[@]}"
)

# ── Lazy compinit: rebuild cache at most once per 24 hours ──────────
# The zcompdump lives in XDG_CACHE_HOME, not $HOME.
_zcompdump="${XDG_CACHE_HOME}/zsh/zcompdump"
mkdir -p "${XDG_CACHE_HOME}/zsh"

autoload -Uz compinit

# Use extendedglob for the age check (#q glob qualifier).
# N     = null-glob (no error if no match)
# .     = regular files only
# mh+24 = modified more than 24 hours ago
if [[ -n "${_zcompdump}"(#qN.mh+24) ]]; then
  # Cache is stale or absent: full rebuild (security-checked)
  compinit -d "${_zcompdump}"
else
  # Cache is fresh: skip security check for faster startup (-C flag)
  compinit -C -d "${_zcompdump}"
fi
unset _zcompdump

# ── Completion behavior ─────────────────────────────────────────────
zstyle ":completion:*" menu select
zstyle ":completion:*" group-name ""
zstyle ":completion:*:descriptions" format "%F{cyan}%B── %d%b%f"
zstyle ":completion:*:messages"     format "%F{yellow}%B── %d%b%f"
zstyle ":completion:*:warnings"     format "%F{red}No matches: %d"
zstyle ":completion:*:default" list-colors "${(s.:.)LS_COLORS}"

# Partial-word completion: cd /u/lo/b → /usr/local/bin
zstyle ":completion:*" matcher-list \
  "" \
  "m:{a-zA-Z}={A-Za-z}" \
  "r:|[._-]=* r:|=*" \
  "l:|=* r:|=*"

zstyle ":completion:*" special-dirs true
zstyle ":completion:*" verbose true
zstyle ":completion:*:default" list-prompt "%S%M matches%s"
zstyle ":completion:*:processes" command "ps -u $USER -o pid,comm"
zstyle ":completion:*:processes-names" command "ps -u $USER -o comm"
zstyle ":completion:*:kill:*" force-list always
zstyle ":completion:*:*:kill:*:processes" list-colors \
  "=(#b) #([0-9]#)*=0=01;31"

# SSH/SCP/RSYNC: complete from known_hosts
zstyle ":completion:*:(ssh|scp|rsync):*" tag-order \
  "hosts:-host hosts:-domain:domain hosts:-ipaddr:ip-address *"
zstyle ":completion:*:(ssh|scp|rsync):*" group-order \
  hosts-host domains-domain hosts-ipaddr

# Rehash automatically: new executables on PATH are found without manual rehash
zstyle ":completion:*:commands" rehash 1

# ── Completion options (setopt) ─────────────────────────────────────
setopt COMPLETE_IN_WORD
setopt ALWAYS_TO_END
setopt AUTO_MENU
setopt AUTO_LIST
setopt LIST_PACKED
setopt NO_LIST_BEEP
setopt MENU_COMPLETE
