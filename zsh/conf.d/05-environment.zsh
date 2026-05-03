# $ZDOTDIR/conf.d/05-environment.zsh
# ─────────────────────────────────────────────────────────────────────
# Early environment detection. Runs before PATH construction and before
# any other fragment so that downstream fragments can branch on these
# variables.
# ─────────────────────────────────────────────────────────────────────

# ── Operating system ────────────────────────────────────────────────
# Exposed as $OSTYPE_SHORT for ergonomic conditionals throughout conf.d.
case "$(uname -s)" in
  Darwin)   export OSTYPE_SHORT="macos"   ;;
  Linux)    export OSTYPE_SHORT="linux"   ;;
  FreeBSD)  export OSTYPE_SHORT="bsd"     ;;
  *)        export OSTYPE_SHORT="unknown" ;;
esac

# ── Container detection ─────────────────────────────────────────────
# /.dockerenv is created by the docker runtime; /run/.containerenv by
# Podman. VS Code / Cursor also set REMOTE_CONTAINERS=true when the
# editor is attached to a devcontainer.
if [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]] \
  || [[ -n "${REMOTE_CONTAINERS:-}" ]] \
  || [[ -n "${CODESPACES:-}" ]]; then
  export IS_CONTAINER=1
fi

# Specifically: are we inside a devcontainer (vs. some other container)?
# REMOTE_CONTAINERS is set by VS Code/Cursor; CODESPACES by GitHub Codespaces.
if [[ -n "${REMOTE_CONTAINERS:-}" ]] || [[ -n "${CODESPACES:-}" ]]; then
  export IS_DEVCONTAINER=1
fi

# ── IDE / editor detection ──────────────────────────────────────────
# VSCODE_INJECTION is set when VS Code or Cursor injects shell integration.
if [[ -n "${VSCODE_INJECTION:-}" ]] || [[ "${TERM_PROGRAM}" == "vscode" ]]; then
  export IS_VSCODE_TERMINAL=1
fi

# ── CI detection ────────────────────────────────────────────────────
# Most CI services set CI=true. Useful to skip interactive niceties.
if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] \
  || [[ -n "${GITLAB_CI:-}" ]] || [[ -n "${BUILDKITE:-}" ]]; then
  export IS_CI=1
fi
