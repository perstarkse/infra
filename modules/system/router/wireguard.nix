{ lib, config, pkgs, ... }:
{
  config.flake.nixosModules.router-wireguard = { lib, config, pkgs, ... }:
  let
    cfg = config.my.router;
    wg = cfg.wireguard or {};
    helpers = config.routerHelpers or {};
    wan = helpers.wanInterface or cfg.wan.interface;
    enabled = cfg.enable && (wg.enable or false);

    interfaceName = wg.interfaceName or "wg0";
    listenPort = toString (wg.listenPort or 51820);

    subnetBase = wg.subnet or "10.6.0";
    cidrPrefix = toString (wg.cidrPrefix or 24);
    routerAddressWithPrefix = "${subnetBase}.1/${cidrPrefix}";
    lanCidr = helpers.lanCidr or "${cfg.lan.subnet}.0/24";

    mkPeer = peer: {
      PublicKey = peer.publicKey;
      AllowedIPs = [ "${subnetBase}.${toString peer.ip}/32" ];
    } // (lib.optionalAttrs (peer.persistentKeepalive != null) {
      PersistentKeepalive = peer.persistentKeepalive;
    });
  in
  {
    config = lib.mkIf enabled {
        my.secrets.declarations = [
  (config.my.secrets.mkMachineSecret {
    name = "wireguard-server";
    runtimeInputs = [ pkgs.wireguard-tools ];
    files = {
      "private-key" = {
        mode = "0400";
        additionalReaders = [ "systemd-network" ];
      };
      "public-key" = {
        mode = "0400";
        secret = false;
      };
    };
    prompts."private-key".input = {
      description = "WireGuard private key";
      type = "hidden";
      persist = true;
    };
    script = ''
      set -euo pipefail
      umask 077
      mkdir -p "$out"

      # If provided via prompt, write the private key; otherwise generate one
      if [ -s "$prompts/private-key" ] 2>/dev/null; then
        install -m 0400 -D "$prompts/private-key" "$out/private-key"
      else
        wg genkey > "$out/private-key"
        chmod 0400 "$out/private-key"
      fi

      # Derive public key from private key in output
      wg pubkey < "$out/private-key" > "$out/public-key"
      chmod 0644 "$out/public-key"
    '';
  })
];

      systemd.network.netdevs.
        "30-${interfaceName}" = {
        netdevConfig = {
          Kind = "wireguard";
          Name = interfaceName;
        };
        wireguardConfig = {
          PrivateKeyFile = (if wg.privateKeyFile != null then wg.privateKeyFile else (config.my.secrets.getPath "wireguard-server" "private-key"));
          ListenPort = listenPort;
          RouteTable = "main";
        };
        wireguardPeers = map mkPeer (wg.peers or []);
      };

      systemd.network.networks.
        "30-${interfaceName}" = {
        matchConfig.Name = interfaceName;
        address = [ routerAddressWithPrefix ];
        networkConfig = {
          ConfigureWithoutCarrier = true;
          IPv4Forwarding = true;
          IPv6Forwarding = false;
        };
        linkConfig.MTUBytes = "1420";
      };
    };
  };
} 