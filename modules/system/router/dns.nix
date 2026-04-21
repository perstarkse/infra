{
  config.flake.nixosModules.router-dns = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.router;
    dnsCfg = cfg.dns;
    helpers = config.routerHelpers or {};
    zones = helpers.zones or [];
    segments = helpers.segments or [];
    primarySegment = helpers.primarySegment or null;
    routerIp = if primarySegment != null then primarySegment.routerIp else "${cfg.segments.${cfg.primarySegment}.subnet}.1";
    ulaPrefix = helpers.ulaPrefix or cfg.ipv6.ulaPrefix;
    inherit (cfg) services;
    listenerIps = map (segment: segment.routerIp) segments;
    enabled = cfg.enable && dnsCfg.enable;
    normalizeZone = z:
      if lib.hasSuffix "." z then z else "${z}.";
    rawLocalZones = dnsCfg.localZones or [];
    localZones =
      if rawLocalZones == []
      then ["lan."]
      else lib.unique (map normalizeZone rawLocalZones);
    isIPv4Literal = s: builtins.match "^[0-9]{1,3}(\.[0-9]{1,3}){3}$" s != null;
    normalizeFqdn = host:
      if lib.hasSuffix "." host then host else "${host}.";
    mkServiceRecord = service:
      if isIPv4Literal service.target
      then "\"${service.name} IN A ${service.target}\""
      else "\"${service.name} IN CNAME ${normalizeFqdn service.target}\"";

    blockyPort = 53;
    blockyHttpPort = 4000;
    unboundPort = 5354;
    unboundListen = ["127.0.0.1" "::1"];

    mkInlineSourceEntries = domains:
      if domains == []
      then []
      else [((lib.concatStringsSep "\n" domains) + "\n")];

    profileDenyDomains = lib.mapAttrs (
      _name: profile:
        profile.denyDomains
    ) dnsCfg.profiles;

    protectedDohProfiles = lib.unique (map (
      segment: segment.dnsProfile
    ) (lib.filter (
      segment:
        dnsCfg.dohBlocking.enable
        && !(lib.elem segment.name dnsCfg.dohBlocking.exemptSegments)
    ) segments));

    effectiveProfileDenyDomains = lib.mapAttrs (
      name: domains:
        domains ++ lib.optionals (lib.elem name protectedDohProfiles) dnsCfg.dohBlocking.denyDomains
    ) profileDenyDomains;

    blockyDenyLists = lib.mapAttrs (
      name: profile:
        profile.blocklistSources ++ (mkInlineSourceEntries effectiveProfileDenyDomains.${name})
    ) dnsCfg.profiles;

    blockyClientGroups =
      {
        default = ["default"];
      }
      // lib.listToAttrs (map (
        segment:
          lib.nameValuePair segment.subnetCidr [segment.dnsProfile]
      ) segments);

    blockyBootstrapDns = [
      {upstream = "1.1.1.1";}
      {upstream = "1.0.0.1";}
    ];

    blockyPorts =
      {
        dns = map (ip: "${ip}:${toString blockyPort}") listenerIps ++ ["127.0.0.1:${toString blockyPort}"];
        http = ["127.0.0.1:${toString blockyHttpPort}"];
      }
      // lib.optionalAttrs (primarySegment != null) {
        dns = map (ip: "${ip}:${toString blockyPort}") listenerIps ++ [
          "127.0.0.1:${toString blockyPort}"
          "[${ulaPrefix}::1]:${toString blockyPort}"
        ];
      };
  in {
    config = lib.mkIf enabled {
      services.unbound = {
        enable = true;
        settings = {
          "remote-control" = {"control-enable" = true;};
          server = {
            interface = unboundListen;
            port = unboundPort;
            "access-control" = [
              "127.0.0.0/8 allow"
              "::1 allow"
            ];
            "cache-min-ttl" = 0;
            "cache-max-ttl" = 86400;
            "do-tcp" = true;
            "do-udp" = true;
            prefetch = true;
            "num-threads" = 1;
            "so-reuseport" = true;
            "local-zone" = map (z: "\"${z}\" static") localZones;
            "local-data" =
              lib.concatMap
              (
                lz:
                  [
                    "\"${cfg.hostname}.${lz} IN A ${routerIp}\""
                    "\"${cfg.hostname}.${lz} IN AAAA ${ulaPrefix}::1\""
                  ]
                  ++ lib.concatMap (
                    zone:
                      map (r: "\"${r.name}.${lz} IN A ${r.ip}\"") (zone.dhcp.reservations or [])
                  )
                  zones
              )
              localZones
              ++ map mkServiceRecord services;
          };
          "forward-zone" = [
            {
              name = ".";
              "forward-addr" = dnsCfg.upstreamServers;
              "forward-tls-upstream" = true;
            }
          ];
        };
      };

      services.blocky = {
        enable = true;
        settings = {
          ports = blockyPorts // {dohPath = "/dns-query";};
          log = {
            level = "info";
            privacy = true;
          };
          upstreams = {
            init.strategy = "blocking";
            strategy = "parallel_best";
            groups.default = ["127.0.0.1:${toString unboundPort}"];
          };
          bootstrapDns = blockyBootstrapDns;
          blocking = {
            denylists = blockyDenyLists;
            clientGroupsBlock = blockyClientGroups;
            blockType = dnsCfg.blocking.blockType;
            blockTTL = dnsCfg.blocking.blockTTL;
            loading = {
              strategy = dnsCfg.blocking.loadingStrategy;
              refreshPeriod = dnsCfg.blocking.refreshPeriod;
            };
          };
          customDNS = {
            customTTL = "1h";
            filterUnmappedTypes = false;
          };
          caching = {
            minTime = "0";
            maxTime = "24h";
            prefetching = true;
            cacheTimeNegative = "30m";
          };
          specialUseDomains.enable = false;
          prometheus = {
            enable = true;
            path = "/metrics";
          };
        };
      };

      systemd.services.blocky = {
        after = ["unbound.service"];
        requires = ["unbound.service"];
        serviceConfig = {
          StateDirectoryMode = "0750";
        };
      };
    };
  };
}
