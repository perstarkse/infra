_: {
  config.flake.homeModules.llm-agents-cli = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.my.llm-agents-cli;
  in {
    options.my.llm-agents-cli = {
      enable = lib.mkEnableOption ''
        llm-agents CLI tools into the user profile via pkgs.llm-agents.
      '';

      packages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["opencode" "codex" "claude-code" "amp" "agent-browser"];
        description = ''
          Names under pkgs.llm-agents to install into the user profile.
          Requires the llm-agents overlay in nixpkgs.overlays.
        '';
      };
    };

    config = lib.mkIf (cfg.enable && cfg.packages != []) {
      home.packages =
        map (
          name:
            pkgs.llm-agents.${name}
          or (throw "pkgs.llm-agents.${name} does not exist — check llm-agents.nix package names")
        )
        cfg.packages;
    };
  };
}
