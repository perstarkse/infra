{
  config.flake.nixosModules.atuin = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.atuin;
    atuinConfig = pkgs.writeText "atuin-config.toml" ''
      auto_sync = true
      sync_address = "${cfg.syncAddress}"
      sync_frequency = "5m"
      style = "compact"
      inline_height = 20
      show_help = false

      # Search settings
      search_mode = "fuzzy"
      filter_mode = "global"
      filter_mode_shell_up_key_binding = "session"

      # Security - auto-filter commands that look like secrets
      secrets_filter = true

      # Workspaces - filter by git repo when in one
      workspaces = true

      # Enter puts command in prompt (safer - lets you review before running)
      enter_accept = false
    '';
  in {
    options.my.atuin = {
      enable = lib.mkEnableOption "Enable Atuin shell history";

      syncAddress = lib.mkOption {
        type = lib.types.str;
        default = "https://atuin.lan.stark.pub";
        description = "Atuin sync server address";
      };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [pkgs.atuin];

      environment.etc."atuin/config.toml".source = atuinConfig;

      programs.fish.interactiveShellInit = ''
        if test -f /etc/atuin/config.toml
          set -gx ATUIN_CONFIG_DIR /etc/atuin
        end
        atuin init fish --disable-up-arrow | source
      '';
    };
  };
}
