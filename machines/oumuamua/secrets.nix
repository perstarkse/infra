{
  lib,
  config,
  ...
}: let
  mkSecretGenerator = import ../../vars/helpers.nix {inherit lib config;};

  secrets = [
    {
      name = "mail-gmail-perstark-password";
      type = "shared";
    }
    {
      name = "mail-gmail-sprlkhick-password";
      type = "shared";
    }
    {
      name = "mail-stark-per-password";
      type = "shared";
    }
    {
      name = "mail-stark-work-password";
      type = "shared";
    }
    {
      name = "mail-stark-services-password";
      type = "shared";
    }
    {
      name = "mail-disroot-mojotastic-password";
      type = "shared";
    }

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
      type = "root";
      fileName = "env";
      multiline = true;
    }
    {
      name = "restic-repo-file";
      type = "root";
      fileName = "vault-name";
    }
    {
      name = "restic-password";
      type = "root";
    }
  ];

  generatorsList = lib.map mkSecretGenerator secrets;
in {
  clan.core.vars.generators = lib.mkMerge generatorsList;
}
