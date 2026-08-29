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

=== "Linux: Ptyxis"

    **Use Ptyxis.** It is Fedora's default terminal (since 41), which
    means the recommendation costs nothing: zero install, official
    repo, GNOME-maintained, updated with the distro. It is VTE 0.84
    underneath — truecolor, OSC 7 working-directory tracking, OSC 8
    hyperlinks, OSC 133 prompt marks — and it is container-first: a
    tab can open directly into a toolbox/distrobox container, with the
    host and each container presented as peers in the new-tab menu.

    The deeper reason it fits this framework: Ptyxis satisfies the
    integration principle that disqualified Kitty (see the alternatives
    tab). It never touches the shell's boot path. It reads what the
    shell chooses to emit, and nothing else.

    ### Shell integration: the framework emits, Ptyxis listens

    Fedora's own answer to terminal integration is
    `/etc/profile.d/vte.sh` — a well-behaved script that emits OSC 7
    and OSC 133 from precmd/preexec hooks. But it only reaches zsh
    through `/etc/zprofile`, which runs in **login shells**, and
    Ptyxis (like most GUI terminals) spawns non-login shells by
    default. Net effect on a stock Fedora + zsh setup: no integration
    at all, silently.

    The framework closes the gap on its own terms:
    `conf.d/26-terminal-osc.zsh` emits OSC 7 (percent-encoded cwd) and
    OSC 133 (prompt start / output start / command done + exit code)
    from native zsh hooks — ~30 lines, no vendor script, works in
    *any* terminal that understands the sequences. It defers to
    integrations that already emit them (vte.sh in a login shell,
    iTerm2's and WezTerm's scripts from `25-tool-cache.zsh`, VS Code's
    injection, kitty's opt-in), so nothing double-fires.

    What that buys in Ptyxis today: **new tabs and windows open in
    your current directory** (the `preserve-directory` setting honors
    OSC 7), and correct directory behavior when detaching tabs. The
    OSC 133 marks are cheap future-proofing — Ptyxis does not yet
    expose prompt-jumping UI, but tmux ≥3.4 uses the same marks for
    copy-mode prompt navigation, and WezTerm/kitty/iTerm2 all light up
    on them if you ever sit in front of one.

    ### Recommended settings

    Ptyxis is configured through GSettings — there is no config file
    to symlink, but that makes every setting scriptable.
    `mise run dotfiles:ptyxis` applies the framework's defaults
    idempotently to the app schema and the current default profile:

    | Setting | Key | Value | Why |
    |---------|-----|-------|-----|
    | Silence the bell | `audible-bell` | `false` | The visual bell stays on; sound is noise in a busy session. |
    | Steady cursor | `cursor-blink-mode` | `'off'` | A non-blinking block reads position at a glance. |
    | No blinking text | `text-blink-mode` | `'never'` | TUIs that blink are asking for attention they haven't earned. |
    | Deep scrollback | `scrollback-lines` | `100000` | Match the 100k tmux/iTerm2 history. The 10k default forces re-running commands to see output you already produced. |
    | Follow the shell's cwd | `preserve-directory` | `'safe'` | Honors the OSC 7 the framework emits; `safe` skips it for custom commands. |

    Deliberately not applied (personal, the task prints hints
    instead): font, palette, opacity, `interface-style`.

    **Font.** Same stance as iTerm2 on macOS: a Nerd Font, so prompt
    and CLI glyphs render instead of tofu. Fedora doesn't package the
    patched builds — drop one into `~/.local/share/fonts` and
    `fc-cache -f`, then:

    ```sh
    gsettings set org.gnome.Ptyxis use-system-font false
    gsettings set org.gnome.Ptyxis font-name 'JetBrainsMono Nerd Font 13'
    ```

    ### Version-controlling a GSettings app

    The full configuration surface — every profile, every shortcut —
    round-trips through dconf:

    ```sh
    # Capture (review before committing; contains window geometry too)
    dconf dump /org/gnome/Ptyxis/ > ptyxis-settings.dconf

    # Restore on a new machine (merges; existing keys win only if absent)
    dconf load /org/gnome/Ptyxis/ < ptyxis-settings.dconf
    ```

    The framework deliberately does **not** commit a dconf snapshot:
    profile UUIDs and window geometry are machine-local noise, and the
    settings worth converging are already expressed executably in
    `dotfiles:ptyxis`. Desired state lives in the task; `dconf dump`
    is for ad-hoc backup before experimenting.

    ### Identity separation

    The iTerm2 badge trick, Ptyxis-style: create a second profile
    (Preferences → Profiles → +), give it the `label` "WORK" and a
    visibly different palette, then launch work terminals into it
    directly:

    ```sh
    # Find its UUID, then open work tabs with it
    gsettings get org.gnome.Ptyxis profile-uuids
    ptyxis --tab-with-profile=<uuid> -d ~/development/work
    ```

    A `.desktop` launcher wrapping that command gives you a separate
    dock icon per identity — the cheapest possible "am I in the work
    context?" signal.

    ### Tips and tricks

    - **Tab overview** — ++ctrl+shift+o++ shows every tab as a card,
      live. With `restore-session true` (default, blessed) Ptyxis
      reopens your whole layout on login; the overview is how you find
      things again.
    - **Direct tab access** — ++alt+1++ … ++alt+9++, ++alt+0++ for tab
      10. ++ctrl+shift+alt+t++ reopens a just-closed tab, scrollback
      intact.
    - **Zoom** is per-tab: ++ctrl++ + scroll wheel (or ++ctrl+plus++ /
      ++ctrl+minus++ / ++ctrl+0++). Pair-programming font size without
      touching settings.
    - **Custom links** — Ptyxis's answer to iTerm2 Smart Selection:
      per-profile regex → URL rewrites, so ticket IDs in any command
      output become clickable:

        ```sh
        gsettings set \
          org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$(gsettings get org.gnome.Ptyxis default-profile-uuid | tr -d \')/ \
          custom-links "[('JIRA-[0-9]+', 'https://jira.example.com/browse/\\0')]"
        ```

    - **Process-aware chrome** — `visual-process-leader` (default on)
      tints the window header when the foreground process is `ssh` or
      `sudo`. You get a "this shell is not what it looks like" signal
      for free — leave it on.
    - **Containers** — the new-tab button's dropdown lists every
      toolbox/distrobox alongside the host; a profile's
      `default-container` pins it permanently. This is the feature no
      other emulator has natively, and on a Fedora box that uses
      toolbox for experiments it removes the `toolbox enter` dance.
    - **Scripting the window** — `ptyxis --tab -d "$PWD"`,
      `ptyxis -x 'journalctl -f'`, `--title`, `--standalone` for an
      isolated instance. Project launchers compose from these.
    - **OSC 8 hyperlinks** — VTE renders real hyperlinks;
      ++ctrl++-click opens them. `ls --hyperlink=auto` makes every
      filename clickable; `rg --hyperlink-format=default` does the
      same for match locations.
    - **Remote terminfo just works** — Ptyxis sets
      `TERM=xterm-256color`, which every server on earth has terminfo
      for. kitty (`xterm-kitty`) and foot (`foot`) both require their
      terminfo shipped to every SSH target before `clear` stops
      erroring. This is a real, recurring cost the fancy-TERM
      emulators charge and Ptyxis doesn't.

=== "Linux: alternatives"

    Ptyxis is the default because it is preinstalled, principled, and
    sufficient. Two alternatives are worth naming, and one is worth
    rejecting.

    ### WezTerm — the power option

    WezTerm integrates from the *shell* side on the framework's terms —
    `25-tool-cache.zsh` loads its integration when `$TERM_PROGRAM` is
    `WezTerm` — and adds what Ptyxis lacks: OSC 133 prompt-jumping UI,
    a built-in multiplexer, ligatures, and a programmable Lua config
    that version-controls cleanly and runs identically on macOS.

    Its cost on Fedora is the install channel: WezTerm is **not in the
    official repos** — the practical route is a *nightly Copr*
    (`dnf copr enable wezfurlong/wezterm-nightly`). That is exactly
    the class of third-party dependency this framework avoids
    elsewhere (it is why `[bootstrap.packages]` ships `ffmpeg-free`,
    not RPM Fusion's ffmpeg). If you adopt WezTerm anyway, adopt the
    Copr knowingly:

    ```sh
    # Debian/Ubuntu (WezTerm APT repo)
    curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/wezterm.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/wezterm.gpg] https://apt.fury.io/wez/ * *' | \
      sudo tee /etc/apt/sources.list.d/wezterm.list
    sudo apt update && sudo apt install wezterm

    # Fedora (Copr — nightly; no stable channel exists)
    sudo dnf copr enable wezfurlong/wezterm-nightly
    sudo dnf install wezterm
    ```

    A starter `~/.config/wezterm/wezterm.lua` with the framework's
    settings:

    ```lua
    local wezterm = require 'wezterm'
    local config = wezterm.config_builder()

    config.scrollback_lines = 100000          -- match tmux history
    config.font = wezterm.font_with_fallback {
      'JetBrainsMono Nerd Font', 'MesloLGS Nerd Font',
    }
    config.font_size = 13.0
    config.default_cursor_style = 'SteadyBlock'
    config.hide_tab_bar_if_only_one_tab = true -- tmux owns sessions
    config.enable_scroll_bar = false
    config.audible_bell = 'Disabled'

    -- Identity separation: key the palette off the host, the same
    -- work/personal signal the Ptyxis profile label gives.
    if wezterm.hostname():find 'work' then
      config.color_scheme = 'Catppuccin Frappe'
    else
      config.color_scheme = 'Catppuccin Macchiato'
    end

    return config
    ```

    ### Alacritty — the minimalist

    In the official repos (`sudo dnf install alacritty`), fastest
    startup, TOML config, no multiplexer by design — which pairs
    cleanly with "tmux owns sessions." Deliberately feature-frozen and
    trails on protocol support. It emits no integration of its own,
    but that no longer matters here: `conf.d/26-terminal-osc.zsh`
    supplies OSC 7/133 from the shell side, so Alacritty gets cwd
    tracking for free.

    ### Kitty — rejected, still

    Kitty is the most protocol-forward emulator on Linux — it authored
    the graphics and keyboard protocols newer TUIs are adopting — so
    on a "forward-thinking, not legacy bloat" reading it looks like
    the obvious pick. The framework passes it over anyway, for one
    specific reason: **Kitty's zsh integration injects itself by
    hijacking `ZDOTDIR`.**

    Kitty enables shell integration from the *terminal* side. For zsh
    it points `ZDOTDIR` at its own bundled startup directory, sources
    kitty's `.zshenv`, then restores your `ZDOTDIR` and chains onward.
    That is precisely the move this framework refuses to allow. The
    startup contract pivots on `~/.zshenv` owning `ZDOTDIR` and the
    `conf.d/` chain flowing deterministically from it — and
    `bootstrap.sh` audits startup files for exactly this class of
    third-party injection, flagging it `[rogue]`. An emulator that
    rewrites `ZDOTDIR` to slip its own code into the boot path is the
    same pattern, blessed by the vendor. No exception.

    With `shell_integration no-rc` set, Kitty leaves the launch
    environment alone and becomes usable here — and
    `26-terminal-osc.zsh` now supplies the OSC 7/133 marks its UI
    consumes, so less is lost than before. But you are still turning
    off the flagship feature and installing a custom-`TERM` emulator
    (`xterm-kitty` terminfo on every SSH target) to get what Ptyxis
    ships by default. The protocol lead is real; it does not outweigh
    keeping the shell startup chain authoritative.

    ---

    All of these read `$TERM` correctly, support 24-bit color, and
    work with the framework's tmux configuration unmodified. The
    deciding line is unchanged: integration happens on the shell's
    terms — the framework emits, the terminal listens.

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
