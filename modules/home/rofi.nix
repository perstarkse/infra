{
  config.flake.homeModules.rofi = {
    pkgs,
    config,
    lib,
    ...
  }: {
    options.my.programs.rofi.withRbw = lib.mkEnableOption "Enable rofi-rbw-wayland plugin";

    config = {
      programs.rofi = {
        enable = true;
        terminal = "${pkgs.kitty}/bin/kitty";
        plugins = with pkgs; [rofi-calc rofi-emoji];
      };

      home.packages = lib.mkIf config.my.programs.rofi.withRbw [
        pkgs.rofi-rbw-wayland
      ];
    };
  };
}
