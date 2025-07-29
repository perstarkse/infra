{
  config.flake.homeModules.mail-clients-setup = {
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
      description = "List of mail clients to enable.";
    };

    config = {
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
