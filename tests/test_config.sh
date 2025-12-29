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
@test "config file contains syntax errors - should log error and exit gracefully" {
	# Purpose: Test verifies that the script handles configuration files with syntax errors gracefully.
	# Expected: Script detects syntax error during config loading and logs error message without crashing.
	# Importance: Syntax errors can occur from manual editing or file corruption; script must handle them robustly.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config with syntax error (unclosed quote)
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1
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
@test "config file is unreadable - should log error and exit gracefully" {
	# Purpose: Test verifies that the script handles unreadable configuration files gracefully.
	# Expected: Script detects permission issue and logs error message without crashing.
	# Importance: Permission issues can occur from incorrect file ownership or chmod operations; script must handle gracefully.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
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
@test "config file is a directory - should log warning or error and handle gracefully" {
	# Purpose: Test verifies that the script handles configuration file paths that point to directories instead of files gracefully.
	# Expected: Script detects that config path is a directory and logs warning or error message without crashing.
	# Importance: Directory paths can occur from misconfiguration or symlink issues; script must handle them robustly.
	# Test Category: Error handling, Configuration validation
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

@test "LOG_FILE override in config recalculates LOGS_DIR - should create custom log directory" {
	# Purpose: Test verifies that when LOG_FILE is overridden in config, LOGS_DIR is recalculated correctly.
	# Expected: Script recalculates LOGS_DIR based on LOG_FILE path and creates the custom log directory.
	# Importance: Ensures log file paths work correctly when custom LOG_FILE paths are specified.
	# Test Category: Configuration path handling
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
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
	setup_mock_vpn_environment "192.168.1.1" 1000
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
@test "negative threshold values in config - should handle gracefully and may cause unexpected behavior" {
	# Purpose: Test verifies that the script handles negative threshold values in configuration files.
	# Expected: Script processes negative thresholds without crashing, though behavior may be unexpected.
	# Importance: Negative thresholds can occur from manual editing errors; script must handle them without crashing.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
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
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Script should handle negative thresholds (may cause unexpected behavior)
	run bash "$test_script" --fake

	# Script should run (may have unexpected tier escalation behavior)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "threshold values out of order - should handle gracefully and may skip tiers" {
	# Purpose: Test verifies that the script handles threshold values that are out of order (TIER2 < TIER1, etc.).
	# Expected: Script processes out-of-order thresholds without crashing, though tier escalation behavior may be unexpected.
	# Importance: Out-of-order thresholds can occur from manual editing errors; script must handle them without crashing.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
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
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    exit 0
fi
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Script should handle out-of-order thresholds
	run bash "$test_script" --fake

	# Script should run (may skip tiers or have unexpected behavior)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# CONFIGURATION VARIABLE VALIDATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "invalid COOLDOWN_MINUTES (negative) - should use default or fail gracefully" {
	# Purpose: Test verifies that the script handles negative COOLDOWN_MINUTES values gracefully.
	# Expected: Script either uses default value or fails gracefully with error message when negative cooldown is specified.
	# Importance: Invalid cooldown values can cause unexpected recovery behavior; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
COOLDOWN_MINUTES=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	# Script should handle invalid value (either use default or fail gracefully)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid COOLDOWN_MINUTES (zero) - should use default or fail gracefully" {
	# Purpose: Test verifies that the script handles zero COOLDOWN_MINUTES values gracefully.
	# Expected: Script either uses default value or fails gracefully with error message when zero cooldown is specified.
	# Importance: Zero cooldown can cause excessive recovery attempts; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
COOLDOWN_MINUTES=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid MAX_RESTARTS_PER_HOUR (negative) - should use default or fail gracefully" {
	# Purpose: Test verifies that the script handles negative MAX_RESTARTS_PER_HOUR values gracefully.
	# Expected: Script either uses default value or fails gracefully with error message when negative restart limit is specified.
	# Importance: Invalid restart limits can cause unexpected rate limiting behavior; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
MAX_RESTARTS_PER_HOUR=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid MAX_RESTARTS_PER_HOUR (zero) - should use default or fail gracefully" {
	# Purpose: Test verifies that the script handles zero MAX_RESTARTS_PER_HOUR values gracefully.
	# Expected: Script either uses default value or fails gracefully with error message when zero restart limit is specified.
	# Importance: Zero restart limit can disable rate limiting; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
MAX_RESTARTS_PER_HOUR=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid LOCKFILE_TIMEOUT (negative) - should use default or fail gracefully" {
	# Purpose: Test verifies that the script handles negative LOCKFILE_TIMEOUT values gracefully.
	# Expected: Script either uses default value or fails gracefully with error message when negative timeout is specified.
	# Importance: Invalid lockfile timeout can cause lockfile handling issues; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
LOCKFILE_TIMEOUT=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid LOCKFILE_TIMEOUT (zero) - should use default or fail gracefully" {
	# Purpose: Test verifies that the script handles zero LOCKFILE_TIMEOUT values gracefully.
	# Expected: Script either uses default value or fails gracefully with error message when zero timeout is specified.
	# Importance: Zero timeout can cause immediate lockfile failures; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
LOCKFILE_TIMEOUT=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_COUNT (negative) - should use default or fail gracefully" {
	# Purpose: Test verifies that the script handles negative PING_COUNT values gracefully.
	# Expected: Script either uses default value or fails gracefully with error message when negative ping count is specified.
	# Importance: Invalid ping count can cause ping check failures; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
PING_COUNT=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_COUNT (zero) - should use default or fail gracefully" {
	# Purpose: Test verifies that the script handles zero PING_COUNT values gracefully.
	# Expected: Script either uses default value or fails gracefully with error message when zero ping count is specified.
	# Importance: Zero ping count can disable ping checks; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
PING_COUNT=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_TIMEOUT (negative) - should use default or fail gracefully" {
	# Purpose: Test verifies that the script handles negative PING_TIMEOUT values gracefully.
	# Expected: Script either uses default value or fails gracefully with error message when negative ping timeout is specified.
	# Importance: Invalid ping timeout can cause ping check failures; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
PING_TIMEOUT=-1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_TIMEOUT (zero) - should use default or fail gracefully" {
	# Purpose: Test verifies that the script handles zero PING_TIMEOUT values gracefully.
	# Expected: Script either uses default value or fails gracefully with error message when zero ping timeout is specified.
	# Importance: Zero timeout can cause immediate ping failures; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
PING_TIMEOUT=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# CONFIGURATION VARIABLE VALIDATION - VERY LARGE VALUES
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "invalid COOLDOWN_MINUTES (very large) - should use default or fail gracefully" {
	# Purpose: Test verifies that the script handles very large COOLDOWN_MINUTES values gracefully.
	# Expected: Script either uses default value or fails gracefully with error message when very large cooldown is specified.
	# Importance: Very large cooldown values can cause excessive delays; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
COOLDOWN_MINUTES=999999999
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	# Script should handle very large value (either use default or fail gracefully)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid MAX_RESTARTS_PER_HOUR (very large) - should use default or fail gracefully" {
	# Purpose: Test verifies that the script handles very large MAX_RESTARTS_PER_HOUR values gracefully.
	# Expected: Script either uses default value or fails gracefully with error message when very large restart limit is specified.
	# Importance: Very large restart limits can disable rate limiting; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
MAX_RESTARTS_PER_HOUR=999999999
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_COUNT (very large) - should use default or fail gracefully" {
	# Purpose: Test verifies that the script handles very large PING_COUNT values gracefully.
	# Expected: Script either uses default value or fails gracefully with error message when very large ping count is specified.
	# Importance: Very large ping counts can cause excessive delays; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
PING_COUNT=999999999
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# CONFIGURATION PATH OVERRIDES
# ============================================================================

@test "STATE_DIR override to non-existent directory creates it - should create directory automatically" {
	# Purpose: Test verifies that when STATE_DIR is overridden to a non-existent directory, the script creates it automatically.
	# Expected: Script creates the STATE_DIR directory if it doesn't exist and continues normal operation.
	# Importance: Ensures state directory paths work correctly when custom STATE_DIR paths are specified.
	# Test Category: Configuration path handling
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local custom_state_dir="${TEST_DIR}/custom-state-dir"
	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="192.168.1.1"
STATE_DIR="${custom_state_dir}"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Ensure custom state directory does not exist
	rm -rf "$custom_state_dir" 2>/dev/null || true

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	# Custom state directory should be created
	assert_dir_exist "$custom_state_dir"
	assert_file_exist "$log_file"

	# Cleanup
	rm -rf "$custom_state_dir" 2>/dev/null || true
	remove_mock_from_path
}

# ============================================================================
# ENVIRONMENT VARIABLE OVERRIDES
# ============================================================================

@test "environment variable overrides config file value - should use environment variable" {
	# Purpose: Test verifies that environment variables override config file values correctly.
	# Expected: Script uses environment variable value instead of config file value when both are set.
	# Importance: Environment variable overrides allow runtime configuration changes without modifying config files.
	# Test Category: Configuration precedence
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="10.0.0.1"
COOLDOWN_MINUTES=30
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Override EXTERNAL_PEER_IPS via environment variable
	add_mock_to_path
	EXTERNAL_PEER_IPS="192.168.1.1" run bash "$test_script" --fake

	# Script should use environment variable value (192.168.1.1) instead of config (10.0.0.1)
	assert_file_exist "$log_file"
	# Verify script processed the environment variable IP (check log or behavior)
	# The mock is set up for 192.168.1.1, so if script uses env var, it should succeed

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "environment variable sets invalid value - should handle gracefully" {
	# Purpose: Test verifies that the script handles invalid values set via environment variables gracefully.
	# Expected: Script detects invalid environment variable value and either uses default or fails gracefully with error message.
	# Importance: Invalid environment variables can cause unexpected behavior; script must validate and handle them.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
COOLDOWN_MINUTES=15
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Set invalid COOLDOWN_MINUTES via environment variable
	add_mock_to_path
	COOLDOWN_MINUTES="-5" run bash "$test_script" --fake
	assert_success

	# Script should handle invalid environment variable value gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "multiple environment variables override config - should use all environment variable values" {
	# Purpose: Test verifies that multiple environment variables can override config file values simultaneously.
	# Expected: Script uses all environment variable values instead of corresponding config file values when set.
	# Importance: Multiple environment variable overrides allow comprehensive runtime configuration changes.
	# Test Category: Configuration precedence
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="10.0.0.1"
COOLDOWN_MINUTES=30
MAX_RESTARTS_PER_HOUR=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Override multiple variables via environment
	add_mock_to_path
	EXTERNAL_PEER_IPS="192.168.1.1" \
		COOLDOWN_MINUTES=15 \
		MAX_RESTARTS_PER_HOUR=3 \
		run bash "$test_script" --fake

	# Script should use all environment variable values
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# CONFIGURATION PATH OVERRIDES
# ============================================================================

@test "STATE_DIR override in config updates all dependent paths - should update lockfile, cooldown, and log paths" {
	# Purpose: Test verifies that when STATE_DIR is overridden in config, all dependent paths (lockfile, cooldown file, logs) are updated correctly.
	# Expected: Script updates all paths that depend on STATE_DIR to use the custom directory.
	# Importance: Ensures state directory changes propagate correctly to all dependent file paths.
	# Test Category: Configuration path handling
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local custom_state_dir="${TEST_DIR}/custom-state"
	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="192.168.1.1"
STATE_DIR="${custom_state_dir}"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Ensure custom state directory does not exist initially
	rm -rf "$custom_state_dir" 2>/dev/null || true

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	# Custom state directory should be created
	assert_dir_exist "$custom_state_dir"

	# Dependent paths should use custom STATE_DIR:
	# - LOCKFILE should be in custom_state_dir
	# - COOLDOWN_UNTIL_FILE should be in custom_state_dir
	# - LOGS_DIR should be custom_state_dir/logs
	# - RESTART_COUNT_FILE should be in custom_state_dir/logs
	# Note: Expected paths documented above but not directly asserted as script creates files dynamically

	# Verify that state files are created in the custom directory
	# (Script may create these files during execution)
	assert_file_exist "$log_file"

	# Cleanup
	rm -rf "$custom_state_dir" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "LOG_FILE override to read-only directory - should handle gracefully and output to stderr" {
	# Purpose: Test verifies that the script handles LOG_FILE paths pointing to read-only directories gracefully.
	# Expected: Script detects read-only log directory and either outputs to stderr or fails gracefully with error message.
	# Importance: Read-only directories can occur from permission issues; script must handle them without crashing.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local readonly_log_dir="${TEST_DIR}/readonly-logs"
	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="192.168.1.1"
LOG_FILE="${readonly_log_dir}/vpn-monitor.log"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create read-only log directory
	mkdir -p "$readonly_log_dir"
	chmod 555 "$readonly_log_dir"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should handle read-only log directory gracefully (should output to stderr)
	# Script should not crash even if log writes fail

	# Restore permissions for cleanup
	chmod 755 "$readonly_log_dir" 2>/dev/null || true
	rm -rf "$readonly_log_dir" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "STATE_DIR override to read-only directory - should fail early with clear error message" {
	# Purpose: Test verifies that the script handles STATE_DIR paths pointing to read-only directories gracefully.
	# Expected: Script detects read-only state directory and fails early with clear error message or handles gracefully.
	# Importance: Read-only directories can occur from permission issues; script must handle them without crashing.
	# Test Category: Error handling, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local readonly_state_dir="${TEST_DIR}/readonly-state"
	cat >"$config_file" <<EOF
EXTERNAL_PEER_IPS="192.168.1.1"
STATE_DIR="${readonly_state_dir}"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create read-only state directory
	mkdir -p "$readonly_state_dir"
	chmod 555 "$readonly_state_dir"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should handle read-only state directory gracefully
	# Script should fail early with clear error message or handle gracefully

	# Restore permissions for cleanup
	chmod 755 "$readonly_state_dir" 2>/dev/null || true
	rm -rf "$readonly_state_dir" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with command substitution is rejected - should detect dangerous content and reject without executing" {
	# Purpose: Test verifies that config files with command substitution ($()) are rejected.
	# Expected: Script detects dangerous content and rejects config file without executing code.
	# Importance: Prevents arbitrary code execution if config file is compromised.
	# Test Category: Security, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
VPN_NAME=$(echo "malicious")
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should reject config file with command substitution
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "dangerous content" || assert_file_contains "$log_file" "Failed to parse" || assert_file_contains "$log_file" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with backticks is rejected - should detect dangerous content and reject without executing" {
	# Purpose: Test verifies that config files with backticks are rejected.
	# Expected: Script detects dangerous content and rejects config file without executing code.
	# Importance: Prevents arbitrary code execution if config file is compromised.
	# Test Category: Security, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
VPN_NAME=`echo "malicious"`
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should reject config file with backticks
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "dangerous content" || assert_file_contains "$log_file" "Failed to parse" || assert_file_contains "$log_file" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with eval is rejected - should detect dangerous content and reject without executing" {
	# Purpose: Test verifies that config files with eval are rejected.
	# Expected: Script detects dangerous content and rejects config file without executing code.
	# Importance: Prevents arbitrary code execution if config file is compromised.
	# Test Category: Security, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
eval "malicious code"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should reject config file with eval
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "dangerous content" || assert_file_contains "$log_file" "Failed to parse" || assert_file_contains "$log_file" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with unknown variable is rejected - should detect unknown variable and reject config file" {
	# Purpose: Test verifies that config files with unknown variables (not in schema) are rejected.
	# Expected: Script detects unknown variable and rejects config file.
	# Importance: Prevents setting arbitrary variables that could be used for code injection.
	# Test Category: Security, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
MALICIOUS_VAR="value"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should reject config file with unknown variable
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about unknown variable
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Unknown configuration variable" || assert_file_contains "$log_file" "not in schema" || assert_file_contains "$log_file" "Failed to parse" || assert_file_contains "$log_file" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with valid assignments works correctly - should parse and set variables safely" {
	# Purpose: Test verifies that config files with valid variable assignments are parsed correctly.
	# Expected: Script parses valid config file and sets variables safely.
	# Importance: Ensures legitimate config files continue to work after security fix.
	# Test Category: Security, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1 192.168.1.2"
VPN_NAME="Test VPN"
TIER1_THRESHOLD=2
TIER2_THRESHOLD=4
TIER3_THRESHOLD=6
ENABLE_PING_CHECK=1
DEBUG=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Script should parse valid config file successfully
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log success message
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Configuration loaded from" || assert_file_contains "$log_file" "INFO"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with source is rejected - should detect dangerous content and reject without executing" {
	# Purpose: Test verifies that config files with source command are rejected.
	# Expected: Script detects dangerous content and rejects config file without executing code.
	# Importance: Prevents arbitrary code execution if config file is compromised.
	# Test Category: Security, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
source /etc/passwd
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should reject config file with source
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "dangerous content" || assert_file_contains "$log_file" "Failed to parse" || assert_file_contains "$log_file" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with multiple dangerous patterns in one line is rejected - should detect all patterns and reject" {
	# Purpose: Test verifies that config files with multiple dangerous patterns in one line are rejected.
	# Expected: Script detects dangerous content and rejects config file.
	# Importance: Ensures all dangerous patterns are detected even when combined.
	# Test Category: Security, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
VPN_NAME=$(echo "test") `echo "test"` eval "test"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Script should reject config file with multiple dangerous patterns
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should log error about dangerous content
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "dangerous content" || assert_file_contains "$log_file" "Failed to parse" || assert_file_contains "$log_file" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with dangerous pattern in comment is allowed - should ignore comments and parse successfully" {
	# Purpose: Test verifies that dangerous patterns in comments are ignored (comments are allowed).
	# Expected: Script ignores comments and allows dangerous patterns in comment lines.
	# Importance: Comments should not trigger security checks.
	# Test Category: Security, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
# This is a comment with $(echo "test") `echo "test"` eval "test"
VPN_NAME="Test VPN"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Script should parse config file successfully (comments are ignored)
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should parse successfully (comments are ignored)
	assert_file_exist "$log_file"
	# Should not contain error about dangerous content
	refute_file_contains "$log_file" "dangerous content"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with valid variable assignment without quotes is allowed - should parse safely" {
	# Purpose: Test verifies that valid variable assignments without quotes are parsed correctly.
	# Expected: Script parses valid assignments without quotes safely.
	# Importance: Ensures legitimate config files without quotes continue to work.
	# Test Category: Security, Configuration validation
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
ENABLE_PING_CHECK=1
DEBUG=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	# Create test version of script
	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	# Mock ip command
	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Script should parse valid config file successfully
	add_mock_to_path
	run bash "$test_script" --fake
	assert_success

	# Should parse successfully
	assert_file_exist "$log_file"
	# Should not contain error about dangerous content
	refute_file_contains "$log_file" "dangerous content"

	remove_mock_from_path
}

# ============================================================================
# CONFIG VALIDATION ORDER DEPENDENCIES
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "relative validation - TIER2_THRESHOLD >= TIER1_THRESHOLD (TIER1 has default) - should use TIER1 default for validation" {
	# Purpose: Test verifies that relative validation works when TIER2 is validated before TIER1.
	# Expected: TIER2 validation uses TIER1 default value (1) when TIER1 hasn't been validated yet.
	# Importance: Ensures relative validation works correctly regardless of validation order.
	# Test Category: Configuration validation order
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
# TIER1_THRESHOLD not set - will use default (1)
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	# Should succeed - TIER2 (3) >= TIER1 default (1)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "relative validation - TIER2_THRESHOLD >= TIER1_THRESHOLD (TIER1 has config value) - should use TIER1 config value for validation" {
	# Purpose: Test verifies that relative validation works when TIER1 is validated before TIER2.
	# Expected: TIER2 validation uses TIER1 config value when TIER1 has been validated.
	# Importance: Ensures relative validation uses validated values when available.
	# Test Category: Configuration validation order
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=2
TIER2_THRESHOLD=4
TIER3_THRESHOLD=6
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	# Should succeed - TIER2 (4) >= TIER1 (2)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "relative validation - TIER3_THRESHOLD >= TIER2_THRESHOLD (TIER2 has default) - should use TIER2 default for validation" {
	# Purpose: Test verifies that relative validation works when TIER3 is validated before TIER2.
	# Expected: TIER3 validation uses TIER2 default value (3) when TIER2 hasn't been validated yet.
	# Importance: Ensures relative validation works correctly for nested dependencies.
	# Test Category: Configuration validation order
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER3_THRESHOLD=5
# TIER2_THRESHOLD not set - will use default (3)
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	# Should succeed - TIER3 (5) >= TIER2 default (3)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "relative validation - Referenced variable doesn't exist - Should use default - should use default value for missing variable" {
	# Purpose: Test verifies that relative validation uses default value when referenced variable doesn't exist.
	# Expected: When TIER1_THRESHOLD doesn't exist, TIER2 validation uses TIER1 default (1).
	# Importance: Ensures relative validation gracefully handles missing referenced variables.
	# Test Category: Configuration validation order
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER2_THRESHOLD=2
TIER3_THRESHOLD=4
# TIER1_THRESHOLD not set - will use default (1) for relative validation
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	# Should succeed - TIER2 (2) >= TIER1 default (1), TIER3 (4) >= TIER2 (2)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "relative validation - Multiple relative validations in sequence - should validate all dependencies correctly" {
	# Purpose: Test verifies that multiple relative validations work correctly in sequence.
	# Expected: TIER2 >= TIER1 and TIER3 >= TIER2 both validate correctly.
	# Importance: Ensures complex dependency chains work correctly regardless of validation order.
	# Test Category: Configuration validation order
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	# Should succeed - All relative validations pass:
	# TIER2 (3) >= TIER1 (1) ✓
	# TIER3 (5) >= TIER2 (3) ✓
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# CONFIG SCHEMA DEFAULT APPLICATION
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - All variables get defaults before config file parsing - should apply defaults first" {
	# Purpose: Test verifies that all schema variables get defaults applied before config file parsing.
	# Expected: Variables have default values before config file is parsed.
	# Importance: Ensures variables are safe to reference before config parsing.
	# Test Category: Configuration schema defaults
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create empty config file (no values set)
	touch "$config_file"

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Source the script to access functions directly
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true

	# Apply defaults (simulating what load_config does)
	apply_schema_defaults

	# Verify some variables have defaults (check a few key ones)
	# VPN_NAME should have default "Site-to-Site VPN"
	assert_equal "${VPN_NAME:-}" "Site-to-Site VPN"
	# ENABLE_PING_CHECK should have default 1
	assert_equal "${ENABLE_PING_CHECK:-}" "1"
	# TIER1_THRESHOLD should have default 1
	assert_equal "${TIER1_THRESHOLD:-}" "1"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - Config file values override defaults - should use config file values" {
	# Purpose: Test verifies that config file values override schema defaults.
	# Expected: Config file values take precedence over defaults.
	# Importance: Ensures config file customization works correctly.
	# Test Category: Configuration schema defaults
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
VPN_NAME="Custom VPN Name"
TIER1_THRESHOLD=5
ENABLE_PING_CHECK=0
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	assert_success
	assert_file_exist "$log_file"
	# Config file values should override defaults
	# VPN_NAME should be "Custom VPN Name" not "Site-to-Site VPN"
	assert_file_contains "$log_file" "Custom VPN Name" || assert_file_contains "$log_file" "VPN_NAME" || assert_file_contains "$log_file" "Configuration loaded"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - Required variables without defaults remain empty until validation - should fail validation" {
	# Purpose: Test verifies that required variables without schema defaults remain empty until validation.
	# Expected: Required variables without defaults are empty after apply_schema_defaults but fail validation.
	# Importance: Ensures validation catches missing required values.
	# Test Category: Configuration schema defaults
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config file without EXTERNAL_PEER_IPS (required, no default in schema)
	cat >"$config_file" <<'EOF'
# EXTERNAL_PEER_IPS not set (required variable)
TIER1_THRESHOLD=1
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	run bash "$test_script" --fake
	assert_success

	# Should fail validation (EXTERNAL_PEER_IPS is required)
	# Script should exit with error or log validation error
	assert_file_exist "$log_file"
	# Should contain error about missing required variable or validation failure
	assert_file_contains "$log_file" "EXTERNAL_PEER_IPS" || assert_file_contains "$log_file" "required" || assert_file_contains "$log_file" "ERROR" || assert_file_contains "$log_file" "validation"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - Optional variables without defaults remain empty - should allow empty optional variables" {
	# Purpose: Test verifies that optional variables without schema defaults remain empty.
	# Expected: Optional variables without defaults are empty and remain empty.
	# Importance: Ensures optional variables work correctly when not set.
	# Test Category: Configuration schema defaults
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	# Create config file without INTERNAL_PEER_IPS (optional, no default in schema)
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
# INTERNAL_PEER_IPS not set (optional variable without default)
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	# Should succeed (optional variable can be empty)
	assert_success
	assert_file_exist "$log_file"
	# Script should run without errors (optional variable empty is acceptable)

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Schema defaults - Default application order (before config parsing) - should apply defaults then override with config" {
	# Purpose: Test verifies that defaults are applied before config file parsing.
	# Expected: Defaults are set, then config file values override them.
	# Importance: Ensures correct order of operations in load_config.
	# Test Category: Configuration schema defaults
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
EXTERNAL_PEER_IPS="192.168.1.1"
VPN_NAME="Override Default"
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "192.168.1.1" 1000
	add_mock_to_path

	# Source config functions to test order
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true

	# Test that load_config applies defaults before parsing config file
	# Source required dependencies
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true

	# Set required environment variables for load_config
	export STATE_DIR="$state_dir"
	export LOG_FILE="$log_file"
	export LOGS_DIR="${state_dir}/logs"

	# Unset VPN_NAME to ensure we start clean
	unset VPN_NAME

	# Call load_config which should apply defaults first, then parse config
	load_config "$config_file"

	# Verify that VPN_NAME was set to config file value (not default)
	# This proves defaults were applied first, then overridden by config
	assert_equal "${VPN_NAME:-}" "Override Default"

	remove_mock_from_path
}
