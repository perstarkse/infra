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
      # Only the interactive main user gets the docker group; on headless
      # servers (mainUser.enable = false) there is no user to grant it to.
      users.users.${config.my.mainUser.name} = lib.mkIf config.my.mainUser.enable {
        extraGroups = ["docker"];
      };
    };
  };
}
