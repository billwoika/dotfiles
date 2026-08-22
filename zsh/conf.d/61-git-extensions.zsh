# $ZDOTDIR/conf.d/61-git-extensions.zsh
# ─────────────────────────────────────────────────────────────────────
# Git rebase / checkout / commit flow beyond the core aliases in 60.
# ─────────────────────────────────────────────────────────────────────

# Rebase against a remote branch (fetches first for safety)
git-rebase-remote() {
  [[ $# -eq 1 ]] || { echo "usage: git-rebase-remote <branch>" >&2; return 1; }
  git fetch origin "$1" && git rebase "origin/$1"
}
alias grm='git-rebase-remote main'
alias grs='git-rebase-remote staging'

# Interactive rebase on the last N commits
gir() {
  [[ $# -eq 1 ]] || { echo "usage: gir <N>" >&2; return 1; }
  git rebase -i "HEAD~$1"
}
alias gra='git rebase --abort'
alias grc='git rebase --continue'

# Commit with a message (positional, quoted automatically)
gcm() {
  [[ $# -ge 1 ]] || { echo "usage: gcm <message>" >&2; return 1; }
  git commit -m "$*"
}

# Checkout a new branch
gcrb() {
  [[ $# -eq 1 ]] || { echo "usage: gcrb <branch-name>" >&2; return 1; }
  git checkout -b "$1"
}

# Switch to an existing branch (prints current branch on success)
gswitch() {
  [[ $# -eq 1 ]] || { echo "usage: gswitch <branch>" >&2; return 1; }
  git checkout "$1" && git rev-parse --abbrev-ref HEAD
}

# Fetch + pull in one shot (useful with tracking-branch rebase)
alias gfp='git fetch --prune && git pull --rebase'
alias gf='git fetch'

# Show active git profile (which includeIf matched — docs/git/configuration.md)
alias gwhoami='git config --show-origin user.email'

# Safe force-push (docs/git/configuration.md)
alias gpushf='git push --force-with-lease --force-if-includes'

# Clean merged local branches, excluding main/master/develop
gclean() {
  git branch --merged | \
    grep -vE '^\*|^\s*(main|master|develop)\s*$' | \
    xargs -r -n 1 git branch -d
    # -r (no-run-if-empty): on GNU xargs, without it an empty branch
    # list would invoke `git branch -d` with no args. No-op on BSD.
}

# Find commits by message across all branches
gfind() {
  [[ $# -ge 1 ]] || { echo "usage: gfind <pattern>" >&2; return 1; }
  git log --all --oneline --grep="$*"
}
