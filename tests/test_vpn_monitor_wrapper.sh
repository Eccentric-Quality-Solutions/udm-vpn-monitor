#!/usr/bin/env bats
#
# Tests for vpn-monitor-wrapper.sh — runtime behavior (cron invokes wrapper → monitor runs).

load test_helper

WRAPPER_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor-wrapper.sh"

# bats test_tags=category:integration,priority:high
@test "vpn-monitor-wrapper.sh runs vpn-monitor.sh and records invocations" {
	# Purpose: Cron installs the wrapper; this verifies the wrapper actually executes the monitor script.
	# Expected: At least one invocation of vpn-monitor.sh within a short window (MONITOR_INTERVAL=10).
	# Importance: Install tests only assert crontab text; this covers the runtime path (lock, loop, exec).
	local inst="${TEST_DIR}/install"
	mkdir -p "${inst}/state" "${inst}/logs"

	# Minimal config: interval only (get_monitor_interval reads MONITOR_INTERVAL)
	cat >"${inst}/vpn-monitor.conf" <<EOF
MONITOR_INTERVAL=10
EOF

	cp "$WRAPPER_SCRIPT" "${inst}/vpn-monitor-wrapper.sh"
	chmod +x "${inst}/vpn-monitor-wrapper.sh"

	local inv_file="${TEST_DIR}/monitor_invocations"
	rm -f "$inv_file"
	cat >"${inst}/vpn-monitor.sh" <<EOF
#!/bin/bash
echo "\$(date +%s)" >>"${inv_file}"
exit 0
EOF
	chmod +x "${inst}/vpn-monitor.sh"

	# Run wrapper in background; it loops until killed.
	# `exec` replaces the subshell with the wrapper so $! is the wrapper PID
	# (not a subshell parent that, when killed, leaves the wrapper orphaned
	# holding bats's stdout pipe and hanging the test).
	# Output redirected to a file so the wrapper does not inherit bats's stdout/stderr.
	local wrapper_log="${TEST_DIR}/wrapper.log"
	(cd "$inst" && exec bash ./vpn-monitor-wrapper.sh) >"$wrapper_log" 2>&1 &
	local wpid=$!

	# Poll for first invocation instead of fixed sleep
	local waited=0
	while [[ $waited -lt 50 ]] && [[ ! -s "$inv_file" ]]; do
		sleep 0.1
		waited=$((waited + 1))
	done

	if ! kill -0 "$wpid" 2>/dev/null; then
		echo "wrapper process exited unexpectedly; log:" >&2
		cat "$wrapper_log" >&2 || true
		return 1
	fi

	local n
	n=$(wc -l <"$inv_file" 2>/dev/null | tr -d ' ' || echo 0)
	kill -TERM "$wpid" 2>/dev/null || true
	wait "$wpid" 2>/dev/null || true

	assert [ "${n:-0}" -ge 1 ]
}

# bats test_tags=category:unit
@test "vpn-monitor-wrapper.sh --help exits 0" {
	run bash "$WRAPPER_SCRIPT" --help
	assert_success
	assert_output --partial "MONITOR_INTERVAL"
}
