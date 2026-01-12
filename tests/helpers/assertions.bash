#!/usr/bin/env bash
#
# Assertion Test Helpers
#
# This module provides custom assertion helpers for tests. It consolidates
# common assertion patterns beyond the standard BATS assertions to reduce
# duplication and ensure consistency across tests.
#
# Usage:
#   load test_helper
#   load helpers/assertions
#
#   # Assert log file contains pattern
#   assert_log_contains "${LOG_FILE}" "VPN is healthy"
#
#   # Assert log file does not contain pattern
#   assert_log_not_contains "${LOG_FILE}" "Error occurred"

# Assert log file contains pattern
#
# Verifies that a log file contains a specific pattern (fixed string match).
# Fails the test if pattern is not found or file doesn't exist.
#
# Arguments:
#   $1: Path to log file
#   $2: Pattern to search for (fixed string, not regex)
#
# Returns:
#   0: Pattern found in log file
#   1: Pattern not found or file doesn't exist (fails test)
#
# Note: Uses BATS_TEST_NAME for better error messages when available
assert_log_contains() {
	local log_file="$1"
	local pattern="$2"

	assert_file_exist "$log_file"

	run grep -Fq -- "$pattern" "$log_file"
	# Use BATS_TEST_NAME in error message if available for better debugging
	if [[ -n "${BATS_TEST_NAME:-}" ]]; then
		assert_success "Log file should contain '$pattern' in test '${BATS_TEST_NAME}'"
	else
		assert_success "Log file should contain: $pattern"
	fi
}

# Assert log file does not contain pattern
#
# Verifies that a log file does NOT contain a specific pattern.
# Succeeds if file doesn't exist (empty file doesn't contain pattern).
# Fails the test if pattern is found.
#
# Arguments:
#   $1: Path to log file
#   $2: Pattern to search for (fixed string, not regex)
#
# Returns:
#   0: Pattern not found (or file doesn't exist)
#   1: Pattern found (fails test)
#
# Note: Uses BATS_TEST_NAME for better error messages when available
assert_log_not_contains() {
	local log_file="$1"
	local pattern="$2"

	if [[ ! -f "$log_file" ]]; then
		return 0 # File doesn't exist, so pattern doesn't exist
	fi

	run grep -Fq -- "$pattern" "$log_file"
	# Use BATS_TEST_NAME in error message if available for better debugging
	if [[ -n "${BATS_TEST_NAME:-}" ]]; then
		assert_failure "Log file should not contain '$pattern' in test '${BATS_TEST_NAME}'"
	else
		assert_failure "Log file should not contain: $pattern"
	fi
}

# Assert log file contains one of multiple patterns
#
# Checks if log file contains at least one of the specified patterns.
# Useful for asserting log messages that may vary slightly.
#
# Arguments:
#   $1: Log file path
#   $2+: Patterns to search for (at least one must match)
#
# Returns:
#   0: At least one pattern found
#   1: No patterns found (fails test)
#
# Note: Uses BATS_TEST_NAME for better error messages when available
#
# Example:
#   assert_log_contains_any "$log_file" "ipsec reload failed" "reload failed"
assert_log_contains_any() {
	local log_file="$1"
	shift
	local patterns=("$@")

	assert_file_exist "$log_file"

	local pattern
	for pattern in "${patterns[@]}"; do
		if grep -Fq -- "$pattern" "$log_file" 2>/dev/null; then
			return 0
		fi
	done

	# No patterns found - fail the test
	local patterns_str
	patterns_str=$(
		IFS="' or '"
		echo "${patterns[*]}"
	)
	# Use BATS_TEST_NAME in error message if available for better debugging
	if [[ -n "${BATS_TEST_NAME:-}" ]]; then
		fail "Log file should contain one of: '$patterns_str' in test '${BATS_TEST_NAME}'"
	else
		fail "Log file should contain one of: '$patterns_str'"
	fi
}
