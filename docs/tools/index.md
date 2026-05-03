# Tools

The framework's toolchain story has one primary character (mise) and
one supporting one (Make). mise pins runtimes and tools per-project;
Make provides the universal `make <target>` entry point that most
engineers reach for reflexively.

## In this section

- **[mise and Make](mise-and-make.md)** — the relationship between
  mise as the toolchain manager and Make as a thin wrapper, with the
  full reference patterns for both.
- **[Package Managers](package-managers.md)** — rv for Ruby, uv for
  Python, bun for JavaScript/TypeScript, and how they cooperate with
  mise.
- **[Code Quality](code-quality.md)** — ruff, RuboCop, Biome,
  lefthook, EditorConfig, and the enforcement strategy.
- **[Containers and Devcontainers](containers.md)** — runtime
  selection, Compose for local services, devcontainers, and the
  host-native default.
- **[Editors and IDEs](editors.md)** — terminal editors, IDE
  configuration, the subprocess problem, debugging, LSP, and
  project intelligence.
- **[Database and API Tools](database-api.md)** — database clients,
  API clients, connection management, and the file-based-first stance.

## The framework's toolchain stance

Three principles that shape every choice in this section:

**1. Tools should declare their pinning, not depend on a global
default.** Every project has a `mise.toml` that pins its runtime
versions. The shell does not have a "default Ruby" or "default Python"
that's globally meaningful; if a project uses Ruby 3.3.4, that's
because its `mise.toml` says so, not because the shell happens to
have 3.3.4 installed.

**2. Modern alternatives over legacy when they're mature.** The
framework prefers uv over pip+virtualenv+pip-tools+pipx, biome over
ESLint+Prettier, ruff over pylint+black+isort+pyflakes, bun over
npm+yarn, podman over Docker for free use. The replacements are
faster, simpler, and more cohesive than the tools they replace. The
framework recommends them when they're production-mature, not when
they're trendy.

**3. Discoverability matters as much as correctness.** A project's
build commands should be reachable through `make <target>`, `mise run
<task>`, or both. New engineers should be able to type `make` with no
arguments and get a useful list of what the project supports. The
combination of mise tasks (where the actual logic lives) and Make
(where the universal entry point lives) gives engineers three
discoverable surfaces: IDE run configurations, terminal `mise run`,
and `make` invocations — all backed by the same task definitions.
