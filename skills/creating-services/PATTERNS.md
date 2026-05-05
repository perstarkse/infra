# Exposure Patterns Reference

## Contents
- Router-local service (lanOnly)
- Router-local service (public + Cloudflare)
- Router-imported service (lanOnly)
- Router-imported service (public + Cloudflare)
- Service with DNS-only exposure (no HTTP)
- Service with custom DNS records
- Service with source-restricted firewall
- Service with basicAuth (router-resolved secret)
- Service with DNS-01 ACME certificate
- Service with extra nginx config
- Podman-based service with exposure
- Service without any exposure

---

## Router-local service (lanOnly)

Service runs on `io`, accessible only from LAN/WireGuard.

```nix
my.ntfy = {
  enable = true;
  address = "10.0.0.1";
  baseUrl = "https://ntfy.lan.stark.pub";
  secretName = "ntfy";
  exposure = {
    enable = true;
    useWildcard = "lanstark";
    lanOnly = true;
    # domain defaults to derived from baseUrl
  };
};
```

Module pattern:
```nix
my.exposure.services.ntfy = lib.mkIf cfg.exposure.enable {
  upstream = { host = cfg.address; inherit (cfg) port; };
  http.virtualHosts = [{
    inherit (cfg.exposure) domain lanOnly useWildcard;
    extraConfig = cfg.exposure.extraConfig;
    websockets = true;
  }];
  firewall.local = { enable = cfg.openFirewall; tcp = [cfg.port]; };
};
```

## Router-local service (public + Cloudflare)

Service runs on `io`, publicly accessible via Cloudflare proxy.

```nix
my.wake-proxy.exposure = {
  enable = true;
  domain = "wake.stark.pub";
  public = true;
  cloudflareProxied = true;
  acmeDns01 = {
    dnsProvider = "cloudflare";
    environmentFile = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";
  };
};
```

This uses DNS-01 challenge so ACME can issue certs even behind Cloudflare's proxy.

## Router-imported service (lanOnly)

Service runs on `makemake`, reverse proxied through `io`, LAN-only.

**makemake configuration:**
```nix
my.vaultwarden = {
  enable = true;
  port = 8322;
  address = "10.0.0.10";
  backupDir = "/data/passwords";
  exposure = {
    enable = true;
    domain = "vault.stark.pub";
    lanOnly = true;
    acmeDns01 = {
      dnsProvider = "cloudflare";
      environmentFile = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";
    };
    router = {
      enable = true;
      targets = ["io"];
    };
  };
};
```

**io configuration:**
```nix
my.exposure.routerImports = {
  machines = ["makemake"];
  routerName = "io";
};
```

**Module pattern:**
```nix
my.exposure.services.vaultwarden = lib.mkIf cfg.exposure.enable {
  upstream = { host = cfg.address; inherit (cfg) port; };
  router = { inherit (cfg.exposure.router) enable targets; };
  http.virtualHosts = lib.optional (cfg.exposure.domain != null) {
    inherit (cfg.exposure) domain lanOnly useWildcard acmeDns01;
    websockets = true;
  };
  firewall.local = { enable = true; tcp = [cfg.port]; };
};
```

The `router` sub-option is passed through verbatim. The exposure library uses `targets` to restrict which routers can import, and `targetHost`/`dnsTarget` to override defaults.

## Router-imported service (public + Cloudflare)

Service runs on `makemake`, publicly accessible via Cloudflare.

**makemake configuration:**
```nix
my.openwebui = {
  enable = true;
  port = 8080;
  autoUpdate = true;
  updateSchedule = "weekly";
  exposure = {
    enable = true;
    domain = "chat.stark.pub";
    public = true;
    cloudflareProxied = true;
    router = {
      enable = true;
      targets = ["io"];
    };
  };
};
```

**Module pattern:**
```nix
my.exposure.services.openwebui = lib.mkIf cfg.exposure.enable {
  upstream = { host = config.my.listenNetworkAddress; inherit (cfg) port; };
  router = { inherit (cfg.exposure.router) enable targets; };
  http.virtualHosts = lib.optional (cfg.exposure.domain != null) {
    inherit (cfg.exposure) domain;
    inherit (cfg.exposure) public cloudflareProxied;
  };
  firewall.local = { enable = true; tcp = [cfg.port]; };
};
```

## Service with DNS-only exposure (no HTTP)

Service only needs a DNS record, not an HTTP reverse proxy.

```nix
my.exposure.services.unifi-router = {
  upstream = {
    host = "10.0.0.21";
    port = 443;
    scheme = "https";
  };
  http.virtualHosts = [{
    domain = "unifi.lan.stark.pub";
    lanOnly = true;
    useWildcard = "lanstark";
  }];
  dns.records = [{
    name = "unifi.lan.stark.pub";
    target = "10.0.0.1";
  }];
};
```

## Service with custom DNS records

When a service needs additional DNS names beyond what vhosts provide:

```nix
my.exposure.services.paperless = lib.mkIf cfg.exposure.enable {
  upstream = { host = cfg.address; inherit (cfg) port; };
  router = { inherit (cfg.exposure.router) enable targets; };
  http.virtualHosts = lib.optional (cfg.exposure.domain != null) {
    inherit (cfg.exposure) domain lanOnly useWildcard extraConfig;
    websockets = true;
    # publishDns defaults to true — generates DNS record from domain
  };
  dns.records = [
    { name = "docs.lan.stark.pub"; target = "makemake"; }
  ];
  firewall.local = { enable = cfg.openFirewall; tcp = [cfg.port]; };
};
```

DNS records with `target = "makemake"` use `routerHelpers.machineMap` to resolve the machine name to its full IP. Use raw IPs for non-machine targets.

## Service with source-restricted firewall

```nix
my.exposure.services.paperless = {
  upstream = { host = cfg.address; inherit (cfg) port; };
  firewall.local = {
    enable = true;
    tcp = [cfg.port];
    allowedSources = ["10.0.0.1"];  # only the router can reach this service
  };
};
```

When `allowedSources` is non-empty, `options.nix` generates nftables rules that accept from only those sources and drop everything else. Empty means unrestricted (standard `allowedTCPPorts`).

## Service with basicAuth (router-resolved secret)

For cross-machine services where the auth file lives on the router:

```nix
my.exposure.services.webdav-garage = lib.mkIf cfg.exposure.enable {
  upstream = { host = "127.0.0.1"; port = 8080; };
  router = { enable = true; targets = ["io"]; };
  http.virtualHosts = [{
    domain = "webdav.lan.stark.pub";
    lanOnly = true;
    useWildcard = "lanstark";
    basicAuthSecret = {
      realm = "WebDAV";
      name = "webdav-htpasswd";
      file = "htpasswd";
    };
  }];
};
```

The `basicAuthSecret` is resolved by the importing router via `resolveBasicAuthSecret` callback. The secret must exist on the router machine.

For router-local services with auth, use the direct `basicAuth` option:
```nix
basicAuth = {
  realm = "Restricted";
  htpasswdFile = config.my.secrets.getPath "my-secret" "htpasswd";
};
```

## Service with DNS-01 ACME certificate

When HTTP-01 challenge won't work (e.g., Cloudflare proxied domains or domains that can't serve HTTP on port 80):

```nix
http.virtualHosts = [{
  domain = "vault.stark.pub";
  lanOnly = true;
  acmeDns01 = {
    dnsProvider = "cloudflare";
    environmentFile = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";
  };
}];
```

This creates a `security.acme.certs."vault.stark.pub"` entry with DNS-01 provider config.

## Service with extra nginx config

Some services need special nginx location directives (body size, timeouts, buffering):

```nix
http.virtualHosts = [{
  domain = "ntfy.lan.stark.pub";
  lanOnly = true;
  extraConfig = ''
    client_max_body_size 0;
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_read_timeout 1h;
    proxy_send_timeout 1h;
  '';
}];
```

The extra config is placed inside the `location /` block, not at the server level.

## Podman-based service with exposure

Services running as OCI containers use `--network=host` for simplicity:

```nix
config = lib.mkIf cfg.enable {
  virtualisation.oci-containers.containers.openwebui = {
    image = "ghcr.io/open-webui/open-webui:main";
    volumes = ["${cfg.dataDir}:/app/backend/data"];
    extraOptions = ["--network=host"];
    autoStart = true;
  };

  my.exposure.services.openwebui = lib.mkIf cfg.exposure.enable {
    upstream = { host = config.my.listenNetworkAddress; inherit (cfg) port; };
    router = { inherit (cfg.exposure.router) enable targets; };
    http.virtualHosts = lib.optional (cfg.exposure.domain != null) {
      inherit (cfg.exposure) domain public cloudflareProxied;
    };
    firewall.local = { enable = true; tcp = [cfg.port]; };
  };
};
```

## Service without any exposure

For services that don't need reverse proxy or DNS at all (e.g., databases, internal services):

```nix
config = lib.mkIf cfg.enable {
  services.surrealdb = {
    enable = true;
    host = "127.0.0.1";
    port = cfg.port;
  };
  networking.firewall.allowedTCPPorts = [cfg.port];
};
```

No `exposure` options needed at all. The service is only reachable directly by IP:port.

---

## Exposure field reference

### `exposure.upstream`
- `host`: IP or hostname of the service backend (default: `config.my.listenNetworkAddress`)
- `port`: Port the service listens on
- `scheme`: `"http"` or `"https"` (default: `"http"`)

### `exposure.http.virtualHosts` (per-vhost)
- `domain`: Domain name for the vhost (required)
- `lanOnly`: Restrict to LAN/WireGuard subnets (requires `public` or `lanOnly` set)
- `public`: Explicitly mark as intentionally public (requires `public` or `lanOnly` set)
- `cloudflareProxied`: Require CF edge IPs; LAN/WG still allowed
- `noAcme`: Skip ACME cert (self-signed or behind TLS-terminating proxy)
- `useWildcard`: Reuse a wildcard cert (e.g. `"lanstark"`)
- `acmeDns01`: Per-vhost DNS-01 ACME settings
- `basicAuth`: Direct path to htpasswd file
- `basicAuthSecret`: Router-resolved auth secret reference
- `websockets`: Enable WebSocket proxy (default: true)
- `extraConfig`: Extra nginx directives in the `location /` block
- `publishDns`: Generate DNS record from domain (default: true)
- `targetHost`: Override upstream host for this specific vhost
- `targetPort`: Override upstream port for this specific vhost
- `targetScheme`: Override upstream scheme for this specific vhost

### `exposure.dns.records`
- `name`: DNS record name (domain)
- `target`: IP address or machine name (resolved via `routerHelpers.machineMap`)

### `exposure.router`
- `enable`: Export this service for router-side aggregation
- `targets`: Router names allowed to import (empty = any router)
- `targetHost`: Router-reachable upstream host override
- `dnsTarget`: Custom DNS target for imported records

### `exposure.firewall.local`
- `enable`: Open ports on the local host firewall
- `tcp`: TCP ports to open
- `udp`: UDP ports to open
- `allowedSources`: IPs/CIDRs allowed; empty = unrestricted
