{
  config.flake.homeModules.ssh = {...}: {
    programs.ssh = {
      enable = true;
      # Silence HM deprecation warning about default config removal
      enableDefaultConfig = false;
    };

    # programs.keychain = {
    #   enable = true;
    #   keys = ["~/.ssh/id_ed25519"];
    #   extraFlags = ["--timeout" "180" "--quiet"];
    #   enableFishIntegration = true;
    # };

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
