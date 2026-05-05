{lib}: let
  inherit (lib) mkEnableOption mkOption types;

  basicAuthSubmodule = types.submodule {
    options = {
      realm = mkOption {
        type = types.str;
        default = "Restricted";
        description = "Authentication realm shown to users.";
      };
      htpasswdFile = mkOption {
        type = types.path;
        description = "Path to htpasswd file for basic authentication.";
      };
    };
  };

  basicAuthSecretSubmodule = types.submodule {
    options = {
      realm = mkOption {
        type = types.str;
        default = "Restricted";
        description = "Authentication realm shown to users.";
      };
      name = mkOption {
        type = types.str;
        description = "Clan vars secret name resolved by the importing router.";
      };
      file = mkOption {
        type = types.str;
        default = "htpasswd";
        description = "File inside the Clan vars secret.";
      };
    };
  };

  acmeDns01Submodule = types.submodule {
    options = {
      dnsProvider = mkOption {
        type = types.str;
        description = "lego DNS provider name.";
      };
      environmentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to an EnvironmentFile exporting provider variables.";
      };
      group = mkOption {
        type = types.str;
        default = "nginx";
        description = "Group that should own read access to issued certificates.";
      };
    };
  };
in {
  inherit basicAuthSubmodule basicAuthSecretSubmodule acmeDns01Submodule;

  mkStandardExposureOptions = {
    subject,
    visibility,
    withRouter ? false,
    withRouterTargetHost ? false,
    withRouterDnsTarget ? false,
    withAcmeDns01 ? false,
    withExtraConfigDefault ? null,
    withBasicAuthSecret ? false,
  }:
    {
      enable = mkEnableOption "publish ${subject} exposure metadata";
      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Domain used for generated ${subject} reverse proxy and DNS exposure.";
      };
    }
    // lib.optionalAttrs (visibility == "internal") {
      lanOnly = mkOption {
        type = types.bool;
        default = true;
        description = "Restrict generated reverse proxy access to internal networks.";
      };
      useWildcard = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Wildcard certificate handle for generated reverse proxy exposure.";
      };
    }
    // lib.optionalAttrs (visibility == "public") {
      public = mkOption {
        type = types.bool;
        default = false;
        description = "Mark generated ${subject} exposure as intentionally public.";
      };
      cloudflareProxied = mkOption {
        type = types.bool;
        default = false;
        description = "Require generated ${subject} traffic through Cloudflare or internal networks.";
      };
    }
    // lib.optionalAttrs withAcmeDns01 {
      acmeDns01 = mkOption {
        type = types.nullOr acmeDns01Submodule;
        default = null;
        description = "Per-vhost DNS-01 ACME settings for generated ${subject} exposure.";
      };
    }
    // lib.optionalAttrs (withExtraConfigDefault != null) {
      extraConfig = mkOption {
        type = types.lines;
        default = withExtraConfigDefault;
        description = "Extra nginx location configuration for generated ${subject} exposure.";
      };
    }
    // lib.optionalAttrs withBasicAuthSecret {
      basicAuthSecret = mkOption {
        type = types.nullOr basicAuthSecretSubmodule;
        default = null;
        description = "Request router-resolved HTTP Basic Authentication for generated ${subject} exposure.";
      };
    }
    // lib.optionalAttrs withRouter {
      router =
        {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Export ${subject} exposure to router importers.";
          };
          targets = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Routers allowed to import this ${subject} exposure.";
          };
        }
        // lib.optionalAttrs withRouterTargetHost {
          targetHost = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Router-reachable upstream host override.";
          };
        }
        // lib.optionalAttrs withRouterDnsTarget {
          dnsTarget = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "DNS target published by importing routers.";
          };
        };
    };
}
