# VPN and Tunnels

A VPN client does three things to your machine: creates a virtual
network interface, inserts routes into the routing table, and
(usually) rewrites DNS configuration. Each of these changes is
invisible unless you know where to look, and each can break
assumptions that other tools (Docker, local services) rely on.

This page is more opinionated than most VPN documentation because
most VPN documentation does not exist. The typical corporate VPN
deployment is a subscription tool shoved onto people's machines with
no explanation of what it does, no documentation of its failure modes,
and no recourse when it breaks — because when it breaks, you cannot
search for solutions to proprietary client behavior on Stack Overflow.
The framework's position is that engineers should understand what
their VPN does, why it's configured the way it is, and what tradeoffs
they are absorbing. Your mileage will vary more on this page than any
other in the framework — corporate VPN policy is one of the highest-
variance areas in developer experience.

## What a VPN client actually does

When a VPN connects, it typically:

1. **Creates a tunnel interface** — a virtual NIC (`utun` on macOS,
   `wg0` or `tun0` on Linux) that encrypts traffic and sends it over
   the real NIC to the VPN gateway.
2. **Adds routes** — either a default route (full tunnel: all traffic
   goes through the VPN) or specific subnet routes (split tunnel: only
   traffic to corporate ranges goes through).
3. **Configures DNS** — points the system at the corporate DNS servers,
   either globally (full tunnel) or for specific domains (split DNS).
4. **Installs firewall rules** — some clients add packet filter rules
   to enforce "kill switch" behavior (block all traffic if the tunnel
   drops).

The distinction between full tunnel and split tunnel is the single
most consequential configuration choice. It determines whether your
workstation is "on the internet" or "on the corporate network" while
connected.

## Full tunnel vs. split tunnel

| | Full tunnel | Split tunnel |
|---|---|---|
| **Default route** | VPN gateway | Unchanged (regular internet) |
| **Corporate traffic** | Through VPN | Through VPN |
| **Internet traffic** | Through VPN | Direct |
| **DNS** | Corporate servers for everything | Corporate for internal domains, system default for everything else |
| **Latency** | Higher for all traffic | Higher only for corporate traffic |
| **Privacy** | Corporate can inspect all traffic | Corporate sees only corporate traffic |
| **Local services** | Often unreachable (localhost routing breaks) | Usually fine |
| **Container networking** | Frequently breaks | Usually fine |

**The framework's recommendation:** split tunnel with split DNS,
unless compliance mandates full tunnel. Full tunnel is a blunt
instrument that breaks too many development workflows —
`localhost` access, container port bindings, local DNS resolution,
and LAN services all become casualties.

Most corporate VPN deployments default to full tunnel because it's
simpler to audit. If your organization mandates full tunnel, the
mitigations in the "Living with full tunnel" section below apply.

### The bandwidth reality

A full-tunnel VPN routes *all* traffic through the corporate gateway.
If you have a gigabit connection at home, your effective bandwidth is
now whatever the VPN gateway and its upstream provide — often
dramatically less, and always with added latency from the extra hop.
Legacy OpenVPN tunnels compound this: the userspace encryption and
TCP-over-TCP pathologies can bottleneck a gigabit link to a fraction
of its capacity, even when you are not accessing any internal resource.

Unless you are actively reaching an internal host, a full-tunnel VPN
is burning your bandwidth for no operational benefit. The
organization is paying for the gateway capacity, and you are paying
in developer experience. Split tunnel eliminates this by routing only
internal-bound traffic through the VPN.

### The cost nobody mentions

VPN infrastructure is not free. AWS Client VPN charges roughly $0.05
per active client connection per hour, plus a separate hourly charge
per subnet (endpoint) association — so a full 8-hour workday of
connection time runs about $0.40 per engineer before the association
fee. Organizations that mandate always-on VPN are spending significant
per-seat costs on
gateway capacity that serves no purpose when the engineer is not
accessing internal resources.

Some organizations monitor client connection metrics as a proxy for
employee attendance or engagement — VPN "hours connected" appears in
management dashboards alongside badge swipes and Slack activity. This
is worth knowing. Whether or not your organization does this, the
economics favor split-tunnel or on-demand connection over always-on
full-tunnel.

### A compliance note

This page documents how VPN routing and DNS work, including how
to override pushed configurations (split-tunnel client overrides,
`route-nopull`, manual DNS configuration). Take this information with
eyes wide open: **subverting a corporate VPN or DNS policy likely
violates your employee handbook.** Organizations configure full-tunnel
VPN and mandatory DNS for compliance and security reasons — some of
them good, some of them cargo-culted, but all of them enforceable as
employment policy.

The framework's position is not "ignore your corporate security
team." It is: understand what the VPN does so you can have an informed
conversation with your IT or security team about whether the current
configuration serves its intended purpose, diagnose problems when the
VPN breaks your workflow, and make deliberate choices about
infrastructure you control (personal servers, side projects, home
lab). If your corporate VPN is misconfigured, the right move is to
document the impact and advocate for a better configuration through
proper channels — not to silently subvert it.

## The protocol landscape

### OpenVPN / OpenVPN3 and AWS Client VPN

OpenVPN is what most engineers actually encounter. The legacy
`openvpn` daemon (OpenVPN 2.x) is still everywhere, but the modern
reality is **OpenVPN3** — a rewritten client library with cleaner
session management and better platform integration. AWS Client VPN is
OpenVPN under the hood with AWS-specific authentication (SAML,
certificate-based, Active Directory) and a custom client that wraps
openvpn3.

**The good:** battle-tested protocol, extremely configurable, supports
TCP fallback for restrictive networks (TCP port 443 works through
almost any firewall). OpenVPN3 improves session lifecycle over the
legacy daemon.

**The bad on macOS:** every OpenVPN-based client on macOS creates
virtual tunnel interfaces (`utun`). The critical problem is interface
lifecycle:

- Each connect/disconnect cycle allocates a new `utun` interface.
- Disconnection does not always tear down the previous interface.
- Over days of usage, `ifconfig` accumulates `utun3`, `utun4`, ...
  `utun17` — most of them dead.
- Stale routing table entries pointing at dead interfaces accumulate
  in parallel.
- Eventually, reconnection fails because the client cannot allocate
  the interface it expects.

This is not an OpenVPN protocol problem — it's an implementation
problem in how some macOS clients manage the lifecycle of the `utun`
interfaces they create (leaving stale ones behind on disconnect). The
AWS Client VPN macOS app and Tunnelblick both exhibit this behavior.
(Modern Tunnelblick uses the built-in macOS `utun` interface, not a
kernel extension, for standard tun VPNs — so this is an interface
cleanup issue, not a kext-vs-Network-Extension one.) OpenVPN Connect
(the official OpenVPN3-based client) handles it better but not perfectly.

**The bad on Linux:** fewer problems. The `tun` device model is
well-understood by the kernel, `ip link delete` cleans up reliably,
and NetworkManager's OpenVPN plugin handles lifecycle correctly.

**AWS Client VPN specifically:**

- Pushes full-tunnel by default unless the VPN endpoint is configured
  for split tunnel (an admin decision, not a client decision).
- DNS configuration is pushed from the server — the client has no
  local override.
- The macOS client is a rebranded OpenVPN Connect with AWS
  authentication bolted on. Same utun lifecycle issues.
- On Linux, `openvpn3` CLI works directly with AWS Client VPN `.ovpn`
  configs after handling the SAML authentication flow.

### WireGuard

The modern replacement when you control the server side. Dramatically
simpler: ~4,000 lines of kernel code vs. ~100,000 for OpenVPN's
userspace daemon.

**The good:**

- Interface lifecycle is clean. On macOS, the WireGuard app uses
  Network Extensions correctly — interfaces are created on connect
  and destroyed on disconnect. No phantom `utun` accumulation.
- Configuration is a single flat file. No certificate chains, no
  TLS negotiation, no complex server-side configuration.
- Performance is measurably better — kernel-level encryption with
  modern primitives (ChaCha20, Curve25519).
- Roaming is built in — the tunnel survives network changes (Wi-Fi
  to cellular) without reconnection.
- You understand exactly what is happening. The config file is the
  complete specification of the tunnel — routes, DNS, endpoints, keys.
  No hidden state, no opaque server-pushed configuration.

**The bad:**

- Corporate adoption is slower because existing gateway infrastructure
  is OpenVPN/IPsec-based. You are unlikely to encounter WireGuard as
  a corporate-mandated VPN unless your organization self-hosts.
- No TCP fallback — WireGuard is UDP-only, which means it fails on
  networks that block non-HTTP UDP (some hotel Wi-Fi, aggressive
  corporate firewalls). OpenVPN over TCP port 443 works everywhere.
- No built-in user authentication — WireGuard authenticates keys, not
  users. Corporate deployments need a management layer for key
  distribution and revocation.

**The framework's recommendation:** for infrastructure you control
(personal servers, home lab, team infrastructure where you own the
server), WireGuard is the right answer. The configuration is
transparent, the behavior is predictable, and you will actually
understand what your tunnel does. For corporate VPN mandated by IT,
you use whatever they provide — usually OpenVPN3 or AWS Client VPN.

### IPsec / IKEv2

The oldest enterprise standard. Native OS support on both macOS
(built into Network preferences) and Linux (strongSwan, libreswan).
Configuration complexity is extreme — certificate management, IKE
phase negotiation, transform sets, PFS groups. Individual engineers
rarely configure IPsec directly; it lives behind whatever client IT
provides.

### Tailscale: a warning

Tailscale is a mesh overlay network built on WireGuard. It markets
itself as "zero configuration VPN" — every device in the tailnet
reaches every other device directly via NAT traversal without you
managing keys, routes, or DNS.

**The one thing Tailscale is genuinely good for:** traversing NAT
without configuration. If you need two machines to talk to each other
and both are behind NAT, Tailscale does that in seconds. For this
single use case — the banal task of "connect A to B without opening
firewall ports" — it works as advertised.

**Why the framework actively discourages relying on it beyond that:**

- **It papers over what is happening.** Tailscale hides the WireGuard
  configuration, the routing decisions, and the DNS resolution path
  behind a proprietary control plane. When it works, you learn nothing
  about your network. When it breaks, you have no mental model to
  debug from because the "zero configuration" promise means there is
  no configuration to inspect.
- **It breaks at scale.** The magic works for a handful of personal
  devices. Add a corporate VPN, container networks, and split DNS, and
  Tailscale's implicit routing and DNS claims conflict with everything
  else on the machine. The debugging story becomes "which of these
  three tools wrote to the routing table last?"
- **MagicDNS destroys DNS ownership.** On Linux, enabling MagicDNS
  rewrites `/etc/resolv.conf` to point at `100.100.100.100`. If that
  file is a symlink managed by systemd-resolved, Tailscale replaces
  the symlink with a regular file — silently breaking whatever was
  managing DNS before. On macOS it uses the scoped DNS API (less
  destructive) but still inserts itself as a resolver that can
  conflict with corporate split DNS.
- **It is a corporate product offering what you can build yourself.**
  Tailscale is a managed WireGuard deployment. Everything it does is
  reproducible with WireGuard configuration files, a key distribution
  mechanism, and DNS records. The "free tier" subsidizes you learning
  a proprietary abstraction instead of the underlying technology.
  When the pricing changes or the feature set diverges from your needs,
  you have learned nothing transferable.
- **The always-on interface causes routing conflicts.** The Tailscale
  interface (`tailscale0` on Linux, `utun` on macOS) is always present
  with routes for the `100.x.x.x` CGNAT range. Corporate VPN clients
  that route `100.64.0.0/10` (which overlaps Tailscale's range) create
  silent conflicts.

**The framework's position:** understand WireGuard. Configure it
yourself. Use Tailscale only if the sole thing you need is
zero-config NAT traversal for a handful of personal devices, and be
aware that you are trading understanding for convenience. Do not
build infrastructure dependencies on it.

## Other corporate clients

Cisco AnyConnect, Palo Alto GlobalProtect, and Zscaler/Cloudflare
WARP exist in the wild. If your organization mandates one, you use it
— there is no choice. Brief notes on their behavior:

- **Cisco AnyConnect** — IPsec or SSL-VPN. On macOS, creates `utun`
  interfaces with the same lifecycle problems as OpenVPN. Its socket
  filter kernel extension modifies routing even when disconnected.
  Rewrites global DNS unconditionally. On Linux, the open-source
  `openconnect` client is better-behaved and integrates with
  systemd-resolved.
- **Palo Alto GlobalProtect** — similar to AnyConnect. Full-tunnel by
  default, aggressive DNS rewriting. Uses Network Extensions on macOS
  (better interface lifecycle). On Linux, `globalprotect-openconnect`
  or `gp-saml-gui` provide open-source alternatives.
- **Zscaler / Cloudflare WARP** — cloud proxy products rather than
  traditional VPNs. Generally better about routing and DNS coexistence
  because they are designed to layer on top of existing infrastructure.
  The tradeoff: they install root certificates for TLS interception,
  which breaks certificate pinning in development tools. If `curl` or
  `git` fails with certificate errors after installation, the client's
  root CA is the cause.

## Living with full tunnel

When your organization mandates full-tunnel VPN and you cannot change
it, these mitigations keep development workflows functional:

### Preserve localhost routing

Full-tunnel VPNs sometimes route `127.0.0.0/8` through the tunnel,
breaking local services. Check:

```sh
# macOS
route -n get 127.0.0.1

# Linux
ip route get 127.0.0.1
```

If it routes through the VPN interface, add a local route:

=== "macOS"

    ```sh
    sudo route add -net 127.0.0.0/8 -interface lo0
    ```

=== "Linux"

    ```sh
    sudo ip route add 127.0.0.0/8 dev lo
    ```

### Preserve container networking

The container runtime's bridge network (`10.88.0.0/16` for Podman,
`172.17.0.0/16` for Docker) and custom networks can conflict with VPN
routes. If containers become unreachable after VPN connection:

1. Check if the VPN claims the container subnet:
   `route -n get 172.17.0.1` (macOS) or `ip route get 172.17.0.1`
   (Linux).
2. If so, reconfigure the runtime to use a non-conflicting subnet.
   See the [Container Networking](container-networking.md#subnet-overlap)
   page for Podman and Docker configuration.

### Preserve LAN access

Split-tunnel VPNs preserve LAN access by default. Full-tunnel VPNs
often do not. If you need to reach local network devices (printers,
NAS, other machines):

```sh
# Add a route for your LAN subnet via the physical interface
# macOS (assuming en0 is Wi-Fi)
sudo route add -net 192.168.1.0/24 -interface en0

# Linux
sudo ip route add 192.168.1.0/24 dev wlan0
```

These routes need to be re-added after every VPN reconnection. A
post-connect script (if your VPN client supports hooks) is the
sustainable solution.

## Interface management

### Listing active interfaces

=== "macOS"

    ```sh
    # All interfaces with addresses
    ifconfig | grep -E '^[a-z]|inet '

    # Just tunnel interfaces
    ifconfig | grep -E '^utun'

    # What routes point at each interface
    netstat -rn | grep utun
    ```

=== "Linux"

    ```sh
    # All interfaces, brief format
    ip -br addr

    # WireGuard interfaces specifically
    wg show

    # Routes through tunnel interfaces
    ip route show | grep -E 'tun|wg'
    ```

### Cleaning up phantom interfaces (macOS)

When OpenVPN or AnyConnect leaves dead `utun` interfaces:

```sh
# List interfaces that have no assigned address (likely dead)
ifconfig | grep -B1 'flags.*UP' | grep utun

# There is no clean userspace command to remove utun interfaces.
# The reliable fix is a restart of the VPN client's network extension:
# System Settings > General > Login Items & Extensions > Network Extensions
# Toggle the VPN extension off and back on.

# Nuclear option: reboot. This clears all utun interfaces.
```

The real fix is to use a VPN client that manages interface lifecycle
correctly (WireGuard, or a corporate client built on modern Network
Extensions).

### WireGuard interface management

WireGuard interfaces are explicit and clean:

=== "macOS"

    The WireGuard macOS app handles interface creation/destruction
    through Network Extensions. Tunnels appear only when active and
    disappear completely on disconnect.

=== "Linux"

    ```sh
    # Create interface
    sudo ip link add wg0 type wireguard

    # Apply configuration
    sudo wg setconf wg0 /etc/wireguard/wg0.conf

    # Bring up with routes
    sudo ip link set wg0 up
    sudo ip route add 10.0.0.0/24 dev wg0

    # Tear down completely
    sudo ip link delete wg0

    # Or use wg-quick for all of the above:
    sudo wg-quick up wg0
    sudo wg-quick down wg0
    ```

## Split tunnel configuration

If you control the VPN server (self-hosted WireGuard, personal
infrastructure), configure split tunneling explicitly:

### WireGuard split tunnel

The `AllowedIPs` field in the peer configuration determines what
traffic routes through the tunnel:

```ini
[Interface]
PrivateKey = <your-private-key>
Address = 10.0.0.2/32
DNS = 10.0.0.1

[Peer]
PublicKey = <server-public-key>
Endpoint = vpn.example.com:51820
# Split tunnel: only route these subnets through the VPN
AllowedIPs = 10.0.0.0/24, 172.16.0.0/12
# Full tunnel would be: AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

### OpenVPN split tunnel (client-side override)

If the server pushes a full tunnel but you want split:

```
# In your .ovpn client config, ignore pushed routes:
route-nopull

# Then add only the routes you need:
route 10.0.0.0 255.255.255.0
route 172.16.0.0 255.240.0.0
```

This only works if the server does not enforce full-tunnel at the
gateway level (dropping traffic that doesn't arrive through the
tunnel).

## Coexistence patterns

### VPN + containers

Container bridge networks (Podman's `10.88.0.0/16`, Docker's
`172.17.0.0/16`) can overlap with VPN-claimed RFC 1918 ranges. When
they do, container traffic routes through the VPN instead of locally.

The fix is to move the runtime to a non-conflicting subnet. See the
"Preserve container networking" section above.

### Multiple VPNs

Running two VPN clients simultaneously (e.g., corporate VPN +
customer VPN for a consulting engagement) is a routing nightmare.
Both want to own the default route and DNS. The only sustainable
approach is:

1. Use one VPN at a time, switching as needed.
2. If simultaneous is required, ensure both are split-tunnel and
   their `AllowedIPs` / routed subnets do not overlap.
3. Use network namespaces (Linux) to isolate one VPN's traffic
   entirely from the other.

## Monitoring and debugging

```sh
# Watch routing table changes in real time (macOS)
route -n monitor

# Watch interface state changes (Linux)
ip monitor link

# See which DNS server answered a query
dig +short +identify example.com

# Trace the path to a host (useful for identifying where VPN routing diverges)
traceroute -n 10.0.0.1
mtr -n 10.0.0.1      # better interactive version

# On macOS, see all DNS resolver configurations
scutil --dns

# Check if a specific port is reachable through the current route
nc -zv 10.0.0.50 5432 -w 3
```
