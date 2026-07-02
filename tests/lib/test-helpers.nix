_: let
  versions = import ../../flake/lib/versions.nix;

  mkCommonNode = {
    stateVersion ? versions.stateVersion,
    extraPackages ? [],
  }: {
    networking = {
      useNetworkd = true;
      useDHCP = false;
      firewall.enable = false;
    };
    systemd.network.enable = true;
    system.stateVersion = stateVersion;
    environment.systemPackages = extraPackages;
  };

  mkUnfreePkgs = pkgs:
    import pkgs.path {
      localSystem = {inherit (pkgs.stdenv.hostPlatform) system;};
      config.allowUnfree = true;
    };
in {
  inherit mkCommonNode mkUnfreePkgs;
}
