# Environment Layer: mise and direnv

Environment variable management for local development has two
legitimate concerns: non-secret project configuration (which belongs
under source control) and secrets (which never do). This framework
solves both with a layered approach:

- **mise's `[env]` block** is the primary layer for non-secret project
  configuration. Fast, declarative, and committed to the repo.
- **mise's `_.file = ".env.local"`** pulls in developer-local dotenv
  values without direnv involvement for most cases.
- **direnv** is a thin optional layer on top, used only when the
  loading logic is complex enough to require `sh` execution —
  1Password CLI integration, age-encrypted file decryption, dynamic
  AWS profile selection, or team-specific shell helpers.

!!! note "The old proto > direnv split"

    In the previous version of this framework, proto owned versions
    and direnv owned everything else: env vars, secret loading, and
    project-scoped tool activation via `use_proto`, `layout_uv`, and
    `layout_rv` in `direnvrc`. mise subsumes most of this. The
    `layout_uv` function is replaced by mise's
    `python.uv_venv_auto` setting; `use_proto` is replaced by `mise
    activate`; basic env vars move from direnv's bash layer to mise's
    TOML `[env]` section. direnv stays, but its job shrinks to the
    cases where bash execution is actually useful.

## Defining environment variables in mise.toml

For any non-secret project configuration, mise is the simplest path.
The `[env]` block in `mise.toml` is TOML-native, fast (no sh
subprocess), and committed to version control alongside tool versions.

```toml
# mise.toml — [env] block examples
[env]
# Static values
APP_ENV       = "development"
LOG_LEVEL     = "debug"
DATABASE_URL  = "postgres://localhost:5432/myapp_dev"
REDIS_URL     = "redis://localhost:6379/0"

# Computed values (Tera templating)
PROJECT_ROOT  = "{{config_root}}"
PROJECT_NAME  = "{{config_root | basename}}"

# File-based values
_.file = ".env"            # loads .env from the project root
_.file = [".env", ".env.local"]  # multiple, later ones override

# Python venv auto-activation
_.python.venv = { path = ".venv", create = true }

# PATH additions (project-local bins)
_.path = ["./bin", "./scripts"]
```

## Layering in .env.local

For developer-local values (personal API keys, local database paths,
toggle flags), use `.env.local` loaded via mise's `_.file` directive.
This file is never committed — it lives in your global `.gitignore`.
mise loads it on entry into the directory.

Provide an `.env.local.example` file committed to the repository that
lists every required variable with placeholder values and
documentation. This is the contract between the team and each
developer's local environment:

```sh
# .env.local.example  (committed — template only, no real values)
# ────────────────────────────────────────────────────────────────
# Copy this file to .env.local and fill in your credentials.
# NEVER commit .env.local.
# ────────────────────────────────────────────────────────────────

# Application secrets
APP_SECRET_KEY=<generate with: openssl rand -hex 32>

# External service credentials
API_TOKEN_EXTERNAL=<from team secrets vault>
STRIPE_SECRET_KEY=<from Stripe dashboard — test mode key>

# API keys
OPENAI_API_KEY=<your personal key from platform.openai.com>
ANTHROPIC_API_KEY=<your personal key from console.anthropic.com>
```

!!! info "Trust semantics"

    mise requires explicit trust for each `mise.toml` it loads via
    `mise trust` (or automatic trust for files you have edited
    yourself). This is the equivalent of direnv's `direnv allow` — a
    security gate that prevents arbitrary code execution from untrusted
    repositories. You will be prompted the first time you `cd` into a
    cloned project; run `mise trust` to approve.

## When to use direnv

direnv is retained for cases where mise's declarative TOML is
insufficient:

- **Secret loading from external vaults** — `op inject` (1Password),
  `aws-vault exec`, `sops -d` (age-encrypted files), or `pass show`.
  These require running a command and capturing its output — outside
  mise's TOML model.
- **Dynamic cloud-credential selection** — setting `AWS_PROFILE` based
  on the git branch, current IAM role, or a `.aws/config` lookup.
- **Complex conditional env construction** — anything that involves
  branching, loops, or multi-line sh logic.
- **Team-standard helper libraries** — functions like `use_1password`,
  `source_secrets`, `use_aws_profile` that multiple projects reuse
  via `direnvrc`.

## Global direnvrc for complex loaders

When direnv is used, its configuration goes in
`~/.config/direnv/direnvrc` and defines reusable helper functions.
This file is committed to the dotfiles repository.

```sh
# ~/.config/direnv/direnvrc
# ─────────────────────────────────────────────────────────────────────
# Standard library for project .envrc files.
# Scope: secret loading and other sh-script-native patterns. Basic
# env vars and venv activation live in mise.toml.
# ─────────────────────────────────────────────────────────────────────

# ── 1Password CLI integration ───────────────────────────────
# Usage in .envrc:  use_1password dev
use_1password() {
  local vault="${1:-dev}"
  if command -v op &>/dev/null && op account list &>/dev/null; then
    log_status "Loading secrets from 1Password vault: $vault"
    eval "$(op inject -i .envrc.op 2>/dev/null || true)"
  else
    log_error "1Password CLI not available or not authenticated. Run: op signin"
  fi
}

# ── age-encrypted secrets via sops ────────────────────────────
# Usage in .envrc:  use_sops secrets.enc.env
use_sops() {
  local file="${1:-secrets.enc.env}"
  if command -v sops &>/dev/null && [[ -f "$file" ]]; then
    eval "$(sops -d "$file")"
  fi
}

# ── AWS profile by branch ──────────────────────────────────
# Usage in .envrc:  use_aws_profile
use_aws_profile() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
  case "$branch" in
    main|master)    export AWS_PROFILE="prod-readonly" ;;
    staging*)       export AWS_PROFILE="staging" ;;
    *)              export AWS_PROFILE="dev" ;;
  esac
  log_status "AWS profile: $AWS_PROFILE"
}
```

A project `.envrc` using these helpers is then minimal and declarative:

```sh
# .envrc  (committed — calls helpers from direnvrc)
# mise handles tool versions and basic env vars; direnv handles secrets.
use_1password dev
use_aws_profile
```

## Global .gitignore requirements

Add the following to your global gitignore. This provides a backstop
beyond any per-project `.gitignore` — these files are never committed
regardless of whether a project maintainer forgot to add them:

```gitignore
# mise & direnv local overrides (developer-local secrets)
.env.local
.envrc.local
.envrc.secrets

# direnv build artifacts
.direnv/

# Python virtual environments
.venv/

# Editor artifacts
.DS_Store
Thumbs.db
*.swp
*.swo
```
