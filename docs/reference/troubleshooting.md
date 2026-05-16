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

- **Repository not under `~/work/` or `~/personal/`.** The `includeIf`
  directives in `~/.config/git/config` match on directory path. Clone
  work repos under `~/work/` and personal repos under `~/personal/`.
- **Legacy `~/.gitconfig` exists.** Delete it; the framework uses
  `~/.config/git/config` exclusively.
- **Trailing slash missing.** `includeIf "gitdir:~/work/"` requires
  the trailing slash.

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
- **direnv not installed.** `command -v direnv` — install via
  `brew install direnv` (macOS), `sudo apt install direnv`
  (Debian/Ubuntu), or `sudo dnf install direnv` (Fedora/RHEL).
- **mise handling the env.** If you moved env vars to `mise.toml`'s
  `[env]` block, direnv is no longer needed for those variables.

## Rogue shell injections after tool install

**Symptom:** `bootstrap.sh` audit reports `[rogue]` entries.

**Fix:** Remove the offending lines from the reported files. The
framework's `conf.d/10-path.zsh` is the single source of truth for
PATH; ad-hoc installer-injected lines duplicate or conflict with it.

```sh
# Re-run the audit
sh bootstrap.sh --dry-run 2>&1 | grep '\[rogue\]'
```
