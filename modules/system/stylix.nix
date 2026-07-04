{inputs, ...}: {
  config.flake.nixosModules.system-stylix = {
    pkgs,
    lib,
    ...
  }: {
    imports = [
      inputs.stylix.nixosModules.stylix
    ];

    # Upstream stylix (>= 718c14e) sets services.kmscon.config, which nixpkgs
    # 26.05 does not expose yet (only extraConfig/fonts).
    options.services.kmscon.config = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };

    config.stylix = {
      enable = true;
      autoEnable = true;
      polarity = "dark";
      enableReleaseChecks = false;
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
