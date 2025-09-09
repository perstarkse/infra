{
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];
  boot = {
    initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"];
    initrd.kernelModules = ["vfio-pci"];
    kernelModules = ["kvm-intel" "vfio-pci" "iommu"];
    kernelParams = ["intel_iommu=on" "iommu=pt"];

    # boot.postBootCommands = ''
    #   DEVS="0000:02:00.0 0000:03:00.0 0000:04:00.0"

    #   for DEV in $DEVS; do
    #     echo "vfio-pci" > /sys/bus/pci/devices/$DEV/driver_override
    #   done
    #   modprobe -i vfio-pci
    # '';

    extraModulePackages = [];
    swraid = {
      enable = true;
      mdadmConf = ''
        MAILADDR supervisor@starks.cloud
        ARRAY /dev/md0 metadata=0.90 UUID=55a6beaa:91e07a8c:1dccfe9b:c572fcb0
        ARRAY /dev/md1 metadata=0.90 UUID=b1558a3b:d342715b:1dccfe9b:c572fcb0
        ARRAY /dev/md2 metadata=0.90 UUID=086ec43b:91011b45:1dccfe9b:c572fcb0
      '';
    };
  };
  fileSystems = {
    "/boot" = {
      device = "/dev/md0p1";
      fsType = "vfat";
      options = ["defaults" "umask=0077" "dmask=0077" "fmask=0077" "x-gvfs-show"];
    };

    "/" = {
      device = "/dev/md1";
      fsType = "xfs";
    };

    "/mnt/18tb" = {
      device = "/dev/disk/by-uuid/937c61e1-9f1c-4d56-8984-5888236ab762";
      fsType = "xfs";
      # options = ["noatime"];
    };

    "/mnt/4tb" = {
      device = "/dev/disk/by-uuid/7c672abf-30ec-46be-aa0f-7931d6ba1931";
      fsType = "xfs";
      # options = ["noatime"];
    };

    "/storage" = {
      fsType = "fuse.mergerfs";
      device = "/mnt/*";
      options = [
        "cache.files=partial"
        "dropcacheonclose=true"
        "category.create=mfs"
        "use_ino"
        "allow_other"
        "cache.readdir=true"
        "minfreespace=10G"
      ];
    };

    "/data/media" = {
      device = "/storage/media/library";
      fsType = "none";
      options = ["bind"];
      depends = ["/storage"];
    };

    "/data/torrents" = {
      device = "/storage/torrents";
      fsType = "none";
      options = ["bind"];
      depends = ["/storage"];
    };
  };

  swapDevices = [
    {device = "/dev/md2";}
  ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
