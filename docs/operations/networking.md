# Networking

The developer workstation is a surprisingly hostile networking
environment. A corporate VPN rewrites your routing table and DNS.
Container runtimes create bridge networks that shadow host routes.
Tailscale installs a userspace tunnel that claims ownership of
`/etc/resolv.conf`. A debugging proxy needs to intercept HTTPS but
the VPN's split tunnel won't route to localhost. Each tool is
reasonable in isolation; stacked together they produce failures that
look like "the internet is broken" but are actually three layers of
conflicting network configuration.

This section treats workstation networking as a first-class
operational concern — not because engineers need to become network
administrators, but because the failure mode of *not* understanding
the stack is hours of debugging something that turns out to be a DNS
override you didn't know existed.

## The layered model

Every packet leaving your machine passes through a stack of decisions.
When networking breaks, the fix is always "figure out which layer is
lying":

| Layer | What decides | Typical saboteurs |
|-------|-------------|-------------------|
| **Physical/virtual interface** | Which NIC or tunnel carries traffic | VPN clients adding utun interfaces, container bridge adapters |
| **Routing table** | Where packets for a given destination go | VPN split-tunnel rules, container overlay networks, Tailscale MagicDNS |
| **DNS resolution** | What IP a hostname resolves to | resolv.conf rewrites, scoped DNS on macOS, systemd-resolved stub listeners |
| **Firewall / packet filter** | Whether traffic is allowed through | macOS pf, iptables/nftables, container runtime iptables rules, Little Snitch |
| **Application proxy** | Whether traffic is intercepted before leaving | HTTP_PROXY vars, mitmproxy, PAC files, browser proxy settings |

Diagnosis always works top-down: check if the interface exists, check
if the route points where you think, check if DNS resolves correctly,
check if the firewall allows it, check if something is proxying it.
Most "networking is broken" complaints are layer 3 (DNS) masquerading
as layer 1 (connectivity).

## Why these tools fight each other

The root problem is **ownership of shared mutable state**. The routing
table, the DNS configuration, and the interface list are global — every
tool that touches networking writes to the same places, and none of them
coordinate:

- **VPN clients** assume they own the default route and DNS. A
  full-tunnel VPN literally replaces your internet connection with a
  tunnel through corporate infrastructure. Even split-tunnel VPNs
  typically claim DNS unconditionally.
- **Tailscale** wants to be the DNS resolver so that MagicDNS (hostname
  resolution for tailnet nodes) works transparently. On Linux, this
  means rewriting `/etc/resolv.conf` — which breaks any symlink-based
  management of that file.
- **Container runtimes** (Podman, Docker) create their own bridge
  networks, insert iptables rules (on Linux) or a userspace proxy (on
  macOS), and run their own DNS resolver inside containers. Containers
  can't resolve host-network DNS unless explicitly configured.
- **Local proxies** need traffic routed to them, which means either
  system-wide proxy settings (that the VPN may override) or iptables
  redirection (that the container runtime's rules may shadow).

The framework's position: understand what each tool claims ownership
of, and configure them so ownership boundaries don't overlap. Where
overlap is unavoidable, know who wins and design around it.

## Diagnostic workflow

When networking breaks, run these commands in order. The one that
produces unexpected output tells you which layer to investigate:

=== "macOS"

    ```sh
    # 1. What interfaces exist and are active?
    ifconfig | grep -E '^[a-z]|inet '

    # 2. Where does traffic to a given IP route?
    route -n get 8.8.8.8          # default route
    route -n get 10.0.0.1         # internal/VPN range

    # 3. What DNS servers are configured (per interface)?
    scutil --dns | grep nameserver

    # 4. Does DNS resolve correctly?
    dig +short example.com
    dig +short internal.corp.example.com  # should go through VPN DNS

    # 5. Can you actually reach the resolved IP?
    nc -zv 93.184.216.34 443 -w 3

    # 6. Is something proxying?
    echo $HTTP_PROXY $HTTPS_PROXY $ALL_PROXY
    networksetup -getwebproxy "Wi-Fi"
    ```

=== "Linux"

    ```sh
    # 1. What interfaces exist and are active?
    ip -br addr

    # 2. Where does traffic to a given IP route?
    ip route get 8.8.8.8
    ip route get 10.0.0.1

    # 3. What DNS servers are configured?
    resolvectl status        # systemd-resolved
    cat /etc/resolv.conf     # fallback / non-systemd

    # 4. Does DNS resolve correctly?
    dig +short example.com
    dig +short internal.corp.example.com

    # 5. Can you actually reach the resolved IP?
    nc -zv 93.184.216.34 443 -w 3

    # 6. Is something proxying?
    echo $HTTP_PROXY $HTTPS_PROXY $ALL_PROXY
    ```

## The utun proliferation problem (macOS)

Every VPN client on macOS creates virtual tunnel interfaces named
`utun0`, `utun1`, `utun2`, etc. The problem: these interfaces are
never cleaned up on disconnect in many OpenVPN-based clients. Over
days of connect/disconnect cycles, `ifconfig` accumulates dozens of
phantom `utun` interfaces. This is cosmetically annoying but also
causes real problems:

- Interface numbering becomes unpredictable, breaking scripts that
  reference interfaces by name.
- Some VPN clients fail to reconnect because they expect to create
  `utun4` but it already exists as an orphan.
- The routing table accumulates stale entries pointing at dead
  interfaces.

The fix is to use VPN clients built on the modern Network Extension
framework (which handles interface lifecycle correctly) rather than
legacy `tun`/`tap` kext-based clients. WireGuard's macOS app is clean
here. Most corporate Cisco AnyConnect and GlobalProtect deployments
are not.

## In this section

- **[VPN and Tunnels](vpn.md)** — corporate VPN configuration, split
  tunneling, WireGuard vs OpenVPN, the utun lifecycle problem, and
  platform-specific VPN integration.
- **[DNS](dns.md)** — resolv.conf ownership, systemd-resolved, macOS
  scoped DNS, split DNS with VPNs, why Tailscale breaks symlinks, and
  stub resolver configuration.
- **[Container Networking](container-networking.md)** — Podman/Docker
  bridge/host/overlay modes, DNS resolution inside containers, port
  binding conflicts, and how container networks interact with VPN routes.
- **[Proxy and Traffic Capture](proxy-and-capture.md)** — local forward
  proxies for debugging, mitmproxy/Charles/Proxyman setup, certificate
  trust stores, and how proxy configuration interacts with VPN split
  tunnels.

## The framework's stance

**Networking tools must not silently rewrite shared configuration.**
The ideal VPN client does not touch `/etc/resolv.conf` — it registers
its DNS servers through the platform's scoped-DNS API (macOS
`configd`, systemd-resolved per-link config) so that only traffic
destined for the VPN's domains uses the VPN's resolvers. The ideal
container runtime does not insert global iptables rules that break
host-network assumptions.

Reality rarely matches the ideal, so the framework's pragmatic
position is: know what each tool claims, verify the claims match your
expectations on first install, and have a diagnostic reflex when
something breaks. The detail pages that follow provide the specifics.
