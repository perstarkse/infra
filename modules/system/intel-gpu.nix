{
  config.flake.nixosModules.intel-gpu = {pkgs, ...}: {
    config = {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          intel-media-driver
          intel-compute-runtime
          vpl-gpu-rt
        ];
      };

      services.xserver.videoDrivers = ["modesetting"];

      environment.sessionVariables = {
        LIBVA_DRIVER_NAME = "iHD";
      };
    };
  };
}
