#!/usr/bin/env bash
set -uo pipefail

DISPLAY_NUM="@DISPLAY_NUM@"
MAX_ATTEMPTS="@MAX_ATTEMPTS@"
RETRY_INTERVAL="@RETRY_INTERVAL@"
POLICY_FILE="${MONITOR_POWER_POLICY:-/run/monitor-power/policy}"
SOURCE="${1:-resume}"

policy() {
	local value=""
	[[ -r "$POLICY_FILE" ]] || {
		echo "off-until-input"
		return
	}
	value=$(<"$POLICY_FILE")
	value=${value//$'\n'/}
	if [[ -z "$value" ]]; then
		echo "off-until-input"
		return
	fi
	echo "$value"
}

write_policy() {
	@MKDIR@ -p "$(@DIRNAME@ "$POLICY_FILE")"
	printf '%s\n' "$1" >"$POLICY_FILE"
}

turn_on() {
	@DDCUTIL@ --maxtries 1,1,1 -d "$DISPLAY_NUM" setvcp --noverify D6 01 || return 1
	@DDCUTIL@ --maxtries 1,1,1 -d "$DISPLAY_NUM" getvcp D6 2>/dev/null |
		@GREP@ -qE 'sl=0x01|DPM: On'
}

turn_off() {
	@DDCUTIL@ --maxtries 1,1,1 -d "$DISPLAY_NUM" setvcp --noverify D6 05 || return 1
	@DDCUTIL@ --maxtries 1,1,1 -d "$DISPLAY_NUM" getvcp D6 2>/dev/null |
		@GREP@ -qE 'sl=0x05|DPM: Off'
}

force_on() {
	local attempt
	for attempt in $(@SEQ@ 1 "$MAX_ATTEMPTS"); do
		if turn_on 2>/dev/null; then
			@LOGGER@ -t monitor-power "display on ($1)"
			exit 0
		fi
		@SLEEP@ "$RETRY_INTERVAL"
	done
	@DDCUTIL@ --maxtries 1,1,1 -d "$DISPLAY_NUM" setvcp --noverify D6 01 || true
	@LOGGER@ -t monitor-power "display on without verify ($1)"
	exit 0
}

# Physical seat already claimed the machine (input daemon wrote policy=on).
if [[ "$(policy)" == "on" ]]; then
	force_on "physical input"
fi

if [[ "$(policy)" != "on" ]]; then
	write_policy "off-until-input"
fi

for attempt in $(@SEQ@ 1 "$MAX_ATTEMPTS"); do
	if [[ "$(policy)" == "on" ]]; then
		force_on "physical input during $SOURCE"
	fi
	if turn_off 2>/dev/null; then
		if [[ "$(policy)" == "on" ]]; then
			force_on "physical input during $SOURCE"
		fi
		@LOGGER@ -t monitor-power "display off after $SOURCE (until physical input)"
		exit 0
	fi
	@SLEEP@ "$RETRY_INTERVAL"
done

if [[ "$(policy)" == "on" ]]; then
	force_on "physical input during $SOURCE"
fi

@DDCUTIL@ --maxtries 1,1,1 -d "$DISPLAY_NUM" setvcp --noverify D6 05 || true
@LOGGER@ -t monitor-power "display off after $SOURCE without verify (until physical input)"
exit 0
