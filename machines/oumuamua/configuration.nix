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
      sound
      options
      shared
      interception-tools
      system-stylix
      ledger
      user-ssh-keys
      user-age-key
    ]
    ++ (with private-infra.nixosModules; [hello-service]);

  home-manager.users.${config.my.mainUser.name} = {
    imports = with modules.homeModules;
      [
        options
        helix
        git
        direnv
        fish
        zellij
        starship
        mail-clients-setup
        ssh
      ]
      ++ (with private-infra.homeModules; [
        mail-clients
        sops-infra
        rbw
      ]);
    my = {
      secrets = config.my.sharedSecretPaths;

      programs = {
        mail = {
          clients = ["aerc"];
        };
        rbw = {
          pinentrySource = "tty";
        };
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

  environment.systemPackages = [
    # pkgs.epy
  ];
}
