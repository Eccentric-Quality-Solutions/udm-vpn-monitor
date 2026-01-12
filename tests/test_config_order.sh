#!/usr/bin/env bats
#
# Tests for Configuration Validation Order Dependencies
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# CONFIG VALIDATION ORDER DEPENDENCIES
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "relative validation - TIER2_THRESHOLD >= TIER1_THRESHOLD (TIER1 has default)" {
	# Purpose: Test verifies that relative validation works when TIER2 is validated before TIER1
	# Expected: TIER2 validation uses TIER1 default value (1) when TIER1 hasn't been validated yet
	# Importance: Ensures relative validation works correctly regardless of validation order
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
# TIER1_THRESHOLD not set - will use default (1)
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	# Should succeed - TIER2 (3) >= TIER1 default (1)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "relative validation - TIER2_THRESHOLD >= TIER1_THRESHOLD (TIER1 has config value)" {
	# Purpose: Test verifies that relative validation works when TIER1 is validated before TIER2
	# Expected: TIER2 validation uses TIER1 config value when TIER1 has been validated
	# Importance: Ensures relative validation uses validated values when available
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
TIER1_THRESHOLD=2
TIER2_THRESHOLD=4
TIER3_THRESHOLD=6
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	# Should succeed - TIER2 (4) >= TIER1 (2)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "relative validation - TIER3_THRESHOLD >= TIER2_THRESHOLD (TIER2 has default)" {
	# Purpose: Test verifies that relative validation works when TIER3 is validated before TIER2
	# Expected: TIER3 validation uses TIER2 default value (3) when TIER2 hasn't been validated yet
	# Importance: Ensures relative validation works correctly for nested dependencies
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
TIER1_THRESHOLD=1
TIER3_THRESHOLD=5
# TIER2_THRESHOLD not set - will use default (3)
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	# Should succeed - TIER3 (5) >= TIER2 default (3)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "relative validation - Referenced variable doesn't exist - Should use default" {
	# Purpose: Test verifies that relative validation uses default value when referenced variable doesn't exist
	# Expected: When TIER1_THRESHOLD doesn't exist, TIER2 validation uses TIER1 default (1)
	# Importance: Ensures relative validation gracefully handles missing referenced variables
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
TIER2_THRESHOLD=2
TIER3_THRESHOLD=4
# TIER1_THRESHOLD not set - will use default (1) for relative validation
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	# Should succeed - TIER2 (2) >= TIER1 default (1), TIER3 (4) >= TIER2 (2)
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "relative validation - Multiple relative validations in sequence" {
	# Purpose: Test verifies that multiple relative validations work correctly in sequence
	# Expected: TIER2 >= TIER1 and TIER3 >= TIER2 both validate correctly
	# Importance: Ensures complex dependency chains work correctly regardless of validation order
	local config_file="${TEST_DIR}/vpn-monitor.conf"
	cat >"$config_file" <<EOF
LOCATION_TEST_EXTERNAL="${TEST_PEER_IP}"
LOCATION_TEST_INTERNAL="${TEST_PEER_IP}"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
TIER3_THRESHOLD=5
EOF

	mkdir -p "${TEST_DIR}/logs"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local state_dir="${TEST_DIR}"

	local test_script
	test_script=$(create_test_vpn_monitor_script "$VPN_MONITOR_SCRIPT" "${TEST_DIR}/vpn-monitor.sh" "$config_file" "$state_dir" "$log_file")

	setup_mock_vpn_environment "${TEST_PEER_IP}" 1000
	add_mock_to_path

	run bash "$test_script" --fake

	# Should succeed - All relative validations pass:
	# TIER2 (3) >= TIER1 (1) ✓
	# TIER3 (5) >= TIER2 (3) ✓
	assert_success
	assert_file_exist "$log_file"

	remove_mock_from_path
}
