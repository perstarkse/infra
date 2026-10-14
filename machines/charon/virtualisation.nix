{pkgs, ...}: {
  my.libvirt = {
    enable = true;
    spiceUSBRedirection = true;

    shutdownOnSuspend = {
      enable = true;
      vms = ["win11"];
    };

    # Dir-backed pool so NixVirt creates win11-new.qcow2 on activation if missing.
    pools = [
      {
        name = "vm-disks";
        uuid = "b1a7e4d2-9f33-4c71-8e2a-6d5b0c9f1a47";
        path = "/mnt/sdb/disks";
        volumes = [
          {
            name = "win11-new.qcow2";
            capacity = {
              count = 80;
              unit = "GiB";
            };
            format = "qcow2";
          }
        ];
      }
    ];

    domains = [
      {
        name = "win11";
        uuid = "8c4d2bf3-3e6e-4c9b-a012-4b7c1e6f8d02";
        template = "windows";
        memory = {
          count = 8;
          unit = "GiB";
        };
        storageVol = "/mnt/sdb/disks/win11-new.qcow2";
        installVol = "/mnt/sdb/iso/win11.iso";
        networkName = "vm-nat";
        macAddress = "52:54:00:8e:11:02";
        nvramPath = "/var/lib/libvirt/qemu/nvram/win11-new_VARS.fd";
        virtioNet = true;
        virtioDrive = true;
        virtioVideo = true;
        installVirtio = true;
      }
    ];

    networks = [
      {
        name = "vm-nat";
        uuid = "80c19792-39ed-5c58-01b2-56ccfbac0b6b";
        mode = "nat";
        subnet = "192.168.101.0/24";
        gateway = "192.168.101.1";
        dhcpStart = "192.168.101.10";
        dhcpEnd = "192.168.101.254";
        firewallPorts = {
          tcp = [22 80 443];
          udp = [53];
        };
      }
      {
        name = "vm-isolated";
        uuid = "90d2a8a3-4afe-6d69-12c3-67dd0cbd1c7c";
        mode = "isolated";
        subnet = "192.168.123.0/24";
        gateway = "192.168.123.1";
        dhcpStart = "192.168.123.10";
        dhcpEnd = "192.168.123.254";
        firewallPorts = {
          tcp = [];
          udp = [];
        };
      }
    ];
  };

  programs.virt-manager.enable = true;
  environment.systemPackages = [
    pkgs.virt-manager
  ];
}
