#!/usr/bin/env bats
#
# Tests for Tier 1 Recovery Actions (Logging)
# Tests critical paths and error handling scenarios for Tier 1 recovery

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_cooldown
load fixtures/vpn_at_tier

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# TIER 1 RECOVERY TESTS
# ============================================================================

# Note: Tier 1 recovery primarily involves logging failures.
# Most Tier 1 behavior is tested implicitly in other test files.
# This file contains explicit Tier 1 tests if needed.

# bats test_tags=category:high-risk,priority:high
@test "tier 1: logging triggered on first failure" {
	# Purpose: Test verifies that Tier 1 recovery action triggers logging when failure count reaches threshold
	# Expected: Script logs failure when failure count reaches Tier 1 threshold
	# Importance: Tier 1 is the first level of recovery and should log failures for monitoring
	setup_vpn_at_tier_fixture 1 "${TEST_PEER_IP}"

	run bash "$TEST_SCRIPT"

	# Should log Tier 1 failure
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tier 1" || assert_file_contains "$LOG_FILE" "failure"

	remove_mock_from_path
}
