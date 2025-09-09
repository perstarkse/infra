{
  config.flake.nixosModules.router-dns = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    dnsCfg = cfg.dns;
    helpers = config.routerHelpers or {};
    lanSubnet = helpers.lanSubnet or cfg.lan.subnet;
    routerIp = helpers.routerIp or "${lanSubnet}.1";
    ulaPrefix = helpers.ulaPrefix or cfg.ipv6.ulaPrefix;
    lanCidr = helpers.lanCidr or "${lanSubnet}.0/24";
    inherit (cfg) machines;
    inherit (cfg) services;
    wgSubnet = (cfg.wireguard or {}).subnet or "10.6.0";
    wgCidr = "${wgSubnet}.0/24";
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
            "access-control" = [
              "127.0.0.0/8 allow"
              "::1 allow"
              "${lanCidr} allow"
              "${ulaPrefix}::/64 allow"
              "${wgCidr} allow"
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
              ++ (map (machine: "\"${machine.name}.${dnsCfg.localZone} IN A ${lanSubnet}.${machine.ip}\"") machines)
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
