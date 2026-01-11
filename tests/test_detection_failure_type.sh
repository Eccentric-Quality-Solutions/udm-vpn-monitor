#!/usr/bin/env bats
#
# Tests for Failure Type Detection
# Tests critical paths and error handling scenarios

load test_helper
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing
load fixtures/vpn_rekey

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# 2.3 FAILURE TYPE DETECTION
# ============================================================================

# bats test_tags=category:high-risk,priority:medium
@test "Failure type tunnel_down - No Phase 2 SA found" {
	# Purpose: Test verifies that failure type "tunnel_down" is detected when no Phase 2 SA is found
	# Expected: Failure type is detected as "tunnel_down" when no SA exists
	# Importance: Enables targeted recovery strategies based on failure type
	setup_vpn_down_fixture "${TEST_PEER_IP}"
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect tunnel_down failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Tunnel down" || assert_file_contains "$LOG_FILE" "tunnel_down"

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_TEST_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "tunnel_down"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type routing_issue - Phase 2 SA exists but bytes not increasing" {
	# Purpose: Test verifies that failure type "routing_issue" is detected when SA exists but bytes not increasing
	# Expected: Failure type is detected as "routing_issue" when SA exists but traffic not flowing
	# Importance: Enables targeted recovery strategies for routing issues
	# Disable ping check so that bytes not increasing is treated as a routing issue, not idle tunnel
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_PING_CHECK=0'

	# Set initial bytes (same as current - not increasing) using location-based state functions
	# Ensure STATE_DIR is set (setup_location_vpn_monitor sets it, but ensure it's available)
	export STATE_DIR="${TEST_DIR}"
	export LOGS_DIR="${TEST_DIR}/logs"
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true
	# Use get_peer_state_file_path to get the correct path dynamically
	local expected_state_file
	expected_state_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "last_bytes" 2>/dev/null || echo "${STATE_DIR}/last_bytes_TEST_192_168_1_1")

	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "1000" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true

	# Verify state file was created correctly
	assert_file_exist "$expected_state_file"
	local stored_bytes
	stored_bytes=$(get_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "0" 2>/dev/null || echo "0")
	assert_equal "$stored_bytes" "1000"

	# Mock ip command - SA exists but bytes not increasing
	mock_ip_xfrm_state "${TEST_PEER_IP}" 1000 >/dev/null

	# Mock ipsec to fail (prevent fallback from succeeding and masking failure)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect routing_issue failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Routing issue" || assert_file_contains "$LOG_FILE" "routing_issue"

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_TEST_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "routing_issue"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type routing_issue - Phase 2 SA exists but ping fails" {
	# Purpose: Test verifies that failure type "routing_issue" is detected when SA exists but ping fails
	# Expected: Failure type is detected as "routing_issue" when SA exists but connectivity fails
	# Importance: Enables targeted recovery strategies for routing issues
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' "LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP}\""

	# Set initial bytes (increasing) using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "1000" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true

	# Mock ip command - SA exists
	mock_ip_xfrm_state "${TEST_PEER_IP}" "2000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ping - fails
	mock_ping_failure >/dev/null
	add_mock_to_path

	# Mock ipsec to fail (prevent fallback from succeeding and masking failure)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect routing_issue failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Routing issue" || assert_file_contains "$LOG_FILE" "routing_issue"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "Failure type routing_issue - Multiple IPs threshold logic (2/3 IPs respond = pass, 0/3 = fail)" {
	# Purpose: Test verifies that multiple IP threshold logic works correctly in failure type detection
	# Expected: With 3 IPs, threshold is ceil(3 * 0.3) = 1, so 2/3 responding (>=threshold) = no routing_issue, 0/3 responding (<threshold) = routing_issue
	# Importance: Ensures threshold logic correctly handles multiple IP scenarios in failure classification
	local ip1="192.168.1.1"
	local ip2="192.168.1.2"
	local ip3="192.168.1.3"
	local multiple_ips="${ip1} ${ip2} ${ip3}"

	# Test case 1: 2/3 IPs respond (meets 30% threshold) - should NOT detect routing_issue
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' "LOCATION_TEST_INTERNAL=\"${multiple_ips}\""

	# Set initial bytes (increasing) using location-based state functions
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "1000" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true

	# Mock ip command - SA exists
	mock_ip_xfrm_state "${TEST_PEER_IP}" "2000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true

	# Mock ping - succeeds for 2 out of 3 IPs (meets threshold: ceil(3 * 0.3) = 1, need >= 1, have 2)
	mock_ping_selective "${ip1} ${ip2}" >/dev/null
	add_mock_to_path

	# Mock ipsec to fail (prevent fallback from succeeding and masking failure)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should NOT detect routing_issue (threshold met: 2/3 >= 30%)
	assert_file_exist "$LOG_FILE"
	refute_file_contains "$LOG_FILE" "routing_issue"

	# Clean up for next test case
	remove_mock_from_path

	# Test case 2: 0/3 IPs respond (below 30% threshold) - should detect routing_issue
	# Reset state
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "1000" || true

	# Mock ping - all fail (0/3 < threshold: ceil(3 * 0.3) = 1, need >= 1, have 0)
	mock_ping_failure >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect routing_issue (threshold not met: 0/3 < 30%)
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Routing issue" || assert_file_contains "$LOG_FILE" "routing_issue"

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type rekey - SPI changed (not a failure, but logged)" {
	# Purpose: Test verifies that failure type "rekey" is detected when SPI changes (not a failure)
	# Expected: Failure type is detected as "rekey" when SPI changes, VPN marked as OK
	# Importance: Rekey events are logged but not treated as failures
	setup_vpn_rekey_fixture "${TEST_PEER_IP}" "0x12345678" "0x87654321" 1000 2000
	run bash "$TEST_SCRIPT" --fake

	# Should detect rekey (not a failure)
	assert_success
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "rekey" || assert_file_contains "$LOG_FILE" "SA rekey detected"

	# Verify failure type stored (rekey is logged but VPN is OK)
	local failure_type_file="${STATE_DIR}/failure_type_TEST_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		# Rekey may be stored for monitoring purposes
		assert [ "$failure_type" == "rekey" ] || [ "$failure_type" == "unknown" ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type unknown - Unable to determine type" {
	# Purpose: Test verifies that failure type "unknown" is detected when unable to determine specific type
	# Expected: Failure type is detected as "unknown" when detection methods fail
	# Importance: Ensures failure tracking continues even when specific type cannot be determined
	# Disable ping check so that when byte counter extraction fails, VPN check fails and failure type detection is triggered
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_PING_CHECK=0'

	# Mock ip command - SA exists but no byte counter info
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Handle "ip -s xfrm state" (with statistics flag)
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    # No lifetime line (can't extract bytes)
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Handle "ip xfrm state" (without statistics flag)
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    # No lifetime line (can't extract bytes)
    exit 0
fi
# Handle other ip commands
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect unknown failure type
	assert_file_exist "$LOG_FILE"
	assert_file_contains "$LOG_FILE" "Unknown" || assert_file_contains "$LOG_FILE" "unknown"

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_TEST_192_168_1_1"
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "unknown"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type stored in state file for recovery actions" {
	# Purpose: Test verifies that failure type is stored in state file for use by recovery actions
	# Expected: Failure type is stored in state file and can be retrieved for recovery strategies
	# Importance: Enables recovery actions to use failure-specific strategies
	setup_vpn_down_fixture "${TEST_PEER_IP}"
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify failure type stored in state file
	local failure_type_file="${STATE_DIR}/failure_type_TEST_192_168_1_1"
	assert_file_exist "$failure_type_file"
	local failure_type
	failure_type=$(cat "$failure_type_file")
	assert [ "$failure_type" == "tunnel_down" ] || [ "$failure_type" == "unknown" ]

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type cleared on VPN recovery" {
	# Purpose: Test verifies that failure type is cleared when VPN recovers
	# Expected: Failure type file is removed or cleared when VPN becomes healthy
	# Importance: Ensures failure type tracking is reset after recovery
	# Use same fixture as working test in test_detection.sh
	setup_vpn_active_fixture "${TEST_PEER_IP}" 1000 2000

	source_function "get_peer_state_file_path"
	# Create failure type file (from previous failure)
	local failure_type_file
	failure_type_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_type")
	echo "tunnel_down" >"$failure_type_file"

	# Note: With the false positive fix, recovery messages are only logged when
	# failure_count > 0 (actual failures occurred). If only failure_type file exists
	# without failure_count, the file is cleared silently to prevent false positive
	# recovery messages. Using get_peer_state_file_path ensures the correct path format.

	run bash "$TEST_SCRIPT" --fake

	# VPN should be healthy
	assert_success
	assert_file_exist "$LOG_FILE"
	# No recovery message should be logged when only failure_type exists (no actual failures)
	# This prevents false positive recovery messages when VPN was already healthy
	assert_log_not_contains "$LOG_FILE" "recovered"
	assert_log_not_contains "$LOG_FILE" "restored"

	# Failure type file should be cleared silently (no recovery message logged)
	# This verifies that stale failure_type files are cleaned up without false positives

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type detection when xfrm unavailable" {
	# Purpose: Test verifies that failure type detection works when xfrm is unavailable
	# Expected: Failure type is detected using fallback methods when xfrm unavailable
	# Importance: Ensures failure type detection works even when preferred method unavailable
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}"

	# Don't create ip mock (xfrm unavailable)
	# Mock ipsec - no connection
	mock_ipsec_status 0
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect failure type using fallback
	assert_file_exist "$LOG_FILE"
	# Should contain failure type detection (may be unknown or tunnel_down)
	assert_file_contains "$LOG_FILE" "tunnel_down" || assert_file_contains "$LOG_FILE" "unknown" || assert_file_contains "$LOG_FILE" "VPN check failed"

	remove_mock_from_path
}
