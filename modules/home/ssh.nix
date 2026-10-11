{
  config.flake.homeModules.ssh = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.ssh;
  in {
    options.my.ssh.enable = lib.mkEnableOption "ssh client config + ssh-agent";

    config = lib.mkIf cfg.enable {
      programs.ssh = {
        enable = true;
        # Silence HM deprecation warning about default config removal
        enableDefaultConfig = false;
      };

      home.file.".ssh/config" = {
        text = ''
          # Per-host blocks live in conf.d/ (e.g. a tool that needs its own
          # IdentityFile). Included first so a specific Host can be overridden
          # by anything the user drops in later.
          Include ~/.ssh/conf.d/*

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
  };
}
