{
  config.flake.nixosModules.nvidia = {
    lib,
    config,
    pkgs,
    ...
  }: {
    options.my.hardware.nvidia.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable NVIDIA proprietary drivers and settings.";
    };

    config = lib.mkIf config.my.hardware.nvidia.enable {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      boot.initrd.kernelModules = ["nvidia"];

      # This line will now work because 'config.boot' is available
      # during a proper NixOS module evaluation.
      boot.extraModulePackages = [config.boot.kernelPackages.nvidiaPackages.stable];

      services.xserver.videoDrivers = ["nvidia"];

      hardware.nvidia = {
        open = true;
        modesetting.enable = true;
        powerManagement.enable = true;
        forceFullCompositionPipeline = false;
        nvidiaSettings = true;
      };

      environment.systemPackages = [pkgs.nvidia-vaapi-driver];

      environment.sessionVariables = {
        GBM_BACKEND = "nvidia-drm";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        LIBVA_DRIVER_NAME = "nvidia";
        __NV_DISABLE_EXPLICIT_SYNC = "1";
      };

      environment.etc."nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool.json".text = ''
        {
          "rules": [
            {
              "pattern": { "feature": "cmdline", "matches": "Hyprland" },
              "profile": "Limit Free Buffer Pool On Wayland Compositors"
            }
          ],
          "profiles": [
            {
              "name": "Limit Free Buffer Pool On Wayland Compositors",
              "settings": [ { "key": "GLVidHeapReuseRatio", "value": 1 } ]
            }
          ]
        }
      '';
    };
  };
}
