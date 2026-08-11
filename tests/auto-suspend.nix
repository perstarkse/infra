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

  # Keyboard description in evemu 2.7.0 text format (N:/I:/B: lines, see
  # evemu_read in evemu.c): bus 0003 (USB), vendor/product/version, then the
  # EV_SYN and EV_KEY masks. EV_KEY bits: 28 = KEY_ENTER, 30 = KEY_A — both
  # fall in byte 3 of the mask (0x10 | 0x40 = 0x50).
  inputDeviceDesc = pkgs.writeText "test-keyboard.desc" ''
    N: test keyboard
    I: 0003 1234 5678 0100
    B: 00 00 00 00 00 00 00 00 00
    B: 01 00 00 00 50 00 00 00 00
  '';

  # Headless node: exercise auto-suspend decision logic with short, manually
  # triggered checks. Without an input device the input watcher baselines
  # last-input at startup, so the machine counts as idle from boot — matching
  # production when nobody is at a seat.
  mkNode = {
    loadThreshold,
    checkInhibitors ? true,
    requiredIdleChecks ? 2,
    userIdleSeconds ? 1,
    withInput ? false,
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

      boot.kernelModules = lib.mkIf withInput ["uinput"];
      environment.systemPackages = lib.mkIf withInput [pkgs.evemu];

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

  inputIdleNode = mkNode {
    loadThreshold = "100.0";
    userIdleSeconds = 4; # generous vs the watcher's 1s poll
    withInput = true;
  };

  inputActiveNode = mkNode {
    loadThreshold = "100.0";
    userIdleSeconds = 4;
    withInput = true;
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

  # Creates a uinput keyboard on the machine and leaves `input_node` holding
  # its /dev/input/eventN path. These tests drive the exact same evdev path
  # the production machine uses, so they exercise the real input signal.
  mkInputSetup = ''
    machine.succeed("rm -f /var/log/auto-suspend.log /run/auto-suspend/idle-count /tmp/auto-suspend-suspended")
    machine.succeed("cp ${inputDeviceDesc} /tmp/kbd.desc")
    machine.succeed("systemd-run --unit=evemu-device --collect ${pkgs.evemu}/bin/evemu-device /tmp/kbd.desc")
    # evemu-device prints "test keyboard: /dev/input/eventN" once the device is up.
    machine.wait_until_succeeds(
        "journalctl -u evemu-device | grep -q '/dev/input/event'",
        timeout=30,
    )
    input_node = machine.succeed(
        "journalctl -u evemu-device | grep -o 'event[0-9]*' | head -1"
    ).strip()
    machine.succeed(f"test -n \"{input_node}\"")
    # The watcher rescans /dev/input every second; give it a beat to attach to
    # the new device so injected events are seen (evdev does not replay to
    # readers that attach later).
    machine.succeed("sleep 3")
  '';

  # Python helpers inserted at the top of an input testScript, after
  # mkInputSetup. press_key injects a keystroke; wait_input_updated waits until
  # the input watcher has recorded it.
  inputHelpers = ''
    def press_key():
        machine.succeed(f"${pkgs.evemu}/bin/evemu-event /dev/input/{input_node} --type EV_KEY --code KEY_A --value 1 --sync")
        machine.succeed(f"${pkgs.evemu}/bin/evemu-event /dev/input/{input_node} --type EV_KEY --code KEY_A --value 0 --sync")

    def wait_input_updated():
        prev = machine.succeed("cat /run/auto-suspend/last-input").strip()
        press_key()
        machine.wait_until_succeeds(f"test \"$(cat /run/auto-suspend/last-input)\" != \"{prev}\"", timeout=15)
  '';
in {
  auto-suspend-idle-suspends = pkgs.testers.runNixOSTest {
    name = "auto-suspend-idle-suspends";
    nodes.machine = idleNode;

    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("auto-suspend-input-watch.service")

      machine.succeed("rm -f /var/log/auto-suspend.log /run/auto-suspend/idle-count /tmp/auto-suspend-suspended")
      # No input ever: let the watcher's boot baseline age past the 1s threshold.
      machine.succeed("sleep 2")
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
      machine.succeed("grep -E 'user:idle\\(idleFor=' /var/log/auto-suspend.log")
    '';
  };

  auto-suspend-load-keeps-active = pkgs.testers.runNixOSTest {
    name = "auto-suspend-load-keeps-active";
    nodes.machine = loadBusyNode;

    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("auto-suspend-input-watch.service")

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
      machine.wait_for_unit("auto-suspend-input-watch.service")

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

  # Regression test for the stale-idle-hint bug: sustained input activity must
  # never be misread as idle, no matter how long the seat stays continuously
  # active.
  auto-suspend-input-keeps-active = pkgs.testers.runNixOSTest {
    name = "auto-suspend-input-keeps-active";
    nodes.machine = inputActiveNode;

    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("auto-suspend-input-watch.service")
      ${mkInputSetup}
      ${inputHelpers}

      # Continuous input across three checks must keep the machine awake.
      for i in range(3):
          wait_input_updated()
          machine.succeed("systemctl start auto-suspend.service")
          machine.succeed("grep -E 'user:ACTIVE' /var/log/auto-suspend.log")

      machine.succeed("test ! -f /tmp/auto-suspend-suspended")
      machine.succeed("! grep -q 'SUSPENDING' /var/log/auto-suspend.log")
      machine.succeed("! grep -q 'IDLE ' /var/log/auto-suspend.log")
    '';
  };

  # The correct input signal end to end: one burst of input, then silence —
  # the machine must go idle and suspend via the evdev signal alone, with no
  # swayidle idlehint involved.
  auto-suspend-input-idle-suspends = pkgs.testers.runNixOSTest {
    name = "auto-suspend-input-idle-suspends";
    nodes.machine = inputIdleNode;

    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("auto-suspend-input-watch.service")
      ${mkInputSetup}
      ${inputHelpers}

      # Recent input keeps the machine active.
      wait_input_updated()
      machine.succeed("systemctl start auto-suspend.service")
      machine.succeed("grep -E 'user:ACTIVE' /var/log/auto-suspend.log")

      # Silence past userIdleSeconds=4 must count as idle.
      machine.succeed("sleep 6")
      machine.succeed("systemctl start auto-suspend.service")
      machine.succeed("grep -E 'IDLE 1/2' /var/log/auto-suspend.log")
      machine.succeed("grep -E 'user:idle\\(idleFor=' /var/log/auto-suspend.log")
      machine.succeed("test ! -f /tmp/auto-suspend-suspended")

      machine.succeed("systemctl start auto-suspend.service")
      machine.succeed("grep -E 'SUSPENDING after 2 consecutive idle checks' /var/log/auto-suspend.log")
      machine.wait_until_succeeds("test -f /tmp/auto-suspend-suspended", timeout=30)
      machine.wait_until_succeeds("test ! -e /run/auto-suspend/idle-count", timeout=30)
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
