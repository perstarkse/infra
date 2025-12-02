{
  config.flake.homeModules.chromium = _: {
    config = {
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
