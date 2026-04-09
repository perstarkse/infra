{
  config.flake.homeModules.firefox = {
    config = {
      stylix.targets.firefox.profileNames = ["default"];
      programs.firefox = {
        enable = true;
        profiles = {
          default = {
            id = 0;
            name = "default";
            isDefault = true;
            settings = {
              "browser.startup.homepage" = "https://search.lan.stark.pub";
              "browser.search.defaultenginename" = "ddg";
              "browser.search.order.1" = "ddg";
              "browser.compactmode.show" = true;
              "browser.cache.disk.enable" = false;
              "widget.disable-workspace-management" = true;
            };
            search = {
              force = true;
              default = "ddg";
              order = ["ddg"];
            };
          };
        };
      };
    };
  };
}
