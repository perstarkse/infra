{
  config.flake.homeModules.fish = {
    programs.fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting
      '';
      # interactiveShellInit = ''
      #   set fish_greeting
      #   set -gx OPENAI_API_KEY (cat ${config.sops.secrets."api_keys/openai".path})
      #   set -gx OPENROUTER_API_KEY (cat ${config.sops.secrets."api_keys/openrouter".path})
      #   set -gx AWS_ACCESS_KEY_ID (cat ${config.sops.secrets."api_keys/aws/access".path})
      #   set -gx AWS_SECRET_ACCESS_KEY (cat ${config.sops.secrets."api_keys/aws/secret".path})
      # '';
    };
  };
}
