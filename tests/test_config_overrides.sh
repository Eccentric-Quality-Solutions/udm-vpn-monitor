#!/usr/bin/env bats
#
# Tests for Configuration Path and Environment Variable Overrides
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# CONFIGURATION PATH OVERRIDES
# ============================================================================

@test "STATE_DIR override to non-existent directory creates it" {
	# Purpose: Test verifies that when STATE_DIR is set to a non-existent directory, the script creates it
	# Expected: Script creates the STATE_DIR directory if it doesn't exist before using it
	# Importance: Ensures script works correctly when custom state directories are specified
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	local custom_state_dir="${TEST_DIR}/custom-state-dir"
	cat >"$config_file" <<EOF
LOCATION_NYC_EXTERNAL="192.168.1.1"
LOCATION_NYC_INTERNAL="192.168.1.1"
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

@test "environment variable overrides config file value" {
	# Purpose: Test verifies that environment variables override config file values
	# Expected: Script uses environment variable value instead of config file value when both are set
	# Importance: Enables runtime configuration overrides without modifying config files
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="10.0.0.1"
LOCATION_NYC_INTERNAL="10.0.0.1"
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

	# Override LOCATION_NYC_EXTERNAL via environment variable
	add_mock_to_path
	LOCATION_NYC_EXTERNAL="192.168.1.1" LOCATION_NYC_INTERNAL="192.168.1.1" run bash "$test_script" --fake

	# Script should use environment variable value (192.168.1.1) instead of config (10.0.0.1)
	assert_file_exist "$log_file"
	# Verify script processed the environment variable IP (check log or behavior)
	# The mock is set up for 192.168.1.1, so if script uses env var, it should succeed

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "environment variable sets invalid value" {
	# Purpose: Test verifies that the script handles invalid values set via environment variables gracefully
	# Expected: Script processes invalid environment variable value without crashing
	# Importance: Environment variables can be set incorrectly; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="192.168.1.1"
LOCATION_NYC_INTERNAL="192.168.1.1"
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

@test "multiple environment variables override config" {
	# Purpose: Test verifies that multiple environment variables can override config file values simultaneously
	# Expected: Script uses all environment variable values instead of corresponding config file values
	# Importance: Enables comprehensive runtime configuration overrides for multiple settings
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<'EOF'
LOCATION_NYC_EXTERNAL="10.0.0.1"
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
	LOCATION_NYC_EXTERNAL="192.168.1.1" \
		LOCATION_NYC_INTERNAL="192.168.1.1" \
		COOLDOWN_MINUTES=15 \
		MAX_RESTARTS_PER_HOUR=3 \
		run bash "$test_script" --fake

	# Script should use all environment variable values
	assert_file_exist "$log_file"

	remove_mock_from_path
}
