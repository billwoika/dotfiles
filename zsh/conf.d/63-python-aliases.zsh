# $ZDOTDIR/conf.d/63-python-aliases.zsh
# ─────────────────────────────────────────────────────────────────────
# Python (uv-centric) aliases and helpers.
# Core `uvr`, `uvs`, `uva` are in 60-aliases.zsh.
# ─────────────────────────────────────────────────────────────────────

# Quick test runners
alias pt='uv run pytest -q'
alias ptv='uv run pytest -v'
alias ptk='uv run pytest -q -k'       # usage: ptk "test_login"

# One-shot script or tool execution without installing.
# uvx is uv's equivalent of npx — runs the latest version of a PyPI CLI.
alias uvx='uv tool run'

# Clean Python caches throughout a project
pyclean() {
  find . -type d \( -name "__pycache__" -o -name ".mypy_cache" \
                    -o -name ".ruff_cache" -o -name ".pytest_cache" \) \
    -prune -exec rm -rf {} +
  find . -name "*.pyc" -delete
  echo "Cleaned Python caches."
}

# Jupyter Lab (project-local, bound to all interfaces for remote access)
alias jl='uv run jupyter lab --port=9999 --ip=0.0.0.0'

# Serve current directory as static HTTP (debugging frontend/static files)
alias pyserve='python3 -m http.server 8000'
