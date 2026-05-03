# Devcontainer Reference Templates

This directory holds reference templates for using devcontainers with
this framework. Copy these files into a project's `.devcontainer/`
directory and adapt as needed.

See **Section 21** of the framework document for the full rationale and
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
cd ~/work/my-service
mkdir -p .devcontainer
cp ~/dotfiles/devcontainer/devcontainer.json   .devcontainer/
cp ~/dotfiles/devcontainer/Dockerfile.dev      .devcontainer/
cp ~/dotfiles/devcontainer/post-create.sh      .devcontainer/
chmod +x .devcontainer/post-create.sh

# If the project doesn't already have a compose stack:
cp ~/dotfiles/devcontainer/compose.yml.example compose.yml

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

The reference `devcontainer.json` also bind-mounts `~/dotfiles` from the
host, which serves the same purpose for users who have the dotfiles
checked out locally but haven't configured the editor setting.
