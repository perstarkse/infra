args@{
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
      politikerstod
      atuin-server
      atuin
      webdav-garage
      paperless
    ]
    ++ (if args ? "nix-topology" then [args."nix-topology".nixosModules.default] else [])
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
        includeTags = ["makemake" "minne" "surrealdb" "b2" "minne-saas" "nous" "politikerstod" "garage" "garage-s3" "paperless"];
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
        # {
        #   readers = ["garage"];
        #   path = config.my.secrets.getPath "garage" "env";
        # }
        {
          readers = ["politikerstod"];
          path = config.my.secrets.getPath "politikerstod" "env";
        }
      ];
    };

    # Backups configuration
    backups = let
      mkB2 = path: {
        enable = true;
        inherit path;
        frequency = "daily";
        backend = {
          type = "b2";
          bucket = null;
          lifecycleKeepPriorVersionsDays = 30;
        };
      };
    in {
      minne = mkB2 config.my.minne.dataDir;
      minne-saas = mkB2 config.my.minne-saas.dataDir;
      vaultwarden = mkB2 config.my.vaultwarden.backupDir;
      surrealdb = mkB2 config.my.surrealdb.dataDir;
      surrealdb-saas = mkB2 config.my.minne-saas.surrealdb.dataDir;
      nous = mkB2 config.my.nous.dataDir;
      paperless = {
        enable = true;
        path = config.my.paperless.dataDir;
        frequency = "daily";
        backend = {
          type = "garage-s3";
        };
      };
    };

    k3s = {
      enable = false;
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
      port = 3001;
      address = "10.0.0.10";
      dataDir = "/var/lib/minne-saas";

      surrealdb = {
        host = "127.0.0.1";
        port = 8221;
        dataDir = "/var/lib/surrealdb-saas";
      };

      logLevel = "info";
      demoMode = true;
      demoAllowedMutatingPaths = [
        "/signin"
        "/gdpr/accept"
        "/gdpr/deny"
        "/waitlist"
        "/waitlist/"
      ];
    };

    # Garage S3-compatible storage (clustered with io)
    garage = {
      enable = true;
      dataDir = "/var/lib/garage/data";
      metaDir = "/var/lib/garage/meta";
      s3Port = 3900;
      region = "garage";
      replicationMode = 2;
      rpcPublicAddr = "10.0.0.10:3901";
      zone = "makemake";
    };

    # WebDAV access to Garage S3 for iPhone
    webdav-garage = {
      enable = true;
      bucket = "shared";
      endpoint = "http://127.0.0.1:3900";
      bindAddress = "0.0.0.0";
      port = 8081;
      htpasswdFile = config.my.secrets.getPath "webdav-htpasswd" "htpasswd";
    };

    # Nous burnout prevention app
    nous = {
      enable = true;
      port = 3002;
      address = "10.0.0.10";
      dataDir = "/var/lib/nous";
      host = "https://nous.fyi";
      logLevel = "info"; # Temporarily debug to diagnose mail issues

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

    # Politikerstöd Service
    politikerstod = {
      enable = true;
      port = 5150;
      host = "https://politikerstod.stark.pub";
      openFirewall = true;

      database = {
        name = "politikerstod_prod";
        user = "politikerstod";
        host = "192.168.100.12"; # Container IP
        port = 5432;
        enableContainer = true;
        allowedHosts = ["10.0.0.15"]; # charon - remote worker
        container = {
          hostAddress = "192.168.100.10";
          localAddress = "192.168.100.12";
        };
      };

      smtp = {
        host = "mail-eu.smtp2go.com";
        port = 587;
        secure = false; # Upgrade via STARTTLS
      };

      settings = {
        logLevel = "info";
        prettyBacktrace = true;
        numWorkers = 4;
        pollingHistoricalMonths = 36;
        openaiModel = "gpt-4.1-mini";
        evaluationModel = "gpt-4.1-mini";
      };
    };

    # Atuin Sync Server
    atuin-server = {
      enable = true;
      port = 8888;
      openFirewall = true;
    };

    # Atuin client
    atuin.enable = true;

    # Paperless-ngx document management
    paperless = {
      enable = true;
      openFirewall = true;
      port = 28981;
      address = "10.0.0.10";
      url = "https://paperless.lan.stark.pub";
      dataDir = "/var/lib/paperless";
      consumptionDir = "/var/lib/paperless/consume";
      mediaDir = "/var/lib/paperless/media";
      ocr.language = "swe+eng";
      database = {
        name = "paperless";
        user = "paperless";
        host = "192.168.100.22";
        port = 5432;
        enableContainer = true;
        container = {
          hostAddress = "192.168.100.20";
          localAddress = "192.168.100.22";
        };
      };
      tika.enable = true;
      s3Consumption = {
        enable = true;
        bucket = "paperless-consume";
        endpoint = "http://127.0.0.1:3900";
        region = "garage";
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
    unrar
    # devenv
  ];

  programs.fuse.userAllowOther = true;

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      function unrar-dirs --description "Unrar files in specified directories"
        for dir in $argv
          if test -d "$dir"
            echo "Processing $dir..."
            pushd "$dir"
            if test (count (find . -maxdepth 1 -name "*.rar")) -gt 0
              ${pkgs.unrar}/bin/unrar e -o+ *.rar
            else
              echo "No rar files found in $dir"
            end
            popd
          else
            echo "Directory $dir does not exist"
          end
        end
      end
    '';
  };

  nixpkgs.config.allowUnfree = true;

  # Restrict WebDAV port to router only (auth handled by nginx on io)
  networking.firewall.extraInputRules = ''
    ip saddr 10.0.0.1 tcp dport 8081 accept
    tcp dport 8081 drop
  '';

  # Centralized logging to router for fail2ban
  services.journald.upload = {
    enable = true;
    settings = {
      Upload = {
        URL = "http://10.0.0.1:19532";
      };
    };
  };
}
