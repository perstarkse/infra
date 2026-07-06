#!/usr/bin/env bash
set -euo pipefail

monitor-power off || true
exec systemctl suspend
