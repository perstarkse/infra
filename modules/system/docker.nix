{
  config.flake.nixosModules.docker = {config,...}: {
    config = {
      virtualisation.docker = {
        enable = true;
        rootless.enable = true;
        autoPrune.enable = true;
      };
      users.users.${config.my.mainUser.name} = {
        extraGroups = ["docker"];
      };
    };
  };
}
