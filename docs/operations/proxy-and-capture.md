# Proxy and Traffic Capture

When debugging a web application, the most direct tool is a local
forward proxy that sits between your client and the server, showing
you exactly what bytes cross the wire. This is the "packet capture for
application developers" workflow — more targeted than Wireshark,
easier to configure than `tcpdump`, and capable of decrypting HTTPS
traffic that network-layer captures cannot read.

This page covers how local proxies work, how to configure certificate
trust so HTTPS interception works without breaking everything, and
how proxy configuration interacts with VPNs and container networking.

## How a forward proxy works

A forward proxy intercepts outbound HTTP/HTTPS traffic from a client:

1. The client is configured to send all HTTP traffic to
   `localhost:8080` (or wherever the proxy listens).
2. For HTTPS, the proxy performs a TLS man-in-the-middle: it presents
   its own certificate to the client, decrypts the traffic, inspects
   it, then re-encrypts and forwards to the real server.
3. The proxy shows you the full request/response cycle — headers,
   bodies, timing, TLS details.

The TLS interception requires the client to trust the proxy's CA
certificate. This is the primary setup step and the primary source of
problems.

## Tool choices

### mitmproxy

Open-source, terminal and web UI, scriptable in Python. The
framework's recommendation for engineers who want programmatic access
to captured traffic.

```sh
# Install
brew install mitmproxy      # macOS
pipx install mitmproxy      # Linux or cross-platform

# Start the proxy (default: localhost:8080)
mitmproxy                   # terminal UI
mitmweb                     # browser UI at http://localhost:8081

# Dump mode (non-interactive, log to file)
mitmdump -w capture.flow
```

**Strengths:** scriptable (Python addons), supports HTTP/2 and
WebSocket, replay capabilities, free.

**Weaknesses:** TUI requires terminal familiarity, no native macOS
system proxy integration (manual configuration needed).

### Charles Proxy

Commercial, GUI-first, macOS-native. Common in mobile and frontend
development teams.

**Strengths:** polished GUI, throttling (simulate slow networks),
breakpoints (modify requests/responses in flight), map local/remote
(rewrite responses from local files), auto-configures macOS system
proxy.

**Weaknesses:** paid license, Java-based (memory hungry), no
scripting API, not scriptable in CI.

### Proxyman

Commercial, macOS-native (Swift), modern UI. The closest thing to
Charles that doesn't feel dated.

**Strengths:** native macOS integration (auto-configures system
proxy, keychain trust), Apple-platform focus (iOS simulator
interception built in), lightweight.

**Weaknesses:** macOS only, paid for full features, limited scripting.

### Wireshark / tcpdump

Network-layer capture. Sees all traffic including non-HTTP, but
cannot decrypt HTTPS (unless you supply the session keys via
`SSLKEYLOGFILE`).

```sh
# Capture HTTP traffic on the loopback interface
sudo tcpdump -i lo0 -A port 8080       # macOS
sudo tcpdump -i lo -A port 8080        # Linux

# Capture all traffic on a specific interface, write to file for Wireshark
sudo tcpdump -i en0 -w capture.pcap
```

**When to use instead of a forward proxy:** debugging non-HTTP
protocols, diagnosing connection-level failures (TCP resets, TLS
handshake failures), capturing traffic that bypasses HTTP proxy
settings (raw socket connections, UDP).

## Certificate trust setup

HTTPS interception requires the proxy's CA certificate in the
system trust store. Without this, every HTTPS connection fails with
certificate errors.

### Installing the proxy CA

=== "macOS"

    ```sh
    # mitmproxy generates its CA on first run at ~/.mitmproxy/
    # Install it to the system keychain:
    sudo security add-trusted-cert -d -r trustRoot \
      -k /Library/Keychains/System.keychain \
      ~/.mitmproxy/mitmproxy-ca-cert.pem

    # Or open Keychain Access, drag in the cert, and set "Always Trust"
    ```

    Charles and Proxyman have menu items that handle this automatically
    (Help > SSL Proxying > Install Charles Root Certificate).

=== "Linux"

    ```sh
    # Copy the CA cert to the system trust store
    sudo cp ~/.mitmproxy/mitmproxy-ca-cert.pem \
      /usr/local/share/ca-certificates/mitmproxy.crt
    sudo update-ca-certificates

    # Fedora/RHEL:
    sudo cp ~/.mitmproxy/mitmproxy-ca-cert.pem \
      /etc/pki/ca-trust/source/anchors/mitmproxy.pem
    sudo update-ca-trust
    ```

### Per-tool trust considerations

Not every tool uses the system trust store:

| Tool | Trust source | Extra configuration |
|------|-------------|-------------------|
| **curl** | System store (macOS), `/etc/ssl/certs` (Linux) | Usually works after system install |
| **Node.js** | Does not use system store by default | Set `NODE_EXTRA_CA_CERTS=~/.mitmproxy/mitmproxy-ca-cert.pem` |
| **Python (requests)** | Uses `certifi` bundle, not system store | Set `REQUESTS_CA_BUNDLE=~/.mitmproxy/mitmproxy-ca-cert.pem` or `SSL_CERT_FILE` |
| **Java** | Uses its own keystore | `keytool -import -trustcacerts -keystore $JAVA_HOME/lib/security/cacerts -file ca.pem` |
| **Ruby** | System store on macOS, OpenSSL bundle on Linux | Usually works after system install |
| **Go** | System store | Usually works after system install |
| **Firefox** | Its own certificate store | Must import manually in Settings > Certificates |
| **git** | Configurable via `http.sslCAInfo` | `git config --global http.sslCAInfo ~/.mitmproxy/mitmproxy-ca-cert.pem` |
| **Containers** | Container's `/etc/ssl/certs` | Must mount or build the cert into the image |

**The environment variable approach** (set in your `.envrc` when proxy
debugging is active):

```sh
# .envrc for a proxy-debugging session
export NODE_EXTRA_CA_CERTS="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
export REQUESTS_CA_BUNDLE="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
export SSL_CERT_FILE="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
```

### Removing trust when done

Leaving a proxy CA in your system trust store when you're not actively
debugging is a security risk — anyone with the proxy's private key
(at `~/.mitmproxy/mitmproxy-ca.pem`) can intercept your HTTPS
traffic.

```sh
# macOS: remove from system keychain
sudo security delete-certificate -c "mitmproxy" /Library/Keychains/System.keychain

# Linux: remove and update
sudo rm /usr/local/share/ca-certificates/mitmproxy.crt
sudo update-ca-certificates --fresh
```

### The offline root CA approach (recommended)

A safer and lower-overhead alternative to installing and removing
proxy tool CAs: create your own root CA, install it in your system
trust store once, keep the private key entirely offline, and issue
short-lived certificates from it on demand for debugging sessions.

This mirrors how actual certificate authorities operate — the root
key is secured offline (ideally on an air-gapped device or encrypted
USB), and only subordinate or leaf certificates are issued for
active use. The difference from a proxy tool's auto-generated CA:
you control the key's security posture, the root cert is permanent
and trusted, and the ephemeral certs you issue expire quickly enough
that a compromise window is bounded.

```sh
# Generate the root CA (do this once, secure the key offline)
openssl req -x509 -new -nodes \
  -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout ~/secure-offline/debug-root-ca.key \
  -out ~/debug-root-ca.crt \
  -days 3650 \
  -subj "/CN=Local Debug Root CA/O=Personal"

# Install the root cert in your system trust store (one time)
# macOS:
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ~/debug-root-ca.crt

# Linux:
sudo cp ~/debug-root-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# Issue an ephemeral cert for a debugging session (when needed)
# Bring the root key online temporarily:
openssl req -new -nodes \
  -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout /tmp/debug-session.key \
  -out /tmp/debug-session.csr \
  -subj "/CN=Debug Session $(date +%Y%m%d)/O=Personal"

openssl x509 -req \
  -in /tmp/debug-session.csr \
  -CA ~/debug-root-ca.crt \
  -CAkey ~/secure-offline/debug-root-ca.key \
  -CAcreateserial \
  -out /tmp/debug-session.crt \
  -days 1

# Configure mitmproxy to use the ephemeral cert:
mitmproxy --set client_certs=/tmp/debug-session.crt \
  --certs /tmp/debug-session.crt --cert-passphrase ""
```

The ephemeral certificate expires in 24 hours. The root key goes
back offline immediately after issuance. Your system trust store
contains only the long-lived root — which is useless without the
private key — so there is no permanently-exposed signing capability
on your machine.

This approach eliminates the "install CA / remove CA" dance for
each debugging session while maintaining a tighter security boundary
than leaving mitmproxy's auto-generated CA permanently trusted.

## Configuring clients to use the proxy

### System-wide proxy (macOS)

```sh
# Set HTTP proxy
networksetup -setwebproxy "Wi-Fi" localhost 8080

# Set HTTPS proxy
networksetup -setsecurewebproxy "Wi-Fi" localhost 8080

# Disable when done
networksetup -setwebproxystate "Wi-Fi" off
networksetup -setsecurewebproxystate "Wi-Fi" off
```

Charles and Proxyman handle this automatically when they start/stop.
mitmproxy does not — configure manually or use the commands above.

### Environment variables

Most CLI tools and many libraries respect the standard proxy
environment variables:

```sh
export HTTP_PROXY=http://localhost:8080
export HTTPS_PROXY=http://localhost:8080
export NO_PROXY=localhost,127.0.0.1,.internal.example.com
```

`NO_PROXY` is critical — without it, requests to `localhost` (your
own development server) route through the proxy, which is usually
not what you want and can cause loops.

### Per-tool proxy configuration

```sh
# curl (uses environment variables, or explicit)
curl --proxy http://localhost:8080 https://api.example.com/v1/data

# git (for debugging git HTTP operations)
git -c http.proxy=http://localhost:8080 fetch origin

# npm/yarn
npm config set proxy http://localhost:8080
npm config set https-proxy http://localhost:8080

# pip
pip install --proxy http://localhost:8080 somepackage
```

## Proxy + VPN interaction

This is where the layers stack up and break. The problem:

1. The VPN client installs routes for corporate traffic.
2. The proxy listens on `localhost:8080`.
3. The client sends traffic to the proxy at `localhost:8080`.
4. The proxy makes the real request to the target server.
5. The proxy's outbound request uses the host's routing table — which
   includes the VPN routes.

**This usually works** — the proxy makes requests as if it were any
application on the host, and VPN routing applies normally.

**When it breaks:**

- **Full-tunnel VPN with proxy bypass:** some VPN configurations
  route `127.0.0.0/8` through the tunnel. The client can't reach the
  local proxy because "localhost" routes through the VPN. Fix:
  ensure localhost is excluded from VPN routing (see the
  [VPN page](vpn.md#preserve-localhost-routing)).
- **Split-tunnel + proxy for VPN traffic:** you want to capture traffic
  going to a corporate API that's only reachable through the VPN. The
  proxy sits between the client and the VPN — this works as long as
  the proxy's outbound traffic follows VPN routes. Verify with
  `curl --proxy http://localhost:8080 https://internal.api.corp/health`.
- **VPN overrides system proxy settings:** some corporate VPN clients
  (Cisco AnyConnect, Zscaler) force their own proxy configuration,
  overriding the system proxy you set for mitmproxy. The VPN client
  installs a PAC file or system proxy that takes precedence. In this
  case, use environment variables (`HTTP_PROXY`) rather than system
  proxy settings — environment variables are per-process and cannot
  be overridden by the VPN.

## Proxy + containers

Containers do not inherit the host's proxy settings unless explicitly
configured.

### Passing proxy to container builds

```dockerfile
# These are built-in build args (no ARG declaration needed)
# Set them at build time:
podman build \
  --build-arg HTTP_PROXY=http://host.containers.internal:8080 \
  --build-arg HTTPS_PROXY=http://host.containers.internal:8080 \
  .
```

Note: `host.containers.internal` (Podman) or `host.docker.internal`
(Docker) resolves to the host from inside the container. Using
`localhost` inside a container refers to the container's own loopback.

### Passing proxy to running containers

```yaml
services:
  api:
    environment:
      HTTP_PROXY: http://host.containers.internal:8080
      HTTPS_PROXY: http://host.containers.internal:8080
      NO_PROXY: localhost,127.0.0.1
    extra_hosts:
      - "host.containers.internal:host-gateway"
```

The container also needs the proxy CA certificate in its trust store:

```dockerfile
COPY mitmproxy-ca-cert.pem /usr/local/share/ca-certificates/mitmproxy.crt
RUN update-ca-certificates
```

Or mount it at runtime:

```sh
podman run -v ~/.mitmproxy/mitmproxy-ca-cert.pem:/usr/local/share/ca-certificates/mitmproxy.crt \
  --env HTTPS_PROXY=http://host.containers.internal:8080 \
  myapp
```

## Transparent proxy (advanced)

Instead of configuring each client to use the proxy, you can redirect
traffic at the network layer — all outbound HTTP/HTTPS traffic is
routed to the proxy without the client knowing.

### macOS (pf)

```sh
# /etc/pf.conf addition (redirect port 80/443 to mitmproxy transparent port)
rdr pass on lo0 proto tcp from any to any port {80, 443} -> 127.0.0.1 port 8080

# Enable and load
sudo pfctl -e -f /etc/pf.conf

# Run mitmproxy in transparent mode
mitmproxy --mode transparent
```

### Linux (iptables)

```sh
# Redirect outbound HTTP/HTTPS to mitmproxy
sudo iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8080
sudo iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8080

# Run mitmproxy in transparent mode
mitmproxy --mode transparent

# Remove when done
sudo iptables -t nat -D OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8080
sudo iptables -t nat -D OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8080
```

**Warning:** transparent proxying captures *all* HTTPS traffic on
those ports, including system updates, background services, and
tools that pin certificates. Use this sparingly and remove when
done.

## The SSLKEYLOGFILE alternative

For read-only capture (no modification of traffic), you can log TLS
session keys and use them to decrypt a pcap in Wireshark — no proxy
CA installation needed:

```sh
# Set the keylog file (supported by Chrome, Firefox, curl, and most OpenSSL apps)
export SSLKEYLOGFILE="$HOME/sslkeys.log"

# Capture traffic normally
sudo tcpdump -i en0 -w capture.pcap

# Open capture.pcap in Wireshark, set:
# Preferences > Protocols > TLS > (Pre)-Master-Secret log filename = ~/sslkeys.log
# Wireshark decrypts the HTTPS traffic using the logged session keys
```

**Advantages:** no CA trust modification, no proxy configuration,
captures traffic from applications that refuse to use proxies.

**Disadvantages:** read-only (cannot modify requests), requires
launching applications with the env var set, not all applications
honor `SSLKEYLOGFILE`.

## Security considerations

- **Proxy CA private keys** are equivalent to a root CA for your
  machine. Protect `~/.mitmproxy/mitmproxy-ca.pem` like any other
  private key (permissions 600, never committed to repos, never
  shared).
- **Cloud proxy tools** (Zscaler, Cloudflare WARP) install their own
  CA certificates for TLS interception. This is the same mechanism
  you use for debugging — the difference is who controls the key.
  Know which CAs are in your trust store and why.
- **Remove proxy configuration when done.** Stale `HTTP_PROXY`
  variables cause cryptic failures weeks later when the proxy is no
  longer running. The `.envrc` pattern (variables scoped to a project
  directory) mitigates this — proxy config disappears when you leave
  the directory.
- **Never proxy in production-like environments** without
  understanding that you are degrading the security boundary.
  Interception proxies deliberately break the TLS trust model. That's
  acceptable for development debugging; it is not acceptable as a
  permanent architectural choice.
