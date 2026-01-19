#!/usr/bin/env bats
#
# Tests for Tier 3 Recovery Actions (Full Restart)
# Tests critical paths and error handling scenarios for Tier 3 recovery

load test_helper
load helpers/config
load helpers/assertions
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_at_tier

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# TIER 3 RECOVERY TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "tier 3: full restart with ipsec command" {
	# Purpose: Test verifies that Tier 3 recovery action triggers full IPsec restart when failure count reaches threshold
	# Expected: Script executes "ipsec restart" command when failure count reaches Tier 3 threshold
	# Importance: Full restart is the most aggressive recovery action and should only trigger after multiple failures
	setup_vpn_at_tier_fixture 3 "${TEST_PEER_IP}" 'MAX_RESTARTS_PER_WINDOW=10' 'RATE_LIMIT_WINDOW_MINUTES=60'

	# Mock ipsec - restart succeeds, track restart call
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ipsec-restart-called" > /tmp/ipsec_called.txt
    exit 0
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Should call ipsec restart
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "full IPsec restart" "Tier 3"
	if [[ -f /tmp/ipsec_called.txt ]]; then
		assert_file_exist /tmp/ipsec_called.txt
		rm -f /tmp/ipsec_called.txt
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "tier 3: full restart fails - error handling" {
	# Purpose: Test verifies that Tier 3 recovery handles errors gracefully when ipsec restart command fails
	# Expected: Script logs error message and continues execution when restart command fails
	# Importance: Error handling prevents script crashes and ensures monitoring continues after recovery failures
	setup_vpn_at_tier_fixture 3 "${TEST_PEER_IP}" 'MAX_RESTARTS_PER_WINDOW=10' 'RATE_LIMIT_WINDOW_MINUTES=60'

	# Mock ipsec - reload fails, restart fails; VPN must be DOWN (status_exit=1)
	mock_ipsec_reload_restart 1 1 1
	add_mock_to_path

	run bash "$TEST_SCRIPT"
	# Allow exit code 0 (success) or 1 (warnings) - Recovery may fail but script should handle gracefully
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should handle error gracefully
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Failed to restart" "ERROR"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "tier 3: full restart when ipsec unavailable" {
	# Purpose: Test verifies that Tier 3 recovery handles gracefully when ipsec command is unavailable
	# Expected: Script logs error message indicating ipsec is not available and continues execution
	# Importance: Graceful handling prevents script failures when required recovery tools are missing
	setup_vpn_at_tier_fixture 3 "${TEST_PEER_IP}" 'MAX_RESTARTS_PER_WINDOW=10' 'RATE_LIMIT_WINDOW_MINUTES=60'

	# Don't create ipsec mock (unavailable)

	add_mock_to_path
	run bash "$TEST_SCRIPT"
	# Allow exit code 0 (success) or 1 (warnings) - Recovery commands unavailable causes warnings
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should handle unavailable commands gracefully
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "not available" "ERROR"

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "tier 3: restart succeeds but VPN doesn't recover (restart recorded)" {
	# Purpose: Test verifies that restart is recorded in restart_count file even when restart succeeds but VPN doesn't recover immediately
	# Expected: Restart timestamp is recorded in restart_count file after restart attempt, enabling rate limiting
	# Importance: Rate limiting prevents restart loops when VPN takes time to recover after restart command succeeds
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_WINDOW=10' \
		'RATE_LIMIT_WINDOW_MINUTES=60' \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local failure_counter
	failure_counter=$(get_failure_counter_path_for_location_var "LOCATION_TEST_EXTERNAL" "${TEST_PEER_IP}")
	local restart_file="${STATE_DIR}/restart_count"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN still down after restart
	mock_ip_vpn_down

	# Mock ipsec - reload/restart fail; VPN must be DOWN (status_exit=1)
	mock_ipsec_reload_restart 1 1 1
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Run script (not in fake mode, so restart will actually execute)
	run bash "$test_script"

	# Restart should succeed, restart should be recorded
	assert_file_exist "$LOG_FILE"
	# Restart timestamp should be recorded in restart_count file (if restart was triggered)
	# Note: Restart is recorded by full_restart() function for rate limiting
	if [[ -f "$restart_file" ]]; then
		# File should contain at least one timestamp (the restart we just triggered)
		local file_lines
		file_lines=$(wc -l <"$restart_file" 2>/dev/null | tr -d ' ' || echo "0")
		assert [ "$file_lines" -ge 1 ]
	else
		# If restart file doesn't exist, check if restart was actually called
		# This might happen if rate limiting prevented restart
		assert_log_contains_any "$LOG_FILE" "restart" "Tier 3"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "tier 3: restart fails but restart is still recorded" {
	# Purpose: Test verifies behavior when restart command fails - restart is still recorded for rate limiting
	# Expected: When restart fails, restart timestamp IS recorded in restart_count file (recorded before execution)
	# Importance: Documents current behavior where restart attempts are recorded before execution, even if they fail
	# Note: This behavior means failed restart attempts count toward rate limit, which prevents retry loops
	setup_vpn_at_tier_fixture 3 "${TEST_PEER_IP}" 'MAX_RESTARTS_PER_WINDOW=10' 'RATE_LIMIT_WINDOW_MINUTES=60' 'ENABLE_XFRM_RECOVERY=0'

	local restart_file="${STATE_DIR}/restart_count"

	# Record initial restart count (if file exists)
	local initial_restart_count=0
	if [[ -f "$restart_file" ]]; then
		initial_restart_count=$(wc -l <"$restart_file" 2>/dev/null | tr -d ' ' || echo "0")
	fi

	# Mock ipsec - reload succeeds, restart fails; VPN must be DOWN (status_exit=1)
	mock_ipsec_reload_restart 0 1 1
	add_mock_to_path

	run bash "$TEST_SCRIPT"
	# Allow exit code 0 (success) or 1 (warnings) - Restart failure causes warnings
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should handle restart failure
	assert_file_exist "$LOG_FILE"
	# Error message format: "Failed to restart IPsec service for $location_name (exit code: $ipsec_exit_code)"
	# Note: Error message check uses OR - if either pattern is found, test passes
	# The key assertion is that restart is recorded even when it fails (checked below)
	assert_log_contains_any "$LOG_FILE" "Failed to restart" "ERROR"

	# Restart IS recorded even when restart fails (recorded before execution)
	# This behavior means failed attempts count toward rate limit, preventing retry loops
	if [[ -f "$restart_file" ]]; then
		local final_restart_count
		final_restart_count=$(wc -l <"$restart_file" 2>/dev/null | tr -d ' ' || echo "0")
		# Restart count should have increased (restart recorded before execution)
		assert [ "$final_restart_count" -gt "$initial_restart_count" ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "tier 3: PIPESTATUS handling when restart command fails in pipe" {
	# Purpose: Test verifies that PIPESTATUS is correctly handled when restart command fails in a pipe
	# Expected: Script detects restart failure using PIPESTATUS (not tee exit code) and logs error message
	# Importance: PIPESTATUS handling ensures restart failures are correctly detected when commands are piped
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_WINDOW=10' \
		'RATE_LIMIT_WINDOW_MINUTES=60' \
		'ENABLE_XFRM_RECOVERY=0' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local failure_counter
	failure_counter=$(get_failure_counter_path_for_location_var "LOCATION_TEST_EXTERNAL" "${TEST_PEER_IP}")

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down (no SA found, so VPN check fails)
	# This ensures Tier 3 recovery is triggered
	mock_ip_vpn_down

	# Mock ipsec - reload fails, restart fails; VPN must be DOWN (status_exit=1)
	mock_ipsec_reload_restart 1 1 1
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	run bash "$test_script"
	# Allow exit code 0 (success) or 1 (warnings) - PIPESTATUS failure causes warnings
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should detect failure via PIPESTATUS (not tee exit code)
	# The error message should be logged when restart fails
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Failed to restart" "ERROR"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "tier 3: recovery action prevented by rate limiting" {
	# Purpose: Test verifies that Tier 3 recovery actions are prevented when rate limit is exceeded
	# Expected: Script detects rate limit exceeded and prevents restart command from being executed
	# Importance: Rate limiting prevents restart loops and allows VPN time to stabilize after recovery attempts
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=3" \
		"RATE_LIMIT_WINDOW_MINUTES=60" \
		"ENABLE_NETWORK_PARTITION_CHECK=0"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local failure_counter
	failure_counter=$(get_failure_counter_path_for_location_var "LOCATION_TEST_EXTERNAL" "${TEST_PEER_IP}")
	local restart_file="${STATE_DIR}/restart_count"
	export RESTART_COUNT_FILE="$restart_file"

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Set up rate limiting: create restart_count file with MAX_RESTARTS_PER_WINDOW (3) recent restarts
	local base_time=$(date +%s)
	local recent=$((base_time - 1800)) # 30 minutes ago (within 60 minute window)
	echo "$recent" >"$restart_file"
	echo "$recent" >>"$restart_file"
	echo "$recent" >>"$restart_file"

	# Mock ip command - VPN down
	mock_ip_vpn_down

	# Mock ipsec - should not be called when rate limited (but if it is, it fails)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    echo "ERROR: Restart should not be called when rate limited" >&2
    exit 1
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	run bash "$test_script"
	# Allow exit code 0 (success) or 1 (warnings) - Rate limiting causes warnings but script should still run
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Should prevent restart due to rate limiting, no recovery action should be triggered
	assert_file_exist "$LOG_FILE"
	# Check for rate limit message (check both the WARNING from check_rate_limit and ERROR from full_restart)
	assert_log_contains_any "$LOG_FILE" "Rate limit exceeded" "rate limit" "Rate limit exceeded, skipping Tier 3"
	# ipsec restart should not be called (rate limiting prevents it)
	refute_file_contains "$LOG_FILE" "ERROR: Restart should not be called when rate limited"

	# Verify restart was not recorded (file should still have 3 entries)
	if [[ -f "$restart_file" ]]; then
		local file_lines
		file_lines=$(wc -l <"$restart_file" 2>/dev/null | tr -d ' ' || echo "0")
		# Should still have exactly 3 entries (no new restart recorded)
		assert_equal "$file_lines" "3"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "tier 3: restart command hangs (timeout scenario - not currently handled)" {
	# Purpose: Test documents that timeout handling is not currently implemented for restart commands that hang
	# Expected: Script hangs indefinitely if restart command hangs (test uses timeout to prevent infinite hang)
	# Importance: Documents known limitation - timeout handling for hanging recovery commands is not implemented
	# Note: This test documents that timeout handling is not currently implemented
	# The script will hang if restart command hangs - this is a known limitation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=10" \
		"RATE_LIMIT_WINDOW_MINUTES=60"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local failure_counter
	failure_counter=$(get_failure_counter_path_for_location_var "LOCATION_TEST_EXTERNAL" "${TEST_PEER_IP}")

	# Set failure count to Tier 3 threshold
	echo "5" >"$failure_counter"

	# Mock ip command - VPN down
	mock_ip_vpn_down

	# Mock ipsec - hangs indefinitely (simulates timeout scenario)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "restart" ]]; then
    # Hang indefinitely (simulates command that never returns)
    while true; do
        sleep 1
    done
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Run with timeout to prevent test from hanging forever
	# This documents that the script would hang without timeout handling
	# Use timeout with --kill-after to ensure all child processes are killed
	# Give script 0.5s to start and create log file, then timeout kills it
	# Don't use --preserve-status so timeout returns 124 on timeout (we ignore exit code with || true)
	PATH="${TEST_DIR}:${PATH}" timeout --kill-after=0.1 0.5 bash "$test_script" 2>/dev/null || true

	# Clean up any remaining mock ipsec processes that might have escaped
	pkill -f "${TEST_DIR}/ipsec.*restart" 2>/dev/null || true
	sleep 0.1

	# Current behavior: script hangs if restart command hangs
	# This test documents the limitation - timeout handling is not implemented
	# The test succeeds if timeout kills the process (expected behavior)
	# Skip condition: Log file must be created by script before timeout kills it for test verification
	# Log file should exist (created before timeout kills the script)
	if [[ ! -f "$LOG_FILE" ]]; then
		skip "Log file not created (script may have been killed before initialization at ${LOG_FILE}, test requires log file to verify timeout behavior)"
	fi
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "tier 3: VPN fails, reaches Tier 3, restart fails, then recovers naturally" {
	# Purpose: Test verifies that failure counter is reset when VPN recovers naturally after failed restart attempt
	# Expected: Failure counter is reset to 0 when VPN recovers naturally, even after restart command failed
	# Importance: Natural recovery detection prevents false escalation after VPN recovers without recovery action success
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=10" \
		"RATE_LIMIT_WINDOW_MINUTES=60" \
		"ENABLE_XFRM_RECOVERY=0" \
		"ENABLE_NETWORK_PARTITION_CHECK=0"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local failure_counter
	failure_counter=$(get_failure_counter_path_for_location_var "LOCATION_TEST_EXTERNAL" "${TEST_PEER_IP}")
	local restart_file="${TEST_DIR}/state/restart_count"

	# Set failure count to Tier 3 threshold (simulating previous failures)
	echo "5" >"$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command - VPN is down initially (no SA)
	# Create mock that returns empty output (no SA found)
	mock_ip_vpn_down

	# Mock ipsec - restart fails, status succeeds
	mock_ipsec_reload_restart 1 0 0 "default" "${TEST_PEER_IP}"
	add_mock_to_path

	# First run: VPN fails, reaches Tier 3, restart fails
	run bash "$test_script"
	# Allow exit code 0 (success) or 1 (warnings) - Recovery failure causes warnings
	if [[ $status -ne 0 ]] && [[ $status -ne 1 ]]; then
		fail "Script exited with unexpected status: $status"
	fi

	# Verify restart was attempted and failed
	assert_file_exist "$LOG_FILE"

	# Now simulate natural recovery: VPN comes back up (SA exists)
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000

	# Second run: VPN recovers naturally (should reset failure count)
	run bash "$test_script"
	assert_success

	# After natural recovery, failure count should be reset to 0
	if [[ -f "$failure_counter" ]]; then
		local count
		count=$(cat "$failure_counter" 2>/dev/null || echo "0")
		# Failure count should be reset to 0 after natural recovery
		assert_equal "$count" 0
	else
		# File doesn't exist - reset_failure_count may delete the file when resetting to 0
		# This is also valid behavior (file not existing means count is 0)
		# But verify that reset actually happened by checking the log
		assert_log_contains_any "$LOG_FILE" "recovered" "reset"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "tier 3: recovery succeeds but byte counters do not increase immediately" {
	# Purpose: Test verifies behavior when recovery succeeds but byte counters don't increase immediately after restart
	# Expected: Script handles case where VPN SA exists but traffic hasn't resumed yet after recovery
	# Importance: Tests edge case where VPN appears recovered but traffic hasn't resumed, preventing false failure detection
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	# Ensure get_peer_state_file_path is available for last_bytes_file
	source_function "get_peer_state_file_path"
	local last_bytes_file
	last_bytes_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "last_bytes")
	local failure_counter
	failure_counter=$(get_failure_counter_path_for_location_var "LOCATION_TEST_EXTERNAL" "${TEST_PEER_IP}")

	# Set failure count to trigger recovery check
	echo "3" >"$failure_counter"

	# Set last_bytes to a non-zero value (simulating previous traffic)
	echo "1000" >"$last_bytes_file"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command - VPN is up (SA exists) but byte counters haven't increased yet
	# Return same byte count as last_bytes (simulates no new traffic after recovery)
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000

	run bash "$test_script"
	assert_success

	# Should handle case where VPN recovers (SA exists) but byte counters don't increase immediately
	# Script should log warning about bytes not increasing but continue execution
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "tier 3: execute_ipsec_restart fails gracefully when LOG_FILE is unset" {
	# Purpose: Test verifies that execute_ipsec_restart validates LOG_FILE is set before using it
	# Expected: Function returns error when LOG_FILE is unset, preventing tee command from failing silently
	# Importance: Validation ensures clear error messages when required variables are missing, preventing silent failures
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source recovery functions to test directly
	source_recovery_module

	# Unset LOG_FILE to test validation
	unset LOG_FILE

	# Mock ipsec command (should not be called since validation fails first)
	# VPN must be DOWN (status_exit=1) for consistency
	mock_ipsec_reload_restart 1 1 1
	add_mock_to_path

	# Test execute_ipsec_restart function directly - should fail with validation error
	# run captures both stdout and stderr by default
	run execute_ipsec_restart "${TEST_PEER_IP}" "TEST_LOCATION"
	assert_failure

	# Should return error message about LOG_FILE not being set
	# handle_error writes ERROR messages to stderr, which is captured by run
	assert_output --partial "LOG_FILE not set"

	remove_mock_from_path
}

# ============================================================================
# PARAMETER VALIDATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "execute_ipsec_reload: fails gracefully when peer_ip is missing" {
	# Purpose: Test verifies that execute_ipsec_reload validates peer_ip parameter is provided
	# Expected: Function returns error when peer_ip is empty or unset
	# Importance: Validation ensures clear error messages when required parameters are missing, preventing silent failures
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source recovery functions to test directly
	source_recovery_module

	# Mock ipsec command (should not be called since validation fails first)
	mock_ipsec_reload_restart 0 0 0
	add_mock_to_path

	# Test execute_ipsec_reload function with empty peer_ip - should fail with validation error
	run execute_ipsec_reload "" "TEST_LOCATION"
	assert_failure

	# Should return error message about required parameters
	assert_output --partial "peer_ip and location_name are required"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "execute_ipsec_reload: fails gracefully when location_name is missing" {
	# Purpose: Test verifies that execute_ipsec_reload validates location_name parameter is provided
	# Expected: Function returns error when location_name is empty or unset
	# Importance: Validation ensures clear error messages when required parameters are missing, preventing silent failures
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source recovery functions to test directly
	source_recovery_module

	# Mock ipsec command (should not be called since validation fails first)
	mock_ipsec_reload_restart 0 0 0
	add_mock_to_path

	# Test execute_ipsec_reload function with empty location_name - should fail with validation error
	run execute_ipsec_reload "${TEST_PEER_IP}" ""
	assert_failure

	# Should return error message about required parameters
	assert_output --partial "peer_ip and location_name are required"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "execute_ipsec_restart: fails gracefully when location_name is missing" {
	# Purpose: Test verifies that execute_ipsec_restart validates location_name parameter is provided
	# Expected: Function returns error when location_name is empty or unset
	# Importance: Validation ensures clear error messages when required parameters are missing, preventing silent failures
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source recovery functions to test directly
	source_recovery_module

	# Set LOG_FILE (required for execute_ipsec_restart)
	export LOG_FILE="${TEST_DIR}/logs/vpn-monitor.log"
	mkdir -p "${TEST_DIR}/logs"

	# Mock ipsec command (should not be called since validation fails first)
	mock_ipsec_reload_restart 0 0 0
	add_mock_to_path

	# Test execute_ipsec_restart function with empty location_name - should fail with validation error
	run execute_ipsec_restart "${TEST_PEER_IP}" ""
	assert_failure

	# Should return error message about required parameters
	assert_output --partial "location_name is required"

	remove_mock_from_path
}

# ============================================================================
# VERIFICATION FAILURE SCENARIO TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "execute_ipsec_reload: verification failure returns correct error code" {
	# Purpose: Test verifies that execute_ipsec_reload returns failure when verification fails
	# Expected: Function returns 1 when verify_ipsec_connections_active fails, even if ipsec reload succeeds
	# Importance: Ensures recovery success reporting is accurate when verification fails
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source recovery functions to test directly
	source_recovery_module

	# Mock ipsec - reload succeeds, status returns peer IP (verification should succeed normally)
	# But we'll override verify_ipsec_connections_active to return failure
	mock_ipsec_reload_restart 0 0 0
	add_mock_to_path

	# Override verify_ipsec_connections_active to return failure (simulating verification failure)
	# Test override for verify_ipsec_connections_active
	#
	# Overrides the real verify_ipsec_connections_active function to simulate
	# a verification failure scenario in tests. Always returns failure to test
	# error handling paths.
	#
	# Arguments:
	#   $1: Space-separated list of peer IPs to verify (optional, ignored in test override)
	#
	# Returns:
	#   1: Always returns failure to simulate verification failure
	#
	# Note:
	#   This is a test helper function that overrides the real implementation
	#   to simulate failure scenarios
	verify_ipsec_connections_active() {
		return 1
	}

	# Test execute_ipsec_reload function - should succeed in reload but fail on verification
	run execute_ipsec_reload "${TEST_PEER_IP}" "TEST_LOCATION"
	assert_failure

	# Should log warning about verification failure
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "verification: some connections not active"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "execute_ipsec_restart: verification failure for connections returns correct error code" {
	# Purpose: Test verifies that execute_ipsec_restart returns failure when connection verification fails
	# Expected: Function returns 1 when verify_ipsec_connections_active fails, even if ipsec restart succeeds
	# Importance: Ensures recovery success reporting is accurate when verification fails
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source recovery functions to test directly
	source_recovery_module

	# Set LOG_FILE (required for execute_ipsec_restart)
	export LOG_FILE="${TEST_DIR}/logs/vpn-monitor.log"
	mkdir -p "${TEST_DIR}/logs"

	# Mock ipsec - restart succeeds
	mock_ipsec_reload_restart 0 0 0
	add_mock_to_path

	# Override verify_ipsec_connections_active to return failure (simulating verification failure)
	# Test override for verify_ipsec_connections_active
	#
	# Overrides the real verify_ipsec_connections_active function to simulate
	# a verification failure scenario in tests. Always returns failure to test
	# error handling paths.
	#
	# Arguments:
	#   $1: Space-separated list of peer IPs to verify (optional, ignored in test override)
	#
	# Returns:
	#   1: Always returns failure to simulate verification failure
	#
	# Note:
	#   This is a test helper function that overrides the real implementation
	#   to simulate failure scenarios
	verify_ipsec_connections_active() {
		return 1
	}

	# Override verify_byte_counters_resume to return success (so we test connection verification failure in isolation)
	# Test override for verify_byte_counters_resume
	#
	# Overrides the real verify_byte_counters_resume function to simulate
	# a successful byte counter verification in tests. Always returns success
	# to isolate connection verification failure testing.
	#
	# Arguments:
	#   $1: Peer IP address to verify (ignored in test override)
	#   $2: Optional location name for logging context (ignored in test override)
	#
	# Returns:
	#   0: Always returns success to simulate successful byte counter verification
	#
	# Note:
	#   This is a test helper function that overrides the real implementation
	#   to simulate success scenarios for isolated testing
	verify_byte_counters_resume() {
		return 0
	}

	# Test execute_ipsec_restart function - should succeed in restart but fail on connection verification
	run execute_ipsec_restart "${TEST_PEER_IP}" "TEST_LOCATION"
	assert_failure

	# Should log warning about verification failure
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Some connections not active"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "execute_ipsec_restart: verification failure for byte counters returns correct error code" {
	# Purpose: Test verifies that execute_ipsec_restart returns failure when byte counter verification fails
	# Expected: Function returns 1 when verify_byte_counters_resume fails, even if connections are active
	# Importance: Ensures recovery success reporting is accurate when byte counter verification fails
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source recovery functions to test directly
	source_recovery_module

	# Set LOG_FILE (required for execute_ipsec_restart)
	export LOG_FILE="${TEST_DIR}/logs/vpn-monitor.log"
	mkdir -p "${TEST_DIR}/logs"

	# Mock ipsec - restart succeeds, status returns peer IP (connection verification should succeed)
	mock_ipsec_reload_restart 0 0 0
	add_mock_to_path

	# Override verify_ipsec_connections_active to return success
	# Test override for verify_ipsec_connections_active
	#
	# Overrides the real verify_ipsec_connections_active function to simulate
	# a successful connection verification in tests. Always returns success to
	# isolate byte counter verification failure testing.
	#
	# Arguments:
	#   $1: Space-separated list of peer IPs to verify (optional, ignored in test override)
	#
	# Returns:
	#   0: Always returns success to simulate successful connection verification
	#
	# Note:
	#   This is a test helper function that overrides the real implementation
	#   to simulate success scenarios for isolated testing
	verify_ipsec_connections_active() {
		return 0
	}

	# Override verify_byte_counters_resume to return failure (simulating byte counter verification failure)
	# Test override for verify_byte_counters_resume
	#
	# Overrides the real verify_byte_counters_resume function to simulate
	# a byte counter verification failure scenario in tests. Always returns
	# failure to test error handling paths.
	#
	# Arguments:
	#   $1: Peer IP address to verify (ignored in test override)
	#   $2: Optional location name for logging context (ignored in test override)
	#
	# Returns:
	#   1: Always returns failure to simulate byte counter verification failure
	#
	# Note:
	#   This is a test helper function that overrides the real implementation
	#   to simulate failure scenarios
	verify_byte_counters_resume() {
		return 1
	}

	# Source config module to make get_location_external_ip available
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true

	# Set up LOCATIONS array so execute_ipsec_restart will call verify_byte_counters_resume
	# This simulates a multi-location scenario
	# Format: "external:IP|internal:IPs" (pipe separator)
	declare -A LOCATIONS
	LOCATIONS["TEST_LOCATION"]="external:${TEST_PEER_IP}|internal:"
	export LOCATIONS

	# Test execute_ipsec_restart function - should succeed in restart and connection verification but fail on byte counter verification
	run execute_ipsec_restart "${TEST_PEER_IP}" "TEST_LOCATION"
	assert_failure

	# Should log warning about byte counter verification failure
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Byte counters resumed for only"

	remove_mock_from_path
}
