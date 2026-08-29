# Environment Layer: mise and direnv

Environment variable management for local development has two
legitimate concerns: non-secret project configuration (which belongs
under source control as values) and secrets (which belong under
source control only as *references* — see
[Secrets](../operations/secrets.md) for the full backend /
orchestration / scope model). This framework solves both with one
primary layer and one escape hatch:

- **mise's `[env]` block** is the primary layer for project
  environment — non-secret values directly, secrets as vault
  references resolved at environment-computation time.
- **mise's `_.file`** pulls in dotenv-style files, including
  sops-encrypted ones, which mise decrypts natively.
- **direnv** is a thin optional layer on top, used only when the
  loading logic genuinely requires `sh` execution — dynamic AWS
  profile selection, conditional construction, team helper
  functions.

!!! note "The old proto > direnv split"

    In the previous version of this framework, proto owned versions
    and direnv owned everything else: env vars, secret loading, and
    project-scoped tool activation via `use_proto`, `layout_uv`, and
    `layout_rv` in `direnvrc`. mise subsumes most of this. The
    `layout_uv` function is replaced by mise's
    `python.uv_venv_auto` setting; `use_proto` is replaced by `mise
    activate`; env vars — secret and non-secret alike — move from
    direnv's bash layer to mise's TOML `[env]` section. direnv
    stays, but its job shrinks to the cases where bash execution is
    actually useful.

## Defining environment variables in mise.toml

For project configuration, mise is the simplest path. The `[env]`
block in `mise.toml` is TOML-native, fast, and committed to version
control alongside tool versions.

```toml
# mise.toml — [env] block examples
[env]
# Static non-secret values
APP_ENV       = "development"
LOG_LEVEL     = "debug"
DATABASE_URL  = "postgres://localhost:5432/myapp_dev"
REDIS_URL     = "redis://localhost:6379/0"

# Computed values (Tera templating)
PROJECT_ROOT  = "{{config_root}}"
PROJECT_NAME  = "{{config_root | basename}}"

# File-based values
_.file = ".env"                  # loads .env from the project root
_.file = [".env", ".env.local"]  # multiple, later ones override

# Python venv auto-activation
_.python.venv = { path = ".venv", create = true }

# PATH additions (project-local bins)
_.path = ["./bin", "./scripts"]
```

## Secrets in mise

Secrets ride the same `[env]` block as references — the committed
file names the credential; the vault holds the value:

```toml
[env]
# Resolve a 1Password reference when the environment is computed;
# cache_duration avoids re-running op on every prompt.
GITHUB_TOKEN = "{{ exec(command='op read op://Personal/GitHub Token/credential', cache_duration='1h') }}"

# sops-encrypted file (age), decrypted natively by mise.
_.file = { path = ".env.json", redact = true }
```

The framework pre-configures mise's native sops support
(`sops.rops`, `sops.strict`, `age.strict` in `mise/config.toml`).
`redact = true` — or a top-level `redactions = ["*_TOKEN"]` list —
keeps resolved values out of task output.

Which secrets belong in a *project* `mise.toml` versus a subtree
config versus no environment variable at all is a scope question —
see [Secrets: scope](../operations/secrets.md#axis-3-scope). The
short version: identity credentials (your GitHub token) should be
resolved by the consuming tool via op plugins, not exported;
subtree-wide variables go in a parent-directory `mise.toml` (mise
merges configs from `/` down to the current directory); only the
project's own configuration goes in the project file.

## Layering in .env.local

`.env.local` is for developer-local configuration that isn't
sensitive in the first place — runtime flags, ports, base URLs,
local paths. It's loaded via mise's `_.file` directive and never
committed (it's per-developer, not secret): it lives in your global
`.gitignore`, and mise loads it on entry into the directory.

`.env.local` is not a secrets channel. If a value would be a
problem in a git history or a screen share, it isn't `.env.local`
material — it goes in the vault and is referenced from committed
files (see [Secrets](../operations/secrets.md)).

Provide an `.env.local.example` file committed to the repository that
lists every variable the project honors, with placeholder values and
documentation:

```sh
# .env.local.example  (committed — copy to .env.local and adjust)
# ────────────────────────────────────────────────────────────────
# Non-sensitive local configuration only. Credentials are NOT set
# here — they resolve from 1Password via the references in
# mise.toml (see docs/operations/secrets.md).
# ────────────────────────────────────────────────────────────────

# Runtime flags and local overrides
APP_PORT=3000
LOG_LEVEL=debug
FEATURE_NEW_CHECKOUT=false

# Local service endpoints
API_BASE_URL=http://localhost:8080
WEBHOOK_TUNNEL_URL=<your ngrok/cloudflared URL>
```

!!! info "Trust semantics"

    mise requires explicit trust for each `mise.toml` it loads via
    `mise trust` (or automatic trust for files mise itself creates via
    `mise use`, or paths listed in `trusted_config_paths`). Note that
    hand-editing a config does NOT auto-trust it — editing is exactly
    what re-triggers the trust prompt. This is the equivalent of
    direnv's `direnv allow` — a
    security gate that prevents arbitrary code execution from untrusted
    repositories. You will be prompted the first time you `cd` into a
    cloned project; run `mise trust` to approve.

## When to use direnv

direnv is retained for the cases where the loading logic is genuine
shell code rather than a declarative reference:

- **Dynamic cloud-credential selection** — setting `AWS_PROFILE`
  based on the git branch, current IAM role, or a `.aws/config`
  lookup.
- **Complex conditional env construction** — anything that involves
  branching, loops, or multi-line sh logic.
- **Team-standard helper libraries** — functions like
  `use_1password`, `use_aws_profile` that multiple projects reuse
  via `direnvrc`.

Plain secret loading is **not** on this list anymore: `op read`,
sops decryption, and static references are all handled by mise's
`[env]` directly. If your `.envrc` would contain nothing but
exports, delete it and use `mise.toml`.

## Global direnvrc for complex loaders

When direnv is used, its helper library lives at
`~/.config/direnv/direnvrc` — shipped as
[`direnv/direnvrc`](https://github.com/billwoika/dotfiles/blob/master/direnv/direnvrc)
in this repository, which is the source of truth (the excerpt below
is illustrative). It provides:

- `use_1password [vault]` — renders a committed `.envrc.op`
  reference file via `op inject`.
- `op_var VAR "op://…"` — load a single variable via `op read`.
- `use_vault VAR path field` — HashiCorp Vault lookup.
- `use_sops [file]` — decrypt an age/sops-encrypted env file.
- `use_keychain VAR service` — macOS Keychain / Linux Secret
  Service lookup.
- `use_aws_profile` — `AWS_PROFILE` by git branch.

```sh
# ── AWS profile by branch (the canonical "actually needs sh" case) ──
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

A project using these helpers commits an `.envrc.example` naming
the team-agreed helper calls; each developer copies it to a
gitignored `.envrc` (and `direnv allow`s it). Both stay minimal
and declarative — helper calls and references, never values:

```sh
# .envrc.example  (committed — copy to .envrc after cloning)
# mise handles tool versions and env vars; direnv handles sh logic.
use_1password dev
use_aws_profile
```

## Global .gitignore requirements

Add the following to your global gitignore. This provides a backstop
beyond any per-project `.gitignore` (kept in sync with
`gitignore.example` and
[Secrets](../operations/secrets.md#what-gitignore-should-always-have))
— these files are never committed regardless of whether a project
maintainer forgot to add them:

```gitignore
# mise & direnv local overrides (developer-local values)
.env
.env.local
.envrc
.envrc.local
.envrc.secrets
mise.local.toml
.mise.local.toml

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

Committed by design (references only, no values): `mise.toml`,
`.envrc.example`, `.envrc.op`, and sops ciphertext files.
