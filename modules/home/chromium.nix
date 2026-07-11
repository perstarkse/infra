{
  config.flake.homeModules.chromium = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.chromium;
  in {
    options.my.chromium.enable = lib.mkEnableOption "chromium with extensions";

    config = lib.mkIf cfg.enable {
      programs.chromium = {
        enable = true;
        # package = pkgs.ungoogled-chromium;
        extensions = [
          {
            id = "acmacodkjbdgmoleebolmdjonilkdbch";
            version = "0.93.52";
          }
          {
            id = "ddkjiahejlhfcafbddmgiahcphecmpfh";
            version = "2025.928.1920";
          }
        ];
      };
    };
  };
}
