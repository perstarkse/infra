{
  config.flake.nixosModules.options = {
    lib,
    config,
    ...
  }: {
    options = {
      my = {
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

        # secrets = lib.mkOption {
        #   type = lib.types.attrsOf lib.types.path;
        #   readOnly = true;
        #   internal = true;
        #   description = "A map of all available secrets, keyed as `secretName/fileName`, to their runtime paths.";
        # };

        # userSecrets = lib.mkOption {
        #   type = lib.types.listOf lib.types.str;
        #   default = [];
        #   description = "List of secrets from `my.secrets` (using `name/fileName` key) to expose to Home Manager.";
        #   example = ["restic-env-file/env" "api-key-openai/api_key"];
        # };

        # sharedSecretPaths = lib.mkOption {
        #   type = lib.types.attrsOf lib.types.path;
        #   readOnly = true;
        #   internal = true;
        #   description = "The derived map of secret name -> runtime path, filtered for Home Manager.";
        # };
      };
    };

    # config = {
    #   my.secrets = let
    #     listOfListsOfPairs =
    #       lib.mapAttrsToList (
    #         genName: gen:
    #           lib.mapAttrsToList (
    #             fileName: fileDef:
    #               lib.nameValuePair "${genName}/${fileName}" fileDef.path
    #           )
    #           gen.files
    #       )
    #       config.clan.core.vars.generators;
    #   in
    #     lib.listToAttrs (lib.flatten listOfListsOfPairs);

    #   my.sharedSecretPaths = lib.getAttrs config.my.userSecrets config.my.secrets;
    # };
  };
}
