# hermes-inspect on the workstations: inspect and chat with the personal agent
# running on makemake.
#
# The agent is a container on a server, so from a laptop everything is remote:
#   - read paths go through the gateway API server (bearer key read from the
#     deployed secret on the target, never through the local shell), and
#   - chat has two shapes: `ask` for one scripted turn, `tui` for the real
#     Hermes TUI over an SSH PTY.
#
# The native Hermes dashboard is deliberately NOT offered: container mode
# forbids backend.mode outright (an eval assertion in upstream's NixOS module),
# so there is no dashboard process to point a browser at. Open WebUI on
# makemake covers the browser case by talking to the same API server.
_: {
  config.flake.homeModules.hermes-inspect = {
    lib,
    pkgs,
    config,
    ...
  }: let
    cfg = config.my.hermes-inspect;
  in {
    options.my.hermes-inspect = {
      enable = lib.mkEnableOption "hermes-inspect CLI for the personal agent";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../pkgs/hermes-inspect {
          inherit (cfg) machine sshUser sshHost;
          inherit (cfg) apiPort;
          inherit (cfg) signalPort;
          inherit (cfg) stateDir;
        };
        defaultText = lib.literalExpression ''
          pkgs.callPackage ../../pkgs/hermes-inspect {
            machine = config.my.hermes-inspect.machine;
            sshUser = config.my.hermes-inspect.sshUser;
            sshHost = config.my.hermes-inspect.sshHost;
            apiPort = config.my.hermes-inspect.apiPort;
            signalPort = config.my.hermes-inspect.signalPort;
            stateDir = config.my.hermes-inspect.stateDir;
          }
        '';
        description = ''
          The CLI package, built from the options below — so setting
          `machine` actually reaches the script. Override wholesale only to
          change something the options do not expose.
        '';
      };

      machine = lib.mkOption {
        type = lib.types.str;
        default = "makemake";
        description = "Clan machine the agent runs on. Documentation/identity only — plain ssh uses sshHost.";
      };

      sshUser = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "ssh user on the agent host. Needs to read the deployed env secret and run docker/systemctl.";
      };

      sshHost = lib.mkOption {
        type = lib.types.str;
        default = "makemake.lan";
        description = ''
          Hostname or address to ssh to. The FQDN, not the bare Clan machine
          name: router split DNS serves `makemake.lan`, while the bare name is
          a Clan-side alias only `clan ssh` understands — plain ssh cannot
          resolve it.
        '';
      };

      apiPort = lib.mkOption {
        type = lib.types.port;
        default = 8642;
        description = ''
          Gateway API server port (API_SERVER_PORT in the agent's env secret).
          Must match my.hermes.firewallPort on the target.
        '';
      };

      signalPort = lib.mkOption {
        type = lib.types.port;
        default = 8085;
        description = "signal-cli SSE port, shown by `hermes-inspect status` so a dead channel is obvious.";
      };

      stateDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/hermes";
        description = ''
          Agent state root on the target. HERMES_HOME is <stateDir>/.hermes and
          the container binary is <stateDir>/current-package/bin/hermes — both are
          what the remote one-shot runs point at. Must match my.hermes.stateDir
          on the agent host.
        '';
      };

      sshAuthSock = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Value exported as SSH_AUTH_SOCK before calling `clan ssh`. null keeps
          whatever the environment already has — do not hard-code a uid here,
          the workstation user's runtime uid is not the same on every machine.

          Only relevant if you set sshUser/sshHost to a target reached through
          an ssh-agent. With the default plain-ssh setup the fleet key comes
          from ~/.ssh and this can stay null.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [cfg.package];

      # The CLI carries ssh/jq/util-linux in its own runtimeInputs, so nothing
      # else is needed on PATH — only the fleet ssh key, which is a
      # per-workstation file, not a session fact.
      home.sessionVariables = lib.optionalAttrs (cfg.sshAuthSock != null) {
        SSH_AUTH_SOCK = cfg.sshAuthSock;
      };
    };
  };
}
