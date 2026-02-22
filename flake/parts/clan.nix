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
          playwrightMcpLatest = inputs."playwright-mcp-latest";
          inherit (inputs) nous;
          nixTopology = inputs.nix-topology;
        };
      };
    };

    inventory = {
      machines = {
        oumuamua = {
          deploy.buildHost = "root@charon.lan";
          tags = [
            "server"
            "check-profile-fast"
          ];
        };
        io = {
          deploy.buildHost = "root@charon.lan";
          tags = [
            "server"
            "check-profile-io-final"
          ];
        };
        makemake = {
          deploy.buildHost = "root@charon.lan";
          tags = [
            "server"
            "check-profile-fast"
            "check-profile-garage"
            "check-profile-politikerstod"
          ];
        };
        charon = {
          tags = [
            "client"
            "check-profile-fast"
            "check-profile-politikerstod"
            "check-profile-wireguard"
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
            server.tags.all = {};
            client.tags.all = {};
          };
        };
        user-p = {
          module = {
            name = "users";
            input = "clan-core";
          };
          roles.default = {
            tags.all = {};
            settings = {
              user = "p";
              prompt = true;
            };
          };
        };
        admin = {
          roles.default = {
            tags.all = {};
            settings = {
              allowedKeys = {
                "p" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6uq8nXD+QBMhXqRNywwCa/dl2VVvG/2nvkw9HEPFzn";
              };
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
