# $ZDOTDIR/conf.d/70-tools.zsh
# ─────────────────────────────────────────────────────────────────────
# Tier 1 only: live activation hooks that must inspect runtime state
# at every prompt or every cd.
#
# Deterministic init/completion output (fzf, gh, kubectl, mise/uv/bun
# completions, iTerm2 shell integration) is handled by
# 25-tool-cache.zsh — see framework doc Appendix C.
# ─────────────────────────────────────────────────────────────────────

# ── mise ────────────────────────────────────────────────────────────
# mise activate installs a zsh precmd hook that rewrites PATH on every cd.
# This is faster than shims for interactive use. Shims (in conf.d/10-path.zsh)
# remain available for subprocesses that inherit a clean env.
if command -v mise &>/dev/null; then
  eval "$(mise activate zsh --quiet 2>/dev/null)"
fi

# ── rv (Ruby) ───────────────────────────────────────────────────────
# rv has its own shell integration that reads .ruby-version on cd.
if command -v rv &>/dev/null; then
  eval "$(rv shell init zsh)"
fi

# ── direnv ──────────────────────────────────────────────────────────
# direnv is layered ON TOP of mise in this stack. Most env var management
# lives in mise.toml's [env] block. direnv is reserved for complex secret
# loading (1Password CLI, age-encrypted files, vaulted credentials).
if command -v direnv &>/dev/null; then
  eval "$(direnv hook zsh)"
fi

# ── SSH ControlMaster directory ─────────────────────────────────────
# ~/.ssh/config references ~/.ssh/control/%C for connection multiplexing.
# The directory is not auto-created; make sure it exists with mode 0700.
[[ -d "${HOME}/.ssh/control" ]] || \
  { mkdir -p "${HOME}/.ssh/control" && chmod 700 "${HOME}/.ssh/control"; }

# ── fzf default options ─────────────────────────────────────────────
# Actual `fzf --zsh` init is handled by 25-tool-cache.zsh.
# These environment variables tune the fzf widgets that init defines.
if command -v fzf &>/dev/null; then
  if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
    export FZF_CTRL_T_COMMAND="${FZF_DEFAULT_COMMAND}"
    export FZF_ALT_C_COMMAND="fd --type d --hidden --follow --exclude .git"
  fi
  export FZF_DEFAULT_OPTS="\
    --height 40% --border --info=inline \
    --color=fg:#28251D,bg:#F7F6F2,hl:#01696F \
    --color=fg+:#28251D,bg+:#EDF2F7,hl+:#0C4E54 \
    --color=info:#7A7974,prompt:#01696F,pointer:#0C4E54 \
    --color=marker:#437A22,spinner:#01696F,header:#7A7974"
fi
