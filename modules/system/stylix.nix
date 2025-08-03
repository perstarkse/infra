{inputs, ...}: {
  config.flake.nixosModules.system-stylix = {pkgs, ...}: {
    imports = [
      inputs.stylix.nixosModules.stylix
    ];
    stylix = {
      enable = true;
      autoEnable = true;
      polarity = "dark";
      base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-frappe.yaml";
      image = ../../wallpaper.jpg;
      fonts = {
        sizes = {
          terminal = 8;
          applications = 9;
          popups = 9;
          desktop = 9;
        };
        monospace = {
          package = pkgs.nerd-fonts.fira-code;
          name = "FiraCode Nerd Font";
        };
        sansSerif = {
          package = pkgs.dejavu_fonts;
          name = "DejaVu Sans";
        };
        serif = {
          package = pkgs.dejavu_fonts;
          name = "DejaVu Serif";
        };
      };
      cursor = {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Classic";
        size = 18;
      };
    };
    # services.libinput = {
    #   mouse.accelProfile = "flat";
    # };
  };
}
