{
  config.flake.nixosModules.vfio = {
    lib,
    config,
    ...
  }: {
    options.my.vfio = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable VFIO GPU passthrough configuration.";
      };
      gpuIds = lib.mkOption {
        type = lib.types.str;
        description = "Comma-separated list of vendor:device IDs for the GPU components.";
        example = "10de:1b81,10de:10f0";
      };
      hugepages = lib.mkOption {
        type = lib.types.int;
        default = 20;
        description = "Number of 1G hugepages to reserve for the VM.";
      };
      kvmfrStaticSizeMb = lib.mkOption {
        type = lib.types.int;
        default = 128;
        description = "Static shared memory size in MB for KVMFR (Looking Glass).";
      };
    };

    config = lib.mkIf config.my.vfio.enable {
      boot = {
        initrd.kernelModules = lib.mkBefore ["vfio-pci" "vfio_pci"];
        kernelModules = ["kvm-amd" "kvmfr"];
        kernelParams = [
          "amd_iommu=on"
          "iommu=1"
          "kvm.ignore_msrs=1"
          "kvm.report_ignored_msrs=0"
          "kvm_amd.npt=1"
          "kvm_amd.avic=1"
          "vfio-pci.ids=${config.my.vfio.gpuIds}"
          "default_hugepagesz=1G"
          "hugepages=${builtins.toString config.my.vfio.hugepages}"
        ];
        extraModulePackages = [config.boot.kernelPackages.kvmfr];
        extraModprobeConfig = ''
          options kvmfr static_size_mb=${builtins.toString config.my.vfio.kvmfrStaticSizeMb}
          softdep nvidia pre: vfio-pci
          softdep nvidia_drm pre: vfio-pci
          softdep nvidia_modeset pre: vfio-pci
          softdep i2c_nvidia_gpu pre: vfio-pci
        '';
      };

      services.udev.extraRules = lib.mkAfter ''
        SUBSYSTEM=="kvmfr", OWNER="root", GROUP="kvm", MODE="0777"
      '';

      programs.virt-manager.enable = true;

      virtualisation.libvirtd = {
        qemu = {
          verbatimConfig = ''
            cgroup_controllers = [ "cpu", "memory", "blkio", "cpuset", "cpuacct" ]
          '';
        };
      };
    };
  };
}
