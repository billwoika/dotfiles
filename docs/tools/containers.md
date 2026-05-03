# Containers, Compose, and Devcontainers

Containers fill three roles in a developer's daily workflow: shipping
reproducible runtime artifacts to production, isolating dependent
services (Postgres, Redis, search engines, message brokers) from the
host, and — optionally — isolating the development environment itself.
This page establishes a runtime-agnostic container strategy, a strong
opinion on Compose as the local-services orchestrator, and a
defensible position on devcontainers as useful-but-optional.

!!! info "Scope"

    Container runtimes, engineer-facing tradeoffs, Compose for local
    services, and devcontainers. Production container builds,
    registries, and deployment pipelines are out of scope.

## Why containers, and why not

Containers are not free. For a developer's interactive workflow there
are three real costs:

- **Filesystem performance overhead on macOS** — every container engine
  runs a Linux VM with bind-mounts across that boundary.
  Filesystem-heavy operations (Rails asset compilation, large monorepo
  grep, Node module dependency resolution) are measurably slower.
- **Host-service integration friction** — the 1Password agent, system
  Keychain, Tailscale, VPN clients, and editor servers all live on the
  host. Reaching them from inside a container is per-tool fiddly.
- **Cognitive overhead** — every problem now has two debugging surfaces
  (host and container).

What containers do better than any alternative:

- **Isolating dependent services** — you cannot cleanly install three
  Postgres major versions side-by-side with Homebrew; you can with
  three Compose stacks.
- **Reproducible production builds** — a Dockerfile is the canonical
  record of what runs in production.
- **Crossing platform boundaries** — CI runs Linux, your laptop is
  macOS, production is amd64 Linux. Container builds are the same
  artifact on all three.

**The framework's stance:** Use Compose for dependent services. Use
Dockerfiles for production builds. Use devcontainers selectively —
the default development loop is host-native with mise, not
container-based.

## Container runtime selection

On Linux, the runtime question is settled: native `docker` or `podman`
run directly on the host kernel. On macOS, every option is a Linux VM.

### Recommendation matrix

| Runtime | License | Best for |
|---------|---------|----------|
| **Docker Desktop** | Free < 250 employees/$10M; paid otherwise | Teams with existing subscriptions, GUI dependency |
| **Podman** | Apache 2.0, always free | License-unrestricted, rootless-by-default security |
| **Colima** | MIT, always free | CLI-only, simple Docker-API compatibility |
| **OrbStack** | Commercial (free personal) | Fastest macOS performance, best Apple Silicon integration |

**Docker Desktop** is the reference implementation — every tutorial
assumes it. The licensing model is the constraint: not free for
organizations over 250 employees or $10M revenue.

**Podman** is Red Hat's daemonless, rootless-by-default engine. CLI is
intentionally Docker-compatible. Compose support via `podman compose`
is mostly complete.

**Colima** is a thin wrapper around Lima. Fully free, CLI-only, choice
of runtime backend.

**OrbStack** has measurably the fastest filesystem performance on Apple
Silicon and the lowest idle resource consumption. Commercial, but
excellent for personal machines.

### The Docker socket symlink

Tools that hard-code `/var/run/docker.sock` break with Podman or
Colima until you create the symlink:

```sh
# For Podman
sudo ln -sfn "$HOME/.local/share/containers/podman/machine/podman.sock" \
  /var/run/docker.sock

# For Colima
sudo ln -sfn "$HOME/.colima/default/docker.sock" \
  /var/run/docker.sock
```

## Compose: the real workhorse

Compose is more important than the runtime choice. A `compose.yml`
checked into the project root declares every service the application
depends on, with versions pinned, ports mapped, and health checks
configured.

### Reference compose.yml

```yaml
# compose.yml — local development services
services:
  postgres:
    image: postgres:16-alpine
    ports: ["5432:5432"]
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: app
      POSTGRES_DB: myapp_dev
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s

volumes:
  pgdata:
```

### compose.override.yml — local customization

The override file is gitignored and lets individual engineers add
services, change ports, or mount volumes without modifying the tracked
`compose.yml`.

### Why services in Compose, application on host

The framework's position: **dependent services in containers, the
application on the host.** The application's hot-reload, debugger
attach, and editor LSP all work best with direct host filesystem
access. The services (Postgres, Redis, Elasticsearch) don't need hot
reload and benefit from isolation.

### Compose lifecycle aliases

```sh
alias dcup='docker compose up -d'
alias dcdown='docker compose down'
alias dcps='docker compose ps'
alias dclogs='docker compose logs -f'
alias dcrestart='docker compose restart'
```

## Dockerfiles for production builds

Production Dockerfiles should use multi-stage builds, pin base images
by digest, and run as a non-root user. The framework provides
reference templates in the `devcontainer/` directory.

## Devcontainers

Devcontainers standardize the development environment as a container
definition checked into the repo. VS Code and JetBrains both support
the specification natively.

### When to opt in

- Projects with complex system dependencies (specific OpenSSL
  versions, GIS toolchains, ML frameworks)
- Onboarding new engineers who need "clone and open" simplicity
- Teams where mise alone doesn't cover the runtime requirements

### When to stay on host

- Projects where filesystem performance matters (Rails, large
  monorepos)
- Projects where the mise.toml + compose.yml pattern already works
- Engineers who need direct host integration (1Password agent,
  Tailscale, VPN)

### Reference devcontainer.json

The framework ships reference templates in the `devcontainer/`
directory of the dotfiles repository:

- `devcontainer.json` — base configuration
- `Dockerfile.dev` — development container image
- `compose.yml.example` — Compose integration
- `post-create.sh` — post-creation setup script

### The dotfiles-in-container pattern

Devcontainers can clone your dotfiles into the container automatically.
In VS Code settings:

```json
{
  "dotfiles.repository": "https://github.com/your-username/dotfiles",
  "dotfiles.installCommand": "sh bootstrap.sh"
}
```

This runs `bootstrap.sh` inside the container, giving you the same
shell configuration, aliases, and tool setup as your host.

## Performance tuning

Filesystem performance is the primary concern on macOS. Options:

- **Named volumes** for dependencies (`node_modules/`, `.bundle/`,
  `.venv/`) — stored inside the VM, not bind-mounted
- **Delegated mounts** (`consistency: delegated` in Compose) — relaxes
  consistency guarantees for better write performance
- **OrbStack** — if switching runtimes is an option, it has the best
  bind-mount performance on Apple Silicon

## Cross-cutting concerns

### Secrets in containers

Never bake secrets into images. Use `--secret` mounts in BuildKit for
build-time secrets, and environment variables (from direnv or Compose
environment files) for runtime secrets.

### Container images

Prefer Alpine-based images for services. Use official images from
Docker Hub or Chainguard for supply-chain assurance.
