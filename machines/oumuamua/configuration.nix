{
  modules,
  private-infra,
  config,
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
      surrealdb
      minne
    ]
    ++ (with vars-helper.nixosModules; [default])
    ++ (with private-infra.nixosModules; [hello-service]);

  home-manager.users.${config.my.mainUser.name} = {
    imports = with modules.homeModules;
      [
        options
        sops
        helix
        git
        direnv
        fish
        zellij
        starship
        ssh
        mail-clients-setup
      ]
      ++ (with private-infra.homeModules; [
        mail-clients
      ]);
    my = {
      programs = {
        mail = {
          clients = ["aerc"];
        };
        helix = {
          languages = ["nix" "markdown"];
        };
      };
    };

    home.stateVersion = "25.11";
  };
  my = {
    mainUser.name = "p";
    secrets = {
      # Auto-discover secrets generators for this machine
      discover = {
        enable = true;
        dir = ../../vars/generators;
        includeTags = ["oumuamua" "user" "openrouter" "fish"];
      };

      exposeUserSecrets = [
        {
          enable = true;
          secretName = "user-ssh-key";
          file = "key";
          user = config.my.mainUser.name;
          group = "users";
          dest = "/home/${config.my.mainUser.name}/.ssh/id_ed25519";
        }
        {
          enable = true;
          secretName = "user-age-key";
          file = "key";
          user = config.my.mainUser.name;
          group = "users";
          dest = "/home/${config.my.mainUser.name}/.config/sops/age/keys.txt";
        }
      ];

      allowReadAccess = [
        {
          readers = [config.my.mainUser.name];
          path = config.my.secrets.getPath "api-key-openai" "api_key";
        }
        {
          readers = [config.my.mainUser.name];
          path = config.my.secrets.getPath "api-key-openrouter" "api_key";
        }
        {
          readers = [config.my.mainUser.name];
          path = config.my.secrets.getPath "api-key-aws-access" "aws_access_key_id";
        }
        {
          readers = [config.my.mainUser.name];
          path = config.my.secrets.getPath "api-key-aws-secret" "aws_secret_access_key";
        }
      ];
    };

    # SurrealDB configuration
    surrealdb = {
      enable = true;
      host = "127.0.0.1";
      port = 8220;
      dataDir = "/var/lib/surrealdb";
    };

    # Minne configuration
    minne = {
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
  };

  time.timeZone = "Europe/Stockholm";

  clan.core.networking.zerotier.controller.enable = true;

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = [
    # pkgs.epy
  ];
}
