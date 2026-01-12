{
  config.flake.homeModules.agent-browser = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.programs.agent-browser;

    defaultPackage = pkgs.callPackage ../../pkgs/agent-browser {};
  in {
    options.programs.agent-browser = {
      enable = lib.mkEnableOption "Install the agent-browser CLI for headless browser automation.";

      package = lib.mkOption {
        type = lib.types.package;
        default = defaultPackage;
        defaultText = lib.literalExpression "pkgs.callPackage ../../pkgs/agent-browser {}";
        description = "Package to install for the agent-browser CLI.";
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [
        cfg.package
        pkgs.playwright-test
        pkgs.playwright-driver
      ];

      home.sessionVariables = {
        PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
      };
    };
  };
}
