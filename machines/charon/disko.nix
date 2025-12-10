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
              priority = 1;
              name = "ESP";
              start = "1M";
              end = "2G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = ["-f" "-L" "nixos-root"];
                subvolumes = {
                  # Root filesystem
                  "/rootfs" = {
                    mountpoint = "/";
                  };
                  # Nix store with compression and noatime
                  "/nix" = {
                    mountOptions = ["compress=zstd" "noatime"];
                    mountpoint = "/nix";
                  };
                  # Var directory
                  "/var" = {
                    mountOptions = ["compress=zstd"];
                    mountpoint = "/var";
                  };
                  # Home directory with compression
                  "/home" = {
                    mountOptions = ["compress=zstd"];
                    mountpoint = "/home";
                  };
                };
              };
            };
          };
        };
      };

      # Data disks - existing filesystems will be preserved
      ssd-intel-a = {
        device = "/dev/disk/by-id/wwn-0x55cd2e41564d34ed";
        type = "disk";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/mnt/sdb";
          # mountOptions = ["noatime"];
        };
      };

      # ssd-intel-b = {
      #   device = "/dev/disk/by-id/wwn-0x55cd2e415638bd82";
      #   type = "disk";
      #   content = {
      #     type = "filesystem";
      #     format = "ext4";
      #     mountpoint = "/mnt/sdc";
      #     # mountOptions = ["noatime"];
      #   };
      # };

      # Windows disk (declared but completely untouched - no content specification)
      #kingston-win = {
      #  device = "/dev/disk/by-id/wwn-0x50026b775804823b";
      #  type = "disk";
      #  # No content block = disk is ignored by disko
      #};
    };

    # Tmpfs for temporary files (10GB in RAM)
    nodev = {
      "/tmpfs" = {
        fsType = "tmpfs";
        mountOptions = [
          "defaults"
          "size=10G"
          "mode=1777" # World-writable with sticky bit
        ];
      };
    };
  };
}
