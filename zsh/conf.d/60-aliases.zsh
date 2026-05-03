# $ZDOTDIR/conf.d/60-aliases.zsh
# ─────────────────────────────────────────────────────────────────────
# Core cross-cutting aliases. Domain-specific aliases (git extensions,
# ruby, python, js, aws, etc.) live in sibling fragments 61-68.
# ─────────────────────────────────────────────────────────────────────

# ── Filesystem navigation ───────────────────────────────────────────
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias -- -="cd -"

# ── Listing (ls flavor detection) ───────────────────────────────────
if ls --color=auto /dev/null &>/dev/null; then
  alias ls="ls --color=auto --group-directories-first"
else
  alias ls="ls -G"
fi
alias l="ls -lh"
alias ll="ls -lah"
alias la="ls -lAh"
alias lt="ls -lth"
alias lS="ls -lSh"

# ── Safety overrides (verbose, non-semantic-changing) ───────────────
alias cp="cp -v"
alias mv="mv -v"

# ── Process management ──────────────────────────────────────────────
alias psa="ps aux"
alias psg="ps aux | grep"
alias killit="kill -9"

# ── Networking ──────────────────────────────────────────────────────
alias myip="curl -s https://api.ipify.org && echo"
alias listening="lsof -iTCP -sTCP:LISTEN -n -P"
alias ports="ss -tulnp 2>/dev/null || netstat -tulnp"

# ── Git (core; extensions in 61-git-extensions.zsh) ─────────────────
alias g="git"
alias gs="git status -sb"
alias ga="git add"
alias gc="git commit"
alias gp="git push"
alias gpl="git pull --rebase"
alias gd="git diff"
alias gdc="git diff --cached"
alias gl="git log --oneline --graph --decorate"
alias gco="git checkout"
alias gb="git branch -vv"
alias gst="git stash"

# ── Language-tooling shorthands (per-language details in 62-64) ─────
# mise tasks — consistent entry point across projects
alias m="mise"
alias mr="mise run"            # run a task defined in mise.toml
alias mx="mise exec --"        # run a one-off command in mise-activated env

# Ruby / Bundler / rv
alias be="bundle exec"
alias bi="bundle install"
alias bo="bundle open"
alias rvr="rv run"
alias rvi="rv install"

# Python (uv)
alias uvr="uv run"
alias uvs="uv sync"
alias uva="uv add"

# Bun
alias br="bun run"
alias bx="bun x"

# ── System ──────────────────────────────────────────────────────────
alias reload="exec zsh"
alias zshconfig="${EDITOR} ${ZDOTDIR}/.zshrc"
alias miseconfig="${EDITOR} ${XDG_CONFIG_HOME}/mise/config.toml"
alias path='echo ${PATH} | tr ":" "\n"'
alias now='date +"%Y-%m-%d %H:%M:%S"'

# ── direnv ──────────────────────────────────────────────────────────
alias da="direnv allow"
alias de="direnv edit"
alias ds="direnv status"
