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
  # Replicates the hand-installed layout: two mirrored NVMe (RAID1 boot/root/swap)
  # as the system disk. The two data disks are NOT disko-managed (never
  # formatted); they're declared as mount-only nodev entries by UUID, so a
  # reinstall preserves the data, and /storage unions them via mergerfs.
  # Note: the live install used mdadm metadata 0.90 for the ESP trick (superblock
  # at the end so the firmware reads the FAT directly). disko only supports 1.x;
  # metadata 1.0 has the same end-anchored geometry, so the RAID1 ESP stays
  # firmware-bootable.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  disko.devices = {
    disk = {
      nvme0 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-CT1000P3SSD8_23364323217F";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1023M";
              type = "EF00";
              content = {
                type = "mdraid";
                name = "md0";
              };
            };
            root = {
              size = "823G";
              type = "FD00";
              content = {
                type = "mdraid";
                name = "md1";
              };
            };
            swap = {
              size = "100%";
              type = "FD00";
              content = {
                type = "mdraid";
                name = "md2";
              };
            };
          };
        };
      };
      nvme1 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-CT1000P3SSD8_2336432309B3";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1023M";
              type = "EF00";
              content = {
                type = "mdraid";
                name = "md0";
              };
            };
            root = {
              size = "823G";
              type = "FD00";
              content = {
                type = "mdraid";
                name = "md1";
              };
            };
            swap = {
              size = "100%";
              type = "FD00";
              content = {
                type = "mdraid";
                name = "md2";
              };
            };
          };
        };
      };
    };
    mdadm = {
      md0 = {
        type = "mdadm";
        level = 1;
        # 1.0 puts the superblock at the end of the member, so the outer EF00
        # partition stays readable as a plain FAT ESP by the UEFI firmware.
        metadata = "1.0";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
          };
        };
      };
      md1 = {
        type = "mdadm";
        level = 1;
        metadata = "1.2";
        content = {
          type = "filesystem";
          format = "xfs";
          mountpoint = "/";
          mountOptions = ["x-initrd.mount"];
        };
      };
      md2 = {
        type = "mdadm";
        level = 1;
        metadata = "1.2";
        content = {type = "swap";};
      };
    };
    nodev = {
      # Data disks: mount-only, never formatted. A reinstall keeps these intact.
      "/mnt/4tb" = {
        type = "nodev";
        fsType = "xfs";
        device = "/dev/disk/by-uuid/7c672abf-30ec-46be-aa0f-7931d6ba1931";
      };
      "/mnt/18tb" = {
        type = "nodev";
        fsType = "xfs";
        device = "/dev/disk/by-uuid/937c61e1-9f1c-4d56-8984-5888236ab762";
      };
      # mergerfs union over the two data disks. disko's nodev type emits the
      # fileSystems entry without any mkfs (mergerfs has none).
      "/storage" = {
        type = "nodev";
        fsType = "fuse.mergerfs";
        device = "/mnt/*";
        mountOptions = [
          "cache.files=partial"
          "dropcacheonclose=true"
          "category.create=epmfs"
          "use_ino"
          "allow_other"
          "cache.readdir=true"
          "minfreespace=10G"
        ];
      };
    };
  };
}
