{
  config.flake.nixosModules.router-firewall = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    helpers = config.routerHelpers or {};
    lanVlanId = helpers.lanVlanId or 1;
    lanInterface = helpers.lanInterface or "vlan${toString lanVlanId}";
    lanBridge = helpers.lanBridge or "br-lan";
    lanSubnet = helpers.lanSubnet or cfg.lan.subnet;
    zones = helpers.zones or [];
    wanZone = lib.findFirst (z: z.kind == "wan") null zones;
    wan =
      if wanZone != null
      then wanZone.interface
      else (helpers.wanInterface or cfg.wan.interface);
    internalZones = lib.filter (z: z.kind != "wan") zones;
    zoneMap = lib.listToAttrs (map (z: lib.nameValuePair z.name z) internalZones);
    lanZone = lib.attrByPath ["lan"] null zoneMap;
    lanZoneInterface =
      if lanZone != null
      then lanZone.interface
      else lanInterface;

    expandProtocols = pf:
      if pf.protocol == "tcp udp"
      then ["tcp" "udp"]
      else [pf.protocol];

    portForwards =
      lib.concatMap (
        machine:
          lib.concatMap (
            pf:
              map (
                protocol: {
                  inherit machine protocol;
                  inherit (pf) port;
                }
              ) (expandProtocols pf)
          )
          machine.portForwards
      )
      cfg.machines;

    forwardRules = lib.concatStringsSep "\n" (map (
        pfRule: "iifname \"${wan}\" oifname \"${lanZoneInterface}\" ip daddr ${lanSubnet}.${pfRule.machine.ip} ${pfRule.protocol} dport ${toString pfRule.port} accept"
      )
      portForwards);
    dnatRules = lib.concatStringsSep "\n" (map (
        pfRule: "iifname \"${wan}\" ${pfRule.protocol} dport ${toString pfRule.port} dnat to ${lanSubnet}.${pfRule.machine.ip}"
      )
      portForwards);

    wgEnabled = cfg.wireguard.enable or false;
    wgPort = toString (cfg.wireguard.listenPort or 51820);
    wanAllowedTcpRules = lib.concatStringsSep "\n" (map (port: "iifname \"${wan}\" tcp dport ${toString port} accept") (lib.unique cfg.wan.allowedTcpPorts));
    wanAllowedUdpRules = lib.concatStringsSep "\n" (map (port: "iifname \"${wan}\" udp dport ${toString port} accept") (lib.unique cfg.wan.allowedUdpPorts));

    inputInternalRules = lib.concatStringsSep "\n" (map (zone: "iifname \"${zone.interface}\" accept") internalZones);

    dropLanBridgeTaggedDhcpRules =
      if lanZoneInterface == lanBridge
      then
        lib.concatStringsSep "\n" (map (
            vlan: "iifname \"${lanBridge}\" vlan id ${toString vlan.id} udp dport 67 drop"
          )
          cfg.vlans)
      else "";

    forwardSameZoneRules = lib.concatStringsSep "\n" (map (zone: "iifname \"${zone.interface}\" oifname \"${zone.interface}\" accept") internalZones);

    forwardWanEgressRules = lib.concatStringsSep "\n" (map (
        zone: lib.optionalString (zone.wanEgress or false) "iifname \"${zone.interface}\" oifname \"${wan}\" accept"
      )
      internalZones);

    forwardWanReturnRules = lib.concatStringsSep "\n" (map (
        zone: "iifname \"${wan}\" oifname \"${zone.interface}\" ct state established,related accept"
      )
      internalZones);

    bridgeLanInputCompatRule =
      if lanZone != null && lanZone.interface != lanBridge
      then ''
        iifname "${lanBridge}" accept
      ''
      else "";

    bridgeLanForwardCompatRules =
      if lanZone != null && lanZone.interface != lanBridge
      then let
        bridgeAllowToRules = lib.concatStringsSep "\n" (map (
            targetName: let
              target = lib.attrByPath [targetName] null zoneMap;
            in
              if target == null
              then ""
              else "iifname \"${lanBridge}\" oifname \"${target.interface}\" accept"
          )
          (lanZone.allowTo or []));
      in ''
        iifname "${lanBridge}" oifname "${lanBridge}" accept
        ${lib.optionalString (lanZone.wanEgress or false) "iifname \"${lanBridge}\" oifname \"${wan}\" accept"}
        iifname "${wan}" oifname "${lanBridge}" ct state established,related accept
        ${bridgeAllowToRules}
      ''
      else "";

    forwardZoneAllowRules = lib.concatStringsSep "\n" (lib.concatMap (zone:
      map (
        targetName: let
          target = lib.attrByPath [targetName] null zoneMap;
        in
          if target == null
          then ""
          else "iifname \"${zone.interface}\" oifname \"${target.interface}\" accept"
      )
      (zone.allowTo or []))
    internalZones);

    forwardCommonRules = ''
      ct state established,related accept
      ${forwardSameZoneRules}
      ${forwardWanEgressRules}
      ${forwardWanReturnRules}
      ${bridgeLanForwardCompatRules}
      ${forwardZoneAllowRules}
    '';
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
                ${dropLanBridgeTaggedDhcpRules}
                ${bridgeLanInputCompatRule}
                ${inputInternalRules}
                iifname "${wan}" ct state established,related accept
                iifname "${wan}" ip protocol icmp accept
                iifname "${wan}" tcp dport { 80, 443 } accept
                ${wanAllowedTcpRules}
                ${wanAllowedUdpRules}
                ${lib.optionalString wgEnabled "iifname \"${wan}\" udp dport ${wgPort} accept"}
              }
              chain forward {
                type filter hook forward priority 0; policy drop;
                ${forwardCommonRules}
                ${forwardRules}
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
                ${bridgeLanInputCompatRule}
                ${inputInternalRules}
                iifname "zt*" accept
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
                ${forwardCommonRules}
                ${lib.optionalString (lanZone != null) "iifname \"zt*\" oifname \"${lanZoneInterface}\" accept"}
                ${lib.optionalString (lanZone != null) "iifname \"${lanZoneInterface}\" oifname \"zt*\" accept"}
              }
            '';
          };
        };
      };
    };
  };
}
