{
  modules,
  config,
  pkgs,
  vars-helper,
  private-infra,
  ...
}: {
  imports = with modules.nixosModules;
    [
      ./hardware-configuration.nix
      ./boot.nix
      options
      shared
      interception-tools
      system-stylix
      docker
      vaultwarden
      openwebui
      surrealdb
      minne
      minne-saas
      minecraft
      backups
      k3s
      garage
      nous
    ]
    ++ (with vars-helper.nixosModules; [default])
    ++ (with private-infra.nixosModules; [media mailserver]);
  my = {
    mainUser = {
      name = "p";
    };

    listenNetworkAddress = "10.0.0.10";
    secrets = {
      discover = {
        enable = true;
        dir = ../../vars/generators;
        includeTags = ["makemake" "minne" "surrealdb" "b2" "minne-saas"];
      };

      generateManifest = false;

      allowReadAccess = [
        {
          readers = ["minne"];
          path = config.my.secrets.getPath "minne-env" "env";
        }
        {
          readers = ["nous"];
          path = config.my.secrets.getPath "nous" "env";
        }
        {
          readers = ["garage"];
          path = config.my.secrets.getPath "garage" "env";
        }
      ];
    };

    # Backups configuration
    backups = {
      minne = {
        enable = true;
        path = config.my.minne.dataDir;
        frequency = "daily";
        backend = {
          type = "b2";
          bucket = null;
          lifecycleKeepPriorVersionsDays = 30;
        };
      };
      minne-saas = {
        enable = true;
        path = config.my.minne-saas.dataDir;
        frequency = "daily";
        backend = {
          type = "b2";
          bucket = null;
          lifecycleKeepPriorVersionsDays = 30;
        };
      };
      vaultwarden = {
        enable = true;
        path = config.my.vaultwarden.backupDir;
        frequency = "daily";
        backend = {
          type = "b2";
          bucket = null;
          lifecycleKeepPriorVersionsDays = 30;
        };
      };
      surrealdb = {
        enable = true;
        path = config.my.surrealdb.dataDir;
        frequency = "daily";
        backend = {
          type = "b2";
          bucket = null;
          lifecycleKeepPriorVersionsDays = 30;
        };
      };
      nous = {
        enable = true;
        path = config.my.nous.dataDir;
        frequency = "daily";
        backend = {
          type = "b2";
          bucket = null;
          lifecycleKeepPriorVersionsDays = 30;
        };
      };
    };

    k3s = {
      enable = true;
      initServer = true;
      tlsSan = "10.0.0.10";
      # disable = ["servicelb" "traefik"];
      extraFlags = [
      ];
    };

    vaultwarden = {
      enable = true;
      port = 8322;
      address = "10.0.0.10";
    };

    openwebui = {
      enable = true;
      port = 8080;
      autoUpdate = true;
      updateSchedule = "weekly";
    };

    # SurrealDB configuration
    surrealdb = {
      enable = true;
      host = "127.0.0.1";
      port = 8220;
      dataDir = "/var/lib/surrealdb";
    };

    # Minne configuration
    minne = {
      enable = true;
      port = 3000;
      address = "10.0.0.10";
      dataDir = "/var/lib/minne";

      surrealdb = {
        host = "127.0.0.1";
        port = 8220;
      };

      logLevel = "debug";
    };

    # Minne SaaS configuration
    minne-saas = {
      enable = true;
      port = 3003;
      address = "10.0.0.10";
      dataDir = "/var/lib/minne-saas";

      surrealdb = {
        host = "127.0.0.1";
        port = 8221;
      };

      logLevel = "info";

      saasConfig = {
        demo_mode = false;
        demo_allowed_mutating_paths = ["/signin" "/gdpr/accept" "/gdpr/deny"];
      };
    };

    # Garage S3-compatible storage for Nous
    garage = {
      enable = true;
      dataDir = "/var/lib/garage/data";
      metaDir = "/var/lib/garage/meta";
      s3Port = 3900;
      region = "garage";
    };

    # Nous burnout prevention app
    nous = {
      enable = true;
      port = 3002;
      address = "10.0.0.10";
      dataDir = "/var/lib/nous";
      host = "https://nous.fyi";
      logLevel = "debug"; # Temporarily debug to diagnose mail issues

      database = {
        name = "nous_prod";
        user = "nous";
      };

      s3 = {
        endpoint = "http://127.0.0.1:3900";
        bucket = "nous-backups";
        region = "garage";
      };

      smtp = {
        host = "mail-eu.smtp2go.com";
        port = 587;
      };
    };

    minecraft = {
      enable = true;
      eula = true;
      openFirewall = true;
      servers = {
        berget-2 = {
          enable = true;
          package = pkgs.fabricServers."fabric-1_21_1";
          openFirewall = true;
          mods = [
            {
              name = "FabricAPI";
              url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/qKPgBeHl/fabric-api-0.104.0%2B1.21.1.jar";
              sha512 = "B3P0XTZLUGtOWwJKqPHUmJAPzwoCDSAlFU4WPlCg7u4bgpa/KcId9c7UISbtRmNeXtCU3yV5bsVS63Y5lDjn5w==";
            }
            {
              name = "Lithium";
              url = "https://cdn.modrinth.com/data/gvQqBUqZ/versions/5szYtenV/lithium-fabric-mc1.21.1-0.13.0.jar";
              sha512 = "1L2anMN9qtiCiqT6nKIOT4nRDjDPba9FRu9M9KaEuiHqCGWpwjzvnR9DSOm6SsqarKPbn5lTT8YQ+nilygvxUQ==";
            }
            {
              name = "Collective";
              url = "https://cdn.modrinth.com/data/e0M1UDsY/versions/13do3Fe4/collective-1.21.1-7.84.jar";
              sha512 = "K81i8rdKELYD5oeG22aarqo0mOrHZv0giFHiT1gHov2VE1oP7CtjCPZJMSdaQSMQFmQnOQ1/ylE6aBHmpMXpaQ==";
            }
            {
              name = "VillageSpawnPoint";
              url = "https://cdn.modrinth.com/data/KplTt9Ku/versions/Vl3DreYU/villagespawnpoint-1.21.1-4.4.jar";
              sha512 = "iPOh4iTxfTSToZPZbnH+kyWg33INWDAciCc8uJ/MAKWMyNiftdTX5tefkNka1YWcxwTIQ4YD+4tomTRclpwCtg==";
            }
            {
              name = "Tectonic";
              url = "https://cdn.modrinth.com/data/lWDHr9jE/versions/mSYrCaov/tectonic-fabric-1.21.1-2.4.1a.jar";
              sha512 = "qd2k6xkSpyTh7/ZMpwvp8WX5dD6TbccDxC6+LstM/Rpmpowiqv7wipXIMs6ezPfPg2jG5FV1b5pQV1Ug3UgZGw==";
            }
            {
              name = "Terralith";
              url = "https://cdn.modrinth.com/data/8oi3bsk5/versions/lQreFvOm/Terralith_1.21.x_v2.5.7.jar";
              sha512 = "Q9QL/o3OYDt8nr63LbOJ4nfNMFVBRik1DyiDpsdkcqiHrDUKldnsVcKK7BZd7nc2QEYstnTNxMPvswCZ80Y7cg==";
            }
            {
              name = "Chunky";
              url = "https://cdn.modrinth.com/data/fALzjamp/versions/dPliWter/Chunky-1.4.16.jar";
              sha512 = "foYvTbVju7XPqLwMJgyal7dmLyjQ+EBTVcM9e0EAzgU3izntN8XXXSkZpAwkSjARu0umP51T8Q1QsRsyZW6jlQ==";
            }
          ];
          serverProperties = {
            difficulty = 1;
            gamemode = 0;
            max-players = 2;
            motd = "välkommen till långberget-2";
            server-port = 56000;
            view-distance = 15;
            tick-distance = 3;
            enable-rcon = false;
          };
        };
      };
    };
  };

  time.timeZone = "Europe/Stockholm";

  environment.systemPackages = with pkgs; [
    mergerfs
    # devenv
  ];

  programs.fuse.userAllowOther = true;

  nixpkgs.config.allowUnfree = true;

  # SurrealDB SaaS Service (Managed separately from the module for now)
  systemd.services.surrealdb-saas = {
    description = "SurrealDB SaaS - Database Server";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];

    serviceConfig = {
      Type = "simple";
      User = "surrealdb";
      Group = "surrealdb";
      WorkingDirectory = "/var/lib/surrealdb-saas";
      # Using the same package as the main surrealdb service
      ExecStart = ''${pkgs.surrealdb}/bin/surreal start --bind 127.0.0.1:8221 rocksdb:/var/lib/surrealdb-saas/data.db'';
      Restart = "always";
      RestartSec = "10";

      EnvironmentFile = [
        (config.my.secrets.getPath "surrealdb-credentials" "credentials")
      ];
    };
  };

  # Ensure SaaS DB directory exists
  systemd.tmpfiles.rules = [
    "d /var/lib/surrealdb-saas 0755 surrealdb surrealdb -"
  ];
}
