{
  config.flake.nixosModules.sunshine = {pkgs, ...}: {
    config = {
      hardware.uinput.enable = true;
      # systemd.user.services.sunshine.serviceConfig = {
      #   DevicePolicy = "auto"; # or "closed" with explicit allows
      #   DeviceAllow = ["/dev/uinput rw"]; # add /dev/dri/* here if needed
      # };
      users.users.p = {
        extraGroups = ["uinput"]; # Enable ‘sudo’ for the user.
        #   packages = with pkgs; [
        #     tree
        #   ];
      };

      services.sunshine = {
        enable = true;
        autoStart = false;
        capSysAdmin = true;
        # capSysAdmin = false;
        openFirewall = true;
        applications = {
          # env = {
          #   PATH = "${pkgs.steam}/bin:${pkgs.gamescope}/bin:${pkgs.coreutils}/bin";
          # };

          # apps = [
          #   {
          #     name = "Steam Big Picture (1080p)";
          #     prep-cmd = [
          #       {
          #         do = "${pkgs.gamescope}/bin/gamescope -- ${pkgs.steam}/bin/steam";
          #       }
          #     ];
          #   }
          # ];
        };
      };
    };
  };
}
