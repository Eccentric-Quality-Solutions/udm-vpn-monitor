#!/usr/bin/env bats
#
# Tests for vpn_multi_location fixture
# Verifies that the fixture correctly sets up multi-location scenarios with
# per-location state (healthy, failing, idle) and optional system-wide flags.
#

load test_helper
load helpers/state
load fixtures/vpn_multi_location

# Path to the VPN monitor script (defined for consistency with other test files)
# shellcheck disable=SC2034
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# VPN_MULTI_LOCATION FIXTURE TESTS
# ============================================================================

# bats test_tags=category:unit,priority:low
@test "vpn_multi_location fixture: default two locations - LOC1 healthy, LOC2 failing" {
	# Purpose: Test verifies fixture sets up LOC1 healthy and LOC2 failing by default
	# Expected: Config has LOC1 and LOC2, LOC1 has last_bytes/spi, LOC2 has failure_count; mock returns SA only for LOC1
	# Importance: Ensures reusable multi-location fixture works for independent failure tracking
	setup_vpn_multi_location_fixture || fail "Fixture setup failed"

	assert_file_exist "$TEST_CONFIG_FILE"
	assert_file_contains "$TEST_CONFIG_FILE" "LOCATION_LOC1_EXTERNAL"
	assert_file_contains "$TEST_CONFIG_FILE" "LOCATION_LOC2_EXTERNAL"

	ensure_state_functions_loaded
	local loc1_bytes
	loc1_bytes=$(get_peer_state "LOC1" "${TEST_PEER_IP}" "last_bytes" "0" 2>/dev/null || echo "0")
	assert [ "$loc1_bytes" -gt 0 ]
	local loc2_fail
	loc2_fail=$(get_peer_state "LOC2" "192.168.1.2" "failure_count" "0" 2>/dev/null || echo "0")
	assert_equal "$loc2_fail" "2"

	run bash "$TEST_SCRIPT" --fake
	# Script may exit 0 (if only logging) or 1 (warnings from failing location)
	assert_file_exist "$LOG_FILE"
}

# bats test_tags=category:unit,priority:low
@test "vpn_multi_location fixture: three locations with custom names and states" {
	# Purpose: Test verifies fixture accepts three locations with healthy/failing/idle
	# Expected: NYC healthy, LA failing, DC idle; config and state match
	# Importance: Ensures fixture supports 2–3 named locations and all state types
	setup_vpn_multi_location_fixture \
		"NYC:${TEST_PEER_IP}:healthy" \
		"LA:192.168.1.2:failing" \
		"DC:192.168.1.3:idle" ||
		fail "Fixture setup failed"

	assert_file_exist "$TEST_CONFIG_FILE"
	assert_file_contains "$TEST_CONFIG_FILE" "LOCATION_NYC_EXTERNAL"
	assert_file_contains "$TEST_CONFIG_FILE" "LOCATION_LA_EXTERNAL"
	assert_file_contains "$TEST_CONFIG_FILE" "LOCATION_DC_EXTERNAL"

	ensure_state_functions_loaded
	local nyc_bytes
	nyc_bytes=$(get_peer_state "NYC" "${TEST_PEER_IP}" "last_bytes" "0" 2>/dev/null || echo "0")
	assert [ "$nyc_bytes" -gt 0 ]
	local la_fail
	la_fail=$(get_peer_state "LA" "192.168.1.2" "failure_count" "0" 2>/dev/null || echo "0")
	assert_equal "$la_fail" "2"
	local dc_bytes
	dc_bytes=$(get_peer_state "DC" "192.168.1.3" "last_bytes" "0" 2>/dev/null || echo "0")
	assert [ "$dc_bytes" -gt 0 ]

	assert [ -n "${VPN_MULTI_LOCATION_SPECS:-}" ]
}

# bats test_tags=category:unit,priority:low
@test "vpn_multi_location fixture: SYSTEM_WIDE_FAILURE_STATE writes state file" {
	# Purpose: Test verifies optional SYSTEM_WIDE_FAILURE_STATE=1 writes shared state file
	# Expected: ${STATE_DIR}/system_wide_failure_state exists and contains 1
	# Importance: Enables tests for system-wide failure with partial recovery
	setup_vpn_multi_location_fixture \
		"LOC1:${TEST_PEER_IP}:healthy" \
		"LOC2:192.168.1.2:failing" \
		"SYSTEM_WIDE_FAILURE_STATE=1" ||
		fail "Fixture setup failed"

	local sw_file="${STATE_DIR}/system_wide_failure_state"
	assert_file_exist "$sw_file"
	run cat "$sw_file"
	assert_success
	assert_output "1"
	# Should not be in config file
	run grep -F "SYSTEM_WIDE_FAILURE_STATE" "$TEST_CONFIG_FILE" 2>/dev/null || true
	assert_failure
}

# bats test_tags=category:unit,priority:low
@test "vpn_multi_location fixture: NETWORK_PARTITION_STATE writes state file" {
	# Purpose: Test verifies optional NETWORK_PARTITION_STATE=1 writes shared state file
	# Expected: ${STATE_DIR}/network_partition_state exists and contains 1
	setup_vpn_multi_location_fixture \
		"LOC1:${TEST_PEER_IP}:healthy" \
		"LOC2:192.168.1.2:failing" \
		"NETWORK_PARTITION_STATE=1" ||
		fail "Fixture setup failed"

	local np_file="${STATE_DIR}/network_partition_state"
	assert_file_exist "$np_file"
	run cat "$np_file"
	assert_success
	assert_output "1"
}

# bats test_tags=category:unit,priority:low
@test "vpn_multi_location fixture: invalid state in spec returns error" {
	# Purpose: Test verifies fixture validates state (healthy|failing|idle) and returns 1
	# Expected: setup_vpn_multi_location_fixture returns 1 and does not create config
	setup_test_environment "${TEST_DIR}"
	run setup_vpn_multi_location_fixture "LOC1:${TEST_PEER_IP}:badstate"
	assert_failure
	assert_output --partial "invalid state"
}
