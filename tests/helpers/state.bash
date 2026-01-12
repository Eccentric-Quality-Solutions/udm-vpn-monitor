#!/usr/bin/env bash
#
# State Management Test Helpers
#
# This module provides helpers for testing state management functionality.
# It consolidates common patterns for working with state files, verifying
# state file contents, and setting up state-related test scenarios.
#
# Usage:
#   load test_helper
#   load helpers/state
#
#   # Ensure state functions are loaded
#   ensure_state_functions_loaded
#
#   # Get state file path
#   local state_file
#   state_file=$(get_state_file_path "TEST" "${TEST_PEER_IP}" "failure_count")
#
#   # Assert state file exists and contains value
#   assert_state_file "$state_file" "5"

# Assert state file exists and contains value
#
# Verifies that a state file exists and contains the expected value.
# Used to check failure counters, restart counts, and other state files.
#
# Arguments:
#   $1: Path to state file
#   $2: Expected value (exact match)
#
# Returns:
#   0: File exists and contains expected value
#   1: File doesn't exist or contains different value (fails test)
assert_state_file() {
	local state_file="$1"
	local expected_value="$2"

	assert_file_exist "$state_file"
	run cat "$state_file"
	assert_success
	assert_output "$expected_value"
}

# Ensure state functions are loaded
#
# Ensures that state management functions (set_peer_state, get_peer_state, etc.)
# are available in the current shell. Sources lib/state.sh if needed.
# Safe to call multiple times (idempotent).
#
# Returns:
#   0: Always succeeds (state functions available or sourced)
#
# Side effects:
#   - Sources lib/state.sh if set_peer_state is not available
#   - Sets up required environment variables (STATE_DIR, LOGS_DIR) if not set
#
# Example:
#   ensure_state_functions_loaded
#   set_peer_state "TEST" "192.168.1.1" "failure_count" "5"
#
# Note:
#   Uses 2>/dev/null || true to suppress errors if state.sh is not found
#   (for maximum compatibility in test environments)
ensure_state_functions_loaded() {
	# Check if state functions are already available
	if command -v set_peer_state >/dev/null 2>&1; then
		return 0
	fi

	# Set up required environment variables if not already set
	STATE_DIR="${STATE_DIR:-${TEST_DIR:-/tmp}}"
	export STATE_DIR
	LOGS_DIR="${LOGS_DIR:-${STATE_DIR}/logs}"
	export LOGS_DIR

	# Source logging.sh first (state.sh requires handle_error from logging.sh)
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true

	# Source state.sh
	# shellcheck source=../lib/state.sh
	source "${BATS_TEST_DIRNAME}/../lib/state.sh" 2>/dev/null || true
}

# Get state file path with common defaults
#
# Helper function that wraps get_peer_state_file_path with sensible defaults
# to reduce repetition in tests. Uses TEST_PEER_IP as default peer IP and
# "TEST" as default location name.
#
# Arguments:
#   $1: Optional location name (defaults to "TEST")
#   $2: Optional peer IP address (defaults to TEST_PEER_IP)
#   $3: Optional state key (defaults to "failure_count")
#
# Returns:
#   Outputs the state file path
#   Returns 0 on success, 1 on failure
#
# Side effects:
#   Sources get_peer_state_file_path function if not available
#
# Example:
#   source_function "get_peer_state_file_path"
#   local failure_counter
#   failure_counter=$(get_state_file_path)
#   # or with custom values:
#   failure_counter=$(get_state_file_path "NYC" "${TEST_PEER_IP}" "last_bytes")
#
# Note:
#   Requires get_peer_state_file_path function to be available.
#   Automatically sources it if not already loaded.
get_state_file_path() {
	local location="${1:-TEST}"
	local peer_ip="${2:-${TEST_PEER_IP}}"
	local key="${3:-failure_count}"

	# Ensure get_peer_state_file_path is available
	if ! command -v get_peer_state_file_path >/dev/null 2>&1; then
		source_function "get_peer_state_file_path" || return 1
	fi

	get_peer_state_file_path "$location" "$peer_ip" "$key"
}

# Test peer state with location
#
# Helper function that encapsulates the common test pattern of:
# - Calling set_peer_state with location name
# - Getting the file path using get_peer_state_file_path
# - Asserting file existence
#
# This reduces duplication across tests that need to verify peer state file creation.
#
# Arguments:
#   $1: Peer IP address
#   $2: State key (e.g., "failure_count", "last_bytes", "spi")
#   $3: Value to set
#   $4: Optional location name (defaults to "TEST")
#   $5: Optional expected value to verify (if not provided, only existence is checked)
#
# Returns:
#   0: File exists (and optionally matches expected value)
#   1: File doesn't exist or value mismatch (fails test)
#
# Side effects:
#   - Calls set_peer_state with location name
#   - Creates state file
#   - Asserts file existence
#   - Optionally verifies file content
#
# Example:
#   # Basic usage - just verify file exists
#   source_function "set_peer_state"
#   source_function "get_peer_state_file_path"
#   test_peer_state "192.168.1.1" "failure_count" "5"
#
#   # With value verification and custom location
#   source_function "set_peer_state"
#   source_function "get_peer_state_file_path"
#   test_peer_state "192.168.1.1" "failure_count" "5" "NYC" "5"
#
# Note:
#   Requires set_peer_state and get_peer_state_file_path functions to be sourced
#   before calling this helper. Tests should source these functions first.
test_peer_state() {
	local peer_ip="$1"
	local key="$2"
	local value="$3"
	local location_name="${4:-TEST}"
	local expected_value="${5:-}"

	# Set peer state with location name
	run set_peer_state "$location_name" "$peer_ip" "$key" "$value"
	assert_success

	# Get file path using get_peer_state_file_path
	local state_file
	state_file=$(get_peer_state_file_path "$location_name" "$peer_ip" "$key")

	# Assert file exists
	assert_file_exist "$state_file"

	# If expected value provided, verify file content
	if [[ -n "$expected_value" ]]; then
		local file_content
		file_content=$(cat "$state_file")
		assert_equal "$file_content" "$expected_value"
	fi
}

# Create a corrupted state file
#
# Helper function that creates a state file with an invalid value to test
# corruption handling. Reduces repetition of the common pattern of creating
# corrupted state files in tests.
#
# Arguments:
#   $1: Optional location name (defaults to "TEST")
#   $2: Optional peer IP address (defaults to TEST_PEER_IP)
#   $3: Optional state key (defaults to "failure_count")
#   $4: Optional invalid value to write (defaults to "invalid-value")
#
# Returns:
#   Outputs the state file path
#   Returns 0 on success, 1 on failure
#
# Side effects:
#   Creates or overwrites the state file with invalid content
#   Sources get_peer_state_file_path function if not available
#
# Example:
#   source_function "get_peer_state_file_path"
#   local failure_counter
#   failure_counter=$(create_corrupted_state_file)
#   # or with custom values:
#   local bytes_file
#   bytes_file=$(create_corrupted_state_file "NYC" "${TEST_PEER_IP}" "last_bytes" "not-a-number")
#
# Note:
#   Requires get_peer_state_file_path function to be available.
#   Automatically sources it if not already loaded.
create_corrupted_state_file() {
	local location="${1:-TEST}"
	local peer_ip="${2:-${TEST_PEER_IP}}"
	local key="${3:-failure_count}"
	local invalid_value="${4:-invalid-value}"

	# Get the state file path
	local state_file
	state_file=$(get_state_file_path "$location" "$peer_ip" "$key") || return 1

	# Create corrupted file
	echo "$invalid_value" >"$state_file"

	# Return the path for use in tests
	echo "$state_file"
}

# Setup a read-only state file with automatic cleanup
#
# Helper function that creates a state file, sets it to read-only, and sets up
# a trap to restore permissions on EXIT. Reduces repetition of the common pattern
# of testing read-only state file handling.
#
# Arguments:
#   $1: Optional location name (defaults to "TEST")
#   $2: Optional peer IP address (defaults to TEST_PEER_IP)
#   $3: Optional state key (defaults to "failure_count")
#   $4: Optional initial value to write (defaults to "3")
#   $5: Optional permissions to set (defaults to "444" for read-only)
#
# Returns:
#   Outputs the state file path
#   Returns 0 on success, 1 on failure
#
# Side effects:
#   Creates the state file with initial value
#   Sets file permissions to read-only (or specified permissions)
#   Sets up EXIT trap to restore original permissions
#   Sources get_peer_state_file_path function if not available
#
# Example:
#   source_function "get_peer_state_file_path"
#   local failure_counter
#   failure_counter=$(setup_readonly_state_file)
#   # File is now read-only and will be restored on test exit
#   # or with custom values:
#   local bytes_file
#   bytes_file=$(setup_readonly_state_file "NYC" "${TEST_PEER_IP}" "last_bytes" "1000" "000")
#
# Note:
#   Requires get_peer_state_file_path function to be available.
#   Automatically sources it if not already loaded.
#   The trap is set up automatically and will restore permissions even if test fails.
setup_readonly_state_file() {
	local location="${1:-TEST}"
	local peer_ip="${2:-${TEST_PEER_IP}}"
	local key="${3:-failure_count}"
	local initial_value="${4:-3}"
	local readonly_perms="${5:-444}"

	# Get the state file path
	local state_file
	state_file=$(get_state_file_path "$location" "$peer_ip" "$key") || return 1

	# Ensure parent directory exists
	local parent_dir
	parent_dir=$(dirname "$state_file")
	mkdir -p "$parent_dir" || return 1

	# Remove existing file if it exists to ensure clean state
	rm -f "$state_file"

	# Create file with initial value and set permissions in one step using install
	# This ensures the file is created with the correct permissions from the start
	printf '%s' "$initial_value" | install -m "$readonly_perms" /dev/stdin "$state_file" || {
		# Fallback to echo + chmod if install fails
		echo "$initial_value" >"$state_file" || return 1
		chmod "$readonly_perms" "$state_file" || {
			echo "Failed to set permissions on $state_file" >&2
			return 1
		}
	}

	# Verify file was created
	[[ -f "$state_file" ]] || {
		echo "Failed to create file: $state_file" >&2
		return 1
	}

	# Save original permissions for restoration
	local original_perms
	original_perms=$(save_permissions_for_restore "$state_file")

	# Set up trap to restore permissions on EXIT
	# Use actual path value, not variable, since trap executes after function returns
	# shellcheck disable=SC2064 # We want variable expansion at trap definition time
	trap "chmod $original_perms \"$state_file\" 2>/dev/null || true" EXIT

	# Return the path for use in tests
	echo "$state_file"
}
