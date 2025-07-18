{
  config.flake.homeModules.ssh = {
    config,
    lib,
    ...
  }: {
    programs.ssh = {
      enable = true;
      forwardAgent = true;
      addKeysToAgent = "yes";
    };

    services.ssh-agent.enable = true;
  };
}
