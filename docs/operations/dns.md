# DNS

DNS on a developer workstation is deceptively simple until it isn't.
The resolution path — "turn a hostname into an IP address" — passes
through layers of configuration that VPN clients, container runtimes,
and overlay networks all want to own. When DNS breaks, nothing works,
and the error messages ("could not resolve host") tell you nothing
about *which* layer failed. This page maps the resolution path on both
macOS and Linux, explains who owns what, and documents the specific
ways that common tools break it.

## The fundamental problem: shared mutable state

`/etc/resolv.conf` (Linux) and the resolver configuration database
(macOS) are global, mutable state that multiple tools write to. There
is no locking mechanism, no ownership model, no coordination protocol.
The last writer wins.

On a developer machine running a VPN, a container runtime, and Tailscale, the
"last writer" changes depending on connection order, which tool
reconnected most recently, and whether a network change event
triggered a reconfiguration. This is why DNS breaks intermittently
and why "it worked yesterday" is a common complaint.

## macOS: the scoped resolver model

macOS does not use `/etc/resolv.conf` in any meaningful way. The file
exists for POSIX compatibility but is not the system's source of
truth. DNS resolution is managed by `configd`, which maintains a
database of per-interface (per-"service") resolver configurations.

### How macOS resolves a name

1. An application calls `getaddrinfo()` or the higher-level
   `CFHostStartInfoResolution`.
2. The system resolver consults `configd`'s resolver database.
3. `configd` matches the query against configured search domains and
   scoped resolvers:
   - If a scoped resolver claims the domain (e.g., `.corp.example.com`
     is assigned to the VPN interface), that resolver answers.
   - Otherwise, the primary DNS servers (from the active network
     service) answer.
4. The response is cached by `mDNSResponder` (the system DNS cache
   daemon).

### Viewing the resolver database

```sh
# Full resolver configuration (all interfaces and scoped resolvers)
scutil --dns

# Output shows numbered "resolver" entries like:
# resolver #1
#   nameserver[0] : 8.8.8.8
#   nameserver[1] : 8.8.4.4
#   if_index : 6 (en0)
#   flags    : Request A records, Request AAAA records
#   reach    : 0x00000002 (Reachable)
#
# resolver #2
#   domain   : corp.example.com
#   nameserver[0] : 10.0.0.1
#   if_index : 14 (utun3)
#   flags    : Request A records, Scoped
```

The "Scoped" flag is key. A scoped resolver only answers queries for
its declared domain — it does not interfere with general DNS
resolution. This is how split DNS *should* work.

### The problem: not all VPN clients use scoped resolvers

Well-behaved clients (Tailscale on macOS, WireGuard macOS app) register
scoped resolvers through the `configd` API. Poorly-behaved clients
(Cisco AnyConnect, many OpenVPN configurations) overwrite the primary
resolver — making the VPN's DNS server answer *all* queries, not just
corporate ones.

Check which model your VPN uses:

```sh
# Connect the VPN, then:
scutil --dns | grep -A3 "domain"

# If you see your VPN's DNS server under a specific domain: good (scoped)
# If you see it as resolver #1 with no domain restriction: bad (global override)
```

### Flushing the macOS DNS cache

When DNS configuration changes (VPN connect/disconnect, network
switch), stale cache entries can persist:

```sh
# Flush mDNSResponder cache
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

## Linux: the resolv.conf battlefield

On Linux, `/etc/resolv.conf` is the canonical DNS configuration file.
It supports at most three `nameserver` entries and optional `search`
domains. This simplicity becomes a liability when multiple tools
compete to write it.

### The ownership problem

On a typical developer Linux machine, any of the following may believe
they own `/etc/resolv.conf`:

- **systemd-resolved** — writes a stub at `127.0.0.53` and manages
  the real resolvers internally.
- **NetworkManager** — writes resolvers based on DHCP or manual
  connection settings.
- **resolvconf** (the legacy tool) — merges resolver configuration
  from multiple sources.
- **VPN clients** — overwrite the file directly on connect.
- **Tailscale** — overwrites the file (or the symlink) to point at
  `100.100.100.100`.
- **Container runtimes** (Podman, Docker) — copy the host's
  `/etc/resolv.conf` into containers at creation time. If the host
  file changes, running containers have stale DNS.
- **dhclient** — overwrites on DHCP lease renewal.

When two of these tools are active, one of them is being silently
overwritten. The symptoms are intermittent resolution failures that
correlate with network events.

### systemd-resolved: the modern answer

`systemd-resolved` solves the ownership problem by being the single
owner. Everything else talks to it through its API rather than writing
`/etc/resolv.conf` directly.

**How it works:**

1. `systemd-resolved` runs as a daemon, listening on `127.0.0.53:53`.
2. `/etc/resolv.conf` is a symlink to
   `/run/systemd/resolve/stub-resolv.conf`, which contains only
   `nameserver 127.0.0.53`.
3. Per-link DNS configuration (different resolvers per interface) is
   managed via `resolvectl` or the D-Bus API.
4. VPN clients and NetworkManager configure their resolvers via
   `resolvectl` rather than writing files.

**Checking the state:**

```sh
# Which link has which DNS servers?
resolvectl status

# What's the global DNS configuration?
resolvectl dns

# Which link is authoritative for which domains?
resolvectl domain

# Test resolution through the stub resolver
resolvectl query example.com
```

**The correct symlink:**

```sh
# Verify the symlink is intact
ls -la /etc/resolv.conf
# Should show: /etc/resolv.conf -> /run/systemd/resolve/stub-resolv.conf

# If broken, restore it:
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```

### Why Tailscale breaks the symlink

Tailscale's MagicDNS feature needs to intercept DNS queries for
`.ts.net` domains. On Linux, it does this by becoming the system DNS
resolver. The implementation:

1. Tailscale checks if `/etc/resolv.conf` is a symlink.
2. If it is a symlink to systemd-resolved's stub, Tailscale uses the
   `resolvectl` API (correct behavior — no file modification needed).
3. If Tailscale cannot detect systemd-resolved, or if the system uses
   a different resolver manager, it **replaces the symlink with a
   regular file** containing `nameserver 100.100.100.100`.

This replacement breaks:
- The symlink contract (whatever created the symlink expects it to
  persist).
- systemd-resolved's ownership (resolved is now serving DNS to nobody
  because nothing points at `127.0.0.53`).
- Any tool that manages `/etc/resolv.conf` via resolvconf (the tool
  now writes to a file that has been replaced out from under it).

**Mitigation:**

```sh
# Tell Tailscale to use systemd-resolved properly
sudo tailscale up --accept-dns=true

# Verify Tailscale registered with resolved (not file replacement)
resolvectl status | grep tailscale

# If Tailscale already broke the symlink, restore it:
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved
sudo tailscale down && sudo tailscale up --accept-dns=true
```

On distributions where systemd-resolved is not available or not
desired, configure Tailscale with `--accept-dns=false` and manually
add the Tailscale DNS for `.ts.net`:

```sh
# /etc/resolvconf/resolv.conf.d/tail (if using resolvconf)
# or a dnsmasq/unbound forward zone
server=/ts.net/100.100.100.100
```

### NetworkManager and DNS

NetworkManager can manage DNS in several modes, configured in
`/etc/NetworkManager/NetworkManager.conf`:

```ini
[main]
# Options: default, dnsmasq, systemd-resolved, none
dns=systemd-resolved
```

- **`default`** — NetworkManager writes `/etc/resolv.conf` directly.
  Conflicts with everything else that writes it.
- **`systemd-resolved`** — NetworkManager pushes DNS configuration to
  resolved via D-Bus. Correct on systemd systems.
- **`dnsmasq`** — NetworkManager starts a local dnsmasq instance and
  points `resolv.conf` at `127.0.0.1`. Supports per-domain routing.
- **`none`** — NetworkManager does not touch DNS. You manage it
  yourself.

**The framework's recommendation:** on systemd-based distributions,
use `dns=systemd-resolved`. This gives you per-link DNS, proper
scoping, and a single owner for `/etc/resolv.conf`.

## Split DNS: the right model

Split DNS means different resolvers answer queries for different
domains. Corporate domains (`.corp.example.com`) go to the corporate
DNS server (through the VPN); everything else goes to the normal
resolver. This is the correct model for split-tunnel VPN — the DNS
topology should match the routing topology.

### Split DNS on macOS

macOS supports split DNS natively through scoped resolvers. If your
VPN client configures them correctly (check with `scutil --dns`), it
works automatically. If not, you can create resolver configuration
files manually:

```sh
# Create /etc/resolver/ directory (macOS reads these as supplemental resolvers)
sudo mkdir -p /etc/resolver

# Route .corp.example.com queries to the corporate DNS
echo "nameserver 10.0.0.1" | sudo tee /etc/resolver/corp.example.com
```

Files in `/etc/resolver/` are read by the system resolver. The
filename is the domain — `corp.example.com` means "use this
nameserver for queries ending in `.corp.example.com`." This works
even if the VPN client does not configure scoped DNS properly.

### Split DNS on Linux (systemd-resolved)

```sh
# Configure the VPN link to claim only specific domains
sudo resolvectl dns tun0 10.0.0.1
sudo resolvectl domain tun0 '~corp.example.com' '~internal.example.com'

# The ~ prefix means "routing domain" — queries matching this domain
# are routed to this link's DNS servers, but the domain is NOT added
# to the search list.
```

For VPN clients that integrate with systemd-resolved (openconnect,
NetworkManager's VPN plugins), this happens automatically if the
server pushes domain configuration.

### Split DNS with WireGuard

WireGuard's `wg-quick` supports `PostUp` scripts that configure
split DNS:

```ini
[Interface]
PrivateKey = <key>
Address = 10.0.0.2/32
DNS = 10.0.0.1
PostUp = resolvectl dns %i 10.0.0.1; resolvectl domain %i '~corp.example.com'
PostDown = resolvectl revert %i
```

On macOS with `wg-quick` (via Homebrew), use the `/etc/resolver/`
method instead:

```ini
[Interface]
PrivateKey = <key>
Address = 10.0.0.2/32
PostUp = echo "nameserver 10.0.0.1" > /etc/resolver/corp.example.com
PostDown = rm -f /etc/resolver/corp.example.com
```

## DNS inside containers

Container runtimes (Podman, Docker) copy the host's
`/etc/resolv.conf` into containers at creation time. This has two
implications:

1. If the host's DNS changes after the container starts (VPN
   connects, network change), the container has stale DNS.
2. If the host uses `127.0.0.53` (systemd-resolved stub), the
   container cannot reach it because the container's `127.0.0.53`
   is its own loopback, not the host.

Both Podman and Docker handle case 2 by detecting the stub resolver
and substituting the real upstream servers. But this detection is not
perfect — especially with non-standard resolved configurations.

**Explicit DNS for containers:**

```sh
# Per-container
podman run --dns 8.8.8.8 --dns-search corp.example.com myimage

# Podman (in ~/.config/containers/containers.conf):
# [containers]
# dns_servers = ["8.8.8.8", "8.8.4.4"]

# Docker (in ~/.docker/daemon.json):
# { "dns": ["8.8.8.8", "8.8.4.4"] }
```

See the [Container Networking](container-networking.md) page for the
full picture of DNS resolution inside the container network model.

## DNS debugging toolkit

```sh
# What nameserver answered this query?
dig +short +identify example.com

# Trace the full resolution path (recursive from root)
dig +trace example.com

# Query a specific server (bypass system resolver)
dig @10.0.0.1 internal.corp.example.com

# Query the systemd-resolved cache specifically
resolvectl query --cache-only=yes example.com

# See NXDOMAIN vs timeout (timeout = routing/firewall; NXDOMAIN = DNS config)
dig internal.corp.example.com
# NXDOMAIN: wrong server answered (it doesn't know the domain)
# Timeout: right server, but unreachable (routing/firewall)

# On macOS, check which resolver will handle a query
dns-sd -G v4 internal.corp.example.com
```

## Do not trust your ISP's default DNS

When you connect to a network without explicit DNS configuration,
your resolver defaults to whatever your ISP provides via DHCP. This
is worth understanding: your ISP's DNS server is a man-in-the-middle
by definition. It sits between you and the entire public internet's
namespace, and ISPs are notoriously opportunistic commercial entities
with no obligation to serve your interests.

**What ISP DNS servers actually do:**

- **NXDOMAIN hijacking.** When you mistype a domain, the correct
  response is NXDOMAIN ("this domain does not exist"). Many ISP
  resolvers instead return a fabricated A record pointing at an
  ad-laden search page operated by the ISP or a partner. This breaks
  applications that depend on NXDOMAIN semantics and degrades your
  security posture by making you unable to distinguish "domain does
  not exist" from "domain resolves to an unexpected host."
- **Query logging and sale.** DNS queries are a complete record of
  every service you use. ISPs aggregate and sell this data, or use it
  for ad targeting. Your DNS traffic is their product.
- **Performance deprioritization.** ISP resolvers are shared
  infrastructure with no SLA for resolution latency. They are often
  slower than dedicated public resolvers because serving DNS well is
  not the ISP's business — selling bandwidth is.
- **Selective interference.** Some ISPs inject DNS responses for
  content-filtering, regulatory compliance, or commercial
  partnerships, transparently redirecting traffic without your
  knowledge.

**The OpenDNS cautionary tale:** readers are encouraged to research
the ownership arc of OpenDNS — originally an independent resolver
that became the de facto DNS for a significant portion of the
consumer market, then acquired by Cisco and folded into their
commercial security product line. The entity that resolves your DNS
is your network gateway to the broader internet. That position grants
capabilities indistinguishable from a man-in-the-middle attack when
operated by an entity whose incentives do not align with yours.

**Choose a reputable upstream resolver.** In any context where you
control your DNS configuration — personal machines, home network,
development environments, servers — explicitly configure a public
resolver with a clear privacy policy, no NXDOMAIN hijacking, and
strong performance:

| Resolver | Primary | Secondary | Notes |
|----------|---------|-----------|-------|
| **Cloudflare** (1.1.1.1) | `1.1.1.1` | `1.0.0.1` | Fastest in most benchmarks, committed to no query logging, supports DNS-over-HTTPS and DNS-over-TLS |
| **Google** (8.8.8.8) | `8.8.8.8` | `8.8.4.4` | Reliable, global, well-documented. Logs queries for 24-48 hours. A distant second on privacy |
| **Quad9** (9.9.9.9) | `9.9.9.9` | `149.112.112.112` | Non-profit, includes malware domain blocking by default |

The framework's preference is Cloudflare's 1.1.1.1 — fastest
resolution latency, strongest privacy commitment (no query logging,
regular third-party audits), and correct NXDOMAIN behavior. Google's
8.8.8.8 is a reasonable fallback with the caveat that Google's
business model is advertising and data is their core asset.

### Encrypt your DNS traffic

Choosing a reputable resolver is necessary but not sufficient.
Traditional DNS (port 53, UDP) is plaintext. Every query you make —
every hostname you resolve — is visible to anyone on the network path
between you and the resolver: your ISP, the coffee shop's Wi-Fi
operator, any intermediate network. This is the same class of problem
as unencrypted HTTP: you are leaking data in a way you almost never
want to if you are even aware that it is happening.

Two protocols encrypt DNS queries in transit:

- **DNS-over-HTTPS (DoH)** — DNS queries wrapped in HTTPS to port
  443. Indistinguishable from normal web traffic to network observers.
  Supported by all major browsers, macOS (14+), and systemd-resolved.
- **DNS-over-TLS (DoT)** — DNS queries wrapped in TLS on a dedicated
  port (853). Visible as "encrypted DNS traffic" to network observers
  (the port identifies its purpose) but the query content is private.
  Supported by systemd-resolved, Android (9+), and most dedicated
  resolver daemons.

The framework does not pick a preferred method — both accomplish the
goal of encrypting queries in transit. DoH has the practical advantage
of being unfilterable (it looks like HTTPS traffic), which matters on
hostile networks. DoT has the advantage of clean separation from web
traffic, which matters for network administrators who want to
identify DNS traffic without decrypting it.

**Configuration:**

=== "macOS (14+)"

    System Settings > Network > Wi-Fi (or Ethernet) > Details > DNS.
    macOS supports encrypted DNS via configuration profiles. Cloudflare
    and other providers publish `.mobileconfig` profiles that configure
    DoH system-wide.

    Alternatively, `networksetup` does not support DoH directly —
    a configuration profile or MDM is required for system-level
    encrypted DNS on macOS.

=== "Linux (systemd-resolved)"

    ```ini
    # /etc/systemd/resolved.conf
    [Resolve]
    DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com
    DNSOverTLS=yes
    ```

    ```sh
    sudo systemctl restart systemd-resolved
    # Verify encrypted transport
    resolvectl status | grep "DNS over TLS"
    ```

=== "Browser-level (DoH)"

    Most browsers support DoH independently of the OS resolver:

    - **Firefox:** Settings > Privacy & Security > DNS over HTTPS
    - **Chrome:** Settings > Privacy and security > Use secure DNS

    Browser-level DoH bypasses the system resolver entirely — queries
    go directly from the browser to the DoH endpoint. This means
    split DNS configurations (corporate domains routed to VPN DNS)
    may not apply to browser traffic unless the browser is configured
    to fall back to the system resolver for private domains.

The key point is not which method you choose — it is that plaintext
DNS is a data leak. Like HTTP before widespread TLS adoption, it
persists mostly through inertia and default configurations rather
than any good reason. If you are deliberate enough to choose your
resolver, be deliberate enough to encrypt the connection to it.

The same incentive structure that leads your ISP to hijack NXDOMAIN
responses is the same incentive structure that leads your corporation
to route all traffic through a VPN — control of the DNS resolution
path is control of the network. The difference is that you can choose
your upstream resolver on machines you control. Exercise that choice
deliberately rather than accepting whatever DHCP assigns.

## The framework's recommendations

1. **Choose your upstream DNS deliberately.** Do not accept ISP
   defaults. Configure Cloudflare (1.1.1.1) or another reputable
   public resolver on every machine you control.
2. **macOS:** use `scutil --dns` to verify that VPN DNS is scoped,
   not global. If it's global, add files to `/etc/resolver/` for
   corporate domains and configure the VPN to not override primary
   DNS (if possible).
3. **Linux:** use systemd-resolved as the single DNS owner. Configure
   all tools (NetworkManager, VPN clients, Tailscale) to talk to
   resolved via its API rather than writing `/etc/resolv.conf`.
4. **Verify the symlink regularly.** If `/etc/resolv.conf` is no
   longer a symlink to resolved's stub, something replaced it.
   Investigate and restore.
5. **Do not trust "the internet is broken" — test DNS separately
   from connectivity.** `nc -zv 8.8.8.8 53` tests connectivity to a
   DNS server. `dig @8.8.8.8 example.com` tests DNS resolution.
   Different failures mean different layers.
6. **Know your TTLs.** After fixing DNS configuration, cached stale
   results persist. Flush caches explicitly on both platforms.
