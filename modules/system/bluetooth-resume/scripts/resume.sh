#!/usr/bin/env bash
set -uo pipefail

MAX_ATTEMPTS="@MAX_ATTEMPTS@"
RETRY_INTERVAL="@RETRY_INTERVAL@"

bt_ready() {
  @BLUETOOTHCTL@ show 2>/dev/null | @GREP@ -q "Powered: yes"
}

power_on() {
  @BLUETOOTHCTL@ power on 2>/dev/null
}

for attempt in $(@SEQ@ 1 "$MAX_ATTEMPTS"); do
  if bt_ready; then
    @LOGGER@ -t bluetooth-resume "adapter ready (attempt $attempt)"
    exit 0
  fi
  power_on || true
  if bt_ready; then
    @LOGGER@ -t bluetooth-resume "adapter ready after power on (attempt $attempt)"
    exit 0
  fi
  @SLEEP@ "$RETRY_INTERVAL"
done

@LOGGER@ -t bluetooth-resume "adapter still down after $MAX_ATTEMPTS attempts, restarting bluetooth.service"
@SYSTEMCTL@ try-restart bluetooth.service
power_on || true
