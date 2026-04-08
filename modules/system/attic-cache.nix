{
  config.flake.nixosModules.attic-cache = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkEnableOption mkIf mkMerge mkOption optionalString types;
    cfg = config.my.attic-cache;

    serverEndpoint = "http://${cfg.server.listenAddress}:${toString cfg.server.port}";
    clientCacheEndpoint = "${cfg.client.endpoint}/${cfg.client.cacheName}";
    clientConfigRoot = "${cfg.client.stateDir}/.config/attic";
    clientConfigFile = "${clientConfigRoot}/config.toml";
    clientNixConfigFile = "/etc/nix/attic-cache.conf";

    inherit (cfg) secretName;
    serverEnvFile = config.my.secrets.getPath secretName "server.env";
    publicKeyFile = config.my.secrets.getPath secretName "public-key";
    pushTokenFile =
      if cfg.client.tokenFileName == null
      then null
      else config.my.secrets.getPath secretName cfg.client.tokenFileName;

    secretCacheName =
      if cfg.server.enable
      then cfg.server.cacheName
      else cfg.client.cacheName;

    configureClient = pkgs.writeShellScriptBin "attic-cache-configure" ''
            set -euo pipefail

            public_key="$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg publicKeyFile})"

            ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg clientConfigRoot}

            tmp="$(${pkgs.coreutils}/bin/mktemp)"
            cat > "$tmp" <<EOF
      extra-substituters = ${clientCacheEndpoint}
      extra-trusted-public-keys = $public_key
      EOF
            ${pkgs.coreutils}/bin/install -D -m 0644 "$tmp" ${lib.escapeShellArg clientNixConfigFile}
            ${pkgs.coreutils}/bin/rm -f "$tmp"

            ${optionalString (pushTokenFile != null) ''
        cat > ${lib.escapeShellArg clientConfigFile} <<EOF
        default-server = "${cfg.client.serverName}"
        [servers.${cfg.client.serverName}]
        endpoint = "${cfg.client.endpoint}/"
        token-file = "${pushTokenFile}"
        EOF
        ${pkgs.coreutils}/bin/chmod 0600 ${lib.escapeShellArg clientConfigFile}
      ''}

            ${optionalString (pushTokenFile == null) ''
        ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg clientConfigFile}
      ''}

            ${pkgs.systemd}/bin/systemctl try-restart nix-daemon.service >/dev/null 2>&1 || true
    '';

    postBuildHook = pkgs.writeShellScript "attic-cache-post-build-hook" ''
      set -eu
      set -f
      export IFS=' '

      if [ ! -f ${lib.escapeShellArg clientConfigFile} ]; then
        exit 0
      fi

      export HOME=${lib.escapeShellArg cfg.client.stateDir}
      export XDG_CONFIG_HOME=${lib.escapeShellArg "${cfg.client.stateDir}/.config"}

      printf '%s\n' $OUT_PATHS | ${pkgs.attic-client}/bin/attic push --stdin ${lib.escapeShellArg "${cfg.client.serverName}:${cfg.client.cacheName}"} || true
    '';

    bootstrapServerCache = pkgs.writeShellScriptBin "attic-cache-bootstrap" ''
      set -euo pipefail

      cache_url=${lib.escapeShellArg "${serverEndpoint}/_api/v1/cache-config/${cfg.server.cacheName}"}
      expected_public_key="$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg publicKeyFile})"
      tmpdir="$(${pkgs.coreutils}/bin/mktemp -d)"
      trap '${pkgs.coreutils}/bin/rm -rf "$tmpdir"' EXIT

      cat > "$tmpdir/server.toml" <<EOF
      listen = "${cfg.server.listenAddress}:${toString cfg.server.port}"
      api-endpoint = "${serverEndpoint}/"
      [database]
      url = "sqlite://${cfg.server.stateDir}/server.db?mode=rwc"
      [storage]
      type = "local"
      path = "${cfg.server.storageDir}"
      [chunking]
      nar-size-threshold = 65536
      min-size = 16384
      avg-size = 65536
      max-size = 262144
      [compression]
      type = "zstd"
      level = 6
      EOF

      set -a
      . ${lib.escapeShellArg serverEnvFile}
      set +a

      bootstrap_token="$(${pkgs.attic-server}/bin/atticadm -f "$tmpdir/server.toml" make-token --sub bootstrap --validity 10y --pull '*' --push '*' --create-cache '*' --delete '*' --configure-cache '*' --configure-cache-retention '*')"

      if current_json="$(${pkgs.curl}/bin/curl -fsS -H "Authorization: Bearer $bootstrap_token" "$cache_url" 2>/dev/null)"; then
        current_public_key="$(printf '%s' "$current_json" | ${pkgs.jq}/bin/jq -r '.public_key')"
        if [ "$current_public_key" != "$expected_public_key" ]; then
          printf '%s\n' "Attic cache ${cfg.server.cacheName} already exists with a different public key (expected: $expected_public_key, got: $current_public_key)." >&2
        fi
        exit 0
      fi

      ${pkgs.coreutils}/bin/mkdir -p "$tmpdir/.config"
      cat > "$tmpdir/.config/config.toml" <<EOF
      default-server = "local"
      [servers.local]
      endpoint = "${serverEndpoint}/"
      token = "$bootstrap_token"
      EOF

      HOME="$tmpdir" XDG_CONFIG_HOME="$tmpdir/.config" ${pkgs.attic-client}/bin/attic login local ${lib.escapeShellArg serverEndpoint} "$bootstrap_token"
      HOME="$tmpdir" XDG_CONFIG_HOME="$tmpdir/.config" ${pkgs.attic-client}/bin/attic cache create --public ${lib.escapeShellArg cfg.server.cacheName}
    '';
  in {
    options.my.attic-cache = {
      secretName = mkOption {
        type = types.str;
        default = "attic-cache";
        description = "Shared Clan vars generator name used for Attic secrets and metadata.";
      };

      server = {
        enable = mkEnableOption "host an Attic binary cache";

        listenAddress = mkOption {
          type = types.str;
          default = config.my.listenNetworkAddress;
          description = "Address for the Attic API and binary cache endpoint.";
        };

        port = mkOption {
          type = types.port;
          default = 8092;
          description = "TCP port used by the Attic server.";
        };

        cacheName = mkOption {
          type = types.str;
          default = "heliosphere";
          description = "Name of the Attic cache.";
        };

        stateDir = mkOption {
          type = types.str;
          default = "/var/lib/atticd";
          description = "SSD-backed state directory for Attic metadata.";
        };

        storageDir = mkOption {
          type = types.str;
          default = "/storage/attic/storage";
          description = "Directory used for Attic chunk and NAR storage.";
        };
      };

      client = {
        enable = mkEnableOption "use an Attic binary cache";

        endpoint = mkOption {
          type = types.str;
          default = "http://10.0.0.10:8092";
          description = "Base HTTP endpoint for the Attic server.";
        };

        serverName = mkOption {
          type = types.str;
          default = "makemake";
          description = "Local Attic client alias for the server.";
        };

        cacheName = mkOption {
          type = types.str;
          default = "heliosphere";
          description = "Cache name to pull from or push to.";
        };

        stateDir = mkOption {
          type = types.str;
          default = "/var/lib/attic-client";
          description = "Root-owned state directory for Attic client auth config.";
        };

        autoPush = mkOption {
          type = types.bool;
          default = false;
          description = "Upload locally built outputs to the cache after successful builds.";
        };

        tokenFileName = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Optional file name within the shared Attic Clan vars generator used for push authentication.";
        };
      };
    };

    config = mkMerge [
      (mkIf (cfg.server.enable || cfg.client.enable) {
        assertions = [
          {
            assertion = !cfg.client.autoPush || cfg.client.tokenFileName != null;
            message = "my.attic-cache.client.autoPush requires my.attic-cache.client.tokenFileName to be set.";
          }
          {
            assertion = !cfg.server.enable || secretCacheName == cfg.server.cacheName;
            message = "Attic cache generator and server cache names must match.";
          }
          {
            assertion = !cfg.client.enable || secretCacheName == cfg.client.cacheName;
            message = "Attic cache generator and client cache names must match.";
          }
        ];

        my.secrets.declarations = [
          {
            ${secretName} = {
              share = true;
              files = {
                "server.env" = {
                  mode = "0400";
                  neededFor = "services";
                };
                "private-key" = {
                  mode = "0400";
                  neededFor = "services";
                };
                "public-key" = {
                  mode = "0400";
                  neededFor = "services";
                };
                "charon-token" = {
                  mode = "0400";
                  neededFor = "services";
                };
              };
              runtimeInputs = [
                pkgs.attic-server
                pkgs.coreutils
                pkgs.nix
                pkgs.openssl
              ];
              script = ''
                set -euo pipefail
                umask 077
                mkdir -p "$out"

                cache_name=${lib.escapeShellArg secretCacheName}
                tmpdir="$(${pkgs.coreutils}/bin/mktemp -d)"
                trap '${pkgs.coreutils}/bin/rm -rf "$tmpdir"' EXIT

                jwt_secret="$(${pkgs.openssl}/bin/openssl genrsa -traditional 4096 | ${pkgs.coreutils}/bin/base64 -w0)"
                printf 'ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=%s\n' "$jwt_secret" > "$out/server.env"
                ${pkgs.coreutils}/bin/chmod 0400 "$out/server.env"

                ${pkgs.nix}/bin/nix-store --generate-binary-cache-key "$cache_name" "$tmpdir/private-key" "$tmpdir/public-key"
                ${pkgs.coreutils}/bin/install -m 0400 "$tmpdir/private-key" "$out/private-key"
                ${pkgs.coreutils}/bin/install -m 0400 "$tmpdir/public-key" "$out/public-key"

                cat > "$tmpdir/server.toml" <<EOF
                listen = "127.0.0.1:0"
                api-endpoint = "http://127.0.0.1:0/"
                [database]
                url = "sqlite://:memory:"
                [storage]
                type = "local"
                path = "/tmp/attic"
                [chunking]
                nar-size-threshold = 65536
                min-size = 16384
                avg-size = 65536
                max-size = 262144
                [compression]
                type = "zstd"
                level = 6
                EOF

                export ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="$jwt_secret"
                ${pkgs.attic-server}/bin/atticadm -f "$tmpdir/server.toml" make-token \
                  --sub charon \
                  --validity 10y \
                  --pull "$cache_name" \
                  --push "$cache_name" \
                  > "$out/charon-token"
                ${pkgs.coreutils}/bin/chmod 0400 "$out/charon-token"
              '';
            };
          }
        ];
      })

      (mkIf cfg.server.enable {
        services.atticd = {
          enable = true;
          environmentFile = serverEnvFile;
          settings = {
            listen = "${cfg.server.listenAddress}:${toString cfg.server.port}";
            api-endpoint = "${serverEndpoint}/";
            database.url = "sqlite://${cfg.server.stateDir}/server.db?mode=rwc";
            storage = {
              type = "local";
              path = cfg.server.storageDir;
            };
          };
        };

        systemd.services.atticd.serviceConfig.DynamicUser = lib.mkForce false;

        systemd.services.atticd-prepare = {
          description = "Prepare Attic server state";
          wantedBy = ["atticd.service"];
          before = ["atticd.service"];
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            Group = "root";
          };
          script = ''
            set -euo pipefail
            ${pkgs.coreutils}/bin/install -d -m 0700 -o atticd -g atticd ${lib.escapeShellArg cfg.server.stateDir}
            ${pkgs.coreutils}/bin/install -d -m 0750 -o atticd -g atticd ${lib.escapeShellArg cfg.server.storageDir}
          '';
        };

        systemd.services.attic-cache-bootstrap = {
          description = "Bootstrap Attic cache";
          after = ["atticd.service" "network-online.target"];
          wants = ["network-online.target"];
          requires = ["atticd.service"];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            Group = "root";
          };
          script = ''
            ${bootstrapServerCache}/bin/attic-cache-bootstrap
          '';
        };

        users.users.atticd = {
          isSystemUser = true;
          group = "atticd";
          home = cfg.server.stateDir;
          createHome = false;
        };
        users.groups.atticd = {};

        environment.systemPackages = [
          pkgs.attic-client
          bootstrapServerCache
        ];

        networking.firewall.allowedTCPPorts = [cfg.server.port];
      })

      (mkIf cfg.client.enable {
        environment.systemPackages = [
          pkgs.attic-client
          configureClient
        ];

        nix.extraOptions = ''
          !include ${clientNixConfigFile}
        '';

        nix.settings = mkIf cfg.client.autoPush {
          post-build-hook = postBuildHook;
        };

        systemd.tmpfiles.rules = [
          "d ${cfg.client.stateDir} 0700 root root -"
          "d ${clientConfigRoot} 0700 root root -"
        ];

        system.activationScripts.attic-cache = ''
          ${configureClient}/bin/attic-cache-configure
        '';
      })
    ];
  };
}
