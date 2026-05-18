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

bun is the JavaScript **package manager** for JS/TS projects in this
stack. It replaces npm, yarn, and pnpm with a dramatically faster
alternative — installs are near-instant, the lockfile is deterministic,
and the CLI is a drop-in replacement for `npm` commands.

!!! warning "A position change from earlier versions"

    Previous versions of this framework advocated bun as a full
    runtime replacement for Node — package manager, bundler, test
    runner, and server runtime in one binary. That position was
    premature. Bun's **package manager** is mature and production-ready.
    Bun's **runtime** is not — it has native binding incompatibilities
    that break real-world toolchains in ways that are difficult to
    diagnose and impossible to work around.

    The framework now recommends: **bun for package management, Node
    for runtime execution.** This is the architecture the broader
    ecosystem has converged on and the one that actually works in
    production.

### Why the runtime isn't ready

Bun markets itself as a drop-in Node replacement, but its runtime
has fundamental compatibility gaps with the native module ecosystem:

- **Native bindings break.** Packages that use N-API or native addons
  compiled for Node's V8 runtime do not work under Bun's JavaScriptCore
  runtime. The most consequential example: `@tailwindcss/oxide` (the
  Rust-compiled core of Tailwind CSS v4) does not load under Bun. This
  means any project using Tailwind CSS cannot run its build toolchain
  under Bun's runtime.
- **Vite under Bun is degraded.** Running Vite via `bun run dev`
  executes Vite's process under Bun's runtime rather than Node. HMR
  becomes a full-page remount instead of state-preserving hot module
  replacement. Vue Single File Component support is hobby-project-tier.
  Dev proxy configuration has gaps.
- **The errors are silent.** When a native binding fails to load under
  Bun, the error messages are often opaque or misleading — a segfault,
  a missing symbol, or a cryptic "cannot find module" for a package
  that is clearly installed. You lose hours before realizing the issue
  is the runtime, not your code.

### The correct architecture

```
bun = package manager     (bun install, bun add, bun.lock)
Node = runtime            (npx vite, npx vue-tsc, node server.js)
```

This gives you bun's speed for dependency resolution and installation
while using Node's mature, ecosystem-compatible runtime for everything
that actually executes JavaScript. The two coexist cleanly — bun
manages `node_modules/` and the lockfile, Node runs the code.

**Make it explicit in package.json:**

```json
{
  "scripts": {
    "dev": "npx vite",
    "build": "npx vue-tsc --noEmit && npx vite build",
    "preview": "npx vite preview",
    "test": "npx vitest"
  }
}
```

The `npx` prefix ensures Node runs the tool even when `bun run dev`
is the invocation (bun delegates to the script content, `npx` invokes
Node). This prevents accidental execution under Bun's runtime.

**In Dockerfiles, the same pattern:**

```dockerfile
FROM node:22-slim
# Install bun for package management only
RUN npm install -g bun
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile
COPY . .
RUN npx vite build
```

### What bun is excellent for

As a package manager, bun is genuinely superior:

- **Install speed** — 10-100x faster than npm for cold installs.
  Near-instant for warm installs with a populated cache.
- **Deterministic lockfile** — `bun.lock` is human-readable text,
  fast to parse, and guarantees identical `node_modules/` across
  machines.
- **Drop-in compatibility** — reads `package.json`, resolves from
  npm registry, produces a standard `node_modules/` directory that
  Node runs against.
- **Workspace support** — monorepo workspaces work correctly.

### Project setup

```sh
bun init
bun add hono
bun add -d typescript @types/bun biome vite

# CI-safe install: exits non-zero if lockfile would change
bun install --frozen-lockfile
```

### bun.lock

`bun.lock` is a human-readable text lockfile (earlier versions of bun
used a binary format — that is no longer the case). Commit it. It is
deterministic, readable for auditing and diffing, and optimized for
fast dependency resolution.

### When bun-as-runtime is acceptable

For scripts and tooling that do not touch native bindings — pure
JavaScript/TypeScript utilities, simple HTTP servers, test runners
for unit tests, and CLI tools — bun's runtime works and is faster
than Node. The restriction is specifically about native addon
compatibility. If your code and its entire dependency tree are pure
JS/TS with no native bindings, `bun run` is fine.

The problem is that you often do not know which of your transitive
dependencies uses native bindings until something breaks. Tailwind
CSS is the canonical example — it's a CSS utility framework that
happens to use a Rust-compiled core, and nothing in your
`tailwind.config.ts` tells you the runtime matters.

**The safe default: use Node as the runtime. Use bun for speed where
you have confirmed it works.**

### The pattern is familiar

This split mirrors the uv/pip situation documented earlier on this
page: uv is the right tool for developer-facing Python workflows, but
`requirements.txt` and `pip install` persist at the CI boundary
because the ecosystem targets them. The framework lives with both,
uses the better tool where it can, and doesn't lose sleep over the
inconsistency.

Bun and Node are the same story. Bun is a Rust-based reimplementation
of the JavaScript toolchain that is faster and more cohesive than the
incumbent — and, like most Rust-based rewrites of mature ecosystems,
it is not yet compatible enough for full production adoption. The
native binding gap will close. Bun's team is actively working on
N-API compatibility and the JavaScriptCore runtime is improving
rapidly. The framework's bet is that bun will eventually absorb the
runtime role too, and this page will simplify accordingly. Until then,
the split is the honest recommendation.

This page will be updated if that bet does not pan out.

!!! note "Team migration from yarn/nvm to bun"

    If your team currently uses yarn and nvm and is gradually adopting
    bun as the package manager, the framework still holds: list `bun`
    and `node` under `[tools]` in your `mise.toml`. bun handles
    `install` and lockfile management; Node runs everything via `npx`.
    Keep `.nvmrc` in repos that teammates share — mise reads it via
    `idiomatic_version_file_enable_tools`. When the project fully
    adopts bun for package management, the `.nvmrc` stays (Node is
    still the runtime) and `bun.lock` replaces `yarn.lock` or
    `package-lock.json`.
