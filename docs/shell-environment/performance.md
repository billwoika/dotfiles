# Startup Performance

A well-structured zsh config should start in under 100ms on modern
hardware. The primary sources of latency are: (1) compinit cache
rebuilds, (2) eval subshells for tool initialization, and (3)
unconditional source calls to large files. The
[architecture](architecture.md) and
[shell integration strategy](integration-strategy.md) pages address
these directly. This page covers profiling and the remaining
optimization surface.

!!! note "mise activation cost vs. proto"

    `mise activate` is comparable to `proto activate` in cost — both
    are single eval calls that register a precmd hook. What differs is
    downstream: mise's hook also evaluates project env vars and task
    definitions on `cd`, where proto required a separate direnv hook
    for the same job. Net effect on a typical project `cd`: about the
    same. Net effect on cold startup: slightly faster, because mise
    replaces both proto and direnv in one eval rather than two.

## Profiling with zprof

zsh ships a built-in profiler (`zprof`). Enable it at the top of
`.zshrc`, run a shell, then read the output. The profiler measures
wall time per function call including time spent in child calls.

```sh
# Temporarily add to the TOP of $ZDOTDIR/.zshrc (remove after profiling):
zmodload zsh/zprof

# ... rest of .zshrc (conf.d sourcing) ...

# Temporarily add to the BOTTOM of $ZDOTDIR/.zshrc:
zprof
```

For external timing:

```sh
# Run 10 shells and read the 10 timings (this lists them; it does not
# compute a mean — use hyperfine below for an actual average):
for i in $(seq 10); do /usr/bin/time zsh -lic exit; done 2>&1

# Or use hyperfine if available:
hyperfine --warmup 3 "zsh -lic exit"
```

## Lazy eval: deferred tool initialization

Some tools' init scripts are slow because they do work beyond
registering shell hooks — they may spawn subshells, read config
files, or call external binaries. For tools used infrequently,
initialization can be deferred to first use with a stub function
pattern:

```zsh
# conf.d/70-tools.zsh addition: lazy zoxide initialization
# Instead of: eval "$(zoxide init zsh)"
# Use a stub that initializes on first call:
_zoxide_lazy_init() {
  unfunction _zoxide_lazy_init cd z    # Remove stubs
  eval "$(zoxide init zsh --cmd cd)"    # Real init
  cd "$@"                                # Execute the original call
}

# Only use lazy init if zoxide adds measurable latency (>20ms).
# For most systems, direct eval is fast enough — measure first.
if command -v zoxide &>/dev/null; then
  functions[cd]=_zoxide_lazy_init
  functions[z]=_zoxide_lazy_init
fi
```

The version-hashed cache in
[shell integration strategy](integration-strategy.md) is the
framework's preferred approach for most tools. Lazy init is the
fallback for tools that genuinely need runtime state and can't be
cached.

## Performance benchmarks by component

Target timings for each configuration section on a 2023+ machine:

| Component | Target | Red Flag | Primary Optimization |
|-----------|--------|----------|---------------------|
| `compinit` (cache hit) | < 5ms | > 30ms | 24h cache + `-C` flag |
| `compinit` (cache miss) | < 150ms | > 300ms | Delete stale `.zcompdump` |
| `mise activate` eval | < 20ms | > 60ms | Guard with `command -v` |
| `rv shell` eval | < 10ms | > 40ms | Guard with `command -v` |
| `direnv hook` eval | < 5ms | > 20ms | Guard with `command -v` |
| `starship init` eval | < 15ms | > 50ms | Version-hashed cache |
| `fzf --zsh` eval | < 5ms | > 20ms | Version-hashed cache |
| `conf.d` sourcing (all) | < 20ms | > 80ms | Remove unused fragments |
| **Total interactive startup** | **< 80ms** | **> 200ms** | **Profile with zprof** |

When a component lands in the "red flag" column, the diagnostic path
is: `zprof` to confirm which function is slow, then check whether the
tool can be moved from Tier 1 (live eval) to Tier 2 (version-hashed
cache) in the [shell integration strategy](integration-strategy.md).
