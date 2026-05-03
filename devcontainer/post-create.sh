#!/bin/sh
# .devcontainer/post-create.sh
# ─────────────────────────────────────────────────────────────────────
# Runs once, after the container is created, as the non-root user.
# Bootstraps dotfiles into XDG locations and installs project deps.
#
# Reference template \u2014 copy to <project>/.devcontainer/post-create.sh
# and adapt the dependency-install section per project.
# ─────────────────────────────────────────────────────────────────────
set -eu

# ── Mark that we're inside a devcontainer for downstream conditionals ──
export IS_DEVCONTAINER=1

# ── Install dotfiles ────────────────────────────────────────────────
# The bind mount at /home/vscode/dotfiles is set up by devcontainer.json.
# VS Code's user-level dotfiles.repository setting also handles this for
# anyone who has it configured \u2014 the bind mount is the team default.
if [ -d "$HOME/dotfiles" ] && [ -f "$HOME/dotfiles/bootstrap.sh" ]; then
  echo ">> Installing dotfiles from $HOME/dotfiles..."
  sh "$HOME/dotfiles/bootstrap.sh"
else
  echo ">> No dotfiles found at $HOME/dotfiles \u2014 skipping bootstrap."
fi

# ── Find the workspace directory ────────────────────────────────────
# devcontainer.json's workspaceFolder is the canonical answer; fall back
# to the first /workspaces/* directory if not set.
WORKSPACE="${LOCAL_WORKSPACE_FOLDER:-${PWD}}"
case "$WORKSPACE" in
  /workspaces/*) ;;
  *)             WORKSPACE=$(ls -d /workspaces/*/ 2>/dev/null | head -1) ;;
esac
cd "$WORKSPACE" || { echo "No workspace directory found"; exit 0; }
echo ">> Workspace: $WORKSPACE"

# ── Install runtimes from the project's mise.toml ───────────────────
if [ -f mise.toml ] || [ -f .mise.toml ]; then
  echo ">> Trusting and installing mise tools..."
  mise trust
  mise install
fi

# ── Project dependency installs (idempotent) ────────────────────────
if [ -f Gemfile ]; then
  echo ">> Installing Ruby gems..."
  rv ruby install
  bundle install
fi

if [ -f pyproject.toml ]; then
  echo ">> uv sync..."
  uv sync
fi

if [ -f package.json ]; then
  echo ">> bun install..."
  bun install
fi

echo ""
echo ">> Devcontainer ready. Open a terminal to begin."
