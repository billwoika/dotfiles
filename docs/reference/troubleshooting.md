# Troubleshooting

Common issues and their diagnostic paths.

## Diagnostics reference

The framework's `conf.d/68-diagnostics.zsh` provides diagnostic
functions. The most important built-in diagnostics:

```sh
# mise self-check
mise doctor

# Show which tools are active and from where
mise ls

# Show the current git identity
git config --show-origin user.email

# Show all loaded SSH keys
ssh-add -l

# Verify SSH to GitHub
ssh -T git@github.com-work
ssh -T git@github.com-personal

# Show current PATH, one entry per line
path    # alias defined in conf.d/60-aliases.zsh

# Benchmark shell startup
timeshell 10    # function from conf.d/80-functions.zsh
```

## mise tool not found after installation

**Symptom:** `mise install` succeeds, but the tool is not on PATH.

**Diagnostic:**

```sh
mise ls           # is the tool listed?
mise where ruby   # where is it installed?
which ruby        # which binary is the shell finding?
```

**Common causes:**

- **Not trusted.** Run `mise trust` in the project directory.
- **Shims not on PATH.** Check that
  `~/.local/share/mise/shims` is in your PATH (run `path`).
- **IDE subprocess.** The IDE didn't inherit the shell environment.
  See [editors](../tools/editors.md) for the subprocess problem.

## Wrong git identity on commits

**Symptom:** Commits show the wrong email address.

**Diagnostic:**

```sh
git config --list --show-origin | grep user
```

**Common causes:**

- **Repository not under `~/development/work/` or
  `~/development/personal/`.** The `includeIf` directives in
  `~/.config/git/config` match on directory path. Clone work repos
  under `~/development/work/repos/` and personal repos under
  `~/development/personal/repos/`.
- **Legacy `~/.gitconfig` exists.** Delete it; the framework uses
  `~/.config/git/config` exclusively.
- **Trailing slash missing.** `includeIf "gitdir:~/development/work/"`
  requires the trailing slash.

## SSH authentication failures

**Symptom:** `Permission denied (publickey)` when pushing to GitHub.

**Diagnostic:**

```sh
ssh -vT git@github.com-work    # verbose output shows which keys are tried
ssh-add -l                      # which keys are loaded in the agent?
```

**Common causes:**

- **Key not loaded.** On macOS: `ssh-add --apple-use-keychain
  ~/.ssh/id_ed25519_work`. On Linux: `ssh-add
  ~/.ssh/id_ed25519_work` (omit `--apple-use-keychain`).
- **`IdentitiesOnly yes` not set.** Without it, SSH offers every key
  in the agent; GitHub rejects after too many attempts.
- **Public key not registered.** Add the `.pub` file contents to
  GitHub > Settings > SSH and GPG keys.
- **Wrong host alias.** The git URL rewrite in the profile must
  match the `Host` entry in `~/.ssh/config`.

## Shell startup is slow

**Symptom:** New terminal takes more than 200ms to become interactive.

**Diagnostic:**

```sh
# External timing
hyperfine --warmup 3 "zsh -lic exit"

# Internal profiling
# Add to top of .zshrc: zmodload zsh/zprof
# Add to bottom of .zshrc: zprof
```

**Common causes:**

- **Tool init running on every startup.** Move deterministic init
  output to the version-hashed cache in `25-tool-cache.zsh`. See the
  [performance page](../shell-environment/performance.md).
- **Stale compinit cache.** Delete `~/.cache/zsh/zcompdump*` and
  restart the shell.
- **Rogue eval in conf.d.** Check `70-tools.zsh` for tools that
  should be in `25-tool-cache.zsh` (Tier 2) instead.

## direnv not loading .envrc

**Symptom:** `cd` into a project directory doesn't set environment
variables.

**Diagnostic:**

```sh
direnv status     # or: ds (alias)
```

**Common causes:**

- **Not allowed.** Run `direnv allow` (or `da`).
- **direnv not installed.** `command -v direnv` — it is declared in
  mise's `[tools]`, so `mise install` delivers it; a missing binary
  usually means the toolchain install has not run yet.
- **mise handling the env.** If you moved env vars to `mise.toml`'s
  `[env]` block, direnv is no longer needed for those variables.

## op cannot talk to the 1Password desktop app

**Symptom:** `op whoami` (or any op command) fails with
`connecting to desktop app: read: connection reset`, even though the
desktop app is running and "Integrate with 1Password CLI" is enabled
in Settings → Developer.

**Cause:** on Linux the app verifies the *calling binary* before
accepting the connection: `op` must be group `onepassword-cli` with
the setgid bit (`-rwxr-sr-x root onepassword-cli`). The CLI's own
rpm/deb sets this; a mise/aqua-installed `op` is plain user-owned and
gets rejected. Worse, a mise `[tools]` entry *shadows* a correctly
installed `/usr/bin/op` because mise's install paths precede system
paths — so adding op to mise can break an integration that worked.

**Diagnostic:**

```sh
command -v op            # mise path = shadowed; /usr/bin/op = system
ls -l /usr/bin/op        # want: -rwxr-sr-x ... root onepassword-cli
rpm -qf /usr/bin/op      # want: 1password-cli-<version>
```

**Fix:** op is a system package on Linux in this framework
(`mise/config.linux.toml`), NOT a `[tools]` entry — see the comment in
`mise/config.toml` for why. If a mise copy exists, remove it:

```sh
mise uninstall --all 1password && mise reshim
sudo dnf install 1password-cli      # Fedora: repo ships with the desktop rpm
command -v op                       # now /usr/bin/op
op whoami                           # "account is not signed in" = integration OK; sign in via the app prompt
```

(macOS is different: the app checks the binary's code signature, which
the official zip keeps, so mise owns op there — `mise/config.macos.toml`.)

## Applications are OOM-killed while memory looks fine

**Symptom:** VS Code (or another Electron app) dies mid-session,
sometimes several times a day. `free -h` afterwards shows several GB
available. `journalctl -k | grep -i 'out of memory'` confirms the
kernel OOM killer fired, and the process it names is the one that
died — not the one that ate the memory.

**Diagnostic:** the kernel logs a full task table at each kill. Read
it, rather than guessing from the current state of the machine:

```sh
# When did it fire, and who got killed?
journalctl -k --since today | grep -E 'Out of memory|oom-kill'

# Who was actually holding memory at that moment? Sum the task
# table by process name (rss and swap columns are in pages; ×4/1024 = MB).
T='2026-08-22 15:36'   # minute of the kill, from the line above
journalctl -k --since "$T:00" --until "$T:59" -o cat \
  | grep -E '^\[ *[0-9]+\]' | sed 's/[][]/ /g' \
  | awk 'NF>=12 {r[$12]+=$5*4/1024; s[$12]+=$10*4/1024; n[$12]++}
         END {for (k in r) printf "%7.0f MB rss %7.0f MB swap  x%-3d %s\n", r[k], s[k], n[k], k}' \
  | sort -rn | head

# Is swap real, or only zram (compressed RAM)?
swapon --show
zramctl
```

**Common causes:**

- **zram is the only swap.** Fedora's default `zram-generator` gives
  you 8 GB of compressed-in-RAM swap and no disk tier, so pressure
  goes straight to the OOM killer. A swap LV that exists but is not in
  `/etc/fstab` does not count. Fix: activate disk swap behind a smaller
  zram — see [Fedora → Swap](platform-setup/fedora.md#swap-pair-zram-with-the-disk-swap-you-provisioned)
  and the reasoning in [Disk Strategy → zram](platform-setup/disk-strategy.md#zram).
- **The killed process is the scapegoat.** The OOM killer picks by
  `oom_score_adj`; Electron renderers run at 300, so VS Code is chosen
  over a browser that is holding five times as much. In the task table
  above, look for `Isolated` (Firefox content processes) or `chrome`
  helpers summing to many GB across dozens of processes.
- **Orphaned sessions.** Long-lived `claude`, language servers or
  Jupyter kernels in directories that no longer exist still hold their
  RSS (and swap). `ps -eo pid,etime,rss,args --sort=-rss | head` and
  `readlink /proc/<pid>/cwd` — a `(deleted)` suffix means it is safe to
  close.

## Rogue shell injections after tool install

**Symptom:** `bootstrap.sh` audit reports `[rogue]` entries.

**Fix:** Remove the offending lines from the reported files. The
framework's `conf.d/10-path.zsh` is the single source of truth for
PATH; ad-hoc installer-injected lines duplicate or conflict with it.

```sh
# Re-run the audit
sh bootstrap.sh --dry-run 2>&1 | grep '\[rogue\]'
```
