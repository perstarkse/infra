#!/usr/bin/env bash
set -euo pipefail

DISPLAY_NUM="@DISPLAY_NUM@"

usage() {
  echo "Usage: monitor-power off|on" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage

case "$1" in
  off) @DDCUTIL@ -d "$DISPLAY_NUM" setvcp --noverify D6 05 ;;
  on) @DDCUTIL@ -d "$DISPLAY_NUM" setvcp --noverify D6 01 ;;
  *) usage ;;
esac
