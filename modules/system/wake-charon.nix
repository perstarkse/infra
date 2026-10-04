# wake-charon on makemake: send charon's magic packet before driving it.
#
# Why makemake sends it (not io): io owns the broadcast domain via wakeproxy,
# but routing through io costs an SSH hop for no benefit — makemake shares the
# host network namespace, so it has the same 10.0.0.255 reachability directly.
# Pure stdlib python3: no wakeonlan/etherwake on makemake, and a WOL packet is
# 6 sync bytes + 16 MAC repeats. Constants interpolate from services.wakeproxy
# on io's config shape (same upstream module options); no duplicated MAC.
#
# Readiness is TCP connect to charon:22, NOT the wakeproxy HTTP frontend —
# POST /_wake/start is CSRF-guarded, rate-limited, and behind an argon2 login
# meant for humans; the agent must not forge browser-shaped headers past that.
_: {
  config.flake.nixosModules.wake-charon = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.wake-charon;
    # Same file io's services.wakeproxy reads (flake/lib/wake-target.nix), so
    # the MAC/IP/timeouts live in exactly one place.
    wakeTarget = import ../../flake/lib/wake-target.nix;
    script =
      pkgs.writers.writePython3Bin "wake-charon" {
        flakeIgnore = ["E501" "W291" "W293"];
      } ''
        import socket
        import sys
        import time

        MAC = "${cfg.mac}"
        BROADCAST_IP = "${cfg.broadcastIp}"
        BROADCAST_PORT = ${toString cfg.broadcastPort}
        SSH_HOST = "${cfg.sshHost}"
        SSH_PORT = ${toString cfg.sshPort}
        TIMEOUT = ${toString cfg.timeoutSeconds}
        POLL_INTERVAL = ${toString cfg.pollIntervalSeconds}


        def parse_mac(mac):
            parts = mac.split(":")
            if len(parts) != 6:
                raise ValueError(f"bad MAC: {mac!r}")
            return bytes(int(p, 16) for p in parts)


        def packet(mac):
            return b"\xff" * 6 + parse_mac(mac) * 16


        def sshd_up():
            try:
                with socket.create_connection((SSH_HOST, SSH_PORT), timeout=5):
                    return True
            except OSError:
                return False


        def probe():
            up = sshd_up()
            print(f"{SSH_HOST}:{SSH_PORT} {'reachable' if up else 'unreachable'}")
            return 0 if up else 1


        def wake(dry_run=False):
            pkt = packet(MAC)
            if dry_run:
                print(pkt.hex())
                return 0
            if sshd_up():
                print(f"{SSH_HOST}:{SSH_PORT} already up, no packet sent")
                return 0
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
                s.sendto(pkt, (BROADCAST_IP, BROADCAST_PORT))
            print(f"magic packet sent to {MAC} via {BROADCAST_IP}:{BROADCAST_PORT}")
            deadline = time.monotonic() + TIMEOUT
            while time.monotonic() < deadline:
                time.sleep(POLL_INTERVAL)
                if sshd_up():
                    print(f"{SSH_HOST}:{SSH_PORT} up")
                    return 0
            print(f"timed out after {TIMEOUT}s waiting for {SSH_HOST}:{SSH_PORT}", file=sys.stderr)
            return 1


        if __name__ == "__main__":
            args = sys.argv[1:]
            dry = "--dry-run" in args
            args = [a for a in args if a != "--dry-run"]
            cmd = args[0] if args else "wake"
            if cmd == "probe":
                sys.exit(probe())
            elif cmd == "wake":
                sys.exit(wake(dry))
            else:
                print(f"usage: {sys.argv[0]} [probe|wake] [--dry-run]", file=sys.stderr)
                sys.exit(2)
      '';
  in {
    options.my.wake-charon = {
      enable = lib.mkEnableOption "wake-charon magic-packet script for charon";

      package = lib.mkOption {
        type = lib.types.package;
        default = script;
        defaultText = lib.literalExpression "the wake-charon script below";
        description = "The script. Exposed so other modules can hand it to a container (see modules/system/hermes.nix); override only to swap the implementation.";
      };

      mac = lib.mkOption {
        type = lib.types.str;
        default = wakeTarget.mac;
        defaultText = "flake.lib.wakeTarget.mac (also io services.wakeproxy.wolMac)";
        description = "charon's WOL MAC (charon enp4s0). Single source in flake/lib/wake-target.nix; override only to retarget the script.";
      };
      broadcastIp = lib.mkOption {
        type = lib.types.str;
        default = wakeTarget.broadcastIp;
        defaultText = "flake.lib.wakeTarget.broadcastIp";
        description = "WOL broadcast address.";
      };
      broadcastPort = lib.mkOption {
        type = lib.types.port;
        default = wakeTarget.broadcastPort;
        defaultText = "flake.lib.wakeTarget.broadcastPort";
        description = "WOL broadcast port.";
      };
      sshHost = lib.mkOption {
        type = lib.types.str;
        default = wakeTarget.host;
        defaultText = "flake.lib.wakeTarget.host";
        description = "charon LAN IP; readiness is TCP connect here, never the wakeproxy HTTP frontend.";
      };
      sshPort = lib.mkOption {
        type = lib.types.port;
        default = wakeTarget.sshPort;
        defaultText = "flake.lib.wakeTarget.sshPort";
        description = "charon sshd port.";
      };
      timeoutSeconds = lib.mkOption {
        type = lib.types.int;
        default = wakeTarget.wakeTimeout;
        defaultText = "flake.lib.wakeTarget.wakeTimeout";
        description = "How long wake polls for sshd before giving up.";
      };
      pollIntervalSeconds = lib.mkOption {
        type = lib.types.int;
        default = wakeTarget.pollInterval;
        defaultText = "flake.lib.wakeTarget.pollInterval";
        description = "Poll interval while waiting for sshd.";
      };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [script];
    };
  };
}
