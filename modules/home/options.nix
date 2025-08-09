{
  config.flake.homeModules.options = {lib, osConfig, ...}: {
    options.my.secrets = lib.mkOption {
      type = lib.types.anything;
      default = (osConfig.my.secrets or {});
      description = "Secrets from the system configuration, exposed to Home Manager. This is intentionally untyped to allow helper functions like getPath.";
    };
  };
}
