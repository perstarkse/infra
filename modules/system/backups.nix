{
  config.flake.nixosModules.backups = {
    lib,
    config,
    pkgs,
    ...
  }: let
    inherit (lib) mkOption mkEnableOption types mkIf mkMerge mapAttrsToList concatLists;
    cfg = config.my.backups;

    backendSubmodule = types.submodule {
      options = {
        type = mkOption {
          type = types.enum ["b2" "s3" "garage-s3"];
          default = "b2";
          description = "Backend type: b2, s3 (AWS), or garage-s3 (local Garage)";
        };
        bucket = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Backend bucket name (auto-derived if null)";
        };
        region = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "S3 region (defaults to 'garage' for garage-s3)";
        };
        endpoint = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "S3 endpoint URL (required for garage-s3, defaults to http://10.0.0.1:3900)";
        };
        lifecycleKeepPriorVersionsDays = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "For B2: keep prior versions for this many days (sets bucket lifecycle).";
        };
      };
    };
  in {
    options.my.backups = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "Enable this backup job";
          path = mkOption {type = types.str;};
          include = mkOption {
            type = types.listOf types.str;
            default = [];
          };
          exclude = mkOption {
            type = types.listOf types.str;
            default = [];
          };
          frequency = mkOption {
            type = types.enum ["hourly" "daily" "weekly"];
            default = "daily";
          };
          pruneOpts = mkOption {
            type = types.listOf types.str;
            default = ["--keep-daily 7" "--keep-weekly 4" "--keep-monthly 12"];
          };

          backends = mkOption {
            type = types.attrsOf backendSubmodule;
            default = {};
            description = "Multiple backends for this backup job (for redundancy). Each key is a logical backend name.";
          };

          backend = mkOption {
            type = types.nullOr backendSubmodule;
            default = null;
            description = "Single backend (deprecated, use 'backends' for multi-backend support)";
          };

          restore = mkOption {
            type = types.submodule {
              options = {
                enable = mkEnableOption "Enable restore mode instead of backup";
                backend = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Backend key within 'backends' to restore from (defaults to first backend)";
                };
                snapshot = mkOption {
                  type = types.str;
                  default = "latest";
                  description = "Snapshot ID or 'latest' to restore";
                };
              };
            };
            default = {
              enable = false;
              snapshot = "latest";
            };
          };
        };
      });
      default = {};
    };

    config = let
      resolveBackends = backup:
        if backup.backends != {}
        then backup.backends
        else if backup.backend != null
        then {default = backup.backend;}
        else {default = {type = "b2";};};

      getEndpoint = bkCfg:
        if bkCfg.endpoint != null
        then bkCfg.endpoint
        else if bkCfg.type == "garage-s3"
        then "http://10.0.0.1:3900"
        else null;

      getRegion = bkCfg:
        if bkCfg.region != null
        then bkCfg.region
        else if bkCfg.type == "garage-s3"
        then "garage"
        else null;

      mkBucketName = jobName: "restic-${config.networking.hostName}-${jobName}";

      mkRepoUrl = jobName: bkCfg: let
        bucketName =
          if bkCfg.bucket != null
          then bkCfg.bucket
          else mkBucketName jobName;
        endpoint = getEndpoint bkCfg;
      in
        if bkCfg.type == "b2"
        then "b2:${bucketName}:${jobName}"
        else if bkCfg.type == "s3"
        then "s3:${bucketName}/${jobName}"
        else if bkCfg.type == "garage-s3"
        then "s3:${endpoint}/${bucketName}/${jobName}"
        else throw "Unsupported backend: ${bkCfg.type}";

      mkSecretName = jobName: bkName: "restic-${jobName}-${bkName}";

      getDependencies = bkCfg:
        if bkCfg.type == "b2"
        then ["b2-service"]
        else if bkCfg.type == "s3"
        then ["api-key-aws-access" "api-key-aws-secret"]
        else if bkCfg.type == "garage-s3"
        then ["garage-s3"]
        else [];

      mkBackendEnvSnippet = bkCfg:
        if bkCfg.type == "b2"
        then ''
          if [ -z "''${in:-}" ]; then
            echo "Error: dependency input mount ($in) not provided; cannot read B2 credentials" >&2
            exit 1
          fi
          B2_APPLICATION_KEY_ID_PATH="''${in}/b2-service/application_key_id"
          B2_APPLICATION_KEY_PATH="''${in}/b2-service/application_key"
          if [ ! -r "''${B2_APPLICATION_KEY_ID_PATH}" ] || [ ! -r "''${B2_APPLICATION_KEY_PATH}" ]; then
            echo "Error: missing B2 credentials under $in/b2-service" >&2
            exit 1
          fi
          B2_APPLICATION_KEY_ID="$(cat "''${B2_APPLICATION_KEY_ID_PATH}")"
          B2_APPLICATION_KEY="$(cat "''${B2_APPLICATION_KEY_PATH}")"
          printf "B2_APPLICATION_KEY_ID=%s\n" "$B2_APPLICATION_KEY_ID" > "$out/env"
          printf "B2_APPLICATION_KEY=%s\n" "$B2_APPLICATION_KEY" >> "$out/env"
          printf "B2_ACCOUNT_ID=%s\n" "$B2_APPLICATION_KEY_ID" >> "$out/env"
          printf "B2_ACCOUNT_KEY=%s\n" "$B2_APPLICATION_KEY" >> "$out/env"
          chmod 0400 "$out/env"

          export B2_APPLICATION_KEY_ID
          export B2_APPLICATION_KEY
          export B2_ACCOUNT_ID="$B2_APPLICATION_KEY_ID"
          export B2_ACCOUNT_KEY="$B2_APPLICATION_KEY"
        ''
        else if bkCfg.type == "s3"
        then let
          region = getRegion bkCfg;
        in ''
          if [ -z "''${in:-}" ]; then
            echo "Error: dependency input mount ($in) not provided; cannot read AWS credentials" >&2
            exit 1
          fi
          AWS_ACCESS_KEY_ID_PATH="''${in}/api-key-aws-access/aws_access_key_id"
          AWS_SECRET_ACCESS_KEY_PATH="''${in}/api-key-aws-secret/aws_secret_access_key"
          if [ ! -r "''${AWS_ACCESS_KEY_ID_PATH}" ] || [ ! -r "''${AWS_SECRET_ACCESS_KEY_PATH}" ]; then
            echo "Error: missing AWS credentials under $in" >&2
            exit 1
          fi
          AWS_ACCESS_KEY_ID="$(cat "''${AWS_ACCESS_KEY_ID_PATH}")"
          AWS_SECRET_ACCESS_KEY="$(cat "''${AWS_SECRET_ACCESS_KEY_PATH}")"
          printf "AWS_ACCESS_KEY_ID=%s\n" "$AWS_ACCESS_KEY_ID" > "$out/env"
          printf "AWS_SECRET_ACCESS_KEY=%s\n" "$AWS_SECRET_ACCESS_KEY" >> "$out/env"
          ${lib.optionalString (region != null) ''printf "AWS_DEFAULT_REGION=%s\n" "${region}" >> "$out/env"''}
          chmod 0400 "$out/env"

          export AWS_ACCESS_KEY_ID
          export AWS_SECRET_ACCESS_KEY
          ${lib.optionalString (region != null) ''export AWS_DEFAULT_REGION="${region}"''}
        ''
        else if bkCfg.type == "garage-s3"
        then let
          region = getRegion bkCfg;
        in ''
          if [ -z "''${in:-}" ]; then
            echo "Error: dependency input mount ($in) not provided; cannot read Garage S3 credentials" >&2
            exit 1
          fi
          ACCESS_KEY_ID_PATH="''${in}/garage-s3/access_key_id"
          SECRET_ACCESS_KEY_PATH="''${in}/garage-s3/secret_access_key"
          if [ ! -r "''${ACCESS_KEY_ID_PATH}" ] || [ ! -r "''${SECRET_ACCESS_KEY_PATH}" ]; then
            echo "Error: missing Garage S3 credentials under $in/garage-s3" >&2
            exit 1
          fi
          AWS_ACCESS_KEY_ID="$(cat "''${ACCESS_KEY_ID_PATH}")"
          AWS_SECRET_ACCESS_KEY="$(cat "''${SECRET_ACCESS_KEY_PATH}")"
          printf "AWS_ACCESS_KEY_ID=%s\n" "$AWS_ACCESS_KEY_ID" > "$out/env"
          printf "AWS_SECRET_ACCESS_KEY=%s\n" "$AWS_SECRET_ACCESS_KEY" >> "$out/env"
          ${lib.optionalString (region != null) ''printf "AWS_DEFAULT_REGION=%s\n" "${region}" >> "$out/env"''}
          chmod 0400 "$out/env"

          export AWS_ACCESS_KEY_ID
          export AWS_SECRET_ACCESS_KEY
          ${lib.optionalString (region != null) ''export AWS_DEFAULT_REGION="${region}"''}
        ''
        else throw "Unsupported backend: ${bkCfg.type}";
    in
      mkMerge [
        {
          my.secrets.declarations = concatLists (mapAttrsToList (
              jobName: backup:
                if !backup.enable
                then []
                else let
                  backends = resolveBackends backup;
                in
                  mapAttrsToList (
                    bkName: bkCfg: let
                      secretName = mkSecretName jobName bkName;
                      repoUrl = mkRepoUrl jobName bkCfg;
                      bucketName =
                        if bkCfg.bucket != null
                        then bkCfg.bucket
                        else mkBucketName jobName;
                    in
                      config.my.secrets.mkMachineSecret {
                        name = secretName;
                        dependencies = getDependencies bkCfg;
                        runtimeInputs = [pkgs.openssl];
                        files = {
                          repo = {mode = "0400";};
                          password = {mode = "0400";};
                          env = {mode = "0400";};
                        };
                        prompts.password = {
                          description = "Restic password for ${jobName}/${bkName}";
                          type = "hidden";
                          persist = true;
                        };
                        script = ''
                          set -euo pipefail
                          if [ -z "''${prompts:-}" ]; then
                            prompts="$(mktemp -d)"
                          fi
                          mkdir -p "$out"

                          if [ -s "$prompts/password" ]; then
                            cp "$prompts/password" "$out/password"
                          else
                            ${pkgs.openssl}/bin/openssl rand -base64 32 > "$out/password"
                          fi
                          chmod 0400 "$out/password"

                          repo="${repoUrl}"
                          bucket="${bucketName}"

                          ${mkBackendEnvSnippet bkCfg}

                          echo "$repo" > "$out/repo"
                        '';
                      }
                  )
                  backends
            )
            cfg);
        }

        {
          services.restic.backups = lib.mkMerge (concatLists (mapAttrsToList (
              jobName: backup:
                if !backup.enable || backup.restore.enable
                then []
                else let
                  backends = resolveBackends backup;
                in
                  mapAttrsToList (
                    bkName: _bkCfg: let
                      secretName = mkSecretName jobName bkName;
                    in {
                      "${jobName}-${bkName}" = {
                        initialize = true;
                        repositoryFile = config.my.secrets.getPath secretName "repo";
                        passwordFile = config.my.secrets.getPath secretName "password";
                        environmentFile = config.my.secrets.getPath secretName "env";
                        paths = [backup.path];
                        extraBackupArgs =
                          (map (p: "--include=" + p) backup.include)
                          ++ (map (p: "--exclude=" + p) backup.exclude);
                        timerConfig.OnCalendar = backup.frequency;
                        inherit (backup) pruneOpts;
                      };
                    }
                  )
                  backends
            )
            cfg));
        }

        {
          systemd.services = lib.mkMerge (concatLists (mapAttrsToList (
              jobName: backup:
                if !backup.enable || backup.restore.enable
                then []
                else let
                  backends = resolveBackends backup;
                in
                  mapAttrsToList (
                    bkName: bkCfg: let
                      secretName = mkSecretName jobName bkName;
                      bucketName =
                        if bkCfg.bucket != null
                        then bkCfg.bucket
                        else mkBucketName jobName;
                      endpoint = getEndpoint bkCfg;
                      region = getRegion bkCfg;
                    in {
                      "restic-bootstrap-${jobName}-${bkName}" = {
                        description = "Create backend bucket for restic ${jobName}/${bkName}";
                        wantedBy = ["multi-user.target"];
                        after = ["network-online.target"];
                        wants = ["network-online.target"];
                        serviceConfig = {
                          Type = "oneshot";
                          EnvironmentFile = config.my.secrets.getPath secretName "env";
                        };
                        script = let
                          b2Script = ''
                            create_out="$(${pkgs.backblaze-b2}/bin/b2v4 bucket create "${bucketName}" allPrivate 2>&1 || true)"
                            if echo "$create_out" | ${pkgs.gnugrep}/bin/grep -qi "already in use"; then
                              :
                            elif [ -n "$create_out" ] && echo "$create_out" | ${pkgs.gnugrep}/bin/grep -qi "error"; then
                              echo "$create_out" >&2
                            fi

                            ${pkgs.backblaze-b2}/bin/b2v4 bucket update "${bucketName}" defaultServerSideEncryption=SSE-B2 >/dev/null 2>&1 || \
                            ${pkgs.backblaze-b2}/bin/b2v3 update-bucket --defaultServerSideEncryption SSE-B2 "${bucketName}" >/dev/null 2>&1 || true

                            ${lib.optionalString (bkCfg.lifecycleKeepPriorVersionsDays != null) ''
                              ${pkgs.backblaze-b2}/bin/b2v4 bucket update "${bucketName}" lifecycleRules='[{"fileNamePrefix":"","daysFromHidingToDeleting":'"${toString bkCfg.lifecycleKeepPriorVersionsDays}"'}]' >/dev/null 2>&1 || \
                              ${pkgs.backblaze-b2}/bin/b2v3 update-bucket --lifecycleRules '[{"fileNamePrefix":"","daysFromHidingToDeleting":'"${toString bkCfg.lifecycleKeepPriorVersionsDays}"'}]' "${bucketName}" >/dev/null 2>&1 || true
                            ''}
                          '';
                          s3Script = ''
                            ${pkgs.awscli2}/bin/aws s3api create-bucket --bucket "${bucketName}" \
                              ${lib.optionalString (region != null) "--region ${region}"} \
                              || true
                          '';
                          garageS3Script = ''
                            ${pkgs.awscli2}/bin/aws --endpoint-url ${endpoint} s3api create-bucket --bucket "${bucketName}" \
                              ${lib.optionalString (region != null) "--region ${region}"} \
                              || true
                          '';
                        in ''
                          set -euo pipefail
                          ${
                            if bkCfg.type == "b2"
                            then b2Script
                            else if bkCfg.type == "s3"
                            then s3Script
                            else if bkCfg.type == "garage-s3"
                            then garageS3Script
                            else throw "Unsupported backend: ${bkCfg.type}"
                          }
                        '';
                      };
                    }
                  )
                  backends
            )
            cfg));
        }

        {
          systemd.services = lib.mkMerge (mapAttrsToList (
              jobName: backup: let
                backends = resolveBackends backup;
                targetBackendName =
                  if backup.restore.backend != null
                  then backup.restore.backend
                  else builtins.head (lib.attrNames backends);
                secretName = mkSecretName jobName targetBackendName;
              in {
                "restic-restore-${jobName}" = mkIf (backup.enable && backup.restore.enable) {
                  description = "Restic restore for ${jobName} from ${targetBackendName}";
                  wantedBy = ["multi-user.target"];
                  serviceConfig = {
                    Type = "oneshot";
                    EnvironmentFile = config.my.secrets.getPath secretName "env";
                    ExecStart = ''
                      ${pkgs.restic}/bin/restic --repository-file ${config.my.secrets.getPath secretName "repo"} \
                        --password-file ${config.my.secrets.getPath secretName "password"} \
                        restore ${backup.restore.snapshot} --target ${backup.path}
                    '';
                  };
                };
              }
            )
            cfg);
        }
      ];
  };
}
