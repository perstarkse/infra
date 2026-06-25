{
  config.flake.nixosModules.vpn-browser = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.vpn-browser;

    inherit (config.my.secrets) getPath;
    wgSecretName = "vpn-browser-${cfg.wrapperName}";
    wgConfigPath = getPath wgSecretName "wg.conf";
    vethHost = "veth-${cfg.namespaceName}-host";
    vethNs = "veth-${cfg.namespaceName}";
    subnet = "10.200.200.0/24";
    hostAddress = "10.200.200.1";
    nsAddress = "10.200.200.2";

    balancedQutebrowserConfig = pkgs.writeText "vpn-browser-balanced-config.py" ''
      # Managed by Nix (my.vpn-browser). Loaded via -C on every launch.
      config.load_autoconfig(False)

      # canvas_reading must stay enabled — disabling it maps to Chromium's
      # --disable-reading-from-canvas and breaks YouTube/video players.
      c.content.headers.do_not_track = None
      c.content.webrtc_ip_handling_policy = 'disable-non-proxied-udp'
      c.content.blocking.enabled = True
      c.content.cookies.accept = 'no-3rdparty'
      c.content.geolocation = False
      c.content.desktop_capture = False
      c.content.dns_prefetch = False
    '';

    strictQutebrowserConfig = pkgs.writeText "vpn-browser-strict-config.py" ''
      # Managed by Nix (my.vpn-browser). Loaded via -C on every launch.
      config.load_autoconfig(False)

      c.content.webgl = False
      c.content.canvas_reading = False
      c.content.headers.do_not_track = None
      c.content.webrtc_ip_handling_policy = 'disable-non-proxied-udp'
      c.content.blocking.enabled = True
      c.content.cookies.accept = 'no-3rdparty'
      c.content.geolocation = False
      c.content.media.audio_capture = False
      c.content.media.video_capture = False
      c.content.media.audio_video_capture = False
      c.content.desktop_capture = False
      c.content.dns_prefetch = False
      c.qt.args = [
          'disable-webgl',
          'disable-webgl2',
          'disable-3d-apis',
      ]
    '';

    privacyConfigs = {
      balanced = balancedQutebrowserConfig;
      strict = strictQutebrowserConfig;
    };
  in {
    options.my.vpn-browser = {
      enable = lib.mkEnableOption "VPN-isolated browser";

      namespaceName = lib.mkOption {
        type = lib.types.str;
        default = "pvpn";
        description = "VPN network namespace name";
      };

      wrapperName = lib.mkOption {
        type = lib.types.str;
        default = "p-qute";
        description = "Name of the wrapper binary and desktop entry";
      };

      desktopName = lib.mkOption {
        type = lib.types.str;
        default = "VPN Qutebrowser";
        description = "Display name in desktop menu";
      };

      browserPackage = lib.mkOption {
        type = lib.types.package;
        default = pkgs.qutebrowser;
        description = "Browser package to run inside the VPN namespace";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/home/${config.my.mainUser.name}/.local/share/${cfg.wrapperName}";
        defaultText = lib.literalExpression ''"/home/<user>/.local/share/<wrapperName>"'';
        description = "Data directory for the VPN browser instance (separate from default profile)";
      };

      timezone = lib.mkOption {
        type = lib.types.str;
        default = "UTC";
        description = "TZ for the VPN browser process (reduces timezone fingerprinting).";
      };

      privacyProfile = lib.mkOption {
        type = lib.types.enum ["none" "balanced" "strict"];
        default = "balanced";
        description = ''
          Qutebrowser fingerprint-hardening preset for the VPN profile.

          balanced (default): UTC timezone, no DNT header, WebRTC lockdown, and
          built-in adblock. Canvas reading and WebGL stay enabled so video sites
          like YouTube keep working.

          strict: balanced plus canvas read blocking and WebGL disabled. Breaks
          video sites; use only when you need maximum GPU/canvas protection.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

      # Oneshot service that creates a netns with a veth pair, runs wg-quick inside,
      # and ensures the tunnel is up before the browser tries to use it.
      systemd.services."vpn-browser-${cfg.namespaceName}" = {
        description = "WireGuard tunnel for ${cfg.desktopName}";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        wantedBy = ["multi-user.target"];
        path = [pkgs.wireguard-tools pkgs.iproute2 pkgs.iptables];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          set -euo pipefail

          NS="${cfg.namespaceName}"
          WG_CONF="${wgConfigPath}"
          VETH_HOST="${vethHost}"
          VETH_NS="${vethNs}"
          HOST_ADDR="${hostAddress}"
          NS_ADDR="${nsAddress}"
          SUBNET="${subnet}"

          # Clean up any leftover state from a previous failed run
          ip netns del "$NS" 2>/dev/null || true
          ip link delete "$VETH_HOST" 2>/dev/null || true
          iptables -t nat -D POSTROUTING -s "$SUBNET" -j MASQUERADE 2>/dev/null || true
          iptables -D FORWARD -i "$VETH_HOST" -j ACCEPT 2>/dev/null || true
          iptables -D FORWARD -o "$VETH_HOST" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

          # Create namespace
          ip netns add "$NS"

          # Create veth pair (simpler than a bridge; just for bootstrap connectivity)
          ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
          ip link set "$VETH_NS" netns "$NS"

          # Configure host side
          ip addr add "$HOST_ADDR/24" dev "$VETH_HOST"
          ip link set "$VETH_HOST" up

          # Configure namespace side
          ip netns exec "$NS" ip addr add "$NS_ADDR/24" dev "$VETH_NS"
          ip netns exec "$NS" ip link set "$VETH_NS" up
          ip netns exec "$NS" ip link set lo up

          # NAT + forwarding rules so the namespace can reach the internet
          # (needed for the initial WG handshake to the endpoint)
          iptables -t nat -I POSTROUTING -s "$SUBNET" -j MASQUERADE
          iptables -I FORWARD -i "$VETH_HOST" -j ACCEPT
          iptables -I FORWARD -o "$VETH_HOST" -m state --state ESTABLISHED,RELATED -j ACCEPT

          # Default route via host
          ip netns exec "$NS" ip route add default via "$HOST_ADDR"

          # Give the namespace its own resolv.conf so wg-quick's DNS changes
          # don't leak onto the host
          mkdir -p "/etc/netns/$NS"
          if [ ! -f "/etc/netns/$NS/resolv.conf" ]; then
            cp /etc/resolv.conf "/etc/netns/$NS/resolv.conf"
          fi

          # Bring up WireGuard inside the namespace.
          # wg-quick's Table=auto handles the endpoint split:
          #   - endpoint IP stays routed via veth → host → internet (for the handshake)
          #   - everything else goes through wg0
          ip netns exec "$NS" wg-quick up "$WG_CONF"
        '';

        serviceConfig.ExecStop = [
          "${pkgs.writeShellScript "vpn-browser-${cfg.namespaceName}-down" ''
            set -euo pipefail

            NS="${cfg.namespaceName}"
            WG_CONF="${wgConfigPath}"
            VETH_HOST="${vethHost}"
            SUBNET="${subnet}"

            # Bring down WireGuard inside the namespace (restores original resolv.conf)
            ip netns exec "$NS" wg-quick down "$WG_CONF" || true

            # Delete the namespace — removes wg0, veth-ns side, all routes
            ip netns del "$NS" || true

            # Clean up host-side iptables rules
            iptables -t nat -D POSTROUTING -s "$SUBNET" -j MASQUERADE 2>/dev/null || true
            iptables -D FORWARD -i "$VETH_HOST" -j ACCEPT 2>/dev/null || true
            iptables -D FORWARD -o "$VETH_HOST" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

            # Clean up host-side veth
            ip link delete "$VETH_HOST" 2>/dev/null || true
          ''}"
        ];
      };

      # Allow the main user to enter the VPN namespace without a password
      security.sudo.extraRules = [
        {
          users = [config.my.mainUser.name];
          commands = [
            {
              command = "${pkgs.iproute2}/bin/ip netns exec ${cfg.namespaceName} *";
              options = ["NOPASSWD"];
            }
          ];
        }
      ];

      # Wrapper script: elevate → enter VPN netns → drop back to user → run browser
      environment.systemPackages = [
        (pkgs.writeShellScriptBin cfg.wrapperName ''
          set -euo pipefail
          basedir="${cfg.dataDir}"
          mkdir -p "$basedir"

          # Capture user-session env vars before sudo strips them.
          # PipeWire lives at $XDG_RUNTIME_DIR/pipewire-0; without these,
          # QtWebEngine/Chromium can't find the audio server → no sound.
          runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          dbus_addr="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=$runtime_dir/bus}"

          qb_args=(--basedir "$basedir")
          ${lib.optionalString (cfg.privacyProfile == "balanced") ''
            qb_args+=(
              -C ${privacyConfigs.balanced}
              -s content.headers.do_not_track ""
              -s content.webrtc_ip_handling_policy disable-non-proxied-udp
            )
          ''}
          ${lib.optionalString (cfg.privacyProfile == "strict") ''
            qb_args+=(
              -C ${privacyConfigs.strict}
              -s content.webgl false
              -s content.canvas_reading false
              -s content.headers.do_not_track ""
              -s content.webrtc_ip_handling_policy disable-non-proxied-udp
            )
          ''}

          exec sudo -n ${pkgs.iproute2}/bin/ip netns exec "${cfg.namespaceName}" \
            sudo -u "${config.my.mainUser.name}" \
            env TZ="${cfg.timezone}" \
              XDG_RUNTIME_DIR="$runtime_dir" \
              DBUS_SESSION_BUS_ADDRESS="$dbus_addr" \
            ${lib.getExe cfg.browserPackage} "''${qb_args[@]}" "$@"
        '')
        (pkgs.makeDesktopItem {
          name = cfg.wrapperName;
          inherit (cfg) desktopName;
          exec = "${cfg.wrapperName} %u";
          icon = "qutebrowser";
          categories = ["Network" "WebBrowser"];
          mimeTypes = [
            "x-scheme-handler/http"
            "x-scheme-handler/https"
            "text/html"
          ];
          type = "Application";
        })
      ];

      # Declare the WireGuard config as a clan secret
      my.secrets.declarations = [
        (config.my.secrets.mkMachineSecret {
          name = wgSecretName;
          runtimeInputs = [pkgs.wireguard-tools];
          files = {
            "wg.conf" = {mode = "0400";};
          };
          prompts."conf".input = {
            description = ''
              Paste your WireGuard config for the '${cfg.desktopName}' VPN browser.
              This is the full [Interface]/[Peer] config from your VPN provider.
              Must include a DNS = ... line.
            '';
            type = "hidden";
            persist = true;
          };
          script = ''
              set -euo pipefail
              umask 077
              mkdir -p "$out"

              if [ -s "$prompts/conf" ] 2>/dev/null; then
                cp "$prompts/conf" "$out/wg.conf"
              else
                privkey=$(wg genkey)
                pubkey=$(echo "$privkey" | wg pubkey)

                cat > "$out/wg.conf" << EOF
            # Auto-generated placeholder for '${cfg.desktopName}'
            # Replace this with your actual VPN config using:
            #   clan vars generate --match ${wgSecretName} --no-sandbox

            [Interface]
            PrivateKey = $privkey
            # Your public key (share with VPN provider): $pubkey
            # Address = 10.x.x.x/32
            # DNS = 10.x.x.x

            [Peer]
            # PublicKey = <server public key>
            # Endpoint = <server>:51820
            # AllowedIPs = 0.0.0.0/0, ::/0
            # PersistentKeepalive = 25
            EOF
              fi

              chmod 0400 "$out/wg.conf"
          '';
          meta.tags = ["vpn-browser" cfg.wrapperName];
          meta.description = "WireGuard VPN config for ${cfg.desktopName}";
        })
      ];

      # Allow root (for the VPN namespace service) to read the secret
      my.secrets.allowReadAccess = [
        {
          readers = ["root"];
          path = wgConfigPath;
        }
      ];
    };
  };
}
