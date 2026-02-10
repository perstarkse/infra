{
  config.flake.nixosModules.wireguard-tunnels = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.wireguardTunnels;

    enabledTunnels = lib.filterAttrs (_: t: t.enable) cfg.tunnels;

    # Create a systemd service for each tunnel using wg-quick
    mkTunnelService = name: tunnel: {
      description = "WireGuard tunnel: ${name}";
      after = ["network-online.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.wireguard-tools}/bin/wg-quick up ${config.my.secrets.getPath "wireguard-tunnels-${name}" "wg.conf"}";
        ExecStop = "${pkgs.wireguard-tools}/bin/wg-quick down ${config.my.secrets.getPath "wireguard-tunnels-${name}" "wg.conf"}";
      };

      # Only auto-start if activationPolicy is "up"
      wantedBy = lib.optionals (tunnel.activationPolicy == "up") ["multi-user.target"];
    };

    # Generate the secret declaration for each tunnel
    mkTunnelSecret = name: _tunnel:
      config.my.secrets.mkMachineSecret {
        name = "wireguard-tunnels-${name}";
        runtimeInputs = [pkgs.wireguard-tools];
        files = {
          "wg.conf" = {
            mode = "0400";
          };
        };
        prompts."conf".input = {
          description = ''
            Paste your WireGuard config for tunnel '${name}'.
            This is the full [Interface]/[Peer] config from your VPN provider.
          '';
          type = "hidden";
          persist = true;
        };
        script = ''
          set -euo pipefail
          umask 077
          mkdir -p "$out"

          if [ -s "$prompts/conf" ] 2>/dev/null; then
            # User provided a config - use it directly
            cp "$prompts/conf" "$out/wg.conf"
          else
            # Generate a placeholder config with new keypair
            privkey=$(wg genkey)
            pubkey=$(echo "$privkey" | wg pubkey)

            cat > "$out/wg.conf" <<EOF
          # Auto-generated placeholder for tunnel '${name}'
          # Replace this with your actual VPN config using:
          #   clan vars generate --match wireguard-tunnels-${name} --no-sandbox

          [Interface]
          PrivateKey = $privkey
          # Your public key (share with VPN provider): $pubkey
          # Address = 10.x.x.x/32

          [Peer]
          # PublicKey = <server public key>
          # Endpoint = <server>:51820
          # AllowedIPs = 0.0.0.0/0, ::/0
          # PersistentKeepalive = 25
          EOF
          fi

          chmod 0400 "$out/wg.conf"
        '';
        meta.tags = ["wireguard-tunnels" name];
        meta.description = "WireGuard tunnel config for ${name}";
      };
  in {
    options.my.wireguardTunnels = {
      enable = lib.mkEnableOption "WireGuard VPN tunnels";

      tunnels = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to enable this tunnel";
            };

            activationPolicy = lib.mkOption {
              type = lib.types.enum ["up" "manual"];
              default = "manual";
              description = ''
                Controls when the tunnel is brought up:
                - "up": Start automatically at boot
                - "manual": Start manually with: systemctl start wg-tunnel-<name>
              '';
            };
          };
        });
        default = {};
        description = ''
          WireGuard tunnels keyed by human-readable names.
          The actual VPN configuration (keys, endpoints, IPs) is stored
          entirely in secrets at wireguard-tunnels-<name>/wg.conf.
          Nothing about your VPN is visible in the Nix store.
        '';
        example = lib.literalExpression ''
          {
            genome-worktree-zenith = {
              activationPolicy = "manual";  # systemctl start wg-tunnel-genome-worktree-zenith
            };
            nebula-crystal-forge = {
              activationPolicy = "up";  # Auto-start at boot
            };
          }
        '';
      };
    };

    config = lib.mkIf (cfg.enable && enabledTunnels != {}) {
      # Use systemd-resolved for DNS - it provides resolvconf compatibility
      # wg-quick will use resolvectl to set per-interface DNS when tunnel is up
      # Falls back to your normal DNS (unbound) when tunnel is down
      services.resolved = {
        enable = true;
        # Disable DNSSEC - let your upstream resolver (unbound) handle validation
        # This avoids "no-signature" failures for internal domains
        dnssec = "false";
      };

      # Ensure wg-quick's dependencies are available
      environment.systemPackages = [pkgs.wireguard-tools];

      # wg-quick needs iproute2 and iptables in PATH
      systemd.services =
        lib.mapAttrs' (
          name: tunnel:
            lib.nameValuePair "wg-tunnel-${name}" (mkTunnelService name tunnel)
        )
        enabledTunnels;

      # Grant root access to the secrets (wg-quick runs as root)
      my.secrets.allowReadAccess =
        lib.mapAttrsToList (name: _: {
          readers = ["root"];
          path = config.my.secrets.getPath "wireguard-tunnels-${name}" "wg.conf";
        })
        enabledTunnels;

      # Generate secrets for all enabled tunnels
      my.secrets.declarations = lib.mapAttrsToList mkTunnelSecret enabledTunnels;
    };
  };
}
