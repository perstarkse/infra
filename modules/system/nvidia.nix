{
  config.flake.nixosModules.nvidia = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.my.gui;
    bufferProfileName = "Limit Free Buffer Pool On Wayland Compositors";
    bufferRules = [
      # {
      #   pattern = {
      #     feature = "cmdline";
      #     matches = "Hyprland";
      #   };
      #   profile = bufferProfileName;
      # }
      {
        pattern = {
          feature = "procname";
          matches = "niri";
        };
        profile = bufferProfileName;
      }
    ];
    bufferProfiles = [
      {
        name = bufferProfileName;
        settings = [
          {
            key = "GLVidHeapReuseRatio";
            value = 0;
          }
        ];
      }
    ];
  in {
    config = {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      boot.initrd.availableKernelModules = [];
      boot.initrd.kernelModules = [];

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

        sessionVariables = lib.mkIf cfg.enable (
          {
            GBM_BACKEND = "nvidia-drm";
            __GLX_VENDOR_LIBRARY_NAME = "nvidia";
            LIBVA_DRIVER_NAME = "nvidia";
            NVD_BACKEND = "direct";
          }
          // lib.optionalAttrs config.my.vfio.enable {
            # needed for Looking Glass
            __NV_DISABLE_EXPLICIT_SYNC = "1";
          }
        );

        etc = lib.mkIf cfg.enable {
          "nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool.json".text = builtins.toJSON {
            rules = bufferRules;
            profiles = bufferProfiles;
          };
        };
      };
    };
  };
}
