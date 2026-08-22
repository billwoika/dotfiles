# mise and Make

The framework treats toolchain management and task running as **two
separate concerns** that meet at a clean boundary:

- **mise** owns runtime pinning and toolchain resolution. It tells the
  shell which Ruby, Python, Node, Go, etc., to use for any given
  directory.
- **Make** (or `just`) provides the **universal task-runner entry
  point** — the `make test` that every engineer reflexively types
  when joining an unfamiliar codebase.

mise tasks are the actual implementation; Make is a thin wrapper that
calls them. Both are committed to the project, both are
team-shareable, and the combination gives engineers three discoverable
surfaces (IDE run configs, terminal `mise run`, `make` invocations)
that all converge on the same task definitions.

## mise as the primary toolchain manager

mise replaces the constellation of version managers (asdf, nvm, rbenv,
pyenv) with a single tool that handles all of them. A project's
`mise.toml` declares its runtime versions:

```toml
# mise.toml at project root
[tools]
ruby = "3.3.4"
python = "3.12.5"
node = "22.8.0"
bun = "1.1.27"

# Project-specific tools, pinned the same way
biome = "1.9.4"
ruff = "0.6.9"
just = "1.36.0"
```

When you `cd` into the project, mise's shell hook activates the pinned
versions. When you leave, they deactivate. Subprocesses inherit the
correct versions automatically because mise modifies `$PATH` rather
than relying on shell aliases.

### Why mise over alternatives

- **vs. asdf** — mise is faster (Rust vs Bash), supports `mise.toml`
  natively (asdf only reads `.tool-versions`), and has cleaner
  semantics around tool installation and shimming.
- **vs. per-language tools (rbenv, pyenv, nvm)** — one tool to learn,
  one config format to remember, one set of commands. The
  per-language tools each work fine; running four of them is needless
  cognitive overhead.
- **vs. devbox / nix / flox** — those are more powerful but
  substantially more complex. mise hits the sweet spot for engineers
  who want pinned runtimes without committing to a Nix-style
  declarative-everything model.

### mise tasks

Beyond runtime pinning, mise can also run project-defined tasks:

```toml
# mise.toml
[tasks.test]
description = "Run the test suite"
run = "bundle exec rspec"

[tasks.lint]
description = "Run all linters"
run = ["biome check", "ruff check", "rubocop"]

[tasks.dev]
description = "Run the development server"
run = "bin/rails server"

[tasks.build]
description = "Build production artifacts"
depends = ["test", "lint"]
run = "./bin/build"
```

The advantages over a Makefile-only approach:

- TOML syntax most engineers can read without training.
- Built-in dependency declaration via `depends`.
- Per-task environment overrides (`mise run --env staging deploy`).
- Discoverability via `mise tasks ls`.
- No tab-vs-space issues.
- Tasks can be `*.sh` files in `mise/tasks/` for complex logic.

You invoke them with `mise run <task>`:

```sh
mise run test         # exec the test task
mise run --watch test # re-run on file changes
mise tasks ls         # list all available tasks
```

The framework also ships **global** tasks in the user-scope config —
`dotfiles:link`, `dotfiles:audit`, `dotfiles:test`,
`dotfiles:capabilities`, and the aggregate `dotfiles:doctor` — visible
from any directory. One caveat carries over to projects: unlike
`[tools]` and `[env]`, which merge additively across the config
hierarchy, tasks are **replaced whole per name** — a project defining
`dotfiles:doctor` shadows the global one entirely.

## Make as the wrapper layer

Make has been around since 1976 and remains the closest thing to a
universal "run the project's thing" entry point in software. A new
engineer joining a project, looking at the README, has a near-100%
chance of recognizing `make test` and a less-than-100% chance of
recognizing `mise run test`, `bundle exec rake test`, `bun run test`,
or `uv run pytest`.

The framework leans into this with a **thin-wrapper pattern**: every
project gets `make <target>` for free without losing the advantages
of mise tasks.

### Why Make still matters in 2026

Make's enduring value is not its incremental-build feature — modern
language tooling handles dependency tracking better. The value is
**discoverability and convention**:

- Every Unix engineer knows `make` might do something useful in an
  unfamiliar repository.
- CI configurations across every platform (GitHub Actions, GitLab CI,
  CircleCI, Jenkins) have first-class support for `make` invocations.
- Editor integrations and IDE "build" buttons frequently default to
  looking for a Makefile target named `build`, `test`, or `run`.
- Make is preinstalled on essentially every Linux distribution, every
  macOS install with Command Line Tools, and every container base
  image larger than Alpine.

Make's enduring weakness is equally real: arcane syntax, errors fail
silently by default, tab-vs-space indentation is load-bearing, and
recursive variable expansion produces bugs that are hard to diagnose.
The framework's recommendation — **thin wrappers, not real build
logic** — sidesteps almost all of this.

### The thin-wrapper pattern

For new projects in this stack, the recommended `Makefile` is six to
ten lines that delegate to mise tasks:

```make
# Makefile
# ─────────────────────────────────────────────────────────────────
# Thin wrapper around mise tasks. Real task definitions live in mise.toml.
# This file exists to provide the universal `make <target>` entry point.
# ─────────────────────────────────────────────────────────────────

.SHELLFLAGS := -ec
.DEFAULT_GOAL := help
.PHONY: help test lint fmt build run deploy clean

help:    ## Show this help (default)
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ \
	  { printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

test:    ## Run the test suite
	@mise run test

lint:    ## Run all linters
	@mise run lint

fmt:     ## Format the codebase
	@mise run fmt

build:   ## Build the production artifact
	@mise run build

run:     ## Run the application locally
	@mise run dev

deploy:  ## Deploy to staging
	@mise run deploy

clean:   ## Remove build artifacts and caches
	@mise run clean
```

Three small things in that file are doing real work:

- **`.SHELLFLAGS := -ec`** makes Make's invoked shell exit on any
  command failure. Without this, `make test` can pass even when `mise
  run test` inside it fails. This is the single most common Makefile
  bug.
- **`.PHONY: ...`** tells Make these targets are not file names.
  Without it, if a file or directory named `test` ever appears in the
  project root, `make test` becomes a no-op.
- **The `help:` target** uses an awk one-liner that scans the Makefile
  for lines matching `<target>: ## description` and prints them. This
  is a 25-year-old Makefile idiom and the closest thing the format
  has to self-documentation. Engineers running `make` with no
  arguments get a useful list of what the project supports without
  reading the file.

!!! warning "Tabs, not spaces"

    Make is the one place in this entire framework where the
    indentation rule is **tab characters, not spaces**. Every recipe
    line must start with a tab. Spaces produce the cryptic `***
    missing separator` error. The framework's `.editorconfig` handles
    this automatically by setting `indent_style = tab` for `Makefile`.

### When the wrapper isn't enough

The thin-wrapper pattern works because most projects' task lists are
flat — `test` is a leaf, `lint` is a leaf, `build` is a leaf. When a
project genuinely needs Make's task-graph features (target
dependencies, conditional rebuild based on file timestamps, parallel
execution with `make -j`), the wrapper can grow without becoming
unmaintainable as long as you stay disciplined:

- **Keep complex logic out of recipes.** If a target needs more than
  three lines of shell, write a script and call it: `deploy: ;
  @./bin/deploy.sh`.
- **Avoid recursive Make.** Calling `make` from inside a recipe
  (especially across subdirectories) is a long-recognized antipattern
  that breaks parallelism, dependency tracking, and error
  propagation.
- **Use `$$` for shell variables.** A literal `$VAR` gets expanded by
  Make first, then by the shell. Always write `$$VAR` for shell
  variables, `$(VAR)` for Make variables.
- **Pin tool versions through mise, not Make.** Recipes call `ruff`,
  `biome`, `kubectl` expecting them on PATH. mise's shims ensure the
  right version is found.

## just — the modern alternative

If you'd rather skip Make's quirks entirely and don't want to commit
to mise tasks as the only entry point, **just** (`casey/just`) is a
Make replacement designed specifically for the task-runner use case.
It uses recipe-and-target syntax with sane defaults: spaces are fine,
errors fail by default, recipes run in their own shell, and the help
target is built in. Available via mise — declare `just = "latest"` in
`mise/config.toml` (never `mise use -g`, which rewrites the symlinked
global config), or pin it per-project with `mise use just@latest`.

```just
# justfile
# Run `just` (no args) to see the list of recipes.
default:
    @just --list

test:
    mise run test

lint:
    mise run lint

# Recipe with a parameter — just supports this natively
deploy env="staging":
    mise run deploy {{env}}
```

The framework's recommendation:

- **Make for the wrapper layer in projects that benefit from universal
  recognition** (most projects).
- **just for projects whose maintainers prefer it and don't need Make's
  ubiquity** (often Rust projects, internal tooling, projects without
  external contributors).

Both are valid; neither is wrong; the framework expects mise tasks
underneath either.

## Inheriting an existing Makefile

Existing codebases often have substantial Makefiles — the kind with
200 lines, target-specific variables, conditional includes, pattern
rules, and a five-year history of small additions. "Rewrite this in
mise.toml" is rarely the right move. The framework's guidance for
inherited Makefiles:

- **Audit for the common bugs.** Add `.SHELLFLAGS := -ec` if it's
  missing. Add `.PHONY` declarations for every target that isn't a
  real file. These two changes alone close most silent-failure paths.
- **Add a `help:` target** using the awk pattern above. Walking into a
  project where `make help` produces a useful list is one of the
  cheapest onboarding wins available.
- **Layer mise underneath, don't replace.** Add a `mise.toml` that
  pins the tools the Makefile invokes. Recipes that call `ruff` or
  `kubectl` continue to work, but now everyone gets the same pinned
  version.
- **Refactor incrementally.** When you touch a target for an unrelated
  reason, consider whether its embedded shell logic could move to
  `bin/<target>.sh` and become a one-liner Make recipe. Don't do this
  as a standalone refactor; piggy-back on real changes.

!!! note "What Make is bad at"

    Cross-platform shell incompatibilities (BSD vs. GNU find/sed/awk
    — use scripts in a known language). Anything with non-trivial
    control flow (early returns, nested conditionals — use a script).
    Anything with secrets (recipes log to terminal by default;
    secret-loading belongs in the application's config layer).
    Iterating over dynamic file lists where the iteration logic
    itself is complex (use a script, call it from Make).

    The pattern is the same: when Make starts to feel like a
    programming language, it isn't one, and you'll get a better
    result by writing the logic in a real one and calling it from a
    thin Make recipe.
