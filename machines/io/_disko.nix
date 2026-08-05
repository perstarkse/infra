{
  # INSTALL-TIME ONLY. Renamed `_disko.nix` so clan's machine auto-import
  # (exact filename `disko.nix`) does NOT evaluate it on the running machines.
  # To reinstall this machine from the flake:
  #   1. git mv machines/<m>/_disko.nix machines/<m>/disko.nix
  #   2. git rm machines/<m>/hardware-configuration.nix
  #   3. remove ./hardware-configuration.nix from configuration.nix imports
  #   4. clan machines install <m> --target-host <spare-or-replacement>
  # Deploying this layout to a running machine (machine-update) will NOT format
  # anything, but the generated fileSystems point at /dev/disk/by-partlabel
  # paths that only exist after a disko install, so the machine would fail to
  # boot. Only land it with a reinstall.
  #
  # System NVMe is disko-managed (formatted at install). The /storage SSD is
  # NOT disko-managed: it's a mount-only nodev entry by UUID so a reinstall
  # preserves the data.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  disko.devices = {
    disk = {
      system = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-KINGSTON_SNVS1000G_50026B778475D058";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "858G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
            swap = {
              size = "100%";
              content = {type = "swap";};
            };
          };
        };
      };
    };
    nodev = {
      # Data disk: mount-only, never formatted.
      "/storage" = {
        type = "nodev";
        fsType = "ext4";
        device = "/dev/disk/by-uuid/d2a34464-bf0e-4ab8-a3d5-2e1f73d24c4f";
      };
    };
  };
}
