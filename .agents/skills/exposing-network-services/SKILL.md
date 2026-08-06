---
name: exposing-network-services
description: Exposes services via nginx reverse proxy on the router. Use when adding domains, vhosts, SSL certificates, or making services accessible externally.
---

# Exposing Network Services

External and internal services are exposed through the router (`io`) via nginx reverse proxy. The source of truth is the **endpoints layer**, not raw nginx config.

## The model

Declare the endpoint on the **service machine** (in the service's own module), and give the router permission to import it. The router derives everything else: the cached internal DNS record, the public DNS record, ddclient zones, and the reverse-proxy vhost.

- **Service side** — the service module emits `my.endpoints.services.<service>`, declaring its own `upstream`, the `router` import permission, and its vhosts.
- **Router side (`io`)** — declares which machines to import via `my.endpoints.imports.machines`, plus per-endpoint `vhostOverrides` for router-only concerns (ACME is the common one).

Do **not** add public services as raw `my.router.nginx.virtualHosts` on io: raw WAN-listening vhosts are rejected by an assertion, and hand-maintained ddclient zones are gone — the public registry and ddclient are derived from the endpoints layer. Raw io vhosts are only for a trusted escape hatch (e.g. `journal-upload` binds `10.0.0.1`).

## Configuration Location

- Service module: `modules/system/<service>.nix` — its `my.<service>.endpoints` option (usually `mkStandardEndpointsOptions`) and the `my.endpoints.services.<service>` it emits.
- Router: `machines/io/configuration.nix` → `my.endpoints.imports`.

## Adding an endpoint, the idiomatic way

1. **In the service module**, add a `my.<service>.endpoints` option (see the `mkStandardEndpointsOptions` pattern) and emit an endpoint:

```nix
# modules/system/<service>.nix
my.endpoints.services.<service> = lib.mkIf cfg.endpoints.enable {
  upstream = {
    host = cfg.address;   # the service's own listen address
    port = cfg.port;
  };
  # io is allowed to import this endpoint
  router = { inherit (cfg.endpoints.router) enable targets; };
  http.virtualHosts = lib.optional (cfg.endpoints.domain != null) {
    inherit (cfg.endpoints) domain;
    # supply options from the vhost table below
  };
};
```

1. **In `machines/makemake/configuration.nix`** (or whichever machine runs the service), enable it with the expected shape:

```nix
<service> = {
  enable = true;
  endpoints = {
    enable = true;
    domain = "myapp.stark.pub";
    public = true;                 # or lanOnly = true + useWildcard for *.lan.stark.pub
    router = { enable = true; targets = ["io"]; };
  };
};
```

1. **In `machines/io/configuration.nix`**, add an import/override if needed:

```nix
my.endpoints.imports = {
  machines = ["makemake"];
  routerName = "io";
  # Router-side concerns, e.g. DNS-01 ACME for a public domain not covered by
  # a wildcard cert. Mirror the nous / accounted-invoice precedent.
  vhostOverrides."<service>.<endpoint>" = {
    acmeDns01 = {
      dnsProvider = "cloudflare";
      environmentFile = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";
    };
  };
};
```

## Virtual Host Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `domain` | string | required | FQDN for the vhost |
| `public` | bool | `false` | Intentionally public (WAN-reachable, rate-limited). |
| `cloudflareProxied` | bool | `false` | Require traffic via Cloudflare edge IPs (LAN/WireGuard still allowed) |
| `lanOnly` | bool | `false` | Restrict access to LAN/WireGuard |
| `targetHost`/`targetPort`/`targetScheme` | * | `null` | Override the endpoint-level upstream for this vhost |
| `websockets` | bool | `true` | WebSocket upgrade proxying (`false` for plain REST/webhooks) |
| `rateLimit` | `"strict"`\|`null`\|attrset | `"strict"` | `"strict"` = shared 10r/m public zone; `null` = exempt (SPA apps); `{rate,burst,nodelay}` = dedicated zone |
| `noAcme` | bool | `false` | Disable ACME for this vhost |
| `useWildcard` | string\|`null` | `null` | Name of wildcard cert (e.g. `"lanstark"` for `*.lan.stark.pub`) |
| `acmeDns01` | attrset\|`null` | `null` | DNS-01 ACME (Cloudflare) — for public domains not under a wildcard |
| `basicAuth`/`basicAuthSecret` | attrset | `null` | Router-resolved HTTP Basic Auth |
| `publishDns` | bool | `true` | Publish the derived DNS record for this vhost |
| `extraConfig` | string | `""` | Extra nginx location config |

There is no `cloudflareOnly` option — the current name is `cloudflareProxied`.

## Access Control Patterns

### Public via Cloudflare

```nix
{
  domain = "myapp.stark.pub";
  public = true;
  cloudflareProxied = true;
}
```

Real client IP comes from the CF edge; Cloudflare IPs are auto-updated by a systemd timer.

### LAN / VPN only

```nix
{
  domain = "internal.lan.stark.pub";
  lanOnly = true;
  useWildcard = "lanstark";   # *.lan.stark.pub wildcard cert
}
```

### Public webhook, everything else 444 (the invoices precedent)

```nix
{
  public = true;
  websockets = false;
  extraConfig = ''
    if ($uri !~ ^/api/extensions/ext/invoice-inbox/inbound) {
      return 444;
    }
  '';
}
```

## Certificate Strategies

- **HTTP-01 (default)** for public vhosts.
- **Wildcard** for `*.lan.stark.pub` (DNS-01): declare `my.router.nginx.wildcardCerts` (`name = "lanstark"; baseDomain = "lan.stark.pub"; ...`), reference with `useWildcard = "lanstark"`. Router only.
- **DNS-01 (cloudflare)**: for public domains not under a wildcard cert (e.g. `*.stark.pub`). Handle on the router via `vhostOverrides.<service>.<endpoint>.acmeDns01` (see nous, accounted-invoice in `machines/io/configuration.nix`), or declare `acmeDns01` in the module.
- **`noAcme`**: self-signed/other.

## DNS resolution (split-horizon)

- **Internal**: `io`'s own resolver (blocky → unbound) serves the derived local-data: every vhost resolves to the **router LAN IP `10.0.0.1`** (or the direct upstream for non-HTTP services like `mail`). LAN clients never touch the public/WAN IP, because NAT hairpin is impossible (WAN-ingress-only DNAT + strict rp_filter). This is documented in `modules/system/router/dns.nix`.
- **External**: the same names resolve (via Cloudflare, updated by ddclient) to the current **public IP**. Domains are picked up automatically from the derived `my.publicDomains` registry — you do **not** hand-edit ddclient zones.

Non-HTTP direct records are declared explicitly if needed (e.g. `my.router.services = [{ name = "mail.stark.pub"; target = "10.0.0.10"; }]`), and public non-vhost records go in `my.publicDnsRecords`.

## Checklist

- [ ] Endpoint declared in the **service module** (`my.endpoints.services.<service>`), not on io
- [ ] `upstream` host/port is the service's own listen address
- [ ] `router = { enable = true; targets = ["io"] }` on the service
- [ ] `machines/io` lists the machine in `my.endpoints.imports.machines`
- [ ] Choose access control: `cloudflareProxied`, `lanOnly`, or public/open
- [ ] Cert strategy: default HTTP-01, `useWildcard` (`*.lan.stark.pub`), or `acmeDns01` via `vhostOverrides`
- [ ] No hand-written io `nginx.virtualHosts` or ddclient zones for public domains
- [ ] Validate: `path:.#router-endpoints-checks` and `path:.#endpoints-manifest-check`

## Test Workflow

1. Endpoint-layer changes: `nix build path:.#router-endpoints-checks` (`router-endpoints-smoke`, `-dns-and-vhost`, `-lan-only-enforcement`, `-dns-auto`, `-extra-config`)
2. Manifest consistency: `nix build path:.#endpoints-manifest-check`
3. io config changes: `nix build path:.#predeploy-check`
4. Before deployment: `nix build path:.#final-checks`, then `nix flake check` and `machine-update <machine>`.
