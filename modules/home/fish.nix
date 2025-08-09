{
  config.flake.homeModules.fish = {
    config,
    lib,
    osConfig,
    pkgs,
    ...
  }: let
    secrets = osConfig.my.secrets or null;
    openaiKeyPath = if secrets != null then secrets.getPath "api-key-openai" "api_key" else null;
    openrouterKeyPath = if secrets != null then secrets.getPath "api-key-openrouter" "api_key" else null;
    awsAccessKeyPath = if secrets != null then secrets.getPath "api-key-aws-access" "aws_access_key_id" else null;
    awsSecretKeyPath = if secrets != null then secrets.getPath "api-key-aws-secret" "aws_secret_access_key" else null;
  in {
    programs.fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting
        # Export secrets if available
        ${lib.optionalString (openaiKeyPath != null) ''
        set -gx OPENAI_API_KEY (cat ${openaiKeyPath})
        ''}
        ${lib.optionalString (openrouterKeyPath != null) ''
        set -gx OPENROUTER_API_KEY (cat ${openrouterKeyPath})
        ''}
        ${lib.optionalString (awsAccessKeyPath != null) ''
        set -gx AWS_ACCESS_KEY_ID (cat ${awsAccessKeyPath})
        ''}
        ${lib.optionalString (awsSecretKeyPath != null) ''
        set -gx AWS_SECRET_ACCESS_KEY (cat ${awsSecretKeyPath})
        ''}
      '';
    };
  };
}
