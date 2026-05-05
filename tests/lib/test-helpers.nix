_: let
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
    stateVersion ? "25.11",
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
in {
  inherit unwrapSingletonImports mkRouterModule mkCommonNode;
}
