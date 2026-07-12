#!/usr/bin/env bash
set -uo pipefail

DISPLAY_NUM="@DISPLAY_NUM@"
MAX_ATTEMPTS="@MAX_ATTEMPTS@"
RETRY_INTERVAL="@RETRY_INTERVAL@"
RESUME_ON_LOCAL_WAKE_ONLY="@RESUME_ON_LOCAL_WAKE_ONLY@"
RESUME_WAIT_SECONDS="@RESUME_WAIT_SECONDS@"
REMOTE_WAKE_USER="@REMOTE_WAKE_USER@"
SUSPEND_SINCE_FILE="/run/monitor-power-suspend-since"
SUSPEND_IDLE_HINT_FILE="/run/monitor-power-suspend-idle-hint"

graphical_idle_hint() {
	for session in $(@LOGINCTL@ list-sessions --no-legend | @AWK@ '{print $1}'); do
		session_type=$(@LOGINCTL@ show-session "$session" -p Type --value 2>/dev/null || true)
		session_class=$(@LOGINCTL@ show-session "$session" -p Class --value 2>/dev/null || true)
		if { [[ "$session_type" == "wayland" ]] || [[ "$session_type" == "x11" ]]; } \
			&& [[ "$session_class" == "user" ]]; then
			@LOGINCTL@ show-session "$session" -p IdleHint --value 2>/dev/null || echo "yes"
			return 0
		fi
	done
	echo "yes"
}

remote_wake_detected() {
	[[ -n "$REMOTE_WAKE_USER" ]] || return 1
	for session in $(@LOGINCTL@ list-sessions --no-legend | @AWK@ '{print $1}'); do
		user=$(@LOGINCTL@ show-session "$session" -p Name --value 2>/dev/null || true)
		[[ "$user" == "$REMOTE_WAKE_USER" ]] && return 0
	done
	return 1
}

power_button_wake_detected() {
	[[ -s "$SUSPEND_SINCE_FILE" ]] || return 1
	@JOURNALCTL@ -u systemd-logind -b --since "$(<"$SUSPEND_SINCE_FILE")" --no-pager 2>/dev/null \
		| @GREP@ -qE 'Power key|Sleep key|Lid opened'
}

input_wake_detected() {
	local ev name event_name
	for ev in /dev/input/event*; do
		[[ -r "$ev" ]] || continue
		event_name=$(basename "$ev")
		name=$(cat "/sys/class/input/${event_name}/device/name" 2>/dev/null || true)
		case "$name" in
			*"(MCS)"*|"") continue ;;
		esac
		if @TIMEOUT@ 0.05 @DD@ if="$ev" bs=24 count=1 status=none 2>/dev/null; then
			return 0
		fi
	done
	return 1
}

idle_hint_wake_detected() {
	[[ -s "$SUSPEND_IDLE_HINT_FILE" ]] || return 1
	local before after
	before=$(<"$SUSPEND_IDLE_HINT_FILE")
	after=$(graphical_idle_hint)
	[[ "$before" == "yes" && "$after" == "no" ]]
}

local_wake_detected() {
	power_button_wake_detected && return 0
	input_wake_detected && return 0
	idle_hint_wake_detected && return 0
	return 1
}

should_skip_display_on() {
	local elapsed=0
	local step_ms=500
	local max_ms
	max_ms=$(@AWK@ -v wait="$RESUME_WAIT_SECONDS" 'BEGIN { printf "%d", wait * 1000 }')

	while [[ "$elapsed" -lt "$max_ms" ]]; do
		if remote_wake_detected; then
			return 0
		fi
		if local_wake_detected; then
			return 1
		fi
		@SLEEP@ 0.5
		elapsed=$((elapsed + step_ms))
	done

	if remote_wake_detected; then
		return 0
	fi

	! local_wake_detected
}

if [[ "$RESUME_ON_LOCAL_WAKE_ONLY" == "true" ]] && should_skip_display_on; then
	reason="remote/WoL wake"
	if remote_wake_detected; then
		reason="remote wake ($REMOTE_WAKE_USER)"
	fi
	@LOGGER@ -t monitor-power "skipping display on ($reason)"
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
