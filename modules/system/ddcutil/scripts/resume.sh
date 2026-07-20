#!/usr/bin/env bash
set -uo pipefail

DISPLAY_NUM="@DISPLAY_NUM@"
MAX_ATTEMPTS="@MAX_ATTEMPTS@"
RETRY_INTERVAL="@RETRY_INTERVAL@"
RESUME_ON_LOCAL_WAKE_ONLY="@RESUME_ON_LOCAL_WAKE_ONLY@"
RESUME_WAIT_SECONDS="@RESUME_WAIT_SECONDS@"
REMOTE_WAKE_USER="@REMOTE_WAKE_USER@"
KEEP_AWAKE_STATE_DIR="@KEEP_AWAKE_STATE_DIR@"
KEEP_AWAKE_UNIT="@KEEP_AWAKE_UNIT@"
SUSPEND_CURSOR_FILE="/run/monitor-power-suspend-cursor"
SUSPEND_SINCE_FILE="/run/monitor-power-suspend-since"

# Active wake-proxy lease: until timestamp in the future AND pid still alive.
# Stale files after suspend must not count (pid is dead).
keep_awake_lease_active() {
	local pid_file="$KEEP_AWAKE_STATE_DIR/${KEEP_AWAKE_UNIT}.pid"
	local until_file="$KEEP_AWAKE_STATE_DIR/${KEEP_AWAKE_UNIT}.until"
	[[ -s "$pid_file" && -s "$until_file" ]] || return 1

	local pid until_ts now
	pid=$(<"$pid_file")
	until_ts=$(<"$until_file")
	now=$(@DATE@ +%s)

	case "$pid" in
	"" | *[!0-9]*) return 1 ;;
	esac
	case "$until_ts" in
	"" | *[!0-9]*) return 1 ;;
	esac

	[[ "$until_ts" -gt "$now" ]] || return 1
	kill -0 "$pid" 2>/dev/null
}

# wake-proxy SSH accept after the suspend marker (lease process is short-lived).
remote_ssh_since_suspend() {
	[[ -n "$REMOTE_WAKE_USER" ]] || return 1

	local journal_args=(-b --no-pager)
	if [[ -s "$SUSPEND_SINCE_FILE" ]]; then
		journal_args+=(--since="$(<"$SUSPEND_SINCE_FILE")")
	elif [[ -s "$SUSPEND_CURSOR_FILE" ]]; then
		journal_args+=(--after-cursor="$(<"$SUSPEND_CURSOR_FILE")")
	fi

	@JOURNALCTL@ "${journal_args[@]}" 2>/dev/null |
		@GREP@ -q "Accepted publickey for ${REMOTE_WAKE_USER}"
}

remote_wake_reason() {
	if keep_awake_lease_active; then
		echo "keep-awake lease (${KEEP_AWAKE_UNIT})"
		return 0
	fi
	if remote_ssh_since_suspend; then
		echo "keep-awake ssh (${REMOTE_WAKE_USER})"
		return 0
	fi
	return 1
}

remote_wake_detected() {
	remote_wake_reason >/dev/null
}

# Verify via getvcp D6. Do not match "DPMS: Off" — that appears while DPM: On.
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

# Optimistic path: power the panel on ASAP, then retract if this was WoL.
turned_on=0
for attempt in $(@SEQ@ 1 "$MAX_ATTEMPTS"); do
	if [[ "$RESUME_ON_LOCAL_WAKE_ONLY" == "true" ]] && remote_wake_detected; then
		reason=$(remote_wake_reason)
		@LOGGER@ -t monitor-power "skipping display on ($reason)"
		exit 0
	fi

	if turn_on 2>/dev/null; then
		@LOGGER@ -t monitor-power "display on (attempt $attempt)"
		turned_on=1
		break
	fi
	@SLEEP@ "$RETRY_INTERVAL"
done

if [[ "$turned_on" -eq 0 ]]; then
	@LOGGER@ -t monitor-power "display still off after $MAX_ATTEMPTS attempts"
	# Best-effort final write without requiring verify (I2C may still be settling).
	@DDCUTIL@ --maxtries 1,1,1 -d "$DISPLAY_NUM" setvcp --noverify D6 01 || true
fi

if [[ "$RESUME_ON_LOCAL_WAKE_ONLY" != "true" ]]; then
	exit 0
fi

elapsed_ms=0
step_ms=250
max_ms=$(@AWK@ -v wait="$RESUME_WAIT_SECONDS" 'BEGIN { printf "%d", wait * 1000 }')

while [[ "$elapsed_ms" -lt "$max_ms" ]]; do
	if remote_wake_detected; then
		reason=$(remote_wake_reason)
		if turn_off 2>/dev/null; then
			@LOGGER@ -t monitor-power "display off after remote wake ($reason)"
		else
			@DDCUTIL@ --maxtries 1,1,1 -d "$DISPLAY_NUM" setvcp --noverify D6 05 || true
			@LOGGER@ -t monitor-power "remote wake ($reason); forced display off without verify"
		fi
		exit 0
	fi
	@SLEEP@ 0.25
	elapsed_ms=$((elapsed_ms + step_ms))
done

exit 0
