#!/usr/bin/env bash
#
# Recovery Test Helpers
#
# This module provides helpers for testing VPN recovery functionality.
# It consolidates common patterns for setting up recovery test environments
# and generating mock xfrm state output for recovery scenarios.
#
# Usage:
#   load test_helper
#   load helpers/recovery
#
#   # Generate xfrm state output for recovery testing
#   generate_xfrm_state_output 1

# Generate xfrm state output for recovery testing
#
# Generates mock xfrm state output that simulates different phases of
# recovery: SA exists, SA deleted, SA re-established. The output varies
# based on the verification attempt number.
#
# This is a standalone function for use in test code. For mock scripts that
# need to generate xfrm state output, define the function inline within the
# mock script (see test_recovery.sh for examples of embedded functions in
# mock scripts).
#
# Arguments:
#   $1: Verification attempt number (determines which phase to simulate)
#       - 1: SA exists (before deletion)
#       - 2-3: SA deleted (empty output)
#       - 4+: SA re-established with incrementing byte counters
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints xfrm state output to stdout (or empty for deleted phase)
#
# Side effects:
#   None (pure function that only outputs)
#
# Example:
#   # Use directly in test code
#   generate_xfrm_state_output 1
#   # Output: SA exists with initial counters
#
#   generate_xfrm_state_output 2
#   # Output: (empty - SA deleted)
#
#   generate_xfrm_state_output 4
#   # Output: SA re-established with byte counter 2000
#
# Note:
#   This function uses TEST_PEER_IP which must be set in the test environment.
#   For mock scripts, define the function inline with escaped variables as needed.
generate_xfrm_state_output() {
	local verify_attempts="$1"
	# First call: SA exists (before deletion)
	if [[ $verify_attempts -eq 1 ]]; then
		echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
		echo "    proto esp spi 0x12345678 reqid 1 mode tunnel"
		echo "    lifetime current:"
		echo "      1000(bytes), 10(packets)"
		echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
	# Next few calls: SA deleted
	elif [[ $verify_attempts -le 3 ]]; then
		: # Empty output (SA deleted)
	# After that: SA re-established with incrementing byte counters
	# Attempt 4: initial counter (2000 bytes) - captured as baseline
	# Attempt 5+: incrementing counters (2100, 2200, etc.) - verification succeeds
	else
		# Calculate byte counter: 2000 + (attempt - 4) * 100
		# This ensures counter increments after initial capture
		local byte_counter=$((2000 + (verify_attempts - 4) * 100))
		local packet_counter=$((20 + (verify_attempts - 4) * 10))
		echo "src ${TEST_PEER_IP} dst ${TEST_PEER_IP}"
		echo "    proto esp spi 0x87654321 reqid 1 mode tunnel"
		echo "    lifetime current:"
		echo "      ${byte_counter}(bytes), ${packet_counter}(packets)"
		echo "    sel src 0.0.0.0/0 dst 0.0.0.0/0"
	fi
}
