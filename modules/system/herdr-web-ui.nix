# herdr-web-ui: the devswha/herdr-web-ui browser client, run as a herdr plugin.
#
# It is a third-party plugin installed from GitHub rather than a Nix package, so
# this module only publishes its LAN endpoint. The plugin install, the pinned
# Bun and the server's PATH live in the Home Manager half
# (modules/home/herdr-web-ui.nix), because herdr.service is a user unit and
# `my.herdr` is a Home Manager option. Home Manager keeps its own `my`
# namespace, so the machine sets `enable` on both sides.
#
# LIMIT: the endpoint is LAN-only and the plugin carries its own token/pairing
# gate. That gate is off unless a token or a paired device exists, so this
# vhost is only as private as the LAN it sits on — see the KNOWN GAP entry in
# CHANGELOG.md.
_: {
  config.flake.nixosModules.herdr-web-ui = {
    config,
    lib,
    mkStandardEndpointsOptions,
    ...
  }: let
    cfg = config.my.herdr-web-ui;
  in {
    options.my.herdr-web-ui = {
      enable = lib.mkEnableOption "herdr-web-ui browser client for herdr";

      port = lib.mkOption {
        type = lib.types.port;
        default = 7317;
        description = ''
          Port the plugin's bridge listens on. It binds `bindHost` (Home
          Manager half), not loopback, because the router reverse-proxies to
          this machine's LAN address and would otherwise connect-refused on its
          own loopback.
        '';
      };

      allowedFirewallSources = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["10.0.0.1"];
        description = ''
          Source IPs/CIDRs allowed to reach the bridge. The reverse proxy is the
          only client, so this should name the router and nothing else; an
          empty list leaves the port closed rather than open to the LAN.
        '';
      };

      endpoints = mkStandardEndpointsOptions {
        subject = "herdr web ui";
        visibility = "internal";
        withRouter = true;
      };
    };

    config = lib.mkIf cfg.enable {
      my.endpoints.services.herdr-web-ui = lib.mkIf cfg.endpoints.enable {
        upstream = {
          # host defaults to listenNetworkAddress (options.nix:405); port does
          # not (options.nix:410), so only the host is left implicit.
          inherit (cfg) port;
        };

        router = {
          inherit (cfg.endpoints.router) enable targets;
        };
        # No `websockets`/`rateLimit` overrides: options.nix already defaults
        # websockets on, and exempts lanOnly vhosts from the shared rate limit.
        http.virtualHosts = lib.optional (cfg.endpoints.domain != null) {
          inherit (cfg.endpoints) domain lanOnly useWildcard;
        };
        # The bridge binds this machine's LAN address, so it needs an inbound
        # rule; without one the router's proxy_pass gets a filtered connection
        # and the vhost just times out. Declared here rather than as an
        # extraInputRules block so the port stays named once, next to its
        # declaration.
        firewall.local = {
          enable = cfg.allowedFirewallSources != [];
          tcp = [cfg.port];
          allowedSources = cfg.allowedFirewallSources;
        };
      };
    };
  };
}
