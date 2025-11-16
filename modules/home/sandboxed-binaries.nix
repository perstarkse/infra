{
  config.flake.homeModules.sandboxed-binaries = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkOption types mkIf concatMapStringsSep escapeShellArg;

    # Same pattern as your sccache module
    cacheBase =
      lib.attrByPath ["xdg" "cacheHome"]
      (config.home.homeDirectory + "/.cache")
      config;

    sccacheDir = cacheBase + "/sccache";

    cfg = config.my.sandboxedHomeBinaries or [];

    mkSandboxWrapper = entry: let
      name = entry.name;
      program = entry.program;
      defaultArgs = entry.defaultArgs;
      enableRustCache = entry.enableRustCache;
      extraWritableDirs = entry.extraWritableDirs;
      allowNetwork = entry.allowNetwork;
      bindCwd = entry.bindCwd;
    in
      pkgs.writeShellScriptBin name ''
        set -euo pipefail

        BWRAP=${pkgs.bubblewrap}/bin/bwrap
        BASH=${pkgs.bash}/bin/bash

        # Base sandbox args:
        # - DO NOT use --unshare-all (it always unshares net).
        # - Unshare user/ipc/pid/uts; only unshare net when allowNetwork = false.
        args=(
          --unshare-user
          --unshare-ipc
          --unshare-pid
          --unshare-uts
          --new-session
          --die-with-parent

          # Core filesystem (RO where reasonable)
          --ro-bind /nix/store /nix/store
          --ro-bind /usr /usr
          --ro-bind /etc /etc
          --ro-bind /run /run
          --proc /proc
          --dev /dev
          --tmpfs /tmp
        )

        # Network: only isolate if allowNetwork = false
        if [ "${
          if allowNetwork
          then "1"
          else "0"
        }" = "0" ]; then
          args+=( --unshare-net )
        fi

        # Bind the current working directory into the sandbox
        if [ "${
          if bindCwd
          then "1"
          else "0"
        }" = "1" ]; then
          args+=( --bind "$PWD" "$PWD" )
        fi

        # Rust sccache dir (path matches your sccache module)
        if [ "${
          if enableRustCache
          then "1"
          else "0"
        }" = "1" ]; then
          args+=( --bind ${escapeShellArg sccacheDir} ${escapeShellArg sccacheDir} )
        fi

        # Extra writable host directories (Codex config, npm, etc.)
        ${concatMapStringsSep "\n" (dir: ''
            args+=( --bind ${escapeShellArg dir} ${escapeShellArg dir} )
          '')
          extraWritableDirs}

        # Run the program inside the sandbox.
        # We keep your outer env (PATH, RUSTC_WRAPPER, SCCACHE_DIR, etc.)
        # and just exec program + defaultArgs + "$@" in a login-ish shell.
        exec "$BWRAP" "''${args[@]}" -- \
          "$BASH" -lc 'exec "$@"' -- \
          ${escapeShellArg program} ${
          concatMapStringsSep " " escapeShellArg defaultArgs
        } "$@"
      '';
  in {
    options.my.sandboxedHomeBinaries = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Name of the sandboxed wrapper binary to create (e.g. sb-codex).";
          };

          program = mkOption {
            type = types.str;
            description = ''
              Program to execute inside the sandbox
              (e.g. "/home/p/.npm-global/bin/codex" or "codex").
            '';
          };

          defaultArgs = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Arguments passed to the program before any user arguments.";
          };

          bindCwd = mkOption {
            type = types.bool;
            default = true;
            description = "Bind the current working directory read-write into the sandbox.";
          };

          enableRustCache = mkOption {
            type = types.bool;
            default = false;
            description = ''
              If true, bind the sccache cache directory (${sccacheDir})
              read-write into the sandbox.
            '';
          };

          extraWritableDirs = mkOption {
            type = types.listOf types.str;
            default = [];
            description = ''
              Additional host directories to bind read-write into the sandbox
              (e.g. ~/.codex, ~/.npm, ~/.config, ~/.cache).
            '';
          };

          allowNetwork = mkOption {
            type = types.bool;
            default = true;
            description = "Allow network inside the sandbox (false → unshare network).";
          };
        };
      });
      default = [];
      description = ''
        List of sandboxed binaries implemented via bubblewrap. Each entry runs
        the given program inside a bwrap sandbox, inheriting the current environment.
      '';
    };

    config = mkIf (cfg != []) {
      home.packages = map mkSandboxWrapper cfg;
    };
  };
}
