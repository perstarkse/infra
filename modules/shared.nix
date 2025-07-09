{
  config.flake.nixosModules.shared = {
    config,
    clan-core,
    ...
  }: {
    imports = [
      clan-core.clanModules.sshd
      clan-core.clanModules.root-password
      clan-core.clanModules.user-password
    ];
    services.avahi.enable = true;
    clan.user-password.user = "user";
    users.users.user = {
      isNormalUser = true;
      extraGroups = ["wheel" "networkmanager" "video" "input"];
      uid = 1000;
      openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
    };
  };
}
