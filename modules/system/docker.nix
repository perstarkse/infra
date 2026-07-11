{
  config.flake.nixosModules.docker = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.docker;
  in {
    options.my.docker.enable = lib.mkEnableOption "Docker daemon";
    config = lib.mkIf cfg.enable {
      virtualisation.docker = {
        enable = true;
        rootless.enable = false;
        autoPrune.enable = true;
      };
      users.users.${config.my.mainUser.name} = {
        extraGroups = ["docker"];
      };
    };
  };
}
