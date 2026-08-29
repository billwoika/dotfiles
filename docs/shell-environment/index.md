# Shell Environment

The shell is the framework's foundation. Every other concern depends on
it: tool resolution, environment variables, prompt formatting,
keybindings, history, completions. The framework's shell architecture
prioritizes three things:

1. **Predictability** — the same dotfiles produce the same shell on
   every machine, every time, with no implicit dependencies on what's
   already installed.
2. **Composability** — configuration is split into small, numbered
   `conf.d/` fragments that load in deterministic order and can be
   added or removed independently.
3. **POSIX compatibility for subprocesses** — non-zsh subprocesses
   (cron jobs, GUI apps spawning shells, container entrypoints) get a
   working environment via `~/.profile`, even though the interactive
   shell is zsh.

## In this section

- **[Philosophy](philosophy.md)** — the four-layer design, what the
  framework includes and what it deliberately excludes.
- **[Architecture](architecture.md)** — the file layout, the `conf.d/`
  pattern, the boot sequence from `zshenv` through `zlogout`, and the
  XDG state directory conventions.
- **[XDG and POSIX Compliance](xdg-and-posix.md)** — the XDG Base
  Directory variables, the `~/.zshenv` bootstrap, and the full
  directory structure.
- **[POSIX Profile](posix-profile.md)** — the `~/.profile`
  compatibility shim for non-zsh subprocesses.
- **[Environment Layer](environment.md)** — mise's `[env]` block for
  project config and secret references, `.env.local` for developer
  overrides, and direnv for sh-logic loading.
- **[Performance](performance.md)** — profiling with `zprof`, lazy
  eval, and per-component benchmark targets.
- **[Installer Behavior](installer-behavior.md)** — how tool
  installers interact with shell profiles, and safe invocation
  patterns for each.
- **[Terminal: iTerm2 and tmux](terminal.md)** — terminal emulator
  configuration, tmux setup, session management, and the nested-tmux
  SSH pattern.
- **[Aliases and Functions](aliases.md)** — the curated alias and
  function library organized by domain.
- **[Shell Integration Strategy](integration-strategy.md)** — the
  five-tier taxonomy for shell injections, the version-hashed cache,
  and defense against hostile installers.

## Why zsh

The framework uses zsh as the interactive shell. The choice predates
this iteration of the framework — zsh is sufficiently more featureful
than bash that it's the better choice for an engineer's primary shell,
and macOS shipping zsh as the default since Catalina removed any
remaining argument for bash compatibility.

The framework does *not* recommend zsh as the `/bin/sh` for scripts.
Scripts that need to be portable should target POSIX `sh`. The
framework's own bootstrap and `~/.profile` are POSIX-compatible
specifically so they work in any subprocess context.
