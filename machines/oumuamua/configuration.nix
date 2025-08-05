{
  modules,
  private-infra,
  config,
  pkgs,
  ...
}: {
  imports = with modules.nixosModules;
    [
      ./../../secrets.nix
      home-module
      options
      shared
      interception-tools
      system-stylix
      user-ssh-keys
      user-age-key
      surrealdb
      minne
    ]
    ++ (with private-infra.nixosModules; [hello-service]);

  home-manager.users.${config.my.mainUser.name} = {
    imports = with modules.homeModules; [
      options
      helix
      git
      direnv
      fish
      zellij
      starship
      ssh
    ];
    # ++ (with private-infra.homeModules; [
    #   sops-infra
    # ]);
    my = {
      secrets = config.my.sharedSecretPaths;

      programs = {
        helix = {
          languages = ["nix" "markdown"];
        };
      };
    };

    home.stateVersion = "25.11";
  };

  my.mainUser.name = "p";

  my.userSecrets = [
    "api-key-openai/api_key"
    "api-key-openrouter/api_key"
    "api-key-aws-access/aws_access_key_id"
    "api-key-aws-secret/aws_secret_access_key"
  ];

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
