{
  lib,
  pkgs,
  nixosModules,
  ...
}: let
  testHelpers = import ./lib/test-helpers.nix {inherit lib;};

  fakeSuspend = pkgs.writeShellScript "fake-suspend" ''
    set -euo pipefail
    ${pkgs.coreutils}/bin/touch /tmp/auto-suspend-suspended
  '';

  # Headless node: exercise auto-suspend decision logic with short, manually
  # triggered checks. No Wayland/swayidle — missing graphical sessions count as
  # user-idle, which matches production when nobody is logged into a seat.
  mkNode = {
    loadThreshold,
    checkInhibitors ? true,
    requiredIdleChecks ? 2,
    userIdleSeconds ? 1,
  }:
    lib.recursiveUpdate (testHelpers.mkCommonNode {}) {
      imports = [
        nixosModules.auto-suspend
        nixosModules.ddcutil
      ];

      # ddcutil options must exist for auto-suspend's useSystemSuspend default.
      my.ddcutil.enable = false;

      my.auto-suspend = {
        enable = true;
        checkIntervalMinutes = 60; # timer disabled below; value unused at runtime
        inherit requiredIdleChecks loadThreshold userIdleSeconds checkInhibitors;
        useSystemSuspend = false;
        activeTcpPorts = [];
      };

      # Deterministic tests: only run checks when the test script starts the unit.
      systemd.timers.auto-suspend.wantedBy = lib.mkForce [];

      # systemctl suspend must not actually sleep the VM.
      systemd.services.systemd-suspend.serviceConfig = {
        ExecStart = lib.mkForce [
          ""
          "${fakeSuspend}"
        ];
        # Allow the fake suspend marker outside the default sleep sandbox.
        ProtectSystem = lib.mkForce false;
        ProtectHome = lib.mkForce false;
        PrivateTmp = lib.mkForce false;
      };
    };

  idleNode = mkNode {
    loadThreshold = "100.0"; # always load-idle in a quiet VM
  };

  loadBusyNode = mkNode {
    loadThreshold = "0.0"; # never load-idle
  };

  inhibitorNode = mkNode {
    loadThreshold = "100.0";
  };

  resumeHookNode = lib.recursiveUpdate (testHelpers.mkCommonNode {}) {
    imports = [
      nixosModules.options
      nixosModules.auto-suspend
      nixosModules.ddcutil
      nixosModules.bluetooth-resume
    ];

    my.mainUser.name = "testuser";
    users.users.testuser = {
      isNormalUser = true;
    };

    my.bluetooth-resume.enable = true;

    my.ddcutil = {
      enable = true;
      monitor = {
        enable = true;
        dataDir = ../machines/charon/monitor;
      };
    };
  };
in {
  auto-suspend-idle-suspends = pkgs.testers.runNixOSTest {
    name = "auto-suspend-idle-suspends";
    nodes.machine = idleNode;

    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")

      machine.succeed("rm -f /var/log/auto-suspend.log /run/auto-suspend/idle-count /tmp/auto-suspend-suspended")
      machine.succeed("systemctl start auto-suspend.service")
      machine.succeed("grep -E 'IDLE 1/2' /var/log/auto-suspend.log")
      machine.succeed("test ! -f /tmp/auto-suspend-suspended")
      machine.succeed("test \"$(cat /run/auto-suspend/idle-count)\" = 1")

      machine.succeed("systemctl start auto-suspend.service")
      machine.succeed("grep -E 'SUSPENDING after 2 consecutive idle checks' /var/log/auto-suspend.log")
      # systemctl suspend returns before systemd-suspend.service finishes.
      machine.wait_until_succeeds("test -f /tmp/auto-suspend-suspended", timeout=30)
      # auto-suspend-reset removes the counter on suspend.target / wake.
      machine.wait_until_succeeds("test ! -e /run/auto-suspend/idle-count", timeout=30)
      machine.succeed("grep -E 'user:idle\\(no-eligible-session' /var/log/auto-suspend.log")
    '';
  };

  auto-suspend-load-keeps-active = pkgs.testers.runNixOSTest {
    name = "auto-suspend-load-keeps-active";
    nodes.machine = loadBusyNode;

    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")

      machine.succeed("rm -f /var/log/auto-suspend.log /tmp/auto-suspend-suspended")
      machine.succeed("mkdir -p /run/auto-suspend")
      machine.succeed("echo 1 > /run/auto-suspend/idle-count")
      machine.succeed("systemctl start auto-suspend.service")
      machine.succeed("grep -E 'ACTIVE \\(reset from 1/2\\)' /var/log/auto-suspend.log")
      machine.succeed("grep -E 'load:ACTIVE' /var/log/auto-suspend.log")
      machine.succeed("test ! -f /tmp/auto-suspend-suspended")
      machine.succeed("test \"$(cat /run/auto-suspend/idle-count)\" = 0")
    '';
  };

  auto-suspend-inhibitor-blocks = pkgs.testers.runNixOSTest {
    name = "auto-suspend-inhibitor-blocks";
    nodes.machine = inhibitorNode;

    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")

      machine.succeed("rm -f /var/log/auto-suspend.log /tmp/auto-suspend-suspended")
      machine.succeed("mkdir -p /run/auto-suspend")
      machine.succeed(
          "systemd-run --unit=test-sleep-inhibit.service "
          + "${pkgs.systemd}/bin/systemd-inhibit --what=sleep --mode=block --who=test --why=vm-test "
          + "${pkgs.coreutils}/bin/sleep infinity"
      )
      machine.wait_until_succeeds(
          "systemd-inhibit --list --no-legend | grep -E 'sleep.*block' | grep -qv handle-power-key",
          timeout=30,
      )

      machine.succeed("echo 1 > /run/auto-suspend/idle-count")
      machine.succeed("systemctl start auto-suspend.service")
      machine.succeed("grep -E 'ACTIVE \\(reset from 1/2\\)' /var/log/auto-suspend.log")
      machine.succeed("grep -E 'inhibitor:BLOCKING' /var/log/auto-suspend.log")
      machine.succeed("test ! -f /tmp/auto-suspend-suspended")
      machine.succeed("test \"$(cat /run/auto-suspend/idle-count)\" = 0")

      machine.succeed("systemctl stop test-sleep-inhibit.service")
    '';
  };

  auto-suspend-resume-hooks = pkgs.testers.runNixOSTest {
    name = "auto-suspend-resume-hooks";
    nodes.machine = resumeHookNode;

    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")

      # Test bluetooth resume post-sleep hook triggers bluetooth-resume-recover non-blockingly
      machine.succeed("/etc/systemd/system-sleep/bluetooth-resume post")
      machine.wait_until_succeeds("journalctl -u bluetooth-resume-recover.service | grep -i 'Bluetooth'", timeout=30)

      # Test monitor-power pre hook records wakeup devices
      machine.succeed("/etc/systemd/system-sleep/monitor-power pre")
      machine.succeed("test -f /run/monitor-power-suspend-wakeup")

      # Test monitor-power post hook triggers monitor-power-resume service non-blockingly
      machine.succeed("/etc/systemd/system-sleep/monitor-power post")
      machine.wait_until_succeeds("journalctl -u monitor-power-resume.service | grep -i 'monitor'", timeout=30)
    '';
  };
}
