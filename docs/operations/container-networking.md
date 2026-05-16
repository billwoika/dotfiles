# Container Networking

Container networking is surprisingly complex for something that
markets itself as "just run it in a container." On Linux, the
container runtime creates real bridge interfaces, inserts iptables
rules, and runs its own DNS resolver. On macOS, both Podman and
Docker Desktop run a Linux VM and proxy traffic through userspace — a
fundamentally different model that produces different failure modes.
This page covers how each network mode works, how container DNS
resolution differs from host DNS, and how container networking
interacts with VPNs and host network assumptions.

The framework recommends Podman as the primary container runtime (see
[Containers and Devcontainers](../tools/containers.md)). Podman's CLI
is intentionally Docker-compatible — `podman run`, `podman network
create`, `podman compose` all work identically. Where this page shows
`podman` commands, substitute `docker` if your environment requires
it. Behavior differences between runtimes are called out explicitly.

## The two runtime models

### Linux: native networking

On Linux, Podman (and Docker) manipulate the host kernel's network
stack directly:

- **Bridge interfaces** (`podman0`, `cni-podman0`, or `docker0`) are
  real Linux bridges visible in `ip link`.
- **veth pairs** connect each container's network namespace to the
  bridge.
- **iptables/nftables rules** handle NAT (masquerade for outbound
  traffic), port publishing (DNAT for inbound), and inter-container
  isolation.
- **The embedded DNS server** (`127.0.0.11` inside containers)
  resolves container names on user-defined networks.

This is actual networking — the same primitives that production
infrastructure uses. Debugging tools (`tcpdump`, `iptables -L`,
`ip netns exec`) work directly.

**Podman-specific note:** Podman runs rootless by default. Rootless
containers use `slirp4netns` or `pasta` for networking rather than
manipulating host iptables directly. This avoids the iptables
conflicts described later in this page but introduces its own
tradeoffs (slightly higher latency, different port binding behavior).

### macOS: VM-proxied networking

Both Podman (via `podman machine`) and Docker Desktop run containers
inside a lightweight Linux VM. The networking path:

1. Container traffic exits the container's network namespace into the
   VM's bridge.
2. The VM's userspace proxy forwards traffic to the macOS host via a
   shared network socket.
3. Port bindings appear on `localhost` on the Mac because the proxy
   listens there.

**Implications:**

- There is no bridge interface on the macOS host. `ifconfig` shows no
  container-related interfaces.
- Container-to-host communication uses a special DNS name
  (`host.docker.internal` or `host.containers.internal` for Podman)
  rather than the host's IP, because the container is in a VM with a
  different network namespace.
- Performance is lower because all traffic passes through userspace
  proxying rather than kernel forwarding.
- `tcpdump` on the macOS host does not see container traffic — the
  traffic is inside the VM.

## Network modes

### Bridge (default)

Every container gets its own IP on an isolated network. Containers on
the same bridge can communicate; the outside world reaches them only
through published ports.

```sh
# Default bridge (legacy, no embedded DNS between containers)
podman run -p 8080:80 nginx

# User-defined bridge (embedded DNS, containers resolve each other by name)
podman network create mynet
podman run --network mynet --name api myapp
podman run --network mynet --name db postgres
# "api" can resolve "db" by hostname; the reverse is also true
```

**When to use:** most development scenarios. Containers are isolated
by default, communicate by name on shared networks, and expose only
what you publish.

**Subnet allocation:**

The runtime allocates bridge subnets from a default pool. Typical
defaults:

- Default bridge: `10.88.0.0/16` (Podman) or `172.17.0.0/16` (Docker)
- User-defined bridges: allocated sequentially from adjacent ranges.
- Compose creates one network per project, each getting its own
  subnet.

These subnets can conflict with corporate VPN routes that claim RFC
1918 ranges. See "VPN conflicts" below.

### Host

The container shares the host's network namespace. No isolation, no
NAT, no port publishing — the container's processes bind directly to
host ports.

```sh
podman run --network host nginx
# nginx binds to port 80 on the host directly
```

**When to use:**

- Performance-critical networking where NAT overhead matters.
- Tools that need to see host network traffic (packet capture,
  network debugging tools).
- Services that need to bind to many ports dynamically (some service
  meshes, mDNS responders).

**Platform note:** `--network host` on macOS (both Podman and Docker
Desktop) means the container uses the *VM's* network namespace, not
the Mac's. This is rarely what you want. On Linux it works as
described.

### Overlay

Overlay networks span multiple hosts (Docker Swarm mode or Podman
with plugins). Traffic between containers on different hosts is
encapsulated in VXLAN and routed over the underlying network.

```sh
# Docker Swarm example:
docker network create --driver overlay --attachable myoverlay
docker run --network myoverlay --name svc1 myapp
```

**When to use:** multi-host container deployments without Kubernetes.
Rare in local development.

**Interaction with host networking:** overlay networks add their own
routing rules and VXLAN interfaces. These can conflict with VPN routes
to the same subnet ranges, though this is uncommon in practice.

### None

No networking at all. The container has only a loopback interface.

```sh
podman run --network none myapp
```

**When to use:** security-sensitive workloads that must not have
network access (secret processing, offline builds).

## DNS inside containers

### The embedded DNS server

On user-defined bridge networks, the runtime provides an embedded DNS
server at `127.0.0.11` inside each container. This server:

- Resolves container names to their bridge IP addresses.
- Resolves service names (in Compose) to the set of container IPs
  behind that service.
- Forwards queries it cannot resolve to the upstream DNS servers
  configured for the container.

On the default bridge network, this embedded DNS does not exist.
Containers on the default bridge can only resolve each other by IP.

### Where upstream DNS comes from

When the runtime creates a container, it determines the upstream DNS
by:

1. Checking `--dns` flags on the run command.
2. Checking runtime configuration (`containers.conf` for Podman,
   `daemon.json` for Docker).
3. Copying the host's `/etc/resolv.conf` (with filtering — see
   below).

**The `127.0.0.53` problem (Linux):**

If the host uses systemd-resolved, `/etc/resolv.conf` contains
`nameserver 127.0.0.53`. The runtime detects this and attempts to
substitute the real upstream servers from resolved. This detection
works most of the time but can fail with non-standard configurations,
leaving containers with no working DNS.

**The VPN problem:**

If the host's DNS changes while a container is running (VPN connects,
DNS servers change), the container retains its original DNS
configuration. Containers created before VPN connection cannot resolve
corporate domains. Containers created after VPN connection may lose
DNS when VPN disconnects.

**The fix for both:** explicit DNS in your Compose file:

```yaml
services:
  api:
    image: myapp
    dns:
      - 8.8.8.8
      - 8.8.4.4
    dns_search:
      - corp.example.com
```

Or runtime-wide:

=== "Podman"

    ```toml
    # ~/.config/containers/containers.conf
    [containers]
    dns_servers = ["8.8.8.8", "8.8.4.4"]
    ```

=== "Docker"

    ```json
    {
      "dns": ["8.8.8.8", "8.8.4.4"]
    }
    ```

    (in `~/.docker/daemon.json`)

### Container-to-host communication

A container often needs to reach a service running on the host (a
database, a mock server, a proxy). The mechanism differs by platform
and runtime:

=== "macOS (Podman)"

    ```sh
    # Inside the container, the host is reachable at:
    host.containers.internal
    # or the Docker-compatible alias:
    host.docker.internal

    # In a compose file:
    services:
      api:
        extra_hosts:
          - "host.docker.internal:host-gateway"
    ```

=== "macOS (Docker Desktop)"

    ```sh
    # Inside the container, the host is reachable at:
    host.docker.internal

    # In docker-compose.yml:
    services:
      api:
        extra_hosts:
          - "host.docker.internal:host-gateway"
    ```

=== "Linux"

    ```sh
    # Option 1: --network host (container IS on the host network)
    podman run --network host myapp

    # Option 2: Use the bridge gateway IP
    podman inspect bridge | grep Gateway

    # Option 3: Add host.docker.internal explicitly
    podman run --add-host host.docker.internal:host-gateway myapp

    # In a compose file:
    services:
      api:
        extra_hosts:
          - "host.docker.internal:host-gateway"
    ```

## Port binding conflicts

When a container publishes a port (`-p 8080:80`), the runtime binds
that port on the host. Common conflicts:

- **Another container** already published the same port. The runtime
  refuses to start the second container.
- **A host process** already listens on that port. The runtime refuses
  to bind.
- **VPN tunnel interface** — on some full-tunnel VPN configurations,
  port bindings on `0.0.0.0` become unreachable because traffic to
  the host's IP routes through the tunnel rather than locally.

**Podman rootless note:** in rootless mode, Podman cannot bind ports
below 1024 without additional configuration (`net.ipv4.ip_unprivileged_port_start`
sysctl or a port forward helper).

### Binding to localhost only

By default, `-p 8080:80` binds on all interfaces (`0.0.0.0:8080`).
For development services that should only be reachable locally:

```sh
podman run -p 127.0.0.1:8080:80 nginx
```

This avoids conflicts with VPN routing (traffic to `127.0.0.1` never
leaves the host) and avoids exposing development services to the
network.

### Finding what's using a port

```sh
# macOS
lsof -i :8080

# Linux
ss -tlnp | grep 8080
```

## VPN conflicts

### Subnet overlap

The most common conflict: the VPN routes `172.16.0.0/12` through the
tunnel, and the container runtime's bridge networks live in that same
range (Docker defaults to `172.17.0.0/16`; Podman defaults to
`10.88.0.0/16` which is less likely to conflict but can still overlap
with VPN-claimed ranges). Traffic destined for containers routes
through the VPN instead of locally.

**Diagnosis:**

```sh
# Check if the container subnet routes through VPN
# macOS:
route -n get 172.17.0.1
# Linux:
ip route get 172.17.0.1

# If the output shows the VPN interface (utun/tun), there's a conflict
```

**Fix:** move the runtime to a subnet outside the VPN's claimed range:

=== "Podman"

    ```toml
    # ~/.config/containers/containers.conf
    [network]
    default_subnet = "192.168.200.0/24"
    ```

    Or per-network: `podman network create --subnet 192.168.201.0/24 mynet`

=== "Docker"

    ```json
    {
      "bip": "192.168.200.1/24",
      "default-address-pools": [
        {"base": "192.168.201.0/24", "size": 24},
        {"base": "192.168.202.0/24", "size": 24}
      ]
    }
    ```

    (in `~/.docker/daemon.json`)

Restart the runtime after changing configuration. Existing networks
need to be recreated.

### DNS resolution from containers through VPN

Containers that need to resolve corporate hostnames (internal APIs,
databases) face a layered problem:

1. The container's DNS points at the embedded resolver
   (`127.0.0.11`).
2. The embedded resolver forwards unresolved queries to the
   container's upstream DNS (from `/etc/resolv.conf` at creation
   time).
3. That upstream needs to be the VPN's DNS server — but only for
   corporate domains.

**Solution with user-defined networks:**

```yaml
services:
  api:
    networks:
      - default
    dns:
      - 10.0.0.1      # Corporate DNS (through VPN)
      - 8.8.8.8       # Fallback for public DNS

networks:
  default:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.200.0/24  # Non-conflicting subnet
```

### Routing container traffic through VPN

By default, container outbound traffic exits via the host's default
route. If the VPN is split-tunnel and a container needs to reach a
VPN-only destination:

- On **Linux (rootful):** iptables masquerade rules use the host's
  routing table. If the host has a route to the VPN subnet, container
  traffic follows it automatically.
- On **Linux (rootless/Podman):** traffic exits via slirp4netns or
  pasta, which also follows the host routing table — VPN routes apply.
- On **macOS:** traffic from containers routes through the VM's
  network stack to the host, then follows the host's VPN routes. This
  usually works transparently.

If it doesn't work, verify that the VPN route is present on the host
and that the VPN is not filtering by source IP (some corporate VPNs
only allow traffic from the tunnel interface's assigned IP).

## iptables interaction (Linux, rootful only)

Docker (and rootful Podman with the `netavark` backend) inserts
iptables rules for container networking. Docker uses dedicated chains
(`DOCKER`, `DOCKER-USER`, `DOCKER-ISOLATION-STAGE-*`); Podman/netavark
uses `NETAVARK-*` chains. These rules:

- NAT outbound container traffic (masquerade).
- DNAT inbound traffic to published ports.
- Isolate networks from each other.

**The problem:** these rules are inserted with high priority. If you
also manage iptables (or nftables) rules for other purposes (firewall,
VPN kill switch, port forwarding), the container runtime's rules can
shadow yours, or yours can break container networking.

**Viewing the rules:**

```sh
# Docker
sudo iptables -L -t nat --line-numbers | grep -i docker
sudo iptables -L DOCKER-USER

# Podman/netavark
sudo iptables -L -t nat --line-numbers | grep -i netavark
```

**Docker's DOCKER-USER chain:** Docker provides this chain
specifically for user-added rules that should be evaluated before
Docker's own rules. If you need to restrict container traffic (e.g.,
block containers from reaching certain hosts), add rules here rather
than modifying the runtime's chains directly.

```sh
# Block containers from reaching a specific IP
sudo iptables -I DOCKER-USER -d 10.0.0.50 -j DROP

# Allow only established connections from containers to VPN range
sudo iptables -I DOCKER-USER -d 10.0.0.0/24 -m state --state NEW -j DROP
```

**Podman rootless avoids all of this.** Rootless networking uses
slirp4netns or pasta, which operate entirely in userspace without
iptables. This is one of the reasons the framework recommends Podman
— rootless-by-default means fewer conflicts with host networking.

## Compose networking

Compose (both `podman compose` and `docker compose`) creates a
network per project (`<project>_default`). All services in the Compose
file join this network and can resolve each other by service name.

```yaml
services:
  api:
    build: .
    ports:
      - "8080:8080"
  redis:
    image: redis:7
  postgres:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: devonly
```

In this setup:
- `api` can connect to `redis:6379` and `postgres:5432` by service
  name.
- Only `api` is exposed to the host (port 8080).
- `redis` and `postgres` are only reachable from within the Compose
  network.

### Sharing networks between Compose projects

Two Compose projects that need to communicate can share a network:

```yaml
# project-a/compose.yml
services:
  api:
    networks:
      - shared

networks:
  shared:
    name: shared-dev-network
    driver: bridge
```

```yaml
# project-b/compose.yml
services:
  worker:
    networks:
      - shared

networks:
  shared:
    external: true
    name: shared-dev-network
```

## Debugging container networking

```sh
# What network is a container on?
podman inspect <container> | jq '.[0].NetworkSettings.Networks'

# What IP does it have?
podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' <container>

# Can the container reach the host?
podman exec <container> ping -c1 host.containers.internal

# Can the container resolve DNS?
podman exec <container> nslookup example.com

# What DNS servers is the container using?
podman exec <container> cat /etc/resolv.conf

# Capture traffic on the container bridge (Linux only)
sudo tcpdump -i podman0 -n port 5432

# List all networks and their subnets
podman network ls
podman network inspect podman | jq '.[0].subnets'
```
