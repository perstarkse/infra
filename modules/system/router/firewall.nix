{
  config.flake.nixosModules.router-firewall = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    helpers = config.routerHelpers or {};
    lanSubnet = helpers.lanSubnet or cfg.lan.subnet;
    wan = helpers.wanInterface or cfg.wan.interface;

    machinesByName = lib.listToAttrs (map (m: lib.nameValuePair m.name m) cfg.machines);
    forwardRules = lib.concatStringsSep "\n" (lib.mapAttrsToList (
        _: machine:
          lib.concatStringsSep "\n" (map (
              pf: "iifname \"${wan}\" oifname \"br-lan\" ip daddr ${lanSubnet}.${machine.ip} ${pf.protocol} dport ${toString pf.port} accept"
            )
            machine.portForwards)
      )
      machinesByName);
    dnatRules = lib.concatStringsSep "\n" (lib.mapAttrsToList (
        _: machine:
          lib.concatStringsSep "\n" (map (
              pf: "iifname \"${wan}\" ${pf.protocol} dport ${toString pf.port} dnat to ${lanSubnet}.${machine.ip}"
            )
            machine.portForwards)
      )
      machinesByName);

    wgEnabled = cfg.wireguard.enable or false;
    wgInterface = cfg.wireguard.interfaceName or "wg0";
    wgPort = toString (cfg.wireguard.listenPort or 51820);
  in {
    config = lib.mkIf cfg.enable {
      networking.nftables = {
        enable = true;
        tables = {
          filterV4 = {
            family = "ip";
            content = ''
              chain input {
                type filter hook input priority 0; policy drop;
                iifname "lo" accept
                iifname "br-lan" accept
                iifname "cni0" accept
                ${lib.optionalString wgEnabled "iifname \"${wgInterface}\" accept"}
                iifname "${wan}" ct state established,related accept
                iifname "${wan}" ip protocol icmp accept
                iifname "${wan}" tcp dport { 80, 443 } accept
                ${lib.optionalString wgEnabled "iifname \"${wan}\" udp dport ${wgPort} accept"}
              }
              chain forward {
                type filter hook forward priority 0; policy drop;
                iifname "br-lan" oifname "${wan}" accept
                iifname "br-lan" oifname "br-lan" accept
                iifname "cni0" oifname "${wan}" accept
                iifname "cni0" oifname "br-lan" accept
                iifname "${wan}" oifname "br-lan" ct state established,related accept
                iifname "${wan}" oifname "cni0" ct state established,related accept
                ${forwardRules}
                ${lib.optionalString wgEnabled "iifname \"${wgInterface}\" oifname \"br-lan\" accept"}
                ${lib.optionalString wgEnabled "iifname \"br-lan\" oifname \"${wgInterface}\" accept"}
                ${lib.optionalString wgEnabled "iifname \"${wgInterface}\" oifname \"${wan}\" accept"}
                ${lib.optionalString wgEnabled "iifname \"cni0\" oifname \"${wgInterface}\" accept"}
                ${lib.optionalString wgEnabled "iifname \"${wgInterface}\" oifname \"cni0\" accept"}
              }
            '';
          };
          natV4 = {
            family = "ip";
            content = ''
              chain prerouting {
                type nat hook prerouting priority -100;
                ${dnatRules}
              }
              chain postrouting {
                type nat hook postrouting priority 100;
                oifname "${wan}" masquerade
              }
            '';
          };
          filterV6 = {
            family = "ip6";
            content = ''
              chain input {
                type filter hook input priority 0; policy drop;
                iifname "lo" accept
                iifname "br-lan" accept
                iifname "zt*" accept
                ${lib.optionalString wgEnabled "iifname \"${wgInterface}\" accept"}
                iifname "${wan}" ct state established,related accept
                iifname "${wan}" icmpv6 type {
                  destination-unreachable, packet-too-big, time-exceeded,
                  parameter-problem, nd-router-advert, nd-neighbor-solicit,
                  nd-neighbor-advert
                } accept
                iifname "${wan}" udp dport dhcpv6-client udp sport dhcpv6-server accept
                ${lib.optionalString wgEnabled "iifname \"${wan}\" udp dport ${wgPort} accept"}
              }
              chain forward {
                type filter hook forward priority 0; policy drop;
                iifname "br-lan" oifname "${wan}" accept
                iifname "${wan}" oifname "br-lan" ct state established,related accept
                iifname "zt*" oifname "br-lan" accept
                iifname "br-lan" oifname "zt*" accept
              }
            '';
          };
        };
      };
    };
  };
}
