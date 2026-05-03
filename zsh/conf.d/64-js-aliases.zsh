# $ZDOTDIR/conf.d/64-js-aliases.zsh
# ─────────────────────────────────────────────────────────────────────
# JavaScript / TypeScript (bun-centric) aliases and helpers.
# Core `br`, `bx` are in 60-aliases.zsh.
# ─────────────────────────────────────────────────────────────────────

# bun shorthands
alias bt='bun test'

# Lint only files staged for commit, matching TS/JS/Vue.
# Useful pre-commit without running the full project lint.
lint-current() {
  git diff --name-only HEAD | \
    grep -E '\.(ts|tsx|js|jsx|vue)$' | \
    xargs -r -I{} bunx eslint {}
}

# Alternative using biome (preferred in this framework, Section 10.3)
biome-current() {
  git diff --name-only HEAD | \
    grep -E '\.(ts|tsx|js|jsx|json)$' | \
    xargs -r -I{} bunx biome check --apply {}
}

# Discover package.json scripts
scripts() {
  if [[ -f package.json ]]; then
    jq -r '.scripts | to_entries[] | "\(.key):\t\(.value)"' package.json
  else
    echo "No package.json in current directory" >&2
    return 1
  fi
}

# TypeScript type check without emit
alias tsc-check='bunx tsc --noEmit'
