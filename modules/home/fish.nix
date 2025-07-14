{
  config.flake.homeModules.fish = {
    config,
    pkgs,
    ...
  }: {
    programs.fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting
        set -gx OPENAI_API_KEY (${pkgs.coreutils}/bin/cat ${config.my.secrets."api-key-openai/api_key"})
        set -gx OPENROUTER_API_KEY (${pkgs.coreutils}/bin/cat ${config.my.secrets."api-key-openrouter/api_key"})
        set -gx AWS_ACCESS_KEY_ID (${pkgs.coreutils}/bin/cat ${config.my.secrets."api-key-aws-access/aws_access_key_id"})
        set -gx AWS_SECRET_ACCESS_KEY (${pkgs.coreutils}/bin/cat ${config.my.secrets."api-key-aws-secret/aws_secret_access_key"})
      '';
    };
  };
}
