# ---
# schema = "single-disk"
# [placeholders]
# mainDisk = "/dev/disk/by-id/scsi-360c1e24507594214af7fd4cc88df713a"
# ---
# This file was automatically generated!
# CHANGING this configuration requires wiping and reinstalling the machine
{
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.enable = true;
  disko.devices = {
    disk = {
      main = {
        name = "main-914585a8786c439eb5abc6bcf1503d15";
        device = "/dev/disk/by-id/scsi-360c1e24507594214af7fd4cc88df713a";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            "boot" = {
              size = "1M";
              type = "EF02"; # for grub MBR
              priority = 1;
            };
            ESP = {
              type = "EF00";
              size = "500M";
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
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
