#!/usr/bin/env bash
set -uo pipefail

DISPLAY_NUM="@DISPLAY_NUM@"
MAX_ATTEMPTS="@MAX_ATTEMPTS@"
RETRY_INTERVAL="@RETRY_INTERVAL@"
WAKE_INTERFACE="@WAKE_INTERFACE@"
RESUME_ON_LOCAL_WAKE_ONLY="@RESUME_ON_LOCAL_WAKE_ONLY@"
SUSPEND_CURSOR_FILE="/run/monitor-power-suspend-cursor"

network_wake_since_suspend() {
	[[ -n "$WAKE_INTERFACE" ]] || return 1

	local wakeup_count_path="/sys/class/net/${WAKE_INTERFACE}/device/power/wakeup_count"
	local saved_count_file="/run/monitor-power-suspend-nic-wakeup-count"
	if [[ -r "$wakeup_count_path" && -s "$saved_count_file" ]]; then
		local before after
		before=$(<"$saved_count_file")
		after=$(<"$wakeup_count_path")
		if [[ "$after" -gt "$before" ]]; then
			return 0
		fi
		return 1
	fi

	local journal_args=(-b -k --no-pager)
	if [[ -s "$SUSPEND_CURSOR_FILE" ]]; then
		journal_args+=(--after-cursor="$(<"$SUSPEND_CURSOR_FILE")")
	fi

	@JOURNALCTL@ "${journal_args[@]}" 2>/dev/null | @GREP@ -qiE \
		"(${WAKE_INTERFACE}.*(magic[[:space:]]*packet|wol)|magic[[:space:]]*packet.*${WAKE_INTERFACE}|received magic packet)"
}

if [[ "$RESUME_ON_LOCAL_WAKE_ONLY" == "true" ]] && network_wake_since_suspend; then
	@LOGGER@ -t monitor-power "skipping display on (network wake on ${WAKE_INTERFACE})"
	exit 0
fi

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
