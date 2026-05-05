{
  config.flake.nixosModules.router-casting = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.router;
    inherit (cfg) casting;
    helpers = config.routerHelpers or (throw "routerHelpers not defined — is the router module loaded?");
    segmentMap = helpers.segmentMap or {};
    source = lib.attrByPath [casting.sourceSegment] null segmentMap;
    targets = map (name: segmentMap.${name}) casting.targetSegments;
    interfaces = lib.unique (lib.optionals (source != null) [source.interface] ++ map (segment: segment.interface) targets);
  in {
    config = lib.mkIf (cfg.enable && casting.enable && casting.mdns.reflector && interfaces != []) {
      services.avahi = {
        reflector = true;
        allowInterfaces = interfaces;
        publish = {
          enable = false;
          userServices = false;
          addresses = false;
          workstation = false;
          domain = false;
          hinfo = false;
        };
      };
    };
  };
}
