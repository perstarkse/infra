{
  getPathDefault,
  withDiscover ? false,
  withAllowReadAccess ? false,
  withGenerateManifest ? false,
  mkMachineSecretDefault ? (_: {}),
  ...
}: {lib, ...}: {
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
