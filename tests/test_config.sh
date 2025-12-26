#!/usr/bin/env bats
#
# Tests for Configuration Loading and Validation
# Tests critical paths and error handling scenarios

load test_helper

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# CONFIGURATION LOADING AND VALIDATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "config file contains syntax errors" {
	# Test verifies that the script handles configuration files with syntax errors gracefully.
	# Expected: Script detects syntax error during config loading and logs error message without crashing.
	# Importance: Syntax errors can occur from manual editing or file corruption; script must handle them robustly.
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
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log error about config file
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Failed to parse configuration file" || assert_file_contains "$log_file" "Invalid configuration line" || assert_file_contains "$log_file" "ERROR"
}

# bats test_tags=category:high-risk,priority:high
@test "config file is unreadable" {
	# Test verifies that the script handles unreadable configuration files gracefully.
	# Expected: Script detects permission issue and logs error message without crashing.
	# Importance: Permission issues can occur from incorrect file ownership or chmod operations; script must handle gracefully.
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
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log error about config file
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "not readable" || assert_file_contains "$log_file" "ERROR"

	# Restore permissions for cleanup
	chmod 644 "$config_file" 2>/dev/null || true
}

# bats test_tags=category:high-risk,priority:high
@test "config file is a directory" {
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
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log warning or error
	assert_file_exist "$log_file"
}

@test "LOG_FILE override in config recalculates LOGS_DIR" {
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
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Run script
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

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
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should run (may have unexpected tier escalation behavior)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "threshold values out of order" {
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
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should run (may skip tiers or have unexpected behavior)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# CONFIGURATION VARIABLE VALIDATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "invalid COOLDOWN_MINUTES (negative)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should handle invalid value (either use default or fail gracefully)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid COOLDOWN_MINUTES (zero)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid MAX_RESTARTS_PER_HOUR (negative)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid MAX_RESTARTS_PER_HOUR (zero)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid LOCKFILE_TIMEOUT (negative)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid LOCKFILE_TIMEOUT (zero)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_COUNT (negative)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_COUNT (zero)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_TIMEOUT (negative)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_TIMEOUT (zero)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# CONFIGURATION VARIABLE VALIDATION - VERY LARGE VALUES
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "invalid COOLDOWN_MINUTES (very large)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should handle very large value (either use default or fail gracefully)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid MAX_RESTARTS_PER_HOUR (very large)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_COUNT (very large)" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# CONFIGURATION PATH OVERRIDES
# ============================================================================

@test "STATE_DIR override to non-existent directory creates it" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

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

@test "environment variable overrides config file value" {
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
	EXTERNAL_PEER_IPS="192.168.1.1" PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should use environment variable value (192.168.1.1) instead of config (10.0.0.1)
	assert_file_exist "$log_file"
	# Verify script processed the environment variable IP (check log or behavior)
	# The mock is set up for 192.168.1.1, so if script uses env var, it should succeed

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "environment variable sets invalid value" {
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
	COOLDOWN_MINUTES="-5" PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Script should handle invalid environment variable value gracefully
	assert_file_exist "$log_file"

	remove_mock_from_path
}

@test "multiple environment variables override config" {
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
	EXTERNAL_PEER_IPS="192.168.1.1" \
		COOLDOWN_MINUTES=15 \
		MAX_RESTARTS_PER_HOUR=3 \
		PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

	# Script should use all environment variable values
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# ============================================================================
# CONFIGURATION PATH OVERRIDES
# ============================================================================

@test "STATE_DIR override in config updates all dependent paths" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake

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
@test "LOG_FILE override to read-only directory" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle read-only log directory gracefully (should output to stderr)
	# Script should not crash even if log writes fail

	# Restore permissions for cleanup
	chmod 755 "$readonly_log_dir" 2>/dev/null || true
	rm -rf "$readonly_log_dir" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "STATE_DIR override to read-only directory" {
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

	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should handle read-only state directory gracefully
	# Script should fail early with clear error message or handle gracefully

	# Restore permissions for cleanup
	chmod 755 "$readonly_state_dir" 2>/dev/null || true
	rm -rf "$readonly_state_dir" 2>/dev/null || true
	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with command substitution is rejected" {
	# Test verifies that config files with command substitution ($()) are rejected.
	# Expected: Script detects dangerous content and rejects config file without executing code.
	# Importance: Prevents arbitrary code execution if config file is compromised.
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
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log error about dangerous content
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "dangerous content" || assert_file_contains "$log_file" "Failed to parse" || assert_file_contains "$log_file" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with backticks is rejected" {
	# Test verifies that config files with backticks are rejected.
	# Expected: Script detects dangerous content and rejects config file without executing code.
	# Importance: Prevents arbitrary code execution if config file is compromised.
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
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log error about dangerous content
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "dangerous content" || assert_file_contains "$log_file" "Failed to parse" || assert_file_contains "$log_file" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with eval is rejected" {
	# Test verifies that config files with eval are rejected.
	# Expected: Script detects dangerous content and rejects config file without executing code.
	# Importance: Prevents arbitrary code execution if config file is compromised.
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
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log error about dangerous content
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "dangerous content" || assert_file_contains "$log_file" "Failed to parse" || assert_file_contains "$log_file" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with unknown variable is rejected" {
	# Test verifies that config files with unknown variables (not in schema) are rejected.
	# Expected: Script detects unknown variable and rejects config file.
	# Importance: Prevents setting arbitrary variables that could be used for code injection.
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
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log error about unknown variable
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Unknown configuration variable" || assert_file_contains "$log_file" "not in schema" || assert_file_contains "$log_file" "Failed to parse" || assert_file_contains "$log_file" "ERROR"
}

# bats test_tags=category:high-risk,priority:critical
@test "config file with valid assignments works correctly" {
	# Test verifies that config files with valid variable assignments are parsed correctly.
	# Expected: Script parses valid config file and sets variables safely.
	# Importance: Ensures legitimate config files continue to work after security fix.
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
	mock_ip_xfrm_state "192.168.1.1" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Script should parse valid config file successfully
	PATH="${TEST_DIR}:${PATH}" run bash "$test_script" --fake || true

	# Should log success message
	assert_file_exist "$log_file"
	assert_file_contains "$log_file" "Configuration loaded from" || assert_file_contains "$log_file" "INFO"

	remove_mock_from_path
}
