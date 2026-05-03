# Shell Integration Strategy

Tools want to add themselves to your shell, and they do so in ways
that are easy to confuse. `mise activate` emits a precmd hook.
`kubectl completion zsh` emits a static completion function.
`bun install` writes a literal `export PATH=` line into your `.zshrc`.
`fzf --zsh` emits a mix of widgets, keybindings, and completions all
in one blob. iTerm2's "Install Shell Integration" writes a
download-and-source line that re-evaluates a 1500-line file on every
shell start. Each of these is a *different kind of thing*, and the
right place for each in the framework is different.

This page establishes a five-tier taxonomy for shell injections, a
concrete caching strategy that converts most "eval at startup"
patterns into deterministic file sources, and a defense-in-depth
posture against installers that modify your shell config without
permission.

## Taxonomy of shell injections

Five categories, each with a distinct lifecycle and a distinct resting
place in the framework:

| Tier | What | Examples | Where it lives |
|------|------|----------|----------------|
| 1 | Live activation hooks | mise, direnv, rv, ssh-agent priming | `70-tools.zsh` (eval at startup) |
| 2 | Deterministic init / completion output | kubectl, bun, gh, mise, uv, starship, zoxide, fzf | `25-tool-cache.zsh` (version-hashed cache) |
| 3 | Static PATH/env additions | bun, cargo, rustup, volta | `10-path.zsh` (declarative) |
| 4 | Editor/terminal integrations | iTerm2, WezTerm, VS Code, JetBrains | `25-tool-cache.zsh` gated by `$TERM_PROGRAM` |
| 5 | Hostile / forced injections | nvm, rustup default, some IDE installers | Repelled — see [installer behavior](installer-behavior.md) |

The dividing line between Tier 1 and Tier 2 is not "hook vs
completion." It is **needs runtime context vs deterministic per binary
version**. `mise activate` is Tier 1 because it must inspect the
current directory at every prompt; the output of `starship init zsh`,
although also a hook installer, is Tier 2 because the output is
identical for every invocation of the same Starship binary. The
latter belongs in the cache.

## Tier 1: live activation hooks

The framework's `conf.d/70-tools.zsh` handles this tier. The rule for
inclusion: the tool must inspect runtime state at every prompt or
every `cd`. If it doesn't, it does not belong here.

- **`mise activate`** — reads the current directory's `mise.toml`
  every `cd`
- **`direnv hook`** — evaluates the `.envrc` of every directory you
  enter
- **`rv shell`** — reads `.ruby-version` on `cd`
- **SSH ControlMaster directory creation** — trivially fast, runs once
  per shell

Everything else that might seem like it belongs in `70-tools.zsh`
via `eval "$(tool init zsh)"` — starship, fzf, zoxide, completions —
belongs in Tier 2.

## Tier 2: version-hashed cache

The single biggest startup-latency improvement available to a
multi-tool zsh setup is to stop running `tool init` subprocesses on
every shell start. The output is deterministic per binary version;
the right behavior is to capture it once and source the file
thereafter, regenerating only when the binary changes.

!!! info "What this saves"

    On a typical machine with mise + uv + bun + gh + kubectl +
    starship + fzf + zoxide installed, naive `eval "$(tool init)"`
    for each costs roughly 60-150ms per shell start — most of it
    spent forking subprocesses to regenerate identical output. The
    cache approach replaces that with N file sources at ~1ms each.

### How the cache works

Each tool entry records a tool name, the command that emits its zsh
code, and an optional gate. On every shell start, for each entry the
loader:

1. Checks whether the tool is on PATH (skip silently if not)
2. Computes a short hash of `tool --version` output
3. Looks up the cache file at
   `${XDG_CACHE_HOME}/zsh/tool-injections/<tool>.<hash>.zsh`
4. **On miss:** removes any older versions of the cache, runs the emit
   command, writes the new file
5. Sources the file

Cache hits are free — a stat, a hash compare, a source. Cache misses
(which only happen on tool upgrade) cost the same as the original
eval, but happen once per upgrade, not once per shell.

### The tool registry

The cache loader lives in `conf.d/25-tool-cache.zsh`. It loads after
`20-completion.zsh` (so `compinit` has run and tools' `compdef` calls
work) but before `70-tools.zsh` (so prompts and hooks see the
completed environment).

```zsh
typeset -gA _ZSHTOOL_CACHE_ENTRIES=(
  starship       "starship init zsh"
  zoxide         "zoxide init zsh --cmd cd"
  fzf            "fzf --zsh"
  mise-comp      "mise completion zsh"
  uv-comp        "uv generate-shell-completion zsh"
  uvx-comp       "uvx --generate-shell-completion zsh"
  bun-comp       "bun completions"
  gh-comp        "gh completion -s zsh"
  kubectl-comp   "kubectl completion zsh"
  rv-comp        "rv completions zsh"
  docker-comp    "docker completion zsh"
)
```

Adding a new tool is a two-line change: add an entry to
`_ZSHTOOL_CACHE_ENTRIES` and a binary mapping to
`_ZSHTOOL_CACHE_BINARY`.

### Cache management commands

The framework provides two commands for debugging and maintenance:

```sh
# Clear all cached injections (next shell regenerates everything)
zshtool-cache-rebuild

# Clear a specific tool's cache
zshtool-cache-rebuild starship

# Print current cache state
zshtool-cache-status
```

## Tier 3: static PATH/env additions

Static additions — `CARGO_HOME/bin` in PATH, `GOPATH` exports — are
handled declaratively in `conf.d/10-path.zsh` with `typeset -U path`
for deduplication. These never change at runtime, so there's nothing
to eval. The [POSIX profile](posix-profile.md) mirrors the same
additions for non-zsh subprocesses.

## Tier 4: editor and terminal integrations

Static integration scripts shipped by host programs (iTerm2 shell
integration, WezTerm helpers) are loaded through the same cache
mechanism but gated by environment variables that the host sets:

```zsh
# iTerm2 — only inside iTerm2 (LC_TERMINAL is set by the terminal)
_zshtool_editor_load "iterm2" \
  "${LC_TERMINAL:#iTerm2}" \
  "${XDG_CONFIG_HOME}/iterm2/shell_integration.zsh"

# WezTerm — OSC 7/133 helpers, useful in shells under WezTerm
_zshtool_editor_load "wezterm" \
  "${TERM_PROGRAM:#WezTerm}" \
  "${XDG_CONFIG_HOME}/wezterm/wezterm.sh"
```

The loader hashes the script contents directly (rather than a
`--version` invocation) and caches the result. The gate variable
ensures the integration loads only when the host program is the active
terminal.

VS Code and Cursor inject their integration via
`VSCODE_INJECTION=1` when the IDE's setting is enabled. The framework
detects this for downstream conditionals but doesn't install
integration itself.

## Tier 5: defending against hostile installers

Some installers write to your shell profiles without asking. The
framework's defense is layered:

**Symlink-as-tripwire.** Because `~/.zshenv` and `~/.zshrc` are
symlinks into the dotfiles repo (not regular files), installers that
append to them modify the tracked source. A `git diff` after any
installation immediately reveals unauthorized writes.

**The bootstrap.sh audit hook.** The bootstrap installer scans shell startup
files for rogue injections from known offenders (`NVM_DIR`,
`VOLTA_HOME`, `BUN_INSTALL`, `cargo/env`, `pyenv init`, `asdf.sh`,
`conda init`). Run it after any tool installation.

**Installer flags worth memorizing:**

| Tool | Flag | Effect |
|------|------|--------|
| rustup | `--no-modify-path` | Skips all profile writes |
| nvm | `--no-use` | Installs without modifying profiles |
| Homebrew | *(none needed)* | Prints instructions only |
| mise | *(base URL only)* | Binary-only, no profile injection |

## Performance validation

After making changes to the cache or tool integration, verify startup
performance hasn't regressed:

```sh
# Quick check
hyperfine --warmup 3 "zsh -lic exit"

# Detailed profiling
# Add to top of .zshrc: zmodload zsh/zprof
# Add to bottom of .zshrc: zprof
```

Target: under 80ms total interactive startup. See the
[performance](performance.md) page for per-component benchmarks.

## When a tool doesn't fit the pattern

If a new tool doesn't fall cleanly into one of the five tiers:

1. **Measure its init cost** with `time zsh -c 'eval "$(tool init zsh)"'`
2. If < 5ms, it's cheap enough for Tier 1 (live eval in
   `70-tools.zsh`)
3. If > 5ms and deterministic per version, it belongs in Tier 2 (add
   to the cache registry)
4. If it's a static PATH/env change, it belongs in Tier 3
   (`10-path.zsh`)
5. If it's gated by a terminal/editor environment variable, it belongs
   in Tier 4

The framework's bias is toward Tier 2 — most tools' init output is
deterministic, and caching it removes the startup cost entirely.
