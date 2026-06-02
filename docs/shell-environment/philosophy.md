# Zsh Configuration Philosophy

The shell is the interactive layer where all tooling is orchestrated.
Most zsh setups fall into one of two failure modes: raw, unstructured
`.zshrc` files that grow into unmaintainable monoliths, or
framework-managed environments (Oh My Zsh, Prezto, Zinit) that trade
a few hours of initial configuration effort for years of implicit
behaviour, update indirection, and startup latency that scales with
plugin count.

This framework describes a third approach: a small, explicit,
self-documenting configuration that a new engineer can read in full
in under ten minutes, that degrades gracefully when tools are absent,
and that adds measurably zero startup latency beyond what zsh itself
requires. Every design decision maps to a POSIX or XDG Base Directory
Specification rationale. Nothing is "magic."

## Four layers

The configuration is structured around four layers, each in its own
file or directory:

| Layer | File | Purpose |
|-------|------|---------|
| Bootstrap | `~/.zshenv` | Always-loaded, minimal, export-only |
| Environment | `$ZDOTDIR/.zshenv` | XDG-located environment and PATH seeds |
| Interactive | `$ZDOTDIR/.zshrc` | Interactive shell settings, sources `conf.d/` fragments |
| Fragments | `$ZDOTDIR/conf.d/` | Modular, single-responsibility configuration |

Each layer has exactly one job. The bootstrap file sets `ZDOTDIR` and
nothing else. The environment file establishes XDG variables and tool
paths. The interactive file is a dispatcher that sources fragments. The
fragments contain the actual configuration.

## What this does not include

**Prompt theming** is intentionally out of scope. Starship (config at
`~/.config/starship.toml` by default — Starship does not honor
`$XDG_CONFIG_HOME`; set `STARSHIP_CONFIG` to relocate it) or a
hand-written `PROMPT` function are both reasonable choices and integrate cleanly
with the config described here.

**Fuzzy finders** (fzf, zoxide) have their eval-based init lines in
a `conf.d/` fragment, as described in the
[shell integration strategy](integration-strategy.md).

**Plugin managers.** No oh-my-zsh, prezto, zinit, antigen. The
`conf.d/` pattern provides composability without the dependency, the
load-time overhead, or the implicit behavior. See the
[Architecture](architecture.md) page for the full argument.
