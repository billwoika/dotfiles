# Containers, Compose, and Devcontainers

Containers fill three roles in a developer's daily workflow: shipping
reproducible runtime artifacts to production, isolating dependent
services (Postgres, Redis, search engines, message brokers) from the
host, and — optionally — isolating the development environment itself.
This page establishes Podman as the preferred runtime, a strong
opinion on Compose as the local-services orchestrator, and a
defensible position on devcontainers as useful-but-optional.

!!! info "Scope"

    Container runtimes, engineer-facing tradeoffs, Compose for local
    services, and devcontainers. Production container builds,
    registries, and deployment pipelines are out of scope.
    For networking behavior (bridge modes, DNS, VPN interactions),
    see [Container Networking](../operations/container-networking.md).

## Why containers, and why not

Containers are not free. For a developer's interactive workflow there
are three real costs:

- **Filesystem performance overhead on macOS** — every container engine
  on macOS runs a Linux VM with bind-mounts across that boundary.
  Filesystem-heavy operations (Rails asset compilation, large monorepo
  grep, Node module dependency resolution) are measurably slower. On
  Linux, containers run natively on the host kernel — filesystem
  bind-mount performance is near-native and this concern does not
  apply.
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

**The framework's stance:** Podman as the container runtime. Compose
for dependent services. Containerfiles for production builds.
Devcontainers selectively — the default development loop is
host-native with mise, not container-based.

## Container runtime selection

On Linux, the runtime question is settled: Podman runs natively on the
host kernel with no daemon. On macOS, every container engine runs a
Linux VM — the question is which VM approach gives you the best
tradeoffs.

### The framework recommends Podman

Podman is the framework's default for three reasons:

1. **Always free.** Apache 2.0 license with no revenue or headcount
   gates. Docker Desktop's licensing model restricts free use to
   organizations under 250 employees or $10M revenue — a threshold
   that catches most mid-size companies by surprise.
2. **Rootless by default.** Containers run without a privileged daemon.
   No root-owned `dockerd` process, no iptables manipulation from a
   system service, fewer attack surfaces.
3. **CLI-compatible with Docker.** `podman run` and `podman build`
   accept the same flags as their `docker` equivalents (Docker-only
   flags are kept as accepted no-ops so scripts don't break), so
   muscle memory, scripts, and CI definitions transfer. One caveat:
   `podman compose` is a thin wrapper that shells out to an external
   provider — `docker-compose` or `podman-compose` must be installed
   for it to do anything. It is not a built-in reimplementation.

The Docker CLI remains the *lingua franca* of container tooling —
tutorials, Stack Overflow answers, and CI examples all use `docker`
commands. The framework's zsh configuration retains `docker` in
completion definitions and aliases because `podman` is a drop-in
replacement: the commands are identical, and many engineers alias
`docker=podman` or symlink the binary.

### Alternative runtimes

| Runtime | License | When it makes sense |
|---------|---------|---------------------|
| **Podman** | Apache 2.0, always free | Default choice. Rootless, daemonless, CLI-compatible with Docker |
| **OrbStack** | Commercial (free personal) | Fastest macOS filesystem performance, best Apple Silicon integration. Worth evaluating for personal machines |
| **Colima** | MIT, always free | CLI-only Docker-API compatibility layer over Lima. Lighter than Docker Desktop, heavier than Podman |
| **Docker Desktop** | Paid above 250 employees/$10M | Teams with existing subscriptions, GUI dependency, or vendor-mandated Docker Enterprise support |

### The Docker socket symlink

Tools that hard-code `/var/run/docker.sock` break with Podman or
Colima until you create the compatibility symlink. On current Podman
(5.x) the machine socket is a per-machine path that you must not
hard-code — discover it with `podman machine inspect`:

```sh
# For Podman (macOS) — resolve the real socket, then symlink it
PODMAN_SOCK="$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"
sudo ln -sfn "$PODMAN_SOCK" /var/run/docker.sock

# For Colima
sudo ln -sfn "$HOME/.colima/default/docker.sock" \
  /var/run/docker.sock
```

Podman also supports `DOCKER_HOST` as an environment variable, which
avoids the symlink for tools that respect it. Again, resolve the path
rather than hard-coding it:

```sh
export DOCKER_HOST="unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"
```

## Compose: the real workhorse

Compose is more important than the runtime choice. A `compose.yml`
checked into the project root declares every service the application
depends on, with versions pinned, ports mapped, and health checks
configured. Both `podman compose` and `docker compose` read the same
file format — the examples below work with either runtime.

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

The framework's aliases use `docker compose` as the command because
Podman's CLI is a drop-in replacement — these work identically with
either runtime. Engineers who prefer explicit Podman invocations can
override these in `aliases.local.zsh`.

```sh
alias dcup='docker compose up -d'
alias dcdown='docker compose down'
alias dcps='docker compose ps'
alias dclogs='docker compose logs -f'
alias dcrestart='docker compose restart'
```

## Containerfiles for production builds

Production container images should use multi-stage builds, pin base
images by digest, and run as a non-root user. Podman/Buildah look for
`Containerfile` first and fall back to `Dockerfile` (Containerfile
wins if both are present); Docker only reads `Dockerfile` by default
and needs `-f Containerfile` otherwise. The framework uses `Containerfile`
in new projects and `Dockerfile` where existing CI expects it — the
content is identical.

### Reference multi-stage build

```dockerfile
# Containerfile — multi-stage production build
FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY . .
RUN npx vite build

FROM node:22-slim AS runtime
RUN useradd -r -s /bin/false appuser
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./
USER appuser
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

Key patterns:

- **Multi-stage** — build dependencies stay in the build stage; the
  runtime image is smaller and has a reduced attack surface.
- **Non-root user** — `USER appuser` ensures the process does not run
  as root inside the container.
- **npm ci** (not `bun install`) — production builds should use the
  ecosystem's most battle-tested tooling. The package manager speed
  advantage matters at development time, not in a CI pipeline that
  runs once per push.
- **Pin base images** — for production, pin by digest
  (`node:22-slim@sha256:...`) rather than tag to prevent silent
  upstream changes.

The framework provides additional reference templates in the
`devcontainer/` directory.

## Devcontainers

Devcontainers standardize the development environment as a container
definition checked into the repo. JetBrains IDEs (2025.3+) support the
specification natively in-IDE; VS Code supports it through the
first-party **Dev Containers** extension (made by Microsoft, but an
add-on rather than built into the core editor).

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

Filesystem performance is the primary concern on macOS. On Linux,
containers run natively on the host kernel and these tuning steps are
unnecessary. Options for macOS:

- **Named volumes** for dependencies (`node_modules/`, `.bundle/`,
  `.venv/`) — stored inside the VM, not bind-mounted
- **Delegated mounts** (`consistency: delegated` in Compose) — the
  Compose spec still accepts the `consistency` field, but its values
  are platform-specific and, since Docker Desktop moved to VirtioFS,
  it is effectively a no-op rather than the meaningful write-perf knob
  it was under the old osxfs/gRPC-FUSE mounts. Harmless to keep; don't
  rely on it for speed.
- **OrbStack** — if switching runtimes is an option, it has the best
  bind-mount performance on Apple Silicon
- **Podman machine resources** — `podman machine set --cpus 4 --memory
  8192` adjusts the VM's allocation, but these two flags are
  **QEMU-only**. On a default Apple Silicon machine (the `applehv`
  provider, which is also where Rosetta x86 translation runs), they do
  not apply — recreate the machine with the desired size, or use a
  provider/`containers.conf` setting instead.

## Cross-cutting concerns

### Secrets in containers

Never bake secrets into images. Use `--secret` mounts for build-time
secrets, and environment variables (from direnv or Compose environment
files) for runtime secrets. Both Podman and Docker support the
`--secret` flag and the `RUN --mount=type=secret` Containerfile
syntax — but only Docker implements it via BuildKit. Podman's build
backend (Buildah) provides the same interface without BuildKit, so the
command is portable even though the underlying machinery differs:

```sh
podman build --secret id=npm_token,env=NPM_TOKEN -t myapp .
```

### Container images

Prefer Alpine-based images for services. Use official images from
Docker Hub, Red Hat's registry (`registry.access.redhat.com`), or
Chainguard for supply-chain assurance. Podman can pull from any
OCI-compliant registry — configure search order in
`$XDG_CONFIG_HOME/containers/registries.conf`.

### Podman-specific configuration

Podman reads configuration from `$XDG_CONFIG_HOME/containers/`:

- `containers.conf` — runtime defaults (log driver, network backend,
  engine settings)
- `registries.conf` — registry search order and mirrors
- `storage.conf` — image storage location and driver

These files are XDG-compliant by default, which aligns with the
framework's directory conventions.
