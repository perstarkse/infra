{
  getPathDefault,
  withDiscover ? false,
  withAllowReadAccess ? false,
  withGenerateManifest ? false,
  mkMachineSecretDefault ? (_: {}),
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
}
