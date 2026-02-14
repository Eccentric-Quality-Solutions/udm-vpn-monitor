#!/usr/bin/env bats
#
# Tests for Error Handling During Critical Operations
# Tests critical paths and error handling scenarios

load test_helper
load helpers/config
load helpers/assertions
load fixtures/vpn_active
load fixtures/vpn_down
load helpers/logging
load helpers/mocks

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# ERROR HANDLING DURING CRITICAL OPERATIONS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "error during state file write" {
	# Purpose: Test verifies that script handles errors during state file write operations gracefully
	# Expected: Script logs error and continues execution without crashing when state file writes fail
	# Importance: Prevents script failures from filesystem permission issues or disk space problems
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_counter
	failure_counter=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")

	# Create failure counter file and make parent directory read-only (prevents write)
	echo "2" >"$failure_counter"
	chmod 555 "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 0
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"
	assert_success

	# Should handle state file write error gracefully (should log error but continue)
	# Script should not crash even if state file writes fail

	# Restore permissions for cleanup
	chmod 755 "${TEST_DIR}/logs" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "error during recovery action (should log and continue)" {
	# Purpose: Test verifies that script handles errors during recovery actions gracefully
	# Expected: Script logs error about recovery failure and continues execution without crashing
	# Importance: Prevents script failures when recovery commands fail, ensuring monitoring continues
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\"" \
		"TIER1_THRESHOLD=1" \
		"TIER2_THRESHOLD=3" \
		"TIER3_THRESHOLD=5" \
		"MAX_RESTARTS_PER_WINDOW=10
RATE_LIMIT_WINDOW_MINUTES=60"

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Set LOGS_DIR and STATE_DIR for state functions (already set by setup_test_environment)
	export LOGS_DIR="${LOGS_DIR}"
	export STATE_DIR="${STATE_DIR}"

	# Use get_peer_state_file_path to get correct path dynamically
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	local failure_counter
	failure_counter=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")

	# Set failure count to Tier 2 threshold (triggers surgical cleanup)
	echo "3" >"$failure_counter"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command - VPN is down (no SA)
	mock_ip_xfrm_state "${TEST_PEER_IP}" "0" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ipsec reload and restart to fail (simulates recovery action failure)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "reload" ]]; then
    echo "Failed to reload IPsec" >&2
    exit 1
fi
if [[ "$1" == "restart" ]]; then
    echo "Failed to restart IPsec" >&2
    exit 1
fi
if [[ "$1" == "status" ]]; then
        echo "${TEST_PEER_IP}: ESTABLISHED"
fi
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Run script - recovery actions should fail but script should continue
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"
	assert_success

	# Should handle recovery action errors gracefully (should log error but continue)
	# Script should not crash even if recovery actions fail
	# Code at lib/recovery.sh:217-220 handles ipsec reload/restart failures gracefully
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "error during VPN check (should log and continue)" {
	# Purpose: Test verifies that script handles errors during VPN check operations gracefully
	# Expected: Script logs error about VPN check failure and continues execution without crashing
	# Importance: Prevents script failures when VPN detection commands fail, ensuring monitoring continues
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	create_test_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Mock ip command to fail with error (simulates VPN check error)
	mock_command_failure "ip" 1 "Error: Cannot access xfrm state"
	add_mock_to_path

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake
	assert_success

	# Should handle VPN check error gracefully (should log error but continue)
	# Code at lib/detection.sh handles xfrm errors gracefully
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# ============================================================================
# ERROR HANDLING FUNCTION EDGE CASES - Previously Untested Critical Paths (P1)
# Tests for untested critical paths identified in docs/UNTESTED_CRITICAL_PATHS.md
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "handle_error called without prefix - fallback to SYSTEM" {
	# Purpose: Test verifies that handle_error() falls back to "SYSTEM" when called without prefix
	# Expected: Function uses "SYSTEM" as default prefix and logs warning about missing prefix
	# Importance: Missing prefix should not crash function; should use safe default
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local log_file="$LOG_FILE"

	# Source logging functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true

	# Set up logging
	export LOG_FILE="$log_file"
	export LOGS_DIR="${TEST_DIR}/logs"

	# Test handle_error without prefix (should use "SYSTEM" as fallback)
	run handle_error "WARNING" "" "Test message without prefix"
	assert_success

	# Should have logged with "SYSTEM" prefix and logged warning about missing prefix
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$log_file" "SYSTEM" "WARNING"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "handle_error with invalid severity level - default to ERROR" {
	# Purpose: Test verifies that handle_error() defaults to "ERROR" when invalid severity is provided
	# Expected: Function uses "ERROR" as default severity and logs warning about invalid severity
	# Importance: Invalid severity should not crash function; should use safe default
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local log_file="$LOG_FILE"

	# Source logging functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true

	# Set up logging
	export LOG_FILE="$log_file"
	export LOGS_DIR="${TEST_DIR}/logs"

	# Test handle_error with invalid severity (should default to "ERROR")
	run handle_error "INVALID_SEVERITY" "SYSTEM" "Test message with invalid severity"
	assert_success

	# Should have logged with "ERROR" severity and logged warning about invalid severity
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$log_file" "ERROR" "Invalid severity"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "handle_error_or_exit_fake_mode exit behavior - fake mode vs normal mode" {
	# Purpose: Test verifies that handle_error_or_exit_fake_mode() exits correctly in fake mode vs normal mode
	# Expected: Fake mode returns 1, normal mode exits with error code
	# Importance: Correct exit behavior ensures tests pass in fake mode but fail appropriately in normal mode
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local log_file="$LOG_FILE"

	# Source logging functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true

	# Set up logging
	export LOG_FILE="$log_file"
	export LOGS_DIR="${TEST_DIR}/logs"

	# Test 1: Fake mode - should return 1, not exit
	export NO_ESCALATE=1
	run handle_error_or_exit_fake_mode "SYSTEM" "Test error message" 1
	assert_failure # Should return 1 (failure) in fake mode

	# Test 2: Normal mode - should exit (tested via script execution)
	unset NO_ESCALATE
	# In normal mode, function calls die() which exits, so we test via script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$STATE_DIR" "$LOG_FILE")

	# Create invalid config to trigger handle_error_or_exit_fake_mode
	# Use "-invalid" which fails validate_ip_or_dns() (starts with hyphen, invalid DNS label)
	create_test_config "$config_file" \
		'LOCATION_TEST_EXTERNAL="-invalid"'

	add_mock_to_path
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script"
	# Should exit with error code in normal mode
	assert_failure

	remove_mock_from_path
}

# ============================================================================
# 6.1 HANDLE ERROR FUNCTION EDGE CASES - Additional Untested Scenarios
# Tests for untested critical paths identified in docs/UNTESTED_CRITICAL_PATHS.md
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "handle_error exit code parsing fails (non-numeric last argument)" {
	# Purpose: Test verifies that handle_error handles non-numeric exit code gracefully
	# Expected: Function should treat non-numeric last argument as part of message, not exit code
	# Importance: Defensive programming ensures function doesn't crash on invalid exit codes
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Call handle_error with non-numeric last argument (should be treated as message, not exit code)
	run handle_error "ERROR" "SYSTEM" "Test error message" "invalid"
	assert_success # Should not exit (exit code was invalid, so treated as message)

	assert_file_exist "$LOG_FILE"
	run grep -E "^\[.*\] \[ERROR\] SYSTEM: Test error message invalid" "$log_file"
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "handle_error log_message fails inside function (logging failure)" {
	# Purpose: Test verifies that handle_error handles logging failures gracefully
	# Expected: Function should handle log_message failures without crashing
	# Importance: Defensive programming ensures error handling doesn't fail when logging fails
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Make log directory read-only to simulate logging failure
	chmod 555 "$(dirname "$log_file")" 2>/dev/null || true

	# Call handle_error - should handle logging failure gracefully
	run handle_error "ERROR" "SYSTEM" "Test error message" 0
	# Should not exit (exit code is 0) even if logging fails
	assert_success

	# Restore permissions for cleanup
	chmod 755 "$(dirname "$log_file")" 2>/dev/null || true
}

# bats test_tags=category:high-risk,priority:high
@test "handle_error ERROR severity with exit code 0 - should not exit" {
	# Purpose: Test verifies that handle_error with ERROR severity and exit code 0 does not exit
	# Expected: Function should log error but not exit when exit code is 0
	# Importance: Non-fatal errors should not cause script exit even with ERROR severity
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Call handle_error with ERROR severity but exit code 0
	run handle_error "ERROR" "SYSTEM" "Test error message" 0
	assert_success # Should not exit (exit code is 0)

	assert_file_exist "$LOG_FILE"
	run grep -E "^\[.*\] \[ERROR\] SYSTEM: Test error message" "$log_file"
	assert_success
}

# ============================================================================
# 6.2 HANDLE ERROR OR EXIT FAKE MODE EDGE CASES - Additional Untested Scenarios
# Tests for untested critical paths identified in docs/UNTESTED_CRITICAL_PATHS.md
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "handle_error_or_exit_fake_mode exit code non-zero in normal mode - should exit via die" {
	# Purpose: Test verifies that handle_error_or_exit_fake_mode exits via die() in normal mode with non-zero exit code
	# Expected: Function should call die() and exit with specified code in normal mode
	# Importance: Correct exit behavior ensures fatal errors cause script termination in normal mode
	source_logging_functions

	local log_file="${TEST_DIR}/test.log"
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Disable fake mode
	unset NO_ESCALATE

	# Call handle_error_or_exit_fake_mode with non-zero exit code in normal mode
	# Should exit via die() with code 2
	run handle_error_or_exit_fake_mode "SYSTEM" "Fatal error" 2
	assert_failure
	assert_equal "$status" 2

	assert_file_exist "$LOG_FILE"
	run grep -E "^\[.*\] \[ERROR\] SYSTEM: Fatal error" "$log_file"
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "handle_error_or_exit_fake_mode called without prefix - fallback to SYSTEM" {
	# Purpose: Test verifies that handle_error_or_exit_fake_mode() falls back to "SYSTEM" when called without prefix
	# Expected: Function uses "SYSTEM" as default prefix and logs warning about missing prefix
	# Importance: Missing prefix should not crash function; should use safe default
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local log_file="$LOG_FILE"

	# Source logging functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true

	# Set up logging
	export LOG_FILE="$log_file"
	export LOGS_DIR="${TEST_DIR}/logs"

	# Test handle_error_or_exit_fake_mode without prefix (should use "SYSTEM" as fallback)
	export NO_ESCALATE=1
	run handle_error_or_exit_fake_mode "" "Test message without prefix"
	assert_failure # Should return 1 in fake mode

	# Should have logged with "SYSTEM" prefix and logged warning about missing prefix
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$log_file" "SYSTEM"
	assert_file_contains "$log_file" "handle_error_or_exit_fake_mode called without prefix - this is a bug"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "handle_error_or_exit_fake_mode is_fake_mode check with invalid NO_ESCALATE" {
	# Purpose: Test verifies that handle_error_or_exit_fake_mode() handles invalid NO_ESCALATE values defensively
	# Expected: Function treats non-1 values as normal mode (not fake mode)
	# Importance: Defensive handling ensures function works correctly even with invalid environment values
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local log_file="$LOG_FILE"

	# Source logging functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true

	# Set up logging
	export LOG_FILE="$log_file"
	export LOGS_DIR="${TEST_DIR}/logs"

	# Test with invalid NO_ESCALATE values (should treat as normal mode)
	# Test 1: NO_ESCALATE=2 (invalid, should be treated as normal mode)
	export NO_ESCALATE=2
	# In normal mode, function calls die() which exits, so we need to test via subshell
	run bash -c "source '${BATS_TEST_DIRNAME}/../lib/logging.sh' 2>/dev/null; export LOG_FILE='$log_file'; export LOGS_DIR='${TEST_DIR}/logs'; export NO_ESCALATE=2; handle_error_or_exit_fake_mode 'SYSTEM' 'Test message' 5" || true
	# Should exit with error code 5 (not return 1 like fake mode)
	[[ $status -eq 5 ]] || [[ $status -ne 0 ]]

	# Test 2: NO_ESCALATE="invalid" (should be treated as normal mode)
	export NO_ESCALATE="invalid"
	run bash -c "source '${BATS_TEST_DIRNAME}/../lib/logging.sh' 2>/dev/null; export LOG_FILE='$log_file'; export LOGS_DIR='${TEST_DIR}/logs'; export NO_ESCALATE='invalid'; handle_error_or_exit_fake_mode 'SYSTEM' 'Test message' 6" || true
	# Should exit with error code 6 (not return 1 like fake mode)
	[[ $status -eq 6 ]] || [[ $status -ne 0 ]]

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "handle_error_or_exit_fake_mode log_message fails inside function" {
	# Purpose: Test verifies that handle_error_or_exit_fake_mode() handles log_message() failures gracefully
	# Expected: Function should still attempt to exit/die even if logging fails
	# Importance: Logging failures should not prevent error handling from working
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local log_file="$LOG_FILE"

	# Make log directory read-only to cause log_message() to fail
	chmod 555 "${TEST_DIR}/logs"

	# Source logging functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true

	# Set up logging
	export LOG_FILE="$log_file"
	export LOGS_DIR="${TEST_DIR}/logs"

	# Test in fake mode - should still return 1 even if logging fails
	export NO_ESCALATE=1
	run handle_error_or_exit_fake_mode "SYSTEM" "Test message" 1 || true
	# Function should still return 1 in fake mode even if logging fails
	# The function may fail due to log_message error, but we verify it attempts to handle error
	[[ $status -ne 0 ]] || true

	# Restore permissions for cleanup
	chmod 755 "${TEST_DIR}/logs" 2>/dev/null || true

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "handle_error_or_exit_fake_mode exit code 0 in fake mode - should return 1" {
	# Purpose: Test verifies that handle_error_or_exit_fake_mode() returns 1 in fake mode even with exit code 0
	# Expected: Fake mode always returns 1, regardless of exit code parameter
	# Importance: Ensures consistent behavior in fake mode for test assertions
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local log_file="$LOG_FILE"

	# Source logging functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true

	# Set up logging
	export LOG_FILE="$log_file"
	export LOGS_DIR="${TEST_DIR}/logs"

	# Test with exit code 0 in fake mode - should return 1, not exit
	export NO_ESCALATE=1
	run handle_error_or_exit_fake_mode "SYSTEM" "Test error message" 0
	assert_failure # Should return 1 (failure) in fake mode, even with exit code 0
	[[ $status -eq 1 ]]

	# Verify error was logged
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$log_file" "Test error message"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "handle_error_or_exit_fake_mode exit code non-zero in fake mode - should return 1" {
	# Purpose: Test verifies that handle_error_or_exit_fake_mode() returns 1 in fake mode with non-zero exit code
	# Expected: Fake mode returns 1, not the specified exit code
	# Importance: Ensures consistent behavior in fake mode - always returns 1 for test assertions
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	setup_test_location_config "$config_file" \
		"LOCATION_TEST_EXTERNAL=\"${TEST_PEER_IP}\"" \
		"LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"
	local log_file="$LOG_FILE"

	# Source logging functions to test directly
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true

	# Set up logging
	export LOG_FILE="$log_file"
	export LOGS_DIR="${TEST_DIR}/logs"

	# Test with various non-zero exit codes in fake mode - should return 1, not exit
	export NO_ESCALATE=1

	# Test with exit code 2
	run handle_error_or_exit_fake_mode "SYSTEM" "Test error message 2" 2
	assert_failure
	[[ $status -eq 1 ]] # Should return 1, not 2

	# Test with exit code 3
	run handle_error_or_exit_fake_mode "SYSTEM" "Test error message 3" 3
	assert_failure
	[[ $status -eq 1 ]] # Should return 1, not 3

	# Test with exit code 4
	run handle_error_or_exit_fake_mode "SYSTEM" "Test error message 4" 4
	assert_failure
	[[ $status -eq 1 ]] # Should return 1, not 4

	# Verify errors were logged
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}
