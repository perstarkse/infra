#!/usr/bin/env bash
set -uo pipefail

DISPLAY_NUM="@DISPLAY_NUM@"
MAX_ATTEMPTS="@MAX_ATTEMPTS@"
RETRY_INTERVAL="@RETRY_INTERVAL@"

turn_on() {
	# ddcutil >=2.x: --maxtries takes write,read,multi_try tries (comma list)
	@DDCUTIL@ --maxtries 1,1,1 -d "$DISPLAY_NUM" setvcp --noverify D6 01
}

for attempt in $(@SEQ@ 1 "$MAX_ATTEMPTS"); do
	if turn_on 2>/dev/null; then
		@LOGGER@ -t monitor-power "display on (attempt $attempt)"
		exit 0
	fi
	@SLEEP@ "$RETRY_INTERVAL"
done

@LOGGER@ -t monitor-power "display still off after $MAX_ATTEMPTS attempts"
turn_on || true
