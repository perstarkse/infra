_: {
  "frigate" = {
    share = true;
    files = {
      "rtsp-main-url" = {
        mode = "0400";
        neededFor = "services";
      };
      "rtsp-sub-url" = {
        mode = "0400";
        neededFor = "services";
      };
    };
    prompts = {
      "rtsp-main-url" = {
        description = "Frigate RTSP main stream URL (rtsp://user:pass@host:554/h264Preview_01_main)";
        type = "hidden";
        persist = true;
      };
      "rtsp-sub-url" = {
        description = "Frigate RTSP sub stream URL (rtsp://user:pass@host:554/h264Preview_01_sub)";
        type = "hidden";
        persist = true;
      };
    };
    script = ''
      set -euo pipefail
      mkdir -p "$out"
      cp "$prompts/rtsp-main-url" "$out/rtsp-main-url"
      cp "$prompts/rtsp-sub-url" "$out/rtsp-sub-url"
      chmod 0400 "$out/rtsp-main-url" "$out/rtsp-sub-url"
    '';
    meta.tags = ["service" "frigate"];
  };
}
