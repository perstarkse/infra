{
  config.flake.homeModules.options = {
    lib,
    osConfig,
    ...
  }: {
    options.my.secrets = lib.mkOption {
      type = lib.types.submodule {
        freeformType = lib.types.attrsOf lib.types.anything;
      };
      default = osConfig.my.secrets or {};
      description = "Secrets from the system configuration, exposed to Home Manager. This is intentionally permissive and supports nested options like my.secrets.wrappedHomeBinaries.";
    };
  };
}
