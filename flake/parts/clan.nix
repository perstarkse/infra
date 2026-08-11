{
  config,
  inputs,
  ...
}: {
  flake.clan = {
    meta.name = "heliosphere";

    specialArgs = {
      ctx = {
        inherit (config) flake;
        inputs = {
          privateInfra = inputs.private-infra;
          varsHelper = inputs.vars-helper;
          inherit (inputs) nous voxtype indicator-alert-daemon;
          agentTooling = inputs."agent-tooling";
          digikeyMcp = inputs."digikey-mcp";
          nixpkgs612 = inputs."nixpkgs-612";
        };
      };
    };

    inventory = {
      machines = {
        sedna = {
          deploy.buildHost = "root@charon.lan";
          tags = [
            "server"
            "check-profile-sedna"
          ];
        };
        io = {
          deploy.buildHost = "root@charon.lan";
          tags = [
            "server"
            "check-profile-io-final"
            "check-profile-sedna"
          ];
        };
        makemake = {
          deploy.buildHost = "root@charon.lan";
          tags = [
            "server"
            "check-profile-fast"
            "check-profile-garage"
            "check-profile-politikerstod"
            "check-profile-paperless"
            "check-profile-backups"
            "check-profile-mailserver"
            "check-profile-accounted"
          ];
        };
        charon = {
          tags = [
            "client"
            "check-profile-fast"
            "check-profile-politikerstod"
            "check-profile-wireguard"
            "check-profile-paperless"
            "check-profile-backups"
          ];
        };
        ariel = {
          deploy.buildHost = "root@charon.lan";
          tags = [
            "client"
            "check-profile-fast"
          ];
        };
      };

      instances = {
        internet = {
          roles.default = {
            machines = {
              sedna = {
                settings.host = "130.61.55.4";
                settings.port = 2222;
              };
              io = {
                settings.host = "io.lan";
              };
              charon = {
                settings.host = "charon.lan";
              };
              makemake = {
                settings.host = "makemake.lan";
              };
              ariel = {
                settings.host = "ariel.lan";
              };
            };
          };
        };
        zerotier = {
          roles = {
            controller.machines.io = {};
            peer.tags.all = {};
          };
        };
        clan-cache = {
          module = {
            name = "trusted-nix-caches";
            input = "clan-core";
          };
          roles.default.tags.all = {};
        };
        sshd-basic = {
          module = {
            name = "sshd";
            input = "clan-core";
          };
          roles = {
            server = {
              tags.all = {};
              settings = {
                authorizedKeys = {
                  "p" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn";
                };
              };
            };
            client.tags.all = {};
          };
        };
        user-p = {
          module = {
            name = "users";
            input = "clan-core";
          };
          # The interactive user p exists only on the desktop machines;
          # servers are root-only (admin via the clan sshd key + root password).
          roles.default = {
            machines = {
              charon = {};
              ariel = {};
            };
            settings = {
              user = "p";
              prompt = true;
            };
          };
        };
        # Root password for console / emergency login. The fleet migrated off
        # the deprecated admin clanService onto sshd, but never re-attached a
        # users instance for root — so root-password vars were orphaned and
        # mutableUsers=false left root password-locked on servers.
        users-root = {
          module = {
            name = "users";
            input = "clan-core";
          };
          roles.default = {
            tags.nixos = {};
            settings = {
              user = "root";
              # Existing migrated vars (user-password-root) are reused; prompt
              # only fires for machines that still lack the generator output
              # (currently sedna).
              prompt = true;
              groups = [];
            };
          };
        };
        emergency-access = {
          module = {
            name = "emergency-access";
            input = "clan-core";
          };

          roles.default.tags.nixos = {};
        };
      };
    };
  };
}
