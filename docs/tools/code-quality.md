# Code Quality Enforcement

Consistent tooling only delivers value if it is enforced. Style
debates are a tax on code review bandwidth; automated formatting
eliminates them. The tools below are selected for speed (all Rust or
native binaries), minimal configuration overhead, and cross-language
coherence.

!!! info "mise + task = project entry points"

    In this framework, every project-level invocation — lint, test,
    build, deploy — is declared as a task in `mise.toml` and run via
    `mise run <task>` (or the `mr` alias). This replaces the sprawling
    Makefile, Justfile, `scripts/*.sh`, and `package.json#scripts`
    ecosystem with a single declarative file. Pre-commit hooks still
    use lefthook (it is specialized for git event dispatch), but what
    lefthook invokes is typically a mise task.

## Python — Ruff

Ruff replaces flake8, isort, pyupgrade, and in most projects pylint
as well. It runs in under 100ms on projects with tens of thousands of
lines of Python. Configure it in `pyproject.toml`:

```toml
[tool.ruff]
line-length    = 100
target-version = "py312"

[tool.ruff.lint]
select = [
  "E",   # pycodestyle errors
  "W",   # pycodestyle warnings
  "F",   # pyflakes
  "I",   # isort
  "B",   # flake8-bugbear
  "C4",  # flake8-comprehensions
  "UP",  # pyupgrade
  "S",   # flake8-bandit (security)
]
ignore = ["S101"]  # allow assert in tests

[tool.ruff.format]
quote-style   = "double"
indent-style  = "space"
line-ending   = "lf"
```

## Ruby — RuboCop

RuboCop with the `rubocop-rails`, `rubocop-rspec`, and
`rubocop-performance` extension gems covers style, Rails idioms, test
structure, and common performance antipatterns. Use `.rubocop.yml` to
inherit from a shared team configuration distributed as a gem or a raw
GitHub URL:

```yaml
# .rubocop.yml
inherit_from:
  - https://raw.githubusercontent.com/myteam/rubocop-config/main/.rubocop.yml

AllCops:
  TargetRubyVersion: 3.3
  NewCops: enable
  Exclude:
    - "db/schema.rb"
    - "db/migrate/**/*"
    - "node_modules/**/*"
    - ".bundle/**/*"

Layout/LineLength:
  Max: 120
```

## JavaScript/TypeScript — Biome

Biome replaces ESLint, Prettier, and import sorters for JS/TS
projects. Like ruff for Python, it is a single Rust binary with
near-instant execution. Configure via `biome.json`:

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.0/schema.json",
  "organizeImports": { "enabled": true },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "correctness": { "noUnusedVariables": "error" },
      "suspicious":  { "noExplicitAny": "warn" }
    }
  },
  "formatter": {
    "enabled":      true,
    "indentStyle":  "space",
    "indentWidth":  2,
    "lineEnding":   "lf",
    "lineWidth":    100
  }
}
```

## Pre-commit hooks — lefthook

Pre-commit hooks enforce quality gates at the last safe moment before
code enters the repository. Use lefthook — a fast, dependency-free
pre-commit runner available as a mise-managed binary — rather than the
Python-based `pre-commit` framework, which introduces an additional
runtime dependency.

```yaml
# lefthook.yml  (committed to VCS)
pre-commit:
  parallel: true
  commands:
    ruff-format:
      glob: "*.py"
      run: mise exec -- ruff format {staged_files}

    ruff-lint:
      glob: "*.py"
      run: mise exec -- ruff check --fix {staged_files}

    rubocop:
      glob: "*.rb"
      run: bundle exec rubocop --autocorrect {staged_files}

    biome:
      glob: "*.{js,ts,jsx,tsx}"
      run: mise exec -- biome check --apply {staged_files}

    secrets-scan:
      run: >
        git diff --cached --name-only |
        xargs grep -l "PRIVATE\|SECRET\|API_KEY\|password" || true

pre-push:
  commands:
    test-python:
      glob: "*.py"
      run: mise run test

    test-ruby:
      glob: "*.rb"
      run: bundle exec rspec --format progress

    test-js:
      glob: "*.{ts,tsx}"
      run: bun test
```

lefthook is already declared in the framework's `[tools]`
(`mise/config.toml`), so every machine gets it at bootstrap. Register
hooks once per repository:

```sh
# In each project
lefthook install
```

For a deeper treatment of lefthook's design choices, staged-files
scoping, and hook types, see
[Tool-Enforced Practices](../git/tool-enforced-practices.md).

## Editor normalization — EditorConfig

EditorConfig is supported natively or via plugin in every major editor
and IDE. It ensures consistent whitespace, line endings, and encoding
regardless of operating system or editor preference — the only
non-negotiable baseline for polyglot projects:

```ini
# .editorconfig  (committed)
root = true

[*]
charset                  = utf-8
end_of_line              = lf
insert_final_newline     = true
trim_trailing_whitespace = true
indent_style             = space
indent_size              = 2

[*.py]
indent_size = 4

[Makefile]
indent_style = tab

[*.md]
trim_trailing_whitespace = false
```
