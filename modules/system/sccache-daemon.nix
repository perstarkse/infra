{
  config,
  lib,
  ...
}: let
  # Unified sccache cache directory. Bind-mounted into Nix build sandboxes
  # via nix.settings.extra-sandbox-paths and shared with devshell cargo builds
  # (modules/home/sccache.nix) and the bubblewrap codex sandbox
  # (modules/home/sandboxed-binaries.nix). sccache compiles through (caching
  # skipped) if this is ever unavailable, so no wrapper fallback is needed.
  defaultCacheDir = "/var/cache/sccache-daemon";
  defaultCacheSize = "150G";

  # Factory: turn sccache on for every buildRustPackage call in the target
  # nixpkgs. Skips sccache itself to avoid a circular build (sccache uses
  # buildRustPackage). Handles both the attrset form and the
  # (finalAttrs: { … }) self-referencing form of buildRustPackage args.
  mkSccacheOverlay = {
    sccachePkg,
    cacheDir,
    cacheSize,
  }: final: prev: prev // {
    rustPlatform = prev.rustPlatform // {
      buildRustPackage = args: let
        withSccache = baseAttrs:
          if baseAttrs ? pname && baseAttrs.pname == "sccache"
          then baseAttrs
          else
            baseAttrs
            // {
              nativeBuildInputs =
                (baseAttrs.nativeBuildInputs or [])
                ++ [sccachePkg];
              RUSTC_WRAPPER = "${sccachePkg}/bin/sccache";
              SCCACHE_DIR = cacheDir;
              SCCACHE_CACHE_SIZE = cacheSize;
            };
      in
        if builtins.isFunction args
        then prev.rustPlatform.buildRustPackage (finalAttrs: withSccache (args finalAttrs))
        else prev.rustPlatform.buildRustPackage (withSccache args);
    };
  };
in {
  # Reusable overlay — applies sccache to buildRustPackage in whichever
  # nixpkgs instance imports it. sccache resolves against the consumer's
  # pkgs (final.sccache), so this is self-contained and version-agnostic.
  # Consumers opt in via an untracked sccache.local.nix that imports it,
  # keeping the cache opt-in and free of committed behavioral change.
  config.flake.overlays.sccache =
    final: prev:
      mkSccacheOverlay {
        sccachePkg = final.sccache;
        cacheDir = defaultCacheDir;
        cacheSize = defaultCacheSize;
      }
      final
      prev;

  config.flake.nixosModules.sccache-daemon = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.sccache-daemon;
  in {
    options.my.sccache-daemon = {
      enable = lib.mkEnableOption "sccache for Nix Rust (buildRustPackage) builds";

      cacheDir = lib.mkOption {
        type = lib.types.str;
        default = defaultCacheDir;
        defaultText = lib.literalExpression "/var/cache/sccache-daemon";
        description = ''
          Cache directory bind-mounted into Nix build sandboxes via
          nix.settings.extra-sandbox-paths. Kept in sync with
          modules/home/sccache.nix and modules/home/sandboxed-binaries.nix.
        '';
      };

      cacheSize = lib.mkOption {
        type = lib.types.str;
        default = defaultCacheSize;
        description = "Max cache size (passed as SCCACHE_CACHE_SIZE).";
      };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [pkgs.sccache];

      systemd.tmpfiles.rules = [
        "d ${cfg.cacheDir} 0777 root root -"
      ];

      # Bind-mount the unified cache dir into Nix build sandboxes so opt-in
      # project flakes (politikerstod/wol-web-proxy via sccache.local.nix)
      # built on this host can actually write to it. We deliberately do NOT
      # apply mkSccacheOverlay to nixpkgs.overlays here: wrapping every
      # system buildRustPackage busts the Nix binary cache (cache.nixos.org
      # no longer matches the altered drv hash) and forces local rebuilds of
      # bat/ripgrep/etc. that can't even use sccache inside the sandbox. The
      # Nix binary cache is the cache for nixpkgs Rust packages; sccache is
      # only for non-Nix builds (devshell cargo, codex bubblewrap sandbox,
      # opt-in project flakes).
      nix.settings.extra-sandbox-paths = [cfg.cacheDir];
    };
  };
}