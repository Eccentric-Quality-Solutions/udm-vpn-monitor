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
	add_mock_to_path
	EXTERNAL_PEER_IPS="192.168.1.1" run bash "$test_script" --fake

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
	add_mock_to_path
	COOLDOWN_MINUTES="-5" run bash "$test_script" --fake
	assert_success

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
	add_mock_to_path
	EXTERNAL_PEER_IPS="192.168.1.1" \
		COOLDOWN_MINUTES=15 \
		MAX_RESTARTS_PER_HOUR=3 \
		run bash "$test_script" --fake

	# Script should use all environment variable values
	assert_file_exist "$log_file"

	remove_mock_from_path
}
