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

case "$(uname -s)" in
  Darwin) _os="macos" ;;
  Linux)  _os="linux" ;;
  *)      _os="unknown" ;;
esac

case "${1:-}" in
  --dry-run|-n) DRY_RUN=1 ;;
  -h|--help)
    cat <<EOF
Usage: sh bootstrap.sh [--dry-run]

Installs symlinks from this dotfiles repository into \$HOME and
\$XDG_CONFIG_HOME, creating directories as needed. Does NOT install
any software — that is handled by mise/rv/etc. after bootstrap.

Options:
  --dry-run, -n   Print what would be done without making changes
  -h, --help      Show this message
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
  "${HOME}/.local/bin" \
; do
  run mkdir -p "$dir"
done
run chmod 700 "${HOME}/.ssh/control"

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
for tpl in work personal allowed_signers; do
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

# ── Audit: scan shell startup files for rogue injections ────────────
audit_shell_injections() {
  local found=0 matches target
  log ""
  log "Auditing shell startup files for rogue injections..."
  for f in "${HOME}/.profile" "${HOME}/.bash_profile" "${HOME}/.bashrc" \
           "${HOME}/.zshenv" "${HOME}/.zshrc" "${HOME}/.zprofile"; do
    [ -f "$f" ] || continue
    # Skip files that are symlinks into our dotfiles repo (those are us)
    if [ -L "$f" ]; then
      target=$(readlink "$f")
      case "$target" in
        */dotfiles/*) continue ;;
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

audit_shell_injections || true

# ── Final instructions ──────────────────────────────────────────────
log ""
log "─────────────────────────────────────────────────────────────────"
log "Symlinks installed. Next steps:"
log ""
log "  1. Install mise:"
log "       curl https://mise.run | sh"
log ""
log "  2. Install rv:"
log "       curl --proto '=https' --tlsv1.2 -LsSf \\"
log "         https://github.com/spinel-coop/rv/releases/latest/download/rv-installer.sh | sh"
log ""
log "  3. Reload the shell:"
log "       exec zsh"
log ""
log "  4. Install runtimes declared in ~/.config/mise/config.toml:"
log "       mise install"
log ""
log "  5. Generate SSH keys (adjust email / machine label):"
log "       ssh-keygen -t ed25519 -C 'dev@springbig.com (work, laptop, YYYY-MM)' \\"
log "         -f ~/.ssh/id_ed25519_work"
log ""
log "  6. Edit the profile templates with your real identity:"
log "       \$EDITOR ~/.config/git/work.config"
log "       \$EDITOR ~/.config/git/personal.config"
log "       \$EDITOR ~/.config/git/allowed_signers"
log "       \$EDITOR ~/.ssh/config"
log ""
log "  7. Validate the ~/.profile with the POSIX test suite:"
log "       sh ${DOTFILES}/sh/tests/profile_test.sh"
log ""
if [ "$_os" = "macos" ]; then
  log "  Optional macOS-specific steps:"
  log ""
  log "  8. Install TextMate and MarkEdit if you want them:"
  log "       brew install --cask textmate markedit"
  log "     Then re-run bootstrap.sh to create their CLI shortcuts."
  log ""
  log "  9. Configure file associations interactively (requires duti):"
  log "       brew install duti"
  log "       sh ${DOTFILES}/macos/setup-file-associations.sh"
  log ""
  log "  10. (Opt-in) Add mise shims to the system PATH so GUI-launched IDEs"
  log "      can find mise-managed tools without being launched from a shell:"
  log "       echo \"\$HOME/.local/share/mise/shims\" | \\"
  log "         sudo tee /etc/paths.d/mise > /dev/null"
  log "      Effect takes hold after a logout/login cycle."
  log ""
fi

if [ "$_os" = "linux" ]; then
  log "  Optional Linux-specific steps:"
  log ""
  log "  8. Ensure zsh is the default shell (if not already):"
  log "       chsh -s \$(which zsh)"
  log ""
  log "  9. Install libsecret for the keychain_get shell function:"
  log "       Debian/Ubuntu: sudo apt install libsecret-tools"
  log "       Fedora/RHEL:   sudo dnf install libsecret"
  log ""
  log "  10. (Opt-in) Add mise shims to the system PATH so GUI-launched IDEs"
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
log "       ${DOTFILES}/devcontainer/*               → <project>/.devcontainer/  (see Section 21.6)"
log ""
log "─────────────────────────────────────────────────────────────────"
