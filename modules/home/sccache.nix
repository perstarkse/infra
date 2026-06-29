{
  config.flake.homeModules.sccache = {
    lib,
    pkgs,
    config,
    ...
  }: let
    # Shared with modules/system/sccache-daemon.nix so devshell cargo builds,
    # the bubblewrap codex sandbox, and nix flake check all hit one cache.
    sccacheDir = "/var/cache/sccache-daemon";
  in {
    config = {
      home = {
        packages = [pkgs.sccache];
        sessionVariables = {
          RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
          SCCACHE_DIR = sccacheDir;
          SCCACHE_CACHE_SIZE = "150G";
          CARGO_INCREMENTAL = "0";
        };
      };
      programs.fish.interactiveShellInit =
        lib.mkIf (config.programs.fish.enable or false)
        (lib.mkAfter ''
          set -gx RUSTC_WRAPPER ${pkgs.sccache}/bin/sccache
          set -gx SCCACHE_DIR ${lib.escapeShellArg sccacheDir}
          set -gx SCCACHE_CACHE_SIZE 150G
          set -gx CARGO_INCREMENTAL 0
        '');
    };
  };
}
