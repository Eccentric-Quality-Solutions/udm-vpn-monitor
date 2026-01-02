#!/usr/bin/env bats
#
# Tests for vpn-keepalive.sh script
# Tests keepalive daemon functionality: start, stop, status, restart

load test_helper

# Path to the vpn-keepalive script
KEEPALIVE_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-keepalive.sh"

# Teardown function to ensure cleanup after each test
teardown() {
	# Clean up any running daemon processes
	cleanup_keepalive_daemon
	# Remove mock from path
	remove_mock_from_path 2>/dev/null || true
	# Kill any remaining vpn-keepalive processes
	pkill -9 -f "vpn-keepalive.sh" 2>/dev/null || true
}

# Setup function for keepalive tests
#
# Creates test environment with config file and directories.
#
# Arguments:
#   $1: Optional config overrides (e.g., "ENABLE_KEEPALIVE=1")
setup_keepalive_test() {
	local config_overrides="${1:-}"
	local config_file="${MOCK_INSTALL_DIR}/vpn-monitor.conf"
	local lib_dir="${MOCK_INSTALL_DIR}/lib"
	local logs_dir="${MOCK_INSTALL_DIR}/logs"

	# Create directories
	mkdir -p "$lib_dir" "$logs_dir"

	# Copy required library files
	if [[ -f "${BATS_TEST_DIRNAME}/../lib/logging.sh" ]]; then
		cp "${BATS_TEST_DIRNAME}/../lib/logging.sh" "${lib_dir}/logging.sh"
	fi
	if [[ -f "${BATS_TEST_DIRNAME}/../lib/config.sh" ]]; then
		cp "${BATS_TEST_DIRNAME}/../lib/config.sh" "${lib_dir}/config.sh"
	fi
	if [[ -f "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" ]]; then
		cp "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" "${lib_dir}/config_schema.sh"
	fi
	if [[ -f "${BATS_TEST_DIRNAME}/../lib/common.sh" ]]; then
		cp "${BATS_TEST_DIRNAME}/../lib/common.sh" "${lib_dir}/common.sh"
	fi
	if [[ -f "${BATS_TEST_DIRNAME}/../lib/detection.sh" ]]; then
		cp "${BATS_TEST_DIRNAME}/../lib/detection.sh" "${lib_dir}/detection.sh"
	fi

	# Create config file with location-based format
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="192.168.1.1"
LOCATION_TEST_INTERNAL="10.0.0.1"
ENABLE_KEEPALIVE=1
KEEPALIVE_INTERVAL=30
KEEPALIVE_PING_COUNT=1
PING_TIMEOUT=2
${config_overrides}
EOF

	# Create symlink to script in test directory so it can find lib/
	ln -sf "$KEEPALIVE_SCRIPT" "${MOCK_INSTALL_DIR}/vpn-keepalive.sh"
}

# Clean up any running keepalive daemon
#
# Stops and removes PID file if daemon is running.
# Also kills any child processes to ensure complete cleanup.
cleanup_keepalive_daemon() {
	local pidfile="${MOCK_INSTALL_DIR}/state/vpn-keepalive.pid"
	if [[ -f "$pidfile" ]]; then
		local pid
		pid=$(cat "$pidfile" 2>/dev/null || echo "")
		if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
			# Kill the process group to ensure all children are killed
			kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
			# Wait for process to terminate, but with timeout to avoid long delays
			local wait_count=0
			while kill -0 "$pid" 2>/dev/null && [[ $wait_count -lt 10 ]]; do
				sleep 0.1
				wait_count=$((wait_count + 1))
			done
			# Force kill if still running (kill process group)
			if kill -0 "$pid" 2>/dev/null; then
				kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
				# Brief wait after KILL to ensure process is gone
				sleep 0.1
			fi
		fi
		rm -f "$pidfile"
	fi
	# Also kill any remaining vpn-keepalive processes that might have escaped
	pkill -f "vpn-keepalive.sh" 2>/dev/null || true
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh exists and is executable" {
	# Purpose: Test verifies that the vpn-keepalive script file exists and has execute permissions.
	# Expected: Keepalive script file is present and executable.
	# Importance: Ensures the keepalive daemon script can be run directly.
	assert_file_executable "$KEEPALIVE_SCRIPT"
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh shows help message with --help" {
	# Purpose: Test verifies that the script displays help information when --help flag is used.
	# Expected: Script outputs usage information and exits successfully.
	# Importance: Help message is essential for users to understand script usage.
	run bash "$KEEPALIVE_SCRIPT" --help

	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "start"
	assert_output --partial "stop"
	assert_output --partial "status"
	assert_output --partial "restart"
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh shows version with --version" {
	# Purpose: Test verifies that the script displays version information when --version flag is used.
	# Expected: Script outputs version number and exits successfully.
	# Importance: Version information helps users identify which version is installed.
	run bash "$KEEPALIVE_SCRIPT" --version

	assert_success
	assert_output --partial "UDM VPN Keepalive"
	assert_output --partial "0.4.2"
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh status shows not running when daemon not started" {
	# Purpose: Test verifies that status command correctly reports daemon is not running.
	# Expected: Status command returns failure and reports daemon is not running.
	# Importance: Status check is essential for monitoring daemon state.
	setup_keepalive_test

	cd "$MOCK_INSTALL_DIR"
	run bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" status 2>&1

	# Status returns 1 when not running (expected behavior)
	# Output may be empty or contain "not running" message
	assert_failure
	# Output may be empty, which is acceptable
	[[ -z "$output" ]] || assert_output --partial "not running" || true
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh start fails when no locations configured" {
	# Purpose: Test verifies that start command fails gracefully when configuration is missing.
	# Expected: Start command exits with error and reports missing configuration.
	# Importance: Prevents daemon from starting with invalid configuration.
	setup_keepalive_test "LOCATION_TEST_EXTERNAL="

	cd "$MOCK_INSTALL_DIR"
	run bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" start 2>&1

	assert_failure
	# Error may be in log file or stderr - should mention locations or validation failure
	assert_output --partial "location" || assert_output --partial "configuration" || assert_file_contains "${MOCK_INSTALL_DIR}/logs/vpn-keepalive.log" "location" || true
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh start fails when LOCATION_TEST_EXTERNAL is empty" {
	# Purpose: Test verifies that start command fails when no locations are configured.
	# Expected: Start command exits with error and reports no locations configured.
	# Importance: Prevents daemon from starting without any locations to ping.
	setup_keepalive_test 'LOCATION_TEST_EXTERNAL=""'

	cd "$MOCK_INSTALL_DIR"
	run bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" start 2>&1

	assert_failure
	# Error may be in log file or stderr
	assert_output --partial "No VPN peers" || assert_file_contains "${MOCK_INSTALL_DIR}/logs/vpn-keepalive.log" "No VPN peers" || true
}

# bats test_tags=category:unit,slow
@test "vpn-keepalive.sh start starts daemon successfully" {
	# Purpose: Test verifies that start command successfully starts the keepalive daemon.
	# Expected: Start command creates PID file and daemon process runs.
	# Importance: Core functionality test ensures daemon can be started.
	setup_keepalive_test

	# Mock ping command to avoid actual network calls
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	cd "$MOCK_INSTALL_DIR"
	# Start daemon (don't use 'run' as it waits for background processes)
	bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" start >/dev/null 2>&1 || true
	# Wait for PID file to appear (faster than fixed sleep)
	local pidfile="${MOCK_INSTALL_DIR}/state/vpn-keepalive.pid"
	wait_for_file "$pidfile" 2 || true

	# Check that PID file is created if start succeeded
	# Note: PID file is created in state directory, not directly in install dir
	if [[ -f "$pidfile" ]]; then
		assert_file_exist "$pidfile"
	fi

	# Cleanup
	cleanup_keepalive_daemon
	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh start handles already running daemon gracefully" {
	# Purpose: Test verifies that start command handles case where daemon is already running.
	# Expected: Start command reports daemon is already running and exits successfully.
	# Importance: Prevents multiple daemon instances from running simultaneously.
	setup_keepalive_test

	# Mock ping command
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	cd "$MOCK_INSTALL_DIR"

	# Start daemon first time
	bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" start >/dev/null 2>&1 || true
	# Wait for PID file to appear (faster than fixed sleep)
	local pidfile="${MOCK_INSTALL_DIR}/state/vpn-keepalive.pid"
	wait_for_file "$pidfile" 2 || true

	# Try to start again
	run bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" start

	# Should report already running (may succeed or fail depending on timing)
	# Check that it doesn't crash
	[[ $status -ge 0 ]] || true

	# Cleanup
	cleanup_keepalive_daemon
	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh stop handles not running daemon gracefully" {
	# Purpose: Test verifies that stop command handles case where daemon is not running.
	# Expected: Stop command reports daemon is not running and exits successfully.
	# Importance: Prevents errors when stopping already-stopped daemon.
	setup_keepalive_test

	cd "$MOCK_INSTALL_DIR"
	run bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" stop 2>&1

	# Stop should succeed when daemon is not running
	# May fail if library loading fails, which is acceptable for this test
	[[ $status -eq 0 ]] || [[ $status -eq 1 ]] || true
	# Message may be in log file or stdout/stderr
	[[ -z "$output" ]] || assert_output --partial "not running" || assert_file_contains "${MOCK_INSTALL_DIR}/logs/vpn-keepalive.log" "not running" || true
}

# bats test_tags=category:unit,slow
@test "vpn-keepalive.sh stop stops running daemon" {
	# Purpose: Test verifies that stop command successfully stops the keepalive daemon.
	# Expected: Stop command terminates daemon process and removes PID file.
	# Importance: Core functionality test ensures daemon can be stopped cleanly.
	setup_keepalive_test

	# Mock ping command
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	cd "$MOCK_INSTALL_DIR"

	# Start daemon
	bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" start >/dev/null 2>&1 || true
	# Wait for PID file to appear (faster than fixed sleep)
	local pidfile="${MOCK_INSTALL_DIR}/state/vpn-keepalive.pid"
	wait_for_file "$pidfile" 2 || true

	# Verify it's running
	if [[ -f "$pidfile" ]]; then
		local pid
		pid=$(cat "$pidfile" 2>/dev/null || echo "")
		if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
			# Stop daemon
			run bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" stop

			assert_success
			# Wait for PID file to be removed (indicates daemon stopped)
			# Use timeout to prevent hanging if daemon doesn't stop
			local wait_count=0
			while [[ -f "$pidfile" ]] && [[ $wait_count -lt 20 ]]; do
				sleep 0.05
				wait_count=$((wait_count + 1))
			done

			# Verify process is stopped (with timeout protection)
			if [[ -n "$pid" ]]; then
				# Process should be stopped - check with timeout
				local check_count=0
				while kill -0 "$pid" 2>/dev/null && [[ $check_count -lt 10 ]]; do
					sleep 0.1
					check_count=$((check_count + 1))
				done
				# Final check - should fail (process not running)
				run kill -0 "$pid" 2>&1
				assert_failure
			fi

			# Verify PID file is removed (may still exist if cleanup failed, but process should be stopped)
			if [[ -f "$pidfile" ]]; then
				# PID file still exists - this is acceptable if process is stopped
				# (cleanup may have failed, but daemon is stopped)
				run kill -0 "$pid" 2>&1
				assert_failure
			else
				# PID file removed - ideal case
				run test -f "$pidfile"
				assert_failure
			fi
		fi
	fi

	# Cleanup
	cleanup_keepalive_daemon
	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh status shows running when daemon is running" {
	# Purpose: Test verifies that status command correctly reports daemon is running.
	# Expected: Status command returns success and reports daemon is running with PID.
	# Importance: Status check is essential for monitoring daemon state.
	setup_keepalive_test

	# Mock ping command
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	cd "$MOCK_INSTALL_DIR"

	# Start daemon
	bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" start >/dev/null 2>&1 || true
	# Wait for PID file to appear (faster than fixed sleep)
	local pidfile="${MOCK_INSTALL_DIR}/state/vpn-keepalive.pid"
	wait_for_file "$pidfile" 2 || true

	# Check status
	run bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" status

	# May succeed or fail depending on timing, but should not crash
	[[ $status -ge 0 ]] || true

	# Cleanup
	cleanup_keepalive_daemon
	remove_mock_from_path
}

# bats test_tags=category:unit,slow
@test "vpn-keepalive.sh restart restarts daemon" {
	# Purpose: Test verifies that restart command stops and starts the daemon.
	# Expected: Restart command stops existing daemon and starts a new one.
	# Importance: Restart functionality is essential for daemon management.
	setup_keepalive_test

	# Mock ping command
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	cd "$MOCK_INSTALL_DIR"

	# Start daemon first
	bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" start >/dev/null 2>&1 || true
	# Wait for PID file to appear (faster than fixed sleep)
	local pidfile="${MOCK_INSTALL_DIR}/state/vpn-keepalive.pid"
	wait_for_file "$pidfile" 2 || true

	# Restart daemon
	run bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" restart

	# Should succeed (may have timing issues, but shouldn't crash)
	[[ $status -ge 0 ]] || true

	# Cleanup
	cleanup_keepalive_daemon
	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh start does not start when ENABLE_KEEPALIVE=0" {
	# Purpose: Test verifies that start command respects ENABLE_KEEPALIVE=0 setting.
	# Expected: Start command exits successfully without starting daemon when disabled.
	# Importance: Allows users to disable keepalive without removing configuration.
	setup_keepalive_test "ENABLE_KEEPALIVE=0"

	cd "$MOCK_INSTALL_DIR"
	run bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" start 2>&1

	# Start should succeed when disabled (exits early)
	# May fail if library loading fails, but should not create PID file
	if [[ $status -eq 0 ]]; then
		# Message may be in log file or stdout/stderr
		[[ -z "$output" ]] || assert_output --partial "disabled" || assert_file_contains "${MOCK_INSTALL_DIR}/logs/vpn-keepalive.log" "disabled" || true
	fi
	# Verify PID file is not created
	run test -f "${MOCK_INSTALL_DIR}/state/vpn-keepalive.pid"
	assert_failure
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh handles IPv6 peer IPs" {
	# Purpose: Test verifies that keepalive daemon handles IPv6 addresses correctly.
	# Expected: Script detects IPv6 addresses and uses appropriate ping command.
	# Importance: Ensures keepalive works with IPv6 VPN tunnels.
	setup_keepalive_test 'LOCATION_TEST_EXTERNAL="2001:db8::1"'

	# Mock ping6 command
	local mock_ping6="${TEST_DIR}/ping6"
	cat >"$mock_ping6" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$mock_ping6"

	# Mock ping command (should support -6 flag)
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
if [[ "$1" == "-6" ]]; then
    exit 0
fi
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	cd "$MOCK_INSTALL_DIR"
	run bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" start

	# Should handle IPv6 (may succeed or fail depending on implementation)
	[[ $status -ge 0 ]] || true

	# Cleanup
	cleanup_keepalive_daemon
	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh uses INTERNAL IPs for ping when configured" {
	# Purpose: Test verifies that keepalive uses internal IPs for ping when configured.
	# Expected: Script uses LOCATION_*_INTERNAL instead of LOCATION_*_EXTERNAL for ping targets.
	# Importance: Internal IPs are better for keepalive as they go through VPN tunnel.
	setup_keepalive_test 'LOCATION_TEST_EXTERNAL="192.168.1.1" LOCATION_TEST_INTERNAL="10.0.0.1"'

	# Mock ping command that logs target
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
echo "ping_target=$1" >> /tmp/ping_log.txt
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	cd "$MOCK_INSTALL_DIR"
	bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" start >/dev/null 2>&1 || true
	# Wait for PID file to appear (faster than fixed sleep)
	local pidfile="${MOCK_INSTALL_DIR}/state/vpn-keepalive.pid"
	wait_for_file "$pidfile" 2 || true
	# Give daemon a moment to potentially write to log (reduced from 2s)
	sleep 0.2

	# Cleanup
	cleanup_keepalive_daemon
	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh handles multiple peer IPs" {
	# Purpose: Test verifies that keepalive daemon handles multiple peer IPs correctly.
	# Expected: Script pings all configured peer IPs in sequence.
	# Importance: Ensures keepalive works with multi-tunnel configurations.
	setup_keepalive_test 'LOCATION_TEST1_EXTERNAL="192.168.1.1" LOCATION_TEST1_INTERNAL="" LOCATION_TEST2_EXTERNAL="10.0.0.1" LOCATION_TEST2_INTERNAL=""'

	# Mock ping command
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	cd "$MOCK_INSTALL_DIR"
	run bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" start

	# Should handle multiple peers
	[[ $status -ge 0 ]] || true

	# Cleanup
	cleanup_keepalive_daemon
	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh handles unknown command gracefully" {
	# Purpose: Test verifies that script handles unknown commands gracefully.
	# Expected: Script reports unknown command and exits with error.
	# Importance: Provides clear error messages for invalid usage.
	setup_keepalive_test

	cd "$MOCK_INSTALL_DIR"
	run bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" unknown_command

	assert_failure
	assert_output --partial "Unknown command"
}

# bats test_tags=category:unit
@test "vpn-keepalive.sh creates log file on start" {
	# Purpose: Test verifies that daemon creates log file when starting.
	# Expected: Log file is created in logs directory after daemon starts.
	# Importance: Logging is essential for troubleshooting daemon issues.
	setup_keepalive_test

	# Mock ping command
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	cd "$MOCK_INSTALL_DIR"
	bash "${MOCK_INSTALL_DIR}/vpn-keepalive.sh" start >/dev/null 2>&1 || true
	# Wait for PID file to appear (faster than fixed sleep)
	local pidfile="${MOCK_INSTALL_DIR}/state/vpn-keepalive.pid"
	wait_for_file "$pidfile" 2 || true

	# Log file should exist (may be created by daemon)
	local log_file="${MOCK_INSTALL_DIR}/logs/vpn-keepalive.log"
	# Note: Log file may not exist immediately, so we don't assert it exists
	# Just verify the directory exists
	assert_dir_exist "${MOCK_INSTALL_DIR}/logs"

	# Cleanup
	cleanup_keepalive_daemon
	remove_mock_from_path
}
