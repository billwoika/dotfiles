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
  tree -L ${2:-3} ${1:-.} | awk -v cap=4 '
    # Collapse runs of same-prefix lines to the first `cap`, then a
    # "... N more ..." summary. Decisions use the CURRENT group, and the
    # summary is flushed for the group that just ENDED (its own prefix).
    function flush(p, c) {
      if (c > cap) print p "... " (c - cap) " more ..."
    }
    BEGIN { last_prefix = ""; count = 0; have_group = 0 }
    {
      prefix = $0
      sub(/[^│├└─]+$/, "", prefix)

      if (have_group && prefix != last_prefix) {
        flush(last_prefix, count)   # summarize the group that just ended
        count = 0
      }

      count++
      if (count <= cap) print       # print first `cap` of THIS group

      last_prefix = prefix
      have_group = 1
    }
    END { flush(last_prefix, count) }  # summarize the final group
  '
}

# ── Quick HTTP server for the current directory ─────────────────────
alias serve='python3 -m http.server 8000'
