{lib}: let
  enabledEndpointsFor = machineName: machineConfig: let
    endpoints = machineConfig.config.my.endpoints.services or {};
    enabled = lib.filterAttrs (_: endpoint: endpoint.enable) endpoints;
  in
    lib.mapAttrsToList (serviceName: endpoint: {
      machine = machineName;
      service = serviceName;
      inherit (endpoint) upstream;
      inherit (endpoint) http;
      inherit (endpoint) dns;
      inherit (endpoint) router;
      inherit (endpoint) firewall;
      inherit (endpoint) renderedFrom;
    })
    enabled;

  mkEndpointsManifest = nixosConfigurations: let
    entries = lib.flatten (lib.mapAttrsToList enabledEndpointsFor nixosConfigurations);
  in {
    exports = lib.filter (entry: entry.renderedFrom == null) entries;
    rendered = lib.filter (entry: entry.renderedFrom != null) entries;
  };

  mkRouterImportedEndpoints = {
    nixosConfigurations,
    routerImportCfg,
    defaultDnsTarget,
    routerName ? routerImportCfg.routerName or "",
    resolveBasicAuthSecret ? (_: null),
  }: let
    routerTargetAllowed = endpoint:
      endpoint.router.targets == [] || lib.elem routerName endpoint.router.targets;

    applyVhostOverride = machineName: serviceName: vhost: let
      override = routerImportCfg.vhostOverrides."${machineName}.${serviceName}" or {};
      overrideBasicAuth = override.basicAuth or null;
      overrideAcmeDns01 = override.acmeDns01 or null;
      secretBasicAuth =
        if vhost.basicAuthSecret != null
        then resolveBasicAuthSecret vhost.basicAuthSecret
        else null;
      basicAuth =
        if overrideBasicAuth != null
        then overrideBasicAuth
        else secretBasicAuth;
    in
      vhost
      // lib.optionalAttrs (basicAuth != null) {inherit basicAuth;}
      // lib.optionalAttrs (overrideAcmeDns01 != null) {acmeDns01 = overrideAcmeDns01;};

    mkImportedEndpoints = machineName: serviceName: endpoint: let
      importedVhosts = map (applyVhostOverride machineName serviceName) endpoint.http.virtualHosts;
    in {
      name = "${machineName}-${serviceName}";
      value = {
        renderedFrom = {
          machine = machineName;
          service = serviceName;
        };
        upstream =
          endpoint.upstream
          // {
            host =
              if endpoint.router.targetHost != null
              then endpoint.router.targetHost
              else machineName;
          };
        http.virtualHosts = importedVhosts;
        dns.records =
          endpoint.dns.records
          ++ map (vhost: {
            name = vhost.domain;
            target =
              if endpoint.router.dnsTarget != null
              then endpoint.router.dnsTarget
              else defaultDnsTarget;
          })
          (lib.filter (vhost: vhost.publishDns) importedVhosts);
        inherit (endpoint) firewall;
      };
    };

    importsForMachine = machineName: let
      machineConfig = nixosConfigurations.${machineName}.config or {};
      endpoints = machineConfig.my.endpoints.services or {};
      routerEndpoints = lib.filterAttrs (_: endpoint: endpoint.enable && endpoint.router.enable && routerTargetAllowed endpoint) endpoints;
    in
      lib.mapAttrsToList (mkImportedEndpoints machineName) routerEndpoints;
  in
    lib.listToAttrs (lib.concatMap importsForMachine routerImportCfg.machines);
in {
  inherit enabledEndpointsFor mkEndpointsManifest mkRouterImportedEndpoints;
}
