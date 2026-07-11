{
  config.flake.homeModules.starship = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.starship;
  in {
    options.my.starship.enable = lib.mkEnableOption "starship prompt with fish integration";

    config = lib.mkIf cfg.enable {
      programs.starship = {
        enable = true;
        enableFishIntegration = true;
        settings = {
          add_newline = false;

          character = {
            success_symbol = "[➜](bold green)";
            error_symbol = "[✗](bold red)";
          };

          cmd_duration = {
            min_time = 500;
            format = "took [$duration]($style)";
          };
          directory = {
            truncation_length = 3;
            truncate_to_repo = false;
          };
          hostname = {
            ssh_only = true;
            format = "at [$hostname]($style) ";
          };
          username = {
            format = "[$user]($style) ";
            show_always = false;
          };

          git_branch = {
            format = "[$symbol$branch]($style) ";
          };

          nix_shell = {
            disabled = false;
            format = "via [☃️ $state( \\($name\\))](bold blue) ";
          };
        };
      };
    };
  };
}
