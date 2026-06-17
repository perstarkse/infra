{inputs, ...}: {
  config.flake.nixosModules.indicator-alert-daemon = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.indicator-alert-daemon;

    tickerJson =
      map (
        t:
          {
            inherit (t) symbol;
            inherit (t) indicators;
          }
          // lib.optionalAttrs (t.intervalType != null) {interval_type = t.intervalType;}
      )
      cfg.tickers;

    format = pkgs.formats.json {};
    configFile = format.generate "indicator-alert-daemon.json" (
      {
        ntfy_url = cfg.ntfyUrl;
        interval_type = cfg.intervalType;
        frequency_seconds = cfg.pollFrequency;
        ticker_delay_ms = cfg.tickerDelayMs;
        tickers = tickerJson;
      }
      // lib.optionalAttrs (cfg.dbPath != null) {db_path = cfg.dbPath;}
    );
  in {
    imports = [
      (import "${inputs.indicator-alert-daemon}/module.nix" inputs.indicator-alert-daemon)
    ];

    services.indicator-alert-daemon.ntfyUrl = lib.mkDefault "https://ntfy.lan.stark.pub/indicator-alerts";

    systemd.services.indicator-alert-daemon.serviceConfig.ExecStart = lib.mkForce "${inputs.indicator-alert-daemon.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/indicator-alert-daemon ${configFile}";
  };
}
