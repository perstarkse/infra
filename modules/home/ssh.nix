{
  config.flake.homeModules.ssh = {
    config,
    lib,
    ...
  }: {
    programs.ssh = {
      enable = true;
    };

    home.file.".ssh/config" = {
      text = ''
        Host *
          ForwardAgent yes
          AddKeysToAgent yes
          Compression no
          ServerAliveInterval 0
          ServerAliveCountMax 3
          HashKnownHosts no
          UserKnownHostsFile ~/.ssh/known_hosts
          ControlMaster no
          ControlPath ~/.ssh/master-%r@%n:%p
          ControlPersist no
      '';
    };

    services.ssh-agent.enable = true;
  };
}
