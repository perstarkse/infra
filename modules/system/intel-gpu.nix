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
          level-zero
        ];
      };

      environment.systemPackages = with pkgs; [
        clinfo
        intel-gpu-tools
      ];

      # Load xe driver early in initrd for Battlemage GPUs
      boot.initrd.kernelModules = ["xe"];

      services.xserver.videoDrivers = ["modesetting"];

      environment.sessionVariables = {
        LIBVA_DRIVER_NAME = "iHD";
      };
    };
  };
}
