# Installer Shell Behavior

Most developer tools ship a `curl | sh` or `curl | bash` installer
that runs in a subprocess disconnected from your interactive zsh
session. These installers read their own shell's profile files, modify
PATH entries, and write configuration to locations determined by the
environment at the time the script runs — not the environment you see
in your terminal. Understanding which shell each installer spawns, and
what environment it inherits, is the difference between a clean install
and an hour of debugging PATH confusion.

## Installer audit

The following table documents every installer in this framework's
toolchain, its shell requirements, and the profile files it modifies:

| Tool | Shell | Invocation | Modifies | Behavior |
|------|-------|------------|----------|----------|
| mise | sh | `curl \| sh` | Nothing (binary only) | Downloads binary to `~/.local/bin`. Shell-specific endpoint adds activation; we use the binary-only form and wire activation in `conf.d/70-tools.zsh`. |
| rv | sh | `curl \| sh` | Nothing (binary only) | Downloads to `~/.local/bin`; activation via `eval "$(rv shell zsh)"` wired in `conf.d/70-tools.zsh`. |
| Homebrew | /bin/bash | `/bin/bash -c ...` | Nothing (prints instructions) | Requires bash explicitly. Prints `eval "$(brew shellenv)"` for user to add. |
| rustup | sh | `curl \| sh` | `~/.profile`, `~/.bashrc`, `~/.zshenv` | Writes `CARGO_HOME/bin` to PATH in all detected profiles. Reads `CARGO_HOME`, `RUSTUP_HOME`. |
| nvm | bash | `curl \| bash` | `~/.bash_profile`, `~/.zshrc`, `~/.profile` | Appends `NVM_DIR` and source lines. Modifies first profile found. |
| uv | sh | `curl \| sh` | Nothing (binary only) | mise manages uv in this stack; standalone installs via `astral.sh/uv/install.sh`. |
| bun | bash | `curl \| bash` | `~/.bashrc`, `~/.zshrc` | mise manages bun in this stack; standalone adds `BUN_INSTALL` to PATH in detected profiles. |

## Safe invocation patterns

The goal is to ensure that when an installer subprocess spawns, it
inherits the correct `XDG_*` variables, `CARGO_HOME`, and `PATH` — so
tools are installed to the right locations and the installer's profile
modifications target the correct files. The
[POSIX profile](posix-profile.md) handles the common case. These
patterns address edge cases and override situations.

### mise

mise's base installer (`curl https://mise.run | sh`) downloads a binary
to `~/.local/bin/mise` and does not modify any profile files. The
shell-specific endpoints (`curl https://mise.run/zsh | sh`) add an
activation line to the detected shell config. In this framework, use
the base installer only — shell activation is managed in
`conf.d/70-tools.zsh` as the single source of truth.

```sh
# Safe mise installation: binary only, no profile injection.
curl https://mise.run | sh

# If ~/.local/bin is not yet on PATH (fresh machine before .profile is loaded):
PATH="$HOME/.local/bin:$PATH" mise --version
```

### rv

rv's installer is similar: downloads a binary to `~/.local/bin/rv` and
writes nothing to shell profiles by default. The `rv shell zsh` command
emits an activation block that you eval from `conf.d/70-tools.zsh` —
already wired in by this framework.

```sh
# Safe rv installation
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/spinel-coop/rv/releases/latest/download/rv-installer.sh | sh

# Verify
rv --version
```

### Homebrew

Homebrew's installer is hardcoded to `/bin/bash -c "$(curl ...)"`. It
does not modify any profile files — it prints post-install instructions
and expects you to add `eval "$(brew shellenv)"` to your profile
manually. In this framework, do not add the eval line. Instead,
Homebrew's bin directory (`/opt/homebrew/bin` on Apple Silicon,
`/usr/local/bin` on Intel) is already on PATH via `/etc/paths` and
macOS's `path_helper`. Verify with `which brew` after installation.

```sh
# Standard Homebrew installation (no special flags needed).
# This spawns /bin/bash regardless of your default shell.
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Verify brew is on PATH (should be via /etc/paths on macOS)
which brew

# If `which brew` fails (Linux, or non-standard prefix):
# Add to conf.d/70-tools.zsh:
#   if [[ -d /opt/homebrew ]]; then
#     eval "$(/opt/homebrew/bin/brew shellenv)"
#   fi
```

### rustup

rustup is the most aggressive profile modifier in this list. Its
installer writes PATH entries to `~/.profile`, `~/.bashrc`, and
`~/.zshenv` simultaneously — every one it finds. It also respects
`CARGO_HOME` and `RUSTUP_HOME` environment variables. Since
`~/.profile` already exports these to the XDG location, rustup will
install to the correct directories. Use `--no-modify-path` to prevent
it from appending redundant PATH entries to your shell profiles.

```sh
# Safe rustup installation: respects CARGO_HOME/RUSTUP_HOME from
# ~/.profile, skips all profile modification.
curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | \
  sh -s -- --no-modify-path -y

# If environment variables are not inherited, export explicitly:
CARGO_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/cargo" \
RUSTUP_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/rustup" \
curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | \
  sh -s -- --no-modify-path -y
```

### nvm (legacy — not recommended)

nvm is not used in this framework — mise replaces it entirely. If you
encounter a project that requires nvm for team compatibility, install
it with `--no-use` to prevent it from modifying your profile and
source it from a dedicated `conf.d/` fragment guarded by a conditional.

### Post-install cleanup

After installing any tool that modifies shell profiles, run the audit
from `bootstrap.sh`:

```sh
# Scan for rogue injections
sh bootstrap.sh --dry-run 2>&1 | grep '\[rogue\]'
```

The audit checks `~/.profile`, `~/.bash_profile`, `~/.bashrc`,
`~/.zshenv`, and `~/.zshrc` for lines injected by common installers
(`NVM_DIR`, `VOLTA_HOME`, `BUN_INSTALL`, `cargo/env`, `pyenv init`,
`asdf.sh`, `conda init`, etc.). Remove any matches and rely on the
framework's `conf.d/10-path.zsh` as the single source of truth.
