{inputs, lib, ...}: {
  config.flake.nixosModules.minecraft = { lib, config, pkgs, ... }: let
    cfg = config.my.minecraft;

    modItemType = lib.types.submodule ({...}: {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "Logical name of the mod (for readability)";
        };
        url = lib.mkOption {
          type = lib.types.str;
          description = "URL to the mod JAR";
        };
        sha512 = lib.mkOption {
          type = lib.types.str;
          description = "sha512 of the mod JAR";
        };
      };
    });

    serverType = lib.types.submodule ({...}: {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable this server instance";
        };

        package = lib.mkOption {
          type = lib.types.package;
          description = "Minecraft server package (e.g., pkgs.fabricServers.\"fabric-1_21_1\")";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Open firewall for this server";
        };

        mods = lib.mkOption {
          type = lib.types.listOf modItemType;
          default = [];
          description = "List of mods with { name, url, sha512 }";
        };

        serverProperties = lib.mkOption {
          type = lib.types.attrs;
          default = {};
          description = "Server properties";
        };
      };
    });
  in {
    imports = [ inputs.nix-minecraft.nixosModules.minecraft-servers ];

    options.my.minecraft = {
      enable = lib.mkEnableOption "Enable Minecraft servers via nix-minecraft";

      eula = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Agree to the Minecraft EULA";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Global openFirewall flag for services.minecraft-servers";
      };

      servers = lib.mkOption {
        type = lib.types.attrsOf serverType;
        default = {};
        description = "Minecraft servers configuration";
      };
    };

    config = lib.mkIf cfg.enable {
      nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];

      services.minecraft-servers = {
        enable = true;
        eula = cfg.eula;
        openFirewall = cfg.openFirewall;
        servers = lib.mapAttrs (serverName: sCfg: {
          enable = sCfg.enable;
          package = sCfg.package;
          openFirewall = sCfg.openFirewall;
          symlinks = lib.mkIf (sCfg.mods != []) {
            mods = pkgs.linkFarmFromDrvs "mods" (builtins.attrValues (
              builtins.listToAttrs (map (m: {
                name = m.name;
                value = pkgs.fetchurl { url = m.url; sha512 = m.sha512; };
              }) sCfg.mods)
            ));
          };
          serverProperties = sCfg.serverProperties;
        }) cfg.servers;
      };
    };
  };
} 