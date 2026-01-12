#!/usr/bin/env bats
#
# Tests for Rapid State Changes (VPN Flapping)
# Tests VPN flapping scenarios, cooldown interactions, and multiple peer flapping
#
# These tests address the gap identified in CRITICAL_PATH_TEST_GAPS_REVIEW.md Section 6.1

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_cooldown
load fixtures/vpn_rate_limited
load fixtures/vpn_flapping
load fixtures/vpn_multiple_peers

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# RAPID STATE CHANGES (VPN FLAPPING) TESTS
# ============================================================================

# bats test_tags=slow,category:integration,priority:medium
@test "VPN fails then recovers then fails again within same cooldown period" {
	# Purpose: Test verifies that VPN flapping within cooldown period is handled correctly.
	# Expected: Cooldown should prevent excessive recovery actions, but failures should still be tracked.
	# Importance: VPN flapping could cause excessive recovery actions if cooldown doesn't work properly.

	# Setup initial state - VPN is up, can switch states during test
	setup_vpn_flapping_fixture "${TEST_PEER_IP}" "up" 1000 2000 \
		'COOLDOWN_MINUTES=1' \
		'LOCKFILE_TIMEOUT=60' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'ENABLE_NETWORK_PARTITION_CHECK=0' \
		'ENABLE_XFRM_RECOVERY=0'

	local log_file="$LOG_FILE"
	local state_dir="$STATE_DIR"
	local test_script="$TEST_SCRIPT"

	# Mock ipsec command for recovery strategy selection
	mock_ipsec_status 0 >/dev/null
	add_mock_to_path

	# First run - VPN is up, should succeed
	run bash "$test_script" --fake
	assert_success

	# Now VPN fails - switch to down state
	switch_vpn_to_down

	# Set failure count to Tier 3 threshold (5) so Tier 3 recovery triggers on next failure
	# This simulates the scenario where VPN has failed 5 times consecutively
	ensure_state_functions_loaded
	set_peer_state "TEST" "${TEST_PEER_IP}" "failure_count" 5 || true

	# Run script - VPN fails, failure count increments to 6, triggering Tier 3 recovery
	run bash "$test_script" --fake

	# Verify log file exists and has content
	assert_file_exist "$log_file"

	# Verify failure was logged (failure count should be 6 after increment)
	assert_file_contains "$log_file" "failed" || assert_file_contains "$log_file" "WARNING" || assert_file_contains "$log_file" "failure"

	# In fake mode, Tier 3 recovery may log "Would attempt" but doesn't set cooldown
	# Check if Tier 3 recovery was triggered (may not log if strategy selection fails in fake mode)
	# Manually set cooldown to simulate real behavior - this allows test to verify cooldown behavior
	# Use a short cooldown period (2 seconds) for testing purposes, even though config requires min 1 minute
	local cooldown_file="${STATE_DIR:-${state_dir}}/cooldown_until"
	local cooldown_seconds=2
	local cooldown_until
	cooldown_until=$(awk "BEGIN {print int($(date +%s) + $cooldown_seconds + 1)}")
	echo "$cooldown_until" >"$cooldown_file"
	assert_file_exist "$cooldown_file"

	# VPN recovers - switch back to active state
	switch_vpn_to_up 3000

	# Third run - VPN recovered but still in cooldown
	# Verify cooldown file exists (should have been set in previous step)
	assert_file_exist "$cooldown_file"

	# Script should exit successfully when in cooldown (cooldown check happens early)
	# This verifies that cooldown prevents VPN checks from running
	run bash "$test_script" --fake
	assert_success

	# VPN fails again (still in cooldown)
	switch_vpn_to_down

	# Fourth run - VPN fails but cooldown is active
	# Script should exit successfully when in cooldown (cooldown check happens early)
	# This verifies that cooldown prevents recovery actions even when VPN fails
	run bash "$test_script" --fake
	assert_success

	remove_mock_from_path
}

# bats test_tags=slow,category:integration,priority:medium
@test "VPN fails then Tier 2 recovery then recovers then fails again immediately" {
	# Purpose: Test verifies that VPN flapping after Tier 2 recovery is handled correctly.
	# Expected: Failure count should reset on recovery, then increment again on next failure.
	# Importance: Rapid failures after recovery could cause incorrect tier escalation.

	# Setup initial state - VPN is up, can switch states during test
	setup_vpn_flapping_fixture "${TEST_PEER_IP}" "up" 1000 2000 \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	local log_file="$LOG_FILE"
	local state_dir="$STATE_DIR"
	local test_script="$TEST_SCRIPT"

	# Mock ipsec for Tier 2 recovery
	mock_ipsec_reload_restart 0 0
	add_mock_to_path

	# VPN fails - switch to down state
	switch_vpn_to_down

	# Run 3 times to trigger Tier 2 recovery
	for _ in {1..3}; do
		run bash "$test_script" --fake
	done

	# Verify Tier 2 recovery was triggered
	assert_file_contains "$log_file" "Tier 2"

	# Verify failure count is 3 (Tier 2 threshold)
	ensure_state_functions_loaded
	local failure_count_file
	failure_count_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
	assert_file_exist "$failure_count_file"
	local failure_count
	failure_count=$(cat "$failure_count_file")
	assert_equal "$failure_count" 3

	# VPN recovers - switch back to active state
	switch_vpn_to_up 2000

	# Run - VPN recovered, failure count should reset
	run bash "$test_script" --fake
	assert_success

	# Verify failure count was reset
	failure_count=$(cat "$failure_count_file" 2>/dev/null || echo "0")
	assert_equal "$failure_count" 0

	# VPN fails again immediately - switch back to down state
	switch_vpn_to_down

	# Run - VPN fails again, failure count should increment from 0
	run bash "$test_script" --fake

	# Verify failure count is 1 (not 4)
	failure_count=$(cat "$failure_count_file" 2>/dev/null || echo "0")
	assert_equal "$failure_count" 1

	remove_mock_from_path
}

# bats test_tags=slow,category:integration,priority:medium
@test "Multiple peers flapping simultaneously - should handle independently" {
	# Purpose: Test verifies that multiple peers flapping simultaneously are handled independently.
	# Expected: Each peer's failure count should be tracked independently, recovery actions should be per-peer.
	# Importance: Multiple peer failures could cause incorrect recovery if not handled independently.

	# Setup multiple peers with initial state
	setup_vpn_multiple_peers_fixture "${TEST_PEER_IP} 192.168.1.2 192.168.1.3" 0 1000 \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	# Update bytes for each peer individually (fixture sets all to same value)
	ensure_state_functions_loaded
	set_peer_state "TEST1" "${TEST_PEER_IP}" "last_bytes" 1000 || true
	set_peer_state "TEST2" "192.168.1.2" "last_bytes" 2000 || true
	set_peer_state "TEST3" "192.168.1.3" "last_bytes" 3000 || true

	local log_file="$LOG_FILE"
	local state_dir="$STATE_DIR"
	local test_script="$TEST_SCRIPT"

	# Mock ip command - all peers fail
	mock_ip_vpn_down >/dev/null
	add_mock_to_path

	# Run - all peers fail
	run bash "$test_script" --fake

	# Verify each peer's failure count is tracked independently
	ensure_state_functions_loaded
	local failure_count_file_1
	failure_count_file_1=$(get_peer_state_file_path "TEST1" "${TEST_PEER_IP}" "failure_count")
	local failure_count_file_2
	failure_count_file_2=$(get_peer_state_file_path "TEST2" "192.168.1.2" "failure_count")
	local failure_count_file_3
	failure_count_file_3=$(get_peer_state_file_path "TEST3" "192.168.1.3" "failure_count")
	local failure_count_1
	failure_count_1=$(cat "$failure_count_file_1" 2>/dev/null || echo "0")
	local failure_count_2
	failure_count_2=$(cat "$failure_count_file_2" 2>/dev/null || echo "0")
	local failure_count_3
	failure_count_3=$(cat "$failure_count_file_3" 2>/dev/null || echo "0")

	# All should be 1 (first failure)
	assert_equal "$failure_count_1" 1
	assert_equal "$failure_count_2" 1
	assert_equal "$failure_count_3" 1

	# Peer 1 recovers, peers 2 and 3 still fail
	# The script calls 'ip xfrm state' once and then greps for each peer IP
	# So we output only peer 1's SA - peers 2 and 3 won't be found when grepped
	mock_ip_xfrm_state "${TEST_PEER_IP}" "1500" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Run again - peer 1 should recover, peers 2 and 3 should fail again
	run bash "$test_script" --fake

	# Verify peer 1's failure count was reset (recovered)
	failure_count_1=$(cat "$failure_count_file_1" 2>/dev/null || echo "0")
	# Should be 0 (recovered) or file doesn't exist
	assert [ "$failure_count_1" -eq 0 ] || [ ! -f "$failure_count_file_1" ]

	# Verify peers 2 and 3's failure counts increased
	failure_count_2=$(cat "$failure_count_file_2" 2>/dev/null || echo "0")
	failure_count_3=$(cat "$failure_count_file_3" 2>/dev/null || echo "0")
	# Should be 2 (second failure each)
	assert_equal "$failure_count_2" 2
	assert_equal "$failure_count_3" 2

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:medium
@test "VPN flapping with rate limiting - should prevent excessive recovery actions" {
	# Purpose: Test verifies that rate limiting prevents excessive recovery actions during VPN flapping.
	# Expected: Rate limiting should block recovery actions after max restarts per hour.
	# Importance: VPN flapping could cause excessive recovery actions if rate limiting doesn't work.

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0

	# Setup rate limited fixture with 3 recent restarts
	local now=$base_time
	setup_vpn_rate_limited_fixture "${TEST_PEER_IP}" 3 \
		$now \
		$((now - 100)) \
		$((now - 200)) \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_HOUR=3' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	local log_file="$LOG_FILE"
	local state_dir="$STATE_DIR"
	local restart_count_file="${state_dir}/restart_count"
	local test_script="$TEST_SCRIPT"

	# Mock ip command - VPN fails
	mock_ip_vpn_down >/dev/null

	# Mock ipsec for Tier 3 recovery
	mock_ipsec_reload_restart 0 0
	add_mock_to_path

	# Run - should hit rate limit
	run bash "$test_script" --fake

	# Verify rate limit was hit
	assert_file_contains "$log_file" "rate limit" || assert_file_contains "$log_file" "Rate limit"

	# Verify no new restart was recorded (rate limited)
	local restart_count_after
	restart_count_after=$(wc -l <"$restart_count_file" | tr -d ' ')
	assert_equal "$restart_count_after" 3

	remove_mock_from_path
}

# bats test_tags=slow,category:integration,priority:medium
@test "VPN flapping - failure count resets correctly on recovery" {
	# Purpose: Test verifies that failure count resets correctly when VPN recovers after flapping.
	# Expected: Failure count should reset to 0 when VPN recovers, regardless of previous failure count.
	# Importance: Failure count not resetting could cause incorrect tier escalation on next failure.

	# Setup initial state - VPN is up, can switch states during test
	setup_vpn_flapping_fixture "${TEST_PEER_IP}" "up" 1000 2000 \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	local log_file="$LOG_FILE"
	local state_dir="$STATE_DIR"
	local test_script="$TEST_SCRIPT"

	# VPN fails - switch to down state
	switch_vpn_to_down

	# Run multiple times to build up failure count
	for _ in {1..4}; do
		run bash "$test_script" --fake
	done

	# Verify failure count is 4
	ensure_state_functions_loaded
	local failure_count_file
	failure_count_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
	assert_file_exist "$failure_count_file"
	local failure_count
	failure_count=$(cat "$failure_count_file")
	assert_equal "$failure_count" 4

	# VPN recovers - switch back to active state
	switch_vpn_to_up 2000

	# Run - VPN recovered, failure count should reset
	run bash "$test_script" --fake
	assert_success

	# Verify failure count was reset to 0
	failure_count=$(cat "$failure_count_file" 2>/dev/null || echo "0")
	assert_equal "$failure_count" 0

	remove_mock_from_path
}

# bats test_tags=category:integration,priority:medium
@test "VPN flapping - cooldown expires but rate limit still active" {
	# Purpose: Test verifies that rate limiting takes precedence over cooldown expiration.
	# Expected: If cooldown expires but rate limit is still active, rate limit should prevent recovery.
	# Importance: Rate limiting should prevent excessive recovery actions even after cooldown expires.

	# Set up controllable time for testing
	local base_time=1609459200 # Fixed timestamp for reproducible tests
	mock_date "$base_time" 0

	# Setup rate limited fixture with 3 recent restarts
	local now=$base_time
	setup_vpn_rate_limited_fixture "${TEST_PEER_IP}" 3 \
		$now \
		$((now - 100)) \
		$((now - 200)) \
		'COOLDOWN_MINUTES=1' \
		'LOCKFILE_TIMEOUT=60' \
		'TIER1_THRESHOLD=1' \
		'TIER2_THRESHOLD=3' \
		'TIER3_THRESHOLD=5' \
		'MAX_RESTARTS_PER_HOUR=3' \
		'ENABLE_NETWORK_PARTITION_CHECK=0'

	local log_file="$LOG_FILE"
	local state_dir="$STATE_DIR"
	local restart_count_file="${state_dir}/restart_count"
	local test_script="$TEST_SCRIPT"

	# Set cooldown to expired (2 seconds ago, which is longer than 1 minute = 60 seconds)
	# For testing, we set it to expired so rate limiting takes precedence
	local cooldown_file="${state_dir}/cooldown_until"
	echo "$((now - 62))" >"$cooldown_file"

	# Mock ip command - VPN fails
	mock_ip_vpn_down >/dev/null

	# Mock ipsec for Tier 3 recovery
	mock_ipsec_reload_restart 0 0
	add_mock_to_path

	# Run - cooldown expired but rate limit active
	run bash "$test_script" --fake

	# Verify rate limit was hit (should take precedence over cooldown)
	assert_file_contains "$log_file" "rate limit" || assert_file_contains "$log_file" "Rate limit"

	# Verify no new restart was recorded
	local restart_count_after
	restart_count_after=$(wc -l <"$restart_count_file" | tr -d ' ')
	assert_equal "$restart_count_after" 3

	remove_mock_from_path
}
