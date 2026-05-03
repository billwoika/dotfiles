# $ZDOTDIR/conf.d/10-path.zsh
# ─────────────────────────────────────────────────────────────────────
# Deterministic PATH construction.
#
# Uses the zsh path array (lowercase) which is automatically synchronized
# with $PATH. typeset -U enforces uniqueness — duplicates are silently
# dropped, so this file is safe to source multiple times.
# ─────────────────────────────────────────────────────────────────────

# Enforce uniqueness on the path array. This applies globally for the
# lifetime of the shell — duplicates added by any subsequent source are
# also discarded.
typeset -U path PATH

# ── Helpers ─────────────────────────────────────────────────────────
_path_prepend() { [[ -d "$1" ]] && path=("$1" "${path[@]}"); }
_path_append()  { [[ -d "$1" ]] && path+=("$1"); }

# ── System baseline (low priority — only if not already set) ────────
_path_append "/usr/local/bin"
_path_append "/usr/bin"
_path_append "/bin"
_path_append "/usr/sbin"
_path_append "/sbin"

# ── User-local binaries ─────────────────────────────────────────────
_path_prepend "${HOME}/.local/bin"

# ── Rust ────────────────────────────────────────────────────────────
_path_prepend "${CARGO_HOME}/bin"

# ── Go ──────────────────────────────────────────────────────────────
_path_prepend "${GOPATH}/bin"

# ── mise shims (highest priority — must shadow system tools) ────────
# mise activate manipulates PATH in interactive shells directly and does
# not use shims for that path. Shims are still used by non-interactive
# subprocesses (scripts, editor build commands, CI, etc.).
#
# The shim directory must come before system bins so that .mise.toml or
# mise.toml version resolution wins over system-installed runtimes.
_path_prepend "${XDG_DATA_HOME}/mise/shims"

# ── Language-ecosystem bins (resolved via mise, not added directly) ──
# Python, Node, bun, and uv executables are resolved through mise activate
# at the shell level and through mise shims above for subprocesses.
# Adding their bin dirs directly would bypass version resolution.

# ── rv: Ruby version & gem manager (not managed by mise in this stack) ──
# rv has its own shell integration (installed in conf.d/70-tools.zsh).
# Its bin directory is added by `rv shell zsh` activation, not here.

# ── Cleanup: unset private helpers to avoid namespace pollution ─────
unfunction _path_prepend _path_append 2>/dev/null || true

# ── Export (path array and PATH are synced automatically by zsh) ────
# Explicitly exporting here makes the value available to subprocesses
# that do not inherit a zsh environment (e.g., exec-d processes).
export PATH
