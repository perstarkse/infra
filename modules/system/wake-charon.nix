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
#
# Keep-awake lease (Phase H gap, closed 2026-10-13): a direct WOL does not
# take wakeproxy's keep-awake lease — only wake.stark.pub traffic does — so a
# long agent run could hit charon's 1800s sleepInhibit ceiling and suspend
# mid-work. `wake-charon lease <seconds>` SSHes to charon's
# wakeproxy-keep-awake target (forced command, restrict'ed key) and takes a
# logind inhibit lease; `wake --lease <seconds>` combines both. The lease
# key is the fleet-wide wake-proxy-keep-awake-ssh generator; machines using
# this grant `agent` read via my.secrets.allowReadAccess.
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
        import subprocess
        import sys
        import time

        MAC = "${cfg.mac}"
        BROADCAST_IP = "${cfg.broadcastIp}"
        BROADCAST_PORT = ${toString cfg.broadcastPort}
        SSH_HOST = "${cfg.sshHost}"
        SSH_PORT = ${toString cfg.sshPort}
        TIMEOUT = ${toString cfg.timeoutSeconds}
        POLL_INTERVAL = ${toString cfg.pollIntervalSeconds}
        KEEP_AWAKE_ENABLED = ${
          if cfg.keepAwake.enable
          then "True"
          else "False"
        }
        KEEP_AWAKE_USER = "${cfg.keepAwake.sshUser}"
        KEEP_AWAKE_HOST = "${cfg.sshHost}"
        KEEP_AWAKE_PORT = ${toString cfg.sshPort}
        IDENTITY_FILE = "${toString cfg.keepAwake.identityFile}"
        MAX_LEASE_SECONDS = ${toString cfg.keepAwake.maxDurationSeconds}
        DEFAULT_LEASE_SECONDS = ${
          if cfg.keepAwake.enable && cfg.keepAwake.defaultDurationSeconds != null
          then toString cfg.keepAwake.defaultDurationSeconds
          else "None"
        }


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


        def parse_duration(val_str):
            s = str(val_str).strip()
            if s.endswith("s") or s.endswith("S"):
                s = s[:-1].strip()
                try:
                    val = float(s)
                    return int(round(val)) if val > 0 else None
                except ValueError:
                    return None
            if s.endswith("m") or s.endswith("M"):
                s = s[:-1].strip()
            try:
                val = float(s)
                return int(round(val * 60)) if val > 0 else None
            except ValueError:
                return None


        def lease(val):
            if not KEEP_AWAKE_ENABLED:
                print("keep-awake is not configured on this machine (my.wake-charon.keepAwake.enable)", file=sys.stderr)
                return 2
            seconds = val if isinstance(val, int) else parse_duration(str(val))
            if seconds is None or seconds <= 0:
                print("lease duration must be a positive number of minutes", file=sys.stderr)
                return 2
            if seconds > MAX_LEASE_SECONDS:
                # Client-side cap mirrors the target's own rejection
                # (WAKEPROXY_KEEP_AWAKE_TARGET_MAX_SECS on charon).
                max_mins = MAX_LEASE_SECONDS // 60
                mins = seconds // 60
                print(f"lease {mins}m ({seconds}s) exceeds max {max_mins}m ({MAX_LEASE_SECONDS}s)", file=sys.stderr)
                return 1
            # StrictHostKeyChecking=yes fails closed: makemake's agent has
            # charon pinned in ~/.ssh/known_hosts (hermes-install-known-hosts);
            # an account without the pin gets a hard error, not a TOFU prompt.
            cmd = [
                "ssh", "-i", IDENTITY_FILE,
                "-o", "BatchMode=yes",
                "-o", "IdentitiesOnly=yes",
                "-o", "StrictHostKeyChecking=yes",
                "-o", "ConnectTimeout=10",
                "-p", str(KEEP_AWAKE_PORT),
                f"{KEEP_AWAKE_USER}@{KEEP_AWAKE_HOST}",
                str(seconds),
            ]
            result = subprocess.run(cmd)
            if result.returncode == 0:
                mins = seconds / 60
                mins_display = int(mins) if mins.is_integer() else f"{mins:.1f}"
                print(f"keep-awake lease {mins_display}m ({seconds}s) accepted by {KEEP_AWAKE_USER}@{KEEP_AWAKE_HOST}")
            return result.returncode


        if __name__ == "__main__":
            args = sys.argv[1:]
            dry = "--dry-run" in args
            args = [a for a in args if a != "--dry-run"]
            no_lease = "--no-lease" in args
            args = [a for a in args if a != "--no-lease"]

            explicit_seconds = None
            for flag in ("--lease", "-l", "--minutes", "-m"):
                if flag in args:
                    i = args.index(flag)
                    if i + 1 >= len(args):
                        print(f"{flag} requires a duration in minutes", file=sys.stderr)
                        sys.exit(2)
                    explicit_seconds = parse_duration(args[i + 1])
                    if explicit_seconds is None:
                        print(f"invalid duration: {args[i + 1]!r} (must be a positive number of minutes)", file=sys.stderr)
                        sys.exit(2)
                    args = args[:i] + args[i + 2:]
                    break

            cmd = "wake"
            pos_seconds = None

            if len(args) == 0:
                cmd = "wake"
            elif len(args) == 1:
                if args[0] in ("wake", "lease", "probe"):
                    cmd = args[0]
                else:
                    duration = parse_duration(args[0])
                    if duration is not None:
                        cmd = "wake"
                        pos_seconds = duration
                    else:
                        print(f"unknown command or invalid duration: {args[0]!r}", file=sys.stderr)
                        print(f"usage: {sys.argv[0]} [probe|wake|lease] [<minutes>] [--dry-run] [--no-lease]", file=sys.stderr)
                        sys.exit(2)
            elif len(args) == 2:
                if args[0] in ("wake", "lease"):
                    cmd = args[0]
                    pos_seconds = parse_duration(args[1])
                    if pos_seconds is None:
                        print(f"invalid duration: {args[1]!r} (must be a positive number of minutes)", file=sys.stderr)
                        sys.exit(2)
                else:
                    print(f"unknown command: {args[0]!r}", file=sys.stderr)
                    print(f"usage: {sys.argv[0]} [probe|wake|lease] [<minutes>] [--dry-run] [--no-lease]", file=sys.stderr)
                    sys.exit(2)
            else:
                print("too many arguments", file=sys.stderr)
                print(f"usage: {sys.argv[0]} [probe|wake|lease] [<minutes>] [--dry-run] [--no-lease]", file=sys.stderr)
                sys.exit(2)

            if no_lease:
                lease_seconds = None
            elif explicit_seconds is not None:
                lease_seconds = explicit_seconds
            elif pos_seconds is not None:
                lease_seconds = pos_seconds
            else:
                lease_seconds = DEFAULT_LEASE_SECONDS

            if cmd == "probe":
                sys.exit(probe())
            elif cmd == "lease":
                if lease_seconds is None:
                    print("lease requires a duration in minutes", file=sys.stderr)
                    sys.exit(2)
                sys.exit(lease(lease_seconds))
            elif cmd == "wake":
                rc = wake(dry)
                # Refresh the lease only after a real wake: dry-run prints the
                # packet and must not touch charon's logind.
                if rc == 0 and lease_seconds is not None and not dry:
                    rc = lease(lease_seconds)
                sys.exit(rc)
            else:
                print(f"usage: {sys.argv[0]} [probe|wake|lease] [<minutes>] [--dry-run] [--no-lease]", file=sys.stderr)
                sys.exit(2)
      '';
  in {
    options.my.wake-charon = {
      enable = lib.mkEnableOption "wake-charon magic-packet script for charon";

      package = lib.mkOption {
        type = lib.types.package;
        default = script;
        defaultText = lib.literalExpression "the wake-charon script below";
        description = "The script. Exposed so other modules can put it on an agent's PATH (services.hermes-agent.extraPackages); override only to swap the implementation.";
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

      keepAwake = {
        enable = lib.mkEnableOption "wakeproxy keep-awake lease support (wake-charon lease <seconds>)";

        sshUser = lib.mkOption {
          type = lib.types.str;
          default = "wakeproxy-keep-awake";
          description = "charon's wakeproxy keep-awake SSH user (services.wakeproxy.keepAwake.sshTarget.user there).";
        };

        identityFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Private key for the wake-proxy-keep-awake-ssh generator, read via
            my.secrets.allowReadAccess (readers = the account that runs
            wake-charon — agent). Required when keepAwake.enable; the same
            public half is in charon's sshTarget authorized_keys.
          '';
        };

        defaultDurationMinutes = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = 60;
          description = ''
            Default keep-awake lease duration (in minutes) requested when
            `wake-charon` runs without an explicit duration. Also triggers
            charon's `monitor-power-keep-awake-off` to force the display off.
            Set to null to require an explicit duration.
          '';
        };

        defaultDurationSeconds = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default =
            if cfg.keepAwake.defaultDurationMinutes != null
            then cfg.keepAwake.defaultDurationMinutes * 60
            else null;
          defaultText = lib.literalExpression "if cfg.keepAwake.defaultDurationMinutes != null then cfg.keepAwake.defaultDurationMinutes * 60 else null";
          description = "Alias for defaultDurationMinutes in seconds.";
        };

        maxDurationSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 14400;
          description = "Client-side lease cap in seconds (14400s = 240m); must not exceed charon's services.wakeproxy.keepAwake.maxDurationSeconds.";
        };
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.keepAwake.enable -> cfg.keepAwake.identityFile != null;
          message = "my.wake-charon.keepAwake.enable needs keepAwake.identityFile (the wake-proxy-keep-awake-ssh private key).";
        }
      ];

      environment.systemPackages = [script] ++ lib.optionals cfg.keepAwake.enable [pkgs.openssh];
    };
  };
}
