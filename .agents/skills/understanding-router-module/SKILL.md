---
name: understanding-router-module
description: Documents the router module architecture, options, and submodules. Use when modifying router functionality, debugging network issues, or understanding how routing/firewall/DNS/nginx work.
---

# Router Module Architecture

The router module (`modules/system/router/`) provides a complete home router implementation for the `io` machine.

## Module Structure

```
modules/system/router/
├── default.nix      # Aggregates all submodules
├── core.nix         # Option definitions and routerHelpers
├── network.nix      # systemd-networkd, bridges, VLANs
├── firewall.nix     # nftables rules, NAT, port forwarding
├── dhcp.nix         # Kea DHCP server
├── dns.nix          # blocky (LAN filtering) → unbound (DoT, local-data)
├── nginx.nix        # Reverse proxy, ACME, Cloudflare
├── wireguard.nix    # WireGuard VPN server + peer generation
├── monitoring.nix   # Prometheus, Grafana, Netdata, ntopng
└── security.nix     # fail2ban, journal receiver
```

## Core Options (`my.router`)

### Top-level

| Option | Description |
|--------|-------------|
| `enable` | Enable router functionality |
| `hostname` | Router hostname |

### Segments (`my.router.segments`)

Named network segments (replaces the old `lan`/`vlans` model), keyed by name:

```nix
segments = {
  trusted = {
    vlan.id = 1;                  # 802.1Q VLAN id (1 = native/untagged)
    subnet = "10.0.0";
    dhcp.range = { start = 100; end = 200; };  # per-segment DHCP pool
    dns.profile = "default";      # blocky profile (default/iot/kids/guests)
    policy.internet = true;       # egress control
  };
  cameras = {
    vlan.id = 30;
    subnet = "10.0.30";
    dhcp = {
      range = { start = 10; end = 50; };
      reservations = [];
    };
    policy.internet = false;      # block internet access
  };
};
```

### Ports (`my.router.ports`)

Physical switch ports and their VLAN membership:

```nix
ports = {
  enp2s0 = {
    mode = "trunk";               # or "access"
    nativeSegment = "trusted";    # untagged / PVID
    taggedSegments = ["iot" "work" "kids" "guests" "cameras"];
  };
};
```

### WAN (`my.router.wan`)

| Option | Default | Description |
|--------|---------|-------------|
| `interface` | `"enp1s0"` | WAN interface name |
| `allowedTcpPorts` / `allowedUdpPorts` | `[]` | Extra WAN-ingress ports (DNAT forwards live on `machines[].portForwards`) |

### Machines (`my.router.machines`)

Static DHCP reservations and port forwarding:

```nix
machines = [{
  name = "makemake";
  ip = "10";                  # → 10.0.0.10
  mac = "00:d0:b4:02:bb:3c";
  portForwards = [
    { port = 25; protocol = "tcp"; }
    { port = 32400; protocol = "tcp"; }
  ];
}];
```

### Services (`my.router.services`)

Local DNS entries:

```nix
services = [
  { name = "mail.stark.pub"; target = "10.0.0.10"; }
];
```

## Submodule Details

### DHCP (`my.router.dhcp`)

Kea DHCPv4 server configuration:

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable Kea DHCP |
| `validLifetime` | `86400` | Lease lifetime (seconds) |
| `renewTimer` | `43200` | Renew timer |
| `rebindTimer` | `75600` | Rebind timer |
| `domainName` | `"lan"` | Domain for DHCP clients |

### DNS (`my.router.dns`)

Two-stage resolver: LAN-facing **blocky** → **unbound** backend:

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable the router DNS stack |
| `localZones` | `["lan."]` | Authoritative local zones |
| `profiles` | `{}` | Per-segment blocky filtering profiles (default/iot/kids/guests) |
| `upstreamServers` | Cloudflare DoT | unbound upstream DNS servers |

blocky listens on `:53` on every segment's router IP and forwards to unbound (`127.0.0.1:5354`), which serves `local-data` for machines, DHCP reservations, and endpoint records. This is the **internal half of split-horizon DNS**: every vhost resolves to the router LAN IP (`10.0.0.1`) or a direct LAN upstream, so LAN clients never use the public/WAN IP (NAT hairpin is impossible — WAN-ingress-only DNAT + strict rp_filter). The public half is ddclient → Cloudflare from the derived `my.publicDomains` registry (see skill: `exposing-network-services`).

### WireGuard (`my.router.wireguard`)

VPN server with auto-generation support:

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable WireGuard |
| `interfaceName` | `"wg0"` | Interface name |
| `listenPort` | `51820` | UDP port |
| `subnet` | `"10.6.0"` | VPN subnet base |
| `routeToLan` | `true` | Route VPN ↔ LAN |
| `defaultEndpoint` | `null` | Default endpoint for generated peers |
| `peers` | `[]` | Peer configurations |

#### Peer options

```nix
peers = [{
  name = "phone";
  ip = 2;                     # → 10.6.0.2
  autoGenerate = true;        # Generate keypair + QR code
  persistentKeepalive = 25;
}];
```

When `autoGenerate = true`:

- Keypair generated via Clan secrets
- Client config + QR code stored in secrets
- Peer applied at runtime via systemd-networkd credentials
- Endpoint comes from `peer.endpoint` or `wireguard.defaultEndpoint` (no Clan prompt when either is set)
- Server public key comes from the `wireguard-server` generator dependency (`$in/wireguard-server/public-key`)

### nginx (`my.router.nginx`)

See skill: `exposing-network-services`

Key options:

- `enable`, `acmeEmail`
- `ddclient.enable`, `ddclient.zones`
- `wildcardCerts`
- `virtualHosts`

### Monitoring (`my.router.monitoring`)

| Component | Options |
|-----------|---------|
| Prometheus | `enable`, `port`, `exporters`, `scrapeConfigs` |
| Grafana | `enable`, `httpAddr`, `httpPort`, `dataDir` |
| Netdata | `enable`, `bindAddress` |
| ntopng | `enable`, `httpPort`, `interfaces` |

### Security (`my.router.security`)

| Option | Description |
|--------|-------------|
| `enable` | Enable security features |
| `fail2ban.enable` | Enable fail2ban |
| `fail2ban.jails.*` | Per-service jails (sshd, nginx, mail) |
| `journalReceiver.enable` | Receive logs from other hosts |

## Router Helpers

The `core.nix` module computes `config.routerHelpers` for use by submodules:

```nix
routerHelpers = {
  primarySegmentName = "trusted";
  primarySubnet = "10.0.0";
  primaryCidr = "10.0.0.0/24";
  primaryRouterIp = "10.0.0.1";
  primaryInterface = "vlan1";
  segments = { /* segment name → computed segment helpers */ };
  zones = [ /* unified zone model for firewall */ ];
  wanInterface = "enp1s0";
  lanBridge = "br-lan";
  bridgePorts = [ /* physical bridge ports */ ];
  machineMap = { /* machine name → {ip, fullIp, mac, ...} */ };
};
```

The old `lanSubnet`/`lanCidr`/`routerIp`/`dhcpStart`/`dhcpEnd`/`ulaPrefix`/`lanInterfaces`/`vlans` aliases were removed.

### Zone Model

Zones abstract network segments for firewall rules:

```nix
zones = [
  { name = "trusted"; kind = "segment"; interface = "vlan1"; subnetCidr = "10.0.0.0/24"; ... }
  { name = "cameras"; kind = "segment"; interface = "vlan30"; internet = false; ... }
  { name = "wireguard"; kind = "wireguard"; interface = "wg0"; ... }
  { name = "wan"; kind = "wan"; interface = "enp1s0"; ... }
];
```

## Firewall Architecture

`firewall.nix` generates nftables rules:

- **NAT**: Masquerade for zones with `nat = true`
- **Forward**: Zone-to-zone rules based on `allowTo`
- **Port forwards**: From `machines[].portForwards`
- **VLAN isolation**: segments with `policy.internet = false` blocked from WAN

## Network Architecture

`network.nix` configures systemd-networkd:

- **br-lan**: Bridge combining LAN interfaces
- **vlanN**: Tagged VLAN interfaces on br-lan
- **wg0**: WireGuard interface
- **WAN**: DHCP client on WAN interface (`RequiredForOnline = "no"` — ISP/PHY failure must not gate boot)
- **wait-online**: waits only for the primary LAN segment (`ConfigureWithoutCarrier` + static address), not WAN or every VLAN
- **igc EEE**: systemd.link `EnergyEfficientEthernet=false` plus an `igc-disable-eee` ethtool oneshot (Intel I225/I226 often leave the link dark after the driver binds)

## Common Modifications

### Add a new segment

```nix
my.router.segments.iot = {
  vlan.id = 40;
  subnet = "10.0.40";
  policy.internet = true;   # Allow internet
};
```

Also tag the segment on the physical ports it should reach (`my.router.ports.<iface>.taggedSegments`).

### Add a WireGuard peer

```nix
my.router.wireguard.peers = [
  {
    name = "laptop";
    ip = 5;
    autoGenerate = true;
    persistentKeepalive = 25;
  }
];
```

Then: `clan vars generate --match wireguard-peer-laptop`

### Add port forwarding

```nix
my.router.machines = [
  {
    name = "server";
    ip = "10";
    mac = "aa:bb:cc:dd:ee:ff";
    portForwards = [
      { port = 8080; protocol = "tcp"; }
    ];
  }
];
```

### Add local DNS entry

```nix
my.router.services = [
  { name = "myapp.lan"; target = "10.0.0.10"; }
];
```

## Testing and Verification

Use local flake targets (these include uncommitted files via `path:.`):

- `nix build path:.#router-checks` — full router-focused suite
- `nix build path:.#predeploy-check` — `io-predeploy` only
- `nix build path:.#final-checks` — router suite + predeploy

Targeted checks:

- `nix build path:.#checks.x86_64-linux.router-services` for nginx/vhost/access control changes
- `nix build path:.#checks.x86_64-linux.router-port-forward` for NAT/forwarding changes
- `nix build path:.#checks.x86_64-linux.router-wireguard` for WireGuard changes

What these tests cover:

- `router-*` tests validate module behavior in focused multi-node topologies
- `io-predeploy` validates actual `machines/io/configuration.nix` behavior with test overrides for hardware/secrets/container-heavy runtime

Recommended workflow:

1. During router module edits: run `path:.#router-checks`
2. Before merge/deploy: run `path:.#final-checks`

## File Reference

| File | Responsibility |
|------|---------------|
| `core.nix` | All `my.router.*` options, `routerHelpers` computation |
| `network.nix` | systemd-networkd: bridges, VLANs, addressing |
| `firewall.nix` | nftables: NAT, forwarding, port forwards |
| `dhcp.nix` | Kea DHCP4 server configuration |
| `dns.nix` | blocky (LAN filtering) → unbound: DoT, local zones, split-horizon local-data |
| `nginx.nix` | nginx: vhosts, ACME, Cloudflare IP updates, ddclient |
| `wireguard.nix` | WireGuard: server, peers, auto-generation |
| `monitoring.nix` | Prometheus, Grafana, Netdata, ntopng |
| `security.nix` | fail2ban, systemd-journal-remote |
