# Secrets

The framework's secrets story has one primary tool (1Password) and
one primary pattern (`op://` references resolved at process-start
time via direnv).

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

## 1Password as the primary store

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

The patterns transfer to other vaults — Bitwarden, AWS Secrets
Manager, Vault, sops + age — but the specific commands change. The
principle (resolve at use time, not at file-edit time) is what
matters.

## The `op://` reference pattern

A 1Password reference looks like:

```
op://<vault>/<item>/<field>
```

For example: `op://Personal/GitHub Token/credential` resolves to the
value of the "credential" field on the "GitHub Token" item in the
"Personal" vault.

References are resolved by `op read`:

```sh
$ op read 'op://Personal/GitHub Token/credential'
ghp_abc123def456...
```

## direnv for project-scoped credential loading

The framework uses [direnv](https://direnv.net/) to load
project-specific environment when you `cd` into a project directory.
A `.envrc` file in the project root declares what variables to set;
direnv prompts you to authorize the file the first time you see it.

The framework's `direnvrc` (loaded automatically) provides helper
functions that resolve 1Password references:

```sh
# .envrc in a project root
use_1password
export GITHUB_TOKEN=$(op_read "op://Personal/GitHub Token/credential")
export DATABASE_URL=$(op_read "op://Work/Project DB/connection_string")
```

When you `cd` into the project, direnv loads the `.envrc`, which
resolves the references and sets the environment variables. When you
`cd` away, direnv unsets them. The credentials exist only in the
shell's environment for the duration of your session in that
directory.

The `.envrc` itself contains no secrets — only references. It's
**safe to commit** as long as the references point to vault items the
team has access to.

## What goes in `.envrc.example` vs `.envrc`

The framework's project pattern:

- **`.envrc.template`** — committed to the repo. Documents the
  references the project uses, with the full `op://` paths the team
  agrees to. New engineers copy this to `.envrc` after cloning.
- **`.envrc`** — gitignored. Per-developer; might add personal
  references on top of the template's shared ones.
- **`.envrc.local`** — also gitignored. For temporary overrides
  during debugging.

## 1Password plugins (the under-used feature)

The plugin system layers on top of shell aliases. Initialize a
plugin once:

```sh
op plugin init aws
op plugin init gh
op plugin init databricks
```

…and the framework's shell sources `~/.config/op/plugins.sh`
automatically. Now `aws s3 ls`, `gh repo view`, etc. resolve their
credentials from 1Password without any manual environment setup.
The plugins handle SSO refresh, MFA prompts, and credential rotation
transparently.

If you already have an `aws-login` function that calls `aws sso
login`, the 1Password plugin replaces that flow entirely — you delete
the function and the plugin takes over.

## Service Accounts for CI and Automation

For unattended processes (CI runners, Kubernetes jobs, scheduled
scripts), 1Password provides **service accounts**. A service account
is a non-human identity with a long-lived token that can be scoped
to specific vaults and items. The token is the value of the
`OP_SERVICE_ACCOUNT_TOKEN` environment variable; everything else
works the same.

In CI:

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
      - run: |
          export DATABASE_URL=$(op read "op://CI/Production DB/connection_string")
          ./bin/deploy
```

The `OP_SERVICE_ACCOUNT_TOKEN` itself lives in GitHub Actions secrets
(or your CI's equivalent). It has minimum-scope access to just the
vault items deploys need. Rotating it is straightforward: generate a
new service account, update the CI secret, retire the old one.

## Vault and sops as alternatives

For teams already using HashiCorp Vault, the same pattern applies
with different commands:

```sh
# .envrc using Vault
use_vault
export DATABASE_URL=$(vault_read secret/data/myapp database_url)
```

For teams using **sops** (getsops/sops, a CNCF Sandbox project — moved
from the mozilla org to getsops in 2023) with age or AWS KMS for
key management, secrets live in encrypted YAML files committed to
the repo:

```sh
# .envrc using sops
use_sops secrets.yaml
# Variables defined in secrets.yaml are now in the environment
```

The framework provides direnv helpers for all three (1Password,
Vault, sops) in the dotfiles `direnvrc`. Pick the one that matches
your team's existing infrastructure. The principle — credentials
resolved at use time, not stored in plaintext — applies regardless.

## What `.gitignore` should always have

Every project should gitignore the local credential files even if
the framework's patterns mean they shouldn't exist:

```gitignore
.env
.env.local
.env.*.local
.envrc
.envrc.local
.envrc.secrets
*.pem
*.key
```

This is defense-in-depth. The framework's pattern means these files
shouldn't have credentials anyway, but accidentally committing them
costs nothing in the cases where they're empty placeholders, and
prevents disaster in the cases where someone forgot.
