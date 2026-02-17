# {
#   config.flake.nixosModules.frigate = {
#     lib,
#     config,
#     self,
#     pkgs,
#     ...
#   }: let
#     openvino_model_xml = pkgs.copyPathToStore (builtins.path {
#       path = ../../dependencies/openvino-model/ssdlite_mobilenet_v2.xml;
#       name = "openvino_model_xml";
#     });
#     openvino_model_bin = pkgs.copyPathToStore (builtins.path {
#       path = ../../dependencies/openvino-model/ssdlite_mobilenet_v2.bin;
#       name = "openvino_model_bin";
#     });
#   in {
#     config = {
#       environment.etc."frigate-models/ssdlite_mobilenet_v2.xml".source = openvino_model_xml;
#       environment.etc."frigate-models/ssdlite_mobilenet_v2.bin".source = openvino_model_bin;
#       hardware.graphics.enable = true;
#       systemd.tmpfiles.rules = [
#         "d /storage/frigate 0750 frigate frigate -"
#         "d /storage/frigate/recordings 0750 frigate frigate -"
#         "d /storage/frigate/clips 0750 frigate frigate -"
#         "d /storage/frigate/cache 0750 frigate frigate -"
#       ];
#       hardware.graphics.extraPackages = with pkgs; [
#         intel-media-driver
#         openvino
#         # openvino-inference-engine
#       ];
#       systemd.services.frigate.serviceConfig.SupplementaryGroups = [
#         "render"
#         "video"
#       ];
#       # Bind mount everything under /var/lib/frigate
#       systemd.services.frigate.serviceConfig.BindPaths = [
#         "/storage/frigate:/var/lib/frigate"
#       ];
#       services.frigate = {
#         enable = true;
#         hostname = "frigate.io.lan";
#         checkConfig = true;
#         vaapiDriver = "iHD";
#         settings = {
#           detectors = {
#             ov = {
#               type = "openvino";
#               device = "GPU";
#               model = {
#                 path = "/etc/frigate-models/ssdlite_mobilenet_v2.xml";
#               };
#             };
#           };
#           ffmpeg = {
#             hwaccel_args = "preset-vaapi";
#           };
#           record = {
#             enabled = true;
#             retain.days = 0;
#           };
#           mqtt.enabled = false;
#           cameras = {
#             reolink_p330 = {
#               ffmpeg.inputs = [
#                 {
#                   path = "rtsp://127.0.0.1:8554/reolink_p330_sub";
#                   input_args = "preset-rtsp-restream";
#                   roles = ["detect"];
#                 }
#                 {
#                   path = "rtsp://127.0.0.1:8554/reolink_p330";
#                   input_args = "preset-rtsp-restream";
#                   roles = ["record"];
#                 }
#               ];
#               detect = {
#                 width = 640;
#                 height = 360;
#                 fps = 5;
#               };
#             };
#           };
#         };
#       };
#     };
#   };
# }
{
  config.flake.nixosModules.frigate = _: let
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
    config = {
      # GPU access for container user
      users.groups.video.members = ["frigate"];
      users.groups.render.members = ["frigate"];
      users.users.frigate = {
        isSystemUser = true;
        group = "frigate";
      };
      users.groups.frigate = {};

      # Required dirs
      systemd.tmpfiles.rules = [
        "d /storage/frigate 0750 frigate frigate -"
        "d /storage/frigate/config 0750 frigate frigate -"
        "d /storage/frigate/recordings 0750 frigate frigate -"
        "d /storage/frigate/clips 0750 frigate frigate -"
        "d /storage/frigate/cache 0750 frigate frigate -"
      ];

      systemd.services.frigate-config-sync = {
        description = "Sync Frigate config into persistent storage";
        before = ["podman-frigate.service"];
        serviceConfig.Type = "oneshot";
        script = ''
          install -D -m 0644 ${frigateConfigYAML} /storage/frigate/config/config.yml
        '';
      };

      systemd.services.podman-frigate = {
        requires = ["frigate-config-sync.service"];
        after = ["frigate-config-sync.service"];
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
