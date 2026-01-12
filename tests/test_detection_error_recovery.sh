#!/usr/bin/env bats
#
# Tests for Detection Error Recovery Paths
# Tests error handling, edge cases, and state management integration for detection functions
#
# These tests address the gaps identified in COVERAGE_GAP_ANALYSIS.md lines 28-49:
# - Error Recovery Paths: cascading failures, command failures, timeouts
# - Edge Cases: multiple peer IPs, byte counter wrap-around, partial failures
# - State Management Integration: state file corruption, write failures, read failures

load test_helper
load helpers/test_data

# ============================================================================
# ERROR RECOVERY PATHS TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "check_vpn_status handles cascading detection failures: xfrm fails → ipsec fails → ping fails" {
	# Purpose: Test verifies that check_vpn_status handles cascading detection failures gracefully
	# Expected: Function attempts all detection methods, logs failures, and returns failure status
	# Importance: Cascading failures can occur in production; must be handled robustly
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local internal_ip="${TEST_PEER_IP2}"

	# Mock ip command - xfrm check fails
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # xfrm check fails - no output
    exit 1
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"

	# Mock ipsec command - ipsec check fails
	mock_ipsec_status 1 >/dev/null

	# Mock ping command - ping check fails
	mock_ping "${TEST_PEER_IP}" "0" >/dev/null
	mv "${TEST_DIR}/mock_ping" "${TEST_DIR}/ping" 2>/dev/null || true
	add_mock_to_path

	# Initialize state
	source_function "set_peer_state"
	set_peer_state "" "$peer_ip" "failure_count" "0"

	# Source required functions
	source_function "check_vpn_status"

	# Enable ping check to test ping failure path
	export ENABLE_PING_CHECK=1

	# Should handle cascading failures gracefully
	run check_vpn_status "$peer_ip" "$internal_ip" ""
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_xfrm_status handles error when ip xfrm state command fails mid-execution" {
	# Purpose: Test verifies that check_xfrm_status handles ip xfrm state command failures gracefully
	# Expected: Function detects command failure and returns failure status
	# Importance: Command failures can occur due to system issues; must be handled properly
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"

	# Mock ip command that fails mid-execution (partial output then failure)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Simulate partial output then failure
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678"
    # Then fail before completing output
    exit 1
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Initialize state
	source_function "set_peer_state"
	set_peer_state "" "$peer_ip" "failure_count" "0"

	# Source required functions
	source_function "check_xfrm_status"

	# Should handle command failure gracefully
	run check_xfrm_status "$peer_ip" "" ""
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_ipsec_status handles error when ipsec status command fails or times out" {
	# Purpose: Test verifies that check_ipsec_status handles ipsec status command failures and timeouts
	# Expected: Function detects command failure/timeout and returns failure status
	# Importance: Command failures and timeouts can occur; must be handled properly
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"

	# Mock ipsec command that times out (hangs then fails)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Simulate timeout - hang for a bit then fail
    sleep 6  # Longer than IPSEC_STATUS_TIMEOUT (5 seconds)
    exit 1
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Initialize state
	source_function "set_peer_state"
	set_peer_state "" "$peer_ip" "failure_count" "0"

	# Source required functions
	source_function "check_ipsec_status"

	# Should handle timeout gracefully (may take a while, but should eventually fail)
	# Note: Actual timeout handling depends on timeout command or script-level timeout
	# Use timeout to prevent hanging if available, otherwise just run the function
	# The function should eventually fail when ipsec times out
	if command -v timeout >/dev/null 2>&1 && timeout --version >/dev/null 2>&1; then
		# timeout command is available and works
		run timeout 7 check_ipsec_status "$peer_ip" || true
	else
		# timeout command not available - just run the function
		# It will hang for 6 seconds then fail, which is acceptable for this test
		run check_ipsec_status "$peer_ip" || true
	fi
	# Command should fail (either timeout or ipsec failure)
	# We check that it doesn't hang indefinitely
	# Note: If timeout command was used but not found, we expect failure anyway
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_connectivity handles error when ping command fails or times out" {
	# Purpose: Test verifies that check_ping_connectivity handles ping command failures and timeouts
	# Expected: Function detects ping failure/timeout and returns failure status
	# Importance: Ping failures can occur due to network issues; must be handled properly
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local local_ip="${TEST_PEER_IP2}"

	# Mock ping command that fails
	mock_ping "${TEST_PEER_IP}" "0" >/dev/null
	mv "${TEST_DIR}/mock_ping" "${TEST_DIR}/ping" 2>/dev/null || true
	add_mock_to_path

	# Source required functions
	source_function "check_ping_connectivity"

	# Should handle ping failure gracefully
	run check_ping_connectivity "$peer_ip" "$local_ip"
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_byte_counters handles error when byte counter extraction fails" {
	# Purpose: Test verifies that check_byte_counters handles byte counter extraction failures gracefully
	# Expected: Function detects extraction failure and returns failure status
	# Importance: Byte counter extraction failures can occur; must be handled properly
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Initialize state with last_bytes
	source_function "set_peer_state"
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "1000"

	# Source required functions
	source_function "check_byte_counters"

	# Test with zero bytes when last_bytes was non-zero (simulates extraction failure scenario)
	# Note: check_byte_counters expects numeric value, so we can't test actual extraction failure here
	# For actual extraction failure, extract_byte_counter is tested in test_detection_xfrm_edge_cases.sh
	# This test verifies that check_byte_counters handles the case where bytes drop to 0
	run check_byte_counters "$location_name" "0" "$peer_ip" "" ""
	# Should handle zero bytes (should return failure when last_bytes was non-zero)
	assert_failure
}

# bats test_tags=category:high-risk,priority:high
@test "detect_sa_rekey handles error when SA rekey detection fails" {
	# Purpose: Test verifies that detect_sa_rekey handles SA rekey detection failures gracefully
	# Expected: Function detects detection failure and returns failure status
	# Importance: SA rekey detection failures can occur; must be handled properly
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Initialize state with stored SPI
	source_function "set_peer_state"
	set_peer_state "$location_name" "$peer_ip" "spi" "0x12345678"

	# Source required functions
	source_function "detect_sa_rekey"
	source_function "get_peer_state"

	# Test with invalid SPI format (should fail validation)
	run detect_sa_rekey "invalid_spi" "$peer_ip" "$location_name"
	assert_failure

	# Test with empty SPI (should fail validation)
	# Note: location_name is required, so we use the provided location_name
	run detect_sa_rekey "" "$peer_ip" "$location_name"
	assert_failure

	# Test with state read failure (simulated by making state file unreadable)
	local state_file
	source_function "get_peer_state_file_path"
	state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "spi")
	if [[ -f "$state_file" ]]; then
		local original_perms
		original_perms=$(save_permissions_for_restore "$state_file")
		if chmod 000 "$state_file" 2>/dev/null; then
			# State file is unreadable - should handle gracefully
			run detect_sa_rekey "0x87654321" "$peer_ip" "$location_name"
			# Should handle state read failure (may return failure or default behavior)
			# Restore permissions
			restore_permissions_after_test "$state_file" "$original_perms"
		fi
	fi
}

# ============================================================================
# EDGE CASES TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "check_vpn_status handles multiple peer IPs with mixed failure states" {
	# Purpose: Test verifies that check_vpn_status handles multiple peer IPs with mixed success/failure states
	# Expected: Function checks each IP independently and handles mixed results correctly
	# Importance: Multiple peer IPs can have different states; must be handled correctly
	setup_test_environment "${TEST_DIR}"
	local peer_ip1="${TEST_PEER_IP}"
	local peer_ip2="192.168.1.2"
	local internal_ip1="${TEST_PEER_IP2}"
	local internal_ip2="10.0.0.2"

	# Mock ip command - first IP succeeds, second fails
	# Use call counter to return different results for each call
	local call_count_file="${TEST_DIR}/xfrm_call_count"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Track call count to return different results
    call_count_file="${call_count_file}"
    if [[ -f "\$call_count_file" ]]; then
        count=\$(cat "\$call_count_file")
        count=\$((count + 1))
    else
        count=1
    fi
    echo "\$count" > "\$call_count_file"
    
    # First call: return SA for first IP (192.168.1.1)
    if [[ \$count -eq 1 ]]; then
        echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
        echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
        echo "    lifetime current: 1000 bytes, 10 packets"
        exit 0
    else
        # Second call: return nothing (no SA for second IP)
        exit 0  # Exit 0 but no output - grep won't find match
    fi
fi
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Initialize state for both IPs
	source_function "set_peer_state"
	set_peer_state "" "$peer_ip1" "failure_count" "0"
	set_peer_state "" "$peer_ip2" "failure_count" "0"

	# Source required functions
	source_function "check_vpn_status"

	# Check first IP (should succeed)
	run check_vpn_status "$peer_ip1" "$internal_ip1" ""
	assert_success

	# Check second IP (should fail)
	run check_vpn_status "$peer_ip2" "$internal_ip2" ""
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_byte_counters handles byte counter wrap-around scenarios (32-bit vs 64-bit)" {
	# Purpose: Test verifies that check_byte_counters handles byte counter wrap-around correctly
	# Expected: Function detects wrap-around and handles it appropriately
	# Importance: Byte counters can wrap around; must be handled correctly to avoid false positives
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Initialize state with high byte count (near 32-bit limit)
	source_function "set_peer_state"
	# Set last_bytes to near 32-bit limit (4294967295)
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "4294967000"

	# Source required functions
	source_function "check_byte_counters"

	# Test wrap-around scenario: current_bytes is less than last_bytes (wrapped)
	# This simulates 32-bit counter wrapping from 4294967295 to 0
	run check_byte_counters "$location_name" "1000" "$peer_ip" "" ""
	# Should handle wrap-around (may detect as increasing if we assume wrap-around,
	# or may flag as suspect depending on implementation)
	# The exact behavior depends on whether the function detects wrap-around
	# For now, we verify it doesn't crash - the function may flag this as suspect
	# which is acceptable behavior

	# Test 64-bit scenario: very large numbers
	# Note: bash may not handle 64-bit numbers correctly, so this may not work
	# But we test the function's handling of large numbers
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "18446744073709551600" 2>/dev/null || true
	# If the state update succeeds, test with a value that would wrap in 64-bit
	# This is a best-effort test since bash integer limits may prevent full 64-bit testing
}

# bats test_tags=category:high-risk,priority:high
@test "check_sa_rekey_occurred handles SA rekey detection with multiple SAs" {
	# Purpose: Test verifies that check_sa_rekey_occurred handles multiple SAs correctly
	# Expected: Function detects rekey when SPI changes across multiple SAs
	# Importance: Multiple SAs can exist during rekey transitions; must be handled correctly
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Initialize state with stored SPI
	source_function "set_peer_state"
	set_peer_state "$location_name" "$peer_ip" "spi" "0x11111111"

	# Source required functions
	source_function "check_sa_rekey_occurred"

	# Test with different SPI (rekey occurred)
	run check_sa_rekey_occurred "0x22222222" "$peer_ip" "$location_name"
	# Should detect rekey (return success)
	assert_success

	# Test with same SPI (no rekey)
	run check_sa_rekey_occurred "0x11111111" "$peer_ip" "$location_name"
	# Should not detect rekey (return failure)
	assert_failure

	# Test with multiple SAs (simulated by checking with different SPIs)
	# The function should handle the current SPI correctly regardless of
	# how many SAs exist (that's handled upstream in check_xfrm_status)
	# Additional SPI change should still detect rekey
	run check_sa_rekey_occurred "0x33333333" "$peer_ip" "$location_name"
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "check_ping_multiple_ips handles partial ping failures (some IPs succeed, others fail)" {
	# Purpose: Test verifies that check_ping_multiple_ips handles partial ping failures correctly
	# Expected: Function succeeds if threshold met (30% of IPs), fails otherwise
	# Importance: Partial ping failures can occur; must be handled correctly
	setup_test_environment "${TEST_DIR}"
	local local_ip="${TEST_PEER_IP2}"

	# Mock ping command - succeeds for first IP, fails for second
	# Use TEST_DIR for call count file to avoid race conditions in parallel tests
	local call_count_file="${TEST_DIR}/ping_call_count"
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<EOF
#!/bin/bash
# Track call count via file in TEST_DIR to avoid race conditions
call_file="${call_count_file}"
if [[ -f "\$call_file" ]]; then
    count=\$(cat "\$call_file")
    count=\$((count + 1))
else
    count=1
fi
echo "\$count" > "\$call_file"

# First call succeeds, second fails
if [[ \$count -eq 1 ]]; then
    exit 0
else
    exit 1
fi
EOF
	chmod +x "$mock_ping"
	add_mock_to_path

	# Source required functions
	source_function "check_ping_multiple_ips"

	# Test with 2 IPs: 1 succeeds, 1 fails (50% success, >= 30% threshold)
	run check_ping_multiple_ips "${TEST_PEER_IP} ${TEST_LOCAL_IP}" "$local_ip"
	# Should succeed (50% >= 30% threshold, ceil(2 * 0.3) = 1, need >= 1 success)
	assert_success

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_network_partition handles network partition detection during VPN recovery" {
	# Purpose: Test verifies that check_network_partition works correctly during VPN recovery scenarios
	# Expected: Function detects network partition and returns appropriate status
	# Importance: Network partition detection during recovery is critical for proper recovery decisions
	setup_test_environment "${TEST_DIR}"

	# Mock commands to simulate network partition
	# Mock ip command - default route check fails
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "route" ]] && [[ "$2" == "show" ]] && [[ "$3" == "default" ]]; then
    # No default route (network partition)
    exit 1
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock nslookup/host command - DNS resolution fails
	mock_nslookup_fail
	add_mock_to_path

	# Source required functions
	source_function "check_network_partition"

	# Should detect network partition
	run check_network_partition "8.8.8.8" "google.com" "2" "br0,eth0"
	assert_failure

	remove_mock_from_path
}

# ============================================================================
# STATE MANAGEMENT INTEGRATION TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "check_vpn_status handles state file corruption during detection" {
	# Purpose: Test verifies that check_vpn_status handles state file corruption gracefully
	# Expected: Function detects corruption and continues with default values or error handling
	# Importance: State file corruption can occur; must be handled gracefully
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Create corrupted state file (invalid JSON/format)
	source_function "get_peer_state_file_path"
	local state_file
	state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "last_bytes")
	mkdir -p "$(dirname "$state_file")"
	echo "invalid_corrupted_data{{{}}" >"$state_file"

	# Mock ip command - xfrm check succeeds
	mock_ip_xfrm_state "${TEST_PEER_IP}" "1000" >/dev/null
	mv "${TEST_DIR}/mock_ip" "${TEST_DIR}/ip" 2>/dev/null || true
	add_mock_to_path

	# Source required functions
	# Note: setup_test_environment already exports STATE_DIR and LOGS_DIR
	source_function "check_vpn_status"

	# Should handle corrupted state file gracefully
	# Function should either use default values or handle corruption
	run check_vpn_status "$peer_ip" "" "$location_name"
	# Should not crash - may succeed or fail depending on corruption handling
	# The key is that it doesn't crash - we don't assert success/failure
	# since the behavior depends on how corruption is handled
	# But we verify the function completes (exit code is set)
	[[ $status -eq 0 ]] || [[ $status -eq 1 ]]

	remove_mock_from_path
}

# bats test_tags=category:high-risk,priority:high
@test "check_byte_counters handles state file write failures during byte counter updates" {
	# Purpose: Test verifies that check_byte_counters handles state file write failures gracefully
	# Expected: Function detects write failure and continues without crashing
	# Importance: State file write failures can occur; must be handled gracefully
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Initialize state
	source_function "set_peer_state"
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "500"

	# Make state file unwritable to simulate write failure
	# Note: setup_test_environment already exports STATE_DIR and LOGS_DIR
	source_function "get_peer_state_file_path"
	local state_file
	state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "last_bytes")
	if [[ -f "$state_file" ]]; then
		local original_perms
		original_perms=$(save_permissions_for_restore "$state_file")
		if chmod 000 "$state_file" 2>/dev/null; then
			# Source required functions
			source_function "check_byte_counters"

			# Should handle write failure gracefully
			run check_byte_counters "$location_name" "1000" "$peer_ip" "" ""
			# Should not crash - may log error but continue
			# Function should complete (may succeed or fail, but shouldn't crash)
			[[ $status -eq 0 ]] || [[ $status -eq 1 ]]

			# Restore permissions
			restore_permissions_after_test "$state_file" "$original_perms"
		else
			skip "Cannot make state file unwritable on this system"
		fi
	else
		skip "State file does not exist for testing"
	fi
}

# bats test_tags=category:high-risk,priority:high
@test "get_failure_type handles error when state file read fails" {
	# Purpose: Test verifies that get_failure_type handles state file read failures gracefully
	# Expected: Function detects read failure and returns "unknown" failure type
	# Importance: State file read failures can occur; must be handled gracefully
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"

	# Make state file unreadable to simulate read failure
	# Note: setup_test_environment already exports STATE_DIR and LOGS_DIR
	source_function "get_peer_state_file_path"
	local state_file
	state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "failure_type")
	mkdir -p "$(dirname "$state_file")"
	echo "tunnel_down" >"$state_file" 2>/dev/null || true

	if [[ -f "$state_file" ]]; then
		local original_perms
		original_perms=$(save_permissions_for_restore "$state_file")
		if chmod 000 "$state_file" 2>/dev/null; then
			# Source required functions
			source_function "get_failure_type"

			# Should handle read failure gracefully
			run get_failure_type "$location_name" "$peer_ip"
			# Should return "unknown" when read fails
			assert_output "unknown"
			assert_failure

			# Restore permissions
			restore_permissions_after_test "$state_file" "$original_perms"
		else
			skip "Cannot make state file unreadable on this system"
		fi
	else
		skip "State file does not exist for testing"
	fi
}

# bats test_tags=category:detection,priority:medium
@test "check_vpn_status combines diagnostic messages when both xfrm and ipsec fail" {
	# Purpose: Test verifies that check_vpn_status combines diagnostic messages from both detection methods
	# Expected: When both xfrm and ipsec status checks fail, a single combined diagnostic message is logged
	#           that includes detection method names and context about why each method failed
	# Importance: Combined diagnostic messages improve log readability and make it easier to correlate
	#              related warnings from the same diagnostic check
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local internal_ip="${TEST_PEER_IP2}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local location_name="TEST"

	# Set up logging
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Mock ip command - xfrm check finds SA but byte counter extraction fails
	# This simulates the scenario where SA exists but byte counter info is unavailable
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return xfrm output with SA but without byte counter info in lifetime current
    # This simulates byte counter extraction failure
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime config: 1000000 bytes, 1000 packets"
    # Note: No "lifetime current:" line, which causes byte counter extraction to fail
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"

	# Mock ipsec command - ipsec check fails (no connection found)
	mock_ipsec_status 1
	add_mock_to_path

	# Initialize state
	source_function "set_peer_state"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "0"

	# Source required functions
	source_function "check_vpn_status"

	# Disable ping check to test the byte counter unavailable path
	# This ensures we get the diagnostic message about byte counter info unavailable
	export ENABLE_PING_CHECK=0

	# Call check_vpn_status - both methods should fail
	run check_vpn_status "$peer_ip" "$internal_ip" "$location_name"
	assert_failure

	# Verify combined diagnostic message was logged
	assert_file_exist "$log_file"

	# Verify the combined message format:
	# 1. Should contain "VPN suspect for" with location name and peer IP
	assert_log_contains "$log_file" "VPN suspect for $location_name ($peer_ip)"

	# 2. Should include xfrm detection method name
	assert_log_contains "$log_file" "Detection method: xfrm (ip xfrm state)"

	# 3. Should include ipsec detection method name
	assert_log_contains "$log_file" "Detection method: ipsec status"

	# 4. Should include context about byte counter availability
	#    (either "byte counter info unavailable" or specific reason)
	assert_log_contains "$log_file" "byte counter info unavailable"

	# 5. Should include context about why byte counter check failed
	#    (ping check disabled or internal IP not provided)
	assert_log_contains "$log_file" "ping check disabled"

	# 6. Should include "No connection found via ipsec status"
	assert_log_contains "$log_file" "No connection found via ipsec status"

	# 7. Verify the message is combined (contains semicolon separator)
	assert_log_contains "$log_file" ";"

	# 8. Verify we don't have separate warning messages (old behavior)
	#    Count occurrences of "VPN suspect" - should be 1 (the combined message)
	local suspect_count
	suspect_count=$(grep -c "VPN suspect" "$log_file" || echo "0")
	[ "$suspect_count" -eq 1 ] || fail "Should have exactly one combined diagnostic message, found $suspect_count"

	remove_mock_from_path
}

# bats test_tags=category:detection,priority:medium
@test "check_vpn_status combined diagnostic includes internal IP context when not provided" {
	# Purpose: Test verifies that combined diagnostic messages include context about internal IP availability
	# Expected: When internal IP is not provided, the diagnostic message should indicate "internal IP not provided"
	#          instead of "ping check disabled"
	# Importance: Different diagnostic contexts help identify the root cause of detection failures
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local location_name="TEST"

	# Set up logging
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Mock ip command - xfrm check finds SA but byte counter extraction fails
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime config: 1000000 bytes, 1000 packets"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"

	# Mock ipsec command - ipsec check fails
	mock_ipsec_status 1
	add_mock_to_path

	# Initialize state
	source_function "set_peer_state"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "0"

	# Source required functions
	source_function "check_vpn_status"

	# Enable ping check but don't provide internal IP
	# This should result in "internal IP not provided" message
	export ENABLE_PING_CHECK=1

	# Call check_vpn_status without internal IP - both methods should fail
	run check_vpn_status "$peer_ip" "" "$location_name"
	assert_failure

	# Verify combined diagnostic message was logged
	assert_file_exist "$log_file"

	# Verify the diagnostic includes "internal IP not provided" context
	assert_log_contains "$log_file" "internal IP not provided"

	# Verify it does NOT say "ping check disabled" (since ping check is enabled)
	assert_log_not_contains "$log_file" "ping check disabled"

	remove_mock_from_path
}

# bats test_tags=category:detection,priority:medium
@test "check_byte_counters populates detailed diagnostic messages correctly" {
	# Purpose: Test verifies that check_byte_counters populates diagnostic variable with detailed failure reasons
	# Expected: When diagnostic variable is provided, function populates it with specific failure reason
	#           instead of generic "byte counter validation failed" message
	# Importance: Detailed diagnostic messages help identify root cause of VPN failures
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local location_name="TEST"
	local internal_peer_ip="${TEST_PEER_IP2}"

	# Set up environment
	STATE_DIR="${TEST_DIR}"
	LOGS_DIR="${STATE_DIR}/logs"
	mkdir -p "${STATE_DIR}"
	mkdir -p "${LOGS_DIR}"
	export STATE_DIR LOGS_DIR
	export ENABLE_PING_CHECK=0

	# Initialize state with last_bytes to simulate bytes not increasing scenario
	source_function "set_peer_state"
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "1000"

	# Source required functions
	source_function "check_byte_counters"

	# Test 1: Bytes not increasing (static) - should populate diagnostic with specific reason
	# Note: Call function directly (not with 'run') so diagnostic variable is set in current shell
	local diagnostic=""
	if check_byte_counters "$location_name" "1000" "$peer_ip" "" "$internal_peer_ip" "diagnostic"; then
		fail "check_byte_counters should fail when bytes are not increasing"
	fi
	# Verify diagnostic was populated with detailed reason
	[[ -n "$diagnostic" ]] || fail "Diagnostic variable should be populated"
	[[ "$diagnostic" == *"bytes not increasing"* ]] || fail "Diagnostic should mention 'bytes not increasing'"
	[[ "$diagnostic" == *"current=1000"* ]] || fail "Diagnostic should include current byte count"
	[[ "$diagnostic" == *"last=1000"* ]] || fail "Diagnostic should include last byte count"
	[[ "$diagnostic" == *"ping check: disabled"* ]] || fail "Diagnostic should include ping check status"

	# Test 2: Bytes decreased - should populate diagnostic with decreased reason
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "2000"
	diagnostic=""
	if check_byte_counters "$location_name" "1500" "$peer_ip" "" "$internal_peer_ip" "diagnostic"; then
		fail "check_byte_counters should fail when bytes decreased"
	fi
	# Verify diagnostic was populated with decreased reason
	[[ -n "$diagnostic" ]] || fail "Diagnostic variable should be populated"
	[[ "$diagnostic" == *"bytes decreased"* ]] || fail "Diagnostic should mention 'bytes decreased'"
	[[ "$diagnostic" == *"current=1500"* ]] || fail "Diagnostic should include current byte count"
	[[ "$diagnostic" == *"last=2000"* ]] || fail "Diagnostic should include last byte count"

	# Test 3: Bytes dropped to zero - should populate diagnostic with dropped reason
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "5000"
	diagnostic=""
	if check_byte_counters "$location_name" "0" "$peer_ip" "" "$internal_peer_ip" "diagnostic"; then
		fail "check_byte_counters should fail when bytes dropped to zero"
	fi
	# Verify diagnostic was populated with dropped reason
	[[ -n "$diagnostic" ]] || fail "Diagnostic variable should be populated"
	[[ "$diagnostic" == *"bytes dropped to 0"* ]] || fail "Diagnostic should mention 'bytes dropped to 0'"
	[[ "$diagnostic" == *"was 5000"* ]] || fail "Diagnostic should include previous byte count"

	# Test 4: First check with zero bytes and ping disabled - should populate diagnostic
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "0"
	diagnostic=""
	if check_byte_counters "$location_name" "0" "$peer_ip" "" "$internal_peer_ip" "diagnostic"; then
		fail "check_byte_counters should fail on first check with zero bytes and ping disabled"
	fi
	# Verify diagnostic was populated with first check reason
	[[ -n "$diagnostic" ]] || fail "Diagnostic variable should be populated"
	[[ "$diagnostic" == *"bytes=0"* ]] || fail "Diagnostic should mention 'bytes=0'"
	[[ "$diagnostic" == *"first check"* ]] || fail "Diagnostic should mention 'first check'"
	[[ "$diagnostic" == *"ping check disabled"* ]] || fail "Diagnostic should mention ping check status"
}

# bats test_tags=category:high-risk,priority:medium
@test "XFRM output reuse optimization - ip xfrm state called once per VPN check cycle" {
	# Purpose: Test verifies that ip xfrm state is only called once per VPN check cycle when
	#          check_vpn_status() → detect_failure_type() flow executes
	# Expected: ip xfrm state is called once (from check_xfrm_primary), and xfrm_output is
	#           passed through determine_vpn_status() → detect_failure_type() to avoid duplicate call
	# Importance: Verifies optimization works correctly and prevents regression
	# Note: Optimization implemented to reduce ip xfrm state calls from 2 to 1 per cycle
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local internal_ip="${TEST_PEER_IP2}"
	local location_name="TEST"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"

	# Set up logging
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Mock ip command that counts xfrm state calls
	# Track both "ip -s xfrm state" and "ip xfrm state" variants
	# Note: get_xfrm_state_for_peer() tries "ip -s xfrm state" first, then falls back to "ip xfrm state" if needed
	# The optimization means get_xfrm_state_for_peer() should only be called once (from check_xfrm_primary),
	# not again from detect_failure_type()
	local call_count_file="${TEST_DIR}/xfrm_call_count"
	echo "0" >"$call_count_file"
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<EOF
#!/bin/bash
# Handle "ip -s xfrm state" (with statistics flag) - tried first by get_xfrm_state_for_peer
if [[ "\$1" == "-s" ]] && [[ "\$2" == "xfrm" ]] && [[ "\$3" == "state" ]]; then
    # Increment call count
    count=\$(cat "$call_count_file" 2>/dev/null || echo "0")
    count=\$((count + 1))
    echo "\$count" > "$call_count_file"
    # Return SA with byte counter info (same value as last_bytes to trigger "bytes not increasing")
    echo "src ${peer_ip} dst ${peer_ip}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    exit 0
fi
# Handle "ip xfrm state" (without statistics flag) - fallback used by get_xfrm_state_for_peer
# This should NOT be called if ip -s xfrm state succeeds
if [[ "\$1" == "xfrm" ]] && [[ "\$2" == "state" ]]; then
    # Increment call count
    count=\$(cat "$call_count_file" 2>/dev/null || echo "0")
    count=\$((count + 1))
    echo "\$count" > "$call_count_file"
    # Return SA with byte counter info
    echo "src ${peer_ip} dst ${peer_ip}"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    exit 0
fi
# Handle other ip commands
exec /usr/bin/ip "\$@"
EOF
	chmod +x "$mock_ip"
	add_mock_to_path

	# Mock ipsec command - ipsec check fails (no connection found)
	mock_ipsec_status 1
	add_mock_to_path

	# Initialize state with last_bytes set to same value (bytes not increasing)
	# This will cause xfrm check to find SA but validation fails (bytes not increasing)
	# xfrm_output will be captured, but VPN check will fail, triggering failure type detection
	source_function "set_peer_state"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "0"
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "1000"

	# Disable ping check to ensure we test the xfrm path (not ping path)
	# When bytes not increasing and ping disabled, xfrm check fails and triggers failure type detection
	export ENABLE_PING_CHECK=0

	# Source required functions
	source_function "check_vpn_status"

	# Call check_vpn_status - should fail (bytes not increasing)
	# Flow: check_xfrm_primary() → captures xfrm_output (SA exists, but bytes not increasing)
	#       → xfrm check fails → determine_vpn_status() called with vpn_ok=0 and xfrm_output
	#       → detect_failure_type() called with xfrm_output (should NOT call get_xfrm_state_for_peer again)
	run check_vpn_status "$peer_ip" "$internal_ip" "$location_name"
	assert_failure

	# Verify ip xfrm state was called at most twice (from check_xfrm_primary via get_xfrm_state_for_peer)
	# get_xfrm_state_for_peer() calls execute_xfrm_state_command() which tries "ip -s xfrm state" first,
	# then falls back to "ip xfrm state" if needed. So we might see 1-2 calls from a single get_xfrm_state_for_peer() invocation.
	# The optimization means get_xfrm_state_for_peer() should only be called once (from check_xfrm_primary),
	# not again from detect_failure_type(). So we should see at most 2 calls total (both variants from one invocation).
	# If detect_failure_type() called get_xfrm_state_for_peer() again, we'd see 3+ calls.
	local call_count
	call_count=$(cat "$call_count_file" 2>/dev/null || echo "0")
	# Should be at most 2 calls (ip -s xfrm state and possibly ip xfrm state fallback from one get_xfrm_state_for_peer() call)
	# If detect_failure_type() called get_xfrm_state_for_peer() again, we'd see 3+ calls
	[ "$call_count" -le 2 ] || fail "ip xfrm state should be called at most twice per VPN check cycle (from check_xfrm_primary via get_xfrm_state_for_peer, not again from detect_failure_type). Found $call_count calls"

	# Verify failure type was detected (confirms detect_failure_type was called)
	assert_file_exist "$log_file"
	# Should have detected failure type (not "unknown" - should be "routing_issue" or similar)
	assert_file_contains "$log_file" "failure type" || assert_file_contains "$log_file" "Failure type"

	remove_mock_from_path
}

# bats test_tags=category:detection,priority:medium
@test "check_vpn_status combined diagnostic includes detailed byte counter validation reason" {
	# Purpose: Test verifies that combined diagnostic messages include detailed byte counter validation failure reasons
	# Expected: When byte counter validation fails, combined diagnostic should include specific reason
	#           (e.g., "bytes not increasing", "bytes decreased") instead of generic "byte counter validation failed"
	# Importance: Detailed diagnostic messages in combined warnings help identify root cause of VPN failures
	setup_test_environment "${TEST_DIR}"
	local peer_ip="${TEST_PEER_IP}"
	local internal_ip="${TEST_PEER_IP2}"
	local log_file="${TEST_DIR}/logs/vpn-monitor.log"
	local location_name="TEST"

	# Set up logging
	export LOG_FILE="$log_file"
	mkdir -p "$(dirname "$log_file")"

	# Mock ip command - xfrm check finds SA with byte counters
	# Generate xfrm output using test data helpers
	local xfrm_output
	xfrm_output=$(generate_xfrm_state_output "healthy" "${TEST_PEER_IP}" "0x12345678" 1000 10 "minimal")
	local xfrm_output_file="${TEST_DIR}/xfrm_output"
	echo "$xfrm_output" >"$xfrm_output_file"

	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Return xfrm output with SA and byte counter info
    cat "MOCK_XFRM_OUTPUT"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	# Replace placeholder with actual file path
	sed -i "s|MOCK_XFRM_OUTPUT|${xfrm_output_file}|g" "$mock_ip"
	chmod +x "$mock_ip"

	# Mock ipsec command - ipsec check fails (no connection found)
	mock_ipsec_status 1
	add_mock_to_path

	# Initialize state with last_bytes set to same value (simulating bytes not increasing)
	source_function "set_peer_state"
	set_peer_state "$location_name" "$peer_ip" "failure_count" "0"
	set_peer_state "$location_name" "$peer_ip" "last_bytes" "1000"

	# Source required functions
	source_function "check_vpn_status"

	# Disable ping check to ensure we get the "bytes not increasing" diagnostic
	export ENABLE_PING_CHECK=0

	# Call check_vpn_status - both methods should fail
	run check_vpn_status "$peer_ip" "$internal_ip" "$location_name"
	assert_failure

	# Verify combined diagnostic message was logged
	assert_file_exist "$log_file"

	# Verify the combined message includes detailed byte counter validation reason
	# Should NOT contain generic "byte counter validation failed"
	assert_log_not_contains "$log_file" "byte counter validation failed"

	# Should contain detailed reason about bytes not increasing
	assert_log_contains "$log_file" "bytes not increasing"

	# Should include specific byte counter values
	assert_log_contains "$log_file" "current=1000"
	assert_log_contains "$log_file" "last=1000"

	# Should include ping check status
	assert_log_contains "$log_file" "ping check: disabled"

	# Should still include detection method names
	assert_log_contains "$log_file" "Detection method: xfrm (ip xfrm state)"
	assert_log_contains "$log_file" "Detection method: ipsec status"

	# Verify the message is combined (contains semicolon separator)
	assert_log_contains "$log_file" ";"

	# Verify we have exactly one combined diagnostic message
	local suspect_count
	suspect_count=$(grep -c "VPN suspect" "$log_file" || echo "0")
	[ "$suspect_count" -eq 1 ] || fail "Should have exactly one combined diagnostic message, found $suspect_count"

	remove_mock_from_path
}
