{
  config.flake.homeModules.secret-wrappers = {
    config,
    lib,
    osConfig,
    pkgs,
    ...
  }: let
    cfg = (config.my.secrets.wrappedHomeBinaries or []);

    mkWrapper = entry:
      let
        name = entry.name;
        command = entry.command;
        envVar = entry.envVar;
        secretPath = entry.secretPath;
        useSystemdRun = entry.useSystemdRun or false;
        wrapperScript = if useSystemdRun then
          pkgs.writeShellScriptBin name ''
            set -euo pipefail
            systemd-run --user --wait --collect --pty \
              -p LoadCredential='${envVar}':'${secretPath}' \
              bash -lc 'export '${envVar}'="$(cat "$CREDENTIALS_DIRECTORY/'${envVar}'")"; exec '${command}' "$@"' bash "$@"
          ''
        else
          pkgs.writeShellScriptBin name ''
            set -euo pipefail
            export '${envVar}'="$(cat '${secretPath}')"
            exec '${command}' "$@"
          '';
      in wrapperScript;

    wrappers = map mkWrapper cfg;

  in {
    config = {
      home.packages = wrappers;

      # Provide a helpful assertion if the user configured entries but my.secrets is missing
      assertions = [
        {
          assertion = (cfg == []) || (config ? my && config.my ? secrets);
          message = "my.secrets.wrappedHomeBinaries is set but config.my.secrets is not available in Home Manager; ensure modules/home/options.nix is imported or osConfig.my.secrets is provided.";
        }
      ];
    };
  };
} 