{
  config.flake.homeModules.options = {lib, ...}: {
    options.my.secrets = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      description = "A map of secret names to their runtime paths.";
    };
  };
}
