{
  getPathDefault,
  withDiscover ? false,
  withAllowReadAccess ? false,
  withGenerateManifest ? false,
  mkMachineSecretDefault ? (_: {}),
  ...
}: {
  lib,
  pkgs,
  ...
}: {
  options.my.secrets =
    {
      declarations = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
      };
      getPath = lib.mkOption {
        type = lib.types.anything;
        default = getPathDefault;
      };
      # New helper API (strict getPath era): stubbed as pass-throughs so
      # modules referencing them eval under test. requireGenerators is
      # accepted and ignored — the stub provides no generators to check.
      requireGenerators = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };
      mkRestartOnRotation = lib.mkOption {
        type = lib.types.anything;
        default = {
          service,
          secretName,
          file ? null,
          files ? null,
          settleSeconds ? 0,
        }: let
          fileList =
            if files != null
            then files
            else [file];
          paths = map (f: getPathDefault secretName f) fileList;
        in {
          paths."${service}-env-rotation" = {
            description = "Restart ${service} when its secret file rotates (stub)";
            wantedBy = ["multi-user.target"];
            pathConfig = {
              PathChanged = paths;
              Unit = "${service}-env-rotation-restart.service";
            };
          };
          services."${service}-env-rotation-restart" = {
            description = "Restart ${service} after secret rotation (stub)";
            serviceConfig =
              {
                Type = "oneshot";
                ExecStart = "systemctl restart ${service}.service";
              }
              // (lib.optionalAttrs (settleSeconds > 0) {
                ExecStartPre = "${pkgs.coreutils}/bin/sleep ${toString settleSeconds}";
              });
          };
        };
      };
      mkTryRestartOnRotation = lib.mkOption {
        type = lib.types.anything;
        default = {
          service,
          secretName,
          file ? null,
          files ? null,
          settleSeconds ? 0,
        }: let
          fileList =
            if files != null
            then files
            else [file];
          paths = map (f: getPathDefault secretName f) fileList;
        in {
          paths."${service}-env-rotation" = {
            description = "Re-apply ${service} when its secret file rotates (stub)";
            wantedBy = ["multi-user.target"];
            pathConfig = {
              PathChanged = paths;
              Unit = "${service}-env-rotation-restart.service";
            };
          };
          services."${service}-env-rotation-restart" = {
            description = "Re-apply ${service} when its secret file rotates (stub)";
            serviceConfig =
              {
                Type = "oneshot";
                ExecStart = "systemctl try-restart ${service}.service";
              }
              // (lib.optionalAttrs (settleSeconds > 0) {
                ExecStartPre = "${pkgs.coreutils}/bin/sleep ${toString settleSeconds}";
              });
          };
        };
      };
      mkMachineSecret = lib.mkOption {
        type = lib.types.anything;
        default = mkMachineSecretDefault;
      };
    }
    // (lib.optionalAttrs withAllowReadAccess {
      allowReadAccess = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
      };
    })
    // (lib.optionalAttrs withGenerateManifest {
      generateManifest = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      exposeUserSecrets = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
      };
      exposeUserSecret = lib.mkOption {
        type = lib.types.nullOr lib.types.anything;
        default = null;
      };
    })
    // (lib.optionalAttrs withDiscover {
      discover = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        dir = lib.mkOption {
          type = lib.types.path;
          default = /tmp;
        };
        includeTags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
        };
        excludeTags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
        };
      };
    });

  # NixOS-level `sops` option space. In production these options are provided
  # by the vars-helper NixOS module (sops-nix itself is imported only as a
  # home-manager module in this repo, so it does not declare NixOS-level
  # `options.sops`). Tests stub vars-helper via this module, so declare the
  # `sops` options consumed by system modules here — currently only
  # router/wireguard's `sops.secrets.<name>.restartUnits`.
  options.sops.secrets = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options.restartUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };
    });
    default = {};
  };
}
