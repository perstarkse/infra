{inputs, ...}: {
  config.flake.homeModules.agent-browser = {
    pkgs,
    lib,
    config,
    ...
  }: let
    inherit (pkgs.stdenv.hostPlatform) system;
    cfg = config.programs.agent-browser;
    defaultPackage = inputs.llm-agents.packages.${system}.agent-browser;
  in {
    options.programs.agent-browser = {
      enable = lib.mkEnableOption "Install the agent-browser CLI for headless browser automation.";

      package = lib.mkOption {
        type = lib.types.package;
        default = defaultPackage;
        defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.agent-browser";
        description = "Package to install for the agent-browser CLI.";
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [cfg.package];
    };
  };
}
