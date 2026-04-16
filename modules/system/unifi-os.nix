_: {
  config.flake.nixosModules.unifi-os = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit
      (lib)
      mkEnableOption
      mkIf
      mkOption
      types
      ;

    cfg = config.services.unifi-os-server;
    stateDir = "/var/lib/unifi-os";
    installerStateDir = "/var/lib/uosserver";
    routerHelpers = config.routerHelpers or {};
    macvlanCfg = cfg.network.macvlan;
    hostAccessEnabled = macvlanCfg.hostAccess.enable;
    useInstallerRuntime = cfg.runtime == "installer";
    parentNetworkUnitName =
      if macvlanCfg.parentInterface == (routerHelpers.lanInterface or null)
      then "35-${macvlanCfg.parentInterface}"
      else "10-${macvlanCfg.parentInterface}";

    defaultPackage = pkgs.callPackage ../../pkgs/unifi-os {
      sha256 = "sha256-IPoWR5GTiy7J1WgMEYdTxGo26qM2nO+U1c742pRo354=";
    };

    ucoreDebug = pkgs.writeText "unifi-core-debug.conf" ''
      [Service]
      StandardOutput=append:/data/unifi-core/logs/stdout.log
      StandardError=append:/data/unifi-core/logs/stderr.log
    '';

    ucorePreStartFix = pkgs.writeText "unifi-core-prestart-fix.conf" ''
      [Service]
      ExecStartPre=-/bin/mkdir -p /data/unifi-core/config/http
      ExecStartPre=-/bin/mkdir -p /var/log/nginx
    '';

    mongoPreStartFix = pkgs.writeText "mongodb-prestart-fix.conf" ''
      [Service]
      ExecStartPre=+/bin/bash -c "mkdir -p /var/log/mongodb && chown mongodb:mongodb /var/log/mongodb /var/lib/mongodb"
    '';

    dbusStartFix = pkgs.writeText "dbus-start-fix.conf" ''
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE busconfig SYSTEM "busconfig.dtd">
      <busconfig>
          <apparmor mode="disabled"/>
      </busconfig>
    '';

    installerPodmanWrapper = pkgs.writeShellScript "uosserver-podman-rootful" ''
      set -euo pipefail

      realPodman=${lib.escapeShellArg "${config.virtualisation.podman.package}/bin/.podman-wrapped"}
      networkName=${lib.escapeShellArg macvlanCfg.networkName}
      containerIp=${lib.escapeShellArg macvlanCfg.ip}
      hostAccessEnabled=${if hostAccessEnabled then "1" else "0"}
      hostAccessIp=${lib.escapeShellArg (macvlanCfg.hostAccess.hostAddress or "")}

      cmd="''${1-}"
      if [[ "$cmd" == "run" || "$cmd" == "create" ]]; then
        shift

        rewritten=("$cmd" "--privileged" "--network=$networkName" "--ip=$containerIp")
        if [[ "$hostAccessEnabled" == "1" ]]; then
          rewritten+=("--add-host=host.docker.internal:$hostAccessIp" "--add-host=host.containers.internal:$hostAccessIp")
        fi

        while ((''${#} > 0)); do
          case "$1" in
            --network)
              shift 2
              ;;
            --network=*)
              shift
              ;;
            --ip)
              shift 2
              ;;
            --ip=*)
              shift
              ;;
            --dns)
              if ((''${#} > 1)) && [[ "$2" == "203.0.113.113" ]]; then
                shift 2
              else
                rewritten+=("$1" "$2")
                shift 2
              fi
              ;;
            --dns=203.0.113.113)
              shift
              ;;
            --add-host)
              if ((''${#} > 1)) && [[ "$2" =~ ^host\.(docker|containers)\.internal:(10\.0\.2\.2|203\.0\.113\.113)$ ]]; then
                shift 2
              else
                rewritten+=("$1" "$2")
                shift 2
              fi
              ;;
            --add-host=host.docker.internal:10.0.2.2|--add-host=host.containers.internal:10.0.2.2|--add-host=host.docker.internal:203.0.113.113|--add-host=host.containers.internal:203.0.113.113)
              shift
              ;;
            --cap-add=NET_RAW|--cap-add=NET_ADMIN)
              shift
              ;;
            --cap-add)
              if ((''${#} > 1)) && [[ "$2" =~ ^NET_(RAW|ADMIN)$ ]]; then
                shift 2
              else
                rewritten+=("$1" "$2")
                shift 2
              fi
              ;;
            *)
              rewritten+=("$1")
              shift
              ;;
          esac
        done

        exec env \
          -u XDG_CONFIG_HOME \
          -u XDG_RUNTIME_DIR \
          -u CONTAINERS_CONF \
          -u DBUS_SESSION_BUS_ADDRESS \
          HOME=/root \
          USER=root \
          LOGNAME=root \
          "$realPodman" "''${rewritten[@]}"
      fi

      exec env \
        -u XDG_CONFIG_HOME \
        -u XDG_RUNTIME_DIR \
        -u CONTAINERS_CONF \
        -u DBUS_SESSION_BUS_ADDRESS \
        HOME=/root \
        USER=root \
        LOGNAME=root \
        "$realPodman" "$@"
    '';

    installerSuWrapper = pkgs.writeShellScript "uosserver-su-rootful" ''
      set -euo pipefail

      orig=("$@")
      cmd=""

      while ((''${#} > 0)); do
        case "$1" in
          -c)
            cmd="$2"
            shift 2
            ;;
          -s|-l|-m|-p|-P|--login|--preserve-environment)
            shift
            if ((''${#} > 0)) && [[ "$1" != -* ]]; then
              shift
            fi
            ;;
          --)
            shift
            break
            ;;
          *)
            shift
            ;;
        esac
      done

      if [[ -n "$cmd" ]]; then
        exec env \
          -u XDG_CONFIG_HOME \
          -u XDG_RUNTIME_DIR \
          -u CONTAINERS_CONF \
          -u DBUS_SESSION_BUS_ADDRESS \
          HOME=/root \
          USER=root \
          LOGNAME=root \
          ${pkgs.runtimeShell} -lc "$cmd"
      fi

      exec ${config.security.wrapperDir}/su "''${orig[@]}"
    '';
  in {
    options.services.unifi-os-server = {
      enable = mkEnableOption "UniFi OS Server container (podman)";

      package = mkOption {
        type = types.package;
        default = defaultPackage;
        defaultText = lib.literalExpression "pkgs.callPackage ../../pkgs/unifi-os { sha256 = \"…\"; }";
        description = ''
          Package containing the extracted UniFi OS Server OCI archive at
          `image.tar`.
        '';
      };

      imageTag = mkOption {
        type = types.str;
        default = "uosserver:0.0.54";
        description = ''
          Exact image name:tag embedded in `image.tar`.
          Must match the repository:tag inside the archive.
        '';
        example = "uosserver:0.0.54";
      };

      runtime = mkOption {
        type = types.enum ["container" "installer"];
        default = "container";
        description = ''
          Runtime implementation to use. `container` keeps the custom Podman
          wrapper. `installer` uses the host-side runtime binaries shipped in the
          official UniFi OS installer.
        '';
      };

      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether or not to open the minimum required ports on the firewall.

          This is necessary to allow firmware upgrades and device discovery to
          work. For remote login, you should additionally open (or forward) port
          8443.
        '';
      };

      environment = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Additional environment variables for the container.";
      };

      lanAddress = mkOption {
        type = types.str;
        default = config.my.listenNetworkAddress;
        defaultText = lib.literalExpression "config.my.listenNetworkAddress";
        description = ''
          LAN-reachable address advertised to UniFi devices for discovery and
          adoption.
        '';
      };

      network = {
        macvlan = {
          networkName = mkOption {
            type = types.str;
            default = "unifi-os-lan";
            description = "Podman network name used for the UniFi macvlan network.";
          };

          parentInterface = mkOption {
            type = types.nullOr types.str;
            default =
              if routerHelpers ? lanInterface
              then routerHelpers.lanInterface
              else routerHelpers.lanBridge or null;
            defaultText = lib.literalExpression "config.routerHelpers.lanInterface or config.routerHelpers.lanBridge or null";
            description = ''
              Parent interface or bridge for the macvlan network.
            '';
          };

          subnet = mkOption {
            type = types.nullOr types.str;
            default = routerHelpers.lanCidr or null;
            defaultText = lib.literalExpression "config.routerHelpers.lanCidr or null";
            description = "IPv4 subnet assigned to the macvlan network.";
          };

          gateway = mkOption {
            type = types.nullOr types.str;
            default = routerHelpers.routerIp or null;
            defaultText = lib.literalExpression "config.routerHelpers.routerIp or null";
            description = "IPv4 gateway assigned to the macvlan network.";
          };

          ip = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "10.0.0.21";
            description = ''
              Static IPv4 address assigned to the UniFi container on the LAN.
            '';
          };

          hostAccess = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Create a host-side macvlan shim so the host can reach the UniFi
                container IP directly.
              '';
            };

            interfaceName = mkOption {
              type = types.str;
              default = "unifi-os-host";
              description = "Host-side macvlan interface name used for host access.";
            };

            hostAddress = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "10.0.0.22";
              description = ''
                /32 address assigned to the host-side macvlan shim interface.
              '';
            };
          };
        };
      };

      extraVolumes = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["/etc/ssl/certs:/etc/rabbitmq/ssl:ro"];
        description = "Additional bind mounts beyond the defaults.";
      };

      extraOptions = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Extra arguments passed to podman.";
      };
    };

    config = mkIf cfg.enable {
      assertions = [
        {
          assertion = macvlanCfg.parentInterface != null;
          message = "services.unifi-os-server.network.macvlan.parentInterface must be set";
        }
        {
          assertion = macvlanCfg.subnet != null;
          message = "services.unifi-os-server.network.macvlan.subnet must be set";
        }
        {
          assertion = macvlanCfg.gateway != null;
          message = "services.unifi-os-server.network.macvlan.gateway must be set";
        }
        {
          assertion = macvlanCfg.ip != null;
          message = "services.unifi-os-server.network.macvlan.ip must be set";
        }
        {
          assertion = !(macvlanCfg.hostAccess.enable && macvlanCfg.hostAccess.hostAddress == null);
          message = "services.unifi-os-server.network.macvlan.hostAccess.hostAddress must be set when hostAccess is enabled";
        }
        {
          assertion = !hostAccessEnabled || builtins.pathExists "${cfg.package}/discovery";
          message = "services.unifi-os-server requires a packaged discovery helper when hostAccess is enabled";
        }
        {
          assertion = !useInstallerRuntime || builtins.pathExists "${cfg.package}/uosserver-service";
          message = "services.unifi-os-server runtime=installer requires uosserver-service in the package";
        }
        {
          assertion = !useInstallerRuntime || builtins.pathExists "${cfg.package}/uosserver";
          message = "services.unifi-os-server runtime=installer requires uosserver in the package";
        }
      ];

      virtualisation.podman.enable = true;
      virtualisation.oci-containers.backend = "podman";

      systemd.network = mkIf hostAccessEnabled {
        netdevs."40-${macvlanCfg.hostAccess.interfaceName}" = {
          netdevConfig = {
            Name = macvlanCfg.hostAccess.interfaceName;
            Kind = "macvlan";
          };
          macvlanConfig.Mode = "bridge";
        };

        networks = {
          # Reuse the parent interface's primary network unit name so the macvlan
          # attachment merges into the existing router config instead of losing to
          # an earlier match.
          "${parentNetworkUnitName}" = {
            matchConfig.Name = macvlanCfg.parentInterface;
            macvlan = [macvlanCfg.hostAccess.interfaceName];
          };

          "90-${macvlanCfg.hostAccess.interfaceName}" = {
            matchConfig.Name = macvlanCfg.hostAccess.interfaceName;
            address = [
              "${macvlanCfg.hostAccess.hostAddress}/32"
            ];
            routes = [
              {
                Destination = "${macvlanCfg.ip}/32";
                Scope = "link";
              }
            ];
            networkConfig.ConfigureWithoutCarrier = true;
            linkConfig.RequiredForOnline = "no";
          };
        };
      };

      networking.firewall = mkIf cfg.openFirewall {
        allowedTCPPorts = [
          443
          8080
          8443
          8843
          8880
          6789
        ];
        allowedUDPPorts = [
          3478
          10001
        ];
      };

      systemd.services.unifi-os-discovery = mkIf (hostAccessEnabled && !useInstallerRuntime) {
        description = "UniFi OS discovery helper";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          ExecStart =
            if useInstallerRuntime
            then "${installerStateDir}/bin/discovery"
            else "${cfg.package}/discovery";
          Restart = "always";
          RestartSec = 1;
          Environment = [
            "DISCOVERY_CLIENT_LOG_PATH=/var/log/unifi-os"
          ];
        };
      };

      systemd.services.unifi-os-discovery-proxy = mkIf hostAccessEnabled {
        description = "Expose UniFi discovery helper on host access IP";
        wantedBy = ["multi-user.target"];
        after =
          ["network-online.target"]
          ++ lib.optionals useInstallerRuntime ["uosserver-runtime.service"]
          ++ lib.optionals (!useInstallerRuntime) ["unifi-os-discovery.service"];
        wants =
          ["network-online.target"]
          ++ lib.optionals (!useInstallerRuntime) ["unifi-os-discovery.service"];
        serviceConfig = {
          ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:11002,bind=${macvlanCfg.hostAccess.hostAddress},fork,reuseaddr TCP:127.0.0.1:11002";
          Restart = "always";
          RestartSec = 1;
        };
      };

      systemd.services.podman-unifi-os-server = mkIf (!useInstallerRuntime) {
        restartTriggers = [cfg.package];

        requires =
          ["podman-unifi-os-server-network.service"]
          ++ lib.optionals hostAccessEnabled [
            "unifi-os-discovery.service"
            "unifi-os-discovery-proxy.service"
          ];
        after =
          ["podman-unifi-os-server-network.service"]
          ++ lib.optionals hostAccessEnabled [
            "unifi-os-discovery.service"
            "unifi-os-discovery-proxy.service"
          ];

        serviceConfig = {
          Delegate = true;
          StateDirectory = [
            "unifi-os"
            "unifi-os/persistent"
            "unifi-os/data"
            "unifi-os/srv"
            "unifi-os/unifi"
            "unifi-os/mongodb"
          ];
          LogsDirectory = "unifi-os";
        };

        preStart = lib.mkAfter ''
          ${pkgs.coreutils}/bin/mkdir -p \
            ${stateDir}/{persistent,data,srv,unifi,mongodb} \
            ${stateDir}/data/unifi-core/{config,logs} \
            /var/log/unifi-os

          ${lib.optionalString macvlanCfg.hostAccess.enable ''
            current_parent="$(${pkgs.iproute2}/bin/ip -o link show ${macvlanCfg.hostAccess.interfaceName} 2>/dev/null | ${pkgs.gnused}/bin/sed -n 's/^[0-9]*: [^@]*@\([^:]*\):.*/\1/p')"
            if [ -n "$current_parent" ] && [ "$current_parent" != ${lib.escapeShellArg macvlanCfg.parentInterface} ]; then
              ${pkgs.iproute2}/bin/ip link delete dev ${macvlanCfg.hostAccess.interfaceName}
              ${pkgs.systemd}/bin/networkctl reload
              ${pkgs.systemd}/bin/networkctl reconfigure ${macvlanCfg.parentInterface}
            fi
          ''}

          uuid_file="${stateDir}/data/uos_uuid"
          if ! grep -qP '^[0-9a-f]{8}-[0-9a-f]{4}-5' "$uuid_file" 2>/dev/null; then
            ${pkgs.util-linux}/bin/uuidgen -s -n @dns -N "$(cat /etc/machine-id)" > "$uuid_file"
          fi

          system_properties="${stateDir}/unifi/system.properties"
          ${pkgs.gnugrep}/bin/grep -q '^system_ip=' "$system_properties" 2>/dev/null \
            && ${pkgs.gnused}/bin/sed -i 's/^system_ip=.*/system_ip=${cfg.lanAddress}/' "$system_properties" \
            || printf '\nsystem_ip=%s\n' '${cfg.lanAddress}' >> "$system_properties"
        '';
      };

      systemd.services.podman-unifi-os-server-network = {
        description = "Create UniFi OS Podman macvlan network";
        wantedBy = ["multi-user.target"];
        before = ["podman-unifi-os-server.service"];
        path = [config.virtualisation.podman.package];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail

          if podman network exists ${lib.escapeShellArg macvlanCfg.networkName}; then
            current_parent="$(podman network inspect ${lib.escapeShellArg macvlanCfg.networkName} --format '{{.NetworkInterface}}')"
            if [ "$current_parent" != ${lib.escapeShellArg macvlanCfg.parentInterface} ]; then
              podman network rm ${lib.escapeShellArg macvlanCfg.networkName}
            fi
          fi

          if ! podman network exists ${lib.escapeShellArg macvlanCfg.networkName}; then
            podman network create \
              -d macvlan \
              --subnet ${lib.escapeShellArg macvlanCfg.subnet} \
              --gateway ${lib.escapeShellArg macvlanCfg.gateway} \
              -o mode=bridge \
              -o parent=${lib.escapeShellArg macvlanCfg.parentInterface} \
              ${lib.escapeShellArg macvlanCfg.networkName}
          fi
        '';
      };

      virtualisation.oci-containers.containers.unifi-os-server = mkIf (!useInstallerRuntime) {
        image = cfg.imageTag;
        imageFile = pkgs.runCommand "unifi-os-image.tar" {} ''
          ln -s ${cfg.package}/image.tar $out
        '';
        autoStart = true;
        privileged = true;

        ports = [];

        extraOptions =
          [
            "--systemd=always"
            "--network=${macvlanCfg.networkName}"
            "--ip=${macvlanCfg.ip}"
          ]
          ++ lib.optionals hostAccessEnabled [
            "--add-host=host.docker.internal:${macvlanCfg.hostAccess.hostAddress}"
            "--add-host=host.containers.internal:${macvlanCfg.hostAccess.hostAddress}"
          ]
          ++ cfg.extraOptions;

        environment =
          {
            UOS_SYSTEM_IP = cfg.lanAddress;
            UOS_SERVER_VERSION = cfg.package.version;
            FIRMWARE_PLATFORM =
              if pkgs.stdenv.hostPlatform.isAarch64
              then "linux-arm64"
              else "linux-x64";
          }
          // cfg.environment;

        volumes =
          [
            "${stateDir}/persistent:/persistent"
            "/var/log/unifi-os:/var/log"
            "${stateDir}/data:/data"
            "${stateDir}/srv:/srv"
            "${stateDir}/unifi:/var/lib/unifi"
            "${stateDir}/mongodb:/var/lib/mongodb"
            "${ucoreDebug}:/etc/systemd/system/unifi-core.service.d/debug.conf:ro"
            "${ucorePreStartFix}:/etc/systemd/system/unifi-core.service.d/prestart-fix.conf:ro"
            "${mongoPreStartFix}:/etc/systemd/system/mongodb.service.d/prestart-fix.conf:ro"
            "${dbusStartFix}:/etc/dbus-1/system.d/start-fix.conf:ro"
            "${dbusStartFix}:/etc/dbus-1/session.d/start-fix.conf:ro"
          ]
          ++ cfg.extraVolumes;
      };

      users.users.uosserver = mkIf useInstallerRuntime {
        isSystemUser = true;
        uid = 980;
        group = "uosserver";
        home = "/home/uosserver";
        createHome = true;
        shell = pkgs.runtimeShell;
        subUidRanges = [
          {
            startUid = 100000;
            count = 65536;
          }
        ];
        subGidRanges = [
          {
            startGid = 100000;
            count = 65536;
          }
        ];
      };

      users.groups.uosserver = mkIf useInstallerRuntime {
        gid = 972;
      };

      systemd.tmpfiles.rules = lib.optionals useInstallerRuntime [
        "d ${installerStateDir} 0755 root root -"
        "d ${installerStateDir}/bin 0755 root root -"
        "d ${installerStateDir}/logs 0755 root root -"
        "d /home/uosserver 0755 uosserver uosserver -"
        "d /run/user/${toString config.users.users.uosserver.uid} 0700 uosserver uosserver -"
        "L+ /usr/bin/podman - - - - ${config.virtualisation.podman.package}/bin/podman"
      ];

      systemd.services.uosserver-runtime = mkIf useInstallerRuntime {
        description = "UniFi OS installer runtime supervisor";
        wantedBy = ["multi-user.target"];
        requires = ["podman-unifi-os-server-network.service"];
        after = [
          "network-online.target"
          "podman-unifi-os-server-network.service"
          "uosserver-updater.service"
        ];
        wants = [
          "network-online.target"
          "podman-unifi-os-server-network.service"
          "uosserver-updater.service"
        ];
        path = [
          config.virtualisation.podman.package
          pkgs.shadow
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.iproute2
        ];
        preStart = ''
          uuid_file="${stateDir}/data/uos_uuid"
          if ! grep -qP '^[0-9a-f]{8}-[0-9a-f]{4}-5' "$uuid_file" 2>/dev/null; then
            ${pkgs.util-linux}/bin/uuidgen -s -n @dns -N "$(cat /etc/machine-id)" > "$uuid_file"
          fi
          uos_uuid="$(cat "$uuid_file")"

          install -d -m700 -o uosserver -g uosserver /run/user/980
          install -d -m700 -o uosserver -g uosserver /home/uosserver/.config/containers

          cat > /home/uosserver/.config/containers/containers.conf <<EOF
          [engine]
          cgroup_manager="cgroupfs"
          events_logger="file"
          EOF
          chown uosserver:uosserver /home/uosserver/.config/containers/containers.conf

          install -C -m755 ${cfg.package}/discovery ${installerStateDir}/bin/discovery
          install -C -m755 ${cfg.package}/uosserver ${installerStateDir}/uosserver
          install -C -m755 ${cfg.package}/uosserver-service ${installerStateDir}/uosserver-service
          ${lib.optionalString (builtins.pathExists "${cfg.package}/updater-service") "install -C -m755 ${cfg.package}/updater-service ${installerStateDir}/updater-service"}
          ${lib.optionalString (builtins.pathExists "${cfg.package}/pasta") "install -C -m755 ${cfg.package}/pasta ${installerStateDir}/pasta"}
          ${lib.optionalString (builtins.pathExists "${cfg.package}/purge") "install -C -m755 ${cfg.package}/purge ${installerStateDir}/purge"}
          install -C -m644 ${cfg.package}/image.tar ${installerStateDir}/image.tar

          cat > ${installerStateDir}/server.conf <<EOF
          NETWORK_MODE=pasta
          CONTAINER_IMAGE_NAME=${cfg.imageTag}
          CONTAINER_VERSION=${cfg.package.version}
          UOS_SERVER_VERSION=${cfg.package.version}
          UOS_UUID=$uos_uuid
          EOF

          mkdir -p ${stateDir}/{persistent,data,srv,unifi,mongodb} ${installerStateDir}/logs

          system_properties="${stateDir}/unifi/system.properties"
          ${pkgs.gnugrep}/bin/grep -q '^system_ip=' "$system_properties" 2>/dev/null \
            && ${pkgs.gnused}/bin/sed -i 's/^system_ip=.*/system_ip=${cfg.lanAddress}/' "$system_properties" \
            || printf '\nsystem_ip=%s\n' '${cfg.lanAddress}' >> "$system_properties"

          if ! ${config.virtualisation.podman.package}/bin/podman image exists ${lib.escapeShellArg cfg.imageTag}; then
            ${config.virtualisation.podman.package}/bin/podman load -i ${installerStateDir}/image.tar
          fi
        '';
        serviceConfig = {
          ExecStart = "${installerStateDir}/uosserver-service";
          Restart = "always";
          RestartSec = 2;
          User = "root";
          WorkingDirectory = installerStateDir;
          BindReadOnlyPaths = [
            "${installerPodmanWrapper}:/usr/bin/podman"
            "${installerSuWrapper}:/usr/bin/su"
          ];
          Environment = [
            "HOME=/home/uosserver"
            "XDG_CONFIG_HOME=/home/uosserver/.config"
            "XDG_RUNTIME_DIR=/run/user/${toString config.users.users.uosserver.uid}"
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/dev/null"
            "CONTAINERS_CONF=/home/uosserver/.config/containers/containers.conf"
            "DISCOVERY_CLIENT_LOG_PATH=/var/log/unifi-os"
          ];
        };
      };

      systemd.services.uosserver-updater = mkIf useInstallerRuntime {
        description = "UniFi OS installer updater runtime";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          ExecStart = "${installerStateDir}/updater-service";
          Restart = "always";
          RestartSec = 2;
          WorkingDirectory = installerStateDir;
        };
      };
    };
  };
}
