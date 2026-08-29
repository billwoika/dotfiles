# Secrets

The framework's secrets story is one system with three separable
decisions:

1. **Backend** — where the secret *rests*: 1Password (primary),
   HashiCorp Vault, sops-encrypted files, or the OS keychain.
2. **Orchestration** — how the secret *reaches a process*: the
   consuming tool itself (op plugins, the 1Password SSH agent),
   mise's `[env]` layer, `op run`/`op inject`, or direnv.
3. **Scope** — which processes *should see it*: your whole identity,
   a directory subtree, one project, or one command invocation.

Every secrets question decomposes into these three axes, and the
answers are independent: choosing 1Password as the backend does not
choose an orchestrator; choosing mise as the orchestrator does not
choose a scope. Conflating them is how you end up with a personal
GitHub token pasted into six `.env` files.

## The principle

Credentials live in a vault. The shell, processes, and tools never
have plaintext credentials on disk. When a process needs a
credential, it gets it via a reference that resolves at the moment
of use — `op read 'op://vault/item/field'` returns the value;
nothing on disk has the value cached.

This pattern is **strictly better** than `.env` files for three
reasons:

1. **Audit trail.** Every `op read` invocation is logged in 1Password.
   You can see when a credential was accessed and from where.
2. **Centralized rotation.** Update the vault entry and every
   process that uses it picks up the new value the next time it
   resolves the reference. No coordinated updates of `.env` files
   on multiple machines.
3. **No plaintext on disk.** Backups, sync services (iCloud, Dropbox),
   spotlight indexes, and screen-sharing tools cannot leak what
   isn't there.

The corollary: the files that *are* on disk — `mise.toml`,
`.envrc.example`, `.envrc.op` — contain only references, which makes
them **safe to commit**. The repo carries the shape of the
environment; the vault carries the values. (The working `.envrc`
itself stays gitignored — see the project pattern below.)

## Axis 1 — Backends

### 1Password as the primary store

The framework recommends 1Password specifically because:

- The CLI (`op`) is mature, scriptable, and reliable.
- The desktop app integrates with the system keychain for unlock,
  including biometric (Touch ID).
- The SSH agent feature replaces `ssh-agent` with a 1Password-backed
  agent that gates each key use behind a Touch ID prompt.
- The plugin system (`op plugin init`) wraps tools like `aws`, `gh`,
  `databricks`, etc. so that they automatically resolve credentials
  from 1Password without you setting environment variables manually.
- The service-account feature supports unattended workloads (CI,
  scheduled scripts) without exposing user credentials.

!!! warning "How op is installed matters"

    On Linux, desktop-app integration requires the `op` binary to be
    setgid `onepassword-cli` — only the CLI's own rpm/deb holds that
    across upgrades, so op is a **system package** here
    (`mise/config.linux.toml`), never a mise `[tools]` entry. A mise
    copy would shadow `/usr/bin/op` on PATH and break the integration
    with `connection reset`. On macOS the app checks the code
    signature instead, and mise owns op (`mise/config.macos.toml`).
    See [Troubleshooting](../reference/troubleshooting.md#op-cannot-talk-to-the-1password-desktop-app).

A 1Password reference looks like:

```
op://<vault>/<item>/<field>
```

For example: `op://Personal/GitHub Token/credential` resolves to the
value of the "credential" field on the "GitHub Token" item in the
"Personal" vault, via `op read`:

```sh
$ op read 'op://Personal/GitHub Token/credential'
ghp_abc123def456...
```

### The alternatives

The three-axis model transfers to other backends unchanged — only
the reference syntax and resolving command differ:

- **HashiCorp Vault** — for teams already running it.
  `vault kv get -field=<field> <path>` is the resolver; the
  `use_vault` direnv helper and mise `exec()` templates both wrap it.
- **sops + age** (getsops/sops, a CNCF Sandbox project) — encrypted
  files committed to the repo. This is the one backend where the
  ciphertext *does* live on disk, which makes it the right choice
  when secrets must travel with the repo (air-gapped environments,
  CI without vault network access). mise decrypts sops files
  natively — see orchestration below.
- **OS keychain** (macOS Keychain / Linux Secret Service) — for
  single-machine, no-team values. The `use_keychain` direnv helper
  wraps `security` / `secret-tool`.

Pick the backend that matches your team's infrastructure. The
principle — resolve at use time, not at file-edit time — and the
orchestration and scope decisions below apply regardless.

## Axis 2 — Orchestration

Four orchestrators, in order of preference. Prefer the earliest one
that fits; each later one has a broader blast radius or more moving
parts.

### Tool-native resolution (no environment variable at all)

The best environment variable is the one you never export. The
1Password plugin system wraps a tool so it resolves its own
credential per invocation:

```sh
op plugin init aws
op plugin init gh
op plugin init databricks
```

…and the framework's shell sources `~/.config/op/plugins.sh`
automatically. Now `aws s3 ls`, `gh repo view`, etc. resolve their
credentials from 1Password without any manual environment setup.
The plugins handle SSO refresh, MFA prompts, and credential rotation
transparently. If you already have an `aws-login` function that
calls `aws sso login`, the plugin replaces that flow entirely.

In the same family: the 1Password **SSH agent** (keys never leave
the vault; each use is gated) and git **credential helpers**. These
are the correct orchestrators for identity-scoped credentials —
see the scope axis below for why.

### mise `[env]` — the primary env-var orchestrator

When a process genuinely needs a variable in its environment (an app
reading `DATABASE_URL`), mise is the default loader. This is the
same `[env]` block that carries non-secret config (see
[Environment Layer](../shell-environment/environment.md)) — secrets
ride the same mechanism as references:

```toml
# mise.toml (committed — references only, no values)
[env]
# Resolve an op:// reference at environment-computation time.
# cache_duration avoids re-invoking op on every prompt.
GITHUB_TOKEN = "{{ exec(command='op read op://Personal/GitHub Token/credential', cache_duration='1h') }}"

# Or: a sops-encrypted file (age keys), decrypted natively by mise —
# no direnv, no sops invocation in your shell.
_.file = { path = ".env.json", redact = true }
```

mise's native sops support is already configured in this framework
(`sops.rops = true`, `sops.strict = true`, `age.strict = true` in
`mise/config.toml`); point `sops.age_key_file` at your age key and
encrypted `.env.json` files decrypt transparently on directory
entry. `redact = true` (or a top-level `redactions` list) keeps
resolved values out of task logs.

### `op run` / `op inject` — process-scoped injection

For the narrowest scope — one command, one process tree — skip the
shell environment entirely:

```sh
# .env.op (committed — references only)
DATABASE_URL="op://Work/Project DB/connection_string"

$ op run --env-file=.env.op -- ./bin/server
```

The secret exists only in that process's environment. `op inject`
is the template-rendering sibling used by the direnv helper below
and in CI.

### direnv — the sh-logic escape hatch

direnv is **not** the secrets orchestrator; mise is. direnv is
retained for the cases that need real shell execution — dynamic
`AWS_PROFILE` selection by git branch, conditional loading, helper
functions shared across projects. The framework's
[`direnv/direnvrc`](../shell-environment/environment.md#global-direnvrc-for-complex-loaders)
ships `use_1password` (renders a committed `.envrc.op` via
`op inject`), `op_var` (single-variable `op read`), `use_vault`,
`use_sops`, `use_keychain`, and `use_aws_profile`. The project
commits an `.envrc.example` documenting the team-agreed helper
calls; each developer copies it to a gitignored `.envrc`:

```sh
# .envrc.example (committed — copy to .envrc after cloning)
use_1password dev
use_aws_profile
```

If your `.envrc` would contain nothing but static variable exports
or vault references, you don't need direnv — that's mise's job.

## Axis 3 — Scope

The scope question is the one `.env`-file thinking cannot even ask:
*which processes should be able to read this value?* The framework
maps scopes to concrete mechanisms:

| Scope | Example | Mechanism |
|---|---|---|
| Identity | your GitHub token, SSH keys | tool-native: op plugins, 1P SSH agent, credential helpers — **no env var** |
| Subtree | `AWS_PROFILE` for everything under `~/development/work/` | mise config hierarchy: `~/development/work/mise.toml` `[env]` |
| Project | an app's `DATABASE_URL` | project `mise.toml` `[env]` with references; direnv for sh-logic |
| Invocation | a deploy script's production credential | `op run --env-file=… -- cmd` |

**Identity scope.** Your GitHub token is uniform across your whole
personal tree — which makes it tempting to export globally. Don't.
A globally exported `GITHUB_TOKEN` is readable by *every* process
you ever run, including the ones that have no business with it, and
it silently overrides per-directory intent (a work checkout that
should use a work identity). Identity credentials belong to the
*consuming tool*, not the environment: `gh` gets it from the op
plugin per invocation, git gets it from a credential helper, SSH
from the 1Password agent. Uniform access, zero exported state.

**Subtree scope.** When a variable genuinely must be *in the
environment* across many projects (an `AWS_PROFILE` default, a
private registry URL for all work repos), use mise's config
hierarchy: mise merges every `mise.toml` from `/` down to the
current directory, so a `~/development/work/mise.toml` applies to
the whole subtree and each project can still override it. The
reference is written once; injection is still bounded to the
subtree — you have not leaked it to your personal projects or your
login shell.

**Project and invocation scope** are the default and the exception
respectively: project `mise.toml` for the app's own configuration,
`op run` when even the project shell shouldn't hold the value (
production credentials in a deploy script).

### How vaults map to scopes (they don't)

1Password vaults are **trust boundaries, not scopes**. A vault
answers "who *can* read this" (you; you-and-team; you-and-client);
the orchestration placement above answers "which processes *do*
read it." Keep vaults coarse — `Personal`, `Work`, one per client
or team — and let the committed references select items out of
them per project. Do not create a vault per project: you'd be
re-implementing scope with access control, multiplying membership
management for no injection-side benefit. (See
[the handbook's argument](../handbook/least-privilege.md) on where
fine-grained slicing of *human* access goes wrong.) The two slices
compose: vault membership gates the team, file placement gates the
process.

## The project pattern

Putting the axes together, a project following the framework commits
the shape and ignores the values:

- **`mise.toml`** — committed. Tool versions, non-secret `[env]`,
  and secret *references* (`exec` + `op read`, or a sops `_.file`).
- **`.envrc.example`** — committed, only if the project needs
  direnv's sh-logic. Documents the team-agreed helper calls and
  references; the contract for what `.envrc` should contain.
- **`.envrc`** — gitignored. Each developer copies it from
  `.envrc.example`, then may layer personal additions on top. It
  should never come to contain values, but gitignoring it means a
  developer who does slip one in hasn't committed it.
- **`.envrc.op` / `.env.op`** — committed; `op inject`/`op run`
  templates, references only.
- **`.env.json` / `secrets.enc.env`** — committed; sops-encrypted
  ciphertext (the one deliberate exception to "nothing on disk").
- **`.env.local`** — gitignored; developer-local configuration that
  isn't sensitive in the first place — runtime flags, ports, base
  URLs. Credentials never go here — they go in the vault,
  referenced from the files above.
- **`.envrc.local` / `.envrc.secrets` / `mise.local.toml`** —
  gitignored; per-developer overrides of the direnv/mise layers.

New engineers clone, `mise trust`, copy `.envrc.example` to
`.envrc` and `direnv allow` (if present), `op signin` — and the
environment assembles itself from references. No secrets handoff,
no "ask someone for the .env file."

## Service accounts for CI and automation

For unattended processes (CI runners, Kubernetes jobs, scheduled
scripts), 1Password provides **service accounts**: a non-human
identity with a long-lived token scoped to specific vaults. Set
`OP_SERVICE_ACCOUNT_TOKEN` and everything else works the same —
same references, same `op read`/`op run` orchestration, invocation
scope by construction.

```yaml
# .github/workflows/deploy.yml
jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
    steps:
      - uses: actions/checkout@v4
      - uses: 1password/install-cli-action@v3
      - run: op run --env-file=.env.op -- ./bin/deploy
```

The `OP_SERVICE_ACCOUNT_TOKEN` itself lives in GitHub Actions secrets
(or your CI's equivalent), with minimum-scope access to just the
vault items deploys need. Rotation is straightforward: generate a
new service account, update the CI secret, retire the old one.

## What `.gitignore` should always have

Every project gitignores the local-value files even though the
framework's patterns mean they shouldn't hold credentials (this
list matches `gitignore.example` in the dotfiles repo):

```gitignore
.env
.env.local
.env.*.local
.envrc
.envrc.local
.envrc.secrets
mise.local.toml
.mise.local.toml
*.pem
*.key
```

Note what is *absent*: `.envrc.example`, `.envrc.op`, `mise.toml`,
and sops ciphertext are committed — they carry references, not
values. The ignore list is defense-in-depth for the per-developer
files where a plaintext value could plausibly land, `.envrc`
included: it *shouldn't* hold values, but ignoring it costs nothing
when it doesn't and prevents disaster when someone slips.
