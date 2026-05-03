# $ZDOTDIR/.zprofile
# ─────────────────────────────────────────────────────────────────────
# Login-shell PATH construction. Sourced once per login session.
# PATH is built here; interactive aliases/completions are in .zshrc.
# ─────────────────────────────────────────────────────────────────────

# Source the deterministic PATH builder.
# The builder lives in conf.d/ and is also sourced by non-login interactive
# shells via .zshrc, making PATH consistent in both contexts.
[[ -f "${ZDOTDIR}/conf.d/10-path.zsh" ]] && source "${ZDOTDIR}/conf.d/10-path.zsh"
