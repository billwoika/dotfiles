# SSH Agent and Key Management

SSH is the authentication substrate for git, remote shells, rsync,
scp, sftp, tunneling, and most deployment pipelines. Its configuration
surface is small but deeply consequential: a misconfigured
`~/.ssh/config` can leak keys between identities, lock you out of
hosts that enforce key-count limits, or silently downgrade a secure
connection. This page establishes a configuration that fails loudly
rather than silently, minimizes passphrase prompts without weakening
security, and cleanly supports multiple identities via host aliases.

## Key management philosophy

The framework commits to the following defaults:

- **Ed25519 keys only** — smaller, faster, and cryptographically
  stronger than RSA at any practical key size. Generate RSA only when
  a legacy server refuses Ed25519 (rare in 2026).
- **One key per identity, not per host** — a single work key
  authenticates you to every work system; a single personal key
  authenticates you everywhere else.
- **Passphrases where they matter** — high-privilege keys (production
  access, root, code signing) must always carry a passphrase. For
  daily-driver keys on an encrypted disk behind strict file
  permissions, the passphrase is defense-in-depth rather than the
  primary security boundary — disk encryption, the agent architecture,
  and (if using 1Password) biometric gating already protect the key
  material. CI/CD keys are passphrase-less by definition; their
  security comes from scoping, short lifetimes, and rotation — not a
  secret nobody can type.
- **Agent over persisted keys** — the private key material stays
  encrypted at rest; the agent holds decrypted material in memory only.
- **`IdentitiesOnly yes`** — without this, SSH offers every key in your
  agent to every host, which breaks authentication on servers that
  reject after N failed attempts and leaks key fingerprints to servers
  that don't need them.
- **No agent forwarding to untrusted hosts** — a compromised host with
  your forwarded agent can sign authentications for any key you have
  loaded. Use `ProxyJump` for jump-host scenarios instead.

## Generating keys

Generate a separate key for each identity. Use descriptive filenames
and meaningful comments — the comment is written into both the public
and private key and is the only way to distinguish keys years later.

```sh
# Work key
ssh-keygen -t ed25519 \
  -C "dev@zftadvancements.com (work, MBP 16\" M4, 2026-04)" \
  -f ~/.ssh/id_ed25519_work

# Personal key
ssh-keygen -t ed25519 \
  -C "you@billwoika.com (personal, MBP 16\" M4, 2026-04)" \
  -f ~/.ssh/id_ed25519_personal

# Permissions must be strict; SSH refuses to use keys with loose perms
chmod 600 ~/.ssh/id_ed25519_*
chmod 644 ~/.ssh/id_ed25519_*.pub
chmod 700 ~/.ssh
```

!!! tip "Why the comment format matters"

    The comment travels with the key. When you look at
    `authorized_keys` on a server two years from now trying to decide
    which lines are stale, the `you@billwoika.com (personal, MBP 16"
    M4, 2026-04)` format tells you: which identity, which machine,
    when the key was generated. Never use the default comment
    (`user@hostname` at generation time).

### Registering public keys

The `.pub` file contents are what you paste into GitHub (Settings >
SSH and GPG keys > New SSH key), GitLab, or a server's
`~/.ssh/authorized_keys`. For GitHub, add the key twice if you use it
for both authentication and signing — once with the "Authentication
Key" type, once with "Signing Key."

=== "macOS"

    ```sh
    pbcopy < ~/.ssh/id_ed25519_work.pub
    ```

=== "Linux (X11)"

    ```sh
    xclip -selection clipboard < ~/.ssh/id_ed25519_work.pub
    ```

=== "Linux (Wayland)"

    ```sh
    wl-copy < ~/.ssh/id_ed25519_work.pub
    ```

```sh
# Copy to a remote server in one step
ssh-copy-id -i ~/.ssh/id_ed25519_work.pub user@host
```

## The ~/.ssh/config file

The SSH config is where host aliases, identity scoping, and connection
options live. The framework's reference config follows a first-match-wins
pattern: specific host blocks come before the general `Host *` block.

```ssh-config
# ── GitHub multi-identity host aliases ────────────────────────
Host github.com-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes
    AddKeysToAgent yes
    UseKeychain yes           # macOS: store passphrase in Keychain

Host github.com-personal
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_personal
    IdentitiesOnly yes
    AddKeysToAgent yes
    UseKeychain yes

# ── Work infrastructure ──────────────────────────────────────
Host bastion
    HostName bastion.zftadvancements.internal
    User your-username
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes

# Internal hosts via bastion — no agent forwarding
Host *.zftadvancements.internal
    User your-username
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes
    ProxyJump bastion         # Jump through bastion; key stays local

# ── Global defaults (must come LAST) ─────────────────────────
Host *
    IdentitiesOnly yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
    ControlMaster auto
    ControlPath ~/.ssh/control/%C
    ControlPersist 10m
    HashKnownHosts yes
    StrictHostKeyChecking accept-new
    UpdateHostKeys yes
    UseKeychain yes
    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519_personal
```

!!! warning "ControlPath needs the directory to exist"

    The `~/.ssh/control/` directory is not created automatically — SSH
    will silently skip multiplexing. The framework's `bootstrap.sh`
    creates it, and `conf.d/70-tools.zsh` checks for it on every shell
    start. The `%C` substitution hashes user, host, port, and address
    into a short filename — safer than the older `%h-%p-%r` form
    because it avoids the Unix socket path-length limit.

## ssh-agent — native, keychain-backed (macOS)

macOS ships a launchd-managed ssh-agent that runs per-user and is
always available at `$SSH_AUTH_SOCK` without any shell activation.
Combined with `UseKeychain yes`, passphrases are stored in the
Keychain, and you never type a passphrase after the initial key load.

```sh
# Load a key and save its passphrase to the Keychain (once per key)
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_work
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_personal

# Verify
ssh-add -l
```

With `AddKeysToAgent yes` in the SSH config, the first use of a key
also triggers an agent load and a Keychain save — you can skip the
`ssh-add` step and just `git push`, answer the passphrase prompt once,
and be done.

## ssh-agent on Linux

Linux does not ship a managed ssh-agent by default. The cleanest
approach on systemd-based distributions is a user service:

```sh
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/ssh-agent.service <<'EOF'
[Unit]
Description=SSH key agent

[Service]
Type=simple
ExecStart=/usr/bin/ssh-agent -D -a %t/ssh-agent.socket
Environment=SSH_AUTH_SOCK=%t/ssh-agent.socket

[Install]
WantedBy=default.target
EOF

systemctl --user enable --now ssh-agent
```

Then export the socket in `~/.profile` or
`~/.config/environment.d/ssh.conf`:

```sh
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.socket"
```

With `AddKeysToAgent yes` in `~/.ssh/config`, keys are added to the
agent automatically on first use for the duration of the session.

On GNOME 46+ desktops (Fedora 40+, Ubuntu 24.04+), `gcr-ssh-agent`
serves as the SSH agent — GNOME 46 moved this out of `gnome-keyring`
into the `gcr-4` package. It is enabled by default, exposes its socket
at `$XDG_RUNTIME_DIR/gcr/ssh`, and provides the same "passphrase
remembered across the session" behavior. (On pre-46 systems the
equivalent was `gnome-keyring` at `$XDG_RUNTIME_DIR/keyring/ssh`.)

The `UseKeychain yes` directive is Apple-only. On upstream OpenSSH
(Linux, *BSD, WSL) it is NOT silently ignored — an unknown keyword is a
fatal `Bad configuration option: usekeychain` that aborts every
connection, because ssh parses the whole file regardless of host match.
To share one config across macOS and Linux safely, add `IgnoreUnknown
UseKeychain` before the first `UseKeychain` line (the framework's
`ssh/config.example` does this at the top of the file); the directive
then becomes a genuine no-op off macOS.

## 1Password SSH agent (recommended alternative)

If you already use 1Password, the 1Password SSH agent is a substantial
upgrade. It stores private keys inside the vault (end-to-end encrypted,
synced across devices), requires Touch ID for every use, integrates
with git commit signing, and eliminates the passphrase workflow. On a
machine using the 1Password agent, your `~/.ssh` directory contains
**no private key material at all**.

### Enabling the agent

In the 1Password desktop app: Settings > Developer > Use the SSH
agent. Point SSH at it:

=== "macOS"

    ```ssh-config
    # In ~/.ssh/config, under Host *:
    Host *
        IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    ```

=== "Linux"

    ```ssh-config
    # In ~/.ssh/config, under Host *:
    Host *
        IdentityAgent ~/.1password/agent.sock
    ```

The `IdentityFile` directives still matter — they tell SSH which public
key to present, and the agent looks up the matching private key in the
vault.

### Commit signing via 1Password

```ini
# In ~/.config/git/work.config (and personal.config)
[gpg "ssh"]
    allowedSignersFile = ~/.config/git/allowed_signers
    # macOS
    program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
    # Linux: program = "/opt/1Password/op-ssh-sign"
```

!!! info "Touch ID on every operation"

    This is both the selling point and the main tradeoff. Every `git
    push`, every `ssh`, every `git commit` (if signing is on) triggers
    a Touch ID prompt. For daily workflows this is the right security
    posture. For high-volume scripts or CI, use short-lived personal
    access tokens or agent-less CI runners.

## Connection multiplexing

`ControlMaster auto` with `ControlPersist 10m` reuses a single
TCP connection for up to 10 minutes of subsequent `ssh`/`scp`/`sftp`
invocations to the same host, dropping second-and-later connection
latency to effectively zero. This is the single biggest
perceived-latency improvement for anyone who runs SSH in a loop.

To close a multiplexed session explicitly: `ssh -O exit <host>`. To
see active control sockets: `ls ~/.ssh/control/`.

## Host aliases for multi-identity use

The `github.com-work` and `github.com-personal` host entries are the
key mechanism. SSH treats them as distinct hosts with distinct identity
files; the git URL rewrites from the
[git configuration](../git/configuration.md) then route clones
through the correct alias based on repository path.

The end-to-end flow:

1. Clone `~/work/zftadvancements/api` — git sees
   `includeIf "gitdir:~/work/"`, loads `work.config`
2. `work.config` rewrites `github.com:zftadvancements/` to
   `github.com-work:zftadvancements/`
3. SSH resolves `github.com-work` to `github.com` + work identity file
4. The correct key is presented; the commit is signed with the work key

## ProxyJump vs. agent forwarding

For reaching internal hosts through a bastion, **always use
`ProxyJump`** rather than agent forwarding (`-A` or
`ForwardAgent yes`):

```ssh-config
Host *.zftadvancements.internal
    ProxyJump bastion
```

Agent forwarding creates a socket on the bastion that anyone with root
access can use to authenticate as you to any host your agent has keys
for. ProxyJump tunnels the TCP connection through the bastion without
exposing the agent — your keys never leave your machine.

## Security checklist

- [ ] Ed25519 keys; passphrases on high-privilege keys, defense-in-depth elsewhere
- [ ] `IdentitiesOnly yes` in `Host *`
- [ ] No agent forwarding; `ProxyJump` for bastions
- [ ] `StrictHostKeyChecking accept-new` (prompt once, then strict)
- [ ] `HashKnownHosts yes` (obscures hostnames in known_hosts)
- [ ] Private key permissions 600, `.ssh` directory 700
- [ ] Keys registered with GitHub as both Authentication and Signing
