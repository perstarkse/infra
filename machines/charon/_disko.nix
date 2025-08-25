{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  disko.devices = {
    disk = {
      # System disk (Force MP600 ~1TB NVMe)
      system = {
        device = "/dev/disk/by-id/nvme-Force_MP600_2104822900012855319B";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "2G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
  size = "100%";
  type = "8300";
  content = {
    type = "btrfs";
    extraArgs = [ "-L" "nixos-root" ];
    mountpoint = "/";
    mountOptions = [ "compress=zstd" "noatime" ];
    subvolumes = {
      "@root" = {
        mountpoint = "/";
        create = "always"; # recreated on install
      };
      "@nix" = {
        mountpoint = "/nix";
        create = "always";
      };
      "@var" = {
        mountpoint = "/var";
        create = "always";
      };
      "@home" = {
        mountpoint = "/home";
        create = "if-missing"; # persists across reinstalls
      };
    };
  };
};

      # Data disks
      ssd-intel-a = {
        device = "/dev/disk/by-id/wwn-0x55cd2e41564d34ed";
        type = "disk";
        content = {
          type = "filesystem";
          # keep existing ext4
          mountpoint = "/mnt/sdb";
          mountOptions = [ "noatime" ];
        };
      };

      ssd-intel-b = {
        device = "/dev/disk/by-id/wwn-0x55cd2e415638bd82";
        type = "disk";
        content = {
          type = "filesystem";
          mountpoint = "/mnt/sdc";
          mountOptions = [ "noatime" ];
        };
      };

      # Windows disk (declared but untouched)
      kingston-win = {
        device = "/dev/disk/by-id/wwn-0x50026b775804823b";
        type = "disk";
      };
    };
  };
}