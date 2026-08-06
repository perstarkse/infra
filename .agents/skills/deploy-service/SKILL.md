---
name: deploy-service
description: Guide for deploying self-built applications (Rust/Go/Node, etc.) as systemd services on NixOS machines using Clan, Flakes, and Sops.
tags:
  - nixos
  - deployment
  - clan
  - systemd
  - secrets
---

# Deploying Self-Built Services

This guide outlines the standard practice for deploying self-built applications within our NixOS infrastructure. It is based on patterns established in modules like `nous`, `minne`, and `minne-saas`.

## Prerequisities

- The application should be a Nix Flake exposing a package (e.g., `packages.${system}.default`).
- You have access to the repository root.

## 1. Add Flake Input

First, add the application's repository to `flake.nix`.

```nix
inputs = {
  # ... existing inputs
  my-app.url = "github:org/my-app";
  my-app.inputs.nixpkgs.follows = "nixpkgs"; # Optional: reuse nixpkgs
};
```

## 2. Create the NixOS Module

Create a new file in `modules/system/<service-name>.nix`. This module bridges the flake input to a systemd service.

### Standard Module Structure

Refer to `modules/system/nous.nix` or `modules/system/minne.nix` for full examples.

```nix
{ inputs, ... }: {
  config.flake.nixosModules.my-app = { config, lib, pkgs, ... }: let
    cfg = config.my.my-app;
    # Access the package from inputs
    appPkg = inputs.my-app.packages.${pkgs.system}.default;
  in {
    options.my.my-app = {
      enable = lib.mkEnableOption "Enable My App";
      
      port = lib.mkOption {
        type = lib.types.port;
        default = 3000;
        description = "Port to listen on";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/my-app";
        description = "State directory";
      };
      
      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open firewall for the service port";
      };

      # Add other configuration options (address, logLevel, external service hosts)
    };

    config = lib.mkIf cfg.enable {
      # 1. Systemd Service
      systemd.services.my-app = {
        description = "My App Service";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];

        serviceConfig = {
          Type = "simple";
          User = "my-app";
          Group = "my-app";
          WorkingDirectory = cfg.dataDir;
          # Run the binary
          ExecStart = "${appPkg}/bin/my-app-binary";
          Restart = "always";
          RestartSec = "10";

          # Pass non-secret config via Environment
          Environment = [
            "PORT=${toString cfg.port}"
            "DATA_DIR=${cfg.dataDir}"
          ];

          # Pass secrets via EnvironmentFile (see Step 3)
          EnvironmentFile = [
            (config.my.secrets.getPath "my-app" "env")
          ];
        };
      };

      # 2. User & Group
      users.users.my-app = {
        isSystemUser = true;
        group = "my-app";
        home = cfg.dataDir;
        createHome = true;
      };
      users.groups.my-app = {};

      # 3. Persistence / Data Dir Permissions
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 my-app my-app -"
      ];

      # 4. Firewall
      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
    };
  };
}
```

## 3. Secrets Management (Clan + Sops)

Secrets are handled by generating an environment file that `systemd` loads.
We place generators in `vars/generators/` and use a robust script pattern that supports both manual input and auto-generation.

### Create Generator

Create `vars/generators/<service-name>.nix`.

```nix
{
  "my-app" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users"; # Essential for systemd services
      };
    };
    prompts = {
      env = {
        description = "My App environment variables (KEY=VALUE)";
        persist = true;
        type = "hidden"; # multiline input
      };
    };
    script = ''
      # Robust prompts handling: Check if prompts are provided
      _prompts_dir="''${prompts:-}"
      if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
         _prompts_dir=""
      fi

      if [ -n "$_prompts_dir" ] && [ -s "$_prompts_dir/env" ]; then
        # Case A: User provided input via prompt
        # Use 'cp' for multi-line env files. 
        # For single-value secrets (e.g. just a password), use: cat ... | tr -d '\n' > ...
        cp "$_prompts_dir/env" "$out/env"
      else
        # Case B: No input provided -> Auto-generate defaults
        echo "# Auto-generated secrets" > "$out/env"
        # Use coreutils (head, base64) instead of openssl if not in path
        secret=$(head -c 32 /dev/urandom | base64 -w0)
        echo "SECRET_KEY=$secret" >> "$out/env"
      fi
    '';
    meta.tags = [ "service" "my-app" ];
  };
}
```

### Generate Secrets

Run the generator. You can skip prompts to auto-generate:

```bash
clan vars generate --match my-app
```

Or provide values interactively (will use your input):
```bash
clan vars generate --match my-app --no-sandbox # sometimes needed for prompts
```

## 4. Enable on Host

Edit `machines/<host>/configuration.nix` to enable the module.

```nix
{ ... }: {
  my.my-app = {
    enable = true;
    port = 4000;
    # other overrides...
  };
}
```

## 5. Deploy

Build and deploy the configuration to the target machine.

```bash
clan machines update <host>
```

## Validation Before Deploy

```bash
nix flake check path:.
```

If the service is exposed via router/nginx or adds forwarding/DNS on `io`:

```bash
nix build path:.#checks.x86_64-linux.router-services
nix build path:.#final-checks
```

## Checklist

- [ ] Flake input added
- [ ] Module created with options for all configurable parameters
- [ ] Systemd service uses `EnvironmentFile` for secrets
- [ ] Dedicated User/Group defined
- [ ] Generator created in `vars/generators/` with robust script (input check + auto-gen)
- [ ] Generator tag added to `my.secrets.discover.includeTags` in machine config
- [ ] Secrets generated via `clan vars generate`
- [ ] Module enabled in machine configuration
- [ ] Relevant local checks passed (`path:.#...` targets above)
