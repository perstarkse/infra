{
  config.flake.nixosModules.sunshine = {
    config = {
      hardware.uinput.enable = true;
      users.users.p = {
        extraGroups = ["uinput"];
      };

      services.sunshine = {
        enable = true;
        autoStart = false;
        capSysAdmin = true;
        openFirewall = true;
        applications = {
        };
      };
    };
  };
}
