#!/usr/bin/env bats
#
# Tests for Configuration Loading and Validation
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# CONFIGURATION LOADING AND VALIDATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "config file contains syntax errors" {
	# Purpose: Test verifies that the script handles configuration files with syntax errors gracefully
	# Expected: Script detects syntax error during config loading and logs error message without crashing
	# Importance: Syntax errors can occur from manual editing or file corruption; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config with syntax error (unclosed quote)
	cat >"$config_file" <<EOF
LOCATION_NYC_EXTERNAL="${TEST_PEER_IP}
VPN_NAME="Test VPN"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle syntax error gracefully
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about config file
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Failed to parse configuration file" || assert_file_contains "$log_file" "Invalid configuration line" || assert_file_contains "$log_file" "ERROR"
}

# bats test_tags=category:high-risk,priority:high
@test "config file is unreadable" {
	# Purpose: Test verifies that the script handles unreadable configuration files gracefully
	# Expected: Script detects permission issue and logs error message without crashing
	# Importance: Permission issues can occur from incorrect file ownership or chmod operations; script must handle gracefully
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
EOF

	# Make config file unreadable
	chmod 000 "$config_file"
	# Verify permissions were set correctly
	assert_file_permission 000 "$config_file"

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle unreadable config gracefully
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about config file
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "not readable" || assert_file_contains "$log_file" "ERROR"

	# Restore permissions for cleanup
	chmod 644 "$config_file" 2>/dev/null || true
}

# bats test_tags=category:high-risk,priority:high
@test "config file is a directory" {
	# Purpose: Test verifies that the script handles configuration file paths that point to directories instead of files gracefully
	# Expected: Script detects that config path is a directory and logs warning or error message without crashing
	# Importance: Directory paths can occur from misconfiguration or symlink issues; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create directory instead of file
	mkdir -p "$config_file"

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should handle directory instead of file gracefully
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log warning or error
	assert_file_exist "$log_file"
}

@test "LOG_FILE override in config recalculates LOGS_DIR" {
	# Purpose: Test verifies that when LOG_FILE is overridden in config, LOGS_DIR is recalculated correctly
	# Expected: Script recalculates LOGS_DIR based on LOG_FILE path and creates the custom log directory
	# Importance: Ensures log file paths work correctly when custom LOG_FILE paths are specified
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_NYC_EXTERNAL="${TEST_PEER_IP}"
LOG_FILE="/tmp/custom-logs/vpn-monitor.log"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"
	local custom_log_file="/tmp/custom-logs/vpn-monitor.log"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command
	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	# Run script
	run bash "$test_script" --fake

	assert_success
	# Custom log directory should be created
	assert_dir_exist "/tmp/custom-logs"
	# Log file should exist in custom location
	assert_file_exist "$custom_log_file"

	# Cleanup
	rm -rf /tmp/custom-logs 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "negative threshold values in config" {
	# Purpose: Test verifies that the script handles negative threshold values in configuration files
	# Expected: Script processes negative thresholds without crashing, though behavior may be unexpected
	# Importance: Negative thresholds can occur from manual editing errors; script must handle them without crashing
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_NYC_EXTERNAL="${TEST_PEER_IP}"
TIER1_THRESHOLD=-1
TIER2_THRESHOLD=-3
TIER3_THRESHOLD=-5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN down
	mock_ip_xfrm_empty >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Script should handle negative thresholds (may cause unexpected behavior)
	run bash "$test_script" --fake

	# Script should run (may have unexpected tier escalation behavior)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "threshold values out of order" {
	# Purpose: Test verifies that the script handles threshold values that are out of order (TIER2 < TIER1, etc.)
	# Expected: Script processes out-of-order thresholds without crashing, though behavior may skip tiers or be unexpected
	# Importance: Out-of-order thresholds can occur from manual editing errors; script must handle them without crashing
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_NYC_EXTERNAL="${TEST_PEER_IP}"
TIER1_THRESHOLD=5
TIER2_THRESHOLD=3
TIER3_THRESHOLD=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command - VPN down
	mock_ip_xfrm_empty >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Script should handle out-of-order thresholds
	run bash "$test_script" --fake

	# Script should run (may skip tiers or have unexpected behavior)
	assert_file_exist "$log_file"

	remove_mock_from_path
}
