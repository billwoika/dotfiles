# Terminal Environment: iTerm2 and tmux

The terminal emulator and the multiplexer are the two pieces of UI
that sit between the engineer and every other tool in this framework.
Time spent configuring them well repays itself within a week. This
page covers iTerm2 (macOS terminal emulator) and tmux (session
multiplexer) as a coherent pair, with specific attention to two
integration points: iTerm2's `tmux -CC` integration mode (native tab
rendering for local tmux sessions), and keybinding coherence with the
emacs-mode zsh configuration from
[keybinds](architecture.md#file-layout).

!!! note "Linux alternatives"

    iTerm2 is macOS-only. On Linux, equivalent feature depth is
    available in **WezTerm** (Lua-configured, cross-platform, has its
    own multiplexer built in), **Kitty** (GPU-accelerated, has its own
    protocol extensions), or **Alacritty** (minimalist, fastest, pairs
    naturally with tmux). The tmux guidance on this page applies
    identically regardless of emulator; the iTerm2-specific features
    have WezTerm equivalents documented in the WezTerm manual.

## iTerm2 installation and initial setup

```sh
# Install iTerm2 via Homebrew cask (preferred — auto-updates with brew upgrade)
brew install --cask iterm2
```

The most important first-run setting: **iTerm2 > Settings > General >
Preferences > Load preferences from a custom folder or URL**. Point
this at a directory in your dotfiles repository (`~/dotfiles/iterm2/`),
and enable "Save changes to folder when iTerm2 quits." iTerm2 writes
its entire preference state — profiles, key bindings, colors, triggers,
window arrangements — to `com.googlecode.iterm2.plist` in that folder.
Commit that file to version control; it is the full configuration
surface, portable across machines.

!!! tip "Binary plist diffs"

    The `com.googlecode.iterm2.plist` is in Apple's binary plist format
    by default, which produces opaque diffs in git. Convert it to XML
    form for readable diffs with `plutil -convert xml1
    com.googlecode.iterm2.plist`. iTerm2 reads either format, and you
    can add this conversion as a pre-commit hook in lefthook.

## Dynamic profiles

Dynamic Profiles are per-profile JSON files that iTerm2 loads from
`~/Library/Application Support/iTerm2/DynamicProfiles/` on startup
and refreshes on change. They layer on top of the main preferences
file: you use them for project-specific or role-specific profiles
(e.g., "Work SSH", "Personal local", "Production DB tunnel") while
the base profile holds your shared defaults. Because they are JSON,
they diff cleanly and can live in the dotfiles tree too.

```json
// ~/dotfiles/iterm2/DynamicProfiles/work-ssh.json
// Symlinked into ~/Library/Application Support/iTerm2/DynamicProfiles/
{
  "Profiles": [
    {
      "Guid": "7d9a8e2c-01a0-4e12-b2f0-3a1e9fd2d4c7",
      "Name": "Work SSH",
      "Dynamic Profile Parent Name": "Default",
      "Custom Command": "Yes",
      "Command": "ssh bastion",
      "Tags": ["work", "ssh"],
      "Badge Text": "WORK"
    }
  ]
}
```

The `Dynamic Profile Parent Name` field is the critical convenience —
the child profile inherits every setting from the parent and overrides
only the fields it specifies.

## Shell integration

iTerm2 shell integration is a set of shell functions and escape
sequences that tell the terminal where prompts begin, when commands
start and finish, what exit code they returned, and what the current
working directory is. Once installed, iTerm2 gains capabilities not
possible with a dumb terminal:

- Cmd-up/Cmd-down to jump between prompts in the scrollback
- Cmd-click on filenames to open them in your editor at the referenced
  line
- Status line integration showing current directory, exit code, job
  name
- Upload/download via `it2dl filename` — no scp, no separate sftp
  session
- Inline image rendering via `imgcat image.png`

The framework integrates shell integration via
`conf.d/25-tool-cache.zsh` so it loads only when iTerm2 is the
active terminal (gated by `$LC_TERMINAL`). See the
[shell integration strategy](integration-strategy.md) for details on
the Tier 4 loading mechanism.

## tmux configuration

The framework's tmux config lives at `~/.config/tmux/tmux.conf`
(XDG-compliant). Key design choices:

**Keep the default `C-b` prefix.** The common advice to rebind to
`C-a` is a trap for emacs users: `C-a` is beginning-of-line, which
you use constantly in every shell prompt. Rebinding it steals that
keystroke from zsh. `C-b` is already clear of any useful default
binding.

**emacs mode for copy and status input.** `mode-keys emacs` and
`status-keys emacs` keep tmux consistent with the zsh emacs-mode
keybindings from `conf.d/50-keybinds.zsh`.

**Splits open in the current pane's directory.** The default splits
open in the session's starting directory, which is almost never what
you want.

**100k line history.** Cheap memory, expensive re-running of commands
to see their output.

### Key bindings

| Binding | Action |
|---------|--------|
| `prefix + "` | Split vertically (current directory) |
| `prefix + %` | Split horizontally (current directory) |
| `prefix + c` | New window (current directory) |
| `prefix + h/j/k/l` | Navigate panes (vim-style, repeatable) |
| `prefix + H/J/K/L` | Resize panes (repeatable) |
| `prefix + Tab` | Switch to last window |
| `prefix + x` | Kill pane (no confirmation) |
| `prefix + r` | Reload config |
| `F12` | Toggle nested tmux (see below) |

### Session management patterns

**Named sessions** are the simple case:

```sh
tmux new-session -s work
tmux new-session -s personal
tmux attach -t work
```

**Project-specific startup scripts** are the next step:

```sh
#!/bin/sh
# bin/tmux-project.sh
SESSION="myproject"
tmux new-session -d -s "$SESSION" -c ~/work/myproject
tmux send-keys -t "$SESSION" "mise run dev" C-m
tmux split-window -t "$SESSION" -v -c ~/work/myproject
tmux send-keys -t "$SESSION" "mise run test --watch" C-m
tmux attach -t "$SESSION"
```

For declarative configs, **tmuxp** reads YAML session definitions.
Install via mise (`mise use -g tmuxp@latest`).

### iTerm2 + tmux integration mode

iTerm2 has a native tmux integration (`tmux -CC`) that renders tmux
windows and panes as native iTerm2 tabs and split panes. The
advantages: native scroll, native Cmd-click, native search. The
disadvantage: it only works locally (remote SSH sessions use regular
tmux).

```sh
# Start or attach with integration mode
tmux -CC new-session -A -s work
```

### Nested tmux (SSH use case)

When SSH'ing into a remote machine that also runs tmux, key presses
go to the local tmux by default — the remote tmux never sees the
prefix. The framework's config includes an `F12` toggle that
disables the local prefix, letting the inner tmux receive `C-b`
directly. Press `F12` again to reclaim the local prefix.

## Optional: tmux plugins

The framework ships tmux-resurrect and tmux-continuum as commented-out
options in `tmux.conf`. Uncomment after installing tpm:

```sh
git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
```

Then reload config (`prefix + r`) and press `prefix + I` to install
plugins.

- **tmux-resurrect** — save/restore tmux sessions across reboots
- **tmux-continuum** — auto-save sessions every 15 minutes, auto-restore
  on tmux start
