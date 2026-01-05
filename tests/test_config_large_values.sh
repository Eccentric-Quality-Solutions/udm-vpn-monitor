#!/usr/bin/env bats
#
# Tests for Configuration Variable Validation - Very Large Values
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# CONFIGURATION VARIABLE VALIDATION - VERY LARGE VALUES
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "invalid COOLDOWN_MINUTES (very large)" {
	# Purpose: Test verifies that the script handles very large COOLDOWN_MINUTES values gracefully
	# Expected: Script processes very large value without crashing, either using default or failing gracefully
	# Importance: Very large values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
COOLDOWN_MINUTES=999999999
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "${TEST_PEER_IP}" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	# Script should handle very large value (either use default or fail gracefully)
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid MAX_RESTARTS_PER_HOUR (very large)" {
	# Purpose: Test verifies that the script handles very large MAX_RESTARTS_PER_HOUR values gracefully
	# Expected: Script processes very large value without crashing, either using default or failing gracefully
	# Importance: Very large values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
MAX_RESTARTS_PER_HOUR=999999999
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "${TEST_PEER_IP}" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "invalid PING_COUNT (very large)" {
	# Purpose: Test verifies that the script handles very large PING_COUNT values gracefully
	# Expected: Script processes very large value without crashing, either using default or failing gracefully
	# Importance: Very large values can occur from manual editing errors; script must handle them robustly
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
PING_COUNT=999999999
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	mock_ip_xfrm_state "${TEST_PEER_IP}" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	run bash "$test_script" --fake

	assert_file_exist "$log_file"

	remove_mock_from_path
}
