{
  ctx,
  pkgs,
  lib,
  ...
}: let
  # Battlemage + xe is stable on this kernel branch; newer 6.12.x regressed GPU init.
  # Pinned via the locked `nixpkgs-612` input instead of builtins.getFlake so
  # evals work offline and the pin stays in flake.lock.
  pinnedKernelPkgs = import ctx.inputs.nixpkgs612 {
    localSystem = {inherit (pkgs.stdenv.hostPlatform) system;};
    config = {
      allowUnfree = true;
    };
  };
in {
  # Battlemage + xe is currently stable on 6.12.74 here; newer 6.12.x regressed GPU init.
  boot.kernelPackages = pinnedKernelPkgs.linuxPackages;

  boot.kernelParams = [
    "usbcore.autosuspend=-1"
  ];

  zramSwap = {
    enable = true;
    priority = 100;
  };

  swapDevices = [
    {
      device = "/mnt/sdb/swap/swapfile";
      size = 64 * 1024; # 64G overflow on enterprise SATA (INTEL SSDSC2KB038TZ) below zram
      priority = 10;
    }
  ];

  # sda (/mnt/sdb) enters standby on its own (~42x this boot, 3-4s per wake)
  # and on every suspend (STANDBY IMMEDIATE even times out after 5s). The
  # swapfile (2+GB used, priority 10 above zram) lives there, so the first
  # post-resume page faults stall with the display already shown — the
  # few-seconds resume freeze. Disable the internal standby timer (-S 0) and
  # APM spindown (-B 255); the resume hook re-applies it since the drive
  # resets to defaults on power cycle.
  # LIMIT: drive standby is disabled outright rather than retuned via ALPM, so
  # idle power draw is higher than it strictly needs to be. Revisit if draw
  # starts to matter and the resume stall can be fixed another way.
  systemd.services.sda-disable-standby = {
    description = "Disable sda internal standby (swap lives on /mnt/sdb)";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.hdparm}/sbin/hdparm -S 0 -B 255 /dev/disk/by-id/ata-INTEL_SSDSC2KB038TZ_PHYI329101K03P8EGN";
    };
  };
  powerManagement.resumeCommands = "${pkgs.hdparm}/sbin/hdparm -S 0 -B 255 /dev/disk/by-id/ata-INTEL_SSDSC2KB038TZ_PHYI329101K03P8EGN || true";

  boot.loader.systemd-boot.configurationLimit = 5;

  services.journald.extraConfig = ''
    SystemMaxUse=1G
    SystemMaxFileSize=100M
    MaxRetentionSec=14day
    RuntimeMaxUse=250M
  '';

  nix.settings.auto-optimise-store = true;

  # Native SATA offload (no bind mounts) — keep NVMe for /nix/store + rust-analyzer salsa DB
  # Docker high churn -> enterprise SATA endurance; huggingface/pip sequential -> SATA
  virtualisation.docker.daemon.settings."data-root" = "/mnt/sdb/cache/docker";

  environment.sessionVariables = {
    HF_HOME = "/mnt/sdb/cache/home-p/huggingface";
    PIP_CACHE_DIR = "/mnt/sdb/cache/home-p/pip";
  };

  systemd.tmpfiles.rules = [
    "d /mnt/sdb/cache 0755 root root -"
    "d /mnt/sdb/cache/docker 0711 root root -"
    "d /mnt/sdb/cache/home-p 0755 p users -"
    "d /mnt/sdb/cache/home-p/huggingface 0755 p users -"
    "d /mnt/sdb/cache/home-p/pip 0755 p users -"
    "d /mnt/sdb/swap 0755 root root -"
  ];

  nix.gc.options = lib.mkForce "--delete-older-than 7d";

  # Decode and persist machine-check exceptions (MCEs) so hardware errors like the
  # uncorrectable EX watchdog errors before the Aug 19 hard reset are not lost.
  # Records go to /var/lib/rasdaemon/ras-mc_event.db; query with ras-mc-ctl.
  hardware.rasdaemon.enable = true;

  systemd.network.links."40-enp4s0" = {
    matchConfig.OriginalName = "enp4s0";
    linkConfig.WakeOnLan = "magic";
  };

  networking = {
    firewall.allowPing = true;
    # Allow localsend receive port
    # Allow 3000/1 and 5000/1 for dev server and tooling
    firewall.allowedTCPPorts = [53317 3001 5000 5001];
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        KernelExperimental = true;
        FastConnectable = true;
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

  security = {
    wrappers.intel_gpu_top = {
      owner = "root";
      group = "root";
      capabilities = "cap_sys_admin+ep";
      source = "${pkgs.intel-gpu-tools}/bin/intel_gpu_top";
    };

    pam.loginLimits = [
      {
        domain = "*";
        item = "nofile";
        type = "-";
        value = "524288";
      }
    ];
  };

  hardware.cpu.amd.updateMicrocode = true;

  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  systemd.services.nix-daemon.serviceConfig = {
    Nice = lib.mkForce 15;
    IOSchedulingClass = lib.mkForce "idle";
    IOSchedulingPriority = lib.mkForce 7;
    LimitNOFILE = "infinity";
  };

  # Cap the in-journal coredump backtrace size: a crashing QtWebEngine renderer
  # produced a >4M COREDUMP_STACK_TRACE entry that exceeds
  # systemd-journal-upload's per-entry buffer, making the uploader fail forever
  # on the same unskippable entry (NRestarts climbing). 512M keeps core dumps
  # but bounds the journal field so uploads can progress.
  systemd.coredump.settings.Coredump.ProcessSizeMax = "512M";

  users.users.p = {
    extraGroups = ["dialout" "plugdev"];
  };
  users.groups.plugdev = {};

  services.udev.extraRules = lib.mkAfter ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="0d28", MODE="0664", GROUP="plugdev", TAG+="uaccess"
    KERNEL=="hidraw*", ATTRS{idVendor}=="0d28", MODE="0666", TAG+="uaccess"
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0d28", MODE="0666", TAG+="uaccess"
  '';
}
