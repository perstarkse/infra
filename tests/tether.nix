{
  lib,
  pkgs,
  nixosModules,
  ...
}: let
  testHelpers = import ./lib/test-helpers.nix {inherit lib;};

  # Tether needs hardware.bluetooth.enable so the real bluetooth.service exists
  # and the ExecStart override lands on something real; the module itself never
  # sets hardware.bluetooth (charon does).
  mkNode = {experimental}: let
    base = testHelpers.mkCommonNode {};
  in
    lib.recursiveUpdate base {
      imports = [
        nixosModules.options
        nixosModules.tether
      ];

      my.mainUser.name = "testuser";
      users.users.testuser = {
        isNormalUser = true;
      };

      hardware.bluetooth.enable = true;
      my.tether = {
        enable = true;
        openFirewall = false; # keep the VM firewall surface tiny
        experimentalBluetoothd = experimental;
      };
    };

  experimentalNode = mkNode {experimental = true;};
  plainNode = mkNode {experimental = false;};
in {
  # The experimental flag must put --experimental on bluetoothd's ExecStart
  # (org.bluez.Bearer.LE1, which ANCS needs), and the class-of-device unit plus
  # its sleep re-applier must exist and be enabled on bluetooth.service.
  tether-system = pkgs.testers.runNixOSTest {
    name = "tether-system";
    nodes.machine = experimentalNode;

    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")

      # --experimental on bluetoothd's ExecStart (the whole point: NixOS has no
      # flag option for it, so the module overrides ExecStart).
      exec_start = machine.succeed(
          "systemctl show bluetooth.service -p ExecStart --value"
      )
      assert "--experimental" in exec_start, f"missing --experimental: {exec_start}"

      # Class-of-Device fix unit exists, is enabled under bluetooth.service, and
      # its ExecStart script applies the A/V Hands-Free class (no hci0 exists in
      # the VM, so the unit cannot complete at runtime here — we assert wiring).
      machine.succeed("systemctl is-enabled tether-btclass@hci0.service")
      machine.succeed("test -f /etc/systemd/system/bluetooth.service.wants/tether-btclass@hci0.service")
      unit_script = machine.succeed(
          "systemctl cat tether-btclass@hci0.service --no-pager"
      )
      script_path = [
          line.split("=", 1)[1].strip()
          for line in unit_script.splitlines()
          if line.startswith("ExecStart=")
      ][0]
      machine.succeed(f"grep -q 'btmgmt --index hci0 class 4 8' {script_path}")

      # Sleep re-applier hook exists and triggers the unit non-blockingly.
      machine.succeed("test -x /etc/systemd/system-sleep/tether-btclass")
      machine.succeed("/etc/systemd/system-sleep/tether-btclass post")
    '';
  };

  # Without the flag, bluetoothd must run WITHOUT --experimental (default-off:
  # changing how bluetoothd runs for the whole machine is opt-in).
  tether-plain = pkgs.testers.runNixOSTest {
    name = "tether-plain";
    nodes.machine = plainNode;

    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")

      exec_start = machine.succeed(
          "systemctl show bluetooth.service -p ExecStart --value"
      )
      assert "--experimental" not in exec_start, f"unexpected --experimental: {exec_start}"
    '';
  };
}
