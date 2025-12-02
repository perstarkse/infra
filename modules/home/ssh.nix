{
  config.flake.homeModules.ssh = _: {
    programs.ssh = {
      enable = true;
      # Silence HM deprecation warning about default config removal
      enableDefaultConfig = false;
    };

    home.file.".ssh/config" = {
      text = ''
        Host *
          ForwardAgent no
          AddKeysToAgent yes
          Compression no
          ServerAliveInterval 0
          ServerAliveCountMax 3
          HashKnownHosts yes
          UserKnownHostsFile ~/.ssh/known_hosts
          ControlMaster no
          ControlPath ~/.ssh/master-%r@%n:%p
          ControlPersist no

        Match user root host localhost,127.0.0.1,::1
          ForwardAgent yes
      '';
    };

    services.ssh-agent.enable = true;
  };
}
