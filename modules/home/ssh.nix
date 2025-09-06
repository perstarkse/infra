{
  config.flake.homeModules.ssh = {
    config,
    lib,
    ...
  }: {
    programs.ssh = {
      enable = true;
    };

    programs.keychain = {
      enable = true;
      agents = ["ssh"];
      keys = ["~/.ssh/id_ed25519"];
      extraFlags = ["--timeout" "180" "--quiet"];
      enableFishIntegration = true;
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
