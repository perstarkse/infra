## Infra: Declarative Homelab with Nix, Clan, and the Dendritic Pattern

A reproducible homelab/infra setup managing a router, server, and workstation with Nix flakes. Orchestrated and deployed with Clan, with automated secrets management and additional ergonomics via a custom vars-helper. The repo largely follows the Dendritic pattern, organizing configuration as composable flake-parts modules.

- **Orchestration & deployment**: Clan framework
- **Secrets**: Clan automated secrets + vars-helper for ACLs and access ergonomics
- **Pattern**: Dendritic (every file is a flake-parts module)
- **Key modules**:
  - Router abstraction (routing, DHCP, DNS, WireGuard, nginx, monitoring)
  - Backups abstraction (restic to B2/S3, auto bucket bootstrap, restore mode)

### References

- Clan: [clan.lol](https://clan.lol/)
- Dendritic pattern: [github.com/mightyiam/dendritic](https://github.com/mightyiam/dendritic)

## Architecture

### Clan-based orchestration

This repo is designed to be driven by Clan, providing:

- **Uniform interface** across machines and services
- **Automated secret management** and provisioning
- **Automated service setup and backups**
- **Peer-to-peer mesh VPN** and live overwrites

See: `https://clan.lol/`.

### Dendritic pattern

Configuration is authored as flake-parts modules, promoting reuse across NixOS and Home Manager scopes, and enabling cross-cutting concerns. Values are shared via the flake `config` rather than ad-hoc `specialArgs`.

See: `https://github.com/mightyiam/dendritic`.

### Secrets and vars-helper

Secrets are declared and generated via Clan. The custom vars-helper adds:

- **Secret discovery** from a generators directory with tag filtering
- **ACLs** to grant read access to specific systemd units/services
- **Ergonomics** around reading secrets paths from the declarative config

See: `https://github.com/perstarkse/clan-vars-helper`.

Example usage in `machines/makemake/configuration.nix`:

```nix
my.secrets.discover = {
  enable = true;
  dir = ../../vars/generators;
  includeTags = ["makemake" "minne" "surrealdb"  "b2"];
};

my.secrets.allowReadAccess = [
  {
    readers = ["minne"];
    path = config.my.secrets.getPath "minne-env" "env";
  }
  {
    readers = ["surrealdb"];
    path = config.my.secrets.getPath "surrealdb-credentials" "credentials";
  }
];
```

## Machines

- `machines/io`: Router (LAN bridge, DHCP, DNS, WireGuard, nginx, monitoring)
- `machines/makemake`: Server (Vaultwarden, OpenWebUI, SurrealDB, Minne, Minecraft)
- `machines/charon`: Workstation
- `machines/oumuamua`: Staging system

Each machine imports shared modules via flake-parts, follows consistent patterns, and consumes secrets declaratively.

## Local test workflow

Recommended commands:

- `nix build path:.#router-checks` — router integration suite (`router-smoke`, `router-vlan-regression`, `router-services`, `router-port-forward`, `router-wireguard`).
- `nix build path:.#predeploy-check` — `io-predeploy` only (real `machines/io/configuration.nix` with test overrides/stubs).
- `nix build path:.#final-checks` — router suite + `io-predeploy`.
- `nix flake check path:.` — all configured checks in this flake.

Useful targeted checks:

- `nix build path:.#checks.x86_64-linux.router-services` for nginx/domain routing changes.
- `nix build path:.#checks.x86_64-linux.router-port-forward` for NAT/port-forward changes.
- `nix build path:.#checks.x86_64-linux.io-predeploy` for full `io` predeploy coverage only.

Notes:

- Prefer `path:.#...` during local work; it includes uncommitted files.
- `nix build path:.#checks.x86_64-linux` builds all checks for that system.
- Add `--show-trace` to any command for full error traces.

## Module: Router

- Path: `modules/system/router/core.nix`
- Consumers: e.g. `machines/io/configuration.nix`

### Features

- **LAN**: bridge with configurable interfaces and subnet
- **DHCP**: Kea with declarative leases and timings
- **DNS**: Unbound with DoT upstreams and local zone
- **WireGuard**: server with peers, keepalive, LAN routing
- **nginx reverse proxy**: ACME automation (including DNS-01 per-vhost), Cloudflare-only or LAN-only ACLs, WebSocket support, extra config snippets
- **Monitoring**: Prometheus exporters (node, unbound), Prometheus, optional Grafana, Netdata, ntopng

### Example declaration (simplified from `machines/io/configuration.nix`)

```nix
my.router = {
  enable = true;
  hostname = "io";

  lan = {
    subnet = "10.0.0";
    dhcpRange = { start = 100; end = 200; };
    interfaces = ["enp2s0" "enp3s0" "enp4s0"];
  };

  wan.interface = "enp1s0";
  ipv6.ulaPrefix = "fd00:711a:edcd:7e75";

  wireguard = {
    enable = true;
    peers = [
      {
        name = "phone";
        ip = 2;
        publicKey = "...";
        persistentKeepalive = 25;
      }
    ];
  };

  machines = [
    { name = "charon";   ip = "15"; mac = "f0:2f:74:de:91:0a"; portForwards = []; }
    { name = "makemake"; ip = "10"; mac = "00:d0:b4:02:bb:3c";
      portForwards = [ { port = 25; } { port = 465; } { port = 993; } { port = 32400; } ];
    }
  ];

  dns = {
    enable = true;
    upstreamServers = [
      "1.1.1.1@853#cloudflare-dns.com"
      "1.0.0.1@853#cloudflare-dns.com"
      "2606:4700:4700::1111@853#cloudflare-dns.com"
      "2606:4700:4700::1001@853#cloudflare-dns.com"
    ];
    localZone = "lan.";
  };

  nginx = {
    enable = true;
    acmeEmail = "email@domain.tld";
    ddclient.enable = true;
    virtualHosts = [
      { domain = "service.domain.tld"; target = "makemake"; port = 7909; websockets = true; cloudflareOnly = true; }
      {
        domain = "service2.domain.tld"; target = "makemake"; port = 3000; cloudflareOnly = true; websockets = false;
        extraConfig = ''
          proxy_set_header Connection "close";
          proxy_http_version 1.1;
          chunked_transfer_encoding off;
          proxy_buffering off;
          proxy_cache off;
        '';
      }
      # Example DNS-01 per-vhost
      { domain = "service.domain.tld"; target = "makemake"; port = 8322; websockets = true; lanOnly = true;
        acmeDns01 = {
          dnsProvider = "cloudflare";
          environmentFile = config.my.secrets.getPath "api-key-cloudflare-dns" "api-token";
        };
      }
    ];
  };
};
```

Configuration options are self-documented in `modules/system/router/core.nix` via `mkOption`, including defaults for interfaces, ULA prefix, exporter settings, and nginx access controls.

## Module: Backups

- Path: `modules/system/backups.nix`
- Consumers: e.g. `machines/makemake/configuration.nix`

### Features

- **Provider**: restic to Backblaze B2 or S3
- **Secrets**: repository URL, password, and provider creds provisioned via Clan + vars-helper
- **Bootstrap**: optional automatic bucket creation and server-side encryption (B2), optional lifecycle rules (keep prior versions)
- **Scheduling**: simple `hourly | daily | weekly`
- **Include/Exclude**: path filters per backup job
- **Restore mode**: flip a flag to run a one-shot restic restore to target path

### Example declaration (from `machines/makemake/configuration.nix`)

```nix
my.backups = {
  minne = {
    enable = true;
    path = config.my.minne.dataDir;
    frequency = "daily";
    backend = { type = "b2"; bucket = null; lifecycleKeepPriorVersionsDays = 30; };
  };

  vaultwarden = {
    enable = true;
    path = config.my.vaultwarden.backupDir;
    frequency = "daily";
    backend = { type = "b2"; bucket = null; lifecycleKeepPriorVersionsDays = 30; };
  };

  surrealdb = {
    enable = true;
    path = config.my.surrealdb.dataDir;
    frequency = "daily";
    backend = { type = "b2"; bucket = null; lifecycleKeepPriorVersionsDays = 30; };
  };
};
```

### Restore flow

To restore, switch a job into restore mode and choose a snapshot:

```nix
my.backups.minne.restore = {
  enable = true;
  snapshot = "latest"; # or a specific snapshot ID
};
```

The module sets up a `restic-restore-<name>` oneshot unit that restores into `path` using the provisioned `repo`, `password`, and `env` files.

## Secrets with vars-helper: examples (from `machines/charon/configuration.nix`)

The vars-helper augments Clan secrets with discovery, ACLs, exposing user secrets, and wrapping binaries with secret-backed environment variables.

### Discover secrets by tags

```nix
my.secrets.discover = {
  enable = true;
  dir = ../../vars/generators;
  includeTags = ["aws" "openai" "openrouter" "user"];
};
```

### Expose user secrets (root-owned -> user paths)

```nix
my.secrets.exposeUserSecrets = [
  {
    enable = true;
    secretName = "user-ssh-key";
    file = "key";
    user = config.my.mainUser.name;
    dest = "/home/${config.my.mainUser.name}/.ssh/id_ed25519";
  }
  {
    enable = true;
    secretName = "user-age-key";
    file = "key";
    user = config.my.mainUser.name;
    dest = "/home/${config.my.mainUser.name}/.config/sops/age/keys.txt";
  }
];
```

### Grant read access via ACL to root-owned secrets

```nix
my.secrets.allowReadAccess = [
  {
    readers = [config.my.mainUser.name];
    path = config.my.secrets.getPath "api-key-openai" "api_key";
  }
  {
    readers = [config.my.mainUser.name];
    path = config.my.secrets.getPath "api-key-openrouter" "api_key";
  }
  {
    readers = [config.my.mainUser.name];
    path = config.my.secrets.getPath "api-key-aws-access" "aws_access_key_id";
  }
  {
    readers = [config.my.mainUser.name];
    path = config.my.secrets.getPath "api-key-aws-secret" "aws_secret_access_key";
  }
];
```

### Wrap home binaries with secret-backed env vars

```nix
home-manager.users.${config.my.mainUser.name} = {
  my.secrets.wrappedHomeBinaries = [
    {
      name = "mods";
      title = "Mods";
      setTerminalTitle = true;
      command = "${pkgs.mods}/bin/mods";
      envVar = "OPENAI_API_KEY";
      secretPath = config.my.secrets.getPath "api-key-openai" "api_key";
      useSystemdRun = true;
    }
  ];
};
```

These abstractions let you declare who can read which secrets, where they should be materialized, and how to inject them into processes, all from Nix configuration.
