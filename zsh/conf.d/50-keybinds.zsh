# $ZDOTDIR/conf.d/50-keybinds.zsh
# ─────────────────────────────────────────────────────────────────────
# Key bindings. emacs mode (user preference) with prefix-search arrows,
# word navigation, and completion menu navigation.
# ─────────────────────────────────────────────────────────────────────

bindkey -e  # emacs mode

# ── History search ──────────────────────────────────────────────────
# Up/Down arrows search history for entries matching what you've typed
# so far, rather than stepping through all entries.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[A"  up-line-or-beginning-search    # Up
bindkey "^[[B"  down-line-or-beginning-search  # Down
bindkey "^[OA"  up-line-or-beginning-search    # Up (alt terminfo)
bindkey "^[OB"  down-line-or-beginning-search  # Down (alt terminfo)
bindkey "^R" history-incremental-search-backward
bindkey "^S" history-incremental-search-forward

# ── Word navigation ─────────────────────────────────────────────────
bindkey "^[[1;3D" backward-word     # Alt-Left
bindkey "^[[1;3C" forward-word      # Alt-Right
bindkey "^[[1;5D" backward-word     # Ctrl-Left
bindkey "^[[1;5C" forward-word      # Ctrl-Right

# ── Editing ─────────────────────────────────────────────────────────
bindkey "^[[H"  beginning-of-line   # Home
bindkey "^[[F"  end-of-line         # End
bindkey "^[[3~" delete-char         # Delete
bindkey "^U"    backward-kill-line  # Ctrl-U kills to start of line
bindkey "^[^?"  backward-kill-word  # Alt-Backspace

# ── WORDCHARS tweak: make Ctrl-W kill one path segment at a time ────
# Default WORDCHARS treats / as part of a word; this override makes
# Ctrl-W stop at path separators — much better for editing paths.
WORDCHARS="${WORDCHARS//[\/.-]/}"

# ── Useful extras ───────────────────────────────────────────────────
# Alt-. pulls the last argument of the previous command (bash parity)
bindkey "^[." insert-last-word

# Ctrl-X Ctrl-E opens the current line in $EDITOR, then executes it.
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey "^X^E" edit-command-line

# ── Completion menu navigation ──────────────────────────────────────
# The `menuselect` keymap is created lazily when menu completion runs.
# Force it into existence by invoking the keymap creation directly,
# then attach the bindings. Errors are suppressed to handle the rare
# case of a zsh build without zle/menuselect support.
zmodload zsh/complist 2>/dev/null
bindkey -M menuselect "^N" down-line-or-history 2>/dev/null
bindkey -M menuselect "^P" up-line-or-history   2>/dev/null
bindkey -M menuselect "^M" .accept-line         2>/dev/null
bindkey -M menuselect "^G" send-break           2>/dev/null
