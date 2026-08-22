# Terminal Environment

The terminal emulator and the multiplexer are the two pieces of UI
that sit between the engineer and every other tool in this framework.
Time spent configuring them well repays itself within a week. This
page covers terminal emulator choices per platform and tmux as the
cross-platform session multiplexer.

## Terminal emulator

=== "macOS: iTerm2"

    ### Installation

    ```sh
    brew install --cask iterm2
    ```

    ### Settings and version control

    The most important first-run setting: **iTerm2 > Settings > General >
    Preferences > Load preferences from a custom folder or URL**. Point
    this at a directory in your dotfiles repository
    (`~/development/personal/repos/dotfiles/iterm2/`),
    and enable "Save changes to folder when iTerm2 quits." iTerm2 writes
    its entire preference state — profiles, key bindings, colors, triggers,
    window arrangements — to `com.googlecode.iterm2.plist` in that folder.
    Commit that file to version control; it is the full configuration
    surface, portable across machines.

    !!! tip "Binary plist diffs"

        The `com.googlecode.iterm2.plist` is in Apple's binary plist
        format by default, which produces opaque diffs in git. Convert it
        to XML form for readable diffs with `plutil -convert xml1
        com.googlecode.iterm2.plist`. iTerm2 reads either format, and you
        can add this conversion as a pre-commit hook in lefthook.

    ### Recommended settings

    These are the settings worth changing from iTerm2's defaults for this
    framework. Set them in the GUI; because preferences are loaded from
    (and saved back to) the version-controlled folder, every change here
    serializes into `com.googlecode.iterm2.plist` and travels with your
    dotfiles.

    | Setting | Location | Value | Why |
    |---------|----------|-------|-----|
    | Scrollback lines | Profiles > Terminal | `100000` (or Unlimited) | Match the 100k tmux history. A short buffer means re-running commands to see output you already produced. |
    | Save lines to scrollback when an app exits | Profiles > Terminal | On | Keeps a full-screen program's final screen (tests, `top`) readable after it quits. |
    | Silence bell / no audible bell | Profiles > Terminal | On | The visual mark is enough; the audible bell is noise in a busy split. |
    | Shell integration: show mark indicators | Profiles > General | On | Surfaces the prompt marks that power Cmd-Shift-up/down jump-to-prompt. |
    | Unlimited clipboard / copy on select | General > Selection | On | Mouse-select copies without a keystroke, matching tmux copy-mode muscle memory. |
    | Applications in terminal may access clipboard | General > Selection | On | Lets `pbcopy`-style flows and OSC 52 work from inside tmux/SSH. |
    | Cursor: box, blink off | Profiles > Text | Box, no blink | A non-blinking block reads position at a glance and stops the distracting flicker. |

    **Font.** Use a Nerd Font so the glyphs the framework's prompt and CLI
    tools emit (git status icons, devicons) render instead of showing
    tofu boxes. Set it at **Profiles > Text > Font** — a patched build
    such as *JetBrainsMono Nerd Font* or *MesloLGS Nerd Font* at 13–14pt
    is a safe default. Enable ligatures only if you want them; they are
    cosmetic, not required.

    **Identity separation.** Give your work and personal contexts visibly
    different profiles so you never paste a work secret into a personal
    shell by accident. The badge and color are the cheapest signals — a
    large translucent `WORK` badge and a distinct tab color cost nothing
    and are unmissable. This pairs directly with the dynamic profiles
    below: define the visual differences once per profile and inherit
    them everywhere.

    ### Dynamic profiles

    Dynamic Profiles are per-profile JSON files that iTerm2 loads from
    `~/Library/Application Support/iTerm2/DynamicProfiles/` on startup
    and refreshes on change. They layer on top of the main preferences
    file: use them for project-specific or role-specific profiles
    (e.g., "Work SSH", "Personal local", "Production DB tunnel") while
    the base profile holds your shared defaults. Because they are JSON,
    they diff cleanly and can live in the dotfiles tree too.

    ```json
    // <dotfiles>/iterm2/DynamicProfiles/work-ssh.json
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

    ### Shell integration

    iTerm2 shell integration is a set of shell functions and escape
    sequences that tell the terminal where prompts begin, when commands
    start and finish, what exit code they returned, and what the current
    working directory is. Once installed, iTerm2 gains capabilities not
    possible with a dumb terminal:

    - Cmd-Shift-up/Cmd-Shift-down to jump between prompts in the scrollback
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

    ### Session logging

    iTerm2 can write the contents of every session to disk. There are
    two distinct mechanisms — automatic per-profile logging and on-demand
    toggling — plus an in-memory replay that writes nothing.

    **Automatic logging** is a per-profile setting:
    **Settings > Profiles > Session > Automatically log session input to
    files in**. Point it at a directory and every session opened with that
    profile is captured. The filename is an interpolated string, so you can
    template it per session, date, and hostname:

    ```text
    \(iterm2.run_id)_\(session.name)_\(session.hostname).log
    ```

    The format toggle alongside it offers three modes:

    - **Plain text** — text and newlines only, control sequences stripped.
      The legible default; greppable, pasteable.
    - **Raw data** — an exact byte copy including every control and color
      escape. Faithful but opaque in a pager.
    - **HTML** — text with colors and font attributes preserved, escapes
      stripped. Useful when you want the rendered look in a browser.

    Prefer **Plain text** unless you specifically need color fidelity.

    **On-demand logging** captures a single session without committing a
    whole profile to it. Toggle it from **Session > Log > Start** in the
    menu bar (or the Toolbelt). Use this for the occasional "capture this
    one debugging run" rather than logging everything you ever type.

    **Instant Replay** (`Cmd-Opt-B`) is the third option and writes no
    file at all — it scrubs backward through what the terminal rendered,
    held in a memory ring buffer. Reach for it when you saw something flash
    past and just need to read it again, not archive it.

    !!! danger "Logs are plaintext secrets on disk"

        Automatic logging captures *everything* the session prints —
        including `export AWS_SECRET_ACCESS_KEY=...`, tokens echoed by a
        misbehaving tool, `op read` output, and anything a heredoc spills.
        These land unencrypted in your log directory and persist after the
        session ends.

        Keep log files **out of version control and off any synced
        directory**. If the log directory lives anywhere near your
        dotfiles tree, add it to `.gitignore`; better, point logging at a
        path under `$XDG_STATE_HOME` (e.g. `~/.local/state/iterm2/logs/`),
        which the framework already treats as machine-local and
        non-versioned. Automatic logging trades the safety of ephemeral
        scrollback for a durable on-disk record — turn it on per profile
        deliberately, not globally.

    ### Triggers

    Triggers run an action when a regular expression matches a line of
    output. They are configured per profile at
    **Settings > Profiles > Advanced > Triggers**. Each trigger is a regex
    plus an action, and the capture groups are available to the action.
    Common uses that fit this framework's automation bent:

    - **Highlight** matching text (color errors red, warnings yellow)
      without any tool needing to emit color itself.
    - **Capture** matched lines into the Toolbelt's Captured Output pane —
      a running list of, say, every `FAILED` test you can click to jump
      back to.
    - **Post a notification** when a long build prints its done line, so
      you can leave the window in the background.
    - **Run a Coprocess** — pipe the matched line to an external command
      whose output is injected back into the terminal.

    Triggers live in the profile, so they serialize into
    `com.googlecode.iterm2.plist` and version-control alongside everything
    else. Define them in a base profile to inherit everywhere.

    ### Smart selection and Semantic History

    **Semantic History** is the Cmd-click-to-open behavior, configured at
    **Settings > Profiles > Advanced > Semantic History**. Set it to
    "Open with editor..." to send text files to your configured editor, or
    "Run command..." for full control. In the command form, iTerm2
    substitutes `\1` for the filename, `\2` for the line number, and `\5`
    for the working directory — so a stack trace or `rg` hit that prints
    `path/to/file.rb:42` opens directly at the line:

    ```sh
    # Semantic History "Run command..." — open at the matched line in vim
    vim +\2 \1
    ```

    This pairs with the framework's editor configuration: the same
    `$EDITOR` you use everywhere becomes the click target.

    **Smart Selection** governs what a double/quadruple-click grabs.
    iTerm2 ships rules for URLs, paths, and email addresses, and you can
    add your own regex rules at
    **Settings > Profiles > Advanced > Smart Selection** — for example, a
    rule that selects a Jira ticket key or a full `git` SHA as one unit.
    Smart Selection rules can also carry actions, overlapping with
    Semantic History for click-to-act behavior.

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

    This integration mode is macOS-only. On Linux, tmux runs directly
    inside the terminal emulator with its own pane and window rendering.

=== "Linux"

    **Use WezTerm.** It is the framework's recommended Linux terminal,
    and the recommendation turns on a principle, not taste: WezTerm
    integrates from the *shell* side, on the framework's terms.
    `conf.d/25-tool-cache.zsh` loads WezTerm's integration when
    `$TERM_PROGRAM` is `WezTerm`, giving you OSC 7/133 semantics — prompt
    marks, command timing, working-directory tracking — through the same
    gated loader that handles every other tool. The shell startup chain
    stays in control of itself. It is also the same emulator you can run
    on macOS, so a single Lua config follows you across every machine.

    ```sh
    # Debian/Ubuntu (from the WezTerm APT repo)
    curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/wezterm.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/wezterm.gpg] https://apt.fury.io/wez/ * *' | \
      sudo tee /etc/apt/sources.list.d/wezterm.list
    sudo apt update && sudo apt install wezterm

    # Fedora (Copr)
    sudo dnf copr enable wezfurlong/wezterm-nightly
    sudo dnf install wezterm
    ```

    Configuration is Lua at `~/.config/wezterm/wezterm.lua` — programmable,
    version-controllable, and diffable. WezTerm ships a built-in
    multiplexer, so tmux is optional for purely local work; we still run
    tmux (see below) because it owns remote sessions that must survive an
    SSH drop, and keeping one multiplexer for both local and remote avoids
    two muscle-memory sets.

    #### Recommended settings

    A starter `~/.config/wezterm/wezterm.lua` covering the settings worth
    changing from WezTerm's defaults for this framework:

    ```lua
    local wezterm = require 'wezterm'
    local config = wezterm.config_builder()

    -- Scrollback: match the 100k tmux history. A short buffer means
    -- re-running commands to see output you already produced.
    config.scrollback_lines = 100000

    -- Font: a Nerd Font so prompt/CLI glyphs render instead of tofu.
    -- font_with_fallback degrades gracefully if the first is absent.
    config.font = wezterm.font_with_fallback {
      'JetBrainsMono Nerd Font',
      'MesloLGS Nerd Font',
    }
    config.font_size = 13.0

    -- Cursor: steady block reads position at a glance, no flicker.
    config.default_cursor_style = 'SteadyBlock'

    -- Get out of tmux's way: WezTerm's own tabs/panes go unused because
    -- tmux owns sessions. Hide the chrome rather than run two systems.
    config.hide_tab_bar_if_only_one_tab = true
    config.enable_scroll_bar = false

    -- Quiet the bell; the visual cue is enough.
    config.audible_bell = 'Disabled'

    return config
    ```

    | Setting | Value | Why |
    |---------|-------|-----|
    | `scrollback_lines` | `100000` | Align with the tmux 100k history. |
    | `font` (Nerd Font) | `JetBrainsMono Nerd Font` + fallback | Render git/devicon glyphs instead of tofu boxes. |
    | `default_cursor_style` | `SteadyBlock` | Position legible at a glance, no blink flicker. |
    | `hide_tab_bar_if_only_one_tab` | `true` | tmux owns sessions; don't surface WezTerm's competing UI. |
    | `audible_bell` | `Disabled` | The visual bell suffices; audible is noise in a busy split. |

    **Identity separation.** Because the config is code, branch it on the
    machine instead of maintaining separate profiles. Key the color scheme
    (and an optional window title prefix) off the hostname or an env var
    so a work box and a personal box are visibly different the moment a
    window opens — the same work/personal signal the iTerm2 badge gives on
    macOS:

    ```lua
    local host = wezterm.hostname()
    if host:find 'work' then
      config.color_scheme = 'Catppuccin Frappe'   -- work: cooler palette
    else
      config.color_scheme = 'Catppuccin Macchiato' -- personal: warmer
    end
    ```

    !!! note "Where WezTerm is the weaker choice"

        The recommendation is honest about its cost. WezTerm is the
        heaviest of the mainstream options: GPU-driven, larger memory
        footprint, and a Lua config that is more to learn than an INI or
        TOML file. If that weight is the wrong trade for you, **Alacritty**
        is the reasonable alternative — minimalist, fastest startup, TOML
        config at `~/.config/alacritty/alacritty.toml`, no multiplexer by
        design (which pairs cleanly with the framework's "tmux owns
        sessions" model). Its cost is that it is deliberately
        feature-frozen and trails on protocol support. Note that it is
        **not wired into the framework's shell-integration loader**, so you
        would set up OSC 7/133 yourself. Install: `sudo apt install
        alacritty` / `sudo dnf install alacritty`.

    !!! warning "Why not Kitty"

        Kitty is the most protocol-forward emulator on Linux — it authored
        the graphics and keyboard protocols newer TUIs are adopting — so
        on a "forward-thinking, not legacy bloat" reading it looks like the
        obvious pick. The framework passes it over anyway, for one specific
        reason: **Kitty's zsh integration injects itself by hijacking
        `ZDOTDIR`.**

        Kitty enables shell integration from the *terminal* side. For zsh
        it does this by pointing `ZDOTDIR` at its own bundled startup
        directory, sourcing kitty's `.zshenv`, then restoring your
        `ZDOTDIR` and chaining onward. That is precisely the move this
        framework refuses to allow. The entire startup contract pivots on
        `~/.zshenv` owning `ZDOTDIR` and the `conf.d/` chain flowing
        deterministically from it — and `bootstrap.sh` actively audits
        startup files for exactly this class of third-party injection,
        flagging it `[rogue]`. An emulator that rewrites `ZDOTDIR` to slip
        its own code into the boot path is the same pattern, blessed by the
        vendor. We do not make an exception for it.

        Kitty offers `shell_integration no-rc`, which leaves the launch
        environment untouched — and with that set, Kitty is usable here.
        But it means turning off the one feature Kitty leads on and
        configuring integration the framework's way regardless, at which
        point WezTerm is the better-aligned tool with nothing to disable.
        The protocol lead is real; it does not outweigh keeping the shell
        startup chain authoritative.

    All three read `$TERM` correctly, support 24-bit color, and work with
    the framework's tmux configuration without modification. The
    difference that decides it is integration discipline: only WezTerm
    integrates without reaching into the boot path.

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
tmux new-session -d -s "$SESSION" -c ~/development/work/repos/myproject
tmux send-keys -t "$SESSION" "mise run dev" C-m
tmux split-window -t "$SESSION" -v -c ~/development/work/repos/myproject
tmux send-keys -t "$SESSION" "mise run test --watch" C-m
tmux attach -t "$SESSION"
```

For declarative configs, **tmuxp** reads YAML session definitions.
Install via mise — add `tmuxp = "latest"` to `mise/config.toml` (never
`mise use -g`, which rewrites the symlinked global config).

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
