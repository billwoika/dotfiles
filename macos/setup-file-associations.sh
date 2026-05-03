#!/bin/sh
# macos/setup-file-associations.sh
# ─────────────────────────────────────────────────────────────────────
# Interactive file-association setup for macOS, using duti.
# Proposes sensible defaults per category and prompts before applying.
#
# Usage:
#   sh macos/setup-file-associations.sh           # interactive
#   sh macos/setup-file-associations.sh --dry-run # preview, no changes
#   sh macos/setup-file-associations.sh --help
# ─────────────────────────────────────────────────────────────────────
set -eu

DRY_RUN=0
case "${1:-}" in
  --dry-run|-n) DRY_RUN=1 ;;
  -h|--help)
    cat <<EOF
Usage: sh setup-file-associations.sh [--dry-run]

Sets macOS file-type associations using duti. Prompts for each category
of file types before making changes.

Categories:
  - Markdown            (.md, .markdown)        -> MarkEdit
  - Config files        (.json, .yml, .toml...) -> TextMate
  - Shell / scripts     (.sh, .zsh, .bash)      -> TextMate
  - Plain text          (.txt, .log)            -> TextMate
  - Source code         (.rb, .py, .js, .ts)    -> VS Code (opt-in)

Options:
  --dry-run, -n   Preview proposed associations without changing anything
  -h, --help      Show this help

Requirements: duti must be installed (brew install duti)
              The target apps must be installed for associations to work.
EOF
    exit 0 ;;
esac

# ── Sanity checks ──────────────────────────────────────────────────
if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script is macOS-only." >&2
  exit 1
fi

if ! command -v duti >/dev/null 2>&1; then
  echo "duti is not installed. Install it with: brew install duti" >&2
  exit 1
fi

# ── App bundle IDs ─────────────────────────────────────────────────
# These are the canonical bundle identifiers as registered by macOS.
TEXTMATE_ID="com.macromates.TextMate"
MARKEDIT_ID="co.cyan.markedit"
VSCODE_ID="com.microsoft.VSCode"

# ── Helpers ────────────────────────────────────────────────────────
app_present() {
  # Returns 0 if the app with the given bundle ID is registered with macOS
  bundle_id="$1"
  /usr/bin/mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" 2>/dev/null \
    | grep -q '.app$'
}

current_default() {
  # Print the current default app for a given extension
  ext="$1"
  duti -x "$ext" 2>/dev/null | head -1 || echo "(none)"
}

ask() {
  # Yes/no prompt. Returns 0 for yes, 1 for no.
  prompt="$1"
  printf "  %s [y/N] " "$prompt"
  read -r answer
  case "$answer" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

apply_extensions() {
  # apply_extensions <bundle_id> <ext1> <ext2> ...
  bundle_id="$1"
  shift
  for ext; do
    if [ "$DRY_RUN" = "1" ]; then
      printf "    [dry] duti -s %s %s all\n" "$bundle_id" "$ext"
    else
      duti -s "$bundle_id" "$ext" all
      printf "    [set] %-12s -> %s\n" ".$ext" "$bundle_id"
    fi
  done
}

show_category() {
  # show_category <category-name> <target-app> <ext1> <ext2> ...
  category="$1"
  target="$2"
  shift 2
  echo ""
  echo "── $category ──────────────────────────────────────────────────"
  echo "  Target app: $target"
  echo "  Extensions: $*"
  echo "  Current defaults:"
  for ext; do
    printf "    .%-10s -> %s\n" "$ext" "$(current_default "$ext")"
  done
}

# ── Run ────────────────────────────────────────────────────────────
echo "macOS file-association setup"
[ "$DRY_RUN" = "1" ] && echo "(DRY RUN \u2014 no changes will be made)"
echo ""

# 1. Markdown -> MarkEdit
if app_present "$MARKEDIT_ID"; then
  show_category "Markdown" "MarkEdit" "md" "markdown"
  if ask "Set MarkEdit as default for these markdown extensions?"; then
    apply_extensions "$MARKEDIT_ID" "md" "markdown"
  else
    echo "  [skipped]"
  fi
else
  echo "── Markdown ── MarkEdit not installed; skipping"
fi

# 2. Config files -> TextMate
if app_present "$TEXTMATE_ID"; then
  show_category "Config files" "TextMate" "json" "yml" "yaml" "toml" "conf" "ini"
  if ask "Set TextMate as default for these config-file extensions?"; then
    apply_extensions "$TEXTMATE_ID" "json" "yml" "yaml" "toml" "conf" "ini"
  else
    echo "  [skipped]"
  fi

  # 3. Shell / scripts -> TextMate
  show_category "Shell / scripts" "TextMate" "sh" "zsh" "bash"
  if ask "Set TextMate as default for these shell extensions?"; then
    apply_extensions "$TEXTMATE_ID" "sh" "zsh" "bash"
  else
    echo "  [skipped]"
  fi

  # 4. Plain text -> TextMate
  show_category "Plain text" "TextMate" "txt" "log"
  if ask "Set TextMate as default for these plain-text extensions?"; then
    apply_extensions "$TEXTMATE_ID" "txt" "log"
  else
    echo "  [skipped]"
  fi
else
  echo "── TextMate categories ── TextMate not installed; skipping"
fi

# 5. Source code -> VS Code (opt-in only; project context usually preferred)
if app_present "$VSCODE_ID"; then
  show_category "Source code" "VS Code" "rb" "py" "js" "ts" "go" "rs"
  echo "  Note: most engineers prefer to open source files via project"
  echo "  context (Open Folder), not by double-clicking individual files."
  if ask "Set VS Code as default for these source-code extensions anyway?"; then
    apply_extensions "$VSCODE_ID" "rb" "py" "js" "ts" "go" "rs"
  else
    echo "  [skipped]"
  fi
else
  echo "── Source code ── VS Code not installed; skipping"
fi

echo ""
echo "Done."
[ "$DRY_RUN" = "1" ] && echo "(no changes were made; rerun without --dry-run to apply)"
