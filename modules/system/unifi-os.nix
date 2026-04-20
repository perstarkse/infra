_: {
  config.flake.nixosModules.unifi-os = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit
      (lib)
      literalExpression
      mkEnableOption
      mkIf
      mkOption
      optionalString
      optionals
      types
      ;

    cfg = config.services.unifi-os-server;
    inherit (cfg) package;
    routerHelpers = config.routerHelpers or {};
    networkCfg = cfg.network;
    hostAccessEnabled = networkCfg.hostAccess.enable;

    installerMetadata = package.passthru.unifiOs or {};
    packageBinaries = {
      imageTar = "${package}/${installerMetadata.binaries.imageTar or "image.tar"}";
      discovery = "${package}/${installerMetadata.binaries.discovery or "discovery"}";
      runtime = "${package}/${installerMetadata.binaries.runtime or "uosserver"}";
      runtimeService = "${package}/${installerMetadata.binaries.runtimeService or "uosserver-service"}";
      updaterService = "${package}/${installerMetadata.binaries.updaterService or "updater-service"}";
      pasta =
        if builtins.pathExists "${package}/pasta"
        then "${package}/pasta"
        else null;
      purge =
        if builtins.pathExists "${package}/purge"
        then "${package}/purge"
        else null;
    };

    vendorPorts = {
      discoveryHelper = installerMetadata.ports.discoveryHelper or 11002;
      discoveryTarget = installerMetadata.ports.discoveryTarget or 10003;
      supervisorWebsocket = installerMetadata.ports.supervisorWebsocket or 11084;
    };

    runtimeUnitName = "unifi-os-runtime";
    updaterUnitName = "uosserver-updater";
    prepareUnitName = "unifi-os-prepare";
    networkUnitName = "unifi-os-macvlan-network";
    discoveryHelperBridgeUnitName = "unifi-os-discovery-helper-bridge";
    supervisorBridgeUnitName = "unifi-os-supervisor-bridge";
    discoveryTargetBridgeUnitName = "unifi-os-discovery-target-bridge";

    parentNetworkUnitName =
      if networkCfg.parentInterface == (routerHelpers.lanInterface or null)
      then "40-${networkCfg.parentInterface}"
      else "10-${networkCfg.parentInterface}";

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
      networkName=${lib.escapeShellArg networkCfg.networkName}
      containerIp=${lib.escapeShellArg cfg.advertisedAddress}
      hostAccessEnabled=${
        if hostAccessEnabled
        then "1"
        else "0"
      }
      hostAccessIp=${lib.escapeShellArg (networkCfg.hostAccess.address or "")}

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

    runtimePath = [
      config.virtualisation.podman.package
      pkgs.shadow
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.iproute2
    ];

    runtimeBindReadOnlyPaths = [
      "${installerPodmanWrapper}:/usr/bin/podman"
      "${installerSuWrapper}:/usr/bin/su"
    ];

    runtimeEnvironment = [
      "HOME=${cfg.serviceUser.home}"
      "XDG_CONFIG_HOME=${cfg.serviceUser.home}/.config"
      "XDG_RUNTIME_DIR=/run/user/${toString cfg.serviceUser.uid}"
      "DBUS_SESSION_BUS_ADDRESS=unix:path=/dev/null"
      "CONTAINERS_CONF=${cfg.serviceUser.home}/.config/containers/containers.conf"
      "DISCOVERY_CLIENT_LOG_PATH=${cfg.logsDirectory}"
    ];

    containerEnv =
      {
        UOS_SERVER_VERSION = package.version;
        FIRMWARE_PLATFORM =
          if pkgs.stdenv.hostPlatform.isAarch64
          then "linux-arm64"
          else "linux-x64";
      }
      // cfg.container.environment;

    containerVolumes =
      [
        "${cfg.dataDirectory.persistent}:/persistent"
        "${cfg.logsDirectory}:/var/log"
        "${cfg.dataDirectory.data}:/data"
        "${cfg.dataDirectory.srv}:/srv"
        "${cfg.dataDirectory.unifi}:/var/lib/unifi"
        "${cfg.dataDirectory.mongodb}:/var/lib/mongodb"
        "${ucoreDebug}:/etc/systemd/system/unifi-core.service.d/debug.conf:ro"
        "${ucorePreStartFix}:/etc/systemd/system/unifi-core.service.d/prestart-fix.conf:ro"
        "${mongoPreStartFix}:/etc/systemd/system/mongodb.service.d/prestart-fix.conf:ro"
        "${dbusStartFix}:/etc/dbus-1/system.d/start-fix.conf:ro"
        "${dbusStartFix}:/etc/dbus-1/session.d/start-fix.conf:ro"
      ]
      ++ cfg.container.extraVolumes;

    renderMultilineArgs = render: values: lib.concatMapStringsSep " \\\n                " render values;

    renderEnvArgs = env:
      renderMultilineArgs (name: "-e ${lib.escapeShellArg "${name}=${env.${name}}"}") (lib.attrNames env);

    renderVolumeArgs = volumes:
      renderMultilineArgs (volume: "-v ${lib.escapeShellArg volume}") volumes;

    renderExtraArgs = args:
      renderMultilineArgs lib.escapeShellArg args;

    bridgeServices = builtins.listToAttrs (map (
        bridge: {
          name = bridge.unitName;
          value = {
            inherit (bridge) description;
            wantedBy = ["multi-user.target"];
            inherit (bridge) after;
            inherit (bridge) wants;
            serviceConfig = {
              ExecStart = bridge.execStart;
              Restart = "always";
              RestartSec = 1;
            };
          };
        }
      ) (optionals hostAccessEnabled [
        {
          unitName = supervisorBridgeUnitName;
          description = "Expose UniFi supervisor websocket on localhost";
          after = ["network-online.target" "${networkUnitName}.service"];
          wants = ["network-online.target" "${networkUnitName}.service"];
          execStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${toString vendorPorts.supervisorWebsocket},bind=127.0.0.1,fork,reuseaddr TCP:${cfg.advertisedAddress}:${toString vendorPorts.supervisorWebsocket}";
        }
        {
          unitName = discoveryTargetBridgeUnitName;
          description = "Expose UniFi discovery target on localhost";
          after = ["network-online.target" "${networkUnitName}.service"];
          wants = ["network-online.target" "${networkUnitName}.service"];
          execStart = "${pkgs.socat}/bin/socat UDP4-RECVFROM:${toString vendorPorts.discoveryTarget},bind=127.0.0.1,fork UDP4-SENDTO:${cfg.advertisedAddress}:${toString vendorPorts.discoveryTarget}";
        }
        {
          unitName = discoveryHelperBridgeUnitName;
          description = "Expose UniFi discovery helper on host access IP";
          after = ["network-online.target" "${runtimeUnitName}.service"];
          wants = ["network-online.target"];
          execStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${toString vendorPorts.discoveryHelper},bind=${networkCfg.hostAccess.address},fork,reuseaddr TCP:127.0.0.1:${toString vendorPorts.discoveryHelper}";
        }
      ]));

    prepareBridgeDependencies = optionals hostAccessEnabled [
      "${supervisorBridgeUnitName}.service"
      "${discoveryTargetBridgeUnitName}.service"
    ];
  in {
    options.services.unifi-os-server = {
      enable = mkEnableOption "UniFi OS Server installer runtime";

      package = mkOption {
        type = types.package;
        default = defaultPackage;
        defaultText = literalExpression "pkgs.callPackage ../../pkgs/unifi-os { sha256 = \"…\"; }";
        description = ''
          Package containing the extracted UniFi OS Server installer assets and
          package metadata.
        '';
      };

      advertisedAddress = mkOption {
        type = types.str;
        default = config.my.listenNetworkAddress;
        defaultText = literalExpression "config.my.listenNetworkAddress";
        description = ''
          LAN-reachable IPv4 address assigned to the UniFi container and
          advertised to UniFi devices for discovery and adoption.
        '';
      };

      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether or not to open the minimum required firewall ports for UniFi
          discovery, adoption, and management.
        '';
      };

      stateDir = mkOption {
        type = types.str;
        default = "/var/lib/unifi-os";
        description = "Persistent host state directory for UniFi OS data.";
      };

      runtimeDir = mkOption {
        type = types.str;
        default = "/var/lib/uosserver";
        description = "Working directory used by the vendor installer runtime binaries.";
      };

      logsDirectory = mkOption {
        type = types.str;
        default = "/var/log/unifi-os";
        description = "Host directory used for UniFi OS logs.";
      };

      dataDirectory = {
        persistent = mkOption {
          type = types.str;
          default = "${cfg.stateDir}/persistent";
          description = "Host directory mounted to /persistent in the UniFi container.";
        };
        data = mkOption {
          type = types.str;
          default = "${cfg.stateDir}/data";
          description = "Host directory mounted to /data in the UniFi container.";
        };
        srv = mkOption {
          type = types.str;
          default = "${cfg.stateDir}/srv";
          description = "Host directory mounted to /srv in the UniFi container.";
        };
        unifi = mkOption {
          type = types.str;
          default = "${cfg.stateDir}/unifi";
          description = "Host directory mounted to /var/lib/unifi in the UniFi container.";
        };
        mongodb = mkOption {
          type = types.str;
          default = "${cfg.stateDir}/mongodb";
          description = "Host directory mounted to /var/lib/mongodb in the UniFi container.";
        };
      };

      serviceUser = {
        name = mkOption {
          type = types.str;
          default = "uosserver";
          description = "System user name used for vendor runtime state.";
        };
        uid = mkOption {
          type = types.int;
          default = 980;
          description = "UID for the UniFi OS installer runtime user.";
        };
        group = mkOption {
          type = types.str;
          default = "uosserver";
          description = "Primary group for the UniFi OS installer runtime user.";
        };
        gid = mkOption {
          type = types.int;
          default = 972;
          description = "GID for the UniFi OS installer runtime group.";
        };
        home = mkOption {
          type = types.str;
          default = "/home/uosserver";
          description = "Home directory for the UniFi OS installer runtime user.";
        };
      };

      network = {
        networkName = mkOption {
          type = types.str;
          default = "unifi-os-lan";
          description = "Podman macvlan network name used for the UniFi container.";
        };

        parentInterface = mkOption {
          type = types.nullOr types.str;
          default = routerHelpers.lanInterface or (routerHelpers.lanBridge or null);
          defaultText = literalExpression "config.routerHelpers.lanInterface or (config.routerHelpers.lanBridge or null)";
          description = "Parent interface or bridge for the UniFi macvlan network.";
        };

        subnet = mkOption {
          type = types.nullOr types.str;
          default = routerHelpers.lanCidr or null;
          defaultText = literalExpression "config.routerHelpers.lanCidr or null";
          description = "IPv4 subnet assigned to the UniFi macvlan network.";
        };

        gateway = mkOption {
          type = types.nullOr types.str;
          default = routerHelpers.routerIp or null;
          defaultText = literalExpression "config.routerHelpers.routerIp or null";
          description = "IPv4 gateway assigned to the UniFi macvlan network.";
        };

        hostAccess = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Create a host-side macvlan shim so the host can directly reach the
              UniFi container IP and expose vendor localhost services onto the LAN.
            '';
          };
          interfaceName = mkOption {
            type = types.str;
            default = "unifi-os-host";
            description = "Host-side macvlan interface name used for UniFi host access.";
          };
          address = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "10.0.0.22";
            description = "Host-side /32 address assigned to the UniFi macvlan shim interface.";
          };
        };
      };

      container = {
        name = mkOption {
          type = types.str;
          default = installerMetadata.containerName or "uosserver";
          description = "Container name expected by the vendor runtime.";
        };
        imageTag = mkOption {
          type = types.str;
          default = installerMetadata.imageTag or "uosserver:0.0.54";
          description = "Exact container image name:tag embedded in the vendor installer.";
        };
        environment = mkOption {
          type = types.attrsOf types.str;
          default = {};
          description = "Additional environment variables applied when creating the UniFi container.";
        };
        extraVolumes = mkOption {
          type = types.listOf types.str;
          default = [];
          example = ["/etc/ssl/certs:/etc/rabbitmq/ssl:ro"];
          description = "Additional bind mounts beyond the default UniFi container mounts.";
        };
        extraOptions = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Additional low-level Podman arguments appended to vendor container creation.";
        };
      };
    };

    config = mkIf cfg.enable {
      assertions = [
        {
          assertion = networkCfg.parentInterface != null;
          message = "services.unifi-os-server.network.parentInterface must be set";
        }
        {
          assertion = networkCfg.subnet != null;
          message = "services.unifi-os-server.network.subnet must be set";
        }
        {
          assertion = networkCfg.gateway != null;
          message = "services.unifi-os-server.network.gateway must be set";
        }
        {
          assertion = !(hostAccessEnabled && networkCfg.hostAccess.address == null);
          message = "services.unifi-os-server.network.hostAccess.address must be set when hostAccess is enabled";
        }
      ];

      virtualisation.podman.enable = true;

      systemd.network = mkIf hostAccessEnabled {
        netdevs."40-${networkCfg.hostAccess.interfaceName}" = {
          netdevConfig = {
            Name = networkCfg.hostAccess.interfaceName;
            Kind = "macvlan";
          };
          macvlanConfig.Mode = "bridge";
        };

        networks = {
          "${parentNetworkUnitName}" = {
            matchConfig.Name = networkCfg.parentInterface;
            macvlan = [networkCfg.hostAccess.interfaceName];
          };

          "90-${networkCfg.hostAccess.interfaceName}" = {
            matchConfig.Name = networkCfg.hostAccess.interfaceName;
            address = ["${networkCfg.hostAccess.address}/32"];
            routes = [
              {
                Destination = "${cfg.advertisedAddress}/32";
                Scope = "link";
              }
            ];
            networkConfig.ConfigureWithoutCarrier = true;
            linkConfig.RequiredForOnline = "no";
          };
        };
      };

      networking.firewall = mkIf cfg.openFirewall {
        allowedTCPPorts = [443 8080 8443 8843 8880 6789];
        allowedUDPPorts = [3478 10001];
      };

      systemd.services =
        bridgeServices
        // {
          ${networkUnitName} = {
            description = "Create UniFi OS macvlan Podman network";
            wantedBy = ["multi-user.target"];
            path = [config.virtualisation.podman.package];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              set -euo pipefail

              if podman network exists ${lib.escapeShellArg networkCfg.networkName}; then
                current_parent="$(podman network inspect ${lib.escapeShellArg networkCfg.networkName} --format '{{.NetworkInterface}}')"
                if [ "$current_parent" != ${lib.escapeShellArg networkCfg.parentInterface} ]; then
                  podman network rm ${lib.escapeShellArg networkCfg.networkName}
                fi
              fi

              if ! podman network exists ${lib.escapeShellArg networkCfg.networkName}; then
                podman network create \
                  -d macvlan \
                  --subnet ${lib.escapeShellArg networkCfg.subnet} \
                  --gateway ${lib.escapeShellArg networkCfg.gateway} \
                  -o mode=bridge \
                  -o parent=${lib.escapeShellArg networkCfg.parentInterface} \
                  ${lib.escapeShellArg networkCfg.networkName}
              fi
            '';
          };

          ${prepareUnitName} = {
            description = "Prepare UniFi OS installer runtime state";
            wantedBy = ["multi-user.target"];
            requires = ["${networkUnitName}.service"];
            after =
              [
                "network-online.target"
                "${networkUnitName}.service"
              ]
              ++ prepareBridgeDependencies;
            wants =
              [
                "network-online.target"
                "${networkUnitName}.service"
              ]
              ++ prepareBridgeDependencies;
            path = runtimePath;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = "root";
              WorkingDirectory = cfg.runtimeDir;
              BindReadOnlyPaths = runtimeBindReadOnlyPaths;
              Environment = runtimeEnvironment;
            };
            script = ''
              set -euo pipefail

              ${optionalString hostAccessEnabled ''
                current_parent="$(${pkgs.iproute2}/bin/ip -o link show ${networkCfg.hostAccess.interfaceName} 2>/dev/null | ${pkgs.gnused}/bin/sed -n 's/^[0-9]*: [^@]*@\([^:]*\):.*/\1/p')"
                if [ -n "$current_parent" ] && [ "$current_parent" != ${lib.escapeShellArg networkCfg.parentInterface} ]; then
                  ${pkgs.iproute2}/bin/ip link delete dev ${networkCfg.hostAccess.interfaceName}
                  ${pkgs.systemd}/bin/networkctl reload
                  ${pkgs.systemd}/bin/networkctl reconfigure ${networkCfg.parentInterface}
                fi
              ''}

              mkdir -p \
                ${cfg.dataDirectory.persistent} \
                ${cfg.dataDirectory.data} \
                ${cfg.dataDirectory.srv} \
                ${cfg.dataDirectory.unifi} \
                ${cfg.dataDirectory.mongodb} \
                ${cfg.logsDirectory} \
                ${cfg.dataDirectory.data}/unifi-core/config \
                ${cfg.dataDirectory.data}/unifi-core/logs \
                ${cfg.runtimeDir}/bin \
                ${cfg.runtimeDir}/logs

              uuid_file="${cfg.dataDirectory.data}/uos_uuid"
              if ! grep -qP '^[0-9a-f]{8}-[0-9a-f]{4}-5' "$uuid_file" 2>/dev/null; then
                ${pkgs.util-linux}/bin/uuidgen -s -n @dns -N "$(cat /etc/machine-id)" > "$uuid_file"
              fi
              uos_uuid="$(cat "$uuid_file")"

              install -d -m700 -o ${cfg.serviceUser.name} -g ${cfg.serviceUser.group} /run/user/${toString cfg.serviceUser.uid}
              install -d -m700 -o ${cfg.serviceUser.name} -g ${cfg.serviceUser.group} ${cfg.serviceUser.home}/.config/containers

              cat > ${cfg.serviceUser.home}/.config/containers/containers.conf <<EOF
              [engine]
              cgroup_manager="cgroupfs"
              events_logger="file"
              EOF
              chown ${cfg.serviceUser.name}:${cfg.serviceUser.group} ${cfg.serviceUser.home}/.config/containers/containers.conf

              install -C -m755 ${packageBinaries.discovery} ${cfg.runtimeDir}/bin/discovery
              install -C -m755 ${packageBinaries.runtime} ${cfg.runtimeDir}/uosserver
              install -C -m755 ${packageBinaries.runtimeService} ${cfg.runtimeDir}/uosserver-service
              install -C -m755 ${packageBinaries.updaterService} ${cfg.runtimeDir}/updater-service
              ${optionalString (packageBinaries.pasta != null) "install -C -m755 ${packageBinaries.pasta} ${cfg.runtimeDir}/pasta"}
              ${optionalString (packageBinaries.purge != null) "install -C -m755 ${packageBinaries.purge} ${cfg.runtimeDir}/purge"}
              install -C -m644 ${packageBinaries.imageTar} ${cfg.runtimeDir}/image.tar

              cat > ${cfg.runtimeDir}/server.conf <<EOF
              NETWORK_MODE=pasta
              CONTAINER_IMAGE_NAME=${cfg.container.imageTag}
              CONTAINER_VERSION=${package.version}
              UOS_SERVER_VERSION=${package.version}
              UOS_UUID=$uos_uuid
              EOF

              system_properties="${cfg.dataDirectory.unifi}/system.properties"
              ${pkgs.gnugrep}/bin/grep -q '^system_ip=' "$system_properties" 2>/dev/null \
                && ${pkgs.gnused}/bin/sed -i 's/^system_ip=.*/system_ip=${cfg.advertisedAddress}/' "$system_properties" \
                || printf '\nsystem_ip=%s\n' '${cfg.advertisedAddress}' >> "$system_properties"

              if ! ${config.virtualisation.podman.package}/bin/podman image exists ${lib.escapeShellArg cfg.container.imageTag}; then
                ${config.virtualisation.podman.package}/bin/podman load -i ${cfg.runtimeDir}/image.tar
              fi

              if ! /usr/bin/podman container exists ${lib.escapeShellArg cfg.container.name}; then
                /usr/bin/podman create \
                  --name ${lib.escapeShellArg cfg.container.name} \
                  --restart unless-stopped \
                  --pids-limit 65536 \
                  --cgroups disabled \
                  --health-cmd "curl --fail http://127.0.0.1/api/ping || exit 1" \
                  --health-interval 60s \
                  --health-timeout 5s \
                  --health-retries 3 \
                  -e UOS_UUID="$uos_uuid" \
                  ${renderEnvArgs containerEnv} \
                  ${renderVolumeArgs containerVolumes} \
                  ${renderExtraArgs cfg.container.extraOptions} \
                  ${lib.escapeShellArg cfg.container.imageTag}
              fi
            '';
          };

          ${updaterUnitName} = {
            description = "UniFi OS installer updater runtime";
            wantedBy = ["multi-user.target"];
            after = ["network-online.target" "${prepareUnitName}.service"];
            wants = ["network-online.target" "${prepareUnitName}.service"];
            path = runtimePath;
            serviceConfig = {
              ExecStart = "${cfg.runtimeDir}/updater-service";
              Restart = "always";
              RestartSec = 2;
              WorkingDirectory = cfg.runtimeDir;
              BindReadOnlyPaths = runtimeBindReadOnlyPaths;
              Environment = runtimeEnvironment;
            };
          };

          ${runtimeUnitName} = {
            description = "UniFi OS installer runtime supervisor";
            wantedBy = ["multi-user.target"];
            requires = ["${prepareUnitName}.service"];
            after = [
              "network-online.target"
              "${prepareUnitName}.service"
              "${updaterUnitName}.service"
            ];
            wants = [
              "network-online.target"
              "${prepareUnitName}.service"
              "${updaterUnitName}.service"
            ];
            path = runtimePath;
            serviceConfig = {
              ExecStart = "${cfg.runtimeDir}/uosserver-service";
              Restart = "always";
              RestartSec = 2;
              User = "root";
              WorkingDirectory = cfg.runtimeDir;
              BindReadOnlyPaths = runtimeBindReadOnlyPaths;
              Environment = runtimeEnvironment;
            };
          };
        };

      users.users.${cfg.serviceUser.name} = {
        isSystemUser = true;
        inherit (cfg.serviceUser) uid;
        inherit (cfg.serviceUser) group;
        inherit (cfg.serviceUser) home;
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

      users.groups.${cfg.serviceUser.group} = {
        inherit (cfg.serviceUser) gid;
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.runtimeDir} 0755 root root -"
        "d ${cfg.runtimeDir}/bin 0755 root root -"
        "d ${cfg.runtimeDir}/logs 0755 root root -"
        "d ${cfg.serviceUser.home} 0755 ${cfg.serviceUser.name} ${cfg.serviceUser.group} -"
        "d /run/user/${toString cfg.serviceUser.uid} 0700 ${cfg.serviceUser.name} ${cfg.serviceUser.group} -"
        "L+ /usr/bin/podman - - - - ${config.virtualisation.podman.package}/bin/podman"
      ];
    };
  };
}
