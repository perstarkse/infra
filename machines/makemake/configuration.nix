{
  modules,
  config,
  pkgs,
  ...
}: {
  imports = with modules.nixosModules;
    [
      ../../secrets.nix
      ./hardware-configuration.nix
      ./boot.nix
      options
      shared
      interception-tools
      system-stylix
      docker
      vaultwarden
      openwebui
      surrealdb
      minne
    ];

  my.mainUser = {
    name = "p";
  };


  time.timeZone = "Europe/Stockholm";

  environment.systemPackages = with pkgs; [
    devenv
  ];

  my.vaultwarden = {
    port = 8322;
    address = "10.0.0.10";
  };

  my.openwebui = {
    port = 7909;
    autoUpdate = true;
    updateSchedule = "weekly";
  };

  # SurrealDB configuration
  my.surrealdb = {
    enable = true;
    host = "127.0.0.1";
    port = 8220;
    credentialsFile = config.my.secrets."surrealdb/credentials";
    dataDir = "/var/lib/surrealdb";
  };

  # Minne configuration
  my.minne = {
    enable = true;
    port = 3000;
    address = "0.0.0.0";
    dataDir = "/var/lib/minne";
    
    surrealdb = {
      host = "127.0.0.1";
      port = 8220;
    };

    logLevel = "info";
  };

  # Add secrets for Minne and SurrealDB
  my.userSecrets = [
    "minne/env"
    "surrealdb/credentials"
  ];
} 