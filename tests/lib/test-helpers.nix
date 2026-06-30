_: let
  versions = import ../../flake/lib/versions.nix;

  unwrapSingletonImports = m:
    if builtins.isAttrs m && m ? imports && builtins.length m.imports == 1
    then unwrapSingletonImports (builtins.elemAt m.imports 0)
    else m;

  mkRouterModule = nixosModules: let
    unwrapped = unwrapSingletonImports nixosModules.router;
  in
    if builtins.isFunction unwrapped
    then unwrapped {ctx.flake.nixosModules = nixosModules;}
    else nixosModules.router;

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
  inherit unwrapSingletonImports mkRouterModule mkCommonNode mkUnfreePkgs;
}
