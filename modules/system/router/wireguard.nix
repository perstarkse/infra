{
  config.flake.nixosModules.router-wireguard = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.router;
    wg = cfg.wireguard or {};
    enabled = cfg.enable && (wg.enable or false);

    interfaceName = wg.interfaceName or "wg0";
    listenPort = toString (wg.listenPort or 51820);
    privateKeyCred = "wireguard-${interfaceName}-private-key";
    privateKeyPath =
      if wg.privateKeyFile != null
      then wg.privateKeyFile
      else (config.my.secrets.getPath "wireguard-server" "private-key");

    subnetBase = wg.subnet or "10.6.0";
    cidrPrefix = toString (wg.cidrPrefix or 24);
    routerAddressWithPrefix = "${subnetBase}.1/${cidrPrefix}";

    generatedPeers = lib.filter (p: (p.autoGenerate or false)) (wg.peers or []);
    staticPeers = lib.filter (p: !(p.autoGenerate or false)) (wg.peers or []);

    peerAddress = peer: "${subnetBase}.${toString peer.ip}/32";
    peerPublicKeyCred = peer: "wireguard-${interfaceName}-peer-${peer.name}-public-key";
    peerPublicKeyPath = peer: config.my.secrets.getPath "wireguard-peer-${peer.name}" "public-key";
    mkPeer = peer:
      {
        PublicKey =
          if peer.autoGenerate
          then "@${peerPublicKeyCred peer}"
          else peer.publicKey;
        AllowedIPs = [(peerAddress peer)];
      }
      // (lib.optionalAttrs (peer.persistentKeepalive != null) {
        PersistentKeepalive = peer.persistentKeepalive;
      });
    networkdCredentials =
      lib.optionals (wg.privateKeyFile == null) [
        "${privateKeyCred}:${privateKeyPath}"
      ]
      ++ map (peer: "${peerPublicKeyCred peer}:${peerPublicKeyPath peer}") generatedPeers;

    routerIp =
      if config ? routerHelpers
      then config.routerHelpers.routerIp
      else throw "routerHelpers not defined — is the router module loaded?";

    mkPeerSecret = peer: (config.my.secrets.mkMachineSecret {
      name = "wireguard-peer-${peer.name}";
      share = true;
      runtimeInputs = [pkgs.wireguard-tools pkgs.qrencode];
      files = {
        "private-key" = {mode = "0400";};
        "public-key" = {mode = "0444";};
        "client.conf" = {mode = "0400";};
        "client.png" = {mode = "0400";};
        "client.qr" = {mode = "0400";};
      };
      prompts = {
        "server-public-key" = {
          description = "WireGuard server public key (fallback if not readable from existing secret)";
          persist = true;
          type = "hidden";
        };
        endpoint = {
          description = "WireGuard endpoint (host:port) for ${peer.name}";
          persist = true;
          type = "hidden";
        };
      };

      script = let
        endpointDefault =
          if peer.endpoint != null
          then peer.endpoint
          else if wg.defaultEndpoint != null
          then wg.defaultEndpoint
          else "";
        dnsDefault =
          if peer.dns != null
          then peer.dns
          else if wg.defaultDns != null
          then wg.defaultDns
          else routerIp;
        clientAllowed =
          lib.concatStringsSep "," (peer.clientAllowedIPs or ["0.0.0.0/0"]);
        peerAddr = peerAddress peer;
        serverPublicKeyPath = config.my.secrets.getPath "wireguard-server" "public-key";
      in ''
                  set -euo pipefail
                  umask 077
                  mkdir -p "$out"

                  wg genkey > "$out/private-key"
                  chmod 0400 "$out/private-key"
                  wg pubkey < "$out/private-key" > "$out/public-key"
                  chmod 0444 "$out/public-key"

                  server_pubkey="''${WIREGUARD_SERVER_PUBKEY:-}"
                  # Try persisted prompt, generated server secret paths, and common clan temp mounts
                  for candidate in \
                    "$prompts/server-public-key" \
                    "${serverPublicKeyPath}" \
                    /run/secrets/vars/wireguard-server/public-key \
                    /tmp/vars-*/wireguard-server/public-key
                  do
                    if [ -z "$server_pubkey" ] && [ -r "$candidate" ]; then
                      server_pubkey=$(cat "$candidate")
                    fi
                  done
                  server_pubkey="$(printf '%s' "$server_pubkey" | tr -d '\n')"
                  if [ -z "$server_pubkey" ]; then
                    echo "Missing server public key. Provide WIREGUARD_SERVER_PUBKEY, a prompt value, or ensure wireguard-server/public-key is readable." >&2
                    exit 1
                  fi

                  endpoint="''${WIREGUARD_ENDPOINT:-${endpointDefault}}"
                  if [ -z "$endpoint" ] && [ -s "$prompts/endpoint" ]; then
                    endpoint=$(cat "$prompts/endpoint")
                  fi
                  if [ -z "$endpoint" ]; then
                    echo "Missing endpoint for peer ${peer.name}. Set wireguard.defaultEndpoint, peer.endpoint, prompt, or WIREGUARD_ENDPOINT." >&2
                    exit 1
                  fi

                  address="''${WIREGUARD_ADDRESS:-${peerAddr}}"
                  dns="''${WIREGUARD_DNS:-${dnsDefault}}"
                  keepalive="''${WIREGUARD_PERSISTENT_KEEPALIVE:-${toString (peer.persistentKeepalive or 25)}}"

                  cat > "$out/client.conf" <<EOF
        [Interface]
        Address = ''${address}
        PrivateKey = $(cat "$out/private-key")
        DNS = ''${dns}

        [Peer]
        PublicKey = ''${server_pubkey}
        AllowedIPs = ${clientAllowed}
        Endpoint = ''${endpoint}
        PersistentKeepalive = ''${keepalive}
        EOF

                  qrencode -t ansiutf8 < "$out/client.conf" > "$out/client.qr"
                  qrencode -t png -o "$out/client.png" < "$out/client.conf"
      '';
      meta.tags = ["wireguard" "router"];
      meta.description = "Peer ${peer.name} WireGuard bundle";
    });
  in {
    config = lib.mkIf enabled {
      assertions =
        map (peer: {
          assertion = peer.publicKey != null;
          message = "my.router.wireguard peer '${peer.name}' requires publicKey when autoGenerate = false";
        })
        staticPeers;

      my.secrets.declarations =
        [
          (config.my.secrets.mkMachineSecret {
            name = "wireguard-server";
            runtimeInputs = [pkgs.wireguard-tools];
            files = {
              # Production passes the key via systemd-networkd LoadCredential (root
              # reads /run/secrets); group ownership is a fallback for direct reads.
              "private-key" = {
                mode = "0440";
                owner = "root";
                group = "systemd-network";
              };
              "public-key" = {
                mode = "0400";
                secret = false;
              };
            };
            prompts."private-key" = {
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
        ]
        ++ map mkPeerSecret generatedPeers;

      sops.secrets =
        {
          "vars/wireguard-server/private-key".restartUnits = lib.mkAfter [
            "systemd-networkd.service"
          ];
        }
        // lib.listToAttrs (map (peer: {
            name = "vars/wireguard-peer-${peer.name}/public-key";
            value.restartUnits = lib.mkAfter ["systemd-networkd.service"];
          })
          generatedPeers);

      systemd = {
        network.netdevs."30-${interfaceName}" = {
          netdevConfig = {
            Kind = "wireguard";
            Name = interfaceName;
          };
          wireguardConfig =
            {
              ListenPort = listenPort;
              RouteTable = "main";
            }
            // lib.optionalAttrs (wg.privateKeyFile != null) {PrivateKeyFile = privateKeyPath;}
            // lib.optionalAttrs (wg.privateKeyFile == null) {PrivateKey = "@${privateKeyCred}";};
          wireguardPeers = map mkPeer (wg.peers or []);
        };

        network.networks."30-${interfaceName}" = {
          matchConfig.Name = interfaceName;
          address = [routerAddressWithPrefix];
          networkConfig = {
            ConfigureWithoutCarrier = true;
            IPv4Forwarding = true;
            IPv6Forwarding = false;
          };
          linkConfig.MTUBytes = "1420";
        };

        services = lib.optionalAttrs (networkdCredentials != []) {
          systemd-networkd.serviceConfig.LoadCredential = networkdCredentials;
        };
      };
    };
  };
}
