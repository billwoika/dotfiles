# $ZDOTDIR/conf.d/30-history.zsh
# ─────────────────────────────────────────────────────────────────────
# History — XDG-compliant location, large size, aggressive dedup,
# immediate cross-session sharing.
# ─────────────────────────────────────────────────────────────────────

mkdir -p "${XDG_STATE_HOME}/zsh"
HISTFILE="${XDG_STATE_HOME}/zsh/history"

# Large history: acts as a personal command corpus.
HISTSIZE=100000
SAVEHIST=100000

# ── History options ─────────────────────────────────────────────────
setopt EXTENDED_HISTORY       # Save timestamp and duration with each command
setopt SHARE_HISTORY          # Share history across all live sessions immediately
setopt HIST_EXPIRE_DUPS_FIRST # Trim duplicate entries before unique ones when full
setopt HIST_IGNORE_DUPS       # Do not record an event identical to the prior event
setopt HIST_IGNORE_ALL_DUPS   # Remove older duplicate if a new duplicate arrives
setopt HIST_FIND_NO_DUPS      # Do not display duplicates during history search
setopt HIST_IGNORE_SPACE      # Commands prefixed with space are not recorded
setopt HIST_SAVE_NO_DUPS      # Do not write duplicates to the history file
setopt HIST_REDUCE_BLANKS     # Strip superfluous whitespace before saving
setopt HIST_VERIFY            # Show expanded history substitution before executing

# Note: INC_APPEND_HISTORY and SHARE_HISTORY are mutually exclusive.
# SHARE_HISTORY subsumes INC_APPEND_HISTORY — do not set both.
