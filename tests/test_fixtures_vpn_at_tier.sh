#!/usr/bin/env bats
#
# Tests for vpn_at_tier fixture
# Verifies that the fixture correctly sets up tier-specific scenarios

load test_helper
load fixtures/vpn_at_tier

# Path to the VPN monitor script (defined for consistency with other test files)
# shellcheck disable=SC2034
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# VPN_AT_TIER FIXTURE TESTS
# ============================================================================

# bats test_tags=category:unit,priority:low
@test "vpn_at_tier fixture: tier 1 sets failure_count=1 and thresholds" {
	# Purpose: Test verifies that vpn_at_tier fixture correctly sets up Tier 1 scenario
	# Expected: Failure count is 1, tier thresholds are set correctly
	# Importance: Ensures fixture works correctly for Tier 1 tests
	setup_vpn_at_tier_fixture 1 "192.168.1.1"

	# Verify state file has correct failure count
	ensure_state_functions_loaded
	local failure_count
	failure_count=$(get_peer_state "TEST" "192.168.1.1" "failure_count" "0" 2>/dev/null || echo "0")
	assert_equal "$failure_count" "1"

	# Verify config has tier thresholds
	assert_file_exist "$TEST_CONFIG_FILE"
	assert_file_contains "$TEST_CONFIG_FILE" "TIER1_THRESHOLD=1"
	assert_file_contains "$TEST_CONFIG_FILE" "TIER2_THRESHOLD=3"
	assert_file_contains "$TEST_CONFIG_FILE" "TIER3_THRESHOLD=5"

	# Verify VPN is down (mock returns empty)
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	# Should detect failure and log (Tier 1 action)
	assert_file_exist "$LOG_FILE"

	remove_mock_from_path
}

# bats test_tags=category:unit,priority:low
@test "vpn_at_tier fixture: tier 2 sets failure_count=3" {
	# Purpose: Test verifies that vpn_at_tier fixture correctly sets up Tier 2 scenario
	# Expected: Failure count is 3, tier thresholds are set correctly
	# Importance: Ensures fixture works correctly for Tier 2 tests
	setup_vpn_at_tier_fixture 2 "192.168.1.1" 'ENABLE_XFRM_RECOVERY=0'

	# Verify state file has correct failure count
	ensure_state_functions_loaded
	local failure_count
	failure_count=$(get_peer_state "TEST" "192.168.1.1" "failure_count" "0" 2>/dev/null || echo "0")
	assert_equal "$failure_count" "3"

	# Verify config has tier thresholds
	assert_file_exist "$TEST_CONFIG_FILE"
	assert_file_contains "$TEST_CONFIG_FILE" "TIER2_THRESHOLD=3"

	# Verify custom config was applied
	assert_file_contains "$TEST_CONFIG_FILE" "ENABLE_XFRM_RECOVERY=0"

	add_mock_to_path
	remove_mock_from_path
}

# bats test_tags=category:unit,priority:low
@test "vpn_at_tier fixture: tier 3 sets failure_count=5" {
	# Purpose: Test verifies that vpn_at_tier fixture correctly sets up Tier 3 scenario
	# Expected: Failure count is 5, tier thresholds are set correctly
	# Importance: Ensures fixture works correctly for Tier 3 tests
	setup_vpn_at_tier_fixture 3 "192.168.1.1" 'MAX_RESTARTS_PER_HOUR=10'

	# Verify state file has correct failure count
	ensure_state_functions_loaded
	local failure_count
	failure_count=$(get_peer_state "TEST" "192.168.1.1" "failure_count" "0" 2>/dev/null || echo "0")
	assert_equal "$failure_count" "5"

	# Verify config has tier thresholds
	assert_file_exist "$TEST_CONFIG_FILE"
	assert_file_contains "$TEST_CONFIG_FILE" "TIER3_THRESHOLD=5"

	# Verify custom config was applied
	assert_file_contains "$TEST_CONFIG_FILE" "MAX_RESTARTS_PER_HOUR=10"

	add_mock_to_path
	remove_mock_from_path
}

# bats test_tags=category:unit,priority:low
@test "vpn_at_tier fixture: invalid tier number returns error" {
	# Purpose: Test verifies that vpn_at_tier fixture handles invalid tier numbers
	# Expected: Fixture returns error for invalid tier number
	# Importance: Ensures fixture validates input correctly
	run setup_vpn_at_tier_fixture 4 "192.168.1.1"
	assert_failure
	assert_output --partial "Invalid tier number"
}
