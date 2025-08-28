{
  config.flake.homeModules.rofi = {
    pkgs,
    config,
    lib,
    osConfig,
    ...
  }: {
    options.my.programs.rofi.withRbw = lib.mkEnableOption "Enable rofi-rbw-wayland plugin";

    config = {
      programs.rofi = {
        enable = true;
        terminal = osConfig.my.gui._terminalCommand;
        plugins = with pkgs; [rofi-calc rofi-emoji];
      };

      home.packages = lib.mkIf config.my.programs.rofi.withRbw [
        pkgs.rofi-rbw-wayland
      ];
    };
  };
}
