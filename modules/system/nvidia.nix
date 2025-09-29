{
  config.flake.nixosModules.nvidia = {pkgs, ...}: {
    config = {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      boot.initrd.availableKernelModules = [];
      boot.initrd.kernelModules = [];
      # boot.initrd.availableKernelModules = ["nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"];
      # boot.extraModprobeConfig = ''
      #   options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
      # '';

      services.xserver.videoDrivers = ["nvidia"];

      hardware.nvidia = {
        open = false;
        modesetting.enable = true;
        powerManagement.enable = true;
        # powerManagement.finegrained = true;
        forceFullCompositionPipeline = false;
        nvidiaSettings = true;
      };
      environment = {
        systemPackages = [pkgs.nvidia-vaapi-driver];

        sessionVariables = {
          GBM_BACKEND = "nvidia-drm";
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
          LIBVA_DRIVER_NAME = "nvidia";
          __NV_DISABLE_EXPLICIT_SYNC = "1"; # needed for looking glass https://github.com/gnif/LookingGlass/issues/1151
          NVD_BACKEND = "direct";
        };

        etc."nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool.json".text = ''
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
  };
}
