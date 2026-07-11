{
  config.flake.nixosModules.sunshine = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.sunshine;
  in {
    options.my.sunshine.enable = lib.mkEnableOption "Sunshine game streaming host";
    config = lib.mkIf cfg.enable {
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
