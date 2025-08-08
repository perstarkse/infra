{
  modules,
  private-infra,
  config,
  pkgs,
  vars-helper,
  ...
}: {
  imports = with modules.nixosModules;
    [
      home-module
      options
      shared
      interception-tools
      system-stylix
      # user-ssh-keys
      # user-age-key
      surrealdb
      minne
    ] ++ (with vars-helper.nixosModules; [default]);
    # ++ (with private-infra.nixosModules; [hello-service]);

  # home-manager.users.${config.my.mainUser.name} = {
  #   imports = with modules.homeModules; [
  #     options
  #     helix
  #     git
  #     direnv
  #     fish
  #     zellij
  #     starship
  #     ssh
  #   ]
  #   ++ (with private-infra.homeModules; [
  #     sops-infra
  #   ]);
  #   my = {
  #     secrets = config.my.sharedSecretPaths;

  #     programs = {
  #       helix = {
  #         languages = ["nix" "markdown"];
  #       };
  #     };
  #   };

  #   home.stateVersion = "25.11";
  # };

  my.mainUser.name = "p";

  # Auto-discover secrets generators for this machine
  my.secrets.discover = {
    enable = true;
    dir = ../../vars/generators;
    # Import all generators in this dir; filter by tags elsewhere if needed
    includeTags = [ "oumuamua" ];
  };

  # Expose SurrealDB credentials to the surrealdb user
  my.secrets.exposeUserSecret = {
    enable = true;
    secretName = "surrealdb-credentials";
    file = "credentials";
    user = "surrealdb";
    dest = "/var/lib/surrealdb/credentials.env";
    mode = "0400";
  };

  time.timeZone = "Europe/Stockholm";

  clan.core.networking.zerotier.controller.enable = true;

  # SurrealDB configuration
  my.surrealdb = {
    enable = true;
    host = "127.0.0.1";
    port = 8220;
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

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = [
    # pkgs.epy
  ];
}
