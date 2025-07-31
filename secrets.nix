{
  lib,
  config,
  ...
}: let
  mkSecretGenerator = import ./vars/helpers.nix {inherit lib config;};

  secrets = [
    {
      name = "api-key-openai";
      type = "shared";
      fileName = "api_key";
    }
    {
      name = "api-key-openrouter";
      type = "shared";
      fileName = "api_key";
    }
    {
      name = "api-key-aws-access";
      type = "shared";
      fileName = "aws_access_key_id";
    }
    {
      name = "api-key-aws-secret";
      type = "shared";
      fileName = "aws_secret_access_key";
    }
    {
      name = "restic-env-file";
      type = "shared";
      fileName = "env";
      multiline = true;
    }
    {
      name = "restic-repo-file";
      type = "shared";
      fileName = "vault-name";
    }
    {
      name = "restic-password";
      type = "shared";
    }
    {
      name = "user-ssh-key";
      type = "shared";
      multiline = true;
      fileName = "id_ed25519";
    }
    {
      name = "user-ssh-key-pub";
      type = "shared";
      fileName = "id_ed25519.pub";
    }
    {
      name = "user-age-key";
      type = "shared";
      fileName = "keys.txt";
    }
    {
      name = "ddclient";
      type = "shared";
      fileName = "ddclient.conf";
      multiline = true;
    }
  ];

  generatorsList = lib.map mkSecretGenerator secrets;
in {
  clan.core.vars.generators = lib.mkMerge generatorsList;
}
