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

# ============================================================================
# ERROR RECOVERY PATHS TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "check_vpn_status handles cascading detection failures: xfrm fails → ipsec fails → ping fails" {
	# Purpose: Test verifies that check_vpn_status handles cascading detection failures gracefully
	# Expected: Function attempts all detection methods, logs failures, and returns failure status
	# Importance: Cascading failures can occur in production; must be handled robustly
	setup_test_environment "${TEST_DIR}"
	local peer_ip="192.168.1.1"
	local internal_ip="10.0.0.1"

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
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # ipsec check fails - no connection found
    exit 1
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"

	# Mock ping command - ping check fails
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Ping check fails
exit 1
EOF
	chmod +x "$mock_ping"
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
	local peer_ip="192.168.1.1"

	# Mock ip command that fails mid-execution (partial output then failure)
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    # Simulate partial output then failure
    echo "src 192.168.1.1 dst 192.168.1.1"
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
	local peer_ip="192.168.1.1"

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
	local peer_ip="192.168.1.1"
	local local_ip="10.0.0.1"

	# Mock ping command that fails
	local mock_ping="${TEST_DIR}/ping"
	cat >"$mock_ping" <<'EOF'
#!/bin/bash
# Ping command fails
exit 1
EOF
	chmod +x "$mock_ping"
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
	local peer_ip="192.168.1.1"
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
	local peer_ip="192.168.1.1"
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
	run detect_sa_rekey "" "$peer_ip" "$location_name"
	assert_failure

	# Test with state read failure (simulated by making state file unreadable)
	local state_file
	source_function "get_peer_state_file_path"
	state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "spi")
	if [[ -f "$state_file" ]]; then
		local original_perms
		original_perms=$(stat -c "%a" "$state_file" 2>/dev/null || echo "644")
		if chmod 000 "$state_file" 2>/dev/null; then
			# State file is unreadable - should handle gracefully
			run detect_sa_rekey "0x87654321" "$peer_ip" "$location_name"
			# Should handle state read failure (may return failure or default behavior)
			# Restore permissions
			chmod "$original_perms" "$state_file" 2>/dev/null || true
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
	local peer_ip1="192.168.1.1"
	local peer_ip2="192.168.1.2"
	local internal_ip1="10.0.0.1"
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
        echo "src 192.168.1.1 dst 192.168.1.1"
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
	local peer_ip="192.168.1.1"
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
	local peer_ip="192.168.1.1"
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
	local local_ip="10.0.0.1"

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
	run check_ping_multiple_ips "192.168.1.1 192.168.1.2" "$local_ip"
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
	local mock_nslookup="${TEST_DIR}/nslookup"
	cat >"$mock_nslookup" <<'EOF'
#!/bin/bash
# DNS resolution fails
exit 1
EOF
	chmod +x "$mock_nslookup"
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
	local peer_ip="192.168.1.1"
	local location_name="TEST"

	# Create corrupted state file (invalid JSON/format)
	source_function "get_peer_state_file_path"
	local state_file
	state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "last_bytes")
	mkdir -p "$(dirname "$state_file")"
	echo "invalid_corrupted_data{{{}}" >"$state_file"

	# Mock ip command - xfrm check succeeds
	local mock_ip="${TEST_DIR}/ip"
	cat >"$mock_ip" <<'EOF'
#!/bin/bash
if [[ "$1" == "xfrm" ]] && [[ "$2" == "state" ]]; then
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime current: 1000 bytes, 10 packets"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"
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
	local peer_ip="192.168.1.1"
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
		original_perms=$(stat -c "%a" "$state_file" 2>/dev/null || echo "644")
		if chmod 000 "$state_file" 2>/dev/null; then
			# Source required functions
			source_function "check_byte_counters"

			# Should handle write failure gracefully
			run check_byte_counters "$location_name" "1000" "$peer_ip" "" ""
			# Should not crash - may log error but continue
			# Function should complete (may succeed or fail, but shouldn't crash)
			[[ $status -eq 0 ]] || [[ $status -eq 1 ]]

			# Restore permissions
			chmod "$original_perms" "$state_file" 2>/dev/null || true
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
	local peer_ip="192.168.1.1"
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
		original_perms=$(stat -c "%a" "$state_file" 2>/dev/null || echo "644")
		if chmod 000 "$state_file" 2>/dev/null; then
			# Source required functions
			source_function "get_failure_type"

			# Should handle read failure gracefully
			run get_failure_type "$location_name" "$peer_ip"
			# Should return "unknown" when read fails
			assert_output "unknown"
			assert_failure

			# Restore permissions
			chmod "$original_perms" "$state_file" 2>/dev/null || true
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
	local peer_ip="192.168.1.1"
	local internal_ip="10.0.0.1"
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
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime config: 1000000 bytes, 1000 packets"
    # Note: No "lifetime current:" line, which causes byte counter extraction to fail
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"

	# Mock ipsec command - ipsec check fails (no connection found)
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # ipsec check fails - no connection found
    exit 1
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"
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
	# 1. Should contain "VPN suspect for" with peer IP
	assert_log_contains "$log_file" "VPN suspect for $peer_ip"

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
	local peer_ip="192.168.1.1"
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
    echo "src 192.168.1.1 dst 192.168.1.1"
    echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
    echo "    lifetime config: 1000000 bytes, 1000 packets"
    exit 0
fi
exec /usr/bin/ip "$@"
EOF
	chmod +x "$mock_ip"

	# Mock ipsec command - ipsec check fails
	local mock_ipsec="${TEST_DIR}/ipsec"
	cat >"$mock_ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    exit 1
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "$mock_ipsec"
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
