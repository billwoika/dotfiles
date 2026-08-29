# Operations

The framework's "operations" section covers patterns that sit between
the engineer's personal environment and the team's deployed services
— secrets management, SSH identity and key management, credential
rotation, and the disciplines that keep development-environment
state consistent across machines and teams.

The two hardest concerns in this category are **credentials** (how
they're stored, how they reach processes, how to keep them off disk)
and **identity** (which SSH key, which git profile, which cloud
credential reaches which system).

## In this section

- **[Secrets](secrets.md)** — the three-axis model: backends
  (1Password primary; Vault, sops, keychain), orchestration (op
  plugins, mise `[env]`, `op run`, direnv), and scope (identity vs
  subtree vs project vs invocation), plus the `op://` reference
  pattern that ties them together.
- **[SSH and Key Management](ssh.md)** — Ed25519 keys, the
  `~/.ssh/config` reference, ssh-agent and 1Password agent, connection
  multiplexing, host aliases for multi-identity use, and ProxyJump.
- **[Networking](networking.md)** — VPN configuration, DNS ownership
  conflicts, container networking modes, local proxies for debugging,
  and why these layers fight each other on a developer workstation.

## The framework's stance on operations

**Credentials live in vaults, not on disk.** Every long-lived
credential (API tokens, database passwords, signing keys) belongs in
a credential store the engineer can audit and rotate. Files like
`.env`, `.aws/credentials`, and `~/.netrc` are convenient but
fundamentally wrong — they put long-lived secrets in plaintext on
disk where backups, sync tools, and laptop theft can leak them.

**Project-level configuration travels with the project.** The
patterns that make a project work — its `mise.toml`, its
`.envrc.example` and `.envrc.op`, its `compose.yml`, its
devcontainer — should be
in the repo. Engineers cloning the repo should be able to get to a
working development environment from `git clone` plus a documented
setup command, with credentials as the only thing they need to
provide individually.

**Reproducibility is the goal, but it's not the only goal.** A
fully-reproducible environment is also a slow one to set up if the
machinery is heavy. The framework's patterns lean toward "good
enough reproducibility" — the same tools at the same versions, the
same shell configuration, the same project setup story — without
chasing absolute purity (Nix-style hermetic builds, pinned compiler
flags, etc.). For most teams, that level of purity isn't worth the
operational cost.
