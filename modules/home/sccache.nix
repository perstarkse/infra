{
  config.flake.homeModules.sccache = {
    lib,
    pkgs,
    config,
    ...
  }: let
    cacheBase =
      lib.attrByPath ["xdg" "cacheHome"] (config.home.homeDirectory + "/.cache") config;
    sccacheDir = cacheBase + "/sccache";
  in {
    config = {
      home.packages = [pkgs.sccache];
      home.sessionVariables = {
        RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
        SCCACHE_DIR = sccacheDir;
        SCCACHE_CACHE_SIZE = "50G";
        CARGO_INCREMENTAL = "0";
      };
      home.activation.ensureSccacheDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p ${lib.escapeShellArg sccacheDir}
      '';
      programs.fish.interactiveShellInit =
        lib.mkIf (config.programs.fish.enable or false)
        (lib.mkAfter ''
          set -gx RUSTC_WRAPPER ${pkgs.sccache}/bin/sccache
          set -gx SCCACHE_DIR ${lib.escapeShellArg sccacheDir}
          set -gx SCCACHE_CACHE_SIZE 50G
          set -gx CARGO_INCREMENTAL 0
        '');
    };
  };
}
