{
  config.flake.nixosModules.backups = { lib, config, pkgs, ... }: let
    inherit (lib) mkOption mkEnableOption types mkIf mkMerge mapAttrsToList;
    cfg = config.my.backups;
  in {
    options.my.backups = mkOption {
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          enable = mkEnableOption "Enable this backup job";
          path = mkOption { type = types.str; };
          include = mkOption { type = types.listOf types.str; default = []; };
          exclude = mkOption { type = types.listOf types.str; default = []; };
          frequency = mkOption {
            type = types.enum [ "hourly" "daily" "weekly" ];
            default = "daily";
          };
          pruneOpts = mkOption {
            type = types.listOf types.str;
            default = [ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 12" ];
          };
          backend = mkOption {
            type = types.submodule {
              options = {
                type = mkOption {
                  type = types.enum [ "b2" "s3" ];
                  default = "b2";
                };
                bucket = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Backend bucket name (auto-derived if null)";
                };
                region = mkOption { type = types.nullOr types.str; default = null; };
                endpoint = mkOption { type = types.nullOr types.str; default = null; };
                lifecycleKeepPriorVersionsDays = mkOption {
                  type = types.nullOr types.int;
                  default = null;
                  description = "For B2: keep prior versions for this many days (sets bucket lifecycle).";
                };
              };
            };
            default = { type = "b2"; };
          };
          restore = mkOption {
            type = types.submodule {
              options = {
                enable = mkEnableOption "Enable restore mode instead of backup";
                snapshot = mkOption {
                  type = types.str;
                  default = "latest";
                  description = "Snapshot ID or 'latest' to restore";
                };
              };
            };
            default = { enable = false; snapshot = "latest"; };
          };
        };
      }));
      default = {};
    };

    config = mkMerge [
      # Secrets declarations
      {
        my.secrets.declarations = lib.flatten (mapAttrsToList (name: backup:
          lib.optional backup.enable (
            config.my.secrets.mkMachineSecret {
              name = "restic-${name}";
              dependencies = (if backup.backend.type == "b2" then [ "b2-service" ] else if backup.backend.type == "s3" then [ "api-key-aws-access" "api-key-aws-secret" ] else [ ]);
              runtimeInputs = [ pkgs.openssl ];
              files = {
                repo = { mode = "0400"; };
                password = { mode = "0400"; };
                env = { mode = "0400"; };
              };
              prompts.password = {
                description = "Restic password for ${name}";
                type = "hidden"; persist = true;
              };
              script = let
                mkBucketName = "restic-${config.networking.hostName}-${name}";
                mkRepoUrl = 
                  if backup.backend.type == "b2" then
                    "b2:${if backup.backend.bucket != null then backup.backend.bucket else mkBucketName}:${name}"
                  else if backup.backend.type == "s3" then
                    "s3:${if backup.backend.bucket != null then backup.backend.bucket else mkBucketName}/${name}"
                  else
                    throw "Unsupported backend: ${backup.backend.type}";
                backendEnvSnippet =
                  if backup.backend.type == "b2" then ''
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
                    # Restic expects these names
                    printf "B2_ACCOUNT_ID=%s\n" "$B2_APPLICATION_KEY_ID" >> "$out/env"
                    printf "B2_ACCOUNT_KEY=%s\n" "$B2_APPLICATION_KEY" >> "$out/env"
                    chmod 0400 "$out/env"

                    export B2_APPLICATION_KEY_ID
                    export B2_APPLICATION_KEY
                    export B2_ACCOUNT_ID="$B2_APPLICATION_KEY_ID"
                    export B2_ACCOUNT_KEY="$B2_APPLICATION_KEY"
                  ''
                  else if backup.backend.type == "s3" then ''
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
                    ${lib.optionalString (backup.backend.region != null) ''printf "AWS_DEFAULT_REGION=%s\n" "${backup.backend.region}" >> "$out/env"''}
                    chmod 0400 "$out/env"

                    export AWS_ACCESS_KEY_ID
                    export AWS_SECRET_ACCESS_KEY
                    ${lib.optionalString (backup.backend.region != null) ''export AWS_DEFAULT_REGION="${backup.backend.region}"''}
                  ''
                  else throw "Unsupported backend: ${backup.backend.type}";
              in ''
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

                repo="${mkRepoUrl}"
                bucket="${if backup.backend.bucket != null then backup.backend.bucket else mkBucketName}"

                ${backendEnvSnippet}

                echo "$repo" > "$out/repo"
              '';
            }
          )
        ) cfg);
      }

      # Restic backup services
      {
        services.restic.backups = lib.mapAttrs (name: backup:
          mkIf (backup.enable && !backup.restore.enable) {
            initialize = true;
            repositoryFile = config.my.secrets.getPath "restic-${name}" "repo";
            passwordFile = config.my.secrets.getPath "restic-${name}" "password";
            environmentFile = config.my.secrets.getPath "restic-${name}" "env";
            paths = [ backup.path ];
            extraBackupArgs = 
              (map (p: "--include=" + p) backup.include)
              ++ (map (p: "--exclude=" + p) backup.exclude);
            timerConfig.OnCalendar = backup.frequency;
            pruneOpts = backup.pruneOpts;
          }
        ) cfg;
      }

      # Backend bootstrap services (networked, runtime)
      {
        systemd.services = lib.mapAttrs' (name: backup:
          lib.nameValuePair "restic-bootstrap-${name}" (mkIf (backup.enable && !backup.restore.enable) {
            description = "Create backend bucket for restic ${name}";
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              Type = "oneshot";
              EnvironmentFile = config.my.secrets.getPath "restic-${name}" "env";
            };
            script = let
              bucketName = if backup.backend.bucket != null then backup.backend.bucket else "restic-${config.networking.hostName}-${name}";
            in ''
              set -euo pipefail
              case ${backup.backend.type} in
                b2)
                  # Try to create the bucket; if it already exists, continue without failing
                  create_out="$(${pkgs.backblaze-b2}/bin/b2v4 bucket create "${bucketName}" allPrivate 2>&1 || true)"
                  if echo "$create_out" | ${pkgs.gnugrep}/bin/grep -qi "already in use"; then
                    : # bucket exists; proceed
                  elif [ -n "$create_out" ] && echo "$create_out" | ${pkgs.gnugrep}/bin/grep -qi "error"; then
                    echo "$create_out" >&2
                    # Do not fail the unit; continue
                  fi

                  # Best-effort enable server-side encryption; ignore failures
                  ${pkgs.backblaze-b2}/bin/b2v4 bucket update "${bucketName}" defaultServerSideEncryption=SSE-B2 >/dev/null 2>&1 || \
                  ${pkgs.backblaze-b2}/bin/b2v3 update-bucket --defaultServerSideEncryption SSE-B2 "${bucketName}" >/dev/null 2>&1 || true

                  # Optionally set lifecycle to keep prior versions for N days (B2)
                  ${lib.optionalString (backup.backend.lifecycleKeepPriorVersionsDays != null) ''
                  ${pkgs.backblaze-b2}/bin/b2v4 bucket update "${bucketName}" lifecycleRules='[{"fileNamePrefix":"","daysFromHidingToDeleting":'"${toString backup.backend.lifecycleKeepPriorVersionsDays}"'}]' >/dev/null 2>&1 || \
                  ${pkgs.backblaze-b2}/bin/b2v3 update-bucket --lifecycleRules '[{"fileNamePrefix":"","daysFromHidingToDeleting":'"${toString backup.backend.lifecycleKeepPriorVersionsDays}"'}]' "${bucketName}" >/dev/null 2>&1 || true
                  ''}
                  ;;
                s3)
                  ${pkgs.awscli2}/bin/aws s3api create-bucket --bucket "${bucketName}" \
                    ${lib.optionalString (backup.backend.region != null) "--region ${backup.backend.region}"} \
                    || true
                  ;;
              esac
            '';
          })
        ) cfg;
      }

      # Restore services
      {
        systemd.services = lib.mapAttrs' (name: backup:
          lib.nameValuePair "restic-restore-${name}" (mkIf (backup.enable && backup.restore.enable) {
            description = "Restic restore for ${name}";
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              EnvironmentFile = config.my.secrets.getPath "restic-${name}" "env";
              ExecStart = ''
                ${pkgs.restic}/bin/restic -r $(cat ${config.my.secrets.getPath "restic-${name}" "repo"}) \
                  --password-file ${config.my.secrets.getPath "restic-${name}" "password"} \
                  restore ${backup.restore.snapshot} --target ${backup.path}
              '';
            };
          })
        ) cfg;
      }
    ];
  };
}