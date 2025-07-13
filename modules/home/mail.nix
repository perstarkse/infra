{
  config.flake.homeModules.mail = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.programs.mail;
    enableThunderbird = lib.elem "thunderbird" cfg.clients;
    enableAerc = lib.elem "aerc" cfg.clients;
  in {
    options.my.programs.mail.clients = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["aerc" "thunderbird"];
      description = "List of mail clients to enable (e.g., 'aerc', 'thunderbird').";
    };
    options.my.programs.mail.passwordPath = lib.mkOption {
      type = lib.types.str;
      description = "Absolute path mail-pw file.";
    };

    config = {
      accounts.email.accounts = {
        "perstark.se" = {
          realName = "Per Stark";
          address = "perstark.se@gmail.com";
          userName = "perstark.se@gmail.com";
          imap.host = "imap.gmail.com";
          smtp.host = "smtp.gmail.com";
          passwordCommand = "${pkgs.coreutils}/bin/cat ${config.my.secrets."mail-gmail-1-password"}";
          flavor = "gmail.com";
          thunderbird = lib.mkIf enableThunderbird {
            enable = true;
            profiles = [];
          };
          aerc = lib.mkIf enableAerc {
            enable = true;
            extraAccounts.default = "INBOX";
          };
        };
        # "sprlkhick" = {
        #   realName = "Per Stark";
        #   address = "sprlkhick@gmail.com";
        #   userName = "sprlkhick@gmail.com";
        #   imap = {
        #     host = "imap.gmail.com";
        #     port = 993;
        #     tls.enable = true;
        #   };
        #   smtp.host = "smtp.gmail.com";
        #   passwordCommand = "${pkgs.coreutils}/bin/cat ${config.sops.secrets."mail/gmail/sprlkhick".path}";
        #   flavor = "plain";
        #   thunderbird = lib.mkIf enableThunderbird {
        #     enable = true;
        #     profiles = [];
        #   };
        #   aerc = lib.mkIf enableAerc {
        #     enable = true;
        #   };
        # };
        # "mojotastic-disroot" = {
        #   realName = "mojotastic";
        #   address = "mojotastic@disroot.org";
        #   userName = "mojotastic@disroot.org";
        #   imap.host = "disroot.org";
        #   smtp.host = "disroot.org";
        #   passwordCommand = "${pkgs.coreutils}/bin/cat ${config.sops.secrets."mail/disroot/mojotastic".path}";
        #   thunderbird = lib.mkIf enableThunderbird {
        #     enable = true;
        #     profiles = [];
        #   };
        #   aerc = lib.mkIf enableAerc {
        #     enable = true;
        #     smtpAuth = "plain";
        #     extraAccounts.default = "INBOX";
        #   };
        # };
        "per@stark.pub" = {
          primary = true;
          realName = "Per Stark";
          address = "per@stark.pub";
          userName = "per@stark.pub";
          imap = {
            host = "mail.stark.pub";
            port = 993;
            tls.enable = true;
          };
          smtp = {
            host = "mail.stark.pub";
            port = 465;
            tls.enable = true;
          };
          passwordCommand = "${pkgs.coreutils}/bin/cat ${config.my.secrets."mail-personal-1-password"}";
          thunderbird = lib.mkIf enableThunderbird {
            enable = true;
            profiles = [];
          };
          aerc = lib.mkIf enableAerc {
            enable = true;
            extraAccounts.default = "INBOX";
          };
        };
        # "work@stark.pub" = {
        #   realName = "Per Stark";
        #   address = "work@stark.pub";
        #   userName = "work@stark.pub";
        #   imap = {
        #     host = "mail.stark.pub";
        #     port = 993;
        #     tls.enable = true;
        #   };
        #   smtp = {
        #     host = "mail.stark.pub";
        #     port = 465;
        #     tls.enable = true;
        #   };
        #   passwordCommand = "${pkgs.coreutils}/bin/cat ${config.sops.secrets."mail/stark/work_pass".path}";
        #   thunderbird = lib.mkIf enableThunderbird {
        #     enable = true;
        #     profiles = [];
        #   };
        #   aerc = lib.mkIf enableAerc {
        #     enable = true;
        #     extraAccounts.default = "INBOX";
        #   };
        # };
        # "services@stark.pub" = {
        #   realName = "Services - Stark";
        #   address = "services@stark.pub";
        #   userName = "services@stark.pub";
        #   imap = {
        #     host = "mail.stark.pub";
        #     port = 993;
        #     tls.enable = true;
        #   };
        #   smtp = {
        #     host = "mail.stark.pub";
        #     port = 465;
        #     tls.enable = true;
        #   };
        #   passwordCommand = "${pkgs.coreutils}/bin/cat ${config.sops.secrets."mail/stark/services_pass".path}";
        #   thunderbird = lib.mkIf enableThunderbird {
        #     enable = true;
        #     profiles = [];
        #   };
        #   aerc = lib.mkIf enableAerc {
        #     enable = true;
        #     extraAccounts.default = "INBOX";
        #   };
        # };
      };

      programs.thunderbird = lib.mkIf enableThunderbird {
        enable = true;
        profiles."default".isDefault = true;
      };

      programs.aerc = lib.mkIf enableAerc {
        enable = true;
        extraConfig = {
          general.unsafe-accounts-conf = true;
          filters = {
            "text/plain" = "cat";
            "text/html" = "w3m -T text/html";
            "text/markdown" = "glow -";
            "application/pdf" = "pdftotext - -";
          };
        };
      };

      home.packages = lib.mkIf enableAerc (with pkgs; [
        poppler
        w3m
        glow
      ]);
    };
  };
}
