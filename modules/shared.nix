{
  config.flake.nixosModules.shared = {
    config,
    clan-core,
    lib,
    ...
  }: let
    mainUser = config.systemSettings.mainUser.name;
  in {
    imports = [
      clan-core.clanModules.sshd
      clan-core.clanModules.root-password
      clan-core.clanModules.user-password
    ];

    system.stateVersion = "25.11";

    services.avahi.enable = true;

    clan.user-password.user = mainUser;

    users.users.${mainUser} = {
      isNormalUser = true;
      extraGroups = ["wheel" "networkmanager" "video" "input"];
      uid = 1000;
      openssh.authorizedKeys.keys =
        # Combine root's keys with the user's extra keys
        config.users.users.root.openssh.authorizedKeys.keys
        ++ config.systemSettings.mainUser.extraSshKeys;
    };
  };
}
