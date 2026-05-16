# Editors and IDEs

Most engineers use more than one editor. The terminal editor opens
dozens of times a day for git commits and quick edits. The full IDE
opens once at the start of a work session and stays open until the
laptop closes. A native GUI editor sits between them for "look at this
file fast." The framework's job is not to pick a winner but to make
every editor configure cleanly with the rest of the stack.

## Philosophy

Three principles shape this page:

1. **Editor choice belongs to the engineer.** The framework specifies
   what each editor needs to integrate with the toolchain (mise, git,
   the dotfiles). It does not specify which editor anyone should use.
2. **Tools are committed only when the team benefits.** Per-project
   `.editorconfig` is committed because every editor reads it.
   Per-project `.vscode/settings.json` is committed when it captures
   team decisions. Personal preferences stay user-level and uncommitted.
3. **Subprocess environments are a real concern.** IDEs that spawn
   child processes for tasks, debuggers, and language servers do not
   inherit the same environment as an interactive shell.

## Terminal editors

### vim — the universal $EDITOR

The framework specifies `EDITOR=vim` in `.zshenv`. This affects
`git commit`, `crontab -e`, `git rebase -i`, and the zsh
edit-command-line widget. vim's universal availability matters: it is
preinstalled on every Linux distribution, every macOS install, every
container base image larger than Alpine, and every server you might
SSH into.

The framework ships a minimal `.vimrc` with sensible defaults: syntax
highlighting, line numbers, sane indentation, persistent undo to
`$XDG_STATE_HOME/vim/undo/`, and swap files to
`$XDG_STATE_HOME/vim/swap/` (keeping the project directory clean).

### nvim — the modern alternative

Neovim is the better choice for engineers who want LSP support,
treesitter-based highlighting, and a Lua-configurable plugin
ecosystem. The framework doesn't ship an nvim config — the nvim
ecosystem has excellent distributions (LazyVim, kickstart.nvim) that
are better starting points than anything the framework would provide.

### nano — the friendly fallback

nano is what `EDITOR=nano` users expect. The framework doesn't set it
as the default, but every `$EDITOR` invocation respects whatever you
override it to. If you prefer nano, set `EDITOR=nano` in your
`$ZDOTDIR/env.local.zsh`.

## Native macOS editors

**TextMate** — the framework's bootstrap detects TextMate and creates
a `mate` CLI symlink in `~/.local/bin/`. Useful as a quick GUI editor
for single files.

**MarkEdit** — a native macOS Markdown editor. Bootstrap creates a
`markedit` wrapper in `~/.local/bin/` since MarkEdit doesn't ship a
CLI.

On Linux, lightweight native GUI editors (gedit, GNOME Text Editor,
Kate) fill a similar role. The framework does not configure them — they
are lightweight enough to need no framework integration.

## .editorconfig

EditorConfig is the non-negotiable baseline for polyglot projects —
every editor and IDE supports it natively or via plugin. The
framework's `.editorconfig` sets UTF-8, LF line endings, 2-space
indent (4 for Python, tabs for Makefiles), final newline, and trim
trailing whitespace (except `.md`). See the
[code quality page](code-quality.md) for the full reference.

## IDE configuration as part of the environment contract

The framework ships reference templates in the `vscode/` and
`jetbrains/` directories:

**VS Code:**
- `settings.json.example` — workspace settings (formatOnSave, ruler,
  language-specific formatters)
- `extensions.json.example` — recommended extensions
- `launch.json.example` — debug configurations

**JetBrains:**
- `RSpec_current_file.xml` — run configuration for RSpec
- `Pytest_current_file.xml` — run configuration for pytest

Copy these into individual projects as starting points. They are not
symlinked into your home directory — each project owns its own copy.

## The IDE-spawned subprocess problem

When VS Code or a JetBrains IDE spawns a terminal, task, or language
server, the child process does not inherit the same environment as
your interactive zsh session. Specifically:

- mise-activated tool versions may not be on PATH
- direnv-loaded environment variables are missing
- The 1Password agent socket may not be forwarded

The framework's defenses:

1. **mise shims on the system PATH.** The `~/.profile` adds
   `~/.local/share/mise/shims` to PATH. IDE-spawned processes that
   inherit the base system PATH find mise-managed tools via shims.
2. **The system-level PATH opt-in.** For GUI-launched IDEs that
   bypass all shell profiles, add mise shims to the system PATH:

    === "macOS"

        ```sh
        echo "$HOME/.local/share/mise/shims" | \
          sudo tee /etc/paths.d/mise > /dev/null
        ```

    === "Linux"

        ```sh
        mkdir -p ~/.config/environment.d
        echo 'PATH=$HOME/.local/share/mise/shims:$PATH' > \
          ~/.config/environment.d/mise.conf
        ```

        This works on systemd-based distributions (Debian 12+,
        Fedora, RHEL 9+). On non-systemd distributions, add the
        export to `~/.profile` instead.
3. **Launch the IDE from the terminal.** `code .` or `idea .` from a
   mise-activated directory inherits the full shell environment.

## Debugging — the underused capability

The framework takes a clear position: **use the debugger, not print
statements.** Debugger breakpoints, watch expressions, and evaluate
panels provide the same information as print debugging without
modifying source, without cleanup, and with the ability to inspect
state interactively.

### Key capabilities

- **Breakpoints** — pause execution at a specific line
- **Watch expressions** — monitor variables across execution steps
- **Evaluate panel** — run arbitrary expressions in the current scope
- **Logpoints** — emit log output at a specific line *without*
  modifying source (the proper `console.log` replacement)
- **Conditional breakpoints** — pause only when a condition is true
- **Exception breakpoints** — pause on thrown exceptions before they
  propagate

### Reference debug configurations

The framework ships `launch.json.example` (VS Code) and JetBrains
run configurations for:

- **Ruby**: RSpec current file via `bundle exec rspec`
- **Python**: pytest current file via `uv run pytest`

## Code intelligence — the LSP contract

Language Server Protocol (LSP) gives every editor the same code
intelligence: go-to-definition, find-references, rename, hover
documentation, and diagnostics. The framework's stance: **rely on
LSP, not grep, for code navigation** in projects large enough to have
a language server.

When the IDE is wrong — and LSP occasionally is — the terminal is the
fallback: `grep -r`, `git grep`, `ag`, `rg`. The
[shell aliases](../shell-environment/aliases.md) include shortcuts for these.

## Source control integration

**Where the IDE wins:** interactive staging (selecting hunks),
inline blame, visual merge conflict resolution, PR review with inline
comments (via extensions).

**Where the terminal wins:** complex rebase operations, bulk branch
operations, anything scripted or automated, `git bisect`.

**Configuration that travels with the project:** the framework's
`.gitattributes` and `.gitignore` patterns work identically in
terminal and IDE contexts. The delta pager configured in
`git/config` provides syntax-highlighted diffs in the terminal.

## Database and DDL artifacts

For projects with databases:

- **Migrations are the canonical artifact.** `db/migrate/` (Rails) or
  the equivalent in your framework is the source of truth for schema.
- **IDE-generated DDL** (DataGrip's "DDL data source") is a read-only
  convenience, not a source of truth.
- **`.idea/dataSources.xml`** can be committed (it contains connection
  metadata, not credentials). `.idea/dataSources.local.xml` must be
  gitignored (it may contain credentials).

## Test integration

Both VS Code (Test Explorer) and JetBrains (built-in test runners)
provide gutter-click test execution, inline failure display, and
re-run-failed workflows. The framework's position: **CI is
authoritative, the IDE is a fast-feedback convenience.** Never ship
code that passes in the IDE but hasn't passed in CI.

## Project intelligence

IDE features worth configuring for every project:

- **Workspace symbols** — Cmd+T / Ctrl+T to jump to any symbol
- **File outline / structure view** — navigate within a file
- **Search across files** — use the IDE's indexed search for
  project-wide queries; fall back to `rg` or `git grep` for
  precision
