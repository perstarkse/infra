{
  config,
  inputs,
  ...
}: let
  inherit (config) flake;
in {
  config.flake.homeModules.agentProfile = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.agentProfile;
  in {
    imports = [
      flake.homeModules.options
      flake.homeModules.sops
      flake.homeModules.ssh
      flake.homeModules.herdr
      flake.homeModules.node
      flake.homeModules.git
      flake.homeModules.agentGit
      flake.homeModules.direnv
      flake.homeModules.zoxide
      inputs.agent-tooling.homeModules.pi-agent
      inputs.agent-tooling.homeModules.antigravity
      inputs.agent-tooling.homeModules.shared-skills
      inputs.agent-tooling.homeModules.pi-web
    ];

    options.my.agentProfile = {
      enable = lib.mkEnableOption "personal agent Home Manager profile and toolchain";

      projectsSymlink = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to link ~/projects out-of-store (e.g. /mnt/sdb/repos on charon). If null, native directory is used.";
      };
    };

    config = lib.mkIf cfg.enable {
      my.agentTooling = {
        pi-agent = {
          enable = true;
          permissionSystem.enable = false;
          mcpServers = flake.lib.mkPiMcpServers {
            inherit config pkgs;
            inputs = {
              agentTooling = inputs.agent-tooling;
              digikeyMcp = inputs.digikey-mcp;
            };
            tokenStore = "/home/agent/.local/state/digikey-mcp/tokens.json";
          };
        };
        antigravity.enable = true;
        shared-skills.enable = true;
      };

      my.git.enable = true;
      my.agentGit.enable = true;
      my.direnv.enable = true;
      my.zoxide.enable = true;
      my.node.enable = true;
      my.ssh.enable = true;

      home.packages = with pkgs; [
        git
        ripgrep
      ];

      my.herdr = {
        enable = true;
        package = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };

      home.file.".ssh/conf.d/herdr-mesh" = {
        text = ''
          Host makemake 10.0.0.10
            HostName 10.0.0.10
            User agent
            IdentityFile ~/.ssh/id_ed25519
            IdentitiesOnly yes
            BatchMode yes

          Host charon 10.0.0.15
            HostName 10.0.0.15
            User agent
            IdentityFile ~/.ssh/id_ed25519
            IdentitiesOnly yes
            BatchMode yes
        '';
      };

      home.file.".ssh/known_hosts" = {
        text = ''
          10.0.0.10,makemake,makemake.lan ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMLhhyxdh0dr+tfcyBgv9K0s5nK9mfwOENBnFVteZOB9
          10.0.0.15,charon,charon.lan ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINysM9VHtOcjYDAZCTuJl+hjNNHlFExmDx5J7o40Vljh
          10.0.0.1,io,io.lan ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMPugZkqgjBKletbzaNipPLSrq5+ToQFBLyCojQLD8pt
          github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
        '';
      };

      home.file."projects" = lib.mkIf (cfg.projectsSymlink != null) {
        source =
          pkgs.runCommandLocal "projects-out-of-store" {}
          "ln -s ${cfg.projectsSymlink} $out";
      };
    };
  };
}
