# Language-Native Package Managers

Runtime version management (mise) and dependency management are
separate concerns. Once mise has resolved the correct `python` or
`bun` binary — or once rv has resolved the correct `ruby` binary —
the language-native tools take over. This separation means mise never
needs to understand gem resolution algorithms, and rv/uv/bun never
need to understand cross-language version switching.

## rv — Ruby version and gem management

rv is a Rust-backed Ruby version and gem manager from the Spinel team
(the same group that maintains Bundler, RubyGems, and rbenv). It is
inspired by uv's approach to Python: a single fast binary that
replaces rvm, rbenv, chruby, asdf-ruby, ruby-build, and ruby-install
with one coherent tool. Precompiled Ruby installs in under a second;
gem operations are an order of magnitude faster than the Ruby-based
alternatives.

!!! note "Why rv for Ruby, and not mise?"

    Two reasons. First, rv is faster and safer than mise's core
    ruby-build-backed plugin: it ships precompiled Ruby binaries with
    signed attestations, avoiding the entire "compile Ruby from
    source" class of problems (OpenSSL mismatches, missing development
    headers, Apple Silicon toolchain gaps). Second, rv's gem-adjacent
    features — `rv clean-install` as a drop-in replacement for
    `bundle install --frozen`, `rv tool install` for isolated CLI
    tools, and `rvx` for ephemeral execution — have no mise equivalent.

    mise reads `.ruby-version` for detection (via idiomatic file
    support), so tool inspection and project navigation work as
    expected. It just doesn't try to install Ruby itself — rv does
    that.

### Installation

```sh
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/spinel-coop/rv/releases/latest/download/rv-installer.sh | sh

# Shell activation is already wired in conf.d/70-tools.zsh:
#   eval "$(rv shell zsh)"

rv --version              # expect: rv 0.5.x or higher
rv ruby list              # list available/installed Ruby versions
```

### Project setup

```sh
rv ruby pin 3.3.4         # writes .ruby-version (committed to VCS)
rv ruby install           # installs the pinned version (precompiled, ~0.5s)

# Gem management — rv clean-install is a faster replacement
# for `bundle install --frozen`, using precompiled gems where possible.
bundle init
bundle add rails --version "~> 8.0"
bundle add rspec --group test
bundle lock

rv clean-install          # also available as: rv ci
```

### Gemfile and bundle configuration

```ruby
# Gemfile  (committed)
source "https://rubygems.org"
ruby "3.3.4"              # matches .ruby-version; rv enforces this

gem "rails", "~> 8.0"
gem "rspec", group: :test
```

Setting `BUNDLE_PATH` inside `.bundle/gems/` keeps project gems
isolated per-project. rv also supports an alternative layout where
gems live under `~/.local/share/rv/gems` keyed by Ruby version and
Gemfile hash.

### Team coexistence with rbenv

If your team uses rbenv, both managers can coexist as long as the
`.ruby-version` file stays consistent:

| Tool | Reads | Installs to | Shim strategy |
|------|-------|-------------|---------------|
| rv (you) | `.ruby-version` + `Gemfile` | `~/.local/share/rv` | PATH manipulation (`rv shell`) |
| rbenv (team) | `.ruby-version` | `~/.rbenv/versions` | Shims in `~/.rbenv/shims` |

`Gemfile.lock` is the shared source of truth for dependencies.

## uv — Python dependency management

uv (Astral) is a Rust-backed Python package and project manager that
replaces pip, pip-tools, virtualenv, and portions of poetry in a
single binary. It is 10-100x faster than pip for most workloads and
produces deterministic lockfiles by default. mise manages the uv binary
version and the Python interpreter; uv manages virtual environments
and dependency resolution.

!!! info "How mise and uv cooperate"

    mise installs the Python interpreter (or reuses one uv already
    installed). With `python.uv_venv_auto = "create|source"` in your
    mise config, `cd` into a project creates and activates `.venv`
    automatically. You can also run `mise sync python --uv` to share
    a single Python installation between the two tools.

### Project initialization

```sh
uv init my-service
cd my-service

uv python pin 3.12.7          # writes .python-version, which mise reads
uv add fastapi uvicorn
uv add --dev pytest ruff mypy
uv sync                        # creates .venv/ in project root
```

### Lockfile strategy

`uv.lock` records the complete resolved dependency graph including
hashes. Commit it. It is the canonical record of what runs in
production. Do not commit `.venv/` — it is regenerated from the
lockfile by `uv sync` in under three seconds on most hardware.

### uv run vs. manual activation

Prefer `uv run <command>` over manually activating the virtual
environment. `uv run` ensures the correct interpreter and
dependencies are active without leaking virtualenv state into parent
shells. When the `python.uv_venv_auto` mise setting is enabled, the
`.venv/bin` directory is prepended to PATH automatically on `cd`,
making explicit activation unnecessary for most workflows.

### When requirements.txt still makes sense

This framework advocates uv for every Python workflow, and the
framework's own docs site uses `uvx --with-requirements` for local
builds. But `docs/requirements.txt` persists in the repo because CI
consumes it via `pip install -r` — and that is a defensible choice,
not a contradiction.

Most GitHub Actions workflows use `setup-python` + `pip`. Astral
publishes a `setup-uv` action, but many teams have not adopted it,
and for a build step that installs three packages and runs once per
push, the runtime difference between pip and uv is negligible. The
value of uv is in developer-facing workflows where resolution speed,
lockfile determinism, and virtual environment management compound
across hundreds of daily invocations. A CI step that runs `pip
install -r requirements.txt` once and exits is not that workflow.

The practical guidance: use `uvx` or `uv run` locally, keep
`requirements.txt` as the lowest-common-denominator format that every
CI platform and deployment pipeline can consume, and do not lose sleep
over the inconsistency. It is the same pragmatism that keeps a
`Makefile` in the repo alongside `mise tasks` — the native tool is
better, but the universal one has value at the boundary.

## bun — JavaScript and TypeScript

bun is the JavaScript runtime, package manager, bundler, and test
runner for all JS/TS projects in this stack. It replaces Node,
npm/yarn/pnpm, Jest, and in most cases webpack/esbuild. The
single-binary design means dependency management, test execution, and
script running are always version-aligned.

!!! note "Team migration from yarn/nvm to bun"

    If your team currently uses yarn and nvm and is gradually adopting
    bun, the framework still holds: list `bun` under `[tools]` in
    your personal `mise.toml`, but keep `.nvmrc` in repos that
    teammates share. mise reads `.nvmrc` via the
    `idiomatic_version_file_enable_tools` setting, so you get correct
    Node resolution for legacy scripts. When the project fully
    migrates to bun, drop `.nvmrc` and add `node` to the `[tools]`
    block only if you need it for tooling that doesn't yet run on
    bun.

### Project initialization

```sh
bun init
bun add hono
bun add -d typescript @types/bun biome

# CI-safe install: exits non-zero if lockfile would change
bun install --frozen-lockfile

bun run dev
bun run test
```

### bun.lock

`bun.lock` is a binary lockfile. Commit it. It is deterministic,
human-unreadable (by design), and optimized for fast dependency
resolution. If you need a human-readable lockfile for auditing, run
`bun install --save-text-lockfile` to produce a text representation
alongside the binary form.

### Replacing npm scripts

bun executes `package.json` scripts natively. For teams migrating
from npm/yarn, the only change needed is replacing `npm run` with
`bun run` and `npx` with `bun x`. There is no global package
installation for CLI tools — use `bun x <tool>` for ephemeral
execution, or add tools as dev dependencies for consistent versioning.
