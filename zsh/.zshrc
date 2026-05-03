# $ZDOTDIR/.zshrc
# ─────────────────────────────────────────────────────────────────────
# Interactive shell configuration. Sources conf.d/ fragments in order.
# Add new behavior by creating a new numbered fragment — do not add
# logic directly to this file.
# ─────────────────────────────────────────────────────────────────────

# Guard: do nothing for non-interactive shells that incorrectly source .zshrc.
[[ -o interactive ]] || return

# Source all conf.d fragments in deterministic lexicographic order.
# The N glob qualifier suppresses errors if the directory is empty.
for _zsh_conf in "${ZDOTDIR}/conf.d"/*.zsh(N); do
  source "${_zsh_conf}"
done
unset _zsh_conf

# Optional machine-local overrides — not tracked in dotfiles.
# Create these files to add per-machine customization without forking
# the shared conf.d/ fragments.
[[ -f "${ZDOTDIR}/aliases.local.zsh" ]] && source "${ZDOTDIR}/aliases.local.zsh"
[[ -f "${ZDOTDIR}/env.local.zsh"     ]] && source "${ZDOTDIR}/env.local.zsh"
