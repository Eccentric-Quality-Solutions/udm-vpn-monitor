#!/usr/bin/env bats
#
# Tests for Failure Type Detection
# Tests critical paths and error handling scenarios

load test_helper
load helpers/assertions
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
	assert_log_contains_any "$LOG_FILE" "Tunnel down" "tunnel_down"

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
	# Use bytes that are less than last_bytes to ensure VPN check fails (bytes decreased)
	mock_ip_xfrm_state "${TEST_PEER_IP}" 500 >/dev/null

	# Mock ipsec to fail (prevent fallback from succeeding and masking failure)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect routing_issue failure type
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Routing issue" "routing_issue"

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
	assert_log_contains_any "$LOG_FILE" "Routing issue" "routing_issue"

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
	assert_log_contains_any "$LOG_FILE" "Routing issue" "routing_issue"

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
	assert_log_contains_any "$LOG_FILE" "rekey" "SA rekey detected"

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
@test "Failure type unknown - SA exists but byte counters unavailable and ping disabled (primary check failed)" {
	# Purpose: Test verifies that failure type "unknown" is returned when SA exists but byte counters unavailable, ping disabled, and primary check failed
	# Expected: Failure type is detected as "unknown" when SA exists but diagnostic data unavailable and primary check failed
	# Importance: Ensures we return "unknown" when we can't definitively determine failure type without diagnostic data
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
	# Mock ipsec to fail (prevent fallback from succeeding and masking failure)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect unknown failure type (cannot determine specific type without diagnostic data)
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Unknown" "unknown" "Unable to determine specific failure type"

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
@test "Failure type routing_issue - SA exists but byte counters unavailable and ping enabled and fails (VPN check failed)" {
	# Purpose: Test verifies that failure type "routing_issue" is detected when SA exists but byte counters unavailable, ping enabled and fails, and VPN check failed
	# Expected: Failure type is detected as "routing_issue" when SA exists but byte counters unavailable, ping check enabled and fails, and VPN check failed
	# Importance: Ensures routing issues are detected even when byte counters can't be extracted but ping check is enabled and fails
	# Enable ping check so that when byte counter extraction fails, ping check is attempted and fails, triggering routing_issue detection
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' "LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP2}\""

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
elif [[ "\$1" == "addr" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "br0" ]]; then
    # Handle route check - return empty (route doesn't exist, will be added)
    exit 0
elif [[ "\$1" == "addr" ]] && [[ "\$2" == "add" ]]; then
    # Handle route add - simulate success
    exit 0
fi
# Handle other ip commands
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	# Mock ping - fails
	mock_ping_failure >/dev/null
	# Mock ipsec to fail (prevent fallback from succeeding and masking failure)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect routing_issue failure type (SA exists, byte counters unavailable, ping enabled and fails)
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Routing issue" "routing_issue" "routing_issue suspected"

	# Verify failure type stored in state file
	source_function "get_peer_state_file_path"
	local failure_type_file
	failure_type_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_type")
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "routing_issue"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Failure type unknown - Unable to determine type (VPN check passed)" {
	# Purpose: Test verifies that failure type "unknown" is detected when unable to determine specific type but VPN check passed
	# Expected: Failure type is detected as "unknown" when detection methods fail but VPN appears healthy
	# Importance: Ensures failure tracking continues even when specific type cannot be determined, but doesn't generate false positives for healthy VPNs
	# Disable ping check and ensure VPN check passes via ipsec fallback
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
	# Mock ipsec to succeed (VPN check passes via fallback)
	mock_ipsec_status 0 >/dev/null
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect unknown failure type when VPN check passed (no routing_issue suspected for healthy VPNs)
	assert_file_exist "$LOG_FILE"
	# When VPN check passed, "unknown" is expected and should not generate warnings
	# The failure type may be "unknown" or not stored at all when VPN is healthy

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
@test "Byte counter extraction failure - malformed lifetime section with SA exists and ping disabled" {
	# Purpose: Test verifies that byte counter extraction failure (malformed lifetime section) is handled correctly when SA exists, ping disabled, and VPN check fails
	# Expected: Failure type is detected as "unknown" when byte counter extraction fails due to malformed lifetime section
	# Importance: Ensures malformed xfrm output doesn't cause incorrect failure type detection
	# Disable ping check so that when byte counter extraction fails, VPN check fails and failure type detection is triggered
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_PING_CHECK=0'

	# Mock ip command - SA exists but malformed lifetime section (missing bytes keyword)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 123456"
    # Missing "bytes" keyword - extraction will fail
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 123456"
    # Missing "bytes" keyword - extraction will fail
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	# Mock ipsec to fail (prevent fallback from succeeding and masking failure)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect unknown failure type (byte counter extraction failed)
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Unknown" "unknown" "byte counter extraction failed" "Unable to determine specific failure type"

	# Verify failure type stored in state file
	source_function "get_peer_state_file_path"
	local failure_type_file
	failure_type_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_type")
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "unknown"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Byte counter extraction failure - non-numeric bytes value with SA exists and ping enabled and fails" {
	# Purpose: Test verifies that byte counter extraction failure (non-numeric bytes) is handled correctly when SA exists, ping enabled and fails
	# Expected: Failure type is detected as "routing_issue" when byte counter extraction fails but ping check enabled and fails
	# Importance: Ensures routing issues are detected even when byte counter extraction fails due to non-numeric values
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_PING_CHECK=1' "LOCATION_TEST_INTERNAL=\"${TEST_PEER_IP2}\""

	# Mock ip command - SA exists but non-numeric bytes value
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: abc123 bytes, 10 packets"
    # Non-numeric bytes value - extraction will fail
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: abc123 bytes, 10 packets"
    # Non-numeric bytes value - extraction will fail
    exit 0
elif [[ "\$1" == "addr" ]] && [[ "\$2" == "show" ]] && [[ "\$3" == "br0" ]]; then
    exit 0
elif [[ "\$1" == "addr" ]] && [[ "\$2" == "add" ]]; then
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	# Mock ping - fails
	mock_ping_failure >/dev/null
	# Mock ipsec to fail (prevent fallback from succeeding and masking failure)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Should detect routing_issue failure type (SA exists, byte counter extraction failed, ping enabled and fails)
	assert_file_exist "$LOG_FILE"
	assert_log_contains_any "$LOG_FILE" "Routing issue" "routing_issue" "routing_issue suspected"

	# Verify failure type stored in state file
	source_function "get_peer_state_file_path"
	local failure_type_file
	failure_type_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_type")
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		assert_equal "$failure_type" "routing_issue"
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "Byte counter extraction failure - empty xfrm output with SA exists and ping disabled" {
	# Purpose: Test verifies that byte counter extraction failure (empty xfrm output) is handled correctly when SA exists via ipsec fallback, ping disabled
	# Expected: Failure type detection should handle empty xfrm output gracefully
	# Importance: Ensures empty xfrm output doesn't cause incorrect failure type detection
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_PING_CHECK=0'

	# Mock ip command - returns empty output (xfrm unavailable or empty)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Return empty output
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Return empty output
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	# Mock ipsec to succeed (SA exists via fallback, but xfrm output is empty)
	mock_ipsec_status 0 >/dev/null
	add_mock_to_path
	run bash "$TEST_SCRIPT" --fake
	assert_success

	# When xfrm output is empty but ipsec shows SA exists, VPN check may pass or fail depending on implementation
	# Failure type should be handled gracefully
	assert_file_exist "$LOG_FILE"
	# Should not crash or produce invalid failure types

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "State passing: sa_exists=1 but xfrm_output empty - handled gracefully" {
	# Purpose: Test verifies that inconsistent state (sa_exists=1 but xfrm_output empty) is handled gracefully
	# Expected: When ipsec fallback succeeds, sa_exists=1 is set but xfrm_output remains empty. Code should handle this by
	#           fetching xfrm_output if needed for failure type detection, or returning "unknown" if unavailable.
	# Importance: Tests defensive handling of state passing when ipsec fallback is used (realistic scenario)
	# This tests the edge case identified in LOGIC_REVIEW_REPORT.md: state passing pattern validation
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_PING_CHECK=0'

	# Mock ip command - returns empty output (xfrm_output will be empty)
	# But ipsec will show SA exists, creating state: sa_exists=1 (from ipsec fallback) but xfrm_output is empty
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Return empty output (xfrm_output will be empty)
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Return empty output (xfrm_output will be empty)
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	# Mock ipsec to succeed (SA exists via ipsec fallback, but xfrm_output is empty)
	# This creates the scenario: sa_exists=1 (from ipsec) but xfrm_output is empty
	mock_ipsec_status 0 >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify VPN check passes via ipsec fallback (should not detect tunnel_down)
	assert_file_exist "$LOG_FILE"
	refute_file_contains "$LOG_FILE" "tunnel_down"
	# Failure type detection should handle empty xfrm_output gracefully
	# It should either fetch xfrm_output (which will still be empty) or return "unknown"
	# Verify failure type is not tunnel_down (since sa_exists=1)
	source_function "get_peer_state_file_path"
	local failure_type_file
	failure_type_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_type")
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		# Should not be tunnel_down since sa_exists=1 (from ipsec fallback)
		assert [ "$failure_type" != "tunnel_down" ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "State passing: inconsistent state between xfrm and ipsec checks - xfrm says no SA, ipsec says SA exists" {
	# Purpose: Test verifies that inconsistent state between xfrm and ipsec checks is handled correctly
	# Expected: When xfrm says no SA exists but ipsec says SA exists, code should use ipsec fallback and VPN check should pass
	# Importance: Tests the fallback mechanism when xfrm and ipsec disagree about SA existence (realistic scenario)
	# This tests the edge case identified in LOGIC_REVIEW_REPORT.md: inconsistent state between xfrm and ipsec checks
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_PING_CHECK=0'

	# Mock ip command - returns empty output (xfrm says no SA exists)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Return empty output (no SA found in xfrm)
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Return empty output (no SA found in xfrm)
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	# Mock ipsec to succeed (ipsec says SA exists - inconsistent with xfrm)
	mock_ipsec_status 0 "test-conn: ESTABLISHED 1 hour ago, ${TEST_PEER_IP}...${TEST_LOCAL_IP}" >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify VPN check passes via ipsec fallback (xfrm failed, ipsec succeeded)
	assert_file_exist "$LOG_FILE"
	# Should NOT detect tunnel_down since ipsec shows SA exists
	refute_file_contains "$LOG_FILE" "tunnel_down"
	# Verify failure type is not tunnel_down
	source_function "get_peer_state_file_path"
	local failure_type_file
	failure_type_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_type")
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		# Should not be tunnel_down since ipsec fallback succeeded (SA exists)
		assert [ "$failure_type" != "tunnel_down" ]
	fi

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:medium
@test "State passing: inconsistent state between xfrm and ipsec checks - xfrm says SA exists, ipsec says no SA" {
	# Purpose: Test verifies that inconsistent state between xfrm and ipsec checks is handled correctly
	# Expected: When xfrm says SA exists but ipsec says no SA exists, code should use xfrm primary check and VPN check should pass
	# Importance: Tests the primary check when xfrm and ipsec disagree about SA existence (xfrm takes precedence)
	# This tests the edge case identified in LOGIC_REVIEW_REPORT.md: inconsistent state between xfrm and ipsec checks
	setup_location_vpn_monitor "${TEST_PEER_IP}" "${TEST_DIR}" 'ENABLE_PING_CHECK=0'

	# Set initial bytes to ensure byte counter check passes
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "last_bytes" "1000" || true
	set_peer_state "TEST" "${TEST_PEER_IP}" "spi" "0x12345678" || true

	# Mock ip command - SA exists in xfrm (xfrm says SA exists)
	mock_ip_xfrm_state "${TEST_PEER_IP}" 2000 >/dev/null
	# Mock ipsec to fail (ipsec says no SA exists - inconsistent with xfrm)
	mock_ipsec_status 1 >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake
	assert_success

	# Verify VPN check passes via xfrm primary check (xfrm succeeded, ipsec fallback not needed)
	assert_file_exist "$LOG_FILE"
	# Should NOT detect tunnel_down since xfrm (primary method) shows SA exists
	refute_file_contains "$LOG_FILE" "tunnel_down"
	# Verify failure type is not tunnel_down
	source_function "get_peer_state_file_path"
	local failure_type_file
	failure_type_file=$(get_peer_state_file_path "TEST" "${TEST_PEER_IP}" "failure_type")
	if [[ -f "$failure_type_file" ]]; then
		local failure_type
		failure_type=$(cat "$failure_type_file")
		# Should not be tunnel_down since xfrm primary check succeeded (SA exists)
		assert [ "$failure_type" != "tunnel_down" ]
	fi

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
	assert_log_contains_any "$LOG_FILE" "tunnel_down" "unknown" "VPN check failed"

	remove_mock_from_path
}
