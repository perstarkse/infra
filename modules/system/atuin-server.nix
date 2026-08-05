_: {
  config.flake.nixosModules.atuin-server = {
    config,
    lib,
    mkStandardEndpointsOptions,
    ...
  }: let
    cfg = config.my.atuin-server;
  in {
    options.my.atuin-server = {
      enable = lib.mkEnableOption "Enable Atuin Sync Server";

      port = lib.mkOption {
        type = lib.types.port;
        default = 8888;
        description = "Port for Atuin server to listen on";
      };

      address = lib.mkOption {
        type = lib.types.str;
        default = config.my.listenNetworkAddress;
        description = "Address for Atuin server to bind to (defaults to my.listenNetworkAddress)";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open firewall for Atuin server port";
      };

      endpoints = mkStandardEndpointsOptions {
        subject = "Atuin server";
        visibility = "internal";
        withRouter = true;
      };
    };

    config = lib.mkIf cfg.enable {
      services.atuin = {
        enable = true;
        inherit (cfg) port;
        host = cfg.address;
        openRegistration = false;
        database = {
          createLocally = true;
        };
      };

      my.endpoints.services.atuin-server = lib.mkIf cfg.endpoints.enable {
        upstream = {
          host = cfg.address;
          inherit (cfg) port;
        };
        router = {inherit (cfg.endpoints.router) enable targets;};
        http.virtualHosts = lib.optional (cfg.endpoints.domain != null) {
          inherit (cfg.endpoints) domain;
          inherit (cfg.endpoints) lanOnly useWildcard;
        };
        firewall.local = {
          enable = cfg.openFirewall;
          tcp = [cfg.port];
        };
      };
    };
  };
}
