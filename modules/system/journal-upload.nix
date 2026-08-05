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
      systemd.services.systemd-journal-upload.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = lib.mkForce "root";
      };
    };
  };
}
