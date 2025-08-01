{
  config.flake.nixosModules.dns = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.dns;
    routerCfg = config.my.router;
    lanSubnet = routerCfg.lanSubnet;
    routerIp = "${lanSubnet}.1";
    ulaPrefix = routerCfg.ulaPrefix;
    lanCidr = "${lanSubnet}.0/24";
  in {
    options.my.dns = {
      enable = lib.mkEnableOption "Enable DNS server (Unbound)";

      upstreamServers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "1.1.1.1@853#cloudflare-dns.com"
          "1.0.0.1@853#cloudflare-dns.com"
          "2606:4700:4700::1111@853#cloudflare-dns.com"
          "2606:4700:4700::1001@853#cloudflare-dns.com"
        ];
        description = "Upstream DNS servers with TLS";
      };

      localZone = lib.mkOption {
        type = lib.types.str;
        default = "lan.";
        description = "Local DNS zone name";
      };
    };

    config = lib.mkIf cfg.enable {
      services.unbound = {
        enable = true;
        settings = {
          remote-control = {
            control-enable = true;
          };
          server = {
            interface = [
              "127.0.0.1"
              "::1"
              routerIp
              "${ulaPrefix}::1"
            ];
            access-control = [
              "127.0.0.0/8 allow"
              "::1 allow"
              "${lanCidr} allow"
              "${ulaPrefix}::/64 allow"
              "0.0.0.0/0 refuse"
              "::0/0 refuse"
            ];
            cache-min-ttl = 0;
            cache-max-ttl = 86400;
            do-tcp = true;
            do-udp = true;
            prefetch = true;
            num-threads = 1;
            so-reuseport = true;
            local-zone = ''"${cfg.localZone}" static'';
            local-data = [
              # Router
              ''"io.${cfg.localZone} IN A ${routerIp}"''
              ''"io.${cfg.localZone} IN AAAA ${ulaPrefix}::1"''

              # Machines
              lib.concatStringsSep
              "\n"
              (map (
                  machine: ''"${machine.name}.${cfg.localZone} IN A ${lanSubnet}.${machine.ip}"''
                )
                routerCfg.machines)

              # Services
              lib.concatStringsSep
              "\n"
              (map (
                  service: ''"${service.name} IN A ${service.target}"''
                )
                routerCfg.services)
            ];
          };
          forward-zone = [
            {
              name = ".";
              forward-addr = cfg.upstreamServers;
              forward-tls-upstream = true;
            }
          ];
        };
      };
    };
  };
}
