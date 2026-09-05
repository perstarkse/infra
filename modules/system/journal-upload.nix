_: {
  config.flake.nixosModules.journal-upload = {
    config,
    lib,
    ...
  }: {
    options.my.journalUpload = {
      enable = lib.mkEnableOption "stream this host's journal to io's mTLS journal-remote";
      serverUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://10.0.0.1:19532";
        description = "URL of the router's systemd-journal-remote listener.";
      };
    };

    config = lib.mkIf config.my.journalUpload.enable {
      services.journald.upload = {
        enable = true;
        settings = {
          Upload = {
            URL = config.my.journalUpload.serverUrl;
            ServerKeyFile = toString (config.my.secrets.getPath "journal-upload" "client.key");
            ServerCertificateFile = toString (config.my.secrets.getPath "journal-upload" "client.pem");
            TrustedCertificateFile = toString (config.my.secrets.getPath "journal-upload" "ca.pem");
          };
        };
      };

      # The mTLS client key is root-only; run the uploader as root (the module
      # defaults to a DynamicUser that cannot read it).
      systemd.services.systemd-journal-upload = {
        after = [
          "network-online.target"
          "systemd-networkd-wait-online.service"
        ];
        wants = [
          "network-online.target"
          "systemd-networkd-wait-online.service"
        ];
        # Secrets live on tmpfs /run/secrets.d; the state dir is on /var.
        # Without an explicit mount dependency the service can start before
        # sops-nix/varsHelper has populated the mTLS certs, failing the first
        # upload with I/O error / 417 and showing as a cosmetic deploy failure
        # (activating auto-restart at the instant clan checks --failed).
        unitConfig.RequiresMountsFor = [
          "/run/secrets.d"
          "/var/lib/systemd/journal-upload"
        ];
        serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = lib.mkForce "root";
          # Upstream is on-failure with RestartSteps=10 / RestartMaxDelaySec=60;
          # keep that shape but give the network (virbr1 re-create on charon/
          # makemake) time to settle so the deploy-time check does not sample
          # the service in auto-restart. 10s also coalesces the 3-417 quick-
          # retry seen after sysinit-reactivation.
          Restart = lib.mkForce "on-failure";
          RestartSec = lib.mkForce "10s";
          # Large catch-up reads (1-7 GiB from disk, 330M-1.3G peak) legitimately
          # take >3 min; the upstream 3 min watchdog SIGABRTs the upload mid-
          # chunk, leaving the remote with a premature EOF (417) and forcing a
          # full re-read on the next restart.
          WatchdogSec = lib.mkForce "5min";
          TimeoutStartSec = lib.mkForce "5min";
        };
      };
    };
  };
}
