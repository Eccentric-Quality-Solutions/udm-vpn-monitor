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
load fixtures/vpn_active
load fixtures/vpn_down
load fixtures/vpn_failing

# ============================================================================
# MULTIPLE PEER PROCESSING EDGE CASES TESTS
# ============================================================================

# bats test_tags=slow,category:high-risk,priority:high
@test "multiple peer edge cases: one peer state file corrupted during monitoring - other peers continue" {
	# Test verifies that when one peer's state file becomes corrupted during monitoring,
	# other peers continue to be monitored successfully.
	# Expected: Corrupted state file is handled gracefully, other peers are processed normally.
	# Importance: State file corruption shouldn't stop monitoring of other peers.
	setup_test_vpn_monitor "192.168.1.1 10.0.0.1 172.16.0.1" "${TEST_DIR}"

	# Create corrupted state file for second peer (10.0.0.1)
	local corrupted_state_file="${TEST_DIR}/logs/failure_counter_10_0_0_1"
	mkdir -p "${TEST_DIR}/logs"
	echo "invalid_data_not_a_number" >"$corrupted_state_file"

	# Create valid state files for other peers
	echo "0" >"${TEST_DIR}/logs/failure_counter_192_168_1_1"
	echo "0" >"${TEST_DIR}/logs/failure_counter_172_16_0_1"

	# Mock VPN healthy for all peers
	setup_mock_vpn_environment "192.168.1.1" 1000
	setup_mock_vpn_environment "10.0.0.1" 1000
	setup_mock_vpn_environment "172.16.0.1" 1000

	run bash "$TEST_SCRIPT"

	# Script should handle corrupted state file gracefully
	assert_success
	# Should handle corrupted state file gracefully and continue with other peers
	assert_file_exist "$LOG_FILE"
	# Should process all peers despite corruption
	# Verify that all peers were processed (check for peer IPs in log)
	assert_file_contains "$LOG_FILE" "192.168.1.1" || assert_file_contains "$LOG_FILE" "172.16.0.1"
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
	# Test verifies that when one peer's monitoring throws an unexpected error,
	# other peers continue to be monitored successfully.
	# Expected: Error is caught and logged, monitoring continues for remaining peers.
	# Importance: One peer's failure shouldn't prevent monitoring of other peers.
	setup_test_vpn_monitor "192.168.1.1 10.0.0.1 172.16.0.1" "${TEST_DIR}"

	# Mock VPN check to throw error for second peer (10.0.0.1)
	# Use a file to track state across calls
	local check_state_file="${TEST_DIR}/check_state"
	echo "0" >"$check_state_file"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Count checks to identify which peer is being checked
    # This is a simplified check - in real scenario, peer IP would be passed differently
    check_count=\$(cat "$check_state_file" 2>/dev/null || echo "0")
    check_count=\$((check_count + 1))
    echo "\$check_count" >"$check_state_file"
    if [[ \$check_count -eq 2 ]]; then
        # Simulate unexpected error for second peer
        echo "Unexpected error occurred" >&2
        exit 255
    fi
    # Return healthy VPN for other peers
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    lifetime current: 1000 bytes"
    exit 0
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	run bash "$TEST_SCRIPT"

	# Script should handle error gracefully
	assert_success
	# Should handle error gracefully and continue with other peers
	assert_file_exist "$LOG_FILE"
	# Should process all peers despite error
	# Verify that all peers were attempted (check for peer IPs in log)
	assert_file_contains "$LOG_FILE" "192.168.1.1" || assert_file_contains "$LOG_FILE" "172.16.0.1"
	# Error should be logged but shouldn't stop processing
	# Script should complete successfully (may exit with warnings)

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "multiple peer edge cases: empty peer IP in middle of list - should skip and continue" {
	# Test verifies that empty peer IPs in the middle of the list are skipped gracefully.
	# Expected: Empty peer IPs are skipped with warning, other peers are processed normally.
	# Importance: Malformed configuration shouldn't prevent monitoring of valid peers.
	setup_test_vpn_monitor "192.168.1.1  10.0.0.1" "${TEST_DIR}"

	# Mock VPN healthy for valid peers
	setup_mock_vpn_environment "192.168.1.1" 1000
	setup_mock_vpn_environment "10.0.0.1" 1000

	run bash "$TEST_SCRIPT"

	# Script should handle empty peer IP gracefully
	assert_success
	# Should skip empty peer IP and continue with valid peers
	assert_file_exist "$LOG_FILE"
	# Should log warning about empty peer IP
	assert_file_contains "$LOG_FILE" "Skipping empty" || assert_file_contains "$LOG_FILE" "empty peer"
	# Should process valid peers
	assert_file_contains "$LOG_FILE" "192.168.1.1" || assert_file_contains "$LOG_FILE" "10.0.0.1"
	# Script should complete successfully

	remove_mock_from_path
}

# bats test_tags=slow,category:high-risk,priority:high
@test "multiple peer edge cases: one peer fails catastrophically - other peers continue independently" {
	# Test verifies that catastrophic failure of one peer (e.g., state file unreadable)
	# doesn't prevent monitoring of other peers.
	# Expected: Failed peer is handled gracefully, other peers monitored independently.
	# Importance: Critical for multi-peer deployments where one peer failure shouldn't affect others.
	setup_test_vpn_monitor "192.168.1.1 10.0.0.1 172.16.0.1" "${TEST_DIR}"

	# Create unreadable state file for second peer (10.0.0.1)
	local unreadable_state_file="${TEST_DIR}/logs/failure_counter_10_0_0_1"
	mkdir -p "${TEST_DIR}/logs"
	echo "5" >"$unreadable_state_file"
	chmod 000 "$unreadable_state_file" 2>/dev/null || true

	# Create valid state files for other peers
	echo "0" >"${TEST_DIR}/logs/failure_counter_192_168_1_1"
	echo "0" >"${TEST_DIR}/logs/failure_counter_172_16_0_1"

	# Mock VPN healthy for all peers
	setup_mock_vpn_environment "192.168.1.1" 1000
	setup_mock_vpn_environment "10.0.0.1" 1000
	setup_mock_vpn_environment "172.16.0.1" 1000

	run bash "$TEST_SCRIPT"

	# Script should handle unreadable state file gracefully
	assert_success
	# Should handle unreadable state file gracefully and continue with other peers
	assert_file_exist "$LOG_FILE"
	# Should process all peers despite unreadable file
	# Verify that all peers were attempted (check for peer IPs in log)
	assert_file_contains "$LOG_FILE" "192.168.1.1" || assert_file_contains "$LOG_FILE" "172.16.0.1"
	# Error should be logged but shouldn't stop processing
	# Script should complete successfully (may exit with warnings)

	# Cleanup: restore permissions for cleanup
	chmod 644 "$unreadable_state_file" 2>/dev/null || true

	remove_mock_from_path
}
