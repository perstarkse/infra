{
  config.flake.nixosModules.frigate = {
    config,
    lib,
    mkStandardExposureOptions,
    ...
  }: let
    cfg = config.my.frigate;
    frigateConfigYAML = builtins.toFile "frigate-config.yml" ''
      mqtt:
        enabled: false

      detectors:
        ov:
          type: openvino
          device: GPU
          model:
            path: /openvino-model/ssdlite_mobilenet_v2.xml

      model:
        width: 300
        height: 300
        input_tensor: nhwc
        input_pixel_format: bgr
        labelmap_path: /openvino-model/coco_91cl_bkgr.txt

      go2rtc:
        streams:
          reolink_p330:
            - rtsp://watcher:YSx%250z3nTS5zp%21hN%25V9I@10.0.30.10:554/h264Preview_01_main
          reolink_p330_sub:
            - rtsp://watcher:YSx%250z3nTS5zp%21hN%25V9I@10.0.30.10:554/h264Preview_01_sub

      cameras:
        reolink_p330:
          ffmpeg:
            hwaccel_args: preset-vaapi
            inputs:
              - path: rtsp://127.0.0.1:8554/reolink_p330_sub
                input_args: preset-rtsp-restream
                roles: [detect]
              - path: rtsp://127.0.0.1:8554/reolink_p330
                input_args: preset-rtsp-restream
                roles: [record]

          detect:
            width: 640
            height: 360
            fps: 5

          record:
            enabled: true
            retain:
              days: 0
    '';
  in {
    options.my.frigate = {
      enable = lib.mkEnableOption "Frigate NVR";
      exposure = mkStandardExposureOptions {
        subject = "Frigate";
        visibility = "internal";
      };
    };

    config = lib.mkIf cfg.enable {
      # GPU access for container user
      users = {
        groups = {
          video.members = ["frigate"];
          render.members = ["frigate"];
          frigate = {};
        };
        users.frigate = {
          isSystemUser = true;
          group = "frigate";
        };
      };

      systemd = {
        # Required dirs
        tmpfiles.rules = [
          "d /storage/frigate 0750 frigate frigate -"
          "d /storage/frigate/config 0750 frigate frigate -"
          "d /storage/frigate/recordings 0750 frigate frigate -"
          "d /storage/frigate/clips 0750 frigate frigate -"
          "d /storage/frigate/cache 0750 frigate frigate -"
        ];

        services.frigate-config-sync = {
          description = "Sync Frigate config into persistent storage";
          before = ["podman-frigate.service"];
          serviceConfig.Type = "oneshot";
          script = ''
            install -D -m 0644 ${frigateConfigYAML} /storage/frigate/config/config.yml
          '';
        };

        services.podman-frigate = {
          requires = ["frigate-config-sync.service"];
          after = ["frigate-config-sync.service"];
        };
      };

      my.exposure.services.frigate = lib.mkIf config.my.frigate.exposure.enable {
        upstream = {
          host = config.my.listenNetworkAddress;
          port = 5000;
        };
        http.virtualHosts = lib.optional (config.my.frigate.exposure.domain != null) {
          inherit (config.my.frigate.exposure) domain;
          inherit (config.my.frigate.exposure) lanOnly useWildcard;
        };
      };

      virtualisation.oci-containers.containers.frigate = {
        image = "ghcr.io/blakeblackshear/frigate:0.16.1";
        autoStart = true;
        privileged = true;

        # GPU access
        devices = ["/dev/dri:/dev/dri"];

        # host networking avoids port management and works with HA on same machine
        extraOptions = ["--network=host"];

        environment = {
          LIBVA_DRIVER_NAME = "iHD";
          OPENVINO_DEVICE = "GPU";
          FRIGATE_USE_OPENVINO = "1";
        };

        # Container mounts
        volumes = [
          "/storage/frigate/config:/config"
          "/storage/frigate:/media/frigate"
          # "/etc/openvino-model:/openvino-model:ro"
        ];
      };
    };
  };
}
