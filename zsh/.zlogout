# $ZDOTDIR/.zlogout
# ─────────────────────────────────────────────────────────────────────
# Sourced when a login shell exits. Optional; keep minimal.
# Useful for clearing sensitive state that shouldn't persist across sessions.
# ─────────────────────────────────────────────────────────────────────

# Example: clear terminal scrollback on logout for shared machines.
# Uncomment on multi-user systems where scrollback residue matters.
# clear
# [[ -n "$TMUX" ]] || tput reset 2>/dev/null
