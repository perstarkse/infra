---
name: creating-services
description: Creates and maintains NixOS service modules for the heliosphere homelab. Use when adding a new service, wiring reverse proxy and DNS exposure, importing remote services into the router, managing secrets via clan vars, or adding firewall rules. Covers both router-local and cross-machine (router-imported) exposure patterns.
---

# Creating and Maintaining Services

## Quick start

A service module is a NixOS flake module under `modules/system/<name>.nix` that:
1. Defines options under `my.<name>` (with `lib.mkOption`)
2. Configures the actual service (systemd, podman, or NixOS service)
3. Populates `my.exposure.services.<name>` for reverse proxy, DNS, and firewall

Minimal working example:

```nix
_: {
  config.flake.nixosModules.minne = {
    config, lib, ...
  }: let cfg = config.my.minne;
  in {
     options.my.minne = {
       enable = lib.mkEnableOption "Enable minne";
       port = lib.mkOption { type = lib.types.port; default = 3000; };
       address = lib.mkOption { type = lib.types.str; default = config.my.listenNetworkAddress; };
       exposure = mkStandardExposureOptions {
         subject = "Minne";
         visibility = "internal";
         withRouter = true;
       };
     };

    config = lib.mkIf cfg.enable {
      systemd.services.minne = { /* ... */ };

      my.exposure.services.minne = lib.mkIf cfg.exposure.enable {
        upstream = { host = cfg.address; inherit (cfg) port; };
        router = { inherit (cfg.exposure.router) enable targets; };
        http.virtualHosts = [{ domain = cfg.exposure.domain; inherit (cfg.exposure) lanOnly useWildcard; }];
        firewall.local = { enable = true; tcp = [cfg.port]; };
      };
    };
  };
}
```

## Workflow

Copy this checklist when creating or modifying a service:

```
Service Progress:
- [ ] Step 1: Write the module under modules/system/<name>.nix
- [ ] Step 2: Define options (enable, port, address, exposure, secrets)
- [ ] Step 3: Implement the service (systemd, podman, or NixOS service)
- [ ] Step 4: Populate my.exposure.services.<name>
- [ ] Step 5: Wire secrets via my.secrets.declarations or my.secrets.discover tags
- [ ] Step 6: Import the module in the machine's configuration.nix
- [ ] Step 7: Configure the service in the machine's configuration.nix
- [ ] Step 8: Run nix flake check
- [ ] Step 9: Run exposure-manifest-check for domain/DNS conflicts
- [ ] Step 10: Deploy with machine-update <host>
```

## Exposure patterns

Three exposure tiers exist, pick based on where the service runs:

| Tier | Use when | Vhost generated on | Router key |
|------|----------|-------------------|------------|
| **Local-only** | Service on the router itself (`io`), LAN-accessible | Router | `exposure.enable = true` (no router sub-option needed) |
| **Router-imported** | Service on another machine (e.g. `makemake`), needs reverse proxy + DNS on the router | Router (imported) | `exposure.router.enable = true; exposure.router.targets = ["io"];` |
| **Host-local** | Service only accessed locally or via direct IP | The service host | No exposure at all |

### Router-imported services (cross-machine)

When the service runs on `makemake` but needs an nginx vhost + DNS on `io`:

**On the service host (makemake):**
```nix
my.minne.exposure = {
  enable = true;
  domain = "minne.lan.stark.pub";
  useWildcard = "lanstark";
  router = {
    enable = true;
    targets = ["io"];
  };
};
```

**On the router (io):**
```nix
my.exposure.routerImports = {
  machines = ["makemake"];
  routerName = "io";
};
```

The router auto-discovers all services with `router.enable = true` from listed machines and generates nginx vhosts, DNS records, and firewall ports.

### Local services on the router

Services running directly on `io` don't need `router.enable` — they just set `exposure.enable = true` and optionally use `lanOnly`, `useWildcard`, or `cloudflareProxied`.

## Secrets

**Using clan vars generators (recommended for pre-existing secrets):**
```nix
my.secrets.discover = {
  enable = true;
  dir = ../../vars/generators;
  includeTags = ["minne"];
};
```

**Generating machine-local secrets:**
```nix
my.secrets.declarations = [
  (config.my.secrets.mkMachineSecret {
    name = "minne-env";
    files."env" = {
      mode = "0400";
      additionalReaders = ["minne"];
    };
    prompts."api-key".input = {
      description = "API key";
      type = "hidden";
      persist = true;
    };
    script = ''
      echo "API_KEY=$(cat "$prompts/api-key")" > "$out/env"
    '';
  })
];
```

**Consuming secrets in services:**
```nix
config.my.secrets.getPath "minne-env" "env"  # → /run/secrets/vars/minne-env/env
```

## Common pitfalls

- **Missing `lanOnly` or `public` on vhosts**: Every virtual host must set `lanOnly = true`, `public = true`, or `cloudflareProxied = true`. The flake check enforces this via an assertion in `options.nix`. `cloudflareProxied` counts as implicitly public.
- **`noAcme` with `cloudflareProxied`**: These are mutually exclusive — Cloudflare expects the backend to serve HTTPS. The flake check enforces this.
- **Double firewall rules**: Don't set `networking.firewall.allowedTCPPorts` AND `exposure.firewall.local` for the same ports. Use `exposure.firewall.local` — it is processed automatically by `options.nix`.
- **Router-import without `targets`**: If `router.targets = []` (default), the exposure is importable by ANY router. Set `targets = ["io"]` to restrict.
- **Service runs on a non-router machine without `options` module**: If `mkStandardExposureOptions` is unresolved, ensure the importing machine config has `nixosModules.options` in its imports (or clan's `specialArgs` is wired).
- **Service module function needs the arg**: Add `mkStandardExposureOptions` to the NixOS module function signature alongside `config`, `lib`, `pkgs`.
- **Secrets in tests**: Use `import ./lib/secrets-stub.nix { inherit lib; getPathDefault = ...; }` for test secret stubs.

## Reference

See [PATTERNS.md](PATTERNS.md) for detailed exposure patterns with full code examples.
