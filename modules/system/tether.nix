_: {
  config.flake.nixosModules.tether = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.tether;
  in {
    options.my.tether = {
      enable = lib.mkEnableOption "Tether iPhone-bridge (system-level bits: firewall, bluetooth class fix)";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../pkgs/tether {};
        defaultText = lib.literalExpression "pkgs.callPackage ../../pkgs/tether {}";
        description = "The tether package providing tetherd/tether/tether-gtk/tether-dialog.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open TCP 5134 for the tetherd mTLS endpoint the iPhone connects to.";
      };

      bluetoothAdapter = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "hci0";
        description = ''
          Adapter for the Bluetooth Class-of-Device fix (Messages/Notifications).
          bluetoothd resets the CoD on every start and MAP/PBAP then fail with an
          OBEX error, so an instance of tether-btclass re-applies A/V Hands-Free
          after bluetooth.service. null disables the unit.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [5134];

      # Ported from upstream packaging/systemd/tether-btclass@.service: upstream
      # ships a template unit expecting /bin/sh and a manual instance enable;
      # inline the instance instead so it is enabled declaratively. Guard with
      # optionalAttrs so bluetoothAdapter = null (option documents this as
      # disabling the unit) doesn't crash string interpolation of the unit name.
      systemd.services = lib.optionalAttrs (cfg.bluetoothAdapter != null) {
        "tether-btclass@${cfg.bluetoothAdapter}" = {
          description = "Set Bluetooth Class of Device to A/V Hands-Free on ${cfg.bluetoothAdapter} for Tether";
          after = ["bluetooth.service"];
          partOf = ["bluetooth.service"];
          wantedBy = ["bluetooth.service"];
          path = [pkgs.bluez pkgs.coreutils pkgs.gnugrep];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            for i in $(seq 1 10); do
              btmgmt --index ${cfg.bluetoothAdapter} class 4 8 >/dev/null 2>&1
              btmgmt --index ${cfg.bluetoothAdapter} info 2>/dev/null | grep -q "class 0x..0408" && exit 0
              sleep 1
            done
            exit 1
          '';
        };
      };

      # bluetoothd resets the Class of Device on every start, and charon's
      # bluetooth-resume re-powers the adapter after sleep which can also reset
      # it. Re-apply the CoD fix after resume too (best-effort, non-blocking).
      environment.etc."systemd/system-sleep/tether-btclass" = lib.mkIf (cfg.bluetoothAdapter != null) {
        source = pkgs.writeShellScript "tether-btclass-sleep-hook" ''
          case "$1" in
            post)
              ${pkgs.systemd}/bin/systemctl start --no-block "tether-btclass@${cfg.bluetoothAdapter}.service" || true
              ;;
          esac
        '';
        mode = "0755";
      };
    };
  };
}
