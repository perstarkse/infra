{
  config.flake.nixosModules.router-dns = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    dnsCfg = cfg.dns;
    helpers = config.routerHelpers or {};
    zones = helpers.zones or [];
    lanSubnet = helpers.lanSubnet or cfg.lan.subnet;
    routerIp = helpers.routerIp or "${lanSubnet}.1";
    ulaPrefix = helpers.ulaPrefix or cfg.ipv6.ulaPrefix;
    inherit (cfg) services;
    internalSubnets = lib.concatMap (z: z.subnets) (lib.filter (z: z.kind != "wan") zones);
    enabled = cfg.enable && dnsCfg.enable;
    normalizeZone = z: let
      z' =
        if lib.hasSuffix "." z
        then z
        else "${z}.";
    in
      z';
    rawLocalZones = dnsCfg.localZones or [];
    localZones = let
      lst = rawLocalZones;
    in
      if lst == []
      then ["lan."]
      else lib.unique (map normalizeZone lst);
  in {
    config = lib.mkIf enabled {
      services.unbound = {
        enable = true;
        settings = {
          "remote-control" = {"control-enable" = true;};
          server = {
            interface = [
              "127.0.0.1"
              "::1"
              routerIp
              "${ulaPrefix}::1"
            ];
            "access-control" =
              [
                "127.0.0.0/8 allow"
                "::1 allow"
                "${ulaPrefix}::/64 allow"
              ]
              ++ (map (cidr: "${cidr} allow") internalSubnets)
              ++ [
                "0.0.0.0/0 refuse"
                "::0/0 refuse"
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
                      map (r: "\"${r.name}.${lz} IN A ${r.ip}\"")
                      (zone.dhcp.reservations or [])
                  )
                  zones
              )
              localZones
              ++ (map (service: "\"${service.name} IN A ${service.target}\"") services);
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
    };
  };
}
