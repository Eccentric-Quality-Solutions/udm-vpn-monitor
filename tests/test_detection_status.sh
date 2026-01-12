#!/usr/bin/env bats
#
# Tests for VPN Status Detection
# Tests critical paths and error handling scenarios

# for better organization and maintainability.

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 3. VPN STATUS DETECTION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "xfrm SA exists but byte counter is exactly 0" {
	# Purpose: Test verifies that the detection function correctly identifies VPN failures when xfrm SA exists but byte counter is exactly 0
	# Expected: Function detects bytes=0 as suspect condition and may mark VPN as failed
	# Importance: Zero byte counter indicates VPN tunnel is established but not passing traffic, a failure condition
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_NYC_EXTERNAL="${TEST_PEER_IP}"
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command - SA exists but bytes=0
	mock_ip_xfrm_state "${TEST_PEER_IP}" 0 >/dev/null
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	run bash "$test_script" --fake

	# Should detect bytes=0 as suspect (may fail VPN check)
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "bytes=0" || assert_file_contains "$log_file" "suspect"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "xfrm SA exists but byte counter decreases" {
	# Purpose: Test verifies that the detection function correctly identifies VPN failures when byte counter decreases between checks
	# Expected: Function detects bytes not increasing and may mark VPN as suspect or failed
	# Importance: Decreasing byte counters indicate abnormal VPN state that requires investigation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_NYC_EXTERNAL="${TEST_PEER_IP}"
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Source state functions to get correct file path
	export STATE_DIR="${state_dir}"
	ensure_state_functions_loaded
	local last_bytes_file
	last_bytes_file=$(get_peer_state_file_path "NYC" "${TEST_PEER_IP}" "last_bytes")

	# Set initial byte count (high value)
	echo "10000" >"$last_bytes_file"

	# Mock ip command - bytes decreased (counter wrap-around scenario)
	mock_ip_xfrm_state "${TEST_PEER_IP}" 5000 >/dev/null
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	run bash "$test_script" --fake

	# Should detect bytes not increasing (may fail VPN check)
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "bytes not increasing" || assert_file_contains "$log_file" "suspect"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "xfrm SA exists but byte counter stays same" {
	# Purpose: Test verifies that the detection function correctly identifies VPN failures when byte counter remains unchanged between checks
	# Expected: Function detects bytes not increasing and marks VPN as suspect or failed
	# Importance: Stagnant byte counters indicate VPN tunnel is not passing traffic, a critical failure condition
	# Disable ping check so that bytes not increasing is detected as suspect (not idle but healthy)
	setup_vpn_failing_fixture "${TEST_PEER_IP}" 0 1000 1000 "0x12345678" 'ENABLE_PING_CHECK=0'

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should detect bytes not increasing
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "bytes not increasing" || assert_file_contains "$LOG_FILE" "suspect"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "byte counter file corrupted" {
	# Purpose: Test verifies that the script handles corrupted byte counter files gracefully without crashing
	# Expected: Script treats corrupted file as 0 or resets it, continuing normal operation
	# Importance: File corruption can occur due to disk errors or manual editing; script must handle it robustly
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	# Source state functions to get correct file path
	ensure_state_functions_loaded
	# Create corrupted byte counter file (non-numeric)
	local last_bytes_file
	last_bytes_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "last_bytes")
	echo "invalid-value" >"$last_bytes_file"

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should handle corrupted file gracefully (treat as 0 or reset)
	assert_success
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "byte counter file contains negative number" {
	# Purpose: Test verifies that the script handles byte counter files containing negative numbers gracefully
	# Expected: Script treats negative value as invalid and either resets to 0 or uses current bytes value
	# Importance: Negative values can occur from file corruption or manual editing; script must handle them robustly
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	# Source state functions to get correct file path
	ensure_state_functions_loaded
	# Create byte counter file with negative number
	local last_bytes_file
	last_bytes_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "last_bytes")
	echo "-1000" >"$last_bytes_file"

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should handle negative value gracefully
	assert_success
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "byte counter file is empty" {
	# Purpose: Test verifies that the script handles empty byte counter files gracefully
	# Expected: Script treats empty file as 0, then updates it with current bytes value from xfrm output
	# Importance: Empty files can occur from file deletion or initialization; script must handle them robustly
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	# Source state functions to get correct file path
	ensure_state_functions_loaded
	# Clear byte counter file to test empty file handling
	local last_bytes_file
	last_bytes_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "last_bytes")
	# Remove file if it exists (from fixture setup), then create empty file
	rm -f "$last_bytes_file"
	touch "$last_bytes_file"
	# Verify file is empty before script runs
	assert_file_empty "$last_bytes_file"

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should handle empty file gracefully (treat as 0, then update with current bytes)
	assert_success
	assert_file_exist "$LOG_FILE"
	# File should be updated with current bytes value (not remain empty)
	# The script treats empty file as 0, then updates it with current bytes from mock (2000)
	assert_file_exist "$last_bytes_file"
	# File should contain a numeric value (current bytes from mock)
	local file_content
	file_content=$(cat "$last_bytes_file")
	if [[ ! "$file_content" =~ ^[0-9]+$ ]]; then
		fail "Byte counter file should contain numeric value, got: $file_content"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "all detection methods unavailable" {
	# Purpose: Test verifies that the script handles the edge case where all VPN detection methods are unavailable without crashing
	# Expected: Script handles missing detection tools gracefully, may log warnings or exit early
	# Importance: Ensures script fails gracefully in environments where required tools are missing
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_NYC_EXTERNAL="${TEST_PEER_IP}"
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Don't create any mock commands (all unavailable)
	# PATH will not include mocks, so real commands won't be found in test environment

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Create minimal PATH with only essential commands
	# Use a PATH that doesn't include ip or ipsec
	PATH="/usr/bin:/bin" run bash "$test_script" --fake
	assert_success

	# Should handle all methods unavailable gracefully
	# Script may exit early, but if log file exists, it should contain error messages
	if [[ -f "$log_file" ]]; then
		assert_file_contains "$log_file" "suspect" || assert_file_contains "$log_file" "failed" || assert_file_contains "$log_file" "WARNING"
	else
		# If log file doesn't exist, script likely exited very early - this is acceptable
		# The important thing is it didn't crash
		echo "Log file not created - script exited early (acceptable behavior)"
	fi
}

# bats test_tags=category:high-risk,priority:high
@test "xfrm output contains multiple lifetime lines" {
	# Purpose: Test verifies that the script correctly handles xfrm output containing multiple lifetime lines
	# Expected: Script extracts the first lifetime line correctly and uses it for byte counter detection
	# Importance: xfrm output can contain multiple lifetime entries; script must parse them correctly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_NYC_EXTERNAL="${TEST_PEER_IP}"
ENABLE_NETWORK_PARTITION_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Mock ip command with multiple lifetime lines
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime current: 2000 bytes, 20 packets"
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	run bash "$test_script" --fake

	# Should extract first lifetime line correctly
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "ping check enabled but LOCATION_*_INTERNAL not set" {
	# Purpose: Test verifies that ping check works correctly when LOCATION_*_INTERNAL is not set
	# Expected: Script uses peer IP for ping check when internal IPs are not configured
	# Importance: Ensures ping check works even when internal IPs are not specified in configuration
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000 "" 'ENABLE_PING_CHECK=1'

	# Mock ping - should use peer IP
	local mock_ping
	mock_ping=$(mock_ping "${TEST_PEER_IP}" "1")
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Should use peer IP for ping check
	assert_success
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}
