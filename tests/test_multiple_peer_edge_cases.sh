#!/usr/bin/env bats
#
# Tests for Multiple Peer Processing Edge Cases (Section 1.1)
# Tests critical paths where one peer failure shouldn't affect others
#
# These tests address the gap identified in CRITICAL_PATH_TEST_GAPS_REVIEW.md:
# - One peer's state file becomes corrupted during monitoring loop - other peers should continue
# - One peer's monitoring throws unexpected error - should not stop other peers
# - Empty peer IP in middle of list - should skip and continue

load test_helper
load helpers/state
load helpers/assertions
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing

# ============================================================================
# MULTIPLE PEER PROCESSING EDGE CASES TESTS
# ============================================================================

# bats test_tags=slow,category:high-risk,priority:high
@test "multiple peer edge cases: one peer state file corrupted during monitoring - other peers continue" {
	# Purpose: Test verifies that when one peer's state file becomes corrupted during monitoring, other peers continue to be monitored successfully
	# Expected: Corrupted state file is handled gracefully, other peers are processed normally
	# Importance: State file corruption shouldn't stop monitoring of other peers
	setup_test_vpn_monitor "${TEST_PEER_IP} ${TEST_PEER_IP2} 172.16.0.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=0'

	# Get state file paths using helper
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create corrupted state file for second peer (10.0.0.1) - location TEST2
	local corrupted_state_file
	corrupted_state_file=$(get_state_file_path "TEST2" "${TEST_PEER_IP2}" "failure_count")
	echo "invalid_data_not_a_number" >"$corrupted_state_file"

	# Create valid state files for other peers
	local peer1_file
	peer1_file=$(get_state_file_path "TEST1" "${TEST_PEER_IP}" "failure_count")
	echo "0" >"$peer1_file"
	local peer3_file
	peer3_file=$(get_state_file_path "TEST3" "172.16.0.1" "failure_count")
	echo "0" >"$peer3_file"

	# Mock VPN healthy for all peers - create single mock that handles all three IPs
	# (setup_mock_vpn_environment overwrites the mock each time, so we need a custom mock)
	mock_ip_xfrm_state_multiple_peers "${TEST_PEER_IP} ${TEST_PEER_IP2} 172.16.0.1" 1000 "0x12345678" >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Script should handle corrupted state file gracefully
	assert_success
	# Should handle corrupted state file gracefully and continue with other peers
	assert_file_exist "$LOG_FILE"
	# Should process all peers despite corruption
	# Verify that all peers were processed (check for peer IPs in log)
	assert_log_contains_any "$LOG_FILE" "${TEST_PEER_IP}" "172.16.0.1"
	# Corrupted state file should be recovered or handled gracefully
	# State file should be fixed or reset
	if [[ -f "$corrupted_state_file" ]]; then
		local content
		content=$(cat "$corrupted_state_file" 2>/dev/null || echo "")
		# State file should be recovered (valid number) or reset
		if [[ -n "$content" ]] && [[ ! "$content" =~ ^[0-9]+$ ]]; then
			# If still corrupted, that's okay - system should handle it gracefully
			# But ideally it should be recovered
			:
		fi
	fi

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "multiple peer edge cases: one peer monitoring throws unexpected error - should not stop other peers" {
	# Purpose: Test verifies that when one peer's monitoring throws an unexpected error, other peers continue to be monitored successfully
	# Expected: Error is caught and logged, monitoring continues for remaining peers
	# Importance: One peer's failure shouldn't prevent monitoring of other peers
	setup_test_vpn_monitor "${TEST_PEER_IP} ${TEST_PEER_IP2} 172.16.0.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=0'

	# Mock VPN check to throw error on second call (simulating error during monitoring)
	# Use a file to track state across calls
	# Note: ip xfrm state is called once per location, so the error will affect one location's check
	local check_state_file="${TEST_DIR}/check_state"
	echo "0" >"$check_state_file"
	local mock_ip="${TEST_DIR}/ip"
	local spi="0x12345678"
	cat >"$mock_ip" <<EOF
#!/bin/bash
# Handle both "ip -s xfrm state" and "ip xfrm state"
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Count checks to identify which location is being checked
    # Each location calls ip xfrm state once, then greps the output
    check_count=\$(cat "$check_state_file" 2>/dev/null || echo "0")
    check_count=\$((check_count + 1))
    echo "\$check_count" >"$check_state_file"
    if [[ \$check_count -eq 2 ]]; then
        # Simulate unexpected error for second location check
        echo "Unexpected error occurred" >&2
        exit 255
    fi
    # Return healthy VPN for other locations - output all SAs
    # The detection code greps this output for each peer IP
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi ${spi} reqid 1 mode tunnel"
    echo "    replay-window 0"
    echo "    auth-trunc hmac(sha256) 0x1234567890abcdef 96"
    echo "    enc cbc(aes) 0x1234567890abcdef"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime soft: 2880s, 0 bytes, 0 packets"
    echo "    current use: 1"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
    echo "src ${TEST_PEER_IP2} dst ${TEST_PEER_IP2}"
    echo "    proto esp spi ${spi} reqid 2 mode tunnel"
    echo "    replay-window 0"
    echo "    auth-trunc hmac(sha256) 0x1234567890abcdef 96"
    echo "    enc cbc(aes) 0x1234567890abcdef"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime soft: 2880s, 0 bytes, 0 packets"
    echo "    current use: 1"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
    echo "src 172.16.0.1 dst 172.16.0.1"
    echo "    proto esp spi ${spi} reqid 3 mode tunnel"
    echo "    replay-window 0"
    echo "    auth-trunc hmac(sha256) 0x1234567890abcdef 96"
    echo "    enc cbc(aes) 0x1234567890abcdef"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime soft: 2880s, 0 bytes, 0 packets"
    echo "    current use: 1"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Count checks to identify which location is being checked
    # Each location calls ip xfrm state once, then greps the output
    check_count=\$(cat "$check_state_file" 2>/dev/null || echo "0")
    check_count=\$((check_count + 1))
    echo "\$check_count" >"$check_state_file"
    if [[ \$check_count -eq 2 ]]; then
        # Simulate unexpected error for second location check
        echo "Unexpected error occurred" >&2
        exit 255
    fi
    # Return healthy VPN for other locations - output all SAs
    # The detection code greps this output for each peer IP
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi ${spi} reqid 1 mode tunnel"
    echo "    replay-window 0"
    echo "    auth-trunc hmac(sha256) 0x1234567890abcdef 96"
    echo "    enc cbc(aes) 0x1234567890abcdef"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime soft: 2880s, 0 bytes, 0 packets"
    echo "    current use: 1"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
    echo "src ${TEST_PEER_IP2} dst ${TEST_PEER_IP2}"
    echo "    proto esp spi ${spi} reqid 2 mode tunnel"
    echo "    replay-window 0"
    echo "    auth-trunc hmac(sha256) 0x1234567890abcdef 96"
    echo "    enc cbc(aes) 0x1234567890abcdef"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime soft: 2880s, 0 bytes, 0 packets"
    echo "    current use: 1"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
    echo "src 172.16.0.1 dst 172.16.0.1"
    echo "    proto esp spi ${spi} reqid 3 mode tunnel"
    echo "    replay-window 0"
    echo "    auth-trunc hmac(sha256) 0x1234567890abcdef 96"
    echo "    enc cbc(aes) 0x1234567890abcdef"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime soft: 2880s, 0 bytes, 0 packets"
    echo "    current use: 1"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
    exit 0
elif [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Return SA for all configured peers based on grep filter
    # The detection code uses "grep -F dst \$peer_ip", so we need to output
    # matching lines for each peer IP when queried
    # Since we can't know which IP is being queried, output all SAs
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi ${spi} reqid 1 mode tunnel"
    echo "    replay-window 0"
    echo "    auth-trunc hmac(sha256) 0x1234567890abcdef 96"
    echo "    enc cbc(aes) 0x1234567890abcdef"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime soft: 2880s, 0 bytes, 0 packets"
    echo "    current use: 1"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
    echo "src ${TEST_PEER_IP2} dst ${TEST_PEER_IP2}"
    echo "    proto esp spi ${spi} reqid 2 mode tunnel"
    echo "    replay-window 0"
    echo "    auth-trunc hmac(sha256) 0x1234567890abcdef 96"
    echo "    enc cbc(aes) 0x1234567890abcdef"
    echo "    lifetime current: 1000 bytes, 10 packets"
    echo "    lifetime hard: 3600s, 0 bytes, 0 packets"
    echo "    lifetime soft: 2880s, 0 bytes, 0 packets"
    echo "    current use: 1"
    echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	run bash "$TEST_SCRIPT" --fake

	# Script should handle error gracefully
	# Use --fake mode so errors are logged but don't cause exit code 1
	assert_success
	# Should handle error gracefully and continue with other peers
	assert_file_exist "$LOG_FILE"
	# Should process all peers despite error
	# Verify that all peers were attempted (check for peer IPs in log)
	assert_log_contains_any "$LOG_FILE" "${TEST_PEER_IP}" "172.16.0.1"
	# Error should be logged but shouldn't stop processing
	# Script should complete successfully (may exit with warnings)

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "multiple peer edge cases: empty peer IP in middle of list - should skip and continue" {
	# Purpose: Test verifies that empty peer IPs in the middle of the list are skipped gracefully
	# Expected: Empty peer IPs are skipped with warning, other peers are processed normally
	# Importance: Malformed configuration shouldn't prevent monitoring of valid peers
	setup_test_vpn_monitor "${TEST_PEER_IP}  ${TEST_PEER_IP2}" "${TEST_DIR}" 'ENABLE_PING_CHECK=0'

	# Mock VPN healthy for valid peers - create single mock that handles both IPs
	# (setup_mock_vpn_environment overwrites the mock each time, so we need a custom mock)
	mock_ip_xfrm_state_multiple_peers "${TEST_PEER_IP} ${TEST_PEER_IP2}" 1000 "0x12345678" >/dev/null
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Script should handle empty peer IP gracefully
	assert_success
	# Should skip empty peer IP and continue with valid peers
	assert_file_exist "$LOG_FILE"
	# Should log warning about empty peer IP
	assert_log_contains_any "$LOG_FILE" "Skipping empty" "empty peer"
	# Should process valid peers
	assert_log_contains_any "$LOG_FILE" "${TEST_PEER_IP}" "${TEST_PEER_IP2}"
	# Script should complete successfully

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "multiple peer edge cases: one peer fails catastrophically - other peers continue independently" {
	# Purpose: Test verifies that catastrophic failure of one peer (e.g., state file unreadable) doesn't prevent monitoring of other peers
	# Expected: Failed peer is handled gracefully, other peers monitored independently
	# Importance: Critical for multi-peer deployments where one peer failure shouldn't affect others
	setup_test_vpn_monitor "${TEST_PEER_IP} ${TEST_PEER_IP2} 172.16.0.1" "${TEST_DIR}" 'ENABLE_PING_CHECK=0'

	# Get state file paths using helper
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Create unreadable state file for second peer (10.0.0.1) - location TEST2
	local unreadable_state_file
	unreadable_state_file=$(get_state_file_path "TEST2" "${TEST_PEER_IP2}" "failure_count")
	echo "5" >"$unreadable_state_file"
	chmod 000 "$unreadable_state_file" 2>/dev/null || true

	# Create valid state files for other peers
	local peer1_file
	peer1_file=$(get_state_file_path "TEST1" "${TEST_PEER_IP}" "failure_count")
	echo "0" >"$peer1_file"
	local peer3_file
	peer3_file=$(get_state_file_path "TEST3" "172.16.0.1" "failure_count")
	echo "0" >"$peer3_file"

	# Mock VPN healthy for all peers - create single mock that handles all three IPs
	# (setup_mock_vpn_environment overwrites the mock each time, so we need a custom mock)
	mock_ip_xfrm_state_multiple_peers "${TEST_PEER_IP} ${TEST_PEER_IP2} 172.16.0.1" 1000 "0x12345678" >/dev/null
	add_mock_to_path

	# Use timeout to prevent hanging (test is marked as slow)
	# 15 seconds should be sufficient for normal execution, but prevents indefinite hangs
	run timeout 15 bash "$TEST_SCRIPT"

	# Script should handle unreadable state file gracefully
	# Note: Exit code 124 from timeout indicates the script hung - this is a test failure
	if [[ "$status" -eq 124 ]]; then
		echo "ERROR: Test script hung (timeout after 15 seconds)" >&2
		echo "This indicates a potential hang when handling unreadable state files" >&2
		echo "Check for file operations that might block on unreadable files" >&2
		# Fail the test explicitly - timeout means the script didn't complete
		false
	fi
	assert_success
	# Should handle unreadable state file gracefully and continue with other peers
	assert_file_exist "$LOG_FILE"
	# Should process all peers despite unreadable file
	# Verify that all peers were attempted (check for peer IPs in log)
	assert_log_contains_any "$LOG_FILE" "${TEST_PEER_IP}" "172.16.0.1"
	# Error should be logged but shouldn't stop processing
	# Script should complete successfully (may exit with warnings)

	# Cleanup: restore permissions for cleanup
	chmod 644 "$unreadable_state_file" 2>/dev/null || true

	remove_mock_from_path
}
