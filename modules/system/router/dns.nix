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
            "local-zone" = "\"${dnsCfg.localZone}\" static";
            "local-data" =
              [
                "\"${cfg.hostname}.${dnsCfg.localZone} IN A ${routerIp}\""
                "\"${cfg.hostname}.${dnsCfg.localZone} IN AAAA ${ulaPrefix}::1\""
              ]
              ++ lib.concatMap (
                zone:
                  map (r: "\"${r.name}.${dnsCfg.localZone} IN A ${r.ip}\"")
                  (zone.dhcp.reservations or [])
              )
              zones
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
