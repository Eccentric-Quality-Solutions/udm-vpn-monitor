#!/usr/bin/env bats
#
# Tests for vpn_idle fixture
# Verifies that the fixture correctly sets up idle tunnel scenarios

load test_helper
load fixtures/vpn_idle

# Path to the VPN monitor script (defined for consistency with other test files)
# shellcheck disable=SC2034
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# VPN_IDLE FIXTURE TESTS
# ============================================================================

# bats test_tags=category:unit,priority:low
@test "vpn_idle fixture: sets up idle tunnel with static bytes and ping success" {
	# Purpose: Test verifies that vpn_idle fixture correctly sets up idle tunnel scenario
	# Expected: Static bytes set, ping mock succeeds, ping check enabled in config
	# Importance: Ensures fixture works correctly for idle tunnel tests
	setup_vpn_idle_fixture "${TEST_PEER_IP}"

	# Verify state file has static bytes
	ensure_state_functions_loaded
	local last_bytes
	last_bytes=$(get_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "0" 2>/dev/null || echo "0")
	assert_equal "$last_bytes" "1000"

	# Verify config has ping check enabled
	assert_file_exist "$TEST_CONFIG_FILE"
	assert_file_contains "$TEST_CONFIG_FILE" "ENABLE_PING_CHECK=1"
	assert_file_contains "$TEST_CONFIG_FILE" "LOCATION_TEST_INTERNAL"

	# Verify ping mock exists and succeeds
	assert_file_exist "${TEST_DIR}/ping"
	run "${TEST_DIR}/ping" -c 1 "${TEST_PEER_IP}" 2>&1 || true
	assert_success

	# Verify mock ip returns static bytes
	assert_file_exist "${TEST_DIR}/ip"
	run "${TEST_DIR}/ip" xfrm state 2>&1 || true
	assert_success
	assert_output --partial "1000 bytes"

	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake

	# Should detect idle tunnel (ping succeeds, bytes not increasing)
	assert_success
	assert_file_exist "$LOG_FILE"
	# Should detect idle tunnel or ping check passed
	assert_file_contains "$LOG_FILE" "idle" || assert_file_contains "$LOG_FILE" "ping check passed" || assert_file_contains "$LOG_FILE" "healthy"

	remove_mock_from_path
}

# bats test_tags=category:unit,priority:low
@test "vpn_idle fixture: custom bytes and internal IP" {
	# Purpose: Test verifies that vpn_idle fixture accepts custom bytes and internal IP
	# Expected: Custom bytes and internal IP are set correctly
	# Importance: Ensures fixture accepts parameters correctly
	setup_vpn_idle_fixture "${TEST_PEER_IP}" 5000 "10.0.0.2"

	# Verify state file has custom bytes
	ensure_state_functions_loaded
	local last_bytes
	last_bytes=$(get_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "0" 2>/dev/null || echo "0")
	assert_equal "$last_bytes" "5000"

	# Verify config has custom internal IP
	assert_file_exist "$TEST_CONFIG_FILE"
	assert_file_contains "$TEST_CONFIG_FILE" "LOCATION_TEST_INTERNAL=\"10.0.0.2\""

	# Verify mock ip returns custom bytes
	assert_file_exist "${TEST_DIR}/ip"
	run "${TEST_DIR}/ip" xfrm state 2>&1 || true
	assert_success
	assert_output --partial "5000 bytes"

	add_mock_to_path
	remove_mock_from_path
}

# bats test_tags=category:unit,priority:low
@test "vpn_idle fixture: custom SPI value" {
	# Purpose: Test verifies that vpn_idle fixture accepts custom SPI value
	# Expected: Custom SPI is set correctly
	# Importance: Ensures fixture accepts SPI parameter correctly
	setup_vpn_idle_fixture "${TEST_PEER_IP}" 1000 "10.0.0.1" "0xABCD1234"

	# Verify state file has custom SPI
	ensure_state_functions_loaded
	local spi
	spi=$(get_peer_state "TEST" "${TEST_PEER_IP}" "spi" "" 2>/dev/null || echo "")
	assert_equal "$spi" "0xABCD1234"

	# Verify mock ip returns custom SPI
	assert_file_exist "${TEST_DIR}/ip"
	run "${TEST_DIR}/ip" xfrm state 2>&1 || true
	assert_success
	assert_output --partial "0xABCD1234"

	add_mock_to_path
	remove_mock_from_path
}

# bats test_tags=category:unit,priority:low
@test "vpn_idle fixture: accepts additional config variables" {
	# Purpose: Test verifies that vpn_idle fixture accepts additional config variables
	# Expected: Additional config variables are set correctly
	# Importance: Ensures fixture accepts extra config parameters correctly
	setup_vpn_idle_fixture "${TEST_PEER_IP}" 1000 "10.0.0.1" "0x12345678" 'TIER1_THRESHOLD=2' 'TIER2_THRESHOLD=4'

	# Verify config has additional variables
	assert_file_exist "$TEST_CONFIG_FILE"
	assert_file_contains "$TEST_CONFIG_FILE" "TIER1_THRESHOLD=2"
	assert_file_contains "$TEST_CONFIG_FILE" "TIER2_THRESHOLD=4"

	add_mock_to_path
	remove_mock_from_path
}
