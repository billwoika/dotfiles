# $ZDOTDIR/conf.d/67-devloop.zsh
# ─────────────────────────────────────────────────────────────────────
# Development loop helpers — tmux shortcuts, smart tree, ad-hoc HTTP.
# ─────────────────────────────────────────────────────────────────────

# ── tmux ────────────────────────────────────────────────────────────
# Attach or create a `main` session (Section 19.8.1)
alias t='tmux new-session -A -s main'
alias td='tmux detach'
alias tls='tmux list-sessions'

# Named session by argument
tm() {
  [[ $# -eq 1 ]] || { echo "usage: tm <session-name>" >&2; return 1; }
  tmux new-session -A -s "$1"
}

# ── tree-trunk: tree output collapsed at N files per directory level ──
# Usage: tree-trunk [dir] [depth]  (defaults: . 3)
tree-trunk() {
  tree -L ${2:-3} ${1:-.} | awk '
    BEGIN { last_prefix = ""; count = 1 }
    {
      # Extract indentation prefix (the tree-drawing characters)
      prefix = $0
      sub(/[^│├└─]+$/, "", prefix)

      if (count < 5) { print }

      if (prefix == last_prefix) {
        count++
      } else {
        if (count > 5) { print prefix " " count " more files..." }
        count = 1
      }
      last_prefix = prefix
    }'
}

# ── Quick HTTP server for the current directory ─────────────────────
alias serve='python3 -m http.server 8000'
