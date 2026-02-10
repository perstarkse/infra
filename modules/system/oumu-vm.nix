_: {
  config.flake.nixosModules.oumu-vm = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.my.oumu-vm;
    storageBase = cfg.storageBaseDir;
  in {
    options.my.oumu-vm = {
      enable = lib.mkEnableOption "Oumu AI assistant VM on io";

      storageBaseDir = lib.mkOption {
        type = lib.types.str;
        default = "/storage/libvirt/oumu";
        description = "Base directory for VM storage (disk images)";
      };

      memoryGb = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "RAM allocated to VM in GB";
      };

      diskSizeGb = lib.mkOption {
        type = lib.types.int;
        default = 120;
        description = "Root disk size in GB";
      };
    };

    config = lib.mkIf cfg.enable {
      # Ensure libvirtd is enabled
      assertions = [
        {
          assertion = config.my.libvirtd.enable or false;
          message = "oumu-vm requires my.libvirtd.enable = true";
        }
      ];

      # Create storage directory and share
      systemd.tmpfiles.rules = [
        "d ${storageBase} 0750 root root -"
        "d ${storageBase}/images 0750 root root -"
        "d ${storageBase}/share 0700 root root -"
      ];

      # Copy deploy key to share when it changes
      systemd.services.oumu-sync-key = {
        description = "Sync Oumu deploy key to VirtioFS share";
        path = [pkgs.coreutils];
        serviceConfig = {
          Type = "oneshot";
        };
        script = ''
          if [ -f /run/secrets/vars/oumu-deploy-key/private_key ]; then
            cp /run/secrets/vars/oumu-deploy-key/private_key ${storageBase}/share/deploy_key
            chmod 400 ${storageBase}/share/deploy_key
          fi
        '';
        wantedBy = ["multi-user.target"];
        after = ["secret-oumu-deploy-key.service"];
      };

      # Initialize VM disk if it doesn't exist
      # We do NOT create an empty disk automatically anymore, because
      # we expect a pre-built NixOS image to be copied here.
      # But we ensure the directory exists.

      # Add VM to libvirt domains - bridged to LAN for direct access
      my.libvirtd.domains = [
        {
          name = "oumu";
          uuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
          template = "linux";
          memory = {
            count = cfg.memoryGb;
            unit = "GiB";
          };
          storageVol = "${storageBase}/images/oumu-root.qcow2";
          bridgeName = "br-lan";
          macAddress = "52:54:00:01:99:00";
          virtioNet = true;
          virtioVideo = false;
          virtioDrive = true;
          active = true;
          restart = true;
          extraXML = ''
            <memoryBacking>
              <source type="memfd"/>
              <access mode="shared"/>
            </memoryBacking>
            <devices>
              <serial type='pty'>
                <target port='0'/>
              </serial>
              <console type='pty'>
                <target type='serial' port='0'/>
              </console>
              <filesystem type="mount" accessmode="passthrough">
                <driver type="virtiofs"/>
                <binary path="${pkgs.virtiofsd}/bin/virtiofsd"/>
                <source dir="${storageBase}/share"/>
                <target dir="host_share"/>
              </filesystem>
            </devices>
          '';
        }
      ];

      # Ensure virtiofsd is available
      environment.systemPackages = [pkgs.virtiofsd];

      # VM is bridged to br-lan, so it gets IP from main DHCP and has full LAN/WAN access
      # No custom network needed - libvirt handles bridging automatically
    };
  };
}
