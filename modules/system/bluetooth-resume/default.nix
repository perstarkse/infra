{
  config.flake.nixosModules.bluetooth-resume = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.bluetooth-resume;

    scriptSubstitutions = [
      "@BLUETOOTHCTL@"
      "@GREP@"
      "@SLEEP@"
      "@LOGGER@"
      "@SEQ@"
      "@SYSTEMCTL@"
      "@MAX_ATTEMPTS@"
      "@RETRY_INTERVAL@"
    ];

    scriptReplacements = [
      "${pkgs.bluez}/bin/bluetoothctl"
      "${pkgs.gnugrep}/bin/grep"
      "${pkgs.coreutils}/bin/sleep"
      "${pkgs.util-linux}/bin/logger"
      "${pkgs.coreutils}/bin/seq"
      "${pkgs.systemd}/bin/systemctl"
      (toString cfg.maxAttempts)
      (toString cfg.retrySeconds)
    ];

    bluetoothResume =
      pkgs.writeShellScript "bluetooth-resume"
      (lib.replaceStrings scriptSubstitutions scriptReplacements (builtins.readFile ./scripts/resume.sh));

    sleepTargets = [
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
  in {
    options.my.bluetooth-resume = {
      enable = lib.mkEnableOption "Fast Bluetooth recovery after system sleep";

      maxAttempts = lib.mkOption {
        type = lib.types.int;
        default = 20;
        description = ''
          Resume attempts to bring the Bluetooth adapter back after system sleep.
          Each attempt probes adapter state and tries bluetoothctl power on.
        '';
      };

      retrySeconds = lib.mkOption {
        type = lib.types.float;
        default = 0.25;
        description = "Seconds between resume attempts when the adapter is not ready yet.";
      };
    };

    config = lib.mkIf cfg.enable {
      systemd.services.bluetooth-resume-recover = {
        description = "Recover Bluetooth after resume";
        wantedBy = sleepTargets;
        after = sleepTargets;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = bluetoothResume;
        };
      };
    };
  };
}
