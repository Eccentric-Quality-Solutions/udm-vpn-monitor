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

# Override calculate_duration to use time_increment_file for time-based testing
#
# Overrides the calculate_duration function after sourcing recovery module to use
# a time increment file for deterministic time-based testing. This allows tests
# to control elapsed time by incrementing a value in a file.
#
# Arguments:
#   $1: Path to time increment file (file should contain elapsed seconds as integer)
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Overrides calculate_duration function in current shell
#   - Function reads from time_increment_file to determine elapsed time
#
# Example:
#   local time_increment_file="${TEST_DIR}/time_increment"
#   echo "0" >"$time_increment_file"
#   source_recovery_module
#   override_calculate_duration_with_increment "$time_increment_file"
#   # Now calculate_duration will return value from time_increment_file
#
# Note:
#   Must be called after source_recovery_module since it overrides a function
#   from the sourced module.
override_calculate_duration_with_increment() {
	local time_increment_file="$1"
	# shellcheck disable=SC2329,SC2034
	# This function overrides calculate_duration in test context (not called here)
	# Variables match original function signature but we use time_increment_file instead
	calculate_duration() {
		local start_time="$1"
		local end_time="${2:-$(get_unix_timestamp)}"
		local increment
		increment=$(cat "${time_increment_file}" 2>/dev/null || echo "0")
		local elapsed=$((increment))
		if [[ $elapsed -lt 0 ]]; then
			elapsed=0
		fi
		echo "$elapsed"
		return 0
	}
}

# Override calculate_duration to always return 0 (simulates time calculation failure)
#
# Overrides the calculate_duration function to always return 0, simulating a
# time calculation failure. This is useful for testing iteration limits when
# time calculation fails.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
#
# Side effects:
#   - Overrides calculate_duration function in current shell
#
# Example:
#   source_recovery_module
#   override_calculate_duration_always_zero
#   # Now calculate_duration always returns 0
#
# Note:
#   Must be called after source_recovery_module since it overrides a function
#   from the sourced module.
override_calculate_duration_always_zero() {
	# shellcheck disable=SC2329
	# This function overrides calculate_duration in test context (not called here)
	calculate_duration() {
		# Always return 0 (time calculation failed)
		echo "0"
		return 0
	}
}

# Set up common mocks for retry_xfrm_recovery tests
#
# Creates common mock commands needed for testing retry_xfrm_recovery function.
# This includes mocks for format_peer_ip_display, log_message, handle_error,
# and clear_recovery_method.
#
# Arguments:
#   $1: Optional path to log file (default: ${TEST_DIR}/vpn-monitor.log)
#
# Returns:
#   0: Always succeeds
#
# Output:
#   Prints path to log file (for use in tests)
#
# Side effects:
#   - Creates mock commands in TEST_DIR
#   - Mocks are not added to PATH (call add_mock_to_path after this)
#
# Example:
#   local log_file
#   log_file=$(setup_retry_xfrm_recovery_mocks)
#   add_mock_to_path
#   # Now mocks are available in PATH
setup_retry_xfrm_recovery_mocks() {
	local log_file="${1:-${TEST_DIR}/vpn-monitor.log}"

	# Mock format_peer_ip_display
	local mock_format_ip="${TEST_DIR}/format_peer_ip_display"
	cat >"$mock_format_ip" <<'EOF'
#!/bin/bash
echo "$1"
EOF
	chmod +x "$mock_format_ip"

	# Mock log_message
	local mock_log="${TEST_DIR}/log_message"
	cat >"$mock_log" <<EOF
#!/bin/bash
echo "\$*" >> "${log_file}"
EOF
	sed -i "s|log_file|${log_file}|g" "$mock_log"
	chmod +x "$mock_log"

	# Mock handle_error
	local mock_handle_error="${TEST_DIR}/handle_error"
	cat >"$mock_handle_error" <<EOF
#!/bin/bash
echo "\$*" >> "${log_file}"
EOF
	sed -i "s|log_file|${log_file}|g" "$mock_handle_error"
	chmod +x "$mock_handle_error"

	# Mock clear_recovery_method
	local mock_clear_recovery="${TEST_DIR}/clear_recovery_method"
	cat >"$mock_clear_recovery" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$mock_clear_recovery"

	echo "$log_file"
}
