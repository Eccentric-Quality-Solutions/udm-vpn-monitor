#!/usr/bin/env bats
#
# Tests for System-Wide Failure Detection
# Tests critical paths for system-wide failure detection and coordinated recovery
#
# These tests address the requirements identified in docs/code-review-system-wide-failure.md:
# - System-wide failure detection (all fail, majority fail, individual failures, resolution)
# - Recovery coordination (coordinator attempts recovery, non-coordinator skips, coordinator cleared)
# - State management (state persistence, corrupted files, timestamp tracking)
# - Configuration (disable detection, threshold values, disable coordination)

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# SYSTEM-WIDE FAILURE DETECTION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "system-wide failure detection: all locations fail simultaneously → system-wide failure detected" {
	# Purpose: Test verifies that system-wide failure is detected when all locations fail simultaneously
	# Expected: System-wide failure detected when 100% of locations fail (default threshold)
	# Importance: Critical for detecting infrastructure-level issues affecting all VPNs
	local ip1="192.168.1.1"
	local ip2="192.168.1.2"
	local ip3="192.168.1.3"
	local peer_ips="${ip1} ${ip2} ${ip3}"

	# Set up test with 3 locations, all failing
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1' \
		'SYSTEM_WIDE_FAILURE_THRESHOLD=100' \
		'DEBUG=1'

	# Source required functions
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Set all locations to failed state (failure_count >= 1)
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$ip1" "failure_count" "5" || true
	set_peer_state "TEST2" "$ip2" "failure_count" "5" || true
	set_peer_state "TEST3" "$ip3" "failure_count" "5" || true

	# Mock ip command - no SAs (all VPNs down)
	mock_ip_xfrm_state "" "" >/dev/null
	# Mock ipsec to fail (prevent fallback from succeeding)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	# Run script
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify system-wide failure was detected
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "System-wide failure detected"
	assert_file_contains "$LOG_FILE" "3 of 3 locations failing"

	# Verify system-wide failure state was set
	local state_file="${STATE_DIR}/system_wide_failure_state"
	assert_file_exist "$state_file"
	local state_value
	state_value=$(cat "$state_file")
	assert_equal "$state_value" "1"

	# Verify timestamp was set
	local timestamp_file="${STATE_DIR}/system_wide_failure_timestamp"
	assert_file_exist "$timestamp_file"
	local timestamp
	timestamp=$(cat "$timestamp_file")
	assert [ "$timestamp" -gt 0 ]

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "system-wide failure detection: majority of locations fail → system-wide failure detected (threshold 80%)" {
	# Purpose: Test verifies that system-wide failure is detected when majority of locations fail (threshold < 100)
	# Expected: System-wide failure detected when 80% of locations fail (threshold = 80)
	# Importance: Allows detection of system-wide issues even if not all locations fail
	local ip1="192.168.1.1"
	local ip2="192.168.1.2"
	local ip3="192.168.1.3"
	local ip4="192.168.1.4"
	local ip5="192.168.1.5"
	local peer_ips="${ip1} ${ip2} ${ip3} ${ip4} ${ip5}"

	# Set up test with 5 locations, threshold 80% (4 out of 5 must fail)
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1' \
		'SYSTEM_WIDE_FAILURE_THRESHOLD=80'

	# Source required functions
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Set 4 out of 5 locations to failed state (80% = 4/5)
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$ip1" "failure_count" "5" || true
	set_peer_state "TEST2" "$ip2" "failure_count" "5" || true
	set_peer_state "TEST3" "$ip3" "failure_count" "5" || true
	set_peer_state "TEST4" "$ip4" "failure_count" "5" || true
	# TEST5 is healthy (no failure_count set)

	# Mock ip command - no SAs for failed locations
	mock_ip_xfrm_state "" "" >/dev/null
	# Mock ipsec to fail (prevent fallback from succeeding)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	# Run script
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify system-wide failure was detected (4/5 = 80% >= 80%)
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "System-wide failure detected"
	assert_file_contains "$LOG_FILE" "4 of 5 locations failing"

	# Verify system-wide failure state was set
	local state_file="${STATE_DIR}/system_wide_failure_state"
	assert_file_exist "$state_file"
	local state_value
	state_value=$(cat "$state_file")
	assert_equal "$state_value" "1"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "system-wide failure detection: individual failures → no system-wide failure detected" {
	# Purpose: Test verifies that individual location failures do not trigger system-wide failure detection
	# Expected: No system-wide failure detected when only 1 out of 3 locations fails (33% < 100% threshold)
	# Importance: Prevents false positives from individual location issues
	local ip1="192.168.1.1"
	local ip2="192.168.1.2"
	local ip3="192.168.1.3"
	local peer_ips="${ip1} ${ip2} ${ip3}"

	# Set up test with 3 locations, default threshold 100%
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1' \
		'SYSTEM_WIDE_FAILURE_THRESHOLD=100'

	# Source required functions
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Set only 1 location to failed state (1/3 = 33% < 100% threshold)
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$ip1" "failure_count" "5" || true
	# TEST2 and TEST3 are healthy

	# Mock ip command - no SAs for failed location
	mock_ip_xfrm_state "" "" >/dev/null
	# Mock ipsec to fail (prevent fallback from succeeding)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	# Run script
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify system-wide failure was NOT detected
	assert_file_exist "$LOG_FILE"
	refute_file_contains "$LOG_FILE" "System-wide failure detected"

	# Verify system-wide failure state was NOT set (or is 0)
	local state_file="${STATE_DIR}/system_wide_failure_state"
	if [[ -f "$state_file" ]]; then
		local state_value
		state_value=$(cat "$state_file")
		assert_equal "$state_value" "0"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "system-wide failure detection: system-wide failure resolved when failures drop below threshold" {
	# Purpose: Test verifies that system-wide failure is cleared when failures drop below threshold
	# Expected: System-wide failure state cleared when failures drop from 100% to 0%
	# Importance: Ensures system-wide failure state is properly cleared when issue is resolved
	local ip1="192.168.1.1"
	local ip2="192.168.1.2"
	local ip3="192.168.1.3"
	local peer_ips="${ip1} ${ip2} ${ip3}"

	# Set up test with 3 locations
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1' \
		'SYSTEM_WIDE_FAILURE_THRESHOLD=100'

	# Source required functions
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Set system-wide failure state (from previous detection)
	set_system_wide_failure_state 1
	local prev_timestamp
	prev_timestamp=$(get_unix_timestamp 2>/dev/null || echo "1000000")
	set_system_wide_failure_timestamp "$prev_timestamp"

	# All locations are now healthy (no failure_count)
	ensure_state_functions_loaded
	# No failure_count set for any location

	# Mock ip command - all VPNs healthy (SAs exist)
	mock_ip_xfrm_state "$ip1" "1000" >/dev/null
	# Mock ipsec to succeed
	mock_ipsec_status 0 >/dev/null
	add_mock_to_path

	# Run script
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify system-wide failure was resolved
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "System-wide failure resolved"

	# Verify system-wide failure state was cleared
	local state_file="${STATE_DIR}/system_wide_failure_state"
	if [[ -f "$state_file" ]]; then
		local state_value
		state_value=$(cat "$state_file")
		assert_equal "$state_value" "0"
	fi

	# Verify coordinator was cleared
	local coordinator_file="${STATE_DIR}/system_wide_failure_coordinator"
	assert_file_not_exist "$coordinator_file"

	remove_mock_from_path
}

# ============================================================================
# RECOVERY COORDINATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "recovery coordination: only coordinator location attempts recovery during system-wide failure" {
	# Purpose: Test verifies that only the coordinator location attempts recovery during system-wide failure
	# Expected: First location becomes coordinator and attempts recovery, other locations skip
	# Importance: Prevents recovery cascades and rate limiting during system-wide failures
	local ip1="192.168.1.1"
	local ip2="192.168.1.2"
	local ip3="192.168.1.3"
	local peer_ips="${ip1} ${ip2} ${ip3}"

	# Set up test with 3 locations, all failing, coordination enabled
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1' \
		'SYSTEM_WIDE_FAILURE_THRESHOLD=100' \
		'COORDINATE_SYSTEM_WIDE_RECOVERY=1'

	# Source required functions
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Set all locations to failed state (at tier 2 threshold to trigger recovery)
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$ip1" "failure_count" "5" || true
	set_peer_state "TEST2" "$ip2" "failure_count" "5" || true
	set_peer_state "TEST3" "$ip3" "failure_count" "5" || true

	# Set system-wide failure state (already detected)
	set_system_wide_failure_state 1

	# Mock ip command - no SAs (all VPNs down)
	mock_ip_xfrm_state "" "" >/dev/null
	# Mock ipsec to fail (prevent fallback from succeeding)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	# Run script
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify coordinator was set (first location to check becomes coordinator)
	local coordinator_file="${STATE_DIR}/system_wide_failure_coordinator"
	assert_file_exist "$coordinator_file"
	local coordinator
	coordinator=$(cat "$coordinator_file")
	# Coordinator should be one of the locations
	assert [ "$coordinator" == "TEST1" ] || [ "$coordinator" == "TEST2" ] || [ "$coordinator" == "TEST3" ]

	# Verify only coordinator attempted recovery (check logs for recovery attempts)
	assert_file_exist "$LOG_FILE"
	# Should have coordinator designation message
	assert_file_contains "$LOG_FILE" "designated as recovery coordinator"

	# Should have messages about skipping recovery for non-coordinator locations
	# (at least one location should skip)
	local skip_count
	skip_count=$(grep -c "Skipping recovery.*recovery coordinated by another location" "$LOG_FILE" || echo "0")
	assert [ "$skip_count" -ge 1 ]

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery coordination: non-coordinator locations skip recovery during system-wide failure" {
	# Purpose: Test verifies that non-coordinator locations skip recovery during system-wide failure
	# Expected: Non-coordinator locations log skip message and do not attempt recovery
	# Importance: Prevents recovery cascades when multiple locations detect system-wide failure
	local ip1="192.168.1.1"
	local ip2="192.168.1.2"
	local ip3="192.168.1.3"
	local peer_ips="${ip1} ${ip2} ${ip3}"

	# Set up test with 3 locations, all failing, coordination enabled
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1' \
		'SYSTEM_WIDE_FAILURE_THRESHOLD=100' \
		'COORDINATE_SYSTEM_WIDE_RECOVERY=1'

	# Source required functions
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Set all locations to failed state (at tier 2 threshold to trigger recovery)
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$ip1" "failure_count" "5" || true
	set_peer_state "TEST2" "$ip2" "failure_count" "5" || true
	set_peer_state "TEST3" "$ip3" "failure_count" "5" || true

	# Set system-wide failure state (already detected)
	set_system_wide_failure_state 1

	# Pre-set coordinator to TEST2 (so TEST1 and TEST3 should skip)
	local coordinator_file="${STATE_DIR}/system_wide_failure_coordinator"
	mkdir -p "$(dirname "$coordinator_file")"
	echo "TEST2" >"$coordinator_file"

	# Mock ip command - no SAs (all VPNs down)
	mock_ip_xfrm_state "" "" >/dev/null
	# Mock ipsec to fail (prevent fallback from succeeding)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	# Run script
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify non-coordinator locations skipped recovery
	assert_file_exist "$LOG_FILE"
	# TEST1 should skip (not coordinator)
	assert_file_contains "$LOG_FILE" "Skipping recovery for TEST1.*recovery coordinated by another location"
	# TEST3 should skip (not coordinator)
	assert_file_contains "$LOG_FILE" "Skipping recovery for TEST3.*recovery coordinated by another location"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery coordination: coordinator cleared when system-wide failure resolved" {
	# Purpose: Test verifies that coordinator is cleared when system-wide failure is resolved
	# Expected: Coordinator file is removed when system-wide failure state is cleared
	# Importance: Ensures coordinator is reset for next system-wide failure event
	local ip1="192.168.1.1"
	local ip2="192.168.1.2"
	local ip3="192.168.1.3"
	local peer_ips="${ip1} ${ip2} ${ip3}"

	# Set up test with 3 locations
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1' \
		'SYSTEM_WIDE_FAILURE_THRESHOLD=100' \
		'COORDINATE_SYSTEM_WIDE_RECOVERY=1'

	# Source required functions
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Set system-wide failure state (from previous detection)
	set_system_wide_failure_state 1

	# Set coordinator
	local coordinator_file="${STATE_DIR}/system_wide_failure_coordinator"
	mkdir -p "$(dirname "$coordinator_file")"
	echo "TEST1" >"$coordinator_file"

	# All locations are now healthy (no failure_count)
	ensure_state_functions_loaded
	# No failure_count set for any location

	# Mock ip command - all VPNs healthy (SAs exist)
	mock_ip_xfrm_state "$ip1" "1000" >/dev/null
	# Mock ipsec to succeed
	mock_ipsec_status 0 >/dev/null
	add_mock_to_path

	# Run script
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify coordinator was cleared
	assert_file_not_exist "$coordinator_file"

	# Verify system-wide failure was resolved
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "System-wide failure resolved"

	remove_mock_from_path
}

# ============================================================================
# STATE MANAGEMENT TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "state management: system-wide failure state persists across script runs" {
	# Purpose: Test verifies that system-wide failure state persists across script runs
	# Expected: State file retains system-wide failure state between script executions
	# Importance: Ensures system-wide failure state is maintained across monitoring cycles
	local ip1="192.168.1.1"
	local ip2="192.168.1.2"
	local ip3="192.168.1.3"
	local peer_ips="${ip1} ${ip2} ${ip3}"

	# Set up test with 3 locations
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1' \
		'SYSTEM_WIDE_FAILURE_THRESHOLD=100'

	# Source required functions
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# First run: All locations fail → system-wide failure detected
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$ip1" "failure_count" "5" || true
	set_peer_state "TEST2" "$ip2" "failure_count" "5" || true
	set_peer_state "TEST3" "$ip3" "failure_count" "5" || true

	mock_ip_xfrm_state "" "" >/dev/null
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify system-wide failure state was set
	local state_file="${STATE_DIR}/system_wide_failure_state"
	assert_file_exist "$state_file"
	local state_value
	state_value=$(cat "$state_file")
	assert_equal "$state_value" "1"

	# Second run: State should persist (locations still failing)
	# Clear log file to check for new detection message
	rm -f "$LOG_FILE"
	mkdir -p "$(dirname "$LOG_FILE")"

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify state still persists
	state_value=$(cat "$state_file")
	assert_equal "$state_value" "1"

	# Should not log "System-wide failure detected" again (already detected)
	# But should still have system-wide failure state
	refute_file_contains "$LOG_FILE" "System-wide failure detected"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "state management: corrupted state files are recovered" {
	# Purpose: Test verifies that corrupted system-wide failure state files are automatically recovered
	# Expected: Corrupted state file is backed up and reset to 0 (no failure)
	# Importance: Prevents invalid state from causing false positives or negatives
	setup_test_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1'

	# Source required functions
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Create corrupted state file (invalid value)
	local state_file="${STATE_DIR}/system_wide_failure_state"
	mkdir -p "$(dirname "$state_file")"
	echo "invalid" >"$state_file"

	# Get state (should recover corrupted file)
	local state_value
	state_value=$(get_system_wide_failure_state)

	# Verify state was recovered (should return 0)
	assert_equal "$state_value" "0"

	# Verify corrupted file was backed up (timestamped suffix e.g., .corrupted.<ts>)
	local backup_count
	backup_count=$(find "${STATE_DIR}" -name "system_wide_failure_state.corrupted.*" 2>/dev/null | wc -l)
	assert [ "$backup_count" -gt 0 ]

	# Verify state file now has valid value
	state_value=$(cat "$state_file")
	assert_equal "$state_value" "0"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "state management: timestamp tracking works correctly" {
	# Purpose: Test verifies that system-wide failure timestamp is tracked correctly
	# Expected: Timestamp is set when failure is detected and used when failure is resolved
	# Importance: Enables tracking of system-wide failure duration
	local ip1="192.168.1.1"
	local ip2="192.168.1.2"
	local ip3="192.168.1.3"
	local peer_ips="${ip1} ${ip2} ${ip3}"

	# Set up test with 3 locations
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1' \
		'SYSTEM_WIDE_FAILURE_THRESHOLD=100'

	# Source required functions
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Set all locations to failed state
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$ip1" "failure_count" "5" || true
	set_peer_state "TEST2" "$ip2" "failure_count" "5" || true
	set_peer_state "TEST3" "$ip3" "failure_count" "5" || true

	mock_ip_xfrm_state "" "" >/dev/null
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	# Run script - should detect system-wide failure and set timestamp
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify timestamp was set
	local timestamp_file="${STATE_DIR}/system_wide_failure_timestamp"
	assert_file_exist "$timestamp_file"
	local timestamp
	timestamp=$(cat "$timestamp_file")
	assert [ "$timestamp" -gt 0 ]

	# Verify timestamp is reasonable (within last minute)
	local current_time
	current_time=$(get_unix_timestamp 2>/dev/null || date +%s)
	local time_diff
	time_diff=$((current_time - timestamp))
	assert [ "$time_diff" -ge 0 ]
	assert [ "$time_diff" -lt 60 ]

	# Now resolve the failure
	# Clear failure counts
	set_peer_state "TEST1" "$ip1" "failure_count" "0" || true
	set_peer_state "TEST2" "$ip2" "failure_count" "0" || true
	set_peer_state "TEST3" "$ip3" "failure_count" "0" || true

	# Mock VPNs as healthy
	mock_ip_xfrm_state "$ip1" "1000" >/dev/null
	mock_ipsec_status 0 >/dev/null

	# Run script - should resolve system-wide failure and log duration
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify resolution message includes duration
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "System-wide failure resolved after"

	remove_mock_from_path
}

# ============================================================================
# CONFIGURATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "configuration: detection can be disabled via ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=0" {
	# Purpose: Test verifies that system-wide failure detection can be disabled via configuration
	# Expected: No system-wide failure detection when ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=0
	# Importance: Allows disabling feature if not needed
	local ip1="192.168.1.1"
	local ip2="192.168.1.2"
	local ip3="192.168.1.3"
	local peer_ips="${ip1} ${ip2} ${ip3}"

	# Set up test with detection disabled
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=0' \
		'SYSTEM_WIDE_FAILURE_THRESHOLD=100'

	# Source required functions
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Set all locations to failed state
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$ip1" "failure_count" "5" || true
	set_peer_state "TEST2" "$ip2" "failure_count" "5" || true
	set_peer_state "TEST3" "$ip3" "failure_count" "5" || true

	mock_ip_xfrm_state "" "" >/dev/null
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	# Run script
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify system-wide failure was NOT detected (detection disabled)
	assert_file_exist "$LOG_FILE"
	refute_file_contains "$LOG_FILE" "System-wide failure detected"

	# Verify system-wide failure state was NOT set
	local state_file="${STATE_DIR}/system_wide_failure_state"
	if [[ -f "$state_file" ]]; then
		local state_value
		state_value=$(cat "$state_file")
		assert_equal "$state_value" "0"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "configuration: threshold configuration works (50%, 80%, 100%)" {
	# Purpose: Test verifies that threshold configuration works for different percentage values
	# Expected: System-wide failure detected when threshold is met (50%, 80%, 100%)
	# Importance: Allows flexible configuration based on deployment needs
	local ip1="192.168.1.1"
	local ip2="192.168.1.2"
	local ip3="192.168.1.3"
	local ip4="192.168.1.4"
	local peer_ips="${ip1} ${ip2} ${ip3} ${ip4}"

	# Test 1: Threshold 50% (2 out of 4 must fail)
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1' \
		'SYSTEM_WIDE_FAILURE_THRESHOLD=50'

	# Source required functions
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Set 2 out of 4 locations to failed state (50% = 2/4)
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$ip1" "failure_count" "5" || true
	set_peer_state "TEST2" "$ip2" "failure_count" "5" || true

	mock_ip_xfrm_state "" "" >/dev/null
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify system-wide failure was detected (2/4 = 50% >= 50%)
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "System-wide failure detected"
	assert_file_contains "$LOG_FILE" "2 of 4 locations failing"

	# Clean up for next test
	remove_mock_from_path
	rm -f "${STATE_DIR}/system_wide_failure_state"
	rm -f "$LOG_FILE"

	# Test 2: Threshold 80% (3.2 out of 4 = 4 out of 4 must fail, rounded up)
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1' \
		'SYSTEM_WIDE_FAILURE_THRESHOLD=80'

	# Source required functions for Test 2
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Set 3 out of 4 locations to failed state (75% < 80%)
	# Explicitly set TEST4 to healthy (0) to ensure clean state
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$ip1" "failure_count" "5" || true
	set_peer_state "TEST2" "$ip2" "failure_count" "5" || true
	set_peer_state "TEST3" "$ip3" "failure_count" "5" || true
	set_peer_state "TEST4" "$ip4" "failure_count" "0" || true

	mock_ip_xfrm_state "" "" >/dev/null
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify system-wide failure was NOT detected (3/4 = 75% < 80%)
	refute_file_contains "$LOG_FILE" "System-wide failure detected"

	# Clean up
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "configuration: coordination can be disabled via COORDINATE_SYSTEM_WIDE_RECOVERY=0" {
	# Purpose: Test verifies that recovery coordination can be disabled via configuration
	# Expected: All locations attempt recovery when coordination is disabled, even during system-wide failure
	# Importance: Allows disabling coordination if not needed
	local ip1="192.168.1.1"
	local ip2="192.168.1.2"
	local ip3="192.168.1.3"
	local peer_ips="${ip1} ${ip2} ${ip3}"

	# Set up test with coordination disabled
	setup_test_vpn_monitor "$peer_ips" "${TEST_DIR}" \
		'ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1' \
		'SYSTEM_WIDE_FAILURE_THRESHOLD=100' \
		'COORDINATE_SYSTEM_WIDE_RECOVERY=0'

	# Source required functions
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" || true
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" || true
	# shellcheck source=../lib/detection.sh
	source "${BATS_TEST_DIRNAME}/../lib/detection.sh" || true

	# Set up state directory
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	mkdir -p "${TEST_DIR}/logs"

	# Set all locations to failed state (at tier 2 threshold to trigger recovery)
	ensure_state_functions_loaded
	set_peer_state "TEST1" "$ip1" "failure_count" "5" || true
	set_peer_state "TEST2" "$ip2" "failure_count" "5" || true
	set_peer_state "TEST3" "$ip3" "failure_count" "5" || true

	# Don't set system-wide failure state - let the script detect it naturally
	# This ensures the "System-wide failure detected" message is logged

	mock_ip_xfrm_state "" "" >/dev/null
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	# Run script
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify system-wide failure was detected
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "System-wide failure detected"

	# Verify NO coordinator was set (coordination disabled)
	local coordinator_file="${STATE_DIR}/system_wide_failure_coordinator"
	assert_file_not_exist "$coordinator_file"

	# Verify NO skip messages (all locations should attempt recovery)
	refute_file_contains "$LOG_FILE" "Skipping recovery.*recovery coordinated by another location"

	remove_mock_from_path
}
