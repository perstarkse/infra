{
  lib,
  config,
  ...
}: let
  mkSecretGenerator = import ../../vars/helpers.nix {inherit lib config;};

  secrets = [
    {
      name = "mail-gmail-1-password";
      type = "shared";
    }
    {
      name = "mail-personal-1-password";
      type = "shared";
    }
    # {
    #   name = "test";
    #   type = "shared";
    # }
    # {
    #   name = "some-service-private-key";
    #   type = "user";
    #   fileName = "id_rsa";
    #   multiline = true;
    # }
    # {
    #   name = "some-api-key";
    #   type = "shared";
    #   fileName = "api_key";
    # }
    # Add new secrets here
  ];

  generatorsList =
    lib.map
    (secret: mkSecretGenerator secret.name secret)
    secrets;
in {
  clan.core.vars.generators = lib.mkMerge generatorsList;
}
