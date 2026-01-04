#!/usr/bin/env bats
#
# Tests for Recovery Method Tracking
# Tests that recovery methods are properly stored, retrieved, and included in restoration messages
#
# These tests verify the recovery method tracking feature that allows correlation
# between recovery attempts and VPN restoration events.

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_at_tier

# ============================================================================
# RECOVERY METHOD TRACKING TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "recovery method tracking: recovery method is stored when xfrm recovery is attempted" {
	# Purpose: Test verifies that recovery method is stored when xfrm recovery is attempted
	# Expected: store_recovery_method is called with "xfrm" when xfrm recovery is attempted
	# Importance: Ensures recovery method tracking works for xfrm-based recovery
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_XFRM_RECOVERY=1' 'TIER2_THRESHOLD=3'

	# Track phase2 calls for SA deletion/re-establishment simulation
	local phase2_call_file="${TEST_DIR}/phase2_calls"
	echo "0" >"$phase2_call_file"

	# Mock ip command for xfrm recovery with incrementing byte counters
	# Note: get_xfrm_state_for_peer may call "ip -s xfrm state" first, then fall back to "ip xfrm state"
	# Byte counters must increase over time for verify_byte_counters_increment to succeed
	local verify_attempt_file="${TEST_DIR}/verify_attempts"
	mock_ip_xfrm_with_incrementing_bytes "192.168.1.1" "1000" "1000" "0x12345678" "$verify_attempt_file" "10.0.0.1" >/dev/null
	add_mock_to_path

	# Mock check_ipsec_phase2 function to simulate SA deletion and re-establishment
	# Tracks its own call count to coordinate with recovery phases
	local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"
	cat >"$mock_check_ipsec_phase2" <<EOF
#!/bin/bash
# Track call count for this function
phase2_calls=\$(cat "$phase2_call_file" 2>/dev/null || echo "0")
phase2_calls=\$((phase2_calls + 1))
echo "\$phase2_calls" > "$phase2_call_file"

# Initially: SAs exist (first call) - return success
# After deletion check: SAs deleted (2nd call) - return failure  
# During verification: SAs re-established (3rd+ call) - return success
if [[ \$phase2_calls -eq 1 ]]; then
	# Initial check: SAs exist
	exit 0
elif [[ \$phase2_calls -eq 2 ]]; then
	# After deletion: SAs don't exist yet
	exit 1
else
	# After re-establishment: SAs exist again
	exit 0
fi
EOF
	chmod +x "$mock_check_ipsec_phase2"
	add_mock_to_path

	source_recovery_module

	# Override check_ipsec_phase2 function to use mock
	#
	# Overrides check_ipsec_phase2 to use mock script for testing.
	#
	# Arguments:
	#   $@: All arguments passed to the function (forwarded to mock script)
	#
	# Returns:
	#   Exit code from mock script
	check_ipsec_phase2() {
		"$mock_check_ipsec_phase2" "$@"
	}

	# Set up failure count at Tier 2 threshold
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local location_name="TEST"
	local peer_ip="192.168.1.1"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "3"

	# Call surgical_cleanup which should store recovery method
	surgical_cleanup "$peer_ip" "$location_name"

	# Verify recovery method was stored
	local recovery_method
	recovery_method=$(get_recovery_method "$location_name" "$peer_ip")
	assert_equal "$recovery_method" "xfrm"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery method tracking: recovery method is stored when ipsec_reload recovery is attempted" {
	# Purpose: Test verifies that recovery method is stored when ipsec_reload recovery is attempted
	# Expected: store_recovery_method is called with "ipsec_reload" when ipsec reload is attempted
	# Importance: Ensures recovery method tracking works for ipsec reload recovery
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_XFRM_RECOVERY=0' 'TIER2_THRESHOLD=3'

	# Mock ipsec command for reload
	mock_ipsec_reload_restart 0 0 >/dev/null
	add_mock_to_path

	source_recovery_module

	# Set up failure count at Tier 2 threshold
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local location_name="TEST"
	local peer_ip="192.168.1.1"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "3"

	# Call surgical_cleanup which should store recovery method
	surgical_cleanup "$peer_ip" "$location_name"

	# Verify recovery method was stored
	local recovery_method
	recovery_method=$(get_recovery_method "$location_name" "$peer_ip")
	assert_equal "$recovery_method" "ipsec_reload"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery method tracking: recovery method is updated when fallback occurs" {
	# Purpose: Test verifies that recovery method is updated when xfrm fails and falls back to ipsec_reload
	# Expected: Recovery method is updated from "xfrm" to "ipsec_reload" when fallback occurs
	# Importance: Ensures fallback recovery methods are correctly tracked
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_XFRM_RECOVERY=1' 'TIER2_THRESHOLD=3'

	# Mock ip command - xfrm recovery will fail (no SAs found)
	# Note: get_xfrm_state_for_peer may call "ip -s xfrm state" first, then fall back to "ip xfrm state"
	mock_ip_xfrm_empty >/dev/null
	add_mock_to_path

	# Mock ipsec command for fallback reload
	mock_ipsec_reload_restart 0 0 >/dev/null
	add_mock_to_path

	source_recovery_module

	# Set up failure count at Tier 2 threshold
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local location_name="TEST"
	local peer_ip="192.168.1.1"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "3"

	# Call surgical_cleanup - xfrm will fail, fallback to ipsec_reload
	surgical_cleanup "$peer_ip" "$location_name"

	# Verify recovery method was updated to ipsec_reload (not xfrm)
	local recovery_method
	recovery_method=$(get_recovery_method "$location_name" "$peer_ip")
	assert_equal "$recovery_method" "ipsec_reload"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery method tracking: VPN restored message includes recovery method" {
	# Purpose: Test verifies that "VPN restored" message includes the recovery method that was used
	# Expected: Log message contains "VPN restored" with recovery method information
	# Importance: Provides visibility into which recovery method successfully restored the VPN
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_XFRM_RECOVERY=1' 'TIER2_THRESHOLD=3'

	# Track phase2 calls for SA deletion/re-establishment simulation
	local phase2_call_file="${TEST_DIR}/phase2_calls"
	echo "0" >"$phase2_call_file"

	# Mock ip command for xfrm recovery with incrementing byte counters
	# Note: get_xfrm_state_for_peer may call "ip -s xfrm state" first, then fall back to "ip xfrm state"
	# Byte counters must increase over time for verify_byte_counters_increment to succeed
	local verify_attempt_file="${TEST_DIR}/verify_attempts"
	mock_ip_xfrm_with_incrementing_bytes "192.168.1.1" "12345" "1000" "0x12345678" "$verify_attempt_file" "10.0.0.1" >/dev/null
	add_mock_to_path

	# Mock check_ipsec_phase2 function to simulate SA deletion and re-establishment
	# Tracks its own call count to coordinate with recovery phases
	local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"
	cat >"$mock_check_ipsec_phase2" <<EOF
#!/bin/bash
# Track call count for this function
phase2_calls=\$(cat "$phase2_call_file" 2>/dev/null || echo "0")
phase2_calls=\$((phase2_calls + 1))
echo "\$phase2_calls" > "$phase2_call_file"

# Initially: SAs exist (first call) - return success
# After deletion check: SAs deleted (2nd call) - return failure  
# During verification: SAs re-established (3rd+ call) - return success
if [[ \$phase2_calls -eq 1 ]]; then
	# Initial check: SAs exist
	exit 0
elif [[ \$phase2_calls -eq 2 ]]; then
	# After deletion: SAs don't exist yet
	exit 1
else
	# After re-establishment: SAs exist again
	exit 0
fi
EOF
	chmod +x "$mock_check_ipsec_phase2"
	add_mock_to_path

	source_recovery_module

	# Override check_ipsec_phase2 function to use mock
	#
	# Overrides check_ipsec_phase2 to use mock script for testing.
	#
	# Arguments:
	#   $@: All arguments passed to the function (forwarded to mock script)
	#
	# Returns:
	#   Exit code from mock script
	check_ipsec_phase2() {
		"$mock_check_ipsec_phase2" "$@"
	}

	# Set up failure count at Tier 2 threshold
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local location_name="TEST"
	local peer_ip="192.168.1.1"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "3"

	# Perform recovery (stores recovery method)
	surgical_cleanup "$peer_ip" "$location_name"

	# Now simulate VPN recovery - update mock ip to return active VPN state
	# Set up state with previous byte counter (bytes will increase)
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "10000" || true

	# Update mock ip to return active VPN (SA exists, bytes increasing)
	# Format matches UDM OS format for proper parsing
	# Note: get_xfrm_state_for_peer may call "ip -s xfrm state" first, then fall back to "ip xfrm state"
	mock_ip_xfrm_state "192.168.1.1" "20000" "0x12345678" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Call monitor_location - VPN should be detected as healthy
	monitor_location "$location_name" "$peer_ip" ""

	# Verify log contains "VPN restored" with recovery method
	assert_file_contains "$LOG_FILE" "VPN restored"
	assert_file_contains "$LOG_FILE" "recovery method: xfrm-based recovery"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery method tracking: recovery method is cleared after logging" {
	# Purpose: Test verifies that recovery method is cleared after being logged in restoration message
	# Expected: Recovery method state file is deleted after VPN restoration is logged
	# Importance: Prevents stale recovery method information from being displayed
	setup_location_vpn_monitor "192.168.1.1" "${TEST_DIR}" 'ENABLE_XFRM_RECOVERY=1' 'TIER2_THRESHOLD=3'

	# Track phase2 calls for SA deletion/re-establishment simulation
	local phase2_call_file="${TEST_DIR}/phase2_calls"
	echo "0" >"$phase2_call_file"

	# Mock ip command for xfrm recovery with incrementing byte counters
	# Note: get_xfrm_state_for_peer may call "ip -s xfrm state" first, then fall back to "ip xfrm state"
	# Byte counters must increase over time for verify_byte_counters_increment to succeed
	local verify_attempt_file="${TEST_DIR}/verify_attempts"
	mock_ip_xfrm_with_incrementing_bytes "192.168.1.1" "12345" "1000" "0x12345678" "$verify_attempt_file" "10.0.0.1" >/dev/null
	add_mock_to_path

	# Mock check_ipsec_phase2 function to simulate SA deletion and re-establishment
	# Tracks its own call count to coordinate with recovery phases
	local mock_check_ipsec_phase2="${TEST_DIR}/check_ipsec_phase2"
	cat >"$mock_check_ipsec_phase2" <<EOF
#!/bin/bash
# Track call count for this function
phase2_calls=\$(cat "$phase2_call_file" 2>/dev/null || echo "0")
phase2_calls=\$((phase2_calls + 1))
echo "\$phase2_calls" > "$phase2_call_file"

# Initially: SAs exist (first call) - return success
# After deletion check: SAs deleted (2nd call) - return failure  
# During verification: SAs re-established (3rd+ call) - return success
if [[ \$phase2_calls -eq 1 ]]; then
	# Initial check: SAs exist
	exit 0
elif [[ \$phase2_calls -eq 2 ]]; then
	# After deletion: SAs don't exist yet
	exit 1
else
	# After re-establishment: SAs exist again
	exit 0
fi
EOF
	chmod +x "$mock_check_ipsec_phase2"
	add_mock_to_path

	source_recovery_module

	# Override check_ipsec_phase2 function to use mock
	#
	# Overrides check_ipsec_phase2 to use mock script for testing.
	#
	# Arguments:
	#   $@: All arguments passed to the function (forwarded to mock script)
	#
	# Returns:
	#   Exit code from mock script
	check_ipsec_phase2() {
		"$mock_check_ipsec_phase2" "$@"
	}

	# Set up failure count at Tier 2 threshold
	# setup_location_vpn_monitor creates location "TEST" from LOCATION_TEST_EXTERNAL
	local location_name="TEST"
	local peer_ip="192.168.1.1"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "3"

	# Perform recovery (stores recovery method)
	surgical_cleanup "$peer_ip" "$location_name"

	# Verify recovery method was stored
	local recovery_method
	recovery_method=$(get_recovery_method "$location_name" "$peer_ip")
	assert_equal "$recovery_method" "xfrm"

	# Now simulate VPN recovery - update mock ip to return active VPN state
	# Set up state with previous byte counter (bytes will increase)
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "10000" || true

	# Update mock ip to return active VPN (SA exists, bytes increasing)
	# Format matches UDM OS format for proper parsing
	# Note: get_xfrm_state_for_peer may call "ip -s xfrm state" first, then fall back to "ip xfrm state"
	mock_ip_xfrm_state "192.168.1.1" "20000" "0x12345678" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Call monitor_location - VPN should be detected as healthy and recovery method cleared
	monitor_location "$location_name" "$peer_ip" ""

	# Verify recovery method was cleared
	recovery_method=$(get_recovery_method "$location_name" "$peer_ip")
	assert_equal "$recovery_method" ""

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "recovery method tracking: recovery method format is correct for all methods" {
	# Purpose: Test verifies that format_recovery_method correctly formats all recovery method types
	# Expected: format_recovery_method returns user-friendly descriptions for all method types
	# Importance: Ensures recovery method display is consistent and readable
	source_recovery_module

	# Test xfrm format
	local formatted
	formatted=$(format_recovery_method "xfrm")
	assert_equal "$formatted" "xfrm-based recovery"

	# Test ipsec_reload format
	formatted=$(format_recovery_method "ipsec_reload")
	assert_equal "$formatted" "ipsec reload"

	# Test ipsec_restart format
	formatted=$(format_recovery_method "ipsec_restart")
	assert_equal "$formatted" "ipsec restart"

	# Test unknown format
	formatted=$(format_recovery_method "unknown_method")
	assert_equal "$formatted" "unknown_method"

	# Test empty format
	formatted=$(format_recovery_method "")
	assert_equal "$formatted" "unknown recovery method"
}
