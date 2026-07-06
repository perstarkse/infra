#!/usr/bin/env bash
# Switch monitor picture profile by name (from monitor.yaml picture_modes).
set -euo pipefail

MONITOR_DIR="@MONITOR_DIR@"
DISPLAY_NUM="@DISPLAY_NUM@"
YQ="@YQ@"
MONITOR_YAML="$MONITOR_DIR/monitor.yaml"

usage() {
  echo "Usage: monitor-profile <mode>|list" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage

if [[ "$1" == "list" ]]; then
  "$YQ" -r '.picture_modes | to_entries[] | select(.value.confirmed == true) | .key + " (E2 " + (.value.e2 | tostring) + ")"' "$MONITOR_YAML"
  exit 0
fi

MODE="$1"

if ! "$YQ" -e ".picture_modes.\"$MODE\"" "$MONITOR_YAML" >/dev/null 2>&1; then
  echo "Unknown profile '$MODE'. Valid names:" >&2
  "$YQ" -r '.picture_modes | keys[]' "$MONITOR_YAML" >&2
  exit 1
fi

e2=$("$YQ" -r ".picture_modes.\"$MODE\".e2 // \"\"" "$MONITOR_YAML")
confirmed=$("$YQ" -r ".picture_modes.\"$MODE\".confirmed // false" "$MONITOR_YAML")

if [[ "$confirmed" != "true" || -z "$e2" || "$e2" == "null" ]]; then
  echo "Profile '$MODE' is not mapped in monitor.yaml." >&2
  exit 1
fi

@DDCUTIL@ -d "$DISPLAY_NUM" setvcp --noverify E2 "$e2"
echo "Set profile $MODE (E2=$e2)"
