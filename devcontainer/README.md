# Devcontainer Reference Templates

This directory holds reference templates for using devcontainers with
this framework. Copy these files into a project's `.devcontainer/`
directory and adapt as needed.

See [docs/tools/containers.md](../docs/tools/containers.md) for the full rationale and
lifecycle. Quick summary:

- `devcontainer.json` — the devcontainer spec config. Goes at
  `<project>/.devcontainer/devcontainer.json`.
- `Dockerfile.dev` — a slim Debian base with mise + rv installed.
  Goes at `<project>/.devcontainer/Dockerfile.dev`.
- `post-create.sh` — runs once after container creation to install
  dotfiles and project dependencies. Goes at
  `<project>/.devcontainer/post-create.sh`.
- `compose.yml.example` — a reference compose stack for local
  dependent services (Postgres, Redis, etc.). Goes at
  `<project>/compose.yml`.

## Usage

In a project that wants devcontainer support:

```sh
DOTFILES=~/development/personal/repos/dotfiles
cd ~/development/work/repos/my-service
mkdir -p .devcontainer
cp "$DOTFILES/devcontainer/devcontainer.json"   .devcontainer/
cp "$DOTFILES/devcontainer/Dockerfile.dev"      .devcontainer/
cp "$DOTFILES/devcontainer/post-create.sh"      .devcontainer/
chmod +x .devcontainer/post-create.sh

# If the project doesn't already have a compose stack:
cp "$DOTFILES/devcontainer/compose.yml.example" compose.yml

# Customize:
$EDITOR .devcontainer/devcontainer.json   # adjust name, ports, extensions
$EDITOR compose.yml                        # adjust services
```

Then open the project in VS Code or Cursor. The editor will prompt you
to "Reopen in Container."

## VS Code dotfiles setting

For the dotfiles bootstrap to work inside the container, set this once
in your editor's User-scope `settings.json`:

```json
{
  "dotfiles.repository": "github.com/yourusername/dotfiles",
  "dotfiles.targetPath": "~/dotfiles",
  "dotfiles.installCommand": "~/dotfiles/bootstrap.sh"
}
```

The reference `devcontainer.json` also bind-mounts the host's
`~/development/personal/repos/dotfiles` to `~/dotfiles` *inside* the
container, which serves the same purpose for users who have the
dotfiles checked out locally but haven't configured the editor
setting. (The container keeps the flat `~/dotfiles` target on purpose:
the `~/development` profile tree — git identity by path, per-profile
mise configs — is a host concept with no meaning in a throwaway
container home.)
