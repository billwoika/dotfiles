# JetBrains Reference Templates

JetBrains IDEs (RubyMine, PyCharm, IntelliJ, WebStorm, GoLand, DataGrip)
store per-project configuration in a `.idea/` directory. Some of that
content is genuinely team-shareable; some is per-developer state that
must never be committed. This directory provides:

1. A reference `.gitignore` block (`gitignore.example` at the repo root)
   that marks the right `.idea/` files as untracked
2. Two example `runConfigurations/` XML files that demonstrate the
   shared-run-config pattern (`runConfigurations/RSpec_current_file.xml`
   and `runConfigurations/Pytest_current_file.xml`)

See **Section 22.6** of the framework document for the full breakdown
of which `.idea/` files to commit and which to gitignore. The summary:

| File | Commit? | Why |
|------|---------|-----|
| `.idea/codeStyles/` | Yes | Team code-style decisions |
| `.idea/inspectionProfiles/` | Yes | Team inspection severities |
| `.idea/runConfigurations/` | Yes | Shared run/debug configs |
| `.idea/<project>.iml` | Yes | Module structure |
| `.idea/modules.xml` | Yes | Module list |
| `.idea/vcs.xml` | Yes | "This is a git project" marker |
| `.idea/workspace.xml` | **No** | Per-developer UI state |
| `.idea/tasks.xml` | **No** | Per-developer task state |
| `.idea/usage.statistics.xml` | **No** | Per-developer telemetry |
| `.idea/dictionaries/` | **No** | Per-developer spell check |
| `.idea/shelf/` | **No** | Per-developer stash |
| `.idea/dataSources.local.xml` | **No** | Saved DB credentials |
| `.idea/sqlDataSources.xml` | **No** | Cached schema metadata |
| `.idea/dataSources/` | **No** | Per-data-source state |

## Usage

In a project that uses JetBrains:

```sh
# Apply the recommended .gitignore additions
cat ~/dotfiles/gitignore.example >> .gitignore

# Create the runConfigurations directory and copy the templates
mkdir -p .idea/runConfigurations
cp ~/dotfiles/jetbrains/runConfigurations/*.xml .idea/runConfigurations/

# Edit the example XML files to match the project's conventions
# (e.g., point Pytest_current_file.xml at the right interpreter)
```

## On `dataSources.xml`

The framework's recommendation is to gitignore **all** of `.idea/dataSources*`
and document database connections in a project `db/README.md` (see
Section 23.1.4). This is more portable across editors and reduces the
risk of accidentally leaking connection details.

Some teams prefer to commit a sanitized `.idea/dataSources.xml` for the
local development database (host=localhost, no credentials) — that's a
defensible choice. If you do, make sure the `dataSources.local.xml`
that holds the credentials is rigorously gitignored.

## Run Configurations as Documentation

The most underused feature here: a committed run configuration is
*documentation* of how to run a piece of the project. New engineers
clicking through "Edit Configurations" in JetBrains learn what tasks
the team has set up. This is genuinely useful in a way that command-line
incantations buried in a README are not.

Pair this with `mise run` task definitions and a Makefile (Section 7.2)
and you give engineers three discoverable entry points:

- IDE users: pick a Run Configuration from the dropdown
- Terminal users: type `mise run <task>` or `make <target>`
- CI: invoke `make <target>` directly

All three converge on the same underlying mise task definition. One
source of truth, three discoverable surfaces.
