{
  config.flake.homeModules.rofi = {
    pkgs,
    config,
    lib,
    osConfig,
    ...
  }: let
    cfg = config.my.rofi;
  in {
    options.my.rofi = {
      enable = lib.mkEnableOption "rofi launcher";
      withRbw = lib.mkEnableOption "Enable rofi-rbw-wayland plugin";
    };

    config = lib.mkIf cfg.enable {
      programs.rofi = {
        enable = true;
        terminal = osConfig.my.gui._terminalCommand;
        plugins = with pkgs; [rofi-calc rofi-emoji];
      };

      home.packages = lib.mkIf cfg.withRbw [
        pkgs.rofi-rbw-wayland
      ];
    };
  };
}
