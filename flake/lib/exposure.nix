{lib}: let
  enabledExposuresFor = machineName: machineConfig: let
    exposures = machineConfig.config.my.exposure.services or {};
    enabled = lib.filterAttrs (_: exposure: exposure.enable) exposures;
  in
    lib.mapAttrsToList (serviceName: exposure: {
      machine = machineName;
      service = serviceName;
      inherit (exposure) upstream;
      inherit (exposure) http;
      inherit (exposure) dns;
      inherit (exposure) router;
      inherit (exposure) firewall;
      inherit (exposure) renderedFrom;
    })
    enabled;

  mkExposureManifest = nixosConfigurations: let
    entries = lib.flatten (lib.mapAttrsToList enabledExposuresFor nixosConfigurations);
  in {
    exports = lib.filter (entry: entry.renderedFrom == null) entries;
    rendered = lib.filter (entry: entry.renderedFrom != null) entries;
  };

  mkRouterImportedExposures = {
    nixosConfigurations,
    routerImportCfg,
    defaultDnsTarget,
    routerName ? routerImportCfg.routerName or "",
    resolveBasicAuthSecret ? (_: null),
  }: let
    routerTargetAllowed = exposure:
      exposure.router.targets == [] || lib.elem routerName exposure.router.targets;

    applyVhostOverride = machineName: serviceName: vhost: let
      override = routerImportCfg.vhostOverrides."${machineName}.${serviceName}" or {};
      overrideBasicAuth = override.basicAuth or null;
      secretBasicAuth =
        if vhost.basicAuthSecret != null
        then resolveBasicAuthSecret vhost.basicAuthSecret
        else null;
      basicAuth =
        if overrideBasicAuth != null
        then overrideBasicAuth
        else secretBasicAuth;
    in
      vhost // lib.optionalAttrs (basicAuth != null) {inherit basicAuth;};

    mkImportedExposure = machineName: serviceName: exposure: let
      importedVhosts = map (applyVhostOverride machineName serviceName) exposure.http.virtualHosts;
    in {
      name = "${machineName}-${serviceName}";
      value = {
        renderedFrom = {
          machine = machineName;
          service = serviceName;
        };
        upstream =
          exposure.upstream
          // {
            host =
              if exposure.router.targetHost != null
              then exposure.router.targetHost
              else machineName;
          };
        http.virtualHosts = importedVhosts;
        dns.records =
          exposure.dns.records
          ++ map (vhost: {
            name = vhost.domain;
            target =
              if exposure.router.dnsTarget != null
              then exposure.router.dnsTarget
              else defaultDnsTarget;
          })
          (lib.filter (vhost: vhost.publishDns) importedVhosts);
        inherit (exposure) firewall;
      };
    };

    importsForMachine = machineName: let
      machineConfig = nixosConfigurations.${machineName}.config or {};
      exposures = machineConfig.my.exposure.services or {};
      routerExposures = lib.filterAttrs (_: exposure: exposure.enable && exposure.router.enable && routerTargetAllowed exposure) exposures;
    in
      lib.mapAttrsToList (mkImportedExposure machineName) routerExposures;
  in
    lib.listToAttrs (lib.concatMap importsForMachine routerImportCfg.machines);
in {
  inherit enabledExposuresFor mkExposureManifest mkRouterImportedExposures;
}
