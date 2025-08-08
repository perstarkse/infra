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
      '';
    };
    home.sessionVariables = {
      # OPENAI_API_KEY = "$(cat ${config.my.secrets."api-key-openai/api_key"})";
      # OPENROUTER_API_KEY = "$(cat ${config.my.secrets."api-key-openrouter/api_key"})";
      # AWS_ACCESS_KEY_ID = "$(cat ${config.my.secrets."api-key-aws-access/aws_access_key_id"})";
      # AWS_SECRET_ACCESS_KEY = "$(cat ${config.my.secrets."api-key-aws-secret/aws_secret_access_key"})";
    };
  };
}
