{
  config.flake.nixosModules.go2rtc = {pkgs, ...}: {
    # Standalone go2rtc service
    config = {
      services.go2rtc = {
        enable = true;

        settings = {
          api.listen = "127.0.0.1:1984";
          rtsp.listen = "127.0.0.1:8554";

          streams = {
            reolink_p330 = [
              "rtsp://watcher:YSx%250z3nTS5zp%21hN%25V9I@10.0.0.103:554/h264Preview_01_main"
            ];

            reolink_p330_sub = [
              "rtsp://watcher:YSx%250z3nTS5zp%21hN%25V9I@10.0.0.103:554/h264Preview_01_sub"
            ];
          };
        };
      };
    };
  };
}
