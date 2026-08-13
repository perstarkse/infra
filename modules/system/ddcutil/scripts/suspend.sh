#!/usr/bin/env bash
set -euo pipefail

mkdir -p /run/monitor-power
printf 'off-until-input\n' > /run/monitor-power/policy
monitor-power off || true
exec systemctl suspend
