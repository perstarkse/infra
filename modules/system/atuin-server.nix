_: {
  config.flake.nixosModules.atuin-server = {
    config,
    lib,
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
    };

    config = lib.mkIf cfg.enable {
      services.atuin = {
        enable = true;
        inherit (cfg) port;
        host = cfg.address;
        openRegistration = true;
        database = {
          createLocally = true;
        };
      };

      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
    };
  };
}
