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
| **Routing table** | Where packets for a given destination go | VPN split-tunnel rules, container overlay networks, Tailscale subnet routes / exit nodes |
| **DNS resolution** | What IP a hostname resolves to | resolv.conf rewrites, scoped DNS on macOS, systemd-resolved stub listeners, Tailscale MagicDNS |
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
    #    (resolve the host rather than hardcoding an address — example.com's
    #    IP is not stable, and pinning one masks DNS-vs-routing failures)
    nc -zv "$(dig +short example.com | tail -1)" 443 -w 3

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
    #    (resolve the host rather than hardcoding an address — example.com's
    #    IP is not stable, and pinning one masks DNS-vs-routing failures)
    nc -zv "$(dig +short example.com | tail -1)" 443 -w 3

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

## Result sets are network traffic

A database query result is not a value that materializes on your
machine. It is a stream of rows the server sends over a socket — the
same socket that, on a developer workstation, often runs through a VPN
tunnel with the latency and [MTU constraints](vpn.md#mtu-and-fragmentation)
a tunnel imposes. How your
client *pulls* those rows is therefore a networking decision, not just
a database one, and the default behavior of most drivers is the wrong
one for large results.

### Client-side vs. server-side cursors

The distinction is *where the result set lives* while you iterate it:

- **Client-side cursor (buffer-all)** — the driver executes the query,
  then reads the *entire* result set into client memory before handing
  you the first row. Simple, and fine for a hundred rows. For a query
  that returns ten million rows it means the client tries to buffer ten
  million rows: the process balloons, often OOM-kills, and the first row
  is not available until the last byte has crossed the link. This is the
  **default** in libpq, psycopg (unnamed cursor), `mysql-connector`, and
  most ORMs.
- **Server-side cursor (streaming)** — the server holds the result set
  (or generates it lazily) and ships rows in bounded batches as the
  client asks for them. Client memory stays flat regardless of result
  size, the first row arrives quickly, and you can stop early — closing
  the cursor cancels the rest of the transfer instead of paying for rows
  you never read. The cost is a longer-lived server-side resource and a
  round trip per batch.

The networking consequence of "buffer-all" is worse over a VPN:
fetch-all turns one logical query into a single large bulk transfer
that competes with everything else on the tunnel and cannot be
interrupted. Streaming spreads it into batches you can pace and abort.

### Streaming vs. fetching

"Fetching" is pulling the whole answer, then working on it. "Streaming"
is processing rows as they arrive and never holding more than a batch.
Reach for streaming whenever the result set is unbounded or large, an
export or ETL is reading row-by-row, or you may stop early. Stick with
fetching when the result is small and bounded and you genuinely need all
of it in memory (sorting, aggregation the database can't do). The knob
that controls batch size — **fetch size** — is the single most important
setting here: too small and you pay a network round trip per handful of
rows (latency murder over a VPN); too large and you are back to
buffering. A few thousand rows per batch is a reasonable starting point.

### Per-engine behavior

The three engines differ in how much "server-side cursor" actually
means at the protocol level:

| Engine | Default | Streaming mechanism | Caveat |
|--------|---------|---------------------|--------|
| **PostgreSQL** | Client buffers entire result | `DECLARE … CURSOR` + `FETCH`, or libpq single-row mode; psycopg *named* cursor | Cursor must live inside a transaction; rows stream from the server as generated |
| **Redshift** | Client buffers entire result | `DECLARE`/`FETCH` cursors exist, but the result is **materialized on the leader node first** | Not true streaming — the leader node assembles the whole result before paging it to you, and cursor result size is capped by cluster limits; for large extracts `UNLOAD` to S3 beats a cursor |
| **MongoDB** | Returns a cursor (batched) by default | Wire-protocol `getMore`: the driver fetches an initial batch, then more on demand as you iterate | Closer to streaming out of the box; watch the default cursor *timeout* (idle cursors are reaped) and `batchSize` |

The key correction to intuition: **Postgres and Redshift default to
buffering the whole result client-side**, so you have to opt into
streaming. **Mongo's cursor is batched by default**, so you mostly have
to avoid accidentally materializing it (`.toArray()` on a huge cursor
re-creates the buffer-all problem). Redshift is the trap — it offers
cursor *syntax* that looks like Postgres streaming but materializes on
the leader node first, so it neither bounds leader memory nor starts
fast; for genuinely large data, `UNLOAD` to S3 and read the files.

### Driver-level controls

How to actually request server-side streaming in common drivers:

```python
# psycopg (Postgres) — a *named* cursor is server-side; itersize sets
# the fetch batch. An unnamed cursor would buffer the whole result.
with conn.cursor(name="export") as cur:   # named => server-side
    cur.itersize = 5000                    # rows per network round trip
    cur.execute("SELECT * FROM events")    # must be inside a transaction
    for row in cur:                        # rows stream in batches of 5000
        handle(row)
```

```java
// JDBC (Postgres/Redshift) — fetch size is ignored unless autocommit
// is off; without this the driver buffers the entire ResultSet.
conn.setAutoCommit(false);
PreparedStatement st = conn.prepareStatement("SELECT * FROM events");
st.setFetchSize(5000);                       // batch size per round trip
ResultSet rs = st.executeQuery();            // streams, not buffered
```

```javascript
// MongoDB (node driver) — cursors stream by default; iterate, don't
// collect. .toArray() would buffer everything into client memory.
const cursor = db.collection('events').find({}).batchSize(5000);
for await (const doc of cursor) {            // getMore fetches batches
  handle(doc);
}
```

The unifying rule: **iterate the cursor, set a sane fetch/batch size,
and never call the "give me everything as an array" convenience method
on a result you can't afford to hold in memory** — especially when that
memory transfer is crossing a VPN tunnel.

### A war story: archiving a bloated cluster against the clock

We learned the difference between these query mechanics the hard way,
and the lesson was as much about access policy as it was about cursors.

A managed-services contract was up for renewal, and the MongoDB cluster
had grown so large that the next storage tier was, frankly,
business-threatening. The renewal would lock us into that tier unless we
archived enough data and instructed the provider to compact the cluster
*by a hard date*. Miss the date and the cost was existential. When we
dug into why the cluster was so bloated, we found the cause was also a
long-standing performance bottleneck: each record stored the raw,
partially-parsed, *and* normalized values from somewhere between 1 and
20 API requests, upserted in layers as different services touched the
same document. Every service that handled a record left its sediment
behind. We confirmed the archived collections could be removed without
breaking downstream systems, dumped them to S3, and lifecycled them into
Glacier for compliance and governance retention.

The technical work hinged on exactly the material above. These were not
small result sets; naively fetching a collection would have OOM-killed
the exporter long before it finished. Understanding how Mongo's cursor
batches via `getMore`, tuning `batchSize`, and streaming documents
straight to a multipart S3 upload — never materializing a collection in
memory — was what made the export complete at all. Cursor mechanics
stopped being trivia and became the thing standing between us and the
deadline.

What made it genuinely painful, though, was not the database — it was
the access model, and it is a direct illustration of
[the case against least privilege](../handbook/least-privilege.md#the-failure-mode).
This was assigned top priority by the COO personally. Even so, simply
getting an S3 bucket provisioned was a fight. A cloud-native Lambda or
equivalent — the obvious right tool, which could have run the export
server-side next to the data — was out of the question entirely. So with
the clock running, we did what we could: the whole thing was
orchestrated locally, from engineer laptops, pulling a critical dataset
down over the corporate link, compressing it, and pushing it back up to
S3. We archived enough, in time, to defuse the bomb.

The galling part is how trivial this should have been. With the right
permission set — `UNLOAD`-style server-side export, a provisioned bucket,
and Lambda infrastructure to run the job next to the data — this is a
few hours of routine work, no laptops streaming gigabytes across a VPN
involved. Instead, a top-priority, business-critical task assigned by
the COO was bottlenecked for days by the reflexive "no" of an access
model that could not distinguish "engineer needs a bucket to save the
company money" from "engineer wants access to something sensitive." The
restriction did not protect anything. It nearly cost the business its
margin, and it turned a routine archive into a laptop-bound scramble.
That cost never appeared in any report — exactly the invisible failure
mode the least-privilege argument warns about.

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
