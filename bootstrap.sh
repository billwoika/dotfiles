#!/bin/sh
# bootstrap.sh
# ─────────────────────────────────────────────────────────────────────
# Idempotent dotfiles installation.
# Usage: sh bootstrap.sh [--dry-run]
#
# POSIX sh only — must run on a freshly-provisioned machine before
# any zsh framework is active.
# ─────────────────────────────────────────────────────────────────────

set -eu

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=0
AUDIT_ONLY=0

case "$(uname -s)" in
  Darwin) _os="macos" ;;
  Linux)  _os="linux" ;;
  *)      _os="unknown" ;;
esac

case "${1:-}" in
  --dry-run|-n)    DRY_RUN=1 ;;
  --audit-only|-a) AUDIT_ONLY=1 ;;
  -h|--help)
    cat <<EOF
Usage: sh bootstrap.sh [--dry-run|--audit-only]

Installs symlinks from this dotfiles repository into \$HOME and
\$XDG_CONFIG_HOME, creating directories as needed. Does NOT install
any software — that is handled by mise/rv/etc. after bootstrap.

Options:
  --dry-run, -n     Print what would be done without making changes
  --audit-only, -a  Run only the rogue-injection audit, then exit
  -h, --help        Show this message
EOF
    exit 0 ;;
esac

# ── Paths ───────────────────────────────────────────────────────────
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# ── Helpers ─────────────────────────────────────────────────────────
run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf "  [dry] %s\n" "$*"
  else
    "$@"
  fi
}

log() { printf "%s\n" "$*"; }

# link <src> <dst> — idempotent symlink creation
link() {
  src=$1; dst=$2
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    printf "  [ok]  %s\n" "$dst"
    return 0
  fi
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    printf "  [backup] %s -> %s.backup\n" "$dst" "$dst"
    run mv "$dst" "${dst}.backup"
  fi
  run ln -sfn "$src" "$dst"
  printf "  [new] %s -> %s\n" "$dst" "$src"
}

# ── Audit: scan shell startup files for rogue injections ────────────
audit_shell_injections() {
  # NOTE: no `local` — it is not POSIX (shellcheck SC3043), and this
  # file is POSIX-sh-only per its header. found/matches/target/f are
  # unique to this function, so plain assignment is safe.
  found=0
  log ""
  log "Auditing shell startup files for rogue injections..."
  for f in "${HOME}/.profile" "${HOME}/.bash_profile" "${HOME}/.bashrc" \
           "${HOME}/.zshenv" "${HOME}/.zshrc" "${HOME}/.zprofile"; do
    [ -f "$f" ] || continue
    # Skip files that are symlinks into our dotfiles repo (those are us).
    # Match the actual $DOTFILES source path rather than a hardcoded
    # "dotfiles" substring, so the audit is correct regardless of where
    # the repo was cloned.
    if [ -L "$f" ]; then
      target=$(readlink "$f")
      case "$target" in
        "$DOTFILES"/*) continue ;;
      esac
    fi
    matches=$(grep -nE \
      'NVM_DIR|VOLTA_HOME|BUN_INSTALL|cargo/env|rustup|pyenv init|asdf\.sh|conda init|emsdk_env' \
      "$f" 2>/dev/null) || matches=""
    if [ -n "$matches" ]; then
      printf "  [rogue] %s\n" "$f"
      printf "%s\n" "$matches" | sed 's/^/    /'
      found=$((found + 1))
    fi
  done
  if [ "$found" -gt 0 ]; then
    log ""
    log "  ^^ Remove these lines and rely on conf.d/10-path.zsh instead."
    log "     The framework's deterministic PATH builder is the single"
    log "     source of truth; ad-hoc installer-injected lines duplicate"
    log "     or conflict with it."
    return 1
  else
    log "  All shell startup files are clean."
    return 0
  fi
}


# --audit-only short-circuits here: the audit is the one part of this
# script worth re-running on its own, because mise and rv can re-create
# bash startup files when they install. Exposed as `mise run dotfiles:audit`.
if [ "$AUDIT_ONLY" = "1" ]; then
  audit_shell_injections
  exit $?
fi

# ── Create XDG directories ──────────────────────────────────────────
log ""
log "Creating XDG directories..."
for dir in \
  "${XDG_CONFIG_HOME}/zsh/conf.d" \
  "${XDG_CONFIG_HOME}/mise" \
  "${XDG_CONFIG_HOME}/direnv" \
  "${XDG_CONFIG_HOME}/git" \
  "${XDG_CONFIG_HOME}/tmux" \
  "${XDG_DATA_HOME}" \
  "${XDG_STATE_HOME}/zsh" \
  "${XDG_CACHE_HOME}/zsh" \
  "${HOME}/.ssh/control" \
  "${XDG_DATA_HOME}/gnupg" \
  "${HOME}/.local/bin" \
  "${HOME}/development/personal/repos" \
  "${HOME}/development/work/repos" \
  "${HOME}/development/opensource/repos" \
; do
  run mkdir -p "$dir"
done
run chmod 700 "${HOME}/.ssh/control"
# GnuPG refuses to operate against a homedir with permissions looser
# than 0700 (silent failure or a "keyblock resource: No such file or
# directory" from callers like mise that gpg --import into it before
# it has ever been initialized). Belongs alongside the other
# security-sensitive dirs above.
run chmod 700 "${XDG_DATA_HOME}/gnupg"

# ── Zsh ─────────────────────────────────────────────────────────────
log ""
log "Installing zsh configuration..."
link "${DOTFILES}/zsh/zshenv"    "${HOME}/.zshenv"
link "${DOTFILES}/zsh/.zshenv"   "${XDG_CONFIG_HOME}/zsh/.zshenv"
link "${DOTFILES}/zsh/.zprofile" "${XDG_CONFIG_HOME}/zsh/.zprofile"
link "${DOTFILES}/zsh/.zshrc"    "${XDG_CONFIG_HOME}/zsh/.zshrc"
link "${DOTFILES}/zsh/.zlogout"  "${XDG_CONFIG_HOME}/zsh/.zlogout"

# conf.d fragments
for f in "${DOTFILES}/zsh/conf.d/"*.zsh; do
  name="$(basename "$f")"
  link "$f" "${XDG_CONFIG_HOME}/zsh/conf.d/${name}"
done

# ── POSIX profile ───────────────────────────────────────────────────
log ""
log "Installing POSIX profile..."
link "${DOTFILES}/profile" "${HOME}/.profile"

# ── mise ────────────────────────────────────────────────────────────
log ""
log "Installing mise configuration..."
link "${DOTFILES}/mise/config.toml" "${XDG_CONFIG_HOME}/mise/config.toml"
# miserc.toml carries auto_env, which decides WHICH config files mise
# loads (config.linux.toml / config.macos.toml). It therefore cannot be
# applied by mise's own [dotfiles] pass — that pass has already happened
# by the time it would matter. Linked here, before mise ever runs.
link "${DOTFILES}/mise/miserc.toml" "${XDG_CONFIG_HOME}/mise/miserc.toml"
# Platform configs, selected by auto_env. Same reasoning: mise resolves
# config.<env>.toml out of MISE_CONFIG_DIR while deciding what to load,
# so they must already be in place — [dotfiles] runs too late.
link "${DOTFILES}/mise/config.linux.toml" "${XDG_CONFIG_HOME}/mise/config.linux.toml"
link "${DOTFILES}/mise/config.macos.toml" "${XDG_CONFIG_HOME}/mise/config.macos.toml"

# ── direnv ──────────────────────────────────────────────────────────
log ""
log "Installing direnv configuration..."
link "${DOTFILES}/direnv/direnvrc" "${XDG_CONFIG_HOME}/direnv/direnvrc"

# ── git ─────────────────────────────────────────────────────────────
log ""
log "Installing git configuration..."
link "${DOTFILES}/git/config"     "${XDG_CONFIG_HOME}/git/config"
link "${DOTFILES}/git/ignore"     "${XDG_CONFIG_HOME}/git/ignore"
link "${DOTFILES}/git/attributes" "${XDG_CONFIG_HOME}/git/attributes"

# Profile templates: copy (not symlink) so user can edit locally without
# dirtying the dotfiles repo. Skip if target already exists.
for tpl in local work personal opensource allowed_signers; do
  src="${DOTFILES}/git/${tpl}.config.example"
  [ "$tpl" = "allowed_signers" ] && src="${DOTFILES}/git/allowed_signers.example"
  dst="${XDG_CONFIG_HOME}/git/${tpl}.config"
  [ "$tpl" = "allowed_signers" ] && dst="${XDG_CONFIG_HOME}/git/allowed_signers"

  if [ -f "$dst" ]; then
    printf "  [keep] %s (edit in place)\n" "$dst"
  elif [ -f "$src" ]; then
    run cp "$src" "$dst"
    printf "  [copy] %s -> %s (EDIT ME)\n" "$src" "$dst"
  fi
done

# ── Per-profile mise seeds ──────────────────────────────────────────
# Copied, not symlinked: mise walks up from a repo to ~/development/<p>/
# and merges these with the user-scope config. They are seeds meant to be
# edited in place, so they stay out of [dotfiles] — same reasoning as the
# git profile configs above.
log ""
log "Installing per-profile mise seeds..."
for prof in personal work opensource; do
  src="${DOTFILES}/mise/${prof}.mise.toml.example"
  dst="${HOME}/development/${prof}/mise.toml"
  if [ -f "$dst" ]; then
    printf "  [keep] %s (edit in place)\n" "$dst"
  elif [ -f "$src" ]; then
    run cp "$src" "$dst"
    printf "  [copy] %s (EDIT ME)\n" "$dst"
  fi
  # mise refuses to load an untrusted config, and these are new files on
  # every fresh machine. Without this, the first command run from inside
  # ~/development/<profile>/ fails with "Config files are not trusted"
  # rather than doing anything useful.
  if [ "$DRY_RUN" != "1" ] && [ -f "$dst" ] && command -v mise >/dev/null 2>&1; then
    mise trust "$dst" >/dev/null 2>&1 && printf "  [trust] %s\n" "$dst"
  fi
done

# ── SSH ─────────────────────────────────────────────────────────────
log ""
log "Installing SSH config (template)..."
if [ -f "${HOME}/.ssh/config" ]; then
  printf "  [keep] %s/.ssh/config (edit in place)\n" "$HOME"
else
  run cp "${DOTFILES}/ssh/config.example" "${HOME}/.ssh/config"
  run chmod 600 "${HOME}/.ssh/config"
  printf "  [copy] %s/.ssh/config (EDIT ME)\n" "$HOME"
fi

# ── tmux ────────────────────────────────────────────────────────────
log ""
log "Installing tmux configuration..."
link "${DOTFILES}/tmux/tmux.conf" "${XDG_CONFIG_HOME}/tmux/tmux.conf"

# ── vim ─────────────────────────────────────────────────────────────
log ""
log "Installing vim configuration..."
run mkdir -p "${HOME}/.vim"
run mkdir -p "${XDG_STATE_HOME}/vim/undo"
run mkdir -p "${XDG_STATE_HOME}/vim/swap"
run mkdir -p "${XDG_STATE_HOME}/vim/backup"
link "${DOTFILES}/vim/vimrc" "${HOME}/.vim/vimrc"

# ── TextMate (auto-symlink CLI if app is installed) ─────────────────
if [ -d "/Applications/TextMate.app" ]; then
  log ""
  log "TextMate detected; installing 'mate' CLI..."
  link "/Applications/TextMate.app/Contents/Resources/mate" "${HOME}/.local/bin/mate"
else
  log ""
  log "TextMate not installed; skipping 'mate' CLI setup."
  if [ "$_os" = "macos" ]; then
    log "  (Install via: brew install --cask textmate)"
  fi
fi

# ── MarkEdit (auto-create wrapper if app is installed) ──────────────
if [ -d "/Applications/MarkEdit.app" ]; then
  log ""
  log "MarkEdit detected; creating 'markedit' wrapper..."
  if [ "$DRY_RUN" = "1" ]; then
    printf "  [dry] write %s/.local/bin/markedit\n" "$HOME"
  elif [ ! -e "${HOME}/.local/bin/markedit" ] || [ -L "${HOME}/.local/bin/markedit" ]; then
    cat > "${HOME}/.local/bin/markedit" <<'MARKEDIT_WRAPPER'
#!/bin/sh
# Auto-generated by dotfiles/bootstrap.sh
# MarkEdit doesn't ship a CLI; this wrapper invokes the .app via macOS open.
exec /usr/bin/open -a MarkEdit.app "$@"
MARKEDIT_WRAPPER
    chmod +x "${HOME}/.local/bin/markedit"
    printf "  [new] %s/.local/bin/markedit\n" "$HOME"
  else
    printf "  [keep] %s/.local/bin/markedit (exists, not overwriting)\n" "$HOME"
  fi
else
  log ""
  log "MarkEdit not installed; skipping 'markedit' wrapper setup."
  if [ "$_os" = "macos" ]; then
    log "  (Install via: brew install --cask markedit)"
  fi
fi

audit_shell_injections || true

# ── Final instructions ──────────────────────────────────────────────
log ""
log "─────────────────────────────────────────────────────────────────"
log "Filesystem prepared. Next steps:"
log ""
log "  1. Provision everything else with mise. bin/mise is vendored and"
log "     version-pinned; it fetches mise into the cache on first run, so"
log "     there is no 'curl | sh' step any more:"
log "       ${DOTFILES}/bin/mise bootstrap"
log ""
log "     That one command does three jobs:"
log "       - system packages (zsh, libsecret, ffmpeg, ...) via dnf/apt/brew,"
log "         from [bootstrap.packages] — this is the part that runs sudo"
log "       - the symlink farm, from the [dotfiles] section"
log "       - every tool in [tools], rv included"
log "     (The login shell is NOT among them — see the chsh step below.)"
log ""
log "     This script already linked ~/.config/mise/config.toml, so plain"
log "     'bin/mise bootstrap' finds the config. The MISE_CONFIG_FILE prefix"
log "     is a fallback for running mise bootstrap WITHOUT this script"
log "     having run first (e.g. after --dry-run); mise will then ask you"
log "     to 'mise trust' the repo config on that first run."
log ""
log "  2. Reload the shell:"
log "       exec zsh"
log ""
log "  3. Generate SSH keys (adjust email / machine label):"
log "       ssh-keygen -t ed25519 -C 'dev@zftadvancements.com (work, laptop, YYYY-MM)' \\"
log "         -f ~/.ssh/id_ed25519_work"
log ""
log "  4. Edit the seed templates with your real identity. These are COPIES,"
log "     not symlinks, and are deliberately kept OUT of [dotfiles] so they"
log "     can drift locally without mise converging them back:"
log "       \$EDITOR ~/.config/git/local.config     # user.name"
log "       \$EDITOR ~/.config/git/work.config"
log "       \$EDITOR ~/.config/git/personal.config"
log "       \$EDITOR ~/.config/git/opensource.config"
log "       \$EDITOR ~/.config/git/allowed_signers"
log "       \$EDITOR ~/.ssh/config"
log ""
log "  5. Verify the whole setup:"
log "       mise run dotfiles:doctor"
log ""
log "     Runs the rogue-injection audit plus the POSIX profile test suite,"
log "     then prints 'mise bootstrap status'. Re-run it after any installer"
log "     touches your shell startup files — a regenerated ~/.bash_profile"
log "     silently shadows ~/.profile, so the POSIX shim stops loading for"
log "     cron and systemd user services."
log ""
if [ "$_os" = "macos" ]; then
  log "  Optional macOS-specific steps:"
  log ""
  log "  6. TextMate and MarkEdit install declaratively now, as"
  log "     brew-cask: entries in [bootstrap.packages]. Step 1 brings"
  log "     them in; re-run THIS script afterwards to create their CLI"
  log "     shortcuts, which are detected from /Applications and so"
  log "     cannot be declared in [dotfiles]:"
  log "       sh ${DOTFILES}/bootstrap.sh"
  log ""
  log "  7. Configure file associations interactively. duti itself is"
  log "     declarative — a brew: entry in mise/config.macos.toml, which"
  log "     only loads on macOS (formulas are not platform-gated, so it"
  log "     must NOT move into the shared config — see the comment in"
  log "     that file). Step 1 installs it; this script stays manual:"
  log "       sh ${DOTFILES}/macos/setup-file-associations.sh"
  log ""
  log "  8. (Opt-in) Add mise shims to the system PATH so GUI-launched IDEs"
  log "      can find mise-managed tools without being launched from a shell:"
  log "       echo \"\$HOME/.local/share/mise/shims\" | \\"
  log "         sudo tee /etc/paths.d/mise > /dev/null"
  log "      Effect takes hold after a logout/login cycle."
  log ""
fi

if [ "$_os" = "linux" ]; then
  log "  Optional Linux-specific steps:"
  log ""
  log "  6. Set zsh as your login shell. libsecret IS declarative now via"
  log "     [bootstrap.packages], but the login shell is NOT: mise takes a"
  log "     single absolute path for it with no per-OS override, and zsh"
  log "     sits at a different path on macOS. Resolve it locally instead."
  log "     Run this AFTER step 1, which is what installs zsh:"
  log "       command -v zsh                  # confirm it exists"
  log "       chsh -s \"\$(command -v zsh)\"     # only if \$SHELL is not zsh"
  log "       echo \$SHELL                     # expect zsh after re-login"
  log ""
  log "  7. (Opt-in) Add mise shims to the system PATH so GUI-launched IDEs"
  log "      can find mise-managed tools without being launched from a shell:"
  log "       mkdir -p ~/.config/environment.d"
  log "       echo 'PATH=\$HOME/.local/share/mise/shims:\$PATH' > \\"
  log "         ~/.config/environment.d/mise.conf"
  log "      Effect takes hold after a logout/login cycle (systemd-based distros)."
  log ""
fi
log "  Reference templates for projects:"
log ""
log "    Copy these into individual project repositories as starting points."
log "    They are not symlinked into your home directory by bootstrap —"
log "    each project owns its own copy."
log ""
log "       ${DOTFILES}/.editorconfig.example       → <project>/.editorconfig"
log "       ${DOTFILES}/gitignore.example           → append to <project>/.gitignore"
log "       ${DOTFILES}/vscode/settings.json.example  → <project>/.vscode/settings.json"
log "       ${DOTFILES}/vscode/extensions.json.example → <project>/.vscode/extensions.json"
log "       ${DOTFILES}/vscode/launch.json.example   → <project>/.vscode/launch.json"
log "       ${DOTFILES}/jetbrains/runConfigurations/* → <project>/.idea/runConfigurations/"
log "       ${DOTFILES}/devcontainer/*               → <project>/.devcontainer/  (see devcontainer/README.md)"
log ""
log "─────────────────────────────────────────────────────────────────"
