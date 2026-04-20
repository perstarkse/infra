{
  config.flake.nixosModules.router-firewall = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    unifiOsCfg = config.services.unifi-os-server or null;
    helpers = config.routerHelpers or {};
    zones = helpers.zones or [];
    internalZones = lib.filter (zone: zone.kind != "wan") zones;
    zoneMap = lib.listToAttrs (map (zone: lib.nameValuePair zone.name zone) internalZones);
    segmentMap = helpers.segmentMap or {};
    primarySegment = helpers.primarySegment or null;
    primaryZoneInterface = if primarySegment != null then primarySegment.interface else null;
    wanZone = lib.findFirst (zone: zone.kind == "wan") null zones;
    wan = if wanZone != null then wanZone.interface else (helpers.wanInterface or cfg.wan.interface);

    expandProtocols = pf:
      if pf.protocol == "tcp udp"
      then ["tcp" "udp"]
      else [pf.protocol];

    portForwards =
      lib.concatMap (
        machine:
          let
            segmentName = if machine.segment != null then machine.segment else cfg.primarySegment;
            targetZone = segmentMap.${segmentName};
          in
            lib.concatMap (
              pf:
                map (
                  protocol: {
                    inherit machine protocol targetZone;
                    inherit (pf) port;
                  }
                ) (expandProtocols pf)
            ) machine.portForwards
      )
      cfg.machines;

    forwardRules = lib.concatStringsSep "\n" (map (
      pfRule: "iifname \"${wan}\" oifname \"${pfRule.targetZone.interface}\" ip daddr ${pfRule.targetZone.subnet}.${pfRule.machine.ip} ${pfRule.protocol} dport ${toString pfRule.port} accept"
    ) portForwards);
    dnatRules = lib.concatStringsSep "\n" (map (
      pfRule: "iifname \"${wan}\" ${pfRule.protocol} dport ${toString pfRule.port} dnat to ${pfRule.targetZone.subnet}.${pfRule.machine.ip}"
    ) portForwards);

    wgEnabled = cfg.wireguard.enable or false;
    wgPort = toString (cfg.wireguard.listenPort or 51820);
    dnsFrontendPort = 53;
    wanAllowedTcpRules = lib.concatStringsSep "\n" (map (port: "iifname \"${wan}\" tcp dport ${toString port} accept") (lib.unique cfg.wan.allowedTcpPorts));
    wanAllowedUdpRules = lib.concatStringsSep "\n" (map (port: "iifname \"${wan}\" udp dport ${toString port} accept") (lib.unique cfg.wan.allowedUdpPorts));

    routerTcpPorts = zone:
      let
        base =
          if (zone.routerAccessLevel or "none") == "full"
          then [22 80 443]
          else [];
        infra =
          if (zone.routerAccessLevel or "none") != "none"
          then [53]
          else [];
      in
        lib.unique (base ++ infra ++ (zone.routerAllowedTcpPorts or []));

    routerUdpPorts = zone:
      let
        infra =
          if (zone.routerAccessLevel or "none") != "none"
          then [53]
          else [];
      in
        lib.unique (infra ++ (zone.routerAllowedUdpPorts or []));

    mkRouterInputRulesV4 = zone:
      let
        allowInfra = (zone.routerAccessLevel or "none") != "none";
        tcpPorts = routerTcpPorts zone;
        udpPorts = routerUdpPorts zone;
      in
        lib.concatStringsSep "\n" (
          lib.optionals allowInfra ["iifname \"${zone.interface}\" ip protocol icmp accept"]
          ++ map (port: "iifname \"${zone.interface}\" tcp dport ${toString port} accept") tcpPorts
          ++ map (port: "iifname \"${zone.interface}\" udp dport ${toString port} accept") udpPorts
          ++ lib.optionals (zone.dhcp.enable or false) ["iifname \"${zone.interface}\" udp sport 68 udp dport 67 accept"]
        );

    mkRouterInputRulesV6 = zone:
      let
        allowInfra = (zone.routerAccessLevel or "none") != "none";
        tcpPorts = routerTcpPorts zone;
        udpPorts = routerUdpPorts zone;
      in
        lib.concatStringsSep "\n" (
          lib.optionals allowInfra [
            ''
              iifname "${zone.interface}" icmpv6 type {
                destination-unreachable, packet-too-big, time-exceeded,
                parameter-problem, nd-router-solicit, nd-router-advert,
                nd-neighbor-solicit, nd-neighbor-advert, echo-request, echo-reply
              } accept
            ''
          ]
          ++ map (port: "iifname \"${zone.interface}\" tcp dport ${toString port} accept") tcpPorts
          ++ map (port: "iifname \"${zone.interface}\" udp dport ${toString port} accept") udpPorts
        );

    inputInternalRulesV4 = lib.concatStringsSep "\n" (map mkRouterInputRulesV4 internalZones);
    inputInternalRulesV6 = lib.concatStringsSep "\n" (map mkRouterInputRulesV6 internalZones);

    dropLanBridgeTaggedDhcpRules =
      if primaryZoneInterface != null && primaryZoneInterface != helpers.lanBridge
      then ""
      else
        lib.concatStringsSep "\n" (map (
          zone: "iifname \"${helpers.lanBridge}\" vlan id ${toString zone.vlanId} udp dport 67 drop"
        ) (lib.filter (zone: !(zone.isPrimary or false) && zone.kind == "segment") internalZones));

    dnsRedirectPreroutingRules = lib.concatStringsSep "\n" (map (
      zone: ''
        iifname "${zone.interface}" tcp dport 53 redirect to ${toString dnsFrontendPort}
        iifname "${zone.interface}" udp dport 53 redirect to ${toString dnsFrontendPort}
      ''
    ) (lib.filter (zone: (zone.kind == "segment") && (zone.dnsRedirectEnabled or false)) internalZones));

    dohProtectedSegments = lib.filter (
      zone:
        (zone.kind == "segment")
        && cfg.dns.dohBlocking.enable
        && !(lib.elem zone.name cfg.dns.dohBlocking.exemptSegments)
    ) internalZones;

    dohTransportBlockRules = lib.concatStringsSep "\n" (lib.concatMap (
      zone:
        (map (port: "iifname \"${zone.interface}\" oifname \"${wan}\" tcp dport ${toString port} reject with tcp reset") cfg.dns.dohBlocking.blockTcpPorts)
        ++ (map (port: "iifname \"${zone.interface}\" oifname \"${wan}\" udp dport ${toString port} reject") cfg.dns.dohBlocking.blockUdpPorts)
    ) dohProtectedSegments);

    mkSameZoneRule = zone:
      if (zone.isolateClients or false)
      then ""
      else "iifname \"${zone.interface}\" oifname \"${zone.interface}\" accept";

    forwardSameZoneRules = lib.concatStringsSep "\n" (lib.filter (rule: rule != "") (map mkSameZoneRule internalZones));
    forwardWanEgressRules = lib.concatStringsSep "\n" (map (
      zone: lib.optionalString (zone.internet or false) "iifname \"${zone.interface}\" oifname \"${wan}\" accept"
    ) internalZones);
    forwardWanReturnRules = lib.concatStringsSep "\n" (map (
      zone: "iifname \"${wan}\" oifname \"${zone.interface}\" ct state established,related accept"
    ) internalZones);

    zoneHasAnyAccess = rule: rule.all || rule.icmp || rule.tcpPorts != [] || rule.udpPorts != [];

    mkReachRule = sourceZone: rule: let
      target = lib.attrByPath [rule.segment] null zoneMap;
      common =
        if target == null
        then []
        else [
          (if rule.all then "iifname \"${sourceZone.interface}\" oifname \"${target.interface}\" accept" else "")
        ]
        ++ map (port: "iifname \"${sourceZone.interface}\" oifname \"${target.interface}\" tcp dport ${toString port} accept") rule.tcpPorts
        ++ map (port: "iifname \"${sourceZone.interface}\" oifname \"${target.interface}\" udp dport ${toString port} accept") rule.udpPorts;
      v4 =
        if target == null || !rule.icmp
        then []
        else ["iifname \"${sourceZone.interface}\" oifname \"${target.interface}\" ip protocol icmp accept"];
      v6 =
        if target == null || !rule.icmp
        then []
        else [
          ''
            iifname "${sourceZone.interface}" oifname "${target.interface}" icmpv6 type {
              destination-unreachable, packet-too-big, time-exceeded,
              parameter-problem, nd-router-solicit, nd-router-advert,
              nd-neighbor-solicit, nd-neighbor-advert, echo-request, echo-reply
            } accept
          ''
        ];
    in {
      inherit target;
      common = lib.filter (line: line != "") common;
      v4 = lib.filter (line: line != "") v4;
      v6 = lib.filter (line: line != "") v6;
    };

    explicitReachPairs = lib.concatMap (
      zone: map (rule: {source = zone; rule = rule;}) (zone.reachRules or [])
    ) internalZones;

    reverseReachPairs = lib.concatMap (
      targetZone:
        map (
          rule:
            let
              sourceZone = lib.attrByPath [rule.segment] null zoneMap;
            in {
              source = sourceZone;
              rule = rule // {segment = targetZone.name;};
            }
        ) (targetZone.canBeReachedFrom or [])
    ) internalZones;

    allReachPairs = lib.filter (
      pair: pair.source != null && lib.attrByPath [pair.rule.segment] null zoneMap != null && zoneHasAnyAccess pair.rule
    ) (explicitReachPairs ++ reverseReachPairs);

    forwardZoneAllowRulesCommon = lib.concatStringsSep "\n" (lib.concatMap (
      pair: (mkReachRule pair.source pair.rule).common
    ) allReachPairs);
    forwardZoneAllowRulesV4 = lib.concatStringsSep "\n" (lib.concatMap (
      pair: (mkReachRule pair.source pair.rule).v4
    ) allReachPairs);
    forwardZoneAllowRulesV6 = lib.concatStringsSep "\n" (lib.concatMap (
      pair: (mkReachRule pair.source pair.rule).v6
    ) allReachPairs);

    bridgeLanInputCompatRule =
      if primaryZoneInterface != null && primaryZoneInterface != helpers.lanBridge
      then ''
        iifname "${helpers.lanBridge}" accept
      ''
      else "";

    unifiDiscoveryInputRule =
      if unifiOsCfg != null && unifiOsCfg.enable && (unifiOsCfg.network.hostAccess.enable or false)
      then ''
        iifname "${unifiOsCfg.network.hostAccess.interfaceName}" tcp dport 11002 accept
      ''
      else "";

    bridgeLanForwardCompatRulesV4 =
      if primaryZoneInterface != null && primaryZoneInterface != helpers.lanBridge
      then let
        primaryRuleObjects = map (rule: mkReachRule {interface = helpers.lanBridge;} rule) (primarySegment.reachRules or []);
        primaryRules = lib.concatStringsSep "\n" (lib.concatMap (obj: obj.common ++ obj.v4) primaryRuleObjects);
      in ''
        iifname "${helpers.lanBridge}" oifname "${helpers.lanBridge}" accept
        ${lib.optionalString (primarySegment != null && (primarySegment.internet or false)) "iifname \"${helpers.lanBridge}\" oifname \"${wan}\" accept"}
        iifname "${wan}" oifname "${helpers.lanBridge}" ct state established,related accept
        ${primaryRules}
      ''
      else "";

    bridgeLanForwardCompatRulesV6 =
      if primaryZoneInterface != null && primaryZoneInterface != helpers.lanBridge
      then let
        primaryRuleObjects = map (rule: mkReachRule {interface = helpers.lanBridge;} rule) (primarySegment.reachRules or []);
        primaryRules = lib.concatStringsSep "\n" (lib.concatMap (obj: obj.common ++ obj.v6) primaryRuleObjects);
      in ''
        iifname "${helpers.lanBridge}" oifname "${helpers.lanBridge}" accept
        ${lib.optionalString (primarySegment != null && (primarySegment.internet or false)) "iifname \"${helpers.lanBridge}\" oifname \"${wan}\" accept"}
        iifname "${wan}" oifname "${helpers.lanBridge}" ct state established,related accept
        ${primaryRules}
      ''
      else "";

    forwardCommonRulesV4 = ''
      ct state established,related accept
      ${forwardSameZoneRules}
      ${dohTransportBlockRules}
      ${forwardWanEgressRules}
      ${forwardWanReturnRules}
      ${bridgeLanForwardCompatRulesV4}
      ${forwardZoneAllowRulesCommon}
      ${forwardZoneAllowRulesV4}
    '';

    forwardCommonRulesV6 = ''
      ct state established,related accept
      ${forwardSameZoneRules}
      ${forwardWanEgressRules}
      ${forwardWanReturnRules}
      ${bridgeLanForwardCompatRulesV6}
      ${forwardZoneAllowRulesCommon}
      ${forwardZoneAllowRulesV6}
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
                ct state established,related accept
                ${dropLanBridgeTaggedDhcpRules}
                ${bridgeLanInputCompatRule}
                ${unifiDiscoveryInputRule}
                ${inputInternalRulesV4}
                iifname "${wan}" ct state established,related accept
                iifname "${wan}" ip protocol icmp accept
                iifname "${wan}" tcp dport { 80, 443 } accept
                ${wanAllowedTcpRules}
                ${wanAllowedUdpRules}
                ${lib.optionalString wgEnabled "iifname \"${wan}\" udp dport ${wgPort} accept"}
              }
              chain forward {
                type filter hook forward priority 0; policy drop;
                ${forwardCommonRulesV4}
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
                ${dnsRedirectPreroutingRules}
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
                ct state established,related accept
                ${bridgeLanInputCompatRule}
                ${unifiDiscoveryInputRule}
                ${inputInternalRulesV6}
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
                ${forwardCommonRulesV6}
                ${lib.optionalString (primaryZoneInterface != null) "iifname \"zt*\" oifname \"${primaryZoneInterface}\" accept"}
                ${lib.optionalString (primaryZoneInterface != null) "iifname \"${primaryZoneInterface}\" oifname \"zt*\" accept"}
              }
            '';
          };
        };
      };
    };
  };
}
