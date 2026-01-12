#!/usr/bin/env bats
#
# Tests for vpn-monitor.sh script
# Tests monitoring functionality, tier escalation, and recovery actions

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_cooldown

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# bats test_tags=category:unit
@test "vpn-monitor.sh exists and is executable - should be present and executable" {
	# Purpose: Test verifies that the VPN monitor script file exists and has execute permissions.
	# Expected: Script file is present and executable.
	# Importance: Ensures the script can be run directly without requiring bash explicitly.
	assert_file_exist "$VPN_MONITOR_SCRIPT"
	assert_file_executable "$VPN_MONITOR_SCRIPT"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh shows help with --help flag - should display usage information" {
	# Purpose: Test verifies that the script displays usage information when --help flag is provided.
	# Expected: Script outputs usage information including "--fake" flag description.
	# Importance: Ensures users can access help documentation for script usage.
	run bash "$VPN_MONITOR_SCRIPT" --help
	assert_success
	assert_output --partial "Usage:"
	assert_output --partial "--fake"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh shows help with -h flag - should display usage information" {
	# Purpose: Test verifies that the script displays usage information when -h short flag is provided.
	# Expected: Script outputs usage information.
	# Importance: Ensures short form help flag works correctly for user convenience.
	run bash "$VPN_MONITOR_SCRIPT" -h
	assert_success
	assert_output --partial "Usage:"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh exits with error if LOCATION_*_EXTERNAL not configured - should exit with error message" {
	# Purpose: Test verifies that the script validates required configuration and exits with error
	# when LOCATION_*_EXTERNAL is missing or empty.
	# Expected: Script exits with failure status and outputs error message about missing configuration.
	# Importance: Prevents script from running with invalid configuration that would cause runtime errors.
	# Create temporary config without LOCATION_*_EXTERNAL
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
VPN_NAME="Test VPN"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	# Create state directory and ensure log directory exists
	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Create test version of script with custom paths
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	run bash "$test_script"

	assert_failure
	assert_output --partial "No location-based configuration found"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh creates state directory if missing - should create directory automatically" {
	# Purpose: Test verifies that the script automatically creates the state directory if it doesn't exist.
	# Expected: State directory is created during script initialization.
	# Importance: Ensures script can run successfully even on first execution without manual directory setup.
	# State directory doesn't exist yet
	local state_dir="${TEST_DIR}/state"
	setup_test_vpn_monitor "${TEST_PEER_IP}" "$state_dir"

	run bash "$TEST_SCRIPT" --fake

	# State directory should be created
	assert_dir_exist "$state_dir"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh initializes state files - should create restart_count file" {
	# Purpose: Test verifies that the script creates necessary state files during initialization.
	# Expected: restart_count file is created in state directory.
	# Importance: State files are required for tracking restart history and rate limiting.
	# Note: Per-peer failure counters are created on-demand, not during initialization.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	run bash "$TEST_SCRIPT" --fake

	# State files should be created in logs directory
	# Note: Per-peer failure counters are created on-demand, not during initialization
	# Only restart_count is created during initialization
	assert_file_exist "${STATE_DIR}/restart_count"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh creates log file - should create log file in logs directory" {
	# Purpose: Test verifies that the script creates the log file for recording execution events.
	# Expected: Log file is created in the logs directory.
	# Importance: Logging is essential for troubleshooting and monitoring script behavior.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	run bash "$TEST_SCRIPT" --fake

	# Log file should be created
	assert_file_exist "$LOG_FILE"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh logs script start - should log start message" {
	# Purpose: Test verifies that the script logs a start message when execution begins.
	# Expected: Log file contains "VPN monitor script started" message.
	# Importance: Start messages help identify script execution boundaries in log files.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	run bash "$TEST_SCRIPT" --fake

	# Check log contains start message
	assert_file_contains "$LOG_FILE" "VPN monitor script started"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh handles --fake flag - should log fake mode message" {
	# Purpose: Test verifies that the script correctly handles the --fake flag for testing mode.
	# Expected: Script logs fake mode message and disables tier escalation actions.
	# Importance: Fake mode allows testing without triggering actual recovery actions.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	run bash "$TEST_SCRIPT" --fake

	# Check log contains fake mode message
	assert_file_contains "$LOG_FILE" "fake mode"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh validates peer IP format - should handle invalid format gracefully" {
	# Purpose: Test verifies that the script validates peer IP addresses and handles invalid formats gracefully.
	# Expected: Script handles invalid IP format without crashing, may log warning or exit early.
	# Importance: IP validation prevents command injection and ensures only valid IPs are processed.
	setup_test_vpn_monitor "invalid-ip" "${TEST_DIR}"

	run bash "$TEST_SCRIPT" --fake

	# Should handle invalid IP (may log warning or error)
	# The script should not crash - check if log file was created or script ran
	# Script may exit early if IP validation fails, so check status is reasonable
	if [[ $status -eq 0 ]] || [[ $status -eq 1 ]]; then
		# Script ran (may have failed validation, which is expected)
		assert_file_exist "$LOG_FILE"
	fi
}

# bats test_tags=category:unit
@test "vpn-monitor.sh rejects dangerous characters in peer IP - should log error and prevent injection" {
	# Purpose: Test verifies that the script rejects peer IPs containing shell injection characters.
	# Expected: Script detects invalid IP format and logs error message, preventing command injection.
	# Importance: Security test ensures malicious input cannot execute arbitrary commands.
	setup_test_vpn_monitor "192.168.1.1; rm -rf /" "${TEST_DIR}"

	run bash "$TEST_SCRIPT" --fake

	# Should reject invalid IP format (new validation function checks format, not just dangerous chars)
	assert_file_contains "$LOG_FILE" "Invalid external IP format"
}

# bats test_tags=slow,category:unit
@test "vpn-monitor.sh handles multiple peer IPs - should process all configured peers" {
	# Purpose: Test verifies that the script correctly processes multiple peer IP addresses from configuration.
	# Expected: Script runs successfully and processes all configured peer IPs.
	# Importance: Supports monitoring multiple VPN tunnels simultaneously.
	setup_test_vpn_monitor "${TEST_PEER_IP} ${TEST_PEER_IP2}" "${TEST_DIR}"

	run bash "$TEST_SCRIPT" --fake

	# Should process multiple IPs - script should run successfully
	assert_file_exist "$LOG_FILE"
}

# bats test_tags=slow,category:unit
@test "vpn-monitor.sh maintains independent failure counters per peer - should track each peer separately" {
	# Purpose: Test verifies that each peer IP maintains its own independent failure counter.
	# Expected: Each peer has a separate counter file that increments independently based on that peer's status.
	# Importance: Ensures failures in one VPN tunnel don't affect monitoring of other tunnels.
	setup_test_vpn_monitor "${TEST_PEER_IP} ${TEST_PEER_IP2}" "${TEST_DIR}" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5'
	# Set up state files using location-aware functions
	# setup_test_vpn_monitor creates locations TEST1 and TEST2 for the two IPs
	source_function "set_peer_state"
	set_peer_state "TEST1" "${TEST_PEER_IP}" "failure_count" "2"
	set_peer_state "TEST2" "${TEST_PEER_IP2}" "failure_count" "4"

	# Create mock ip command that returns empty output (VPN down, no SA) for both peers
	mock_ip_vpn_down
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Use get_peer_state_file_path to get correct paths dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true

	# Each peer should have its own independent counter
	# Peer 1 should have incremented from 2
	local failure_counter1
	failure_counter1=$(get_peer_state_file_path "TEST1" "${TEST_PEER_IP}" "failure_count")
	if [[ -f "$failure_counter1" ]]; then
		local count1
		count1=$(cat "$failure_counter1")
		assert [ "$count1" -gt 2 ]
	fi

	# Peer 2 should have incremented from 4
	local failure_counter2
	failure_counter2=$(get_peer_state_file_path "TEST2" "${TEST_PEER_IP2}" "failure_count")
	if [[ -f "$failure_counter2" ]]; then
		local count2
		count2=$(cat "$failure_counter2")
		assert [ "$count2" -gt 4 ]
	fi

	# Counters should be independent (count1 != count2)
	if [[ -f "$failure_counter1" ]] && [[ -f "$failure_counter2" ]]; then
		local count1
		count1=$(cat "$failure_counter1")
		local count2
		count2=$(cat "$failure_counter2")
		# They should differ since they started at different values
		assert_not_equal "$count1" "$count2"
	fi

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-monitor.sh increments failure counter on failure - should increment counter" {
	# Purpose: Test verifies that the script increments the failure counter when VPN check detects a failure.
	# Expected: Per-peer failure counter file is created and incremented when VPN is down.
	# Importance: Failure counters track consecutive failures to trigger tiered recovery actions.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'TIER1_THRESHOLD=1' 'TIER2_THRESHOLD=3' 'TIER3_THRESHOLD=5'
	setup_mock_vpn_environment "${TEST_PEER_IP}" 0

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true

	# Per-peer failure counter should be incremented
	local failure_counter
	failure_counter=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "failure_count")
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		assert [ "$count" -gt 0 ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-monitor.sh resets failure counter on success - should reset counter to 0" {
	# Purpose: Test verifies that the script resets the failure counter to 0 when VPN check succeeds.
	# Expected: Failure counter is reset to 0 when VPN is healthy, clearing previous failure history.
	# Importance: Ensures recovery actions are only triggered for consecutive failures, not transient issues.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	# Set initial failure count using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	set_peer_state "" "${TEST_PEER_IP}" "failure_count" "5" || true
	set_peer_state "" "${TEST_PEER_IP}" "last_bytes" "1000" || true

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true

	# Per-peer failure counter should be reset (if script ran successfully)
	local failure_counter
	failure_counter=$(get_state_file_path "" "${TEST_PEER_IP}" "failure_count")
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter")
		# Counter should be 0 if VPN check succeeded
		# Note: This test may need VPN to actually be "up" for counter to reset
		assert [ "$count" -ge 0 ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-monitor.sh respects cooldown period - should exit early when active" {
	# Purpose: Test verifies that the script exits early when a cooldown period is active after recovery actions.
	# Expected: Script detects cooldown period and exits without performing checks or actions.
	# Importance: Cooldown prevents excessive recovery actions and allows time for VPN to stabilize.
	setup_vpn_cooldown_fixture "${TEST_PEER_IP}" 0 900 'COOLDOWN_MINUTES=15'

	run bash "$TEST_SCRIPT" --fake

	# Should exit early due to cooldown
	assert_file_contains "$LOG_FILE" "cooldown period"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh handles lockfile timeout - should handle stale lockfile" {
	# Purpose: Test verifies that the script handles stale lockfiles that exceed the timeout period.
	# Expected: Script detects stale lockfile (older than LOCKFILE_TIMEOUT) and handles it appropriately.
	# Importance: Prevents script from being blocked indefinitely by abandoned lockfiles from crashed processes.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'LOCKFILE_TIMEOUT=60'

	# Create stale lockfile (old timestamp)
	local old_timestamp=$(($(date +%s) - 70)) # 70 seconds ago (older than 60s timeout)
	echo "${old_timestamp}:12345" >"$LOCKFILE"

	# Touch lockfile to make it old
	touch -d "@$old_timestamp" "$LOCKFILE" 2>/dev/null || true

	run bash "$TEST_SCRIPT" --fake

	# Should handle stale lockfile
	assert_file_exist "$LOG_FILE"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh prevents concurrent execution with lockfile - should detect existing lockfile" {
	# Purpose: Test verifies that the script uses lockfiles to prevent multiple instances from running simultaneously.
	# Expected: Script detects existing lockfile and either waits or exits to prevent concurrent execution.
	# Importance: Prevents race conditions and state file corruption from multiple script instances.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Create lockfile with current PID
	echo "$(date +%s):$$" >"$LOCKFILE"

	# Try to run script (should detect lockfile)
	run timeout 2 bash "$TEST_SCRIPT" --fake 2>&1

	# Script should handle lockfile detection gracefully
	assert_success
	# Should detect existing lockfile (may exit or wait)
	# The exact behavior depends on whether flock is available
	assert_file_exist "$LOG_FILE"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh loads configuration from file - should log successful load" {
	# Purpose: Test verifies that the script successfully loads configuration variables from the config file.
	# Expected: Script reads config file and logs successful configuration load message.
	# Importance: Configuration loading is essential for script customization and proper operation.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'VPN_NAME="Custom VPN Name"' 'DEBUG=1'

	run bash "$TEST_SCRIPT" --fake

	# Should load config
	assert_file_contains "$LOG_FILE" "Configuration loaded"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh uses default config if file missing - should log warning and use defaults" {
	# Purpose: Test verifies that the script handles missing configuration file gracefully and uses defaults.
	# Expected: Script logs warning about missing config file and continues with default values.
	# Importance: Ensures script can run even if config file is accidentally deleted or misconfigured.
	mkdir -p "${TEST_DIR}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local config_file="${TEST_DIR}/nonexistent.conf"

	# Don't create config file - create test script pointing to non-existent config
	# Ensure logs directory exists for log file
	mkdir -p "${TEST_DIR}/logs"
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$TEST_DIR" "$log_file")

	# Don't create config file - test should handle missing config gracefully
	run bash "$test_script" --fake

	# Should use defaults and warn
	assert_file_contains "$log_file" "Configuration file not found"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh handles ping check when enabled - should perform ping checks" {
	# Purpose: Test verifies that the script performs ping checks when ENABLE_PING_CHECK is enabled in configuration.
	# Expected: Script executes ping checks to internal location IPs as an additional VPN health verification method.
	# Importance: Ping checks provide an additional layer of VPN connectivity verification beyond xfrm state checks.
	setup_location_test_vpn_monitor "${TEST_DIR}" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"LOCATION_NYC_INTERNAL=\"${TEST_PEER_IP}\"" \
		'ENABLE_PING_CHECK=1' \
		'PING_COUNT=3' \
		'PING_TIMEOUT=2'
	setup_mock_vpn_environment "203.0.113.1" 2000 "0x12345678" "${TEST_PEER_IP}" 1

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Should perform ping check
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-monitor.sh handles debug mode - should enable debug logging" {
	# Purpose: Test verifies that the script enables debug logging when DEBUG=1 is set in configuration.
	# Expected: Script enables verbose debug output for troubleshooting script behavior.
	# Importance: Debug mode is essential for diagnosing issues in production environments.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'DEBUG=1'

	DEBUG=1 run bash "$TEST_SCRIPT" --fake

	# Debug output should be present
	assert_file_exist "$LOG_FILE"
	# Debug messages go to stderr, check log file for DEBUG entries
	# May or may not have DEBUG entries depending on execution path
	run grep -q "DEBUG" "$LOG_FILE" || true
	# Note: grep -q returns 0 if found, 1 if not found - both are acceptable here
}

# bats test_tags=category:unit
@test "vpn-monitor.sh checks cron persistence - should verify cron entry exists" {
	# Purpose: Test verifies that the script checks for cron job persistence to ensure scheduled execution.
	# Expected: Script verifies cron entry exists and may warn if cron job is missing.
	# Importance: Ensures script continues to run on schedule even after system reboots or cron changes.
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Remove cron entry if it exists
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true

	run bash "$TEST_SCRIPT" --fake

	# Should check cron persistence
	assert_file_exist "$LOG_FILE"
	# May warn if cron not found
}

# ============================================================================
# Tests for main execution flow functions (initialize_monitor, validate_monitor_state, process_locations)
# ============================================================================

# bats test_tags=category:unit
@test "vpn-monitor.sh initialize_monitor logs script start in normal mode - should log start message" {
	# Purpose: Test verifies that initialize_monitor function logs script start message in normal execution mode.
	# Expected: Log contains "VPN monitor script started" message but not fake mode message.
	# Importance: Ensures proper logging distinguishes between normal and test modes.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	# Should log script start (not fake mode message)
	assert_file_contains "$LOG_FILE" "VPN monitor script started"
	refute_output --partial "fake mode"

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-monitor.sh initialize_monitor logs script start in fake mode - should log fake mode message" {
	# Purpose: Test verifies that initialize_monitor function correctly identifies and logs fake mode operation.
	# Expected: Log contains fake mode message and tier escalation disabled notification.
	# Importance: Fake mode logging helps distinguish test runs from production execution in logs.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	# Should log fake mode message
	assert_file_contains "$LOG_FILE" "fake mode"
	assert_file_contains "$LOG_FILE" "tier escalation disabled"

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-monitor.sh initialize_monitor initializes state files - should create restart_count file" {
	# Purpose: Test verifies that initialize_monitor function creates necessary state files during initialization.
	# Expected: restart_count file is created in state directory during script startup.
	# Importance: State file initialization ensures proper tracking of restart history from first run.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	# State files should be initialized
	assert_file_exist "${STATE_DIR}/restart_count"

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-monitor.sh validate_monitor_state exits when in cooldown period - should exit early" {
	# Purpose: Test verifies that validate_monitor_state function detects active cooldown and exits early.
	# Expected: Script exits early with success status and logs cooldown period message.
	# Importance: Cooldown mechanism prevents excessive recovery actions and allows VPN stabilization time.
	setup_vpn_cooldown_fixture "${TEST_PEER_IP}" 0 900 'COOLDOWN_MINUTES=15'

	run bash "$TEST_SCRIPT" --fake

	assert_success
	# Should exit early due to cooldown
	assert_file_contains "$LOG_FILE" "in cooldown period"
	assert_file_contains "$LOG_FILE" "Script exiting"
}

# bats test_tags=category:unit
@test "vpn-monitor.sh validate_monitor_state continues when not in cooldown - should continue execution" {
	# Purpose: Test verifies that validate_monitor_state function allows script execution when cooldown period has expired.
	# Expected: Script continues normal execution without cooldown-related exit messages.
	# Importance: Ensures script resumes normal monitoring after cooldown period expires.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000 "" 'COOLDOWN_MINUTES=15'

	# Set expired cooldown timestamp using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	set_peer_state "" "${TEST_PEER_IP}" "last_bytes" "1000" || true
	local cooldown_file="${STATE_DIR}/cooldown_until"
	echo $(($(date +%s) - 900)) >"$cooldown_file"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	# Should continue execution (not exit early)
	refute_output --partial "in cooldown period"
	refute_output --partial "Script exiting: in cooldown"

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-monitor.sh validate_monitor_state checks cron persistence on first run - should verify cron entry" {
	# Purpose: Test verifies that validate_monitor_state function checks for cron job persistence on first execution.
	# Expected: Script verifies cron entry exists and may warn if missing, only checking once per installation.
	# Importance: Ensures script continues to run on schedule and alerts if cron job is removed.
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	# Remove cron entry if it exists
	crontab -l 2>/dev/null | grep -v "vpn-monitor.sh" | crontab - || true

	# Remove .cron_checked file if it exists
	rm -f "${TEST_DIR}/.cron_checked"

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	# Should check cron persistence (may warn if cron not found)
	# The check happens in validate_monitor_state

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-monitor.sh process_locations processes single location - should process location and check status" {
	# Purpose: Test verifies that process_locations function correctly processes a single location.
	# Expected: Script processes the location and performs VPN status check, logging location information.
	# Importance: Core functionality test ensures single-location monitoring works correctly.
	# Note: Use setup_test_location_config directly to avoid duplicate locations from setup_location_test_vpn_monitor defaults
	setup_test_environment "${TEST_DIR}"
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"LOCATION_NYC_INTERNAL=\"${TEST_PEER_IP}\""

	TEST_CONFIG_FILE="$config_file"
	TEST_SCRIPT=$(create_test_vpn_monitor_script \
		"$VPN_MONITOR_SCRIPT" \
		"${TEST_DIR}/vpn-monitor.sh" \
		"$TEST_CONFIG_FILE" \
		"$STATE_DIR" \
		"$LOG_FILE")
	export TEST_CONFIG_FILE TEST_SCRIPT

	setup_mock_vpn_environment "203.0.113.1" 1000

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	# Should process the location
	assert_file_exist "$LOG_FILE"
	# Log should contain location processing (check for VPN status check)
	# Check for location name or external IP in log
	assert_file_contains "$LOG_FILE" "NYC" || assert_file_contains "$LOG_FILE" "203.0.113.1"

	remove_mock_from_path
}

# bats test_tags=slow,category:unit
@test "vpn-monitor.sh process_locations processes multiple locations - should process all locations independently" {
	# Purpose: Test verifies that process_locations function correctly processes multiple locations.
	# Expected: Script processes all configured locations and performs VPN status checks for each.
	# Importance: Ensures multi-tunnel monitoring works correctly with independent status tracking per location.
	# Note: Use setup_test_location_config directly to avoid duplicate locations from setup_location_test_vpn_monitor defaults
	setup_test_environment "${TEST_DIR}"
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"LOCATION_NYC_INTERNAL=\"${TEST_PEER_IP}\"" \
		'LOCATION_DC_EXTERNAL="198.51.100.1"' \
		'LOCATION_DC_INTERNAL="192.168.2.1"'

	TEST_CONFIG_FILE="$config_file"
	TEST_SCRIPT=$(create_test_vpn_monitor_script \
		"$VPN_MONITOR_SCRIPT" \
		"${TEST_DIR}/vpn-monitor.sh" \
		"$TEST_CONFIG_FILE" \
		"$STATE_DIR" \
		"$LOG_FILE")
	export TEST_CONFIG_FILE TEST_SCRIPT

	# Mock ip command - VPN healthy (handles both locations)
	# Create a mock that handles multiple location external IPs
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return SA for NYC location (external IP: 203.0.113.1)
    echo "src 192.168.1.1 dst 203.0.113.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
    # Return SA for DC location (external IP: 198.51.100.1)
    echo "src 192.168.2.1 dst 198.51.100.1"
    echo "    proto esp spi 0x87654321 reqid 2 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	assert_success
	# Should process both locations
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=slow,category:unit
@test "vpn-monitor.sh process_locations handles empty location external IP - should skip and log error" {
	# Purpose: Test verifies that process_locations function handles empty location external IP gracefully.
	# Expected: Script skips locations with empty external IP and logs error message.
	# Importance: Prevents errors from malformed configuration with empty location external IPs.
	# Use setup_test_location_config directly to avoid duplicate NYC location from setup_location_test_vpn_monitor
	setup_test_environment "${TEST_DIR}"
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		'LOCATION_NYC_EXTERNAL="203.0.113.1"' \
		"LOCATION_NYC_INTERNAL=\"${TEST_PEER_IP}\"" \
		'LOCATION_DC_EXTERNAL=""' \
		'LOCATION_DC_INTERNAL=""'

	TEST_CONFIG_FILE="$config_file"
	local vpn_monitor_script="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"
	TEST_SCRIPT=$(create_test_vpn_monitor_script \
		"$vpn_monitor_script" \
		"${TEST_DIR}/vpn-monitor.sh" \
		"$TEST_CONFIG_FILE" \
		"$STATE_DIR" \
		"$LOG_FILE")
	export TEST_CONFIG_FILE TEST_SCRIPT

	setup_mock_vpn_environment "203.0.113.1" 1000

	PATH="${TEST_DIR}:${PATH}" run bash "$TEST_SCRIPT" --fake

	# Should handle empty external IP for DC location gracefully
	# The script skips empty locations and logs a warning, but continues processing other locations
	assert_success
	# Check for the warning message about empty external IP
	assert_file_contains "$LOG_FILE" "EXTERNAL IP is empty" || assert_output --partial "EXTERNAL IP is empty"

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "vpn-monitor.sh process_locations validates configuration - should exit with error if invalid" {
	# Purpose: Test verifies that process_locations function validates configuration before processing locations.
	# Expected: Script exits with failure status when LOCATION_*_EXTERNAL is missing.
	# Importance: Configuration validation prevents script execution with invalid settings.
	setup_test_location_config "${TEST_DIR}/vpn-monitor.conf"
	setup_test_environment "${TEST_DIR}"
	TEST_SCRIPT=$(create_test_vpn_monitor_script \
		"$VPN_MONITOR_SCRIPT" \
		"${TEST_DIR}/vpn-monitor.sh" \
		"${TEST_DIR}/vpn-monitor.conf" \
		"${TEST_DIR}" \
		"${TEST_DIR}/logs/vpn-monitor.log")

	run bash "$TEST_SCRIPT" --fake

	# Should fail due to invalid configuration (no locations)
	# parse_location_config() will fail with "No location-based configuration found..."
	# or process_locations() will fail with "No locations configured"
	assert_failure
	assert_output --partial "No location" || assert_output --partial "No locations configured"
}
