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

## Disable format on save

Most modern IDEs promote or default to formatting the entire file
every time you save. VS Code enables `editor.formatOnSave` in many
extension packs. JetBrains offers "Reformat code" as a save action.
Prettier's documentation recommends it. **Turn it off.**

The problem is not formatting. The problem is formatting mixed with
logic changes in the same commit. When format-on-save is active,
every save rewrites every line the formatter touches — regardless of
whether those lines are related to the work in progress. The
consequences compound:

- **PR noise.** A three-line bug fix produces a 40-line diff because
  the formatter reflowed a function two screens away. The reviewer
  now has to mentally separate "what changed" from "what got
  reformatted," and the effort is not trivial — formatting changes
  can mask logic changes hiding in the same hunk.
- **Blame pollution.** `git blame` on any reformatted line now points
  to the unrelated commit that happened to save the file, not to the
  commit that wrote the logic. The archaeological value of blame —
  the primary tool for understanding *why* code is the way it is —
  degrades with every format-on-save commit.
- **Merge conflict multiplication.** Two engineers working on
  different parts of the same file both trigger format-on-save.
  Neither touched the other's code, but the formatter rewrote the
  same whitespace in both branches. The resulting merge conflict is
  on lines neither engineer intentionally changed, in code neither
  engineer needs to review, consuming time that produces zero value.
- **Legacy codebase risk.** On codebases with inconsistent formatting
  history, the first engineer to open a file with format-on-save
  enabled rewrites the entire file. Every line shows as changed. The
  actual fix is buried. If the reformatting introduces a regression
  (and reformatting *can* change behavior — Python's Black has done
  it, Prettier has done it with template literals), the blast radius
  is every line the formatter touched, not the three lines the
  engineer intended to change.

### The correct alternative

Formatting belongs in **its own dedicated pass**, separated from logic
changes:

1. **Pre-commit hook on staged lines only.** Tools like lefthook,
   lint-staged, and husky can run the formatter only on lines that are
   part of the current commit. This formats what you changed without
   touching what you did not.
2. **Dedicated formatting commits.** When a file or module needs a
   formatting pass, do it as a standalone commit with no logic changes.
   The commit message says "reformat" and reviewers know to skim it.
   `git blame` can be configured to ignore these commits via
   `.git-blame-ignore-revs`.
3. **CI enforcement.** A CI check that runs the formatter and fails if
   the output differs from the committed code. This catches formatting
   errors without mixing them into logic diffs.

### Configuring the editors

**VS Code** — in workspace `settings.json`:

```json
{
  "editor.formatOnSave": false,
  "editor.formatOnPaste": false
}
```

**JetBrains** — Settings > Tools > Actions on Save: uncheck "Reformat
code" and "Optimize imports."

**vim/nvim** — do not add `autocmd BufWritePre * :Format` or
equivalent to your config.

The framework's `settings.json.example` template ships with
`formatOnSave` disabled.

### The same problem wears other masks

Format-on-save is the most common offender, but it is one instance of
a broader antipattern: **the IDE silently modifying code you did not
intend to change.** Several other features produce the same class of
problems — noisy diffs, spurious conflicts, unintended behavior
changes — and should be treated with the same suspicion.

**Organize imports on save.** VS Code's
`editor.codeActionsOnSave: { "source.organizeImports": "explicit" }` and
JetBrains' "Optimize imports" save action reorder, add, or remove
import statements every time you save. On a file you touched one
function in, the diff now shows 15 import lines shuffled. Worse: in
languages where import order has side effects (Python, Ruby `require`
ordering in legacy code, CSS `@import` cascade), the reordering can
change runtime behavior silently.

**Auto-import insertion.** IntelliSense and LSP completions that
automatically add an import statement when you accept a suggestion are
convenient in greenfield code and dangerous in legacy code. The
auto-import picks the resolution *it* thinks is correct — which may
be the wrong module when multiple exports share a name, or a barrel
file re-export that changes the dependency graph in ways the build
tool notices but the developer does not. Review every auto-inserted
import before committing; better yet, disable automatic insertion and
add imports deliberately:

```json
{
  "typescript.preferences.importModuleSpecifier": "non-relative",
  "typescript.suggest.autoImports": false,
  "javascript.suggest.autoImports": false
}
```

JetBrains: Settings > Editor > General > Auto Import — uncheck "Add
unambiguous imports on the fly" for languages where you have
experienced incorrect resolutions.

**LSP code actions on save.** Beyond formatting, LSP servers can
apply "quick fixes" automatically — adding missing type annotations,
inserting explicit return types, converting `require` to `import`. VS
Code's `editor.codeActionsOnSave` supports arbitrary code action kinds.
Each one is a transformation applied to code you may not have touched,
producing diffs you did not author. Disable all automatic code actions
on save. Run them manually and deliberately when you want them:

```json
{
  "editor.codeActionsOnSave": {}
}
```

**IntelliSense aggressive completions.** Autocomplete that inserts
boilerplate on Tab or Enter — function signatures with placeholder
arguments, entire interface implementations, generated doc blocks —
puts code in your file that you did not write and may not have read.
The generated code may compile, but it often does not match the actual
intent. Configure completions to *suggest* without *inserting*:

```json
{
  "editor.acceptSuggestionOnCommitCharacter": false,
  "editor.suggest.insertMode": "replace"
}
```

JetBrains: Settings > Editor > General > Code Completion — disable
"Insert selected variant by pressing dot, space, etc."

**The unifying principle:** every automatic code transformation that
fires on save, on keystroke, or on completion acceptance is a tool
making decisions on your behalf. In isolation, each one saves a few
keystrokes. In aggregate, they produce commits where the engineer
cannot confidently say "I wrote every line in this diff and I
understand why each one changed." That confidence is the minimum
standard for a reviewable PR.

## IDE configuration as part of the environment contract

The framework ships reference templates in the `vscode/` and
`jetbrains/` directories:

**VS Code:**
- `settings.json.example` — workspace settings (ruler,
  language-specific formatters, formatOnSave explicitly disabled)
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

## Browser developer tools

For web development, the browser's built-in developer tools are as
indispensable as the IDE debugger — arguably more so, because they
are the only tool that shows you what is actually happening at the
boundary between your server, your frontend code, and the rendering
engine.

See the dedicated [Browser Developer Tools](browser-devtools.md) page
for full coverage of every panel, the Chrome DevTools Protocol, and
how to use these tools effectively for debugging everything from
backend errors to CSS specificity conflicts to memory leaks.

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
