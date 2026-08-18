#!/usr/bin/env bash
set -euo pipefail

# The policy write is root-only (/run is root-owned). Niri spawns this from the
# user session for Mod+Ctrl+L, where it must not abort; the ddcutil systemd-sleep
# pre hook writes the same policy at actual sleep, so skipping is safe.
if [ "$(id -u)" -eq 0 ]; then
	mkdir -p /run/monitor-power
	printf 'off-until-input\n' >/run/monitor-power/policy
fi

monitor-power off || true
exec systemctl suspend
