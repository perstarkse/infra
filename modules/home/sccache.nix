{
  config.flake.homeModules.sccache = {
    lib,
    pkgs,
    config,
    ...
  }: let
    cfg = config.my.sccache;
  in {
    options.my.sccache = {
      enable = lib.mkEnableOption "sccache wrapper for rust dev";
      cacheDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/cache/sccache-daemon";
        description = "Shared sccache dir, keep in sync with my.sccache-daemon.cacheDir.";
      };
      cacheSize = lib.mkOption {
        type = lib.types.str;
        default = "150G";
        description = "SCCACHE_CACHE_SIZE.";
      };
    };

    config = lib.mkIf cfg.enable {
      home = {
        packages = [pkgs.sccache];
        sessionVariables = {
          RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
          SCCACHE_DIR = cfg.cacheDir;
          SCCACHE_CACHE_SIZE = cfg.cacheSize;
          CARGO_INCREMENTAL = "0";
        };
      };
      programs.fish.interactiveShellInit =
        lib.mkIf (config.programs.fish.enable or false)
        (lib.mkAfter ''
          set -gx RUSTC_WRAPPER ${pkgs.sccache}/bin/sccache
          set -gx SCCACHE_DIR ${lib.escapeShellArg cfg.cacheDir}
          set -gx SCCACHE_CACHE_SIZE ${lib.escapeShellArg cfg.cacheSize}
          set -gx CARGO_INCREMENTAL 0
        '');
    };
  };
}
