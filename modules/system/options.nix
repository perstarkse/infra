{
  config.flake.nixosModules.options = {
    lib,
    config,
    ...
  }: {
    options = {
      systemSettings = {
        mainUser = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "The username of the primary user for this system.";
          };
          extraSshKeys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Additional SSH public keys for the main user.";
          };
        };

        userSecrets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "List of secrets to expose inside home-manager.";
        };

        sharedSecretPaths = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          readOnly = true;
          internal = true;
          description = "The derived map of secret name -> runtime path.";
        };
      };
    };

    config = {
      systemSettings.sharedSecretPaths = let
        gens = config.clan.core.vars.generators;
      in
        lib.listToAttrs (map
          (name: lib.nameValuePair name gens."${name}".files.password.path)
          config.systemSettings.userSecrets);
    };
  };
}
