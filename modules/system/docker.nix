{
  config.flake.nixosModules.docker = {config,...}: {
    config = {
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
