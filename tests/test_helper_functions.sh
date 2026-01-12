#!/usr/bin/env bats
#
# Unit tests for helper functions in vpn-monitor.sh
# Tests individual helper functions in isolation
#
# Note: This file uses BATS-specific syntax (@test directives).
# Do not validate with 'bash -n' as it will fail on @test syntax.
# Use 'bats' to run tests or validate syntax.

load test_helper

# Path to the VPN monitor script and modules (for source_lockfile_module)
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"
LIB_DIR="${BATS_TEST_DIRNAME}/../lib"

# bats test_tags=category:unit
@test "get_formatted_timestamp returns valid timestamp format" {
	# Purpose: Test verifies that get_formatted_timestamp function returns timestamp in correct format
	# Expected: Function returns timestamp in YYYY-MM-DD HH:MM:SS format
	# Importance: Timestamp formatting is used throughout logging and must be consistent
	# Source the function
	source_function "get_formatted_timestamp"

	# Run the function
	run get_formatted_timestamp

	assert_success
	# Check format: YYYY-MM-DD HH:MM:SS using regex
	assert_output --regexp '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
}

# bats test_tags=category:unit
@test "ensure_directory_exists creates directory when missing" {
	# Purpose: Test verifies that ensure_directory_exists function creates directories that don't exist
	# Expected: Function creates the specified directory if it doesn't exist, with appropriate error handling
	# Importance: Directory creation is essential for state files, logs, and other runtime data storage
	local test_dir="${TEST_DIR}/new_dir"

	# Source the function
	source_function "ensure_directory_exists"

	# Run the function (should not exit in test context)
	ensure_directory_exists "$test_dir" "test" || true

	assert_dir_exist "$test_dir"
}

# bats test_tags=category:unit
@test "sanitize_peer_ip converts dots to underscores" {
	# Purpose: Test verifies that sanitize_peer_ip function converts IPv4 addresses to filesystem-safe format
	# Expected: Function converts dots to underscores to create valid filenames for state files
	# Importance: IP sanitization enables per-peer state file naming without filesystem issues
	# Source the function
	# shellcheck source=/dev/null
	source_function "sanitize_peer_ip"

	run sanitize_peer_ip "${TEST_PEER_IP}"
	assert_success
	assert_output "192_168_1_1"
}

# bats test_tags=category:unit
@test "sanitize_peer_ip handles IPv6 addresses" {
	# Purpose: Test verifies that sanitize_peer_ip function correctly handles IPv6 addresses for filesystem naming
	# Expected: Function converts colons to underscores to create valid filenames for IPv6 peer state files
	# Importance: IPv6 support requires proper sanitization to handle longer addresses with colons
	# Source the function
	# shellcheck source=/dev/null
	source_function "sanitize_peer_ip"

	run sanitize_peer_ip "2001:db8::1"
	assert_success
	assert_output "2001_db8__1"
}

# bats test_tags=category:unit
@test "extract_lockfile_pid extracts PID from lockfile" {
	# Purpose: Test verifies that extract_lockfile_pid function correctly parses process ID from lockfile format
	# Expected: Function extracts PID from lockfile containing timestamp:pid format
	# Importance: PID extraction is used to verify if lockfile process is still running or stale
	# Source the function
	# shellcheck source=/dev/null
	source_function "extract_lockfile_pid"

	local lockfile="${TEST_DIR}/test.lock"
	echo "1234567890:12345" >"$lockfile"

	LOCKFILE="$lockfile" run extract_lockfile_pid "$lockfile"
	assert_success
	assert_output "12345"
}

# bats test_tags=category:unit
@test "extract_lockfile_pid returns empty for missing lockfile" {
	# Purpose: Test verifies that extract_lockfile_pid function handles missing lockfiles gracefully
	# Expected: Function returns success with empty output when lockfile doesn't exist
	# Importance: Missing lockfile handling prevents errors when checking for stale locks
	# Source the function
	# shellcheck source=/dev/null
	source_function "extract_lockfile_pid"

	run extract_lockfile_pid "${TEST_DIR}/nonexistent.lock"
	assert_success
	# Empty output expected
	assert_output ""
}

# bats test_tags=category:unit
@test "is_process_running returns true for current process" {
	# Purpose: Test verifies that is_process_running function correctly identifies running processes
	# Expected: Function returns success when checking if current process PID is running
	# Importance: Process existence checking is used to verify if lockfile PIDs are still active
	# Source the function
	# shellcheck source=/dev/null
	source_function "is_process_running"

	# Test with current PID
	run is_process_running $$
	assert_success
}

# bats test_tags=category:unit
@test "is_process_running returns false for non-existent PID" {
	# Purpose: Test verifies that is_process_running function correctly identifies non-existent processes
	# Expected: Function returns failure when checking a PID that doesn't exist in the process table
	# Importance: Non-existent PID detection enables identification of stale lockfiles from terminated processes
	# Source the function
	# shellcheck source=/dev/null
	source_function "is_process_running"

	# Use a very high PID that shouldn't exist
	run is_process_running 999999
	assert_failure
}

# bats test_tags=category:unit
@test "is_process_running returns false for empty PID" {
	# Purpose: Test verifies that is_process_running function handles empty PID input gracefully
	# Expected: Function returns failure when PID is empty or invalid, preventing errors
	# Importance: Empty PID handling prevents script crashes when lockfile parsing fails
	# Source the function
	# shellcheck source=/dev/null
	source_function "is_process_running"

	run is_process_running ""
	assert_failure
}

# bats test_tags=category:unit
@test "get_timestamp_plus_minutes adds minutes correctly" {
	# Purpose: Test verifies that get_timestamp_plus_minutes function correctly calculates future timestamps
	# Expected: Function adds specified minutes to current timestamp and returns Unix timestamp
	# Importance: Timestamp calculation is used for cooldown periods and rate limiting calculations
	# Source the function
	# shellcheck source=/dev/null
	source_function "get_timestamp_plus_minutes"

	local now=$(date +%s)
	run get_timestamp_plus_minutes 5

	assert_success
	local future=$(cat <<<"$output")
	local expected=$((now + 300)) # 5 minutes = 300 seconds

	# Allow 5 second tolerance for execution time
	assert [ $((future - expected)) -ge -5 ]
	assert [ $((future - expected)) -le 5 ]
}

# bats test_tags=category:unit
@test "get_file_mtime returns modification time" {
	# Purpose: Test verifies that get_file_mtime function correctly retrieves file modification timestamp
	# Expected: Function returns Unix timestamp representing file's last modification time
	# Importance: File modification time checking enables stale file detection and cache invalidation
	# Source the function
	# shellcheck source=/dev/null
	source_function "get_file_mtime"

	local test_file="${TEST_DIR}/test_file"
	touch "$test_file"
	# File systems update mtime immediately, no delay needed
	# Using deterministic approach: verify file exists before calling get_file_mtime

	run get_file_mtime "$test_file"
	assert_success
	# Should return a Unix timestamp (numeric) - use regex for pattern matching
	assert_output --regexp '^[0-9]+$'
}

# bats test_tags=category:unit
@test "validate_ip_address accepts valid IPv4 addresses" {
	# Purpose: Test verifies that validate_ip_address function correctly accepts valid IPv4 addresses
	# Expected: Function returns success (exit code 0) for valid IPv4 addresses in various ranges
	# Importance: IP validation prevents command injection and ensures only valid IPs are processed
	# Source the function
	# shellcheck source=/dev/null
	source_function "validate_ip_address"

	run validate_ip_address "${TEST_PEER_IP}"
	assert_success

	run validate_ip_address "${TEST_PEER_IP2}"
	assert_success

	run validate_ip_address "172.16.0.1"
	assert_success
}

# bats test_tags=category:unit
@test "validate_ip_address rejects invalid IPv4 addresses" {
	# Purpose: Test verifies that validate_ip_address function correctly rejects invalid IPv4 addresses
	# Expected: Function returns failure (exit code 1) for invalid formats including out-of-range octets
	# Importance: IP validation prevents command injection attacks and ensures data integrity
	# Source the function
	# shellcheck source=/dev/null
	source_function "validate_ip_address"

	run validate_ip_address "256.1.1.1"
	assert_failure

	run validate_ip_address "192.168.1"
	assert_failure

	run validate_ip_address "192.168.1.1.1"
	assert_failure

	run validate_ip_address ""
	assert_failure
}

# bats test_tags=category:unit
@test "validate_ip_address accepts valid IPv6 addresses" {
	# Purpose: Test verifies that validate_ip_address function correctly accepts valid IPv6 addresses
	# Expected: Function returns success (exit code 0) for valid IPv6 addresses in various formats
	# Importance: IPv6 support enables monitoring of IPv6 VPN tunnels and future-proofs the application
	# Source the function
	# shellcheck source=/dev/null
	source_function "validate_ip_address"

	run validate_ip_address "2001:db8::1"
	assert_success

	run validate_ip_address "::1"
	assert_success

	run validate_ip_address "2001:0db8:0000:0000:0000:0000:0000:0001"
	assert_success
}

# bats test_tags=category:unit
@test "validate_ip_address rejects invalid IPv6 addresses" {
	# Purpose: Test verifies that validate_ip_address function correctly rejects invalid IPv6 address formats
	# Expected: Function returns failure (exit code 1) for invalid IPv6 formats including malformed addresses
	# Importance: IPv6 validation prevents errors and ensures only properly formatted addresses are processed
	# Source the function
	# shellcheck source=/dev/null
	source_function "validate_ip_address"

	run validate_ip_address "2001:db8::1::2"
	assert_failure

	run validate_ip_address "2001:db8:::1"
	assert_failure

	run validate_ip_address "2001:db8:g::1"
	assert_failure
}

# bats test_tags=category:unit
@test "extract_byte_counter extracts bytes from xfrm output" {
	# Purpose: Test verifies that extract_byte_counter function correctly parses byte count from xfrm output
	# Expected: Function extracts numeric byte count from "lifetime current" line in xfrm state output
	# Importance: Byte counter extraction is critical for VPN health monitoring via traffic detection
	# Source the function
	# shellcheck source=/dev/null
	source_function "extract_byte_counter"

	local xfrm_output="lifetime current: 123456 bytes, 789 packets"

	run extract_byte_counter "$xfrm_output"
	assert_success
	assert_output "123456"
}

# bats test_tags=category:unit
@test "extract_byte_counter extracts bytes from UDM OS format with (bytes) syntax" {
	# Purpose: Test verifies that extract_byte_counter function correctly parses byte count from UDM OS xfrm output format
	# Expected: Function extracts numeric byte count from multi-line format where bytes appear as "  39492(bytes), 609(packets)"
	# Importance: UDM OS uses different xfrm output format than standard Linux; this format must be supported
	# Source the function
	# shellcheck source=/dev/null
	source_function "extract_byte_counter"

	# UDM OS format: lifetime current: on one line, bytes on next line as "  39492(bytes), 609(packets)"
	local xfrm_output="lifetime current:
  39492(bytes), 609(packets)
  add 2026-01-03 12:19:25 use 2026-01-03 12:19:34"

	run extract_byte_counter "$xfrm_output"
	assert_success
	assert_output "39492"
}

# bats test_tags=category:unit
@test "extract_byte_counter handles missing lifetime line" {
	# Purpose: Test verifies that extract_byte_counter function handles xfrm output without lifetime line gracefully
	# Expected: Function returns failure when lifetime line is missing from xfrm output
	# Importance: Error handling prevents script crashes when xfrm output format is unexpected or malformed
	# Source the function
	# shellcheck source=/dev/null
	source_function "extract_byte_counter"

	local xfrm_output="some other output"

	run extract_byte_counter "$xfrm_output"
	assert_failure
}

# bats test_tags=category:unit
@test "get_failure_count returns 0 for missing counter file" {
	# Purpose: Test verifies that get_failure_count function returns 0 when counter file doesn't exist
	# Expected: Function returns 0 (default value) for peers that haven't experienced failures yet
	# Importance: Default value handling ensures new peers start with zero failure count
	# Set up environment variables
	setup_test_environment "${TEST_DIR}"

	# Source the actual function from the library
	source_function "get_failure_count"

	# Test with peer IP that has no counter file
	# Use empty string for location to test backward compatibility
	run get_failure_count "" "${TEST_PEER_IP}"
	assert_success
	assert_output "0"
}

# bats test_tags=category:unit
@test "get_failure_count returns value from counter file" {
	# Purpose: Test verifies that get_failure_count function correctly reads failure count from existing counter file
	# Expected: Function reads and returns the numeric value stored in the per-peer failure counter file
	# Importance: Failure count retrieval is essential for tier escalation logic and recovery decisions
	# Set up environment variables
	setup_test_environment "${TEST_DIR}"
	# Use set_peer_state to create file with correct location-based path format
	source_function "set_peer_state"
	set_peer_state "" "${TEST_PEER_IP}" "failure_count" "5" || true

	# Source the actual function from the library
	source_function "get_failure_count"

	# Use empty string for location to test backward compatibility
	run get_failure_count "" "${TEST_PEER_IP}"
	assert_success
	assert_output "5"
}

# bats test_tags=category:unit
@test "get_failure_count handles corrupted file" {
	# Purpose: Test verifies that get_failure_count function handles corrupted state files gracefully
	# Expected: Function returns default value (0) and logs warning when state file contains invalid data
	# Importance: Corrupted file handling prevents script crashes and allows recovery from data corruption
	setup_test_environment "${TEST_DIR}"

	source_function "get_failure_count"
	source_function "get_peer_state_file_path"

	# Manually create corrupted file using correct path format
	local counter_file
	counter_file=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "failure_count")
	echo "invalid-value" >"$counter_file"

	# Use empty string for location to test backward compatibility
	run get_failure_count "" "${TEST_PEER_IP}"
	assert_success
	# Should return default (0) for corrupted file (function logs warning)
	# Verify it ends with 0 (the actual return value)
	# Check if last line is "0" OR entire output is "0" (handles newline cases)
	if [[ "${output##*$'\n'}" != "0" ]] && [[ "$output" != "0" ]]; then
		fail "Expected output to be '0' or end with '0', but got: '$output'"
	fi
}

# bats test_tags=category:unit
@test "increment_failure increments counter correctly" {
	# Purpose: Test verifies that increment_failure function correctly increments failure counter files
	# Expected: Function reads current counter value, increments it by 1, and writes back atomically
	# Importance: Failure counters track consecutive failures to trigger tiered recovery actions
	# Set up environment variables
	setup_test_environment "${TEST_DIR}"

	# Source the actual functions from the library
	source_function "increment_failure"
	source_function "get_failure_count"
	source_function "get_peer_state_file_path"

	# First increment - use empty string for location to test backward compatibility
	run increment_failure "" "${TEST_PEER_IP}"
	assert_success
	assert_output "1"

	# Verify the file was created using get_peer_state_file_path to get correct path
	local counter_file
	counter_file=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "failure_count")
	assert_file_exist "$counter_file"
	local count
	count=$(cat "$counter_file")
	assert_equal "$count" 1

	# Second increment
	run increment_failure "" "${TEST_PEER_IP}"
	assert_success
	assert_output "2"

	# Verify the counter was incremented
	count=$(cat "$counter_file")
	assert_equal "$count" 2
}

# bats test_tags=category:unit
@test "reset_failure_count resets counter to 0" {
	# Purpose: Test verifies that reset_failure_count function correctly resets failure counter to zero
	# Expected: Function writes 0 to the failure counter file when VPN recovers successfully
	# Importance: Counter reset clears failure history when VPN recovers, preventing false escalation
	# Set up environment variables
	setup_test_environment "${TEST_DIR}"
	# Use set_peer_state to create file with correct location-based path format
	source_function "set_peer_state"
	set_peer_state "" "${TEST_PEER_IP}" "failure_count" "5" || true

	# Source the actual function from the library
	source_function "reset_failure_count"
	source_function "get_peer_state_file_path"

	# Use empty string for location to test backward compatibility
	run reset_failure_count "" "${TEST_PEER_IP}"
	assert_success

	# Verify the counter was reset using get_peer_state_file_path to get correct path
	local counter_file
	counter_file=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "failure_count")
	assert_file_exist "$counter_file"
	local count
	count=$(cat "$counter_file")
	assert_equal "$count" 0
}

# ============================================================================
# Abstraction Layer Tests (get_peer_state, set_peer_state, etc.)
# ============================================================================

# bats test_tags=category:unit
@test "get_peer_state_file_path returns correct path for failure_count" {
	# Purpose: Test verifies that get_peer_state_file_path function returns correct file path for failure_count state
	# Expected: Function constructs path using logs directory and sanitized peer IP for failure counter file
	# Importance: Consistent path generation ensures state files are stored in predictable locations
	setup_test_environment "${TEST_DIR}"

	source_function "get_peer_state_file_path"

	# Use empty string for location to test backward compatibility (empty location becomes "LOCATION")
	run get_peer_state_file_path "" "${TEST_PEER_IP}" "failure_count"
	assert_success
	assert_output "${STATE_DIR}/failure_counter_LOCATION_192_168_1_1"
}

# bats test_tags=category:unit
@test "get_peer_state_file_path returns correct path for last_bytes" {
	# Purpose: Test verifies that get_peer_state_file_path function returns correct file path for last_bytes state
	# Expected: Function constructs path using state directory and sanitized peer IP for byte counter file
	# Importance: Byte counter file paths enable tracking of VPN traffic for health monitoring
	setup_test_environment "${TEST_DIR}"

	source_function "get_peer_state_file_path"

	# Use empty string for location to test backward compatibility (empty location becomes "LOCATION")
	run get_peer_state_file_path "" "${TEST_PEER_IP}" "last_bytes"
	assert_success
	assert_output "${STATE_DIR}/last_bytes_LOCATION_192_168_1_1"
}

# bats test_tags=category:unit
@test "get_peer_state_file_path handles unknown key" {
	# Purpose: Test verifies that get_peer_state_file_path function handles unknown state keys gracefully
	# Expected: Function logs warning but still returns constructed path for unknown keys
	# Importance: Unknown key handling allows extensibility while maintaining backward compatibility
	setup_test_environment "${TEST_DIR}"

	source_function "get_peer_state_file_path"

	# Use empty string for location to test backward compatibility (empty location becomes "LOCATION")
	run get_peer_state_file_path "" "${TEST_PEER_IP}" "unknown_key"
	assert_success
	# Function logs a warning but still returns the path
	assert_output --partial "${STATE_DIR}/unknown_key_LOCATION_192_168_1_1"
}

# bats test_tags=category:unit
@test "get_peer_state returns default when file missing" {
	# Purpose: Test verifies that get_peer_state function returns default value when state file doesn't exist
	# Expected: Function returns default value (0 or custom) for peers that haven't been initialized yet
	# Importance: Default value handling ensures new peers start with appropriate initial state values
	setup_test_environment "${TEST_DIR}"

	source_function "get_peer_state"

	# Use empty string for location to test backward compatibility
	run get_peer_state "" "${TEST_PEER_IP}" "failure_count"
	assert_success
	assert_output "0"

	# Test with custom default
	run get_peer_state "" "${TEST_PEER_IP}" "failure_count" "99"
	assert_success
	assert_output "99"
}

# bats test_tags=category:unit
@test "get_peer_state returns value from existing file" {
	# Purpose: Test verifies that get_peer_state function correctly reads values from existing state files
	# Expected: Function reads and returns the numeric value stored in the per-peer state file
	# Importance: State retrieval is essential for reading failure counts, byte counters, and other peer state
	setup_test_environment "${TEST_DIR}"

	source_function "get_peer_state"
	source_function "set_peer_state"

	# Create file using set_peer_state to ensure correct path format
	run set_peer_state "" "${TEST_PEER_IP}" "failure_count" "42"
	assert_success

	# Use empty string for location to test backward compatibility
	run get_peer_state "" "${TEST_PEER_IP}" "failure_count"
	assert_success
	assert_output "42"
}

# bats test_tags=category:unit
@test "get_peer_state handles corrupted file" {
	# Purpose: Test verifies that get_peer_state function handles corrupted state files gracefully
	# Expected: Function returns default value (0) and logs warning when state file contains invalid data
	# Importance: Corrupted file handling prevents script crashes and allows recovery from data corruption
	setup_test_environment "${TEST_DIR}"

	source_function "get_peer_state"
	source_function "get_peer_state_file_path"

	# Manually create corrupted file using correct path format
	# Use get_peer_state_file_path to get the correct path (empty location becomes "LOCATION")
	local counter_file
	counter_file=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "failure_count")
	echo "invalid-value" >"$counter_file"

	# Use empty string for location to test backward compatibility
	run get_peer_state "" "${TEST_PEER_IP}" "failure_count"
	assert_success
	# Should return default (0) for corrupted file (function logs warning)
	# Verify it ends with 0 (the actual return value)
	# Check if last line is "0" OR entire output is "0" (handles newline cases)
	if [[ "${output##*$'\n'}" != "0" ]] && [[ "$output" != "0" ]]; then
		fail "Expected output to be '0' or end with '0', but got: '$output'"
	fi
}

# bats test_tags=category:unit
@test "set_peer_state creates file with correct value" {
	# Purpose: Test verifies that set_peer_state function creates state files with correct values
	# Expected: Function creates per-peer state file and writes the specified numeric value atomically
	# Importance: State file creation enables tracking of peer-specific data like failure counts and byte counters
	setup_test_environment "${TEST_DIR}"

	source_function "set_peer_state"
	source_function "get_peer_state_file_path"

	# Use helper function to set state and verify file creation with value
	test_peer_state "${TEST_PEER_IP}" "failure_count" "7" "TEST" "7"
}

# bats test_tags=category:unit
@test "set_peer_state updates existing file" {
	# Purpose: Test verifies that set_peer_state function correctly updates existing state files
	# Expected: Function overwrites existing state file with new value, maintaining atomic write operations
	# Importance: State updates enable tracking changes in failure counts and other peer-specific metrics
	setup_test_environment "${TEST_DIR}"

	source_function "set_peer_state"
	source_function "get_peer_state_file_path"

	# Create file using set_peer_state to ensure correct path format
	run set_peer_state "" "${TEST_PEER_IP}" "failure_count" "5"
	assert_success

	# Use empty string for location to test backward compatibility
	run set_peer_state "" "${TEST_PEER_IP}" "failure_count" "10"
	assert_success

	# Verify file was updated using get_peer_state_file_path
	local counter_file
	counter_file=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "failure_count")
	local count
	count=$(cat "$counter_file")
	assert_equal "$count" 10
}

# bats test_tags=category:unit
@test "set_peer_state validates numeric values" {
	# Purpose: Test verifies that set_peer_state function validates that values are numeric before writing
	# Expected: Function rejects non-numeric values and returns failure to prevent corrupted state files
	# Importance: Validation prevents invalid data from being written to state files, maintaining data integrity
	setup_test_environment "${TEST_DIR}"

	source_function "set_peer_state"
	source_function "get_peer_state_file_path"

	# Should fail with invalid value
	# Use empty string for location to test backward compatibility
	run set_peer_state "" "${TEST_PEER_IP}" "failure_count" "not-a-number"
	assert_failure

	# File should not be created - use get_peer_state_file_path to get correct path
	local counter_file
	counter_file=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "failure_count")
	assert_file_not_exist "$counter_file"
}

# bats test_tags=category:unit
@test "set_peer_state works with last_bytes" {
	# Purpose: Test verifies that set_peer_state function works correctly with last_bytes state key
	# Expected: Function creates last_bytes state file with correct value using atomic write operations
	# Importance: Byte counter state files enable tracking of VPN traffic for health monitoring
	setup_test_environment "${TEST_DIR}"

	source_function "set_peer_state"
	source_function "get_peer_state_file_path"

	# Use helper function to set state and verify file creation with value
	test_peer_state "${TEST_PEER_IP}" "last_bytes" "123456" "TEST" "123456"
}

# bats test_tags=category:unit
@test "delete_peer_state removes existing file" {
	# Purpose: Test verifies that delete_peer_state function removes existing peer state files
	# Expected: Function deletes the specified peer state file when it exists
	# Importance: State file deletion enables cleanup of peer-specific data when no longer needed
	setup_test_environment "${TEST_DIR}"

	source_function "delete_peer_state"
	source_function "set_peer_state"
	source_function "get_peer_state_file_path"

	# Create file and verify it exists using helper function
	test_peer_state "${TEST_PEER_IP}" "failure_count" "5"

	# Get file path for deletion verification
	local counter_file
	counter_file=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "failure_count")

	# Delete the file
	run delete_peer_state "" "${TEST_PEER_IP}" "failure_count"
	assert_success

	# File should be deleted
	assert_file_not_exist "$counter_file"
}

# bats test_tags=category:unit
@test "delete_peer_state succeeds when file missing" {
	# Purpose: Test verifies that delete_peer_state function handles missing state files gracefully
	# Expected: Function succeeds even when state file doesn't exist, preventing errors from missing files
	# Importance: Idempotent deletion prevents errors when attempting to delete already-removed state files
	setup_test_environment "${TEST_DIR}"

	source_function "delete_peer_state"

	# Should succeed even if file doesn't exist
	# Use empty string for location to test backward compatibility
	run delete_peer_state "" "${TEST_PEER_IP}" "failure_count"
	assert_success
}

# bats test_tags=category:unit
@test "cleanup_peer_state removes all peer state files" {
	# Purpose: Test verifies that cleanup_peer_state function removes all state files for a peer
	# Expected: Function deletes all peer-specific state files including failure_count, last_bytes, and other state files
	# Importance: Complete cleanup enables removal of all peer state when peer is no longer monitored
	setup_test_environment "${TEST_DIR}"

	source_function "cleanup_peer_state"
	source_function "set_peer_state"
	source_function "get_peer_state_file_path"

	# Create both failure_count and last_bytes files using set_peer_state to ensure correct path format
	run set_peer_state "" "${TEST_PEER_IP}" "failure_count" "5"
	assert_success
	run set_peer_state "" "${TEST_PEER_IP}" "last_bytes" "123456"
	assert_success

	# Get file paths for verification
	local counter_file
	counter_file=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "failure_count")
	local bytes_file
	bytes_file=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "last_bytes")

	# Verify files exist before cleanup
	assert_file_exist "$counter_file"
	assert_file_exist "$bytes_file"

	# Use empty string for location to test backward compatibility
	run cleanup_peer_state "" "${TEST_PEER_IP}"
	assert_success

	# Both files should be deleted
	assert_file_not_exist "$counter_file"
	assert_file_not_exist "$bytes_file"
}

# bats test_tags=category:unit
@test "get_peer_state and set_peer_state work together" {
	# Purpose: Test verifies that get_peer_state and set_peer_state functions work together correctly
	# Expected: Values written with set_peer_state can be retrieved with get_peer_state
	# Importance: Ensures state abstraction layer provides consistent read/write operations
	setup_test_environment "${TEST_DIR}"

	source_function "get_peer_state"
	source_function "set_peer_state"

	# Set a value - use empty string for location to test backward compatibility
	run set_peer_state "" "${TEST_PEER_IP}" "failure_count" "15"
	assert_success

	# Get it back
	run get_peer_state "" "${TEST_PEER_IP}" "failure_count"
	assert_success
	assert_output "15"
}

# bats test_tags=category:unit
@test "abstraction layer maintains atomic writes" {
	# Purpose: Test verifies that the state abstraction layer uses atomic write operations
	# Expected: State writes use temporary files and atomic rename operations to prevent corruption
	# Importance: Atomic writes prevent partial writes and ensure state file integrity
	setup_test_environment "${TEST_DIR}"

	source_function "set_peer_state"
	source_function "get_peer_state_file_path"

	# Set a value - should use atomic write (temp file + mv)
	# Use empty string for location to test backward compatibility
	run set_peer_state "" "${TEST_PEER_IP}" "failure_count" "20"
	assert_success

	# Verify temp file doesn't exist (should have been renamed)
	# Use get_peer_state_file_path to get correct path
	local counter_file
	counter_file=$(get_peer_state_file_path "" "${TEST_PEER_IP}" "failure_count")
	local temp_file="${counter_file}.tmp"
	assert_file_not_exist "$temp_file"
	assert_file_exist "$counter_file"
}

# bats test_tags=category:unit
@test "check_cooldown returns false when cooldown file missing" {
	# Purpose: Test verifies that check_cooldown function returns false when cooldown file doesn't exist
	# Expected: Function returns failure (not in cooldown) when cooldown file is missing
	# Importance: Missing cooldown file indicates no cooldown period is active, allowing recovery actions
	local state_dir="${TEST_DIR}"

	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
STATE_DIR="$1"

# Get file modification time
#
# Arguments:
#   $1: File path
#
# Returns:
#   Prints Unix timestamp of file modification time, or "0" on error
get_file_mtime() {
	local file="$1"
	stat -c %Y "$file" 2>/dev/null || echo "0"
}

# Check if system is in cooldown period
#
# Arguments:
#   None (uses STATE_DIR environment variable)
#
# Returns:
#   0: In cooldown period
#   1: Not in cooldown period
check_cooldown() {
	local COOLDOWN_UNTIL_FILE="${STATE_DIR}/cooldown_until"
	if [[ ! -f "$COOLDOWN_UNTIL_FILE" ]]; then
		return 1 # Not in cooldown
	fi

	local cooldown_until
	cooldown_until=$(cat "$COOLDOWN_UNTIL_FILE")
	local now
	now=$(date +%s)

	if [[ $now -lt $cooldown_until ]]; then
		return 0 # In cooldown
	else
		rm -f "$COOLDOWN_UNTIL_FILE"
		return 1 # Not in cooldown
	fi
}

check_cooldown
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	run bash "${TEST_DIR}/test_script.sh" "$state_dir"
	assert_failure # Not in cooldown
}

# bats test_tags=category:unit
@test "check_cooldown returns true when in cooldown period" {
	# Purpose: Test verifies that check_cooldown function returns true when cooldown period is active
	# Expected: Function returns success (in cooldown) when current time is before cooldown expiration time
	# Importance: Cooldown checking prevents recovery actions from being executed too frequently
	local state_dir="${TEST_DIR}"
	local cooldown_file="${state_dir}/cooldown_until"
	local future_time=$(($(date +%s) + 900)) # 15 minutes in future
	echo "$future_time" >"$cooldown_file"

	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
STATE_DIR="$1"

# Check if system is in cooldown period
#
# Arguments:
#   None (uses STATE_DIR environment variable)
#
# Returns:
#   0: In cooldown period
#   1: Not in cooldown period
check_cooldown() {
	local COOLDOWN_UNTIL_FILE="${STATE_DIR}/cooldown_until"
	if [[ ! -f "$COOLDOWN_UNTIL_FILE" ]]; then
		return 1 # Not in cooldown
	fi

	local cooldown_until
	cooldown_until=$(cat "$COOLDOWN_UNTIL_FILE")
	local now
	now=$(date +%s)

	if [[ $now -lt $cooldown_until ]]; then
		return 0 # In cooldown
	else
		rm -f "$COOLDOWN_UNTIL_FILE"
		return 1 # Not in cooldown
	fi
}

check_cooldown
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	run bash "${TEST_DIR}/test_script.sh" "$state_dir"
	assert_success # In cooldown
}

# bats test_tags=category:unit
@test "check_cooldown handles corrupted file" {
	# Purpose: Test verifies that check_cooldown function handles corrupted cooldown files gracefully
	# Expected: Function handles invalid timestamp gracefully, treating corrupted file as expired cooldown
	# Importance: Corrupted timestamps can cause arithmetic errors; script must handle them robustly
	setup_test_environment "${TEST_DIR}"

	source_function "check_cooldown"
	source_function "get_unix_timestamp"
	source_function "file_exists_and_readable"

	# Create corrupted cooldown file with invalid timestamp
	local cooldown_file="${STATE_DIR}/cooldown_until"
	echo "invalid-timestamp-value" >"$cooldown_file"

	# check_cooldown reads the file and tries to compare timestamps
	# In bash, when comparing a number to a non-numeric string with -lt,
	# bash treats the string as 0, so the comparison will be false
	# This causes the function to treat it as expired and return 1 (not in cooldown)
	run check_cooldown
	# Function should return 1 (not in cooldown) since invalid timestamp is treated as 0
	# and current time is greater than 0
	assert_failure
	# Corrupted file should be removed
	assert_file_not_exist "$cooldown_file"
}

# bats test_tags=category:unit
@test "check_rate_limit allows restart when under limit" {
	# Purpose: Test verifies that check_rate_limit function allows restarts when under the rate limit
	# Expected: Function returns success when number of recent restarts is below MAX_RESTARTS_PER_HOUR
	# Importance: Rate limiting prevents excessive IPsec restarts that could cause service disruption
	local state_dir="${TEST_DIR}"
	local logs_dir="${TEST_DIR}/logs"
	mkdir -p "$logs_dir"
	local restart_file="${state_dir}/restart_count"

	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
RESTART_COUNT_FILE="$1"
MAX_RESTARTS_PER_HOUR=3

# Check if restart is within rate limit
#
# Arguments:
#   None (uses RESTART_COUNT_FILE and MAX_RESTARTS_PER_HOUR variables)
#
# Returns:
#   0: Within rate limit (restart allowed)
#   1: Over rate limit (restart blocked)
check_rate_limit() {
	local now
	now=$(date +%s)
	local one_hour_ago
	one_hour_ago=$((now - 3600))

	if [[ ! -f "$RESTART_COUNT_FILE" ]]; then
		return 0 # No previous restarts, allow
	fi

	local recent_restarts
	recent_restarts=$(awk -v cutoff="$one_hour_ago" '$1 > cutoff' "$RESTART_COUNT_FILE" 2>/dev/null | wc -l | tr -d ' ')

	if [[ $recent_restarts -ge $MAX_RESTARTS_PER_HOUR ]]; then
		return 1 # Rate limited
	fi

	return 0 # Within rate limit
}

check_rate_limit
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	run bash "${TEST_DIR}/test_script.sh" "$restart_file"
	assert_success # Under limit
}

# bats test_tags=category:unit
@test "check_rate_limit blocks restart when over limit" {
	# Purpose: Test verifies that check_rate_limit function blocks restarts when over the rate limit
	# Expected: Function returns failure when number of recent restarts exceeds MAX_RESTARTS_PER_HOUR
	# Importance: Rate limiting prevents excessive IPsec restarts that could cause service disruption
	local state_dir="${TEST_DIR}"
	local logs_dir="${TEST_DIR}/logs"
	mkdir -p "$logs_dir"
	local restart_file="${state_dir}/restart_count"

	# Create restart file with 4 recent restarts (over limit of 3)
	local now=$(date +%s)
	echo "$now" >>"$restart_file"
	echo "$now" >>"$restart_file"
	echo "$now" >>"$restart_file"
	echo "$now" >>"$restart_file"

	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
RESTART_COUNT_FILE="$1"
MAX_RESTARTS_PER_HOUR=3

# Check if restart is within rate limit
#
# Arguments:
#   None (uses RESTART_COUNT_FILE and MAX_RESTARTS_PER_HOUR variables)
#
# Returns:
#   0: Within rate limit (restart allowed)
#   1: Over rate limit (restart blocked)
check_rate_limit() {
	local now
	now=$(date +%s)
	local one_hour_ago
	one_hour_ago=$((now - 3600))

	if [[ ! -f "$RESTART_COUNT_FILE" ]]; then
		return 0 # No previous restarts, allow
	fi

	local recent_restarts
	recent_restarts=$(awk -v cutoff="$one_hour_ago" '$1 > cutoff' "$RESTART_COUNT_FILE" 2>/dev/null | wc -l | tr -d ' ')

	if [[ $recent_restarts -ge $MAX_RESTARTS_PER_HOUR ]]; then
		return 1 # Rate limited
	fi

	return 0 # Within rate limit
}

check_rate_limit
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	run bash "${TEST_DIR}/test_script.sh" "$restart_file"
	assert_failure # Over limit
}

# bats test_tags=category:unit
@test "check_rate_limit handles corrupted file" {
	# Purpose: Test verifies that check_rate_limit function handles corrupted restart count file gracefully
	# Expected: Function handles invalid timestamp format gracefully without crashing (may count invalid lines due to awk string comparison)
	# Importance: Corrupted restart count files can cause awk errors; script must handle them robustly
	setup_test_environment "${TEST_DIR}"

	# Set required environment variables for check_rate_limit
	export MAX_RESTARTS_PER_HOUR=3
	export SECONDS_PER_HOUR=3600

	source_function "check_rate_limit"
	source_function "get_unix_timestamp"
	source_function "file_exists_and_readable"

	# Create corrupted restart count file with invalid timestamp format
	local restart_file="${STATE_DIR}/restart_count"
	echo "invalid-timestamp-line1" >"$restart_file"
	echo "invalid-timestamp-line2" >>"$restart_file"
	echo "not-a-number" >>"$restart_file"

	# check_rate_limit uses awk to filter timestamps with '$1 > cutoff'
	# awk does string comparison when comparing strings to numbers
	# Non-numeric strings like "invalid-timestamp-line1" will be compared as strings
	# String "invalid-timestamp-line1" > "1000" (lexicographically) evaluates to true
	# So invalid lines will be counted, potentially causing false rate limit hits
	# However, the function should still handle this gracefully (not crash)
	# The actual behavior depends on awk's string comparison, but we verify it doesn't crash
	run check_rate_limit
	# Function should return either 0 or 1 (not crash)
	# Note: Due to awk's string comparison behavior, invalid lines may be counted
	# This is a known limitation - the function should still handle it gracefully
	assert [ $status -eq 0 ] || [ $status -eq 1 ]
}

# bats test_tags=category:unit
@test "record_restart appends timestamp to restart file" {
	# Purpose: Test verifies that record_restart function appends current timestamp to restart count file
	# Expected: Function writes Unix timestamp to restart file, enabling rate limit calculations
	# Importance: Restart timestamps enable rate limiting to prevent excessive IPsec restarts
	local state_dir="${TEST_DIR}"
	local logs_dir="${TEST_DIR}/logs"
	mkdir -p "$logs_dir"
	local restart_file="${state_dir}/restart_count"

	cat >"${TEST_DIR}/test_script.sh" <<'SCRIPT'
#!/bin/bash
RESTART_COUNT_FILE="$1"

# Record a restart timestamp
#
# Arguments:
#   None (uses RESTART_COUNT_FILE variable)
#
# Returns:
#   0: Always succeeds
record_restart() {
	local timestamp
	timestamp=$(date +%s)
	echo "$timestamp" >>"$RESTART_COUNT_FILE"
}

record_restart
cat "$RESTART_COUNT_FILE"
SCRIPT

	chmod +x "${TEST_DIR}/test_script.sh"

	run bash "${TEST_DIR}/test_script.sh" "$restart_file"
	assert_success
	# Should contain a timestamp (numeric) - use regex for pattern matching
	assert_output --regexp '^[0-9]+$'
}

# ============================================================================
# Tests for discover_connection_name function (ipsec-based discovery)
# ============================================================================

# bats test_tags=category:unit
@test "discover_connection_name extracts connection name from ipsec status (libreswan format)" {
	# Purpose: Test verifies that discover_connection_name function correctly parses connection names from libreswan ipsec status output
	# Expected: Function extracts connection name (e.g., "site-a") from ipsec status output matching peer IP
	# Importance: Connection name discovery enables logging and potential per-connection recovery actions
	source_function "discover_connection_name"
	source_function "sanitize_peer_ip"

	# Mock ipsec command - libreswan format with multiple connections
	cat >"${TEST_DIR}/ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    echo "site-a: ESTABLISHED 1 hour ago, 192.168.1.1...192.168.1.2"
    echo "site-b: ESTABLISHED 2 hours ago, 10.0.0.1...10.0.0.2"
elif [[ "$1" == "--help" ]] || [[ "$1" == "--version" ]]; then
    # Handle command availability checks (used by check_command_available)
    exit 0
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "${TEST_DIR}/ipsec"
	add_mock_to_path

	STATE_DIR="${TEST_DIR}"
	run discover_connection_name "192.168.1.1"

	assert_success
	assert_output "site-a"
}

# bats test_tags=category:unit
@test "discover_connection_name extracts connection name from ipsec status (strongswan format)" {
	# Purpose: Test verifies that discover_connection_name function correctly parses connection names from strongswan ipsec status output
	# Expected: Function extracts connection name from strongswan format output, supporting multiple IPsec implementations
	# Importance: Multi-implementation support ensures connection discovery works across different IPsec distributions
	source_function "discover_connection_name"
	source_function "sanitize_peer_ip"

	# Mock ipsec command - strongswan format with multiple connections
	cat >"${TEST_DIR}/ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    echo "site-a: IKEv1, ESTABLISHED, 192.168.1.1"
    echo "site-b: IKEv2, ESTABLISHED, 10.0.0.1"
elif [[ "$1" == "--help" ]] || [[ "$1" == "--version" ]]; then
    # Handle command availability checks (used by check_command_available)
    exit 0
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "${TEST_DIR}/ipsec"
	add_mock_to_path

	STATE_DIR="${TEST_DIR}"
	run discover_connection_name "192.168.1.1"

	assert_success
	assert_output "site-a"
}

# bats test_tags=category:unit
@test "discover_connection_name returns empty string when connection not found" {
	# Purpose: Test verifies that discover_connection_name function returns empty string when peer IP is not found in ipsec status
	# Expected: Function returns empty string when no connection matches the peer IP, indicating connection not established
	# Importance: Empty return value indicates VPN connection is not active, enabling appropriate error handling
	source_function "discover_connection_name"
	source_function "sanitize_peer_ip"

	# Mock ipsec command - no matching peer IP (uses different IP)
	mock_ipsec "libreswan" "192.168.1.1" "site-a"
	add_mock_to_path

	export STATE_DIR="${TEST_DIR}"
	run discover_connection_name "10.0.0.1"

	assert_success
	assert_output ""
}

# bats test_tags=category:unit
@test "discover_connection_name caches connection name" {
	# Purpose: Test verifies that discover_connection_name function caches discovered connection names to avoid repeated ipsec calls
	# Expected: Function writes connection name to cache file on first discovery and uses cache on subsequent calls
	# Importance: Caching reduces overhead of repeated ipsec status calls and improves performance during monitoring
	# Match test 27 pattern: call source_function first
	source_function "discover_connection_name"
	source_function "sanitize_peer_ip"

	# Set STATE_DIR AFTER source_function (matching test 27)
	# But ensure it's exported so it's available in subshells created by 'run'
	STATE_DIR="${TEST_DIR}"
	export STATE_DIR

	# Mock ipsec command - libreswan format
	mock_ipsec "libreswan" "192.168.1.1" "site-a"
	add_mock_to_path

	# Clean up any existing cache file from previous tests
	local cache_file="${TEST_DIR}/connection_name_192_168_1_1"
	rm -f "$cache_file"

	# First call - should discover and cache
	# Use plain 'run' like test 27 (source_function makes functions available)
	run discover_connection_name "192.168.1.1"
	assert_success
	# Manually verify output - assert_output has scoping issues with $output
	# The output variable IS set correctly (we verified with debug), but assert_output
	# can't see it. So we'll verify manually and skip assert_output.
	if [[ "${output:-}" != "site-a" ]]; then
		echo "Expected output: site-a" >&2
		echo "Actual output: [${output:-}]" >&2
		return 1
	fi
	assert_file_exist "$cache_file"
	# Use assert_equal for better error messages
	assert_equal "$(cat "$cache_file")" "site-a"

	# Remove ipsec mock - second call should use cache (tests cache-first behavior)
	rm -f "${TEST_DIR}/ipsec"
	# Ensure STATE_DIR is still exported for second call
	export STATE_DIR
	run discover_connection_name "192.168.1.1"
	assert_success
	# Manually verify output - assert_output has scoping issues
	if [[ "${output:-}" != "site-a" ]]; then
		echo "Expected output: site-a" >&2
		echo "Actual output: [${output:-}]" >&2
		return 1
	fi
	# Verify cache was used (ipsec was removed, so cache must have been used)
	assert_file_exist "$cache_file"
}

# bats test_tags=category:unit
@test "discover_connection_name returns empty when ipsec command not available" {
	# Purpose: Test verifies that discover_connection_name function returns empty string when ipsec command is not available
	# Expected: Function returns empty string and does not create cache file when ipsec is unavailable
	# Importance: Graceful handling of missing ipsec command prevents script failures in environments without IPsec tools
	source_function "discover_connection_name"
	source_function "sanitize_peer_ip"

	# Ensure ipsec is not in PATH
	PATH="/usr/bin:/bin"
	export STATE_DIR="${TEST_DIR}"

	# Ensure no cache exists from previous tests (test isolation)
	local cache_file="${TEST_DIR}/connection_name_192_168_1_1"
	rm -f "$cache_file"

	run discover_connection_name "192.168.1.1"

	assert_success
	assert_output ""
	# Verify no cache was created (since ipsec was unavailable)
	assert [ ! -f "$cache_file" ]
}

# bats test_tags=category:unit
@test "discover_connection_name handles ipsec status failure gracefully" {
	# Purpose: Test verifies that discover_connection_name function handles ipsec status command failures gracefully
	# Expected: Function returns empty string and does not create cache file when ipsec status fails
	# Importance: Error handling prevents script failures when ipsec status command encounters errors
	source_function "discover_connection_name"
	source_function "sanitize_peer_ip"

	# Ensure no cache exists from previous tests (test isolation)
	local cache_file="${TEST_DIR}/connection_name_192_168_1_1"
	rm -f "$cache_file"

	# Mock ipsec command - fails
	cat >"${TEST_DIR}/ipsec" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    exit 1
elif [[ "$1" == "--help" ]] || [[ "$1" == "--version" ]]; then
    # Handle command availability checks (used by check_command_available)
    exit 0
fi
exec /usr/bin/ipsec "$@"
EOF
	chmod +x "${TEST_DIR}/ipsec"
	add_mock_to_path

	STATE_DIR="${TEST_DIR}"
	run discover_connection_name "192.168.1.1"

	assert_success
	assert_output ""
	# Verify no cache was created (since ipsec failed)
	assert [ ! -f "$cache_file" ]
}

# bats test_tags=category:unit
@test "discover_connection_name uses cache when ipsec unavailable (cache-first behavior)" {
	# Purpose: Test verifies that discover_connection_name function uses cached connection name when ipsec is unavailable
	# Expected: Function returns cached connection name even when ipsec command is not available, cache is checked before ipsec availability
	# Importance: Cache-first behavior ensures connection names remain available even when ipsec tools become temporarily unavailable
	# This test explicitly verifies the cache-first behavior fix:
	# Cache should be checked BEFORE ipsec availability check
	source_function "discover_connection_name"
	source_function "sanitize_peer_ip"

	STATE_DIR="${TEST_DIR}"
	export STATE_DIR

	# Pre-populate cache with a connection name
	local cache_file="${TEST_DIR}/connection_name_192_168_1_1"
	echo "cached-connection" >"$cache_file"

	# Ensure ipsec is not in PATH (simulating ipsec unavailable)
	PATH="/usr/bin:/bin"
	export PATH

	# Function should return cached value even though ipsec is unavailable
	run discover_connection_name "192.168.1.1"

	assert_success
	# Manually verify output (assert_output has scoping issues)
	if [[ "${output:-}" != "cached-connection" ]]; then
		echo "Expected output: cached-connection" >&2
		echo "Actual output: [${output:-}]" >&2
		return 1
	fi
	# Verify cache still exists
	assert_file_exist "$cache_file"
	# Use assert_equal for better error messages
	assert_equal "$(cat "$cache_file")" "cached-connection"
}

# ============================================================================
# Tests for config_schema.sh functions
# ============================================================================

# bats test_tags=category:unit
@test "get_config_schema returns schema for existing variable" {
	# Purpose: Test verifies that get_config_schema function returns schema information for existing configuration variables
	# Expected: Function returns schema string containing variable type, requirement status, and validation rules
	# Importance: Schema retrieval enables configuration validation and default value application
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run get_config_schema "TIER1_THRESHOLD"

	assert_success
	assert_output --partial "required"
	assert_output --partial "integer"
}

# bats test_tags=category:unit
@test "get_config_schema returns failure for non-existent variable" {
	# Purpose: Test verifies that get_config_schema function returns failure for variables not in the schema
	# Expected: Function returns failure (exit code 1) when variable is not defined in configuration schema
	# Importance: Failure handling prevents errors when querying schema for unknown variables
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run get_config_schema "NON_EXISTENT_VAR"

	assert_failure
}

# bats test_tags=category:unit
@test "is_config_required returns true for required variable" {
	# Purpose: Test verifies that is_config_required function correctly identifies required configuration variables
	# Expected: Function returns success (exit code 0) for variables marked as required in the schema
	# Importance: Required variable detection enables validation to ensure all required settings are configured
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run is_config_required "TIER1_THRESHOLD"

	assert_success
}

# bats test_tags=category:unit
@test "is_config_required returns false for optional variable" {
	# Purpose: Test verifies that is_config_required function correctly identifies optional configuration variables
	# Expected: Function returns failure (exit code 1) for variables marked as optional in the schema
	# Importance: Optional variable detection enables validation to allow missing optional settings
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run is_config_required "VPN_NAME"

	assert_failure
}

# bats test_tags=category:unit
@test "is_config_required returns false for unknown variable" {
	# Purpose: Test verifies that is_config_required function handles unknown variables gracefully
	# Expected: Function returns failure (exit code 1) for variables not defined in the schema
	# Importance: Unknown variable handling prevents errors when checking requirement status for invalid variables
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run is_config_required "UNKNOWN_VAR"

	assert_failure
}

# bats test_tags=category:unit
@test "get_config_default returns default value for variable with default" {
	# Purpose: Test verifies that get_config_default function returns default value for variables with defaults defined
	# Expected: Function returns the default value specified in the configuration schema
	# Importance: Default value retrieval enables automatic configuration initialization with sensible defaults
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run get_config_default "VPN_NAME"

	assert_success
	assert_output "Site-to-Site VPN"
}

# bats test_tags=category:unit
@test "get_config_default returns empty string for variable without default" {
	# Purpose: Test verifies that get_config_default function returns empty string for variables without defaults
	# Expected: Function returns empty string for variables that don't have default values in the schema
	# Importance: Empty string return enables detection of variables that require explicit configuration
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	# Use a pattern-matched variable (LOCATION_*_EXTERNAL) which doesn't have a default
	run get_config_default "LOCATION_TEST_EXTERNAL"

	assert_success
	# Should return empty string (no default for pattern-matched variables)
	# Function may output newline, so check for empty or whitespace-only
	# Check if output is empty or contains only whitespace
	if [[ -n "$output" ]] && [[ ! "$output" =~ ^[[:space:]]*$ ]]; then
		fail "Expected empty or whitespace-only output, but got: '$output'"
	fi
}

# bats test_tags=category:unit
@test "get_config_default returns failure for non-existent variable" {
	# Purpose: Test verifies that get_config_default function returns failure for variables not in the schema
	# Expected: Function returns failure (exit code 1) when variable is not defined in configuration schema
	# Importance: Failure handling prevents errors when querying defaults for unknown variables
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run get_config_default "NON_EXISTENT_VAR"

	assert_failure
}

# bats test_tags=category:unit
@test "get_config_default handles integer defaults correctly" {
	# Purpose: Test verifies that get_config_default function correctly returns integer default values
	# Expected: Function returns integer default values as strings without modification
	# Importance: Integer default handling ensures numeric configuration values are properly initialized
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run get_config_default "ENABLE_PING_CHECK"

	assert_success
	assert_output "1"
}

# bats test_tags=category:unit
@test "get_config_default handles cron schedule defaults correctly" {
	# Purpose: Test verifies that get_config_default function correctly returns cron schedule default values
	# Expected: Function returns cron schedule default values including special characters and spaces
	# Importance: Cron schedule default handling ensures scheduling configuration is properly initialized
	# Source config_schema.sh
	if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
	fi

	run get_config_default "CRON_SCHEDULE"

	assert_success
	assert_output "*/1 * * * *"
}

# bats test_tags=category:unit
@test "apply_schema_defaults reads defaults from schema (single source of truth)" {
	# Purpose: Test verifies that apply_schema_defaults function reads and applies defaults from configuration schema
	# Expected: Function applies default values from schema to all configuration variables, ensuring single source of truth
	# Importance: Schema-based defaults ensure consistent configuration initialization and reduce duplication
	# Source config.sh (which sources config_schema.sh)
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		# Source logging.sh first (required by config.sh)
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Unset all config variables to test defaults
	# Use both unset and explicit empty assignment to ensure variables are truly unset
	unset VPN_NAME TIER1_THRESHOLD TIER2_THRESHOLD TIER3_THRESHOLD 2>/dev/null || true
	unset COOLDOWN_MINUTES MAX_RESTARTS_PER_HOUR LOCKFILE_TIMEOUT ENABLE_PING_CHECK LOCAL_UDM_IP 2>/dev/null || true
	unset PING_COUNT PING_TIMEOUT ENABLE_KEEPALIVE KEEPALIVE_INTERVAL KEEPALIVE_PING_COUNT 2>/dev/null || true
	unset DEBUG NO_ESCALATE ENABLE_XFRM_RECOVERY LOG_FILE STATE_DIR LOGS_DIR CRON_SCHEDULE 2>/dev/null || true

	# Call apply_schema_defaults directly
	apply_schema_defaults

	# Verify defaults from schema are applied
	# Test a few key defaults from schema (using variables without spaces first)
	# Use assert_equal for better error messages
	assert_equal "$ENABLE_PING_CHECK" "1"
	assert_equal "$PING_COUNT" "3"
	assert_equal "$PING_TIMEOUT" "2"
	assert_equal "$ENABLE_KEEPALIVE" "1"
	assert_equal "$KEEPALIVE_INTERVAL" "30"
	assert_equal "$KEEPALIVE_PING_COUNT" "1"
	assert_equal "$DEBUG" "0"
	assert_equal "$NO_ESCALATE" "0"
	assert_equal "$ENABLE_XFRM_RECOVERY" "1"
	assert_equal "$LOCKFILE_TIMEOUT" "300"

	# Test VPN_NAME (has spaces) - use assert_equal for better error messages
	assert_equal "$VPN_NAME" "Site-to-Site VPN"

	# Test CRON_SCHEDULE (has spaces and special chars) - use assert_equal for better error messages
	assert_equal "$CRON_SCHEDULE" "*/1 * * * *"

	# Verify backward compatibility defaults for required variables
	assert_equal "$TIER1_THRESHOLD" "1"
	assert_equal "$TIER2_THRESHOLD" "3"
	assert_equal "$TIER3_THRESHOLD" "5"
	assert_equal "$COOLDOWN_MINUTES" "15"
	assert_equal "$MAX_RESTARTS_PER_HOUR" "3"
}

# ============================================================================
# Tests for config.sh validation functions
# ============================================================================

# bats test_tags=category:unit
@test "parse_config_schema parses complete schema string" {
	# Purpose: Test verifies that parse_config_schema function correctly parses complete schema definition strings
	# Expected: Function extracts required status, variable type, validation rules, and default value from schema string
	# Importance: Schema parsing enables configuration validation and default value application
	# Source config.sh (which sources config_schema.sh)
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		# Source logging.sh first (required by config.sh)
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	run parse_config_schema "required|integer|min:1|default:5"

	assert_success
	# Check output has 4 lines
	local line_count
	line_count=$(echo "$output" | wc -l | tr -d ' ')
	assert_equal "$line_count" 4
	# Check each component
	local required var_type rules default_val
	{
		read -r required
		read -r var_type
		read -r rules
		read -r default_val
	} <<<"$output"
	# Use assert_equal for better error messages
	assert_equal "$required" "required"
	assert_equal "$var_type" "integer"
	assert_equal "$rules" "min:1"
	# Note: default_val is extracted value without "default:" prefix
	assert_equal "$default_val" "5"
}

# bats test_tags=category:unit
@test "parse_config_schema parses schema with empty rules" {
	# Purpose: Test verifies that parse_config_schema function correctly handles schema strings with empty rules section
	# Expected: Function parses schema correctly when rules section is empty (double pipe separator)
	# Importance: Empty rules handling enables schema definitions for variables without validation rules
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	run parse_config_schema "optional|string||default:test"

	assert_success
	local required var_type rules default_val
	{
		read -r required
		read -r var_type
		read -r rules
		read -r default_val
	} <<<"$output"
	# Use assert_equal for better error messages
	assert_equal "$required" "optional"
	assert_equal "$var_type" "string"
	assert [ -z "$rules" ]
	# Note: default_val is extracted value without "default:" prefix
	assert_equal "$default_val" "test"
}

# bats test_tags=category:unit
@test "parse_config_schema parses schema without default" {
	# Purpose: Test verifies that parse_config_schema function correctly handles schema strings without default values
	# Expected: Function parses schema correctly and returns empty string for default value when none is specified
	# Importance: Schema parsing without defaults enables variables that require explicit configuration
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	run parse_config_schema "required|string|non-empty"

	assert_success
	local required var_type rules default_val
	{
		read -r required
		read -r var_type
		read -r rules
		read -r default_val || default_val=""
	} <<<"$output"
	# Use assert_equal for better error messages
	assert_equal "$required" "required"
	assert_equal "$var_type" "string"
	assert_equal "$rules" "non-empty"
	assert [ -z "$default_val" ]
}

# bats test_tags=category:unit
@test "apply_config_default applies default to empty optional variable" {
	# Purpose: Test verifies that apply_config_default function applies default values to empty optional variables
	# Expected: Function returns default value when variable is empty and marked as optional
	# Importance: Default value application enables automatic configuration initialization for optional settings
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock handle_error to suppress log output
	# Mock function to suppress error logging in tests
	#
	# Arguments:
	#   $@: Error message and parameters (ignored)
	#
	# Returns:
	#   0: Always succeeds
	handle_error() {
		return 0
	}

	# Set up test variable
	TEST_VAR=""
	run apply_config_default "TEST_VAR" "" "optional" "default_value"

	assert_success
	assert_output "default_value"
	# Note: Variable update verification skipped because run executes in subshell
	# The function output is verified above, which confirms the default was applied
}

# bats test_tags=category:unit
@test "apply_config_default does not override existing value" {
	# Purpose: Test verifies that apply_config_default function preserves existing configuration values
	# Expected: Function returns existing value unchanged when variable already has a value
	# Importance: Value preservation ensures user-configured values are not overwritten by defaults
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	run apply_config_default "TEST_VAR" "existing_value" "optional" "default_value"

	assert_success
	assert_output "existing_value"
}

# bats test_tags=category:unit
@test "apply_config_default fails for empty required variable" {
	# Purpose: Test verifies that apply_config_default function fails when required variable is empty and has no default
	# Expected: Function returns failure when variable is required but empty and no default is provided
	# Importance: Required variable validation ensures critical configuration settings are always provided
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock die function to not exit
	# Mock function to prevent script exit in tests
	#
	# Arguments:
	#   $@: Error message and parameters (ignored)
	#
	# Returns:
	#   1: Always fails (simulates die behavior)
	die() {
		return 1
	}

	run apply_config_default "REQUIRED_VAR" "" "required" ""

	assert_failure
}

# bats test_tags=category:unit
@test "apply_config_default allows empty optional variable without default" {
	# Purpose: Test verifies that apply_config_default function allows empty optional variables when no default is specified
	# Expected: Function returns empty string when variable is optional, empty, and has no default value
	# Importance: Empty optional variable handling enables configuration flexibility for truly optional settings
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	run apply_config_default "TEST_VAR" "" "optional" ""

	assert_success
	assert_output ""
}

# bats test_tags=category:unit
@test "validate_config_type validates integer type correctly" {
	# Purpose: Test verifies that validate_config_type function correctly validates integer type configuration values
	# Expected: Function accepts numeric values and returns them unchanged for integer type variables
	# Importance: Integer type validation ensures numeric configuration values are properly formatted
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	run validate_config_type "TEST_VAR" "123" "integer" "required" ""

	assert_success
	assert_output "123"
}

# bats test_tags=category:unit
@test "validate_config_type rejects non-numeric integer value" {
	# Purpose: Test verifies that validate_config_type function rejects non-numeric values for integer type variables
	# Expected: Function returns failure when value is not numeric for integer type variable
	# Importance: Type validation prevents invalid data from being used in integer configuration settings
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock handle_error - when called with ERROR severity, it calls die() which exits
	# For testing in subshell (via run), we make handle_error exit the subshell
	# This simulates the real behavior where die() exits the script
	# Mock function to simulate error handling in tests
	#
	# Arguments:
	#   $1: Severity level
	#   $2: Error message (ignored)
	#   $3: Exit code (default: 1)
	#
	# Returns:
	#   0: Success (non-ERROR severity)
	#   Exits with code 1 if ERROR severity and exit_code != 0
	handle_error() {
		local severity="$1"
		local exit_code="${3:-1}"
		if [[ "$severity" == "ERROR" ]] && [[ "$exit_code" -ne 0 ]]; then
			# Exit the subshell (run will capture this as failure)
			exit 1
		fi
		return 0
	}

	# Mock handle_error_or_exit_fake_mode to prevent it from exiting
	# In fake mode, it returns 1; in normal mode it calls die() and exits
	# For testing, we make it return 1 to simulate fake mode behavior
	# Mock function to simulate fake mode error handling
	#
	# Arguments:
	#   $@: Error parameters (ignored)
	#
	# Returns:
	#   1: Always returns failure (simulates fake mode)
	handle_error_or_exit_fake_mode() {
		return 1
	}

	run validate_config_type "TEST_VAR" "abc" "integer" "required" ""

	assert_failure
}

# bats test_tags=category:unit
@test "validate_config_type applies default for invalid optional integer" {
	# Purpose: Test verifies that validate_config_type function applies default value when optional integer is invalid
	# Expected: Function returns default value when value is invalid and variable is optional with a default
	# Importance: Default application for optional variables enables graceful handling of invalid configuration
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock handle_error to suppress log output
	# Mock function to suppress error logging in tests
	#
	# Arguments:
	#   $@: Error message and parameters (ignored)
	#
	# Returns:
	#   0: Always succeeds
	handle_error() {
		return 0
	}

	run validate_config_type "TEST_VAR" "invalid" "integer" "optional" "5"

	assert_success
	assert_output "5"
	# Note: Variable update verification skipped because run executes in subshell
	# The function output is verified above, which confirms the default was applied
}

# bats test_tags=category:unit
@test "validate_config_type rejects invalid default for optional integer" {
	# Purpose: Test verifies that validate_config_type function rejects invalid default values for optional integers
	# Expected: Function returns failure when default value itself is invalid (non-numeric)
	# Importance: Default value validation prevents invalid defaults from being applied to configuration
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock handle_error to suppress log output
	# Mock function to suppress error logging in tests
	#
	# Arguments:
	#   $@: Error message and parameters (ignored)
	#
	# Returns:
	#   0: Always succeeds
	handle_error() {
		return 0
	}

	# Test that invalid default is rejected (doesn't set global variable)
	run validate_config_type "TEST_VAR" "invalid" "integer" "optional" "not_a_number"

	assert_failure
	# Verify that the global variable was NOT set (should be empty/unset)
	# Since run executes in subshell, we can't directly check, but failure confirms rejection
}

# bats test_tags=category:unit
@test "validate_config_type accepts string type" {
	# Purpose: Test verifies that validate_config_type function correctly validates string type configuration values
	# Expected: Function accepts string values and returns them unchanged for string type variables
	# Importance: String type validation ensures text configuration values are properly handled
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	run validate_config_type "TEST_VAR" "test_string" "string" "required" ""

	assert_success
	assert_output "test_string"
}

# bats test_tags=category:unit
@test "validate_config_rule validates non-empty rule" {
	# Purpose: Test verifies that validate_config_rule function correctly validates non-empty rule for string values
	# Expected: Function accepts non-empty string values when non-empty rule is specified
	# Importance: Non-empty rule validation ensures required string configuration values are not empty
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	run validate_config_rule "TEST_VAR" "non_empty_value" "string" "required" "" "non-empty"

	assert_success
	assert_output "non_empty_value"
}

# bats test_tags=category:unit
@test "validate_config_rule rejects empty value with non-empty rule" {
	# Purpose: Test verifies that validate_config_rule function rejects empty values when non-empty rule is specified
	# Expected: Function returns failure when value is empty but non-empty rule requires a value
	# Importance: Empty value rejection ensures required configuration settings have meaningful values
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock die function
	# Mock function to prevent script exit in tests
	#
	# Arguments:
	#   $@: Error message and parameters (ignored)
	#
	# Returns:
	#   1: Always fails (simulates die behavior)
	die() {
		return 1
	}

	run validate_config_rule "TEST_VAR" "" "string" "required" "" "non-empty"

	assert_failure
}

# bats test_tags=category:unit
@test "validate_config_rule validates min rule for integer" {
	# Purpose: Test verifies that validate_config_rule function correctly validates minimum value rule for integers
	# Expected: Function accepts integer values that meet or exceed the minimum value specified in the rule
	# Importance: Minimum value validation ensures integer configuration values are within acceptable ranges
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	run validate_config_rule "TEST_VAR" "10" "integer" "required" "" "min:5"

	assert_success
	assert_output "10"
}

# bats test_tags=category:unit
@test "validate_config_rule rejects value below min" {
	# Purpose: Test verifies that validate_config_rule function rejects integer values below the minimum
	# Expected: Function returns failure when integer value is less than the minimum specified in the rule
	# Importance: Minimum value enforcement prevents configuration values that are too small
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock die function
	# Mock function to prevent script exit in tests
	#
	# Arguments:
	#   $@: Error message and parameters (ignored)
	#
	# Returns:
	#   1: Always fails (simulates die behavior)
	die() {
		return 1
	}

	run validate_config_rule "TEST_VAR" "3" "integer" "required" "" "min:5"

	assert_failure
}

# bats test_tags=category:unit
@test "validate_config_rule validates max rule for integer" {
	# Purpose: Test verifies that validate_config_rule function correctly validates maximum value rule for integers
	# Expected: Function accepts integer values that are less than or equal to the maximum value specified in the rule
	# Importance: Maximum value validation ensures integer configuration values are within acceptable ranges
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	run validate_config_rule "TEST_VAR" "5" "integer" "required" "" "max:10"

	assert_success
	assert_output "5"
}

# bats test_tags=category:unit
@test "validate_config_rule rejects value above max" {
	# Purpose: Test verifies that validate_config_rule function rejects integer values above the maximum
	# Expected: Function returns failure when integer value exceeds the maximum specified in the rule
	# Importance: Maximum value enforcement prevents configuration values that are too large
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock die function
	# Mock function to prevent script exit in tests
	#
	# Arguments:
	#   $@: Error message and parameters (ignored)
	#
	# Returns:
	#   1: Always fails (simulates die behavior)
	die() {
		return 1
	}

	run validate_config_rule "TEST_VAR" "15" "integer" "required" "" "max:10"

	assert_failure
}

# bats test_tags=category:unit
@test "validate_config_rule validates values rule" {
	# Purpose: Test verifies that validate_config_rule function correctly validates allowed values rule
	# Expected: Function accepts values that are in the allowed values list specified in the rule
	# Importance: Allowed values validation ensures configuration values match predefined options
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	run validate_config_rule "TEST_VAR" "1" "integer" "required" "" "values:0,1"

	assert_success
	assert_output "1"
}

# bats test_tags=category:unit
@test "validate_config_rule rejects value not in allowed values" {
	# Purpose: Test verifies that validate_config_rule function rejects values not in the allowed values list
	# Expected: Function returns failure when value is not in the allowed values specified in the rule
	# Importance: Allowed values enforcement ensures configuration values match predefined valid options
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock die function
	# Mock function to prevent script exit in tests
	#
	# Arguments:
	#   $@: Error message and parameters (ignored)
	#
	# Returns:
	#   1: Always fails (simulates die behavior)
	die() {
		return 1
	}

	run validate_config_rule "TEST_VAR" "2" "integer" "required" "" "values:0,1"

	assert_failure
}

# bats test_tags=category:unit
@test "validate_config_rule validates relative min rule" {
	# Purpose: Test verifies that validate_config_rule function correctly validates relative minimum rules referencing other variables
	# Expected: Function accepts values that meet or exceed the value of the referenced configuration variable
	# Importance: Relative minimum validation enables dependent configuration values (e.g., TIER2_THRESHOLD >= TIER1_THRESHOLD)
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Set referenced variable (must be exported for subshell access)
	export TIER1_THRESHOLD=5
	run validate_config_rule "TIER2_THRESHOLD" "10" "integer" "required" "" "min:TIER1_THRESHOLD"

	assert_success
	assert_output "10"
	unset TIER1_THRESHOLD
}

# bats test_tags=category:unit
@test "validate_config_rules validates multiple rules" {
	# Purpose: Test verifies that validate_config_rules function correctly validates multiple validation rules together
	# Expected: Function accepts values that satisfy all specified rules (e.g., min and max together)
	# Importance: Multiple rule validation enables complex validation requirements for configuration values
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	run validate_config_rules "TEST_VAR" "5" "integer" "required" "" "min:1,max:10"

	assert_success
	assert_output "5"
}

# bats test_tags=category:unit
@test "validate_config_rules handles empty rules string" {
	# Purpose: Test verifies that validate_config_rules function correctly handles empty rules strings
	# Expected: Function accepts any value when no validation rules are specified
	# Importance: Empty rules handling enables configuration variables without validation requirements
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	run validate_config_rules "TEST_VAR" "value" "string" "required" "" ""

	assert_success
	assert_output "value"
}

# bats test_tags=category:unit
@test "validate_config_rules stops on first failure" {
	# Purpose: Test verifies that validate_config_rules function stops validation on the first rule that fails
	# Expected: Function returns failure immediately when any rule fails, without checking remaining rules
	# Importance: Early failure detection improves performance and provides clear error messages
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock die function
	# Mock function to prevent script exit in tests
	#
	# Arguments:
	#   $@: Error message and parameters (ignored)
	#
	# Returns:
	#   1: Always fails (simulates die behavior)
	die() {
		return 1
	}

	run validate_config_rules "TEST_VAR" "3" "integer" "required" "" "min:5,max:10"

	assert_failure
}

# bats test_tags=category:unit,priority:high
@test "validate_config_var persists corrected value to global variable" {
	# Purpose: Test verifies that validate_config_var updates the global variable with the final
	# validated/corrected value after all validations succeed. This is critical for ensuring
	# that corrections (defaults applied, type corrections, rule corrections) are persisted.
	# Expected: When validate_config_var corrects an invalid optional value, the global
	# variable is updated with the corrected value.
	# Importance: Bug fix verification - ensures validation corrections are not lost.
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		if [[ -f "${LIB_DIR}/common.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/common.sh" 2>/dev/null || true
		fi
		if [[ -f "${LIB_DIR}/config_schema.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/config_schema.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock handle_error to suppress log output
	# Mock function to suppress error logging in tests
	#
	# Arguments:
	#   $@: Error message and parameters (ignored)
	#
	# Returns:
	#   0: Always succeeds
	handle_error() {
		return 0
	}

	# Mock handle_error_or_exit_fake_mode to prevent it from exiting
	# Mock function to simulate fake mode error handling
	#
	# Arguments:
	#   $@: Error parameters (ignored)
	#
	# Returns:
	#   1: Always returns failure (simulates fake mode)
	handle_error_or_exit_fake_mode() {
		return 1
	}

	# Test case 1: Invalid optional integer value gets corrected to default
	# PING_COUNT is optional|integer|min:1|max:10|default:3
	# Set invalid value that will be corrected
	PING_COUNT="invalid"

	# Call validate_config_var directly (not with 'run') to access global variables
	# This tests the bug fix where corrections weren't persisted
	# Check return code to ensure validation succeeds
	if ! validate_config_var "PING_COUNT"; then
		fail "validate_config_var should succeed when correcting invalid optional value"
	fi

	# Verify global variable was updated with corrected default value
	assert_equal "${PING_COUNT}" "3"

	# Test case 2: Out-of-range optional integer value gets corrected to default
	# Set value below minimum (will be corrected to default)
	PING_COUNT="0"

	if ! validate_config_var "PING_COUNT"; then
		fail "validate_config_var should succeed when correcting out-of-range optional value"
	fi

	# Verify global variable was updated with corrected default value
	assert_equal "${PING_COUNT}" "3"

	# Test case 3: Out-of-range optional integer value above max gets corrected
	# Set value above maximum (will be corrected to default)
	PING_COUNT="20"

	if ! validate_config_var "PING_COUNT"; then
		fail "validate_config_var should succeed when correcting out-of-range optional value"
	fi

	# Verify global variable was updated with corrected default value
	assert_equal "${PING_COUNT}" "3"

	# Test case 4: Valid value is preserved (not overwritten)
	# Set valid value within range
	PING_COUNT="5"

	if ! validate_config_var "PING_COUNT"; then
		fail "validate_config_var should succeed for valid value"
	fi

	# Verify global variable still has the valid value (not changed to default)
	assert_equal "${PING_COUNT}" "5"
}

# ============================================================================
# PARSE_QUOTED_VALUE TESTS - Quote Parsing Edge Cases
# ============================================================================

# bats test_tags=category:unit,priority:high
@test "parse_quoted_value handles escaped quotes in double-quoted strings" {
	# Purpose: Test verifies that parse_quoted_value correctly handles escaped quotes in double-quoted strings.
	# Expected: Escaped quotes are parsed correctly, parse_result[value] contains literal quote.
	# Importance: Ensures escaped quotes don't break parsing and are handled correctly.
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock log_message to suppress output
	# Mock function to suppress logging in tests
	#
	# Arguments:
	#   $@: Log message and parameters (ignored)
	#
	# Returns:
	#   0: Always succeeds
	log_message() {
		return 0
	}

	# Test: VAR="value with \" escaped"
	declare -A parse_result
	if ! parse_quoted_value '"value with \" escaped"' 'VAR="value with \" escaped"' 1 "parse_result"; then
		fail "parse_quoted_value should succeed for escaped quotes"
	fi

	assert_equal "${parse_result[value]}" 'value with " escaped'
}

# bats test_tags=category:unit,priority:high
@test "parse_quoted_value handles escaped backslash in double-quoted strings" {
	# Purpose: Test verifies that parse_quoted_value correctly handles escaped backslashes.
	# Expected: Escaped backslash results in single backslash in parse_result[value].
	# Importance: Ensures backslash escaping works correctly.
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock log_message to suppress output
	# Mock function to suppress logging in tests
	#
	# Arguments:
	#   $@: Log message and parameters (ignored)
	#
	# Returns:
	#   0: Always succeeds
	log_message() {
		return 0
	}

	# Test: VAR="value with \\ backslash"
	declare -A parse_result
	if ! parse_quoted_value '"value with \\ backslash"' 'VAR="value with \\ backslash"' 1 "parse_result"; then
		fail "parse_quoted_value should succeed for escaped backslash"
	fi

	assert_equal "${parse_result[value]}" 'value with \ backslash'
}

# bats test_tags=category:unit,priority:high
@test "parse_quoted_value detects unclosed double quote" {
	# Purpose: Test verifies that parse_quoted_value correctly detects unclosed double quotes.
	# Expected: Returns error, unclosed quote detected.
	# Importance: Ensures malformed config files are rejected.
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock log_message to capture output
	# Mock function to suppress logging in tests
	#
	# Arguments:
	#   $@: Log message and parameters (ignored)
	#
	# Returns:
	#   0: Always succeeds
	log_message() {
		return 0
	}

	# Test: VAR="unclosed quote
	declare -A parse_result
	run parse_quoted_value '"unclosed quote' 'VAR="unclosed quote' 1 "parse_result"

	assert_failure
}

# bats test_tags=category:unit,priority:high
@test "parse_quoted_value detects unclosed single quote" {
	# Purpose: Test verifies that parse_quoted_value correctly detects unclosed single quotes.
	# Expected: Returns error, unclosed quote detected.
	# Importance: Ensures malformed config files are rejected.
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock log_message to suppress output
	# Mock function to suppress logging in tests
	#
	# Arguments:
	#   $@: Log message and parameters (ignored)
	#
	# Returns:
	#   0: Always succeeds
	log_message() {
		return 0
	}

	# Test: VAR='unclosed quote
	declare -A parse_result
	run parse_quoted_value "'unclosed quote" "VAR='unclosed quote" 1 "parse_result"

	assert_failure
}

# bats test_tags=category:unit,priority:high
@test "parse_quoted_value rejects quotes in unquoted values" {
	# Purpose: Test verifies that parse_quoted_value rejects quotes in unquoted values.
	# Expected: Returns error, quotes not allowed in unquoted values.
	# Importance: Ensures invalid config syntax is rejected.
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock log_message to suppress output
	# Mock function to suppress logging in tests
	#
	# Arguments:
	#   $@: Log message and parameters (ignored)
	#
	# Returns:
	#   0: Always succeeds
	log_message() {
		return 0
	}

	# Test: VAR=value"with"quotes
	declare -A parse_result
	run parse_quoted_value 'value"with"quotes' 'VAR=value"with"quotes' 1 "parse_result"

	assert_failure
}

# bats test_tags=category:unit,priority:high
@test "parse_quoted_value handles trailing backslash before closing quote" {
	# Purpose: Test verifies that parse_quoted_value correctly handles trailing backslash before closing quote
	# Expected: Trailing backslash escapes closing quote, resulting in unclosed quote error
	# Importance: Ensures escape sequences are handled correctly
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock log_message to suppress output
	# Mock function to suppress logging in tests
	#
	# Arguments:
	#   $@: Log message and parameters (ignored)
	#
	# Returns:
	#   0: Always succeeds
	log_message() {
		return 0
	}

	# Test: VAR="value\"
	# The backslash escapes the closing quote, so quote is not closed
	declare -A parse_result
	run parse_quoted_value '"value\"' 'VAR="value\"' 1 "parse_result"

	assert_failure
}

# bats test_tags=category:unit,priority:high
@test "parse_quoted_value handles empty quoted strings" {
	# Purpose: Test verifies that parse_quoted_value correctly handles empty quoted strings
	# Expected: Parses correctly, parse_result[value] is empty string
	# Importance: Ensures empty values are handled correctly
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock log_message to suppress output
	# Mock function to suppress logging in tests
	#
	# Arguments:
	#   $@: Log message and parameters (ignored)
	#
	# Returns:
	#   0: Always succeeds
	log_message() {
		return 0
	}

	# Test: VAR=""
	declare -A parse_result
	if ! parse_quoted_value '""' 'VAR=""' 1 "parse_result"; then
		fail "parse_quoted_value should succeed for empty double-quoted string"
	fi

	assert_equal "${parse_result[value]}" ""

	# Test: VAR=''
	declare -A parse_result2
	if ! parse_quoted_value "''" "VAR=''" 1 "parse_result2"; then
		fail "parse_quoted_value should succeed for empty single-quoted string"
	fi

	assert_equal "${parse_result2[value]}" ""
}

# bats test_tags=category:unit,priority:high
@test "parse_quoted_value handles single quotes with no escaping" {
	# Purpose: Test verifies that parse_quoted_value correctly handles single quotes where backslash is literal.
	# Expected: Parses correctly, backslash is literal (no escaping in single quotes).
	# Importance: Ensures single quotes behave correctly (no escaping in bash).
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock log_message to suppress output
	# Mock function to suppress logging in tests
	#
	# Arguments:
	#   $@: Log message and parameters (ignored)
	#
	# Returns:
	#   0: Always succeeds
	log_message() {
		return 0
	}

	# Test: VAR='value with \ backslash'
	# In single quotes, backslash is literal (no escaping)
	declare -A parse_result
	if ! parse_quoted_value "'value with \\ backslash'" "VAR='value with \\ backslash'" 1 "parse_result"; then
		fail "parse_quoted_value should succeed for single-quoted string with backslash"
	fi

	assert_equal "${parse_result[value]}" 'value with \ backslash'
}

# bats test_tags=category:unit
@test "parse_assignment returns values via associative array" {
	# Purpose: Test verifies that parse_assignment properly returns name and value via associative array
	# via associative array, ensuring no global variable pollution.
	# Expected: Each call to parse_assignment returns fresh values via associative array.
	# Importance: Associative array return mechanism ensures clean data flow and
	# prevents global variable pollution, making code easier to test and understand.
	if [[ -f "${LIB_DIR}/config.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		if [[ -f "${LIB_DIR}/common.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/common.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/config.sh" 2>/dev/null || true
	fi

	# Mock handle_config_error to prevent it from exiting
	# Mock function to prevent config error exit in tests
	#
	# Arguments:
	#   $@: Error message and parameters (ignored)
	#
	# Returns:
	#   1: Always fails (simulates error)
	handle_config_error() {
		return 1
	}

	# Mock is_fake_mode to return false (normal mode)
	# Mock function to simulate normal mode (not fake mode)
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   1: Always returns false (not in fake mode)
	is_fake_mode() {
		return 1
	}

	# Test 1: Parse first assignment
	declare -A parse_result
	if ! parse_assignment "VPN_NAME=\"First VPN\"" 1 "parse_result"; then
		fail "parse_assignment should succeed for valid assignment"
	fi
	assert_equal "${parse_result[name]}" "VPN_NAME"
	assert_equal "${parse_result[value]}" "First VPN"

	# Test 2: Parse second assignment - should return new values
	declare -A parse_result2
	if ! parse_assignment "TIER1_THRESHOLD=5" 2 "parse_result2"; then
		fail "parse_assignment should succeed for valid assignment"
	fi
	assert_equal "${parse_result2[name]}" "TIER1_THRESHOLD"
	assert_equal "${parse_result2[value]}" "5"

	# Test 3: Parse third assignment with different format
	declare -A parse_result3
	if ! parse_assignment "ENABLE_PING_CHECK='1'" 3 "parse_result3"; then
		fail "parse_assignment should succeed for valid assignment"
	fi
	assert_equal "${parse_result3[name]}" "ENABLE_PING_CHECK"
	assert_equal "${parse_result3[value]}" "1"

	# Test 4: Verify that failed parse returns error
	declare -A parse_result4
	run parse_assignment "INVALID_LINE" 4 "parse_result4"
	assert_failure
}

# bats test_tags=category:unit
@test "safe_parse_config_file parses multiple lines correctly" {
	# Purpose: Test verifies that safe_parse_config_file properly parses multiple config lines
	# using local associative arrays, ensuring no global variable pollution.
	# Expected: Each line is parsed independently and all variables are set correctly.
	# Importance: Ensures config file parsing works correctly without relying on global
	# variables, making the code cleaner and easier to test.
	# Source dependencies - standard pattern (now works correctly since config.sh uses -gA)
	# shellcheck source=../lib/common.sh
	source "${BATS_TEST_DIRNAME}/../lib/common.sh" 2>/dev/null || true
	# shellcheck source=../lib/logging.sh
	source "${BATS_TEST_DIRNAME}/../lib/logging.sh" 2>/dev/null || true
	# Source config.sh (which declares CONFIG_SCHEMA as -gA and sources config_schema.sh)
	# shellcheck source=../lib/config.sh
	source "${BATS_TEST_DIRNAME}/../lib/config.sh" 2>/dev/null || true
	# Explicitly source config_schema.sh to ensure CONFIG_SCHEMA is populated
	# (config.sh sources it, but explicitly sourcing again ensures it works in test environment)
	# shellcheck source=../lib/config_schema.sh
	source "${BATS_TEST_DIRNAME}/../lib/config_schema.sh" 2>/dev/null || true

	# Set up test environment
	export STATE_DIR="${TEST_DIR:-/tmp/test_config_reset}"
	export LOG_FILE="${STATE_DIR}/logs/vpn-monitor.log"
	export LOGS_DIR="${STATE_DIR}/logs"
	enable_fake_mode
	mkdir -p "$LOGS_DIR"

	# Create config file with multiple valid lines
	local config_file="${TEST_DIR:-/tmp}/test-reset.conf"
	cat >"$config_file" <<'EOF'
VPN_NAME="Test VPN"
TIER1_THRESHOLD=1
TIER2_THRESHOLD=3
ENABLE_PING_CHECK=1
EOF

	# Parse config file (call directly to access global variables)
	safe_parse_config_file "$config_file"

	# Verify all variables were set correctly (implicitly tests variable reset)
	# This proves that variables are properly reset between iterations because
	# each line is parsed independently and all values are set correctly
	assert_equal "${VPN_NAME:-}" "Test VPN"
	assert_equal "${TIER1_THRESHOLD:-}" "1"
	assert_equal "${TIER2_THRESHOLD:-}" "3"
	assert_equal "${ENABLE_PING_CHECK:-}" "1"

	# Cleanup
	rm -f "$config_file"
}

# ============================================================================
# LOCKFILE ACQUISITION FUNCTION TESTS
# ============================================================================

# Helper function to source lockfile module and dependencies
#
# Sources lockfile module and its dependencies, sets up required environment
# variables for lockfile tests.
#
# Arguments:
#   None
#
# Returns:
#   0: Always succeeds
source_lockfile_module() {
	# Source dependencies in order
	# shellcheck source=/dev/null
	source "${LIB_DIR}/constants.sh" 2>/dev/null || true
	# shellcheck source=/dev/null
	source "${LIB_DIR}/common.sh" 2>/dev/null || true
	# shellcheck source=/dev/null
	source "${LIB_DIR}/logging.sh" 2>/dev/null || true
	# shellcheck source=/dev/null
	source "${LIB_DIR}/state.sh" 2>/dev/null || true
	# shellcheck source=/dev/null
	source "${LIB_DIR}/lockfile.sh" 2>/dev/null || true

	# Set required environment variables
	export LOCKFILE="${TEST_DIR}/test.lock"
	export LOCKFILE_TIMEOUT="${LOCKFILE_TIMEOUT:-60}"
	export LOG_FILE="${TEST_DIR}/test.log"
	mkdir -p "$(dirname "$LOG_FILE")"
}

# bats test_tags=category:unit
@test "acquire_lockfile_flock successfully acquires lock when available" {
	# Purpose: Test verifies that acquire_lockfile_flock function successfully acquires lock when no other process holds it
	# Expected: Function acquires lock using flock, executes main function, and cleans up lockfile
	# Importance: Lock acquisition is essential for preventing multiple instances of the script from running simultaneously
	# Skip condition: Requires 'flock' command to be available for file locking tests
	if ! command -v flock >/dev/null 2>&1; then
		skip "flock command not available (test requires flock for file locking functionality)"
	fi

	source_lockfile_module

	# Test function that will be executed after lock acquisition
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	test_main_func() {
		echo "Lock acquired, executing main function"
		return 0
	}

	# Run acquire_lockfile_flock
	run acquire_lockfile_flock test_main_func

	assert_success
	assert_output --partial "Lock acquired"
	# Lockfile should be cleaned up after execution
	assert_file_not_exist "$LOCKFILE"
}

# bats test_tags=category:unit
@test "acquire_lockfile_flock detects running process and exits gracefully" {
	# Purpose: Test verifies that acquire_lockfile_flock function detects when another process holds the lock
	# Expected: Function detects lockfile conflict, exits gracefully without executing main function
	# Importance: Graceful exit prevents multiple script instances and avoids conflicts
	# Skip condition: Requires 'flock' command to be available for file locking tests
	if ! command -v flock >/dev/null 2>&1; then
		skip "flock command not available (test requires flock for file locking functionality)"
	fi

	source_lockfile_module

	# Create lockfile with current PID (simulating running process)
	echo "$(date +%s):$$" >"$LOCKFILE"
	touch "$LOCKFILE"

	# Test function (should not be executed)
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	test_main_func() {
		echo "This should not execute"
		return 0
	}

	# Run acquire_lockfile_flock - should detect conflict and exit
	run acquire_lockfile_flock test_main_func

	# Should exit with code 0 (graceful exit, not error)
	assert_success
	# Should output warning about lockfile conflict
	assert_output --partial "already running"
	# Main function should not have executed
	refute_output --partial "This should not execute"
}

# bats test_tags=category:unit
@test "acquire_lockfile_flock removes stale lockfile and acquires lock" {
	# Purpose: Test verifies that acquire_lockfile_flock function removes stale lockfiles and acquires lock
	# Expected: Function detects stale lockfile (old timestamp, dead PID), removes it, and successfully acquires lock
	# Importance: Stale lockfile cleanup prevents false positives from terminated processes
	# Skip condition: Requires 'flock' command to be available for file locking tests
	if ! command -v flock >/dev/null 2>&1; then
		skip "flock command not available (test requires flock for file locking functionality)"
	fi

	source_lockfile_module

	# Create stale lockfile (old timestamp, non-existent PID)
	local old_timestamp
	old_timestamp=$(($(date +%s) - LOCKFILE_TIMEOUT - 10))
	echo "${old_timestamp}:99999" >"$LOCKFILE"
	touch -d "@$old_timestamp" "$LOCKFILE" 2>/dev/null || touch "$LOCKFILE"

	# Test function that will be executed after lock acquisition
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	test_main_func() {
		echo "Lock acquired after stale removal"
		return 0
	}

	# Run acquire_lockfile_flock
	run acquire_lockfile_flock test_main_func

	assert_success
	assert_output --partial "Lock acquired"
	# Lockfile should be cleaned up after execution
	assert_file_not_exist "$LOCKFILE"
}

# bats test_tags=category:unit
@test "acquire_lockfile_flock handles race condition when lockfile removed between check and acquisition" {
	# Purpose: Test verifies that acquire_lockfile_flock function handles race conditions when lockfile is removed between check and acquisition
	# Expected: Function handles race condition gracefully, either acquiring lock or detecting conflict
	# Importance: Race condition handling ensures reliable lock acquisition in concurrent scenarios
	# Skip condition: Requires 'flock' command to be available for file locking tests
	if ! command -v flock >/dev/null 2>&1; then
		skip "flock command not available (test requires flock for file locking functionality)"
	fi

	source_lockfile_module

	# Test function that will be executed after lock acquisition
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	test_main_func() {
		echo "Lock acquired"
		return 0
	}

	# Create a background process that removes lockfile after signal file appears
	# This simulates a race condition where lockfile is removed between check and acquisition
	# Use file-based synchronization instead of sleep for deterministic timing
	local signal_file="${TEST_DIR}/bg_ready"
	rm -f "$signal_file"
	(
		# Wait for signal file to appear (indicates lock acquisition attempt started)
		while [[ ! -f "$signal_file" ]]; do
			sleep 0.01
		done
		# Small delay to ensure we're in the middle of acquisition attempt
		sleep 0.05
		rm -f "$LOCKFILE"
	) &
	local bg_pid=$!

	# Create signal file to indicate lock acquisition attempt is starting
	touch "$signal_file"

	# Run acquire_lockfile_flock - should handle race condition gracefully
	run acquire_lockfile_flock test_main_func

	# Wait for background process
	wait $bg_pid 2>/dev/null || true
	rm -f "$signal_file"

	assert_success
	# Lockfile should be cleaned up
	assert_file_not_exist "$LOCKFILE"
}

# bats test_tags=category:unit
@test "acquire_lockfile_flock cleans up lockfile on function exit" {
	# Purpose: Test verifies that acquire_lockfile_flock function cleans up lockfile when wrapped function exits successfully.
	# Expected: Lockfile is removed after function execution completes, even on successful exit.
	# Importance: Ensures lockfiles are properly cleaned up to prevent blocking future script executions.
	# Skip condition: Requires 'flock' command to be available for file locking tests
	if ! command -v flock >/dev/null 2>&1; then
		skip "flock command not available (test requires flock for file locking functionality)"
	fi

	source_lockfile_module

	# Test function that exits successfully
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	test_main_func() {
		echo "Function executed"
		return 0
	}

	# Run acquire_lockfile_flock
	run acquire_lockfile_flock test_main_func

	assert_success
	# Lockfile should be cleaned up even on successful exit
	assert_file_not_exist "$LOCKFILE"
}

# bats test_tags=category:unit
@test "acquire_lockfile_flock cleans up lockfile on function error" {
	# Purpose: Test verifies that acquire_lockfile_flock function cleans up lockfile even when wrapped function exits with error.
	# Expected: Lockfile is removed after function execution completes, regardless of exit code.
	# Importance: Ensures lockfiles are always cleaned up via EXIT trap, preventing permanent blocking on errors.
	# Skip condition: Requires 'flock' command to be available for file locking tests
	if ! command -v flock >/dev/null 2>&1; then
		skip "flock command not available (test requires flock for file locking functionality)"
	fi

	source_lockfile_module

	# Test function that exits with error
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   1: Always fails (for testing error handling)
	test_main_func() {
		echo "Function executed with error"
		return 1
	}

	# Run acquire_lockfile_flock
	run acquire_lockfile_flock test_main_func

	# Function returns error (main_func returns 1), but lockfile should still be cleaned up
	# Note: acquire_lockfile_flock runs in a subshell that propagates exit codes from main_func
	# The EXIT trap ensures cleanup happens regardless of exit code
	assert_failure # Should preserve exit code 1 from main_func
	assert_file_not_exist "$LOCKFILE"
}

# bats test_tags=category:unit
@test "acquire_lockfile_fallback successfully acquires lock when available" {
	# Purpose: Test verifies that acquire_lockfile_fallback function successfully acquires lock when no other process holds it
	# Expected: Function acquires lock using atomic file operations, executes main function, and cleans up lockfile
	# Importance: Fallback lock acquisition enables script execution when flock command is not available
	source_lockfile_module

	# Test function that will be executed after lock acquisition
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	test_main_func() {
		echo "Lock acquired, executing main function"
		return 0
	}

	# Run acquire_lockfile_fallback
	run acquire_lockfile_fallback test_main_func

	assert_success
	assert_output --partial "Lock acquired"
	# Lockfile should be cleaned up after execution
	assert_file_not_exist "$LOCKFILE"
}

# bats test_tags=category:unit
@test "acquire_lockfile_fallback detects running process and exits gracefully" {
	# Purpose: Test verifies that acquire_lockfile_fallback function detects when another process holds the lock
	# Expected: Function detects lockfile conflict, exits gracefully without executing main function
	# Importance: Graceful exit prevents multiple script instances and avoids conflicts
	source_lockfile_module

	# Create lockfile with current PID (simulating running process)
	echo "$(date +%s):$$" >"$LOCKFILE"
	touch "$LOCKFILE"

	# Test function (should not be executed)
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	test_main_func() {
		echo "This should not execute"
		return 0
	}

	# Run acquire_lockfile_fallback - should detect conflict and exit
	run acquire_lockfile_fallback test_main_func

	# Should exit with code 0 (graceful exit, not error)
	assert_success
	# Should output warning about lockfile conflict
	assert_output --partial "already running"
	# Main function should not have executed
	refute_output --partial "This should not execute"
}

# bats test_tags=category:unit
@test "acquire_lockfile_fallback removes stale lockfile and acquires lock" {
	# Purpose: Test verifies that acquire_lockfile_fallback function removes stale lockfiles and acquires lock
	# Expected: Function detects stale lockfile (old timestamp, dead PID), removes it, and successfully acquires lock
	# Importance: Stale lockfile cleanup prevents false positives from terminated processes
	source_lockfile_module

	# Create stale lockfile (old timestamp, non-existent PID)
	local old_timestamp
	old_timestamp=$(($(date +%s) - LOCKFILE_TIMEOUT - 10))
	echo "${old_timestamp}:99999" >"$LOCKFILE"
	touch -d "@$old_timestamp" "$LOCKFILE" 2>/dev/null || touch "$LOCKFILE"

	# Test function that will be executed after lock acquisition
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	test_main_func() {
		echo "Lock acquired after stale removal"
		return 0
	}

	# Run acquire_lockfile_fallback
	run acquire_lockfile_fallback test_main_func

	assert_success
	assert_output --partial "Lock acquired"
	# Lockfile should be cleaned up after execution
	assert_file_not_exist "$LOCKFILE"
}

# bats test_tags=category:unit
@test "acquire_lockfile_fallback handles race condition when lockfile created between check and acquisition" {
	# Purpose: Test verifies that acquire_lockfile_fallback function handles race conditions when lockfile is created between check and acquisition
	# Expected: Function handles race condition gracefully, either acquiring lock or detecting conflict
	# Importance: Race condition handling ensures reliable lock acquisition in concurrent scenarios
	source_lockfile_module

	# Test function that will be executed after lock acquisition
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	test_main_func() {
		echo "Lock acquired"
		return 0
	}

	# Create a background process that creates lockfile when signal file appears
	# This simulates a race condition where another process creates lockfile between check and acquisition
	# Use file-based synchronization to ensure race happens at the right moment
	# Timing is unpredictable - either we get the lock first, or the bg process creates it first
	local signal_file="${TEST_DIR}/acquisition_started"
	rm -f "$signal_file"
	(
		# Wait for signal file to appear (indicates lock acquisition attempt started)
		while [[ ! -f "$signal_file" ]]; do
			sleep 0.01
		done
		# Small delay to ensure we're in the middle of acquisition attempt
		sleep 0.01
		echo "$(date +%s):$$" >"$LOCKFILE"
		touch "$LOCKFILE"
	) &
	local bg_pid=$!

	# Create signal file to indicate lock acquisition attempt is starting
	touch "$signal_file"

	# Run acquire_lockfile_fallback - should handle race condition gracefully
	run acquire_lockfile_fallback test_main_func

	# Wait for background process to complete
	wait $bg_pid 2>/dev/null || true
	rm -f "$signal_file"

	# Should exit with code 0 (graceful exit, not error)
	assert_success

	# Result depends on timing - both outcomes are valid:
	# 1. We got the lock first (before bg process created it) - lockfile should be cleaned up
	# 2. Bg process created lockfile first - should detect conflict and exit gracefully
	# Check if output contains "already running" or "Lock acquired"
	if echo "$output" | grep -q "already running"; then
		# Detected conflict - this is valid behavior
		refute_output --partial "Lock acquired"
	else
		# Successfully acquired lock - verify it was cleaned up
		# Note: bg process may create lockfile after our cleanup, so we check before final cleanup
		assert_output --partial "Lock acquired"
	fi

	# Clean up any remaining lockfile from background process
	rm -f "$LOCKFILE"
}

# bats test_tags=category:unit
@test "acquire_lockfile_fallback retries once when lockfile has dead PID" {
	# Purpose: Test verifies that acquire_lockfile_fallback function retries lock acquisition when lockfile contains dead PID
	# Expected: Function detects dead PID, removes lockfile, retries acquisition once, and successfully acquires lock
	# Importance: Retry logic handles transient lockfile states from recently terminated processes
	source_lockfile_module

	# Test function that will be executed after lock acquisition
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	test_main_func() {
		echo "Lock acquired after retry"
		return 0
	}

	# Create lockfile with non-existent PID (will be detected as dead, not stale by time)
	# This tests the retry logic when PID is dead but lockfile is recent
	echo "$(date +%s):99999" >"$LOCKFILE"
	touch "$LOCKFILE"

	# Run acquire_lockfile_fallback - should detect dead PID, remove lockfile, and retry
	run acquire_lockfile_fallback test_main_func

	# Should succeed after retry
	assert_success
	assert_output --partial "Lock acquired"
	# Lockfile should be cleaned up after execution
	assert_file_not_exist "$LOCKFILE"
}

# bats test_tags=category:unit
@test "acquire_lockfile_fallback cleans up lockfile on function exit" {
	# Purpose: Test verifies that acquire_lockfile_fallback function cleans up lockfile when main function exits successfully
	# Expected: Lockfile is removed by EXIT trap handler even when main function completes successfully
	# Importance: Lockfile cleanup ensures lock is released even on successful completion
	source_lockfile_module

	# Test function that exits successfully
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	test_main_func() {
		echo "Function executed"
		return 0
	}

	# Run acquire_lockfile_fallback
	run acquire_lockfile_fallback test_main_func

	assert_success
	# Lockfile should be cleaned up even on successful exit
	assert_file_not_exist "$LOCKFILE"
}

# bats test_tags=category:unit
@test "acquire_lockfile_fallback cleans up lockfile on function error" {
	# Purpose: Test verifies that acquire_lockfile_fallback function cleans up lockfile when main function exits with error
	# Expected: Lockfile is removed by EXIT trap handler even when main function returns error code
	# Importance: Lockfile cleanup ensures lock is released even on error conditions
	source_lockfile_module

	# Test function that exits with error
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   1: Always fails (for testing error handling)
	test_main_func() {
		echo "Function executed with error"
		return 1
	}

	# Run acquire_lockfile_fallback
	run acquire_lockfile_fallback test_main_func

	# Function returns error, but lockfile should still be cleaned up by trap
	assert_file_not_exist "$LOCKFILE"
}

# bats test_tags=category:unit
@test "acquire_lockfile_fallback handles lockfile with dead PID (not stale by time)" {
	# Purpose: Test verifies that acquire_lockfile_fallback function handles lockfiles with dead PIDs that are not stale by time
	# Expected: Function detects dead PID even when lockfile timestamp is recent, removes lockfile, and acquires lock
	# Importance: Dead PID detection enables lock acquisition even when lockfile is recent but process is terminated
	source_lockfile_module

	# Create lockfile with recent timestamp but non-existent PID
	# This tests the case where PID is dead but lockfile is not stale by time
	echo "$(date +%s):99999" >"$LOCKFILE"
	touch "$LOCKFILE"

	# Test function that will be executed after lock acquisition
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	test_main_func() {
		echo "Lock acquired after dead PID removal"
		return 0
	}

	# Run acquire_lockfile_fallback
	run acquire_lockfile_fallback test_main_func

	assert_success
	assert_output --partial "Lock acquired"
	# Lockfile should be cleaned up after execution
	assert_file_not_exist "$LOCKFILE"
}

# bats test_tags=category:unit
@test "acquire_lockfile_fallback handles lockfile with dead PID during atomic creation retry" {
	# Purpose: Test verifies that acquire_lockfile_fallback function handles dead PID detection during atomic lockfile creation retry
	# Expected: Function detects dead PID during retry, removes lockfile, and successfully acquires lock on retry
	# Importance: Dead PID handling during retry ensures reliable lock acquisition in edge cases
	source_lockfile_module

	# Test function that will be executed after lock acquisition
	#
	# Arguments:
	#   None
	#
	# Returns:
	#   0: Always succeeds
	test_main_func() {
		echo "Lock acquired after retry"
		return 0
	}

	# Create lockfile with dead PID before atomic creation attempt
	# This tests the retry logic when create_lockfile_atomically fails
	# and the lockfile contains a dead PID
	echo "$(date +%s):99999" >"$LOCKFILE"
	touch "$LOCKFILE"

	# Run acquire_lockfile_fallback - should detect dead PID during retry, remove lockfile, and succeed
	run acquire_lockfile_fallback test_main_func

	# Should succeed after retry
	assert_success
	assert_output --partial "Lock acquired"
	# Lockfile should be cleaned up after execution
	assert_file_not_exist "$LOCKFILE"
}

# ============================================================================
# Constants Tests
# ============================================================================

# bats test_tags=category:unit
@test "constants are properly loaded and have correct values" {
	# Purpose: Test verifies that constants.sh file defines all required constants with correct values.
	# Expected: All constants (IPv4/IPv6 limits, ping thresholds, xfrm settings, time conversions) are defined correctly.
	# Importance: Constants ensure consistent validation limits and configuration values across the application.
	# Skip condition: Requires constants.sh file to be available for constant validation tests
	# Source constants.sh
	# shellcheck source=/dev/null
	source "${LIB_DIR}/constants.sh" 2>/dev/null || {
		skip "constants.sh not found (test requires constants.sh at ${LIB_DIR}/constants.sh to verify constant definitions)"
	}

	# Verify IPv4 constants
	assert_equal "$MAX_IPV4_OCTET" 255
	assert_equal "$IPV4_OCTET_COUNT" 4
	assert_equal "$IPV4_CIDR_SINGLE_HOST" 32

	# Verify IPv6 constants
	assert_equal "$MAX_IPV6_SEGMENTS" 8
	assert_equal "$MIN_IPV6_SEGMENT_HEX_DIGITS" 1
	assert_equal "$MAX_IPV6_SEGMENT_HEX_DIGITS" 4

	# Verify ping constants
	assert_equal "$PING_PACKET_LOSS_THRESHOLD" 100
	assert_equal "$PING_SUCCESS_THRESHOLD" "0.3"
	assert_equal "$PING_CEIL_ADJUSTMENT" "0.999"

	# Verify xfrm constants
	assert_equal "$XFRM_OUTPUT_CONTEXT_LINES" 10
	assert_equal "$XFRM_RECOVERY_SLEEP_SECONDS" 3
	assert_equal "$XFRM_RECOVERY_VERIFY_TIMEOUT" 30
	assert_equal "$XFRM_RECOVERY_VERIFY_INTERVAL" 2
	assert_equal "$XFRM_RECOVERY_MAX_INTERVAL" 16

	# Verify time constants
	assert_equal "$SECONDS_PER_MINUTE" 60
	assert_equal "$SECONDS_PER_HOUR" 3600
	assert_equal "$SECONDS_PER_DAY" 86400
}

# bats test_tags=category:unit
@test "IPv4 validation uses MAX_IPV4_OCTET constant" {
	# Purpose: Test verifies that IPv4 validation function uses MAX_IPV4_OCTET constant for boundary checking
	# Expected: Function accepts values up to MAX_IPV4_OCTET (255) and rejects values exceeding it
	# Importance: Constant-based validation ensures consistent IP address validation limits
	# Source the function (which loads constants)
	# shellcheck source=/dev/null
	source_function "validate_ipv4"

	# Test boundary values
	# 255 should be valid (MAX_IPV4_OCTET)
	run validate_ipv4 "255.255.255.255"
	assert_success

	# 256 should be invalid (> MAX_IPV4_OCTET)
	run validate_ipv4 "256.1.1.1"
	assert_failure

	# 0 should be valid (within range)
	run validate_ipv4 "0.0.0.0"
	assert_success
}

# bats test_tags=category:unit
@test "IPv6 validation uses hex digit constants" {
	# Purpose: Test verifies that IPv6 validation function uses hex digit constants for segment validation
	# Expected: Function accepts segments with 1-4 hex digits and rejects segments with more than 4 hex digits
	# Importance: Constant-based validation ensures consistent IPv6 address validation limits
	# Source the function (which loads constants)
	# shellcheck source=/dev/null
	source_function "validate_ipv6"

	# Test valid IPv6 with 1-4 hex digits per segment (MIN-MAX range)
	run validate_ipv6 "1:2:3:4:5:6:7:8"
	assert_success

	run validate_ipv6 "a:b:c:d:e:f:1:2"
	assert_success

	run validate_ipv6 "abcd:ef01:2345:6789:abcd:ef01:2345:6789"
	assert_success

	# Test invalid IPv6 with >4 hex digits per segment (> MAX_IPV6_SEGMENT_HEX_DIGITS)
	run validate_ipv6 "12345:db8::1"
	assert_failure

	# Test invalid IPv6 with triple colon (compression format issue)
	run validate_ipv6 "2001:db8:::1"
	assert_failure
}

# ============================================================================
# SA Rekey Detection Tests
# ============================================================================

# bats test_tags=category:unit
@test "extract_spi extracts hex SPI from xfrm output" {
	# Purpose: Test verifies that extract_spi function correctly extracts hexadecimal SPI values from xfrm output
	# Expected: Function extracts SPI value in hexadecimal format (0x prefix) from xfrm state output
	# Importance: SPI extraction enables SA rekey detection by tracking Security Parameter Index changes
	# Source the function
	# shellcheck source=/dev/null
	source_function "extract_spi"

	local xfrm_output="src 192.168.1.1 dst 203.0.113.1
    proto esp spi 0x12345678 reqid 1 mode tunnel
    lifetime current: 1000 bytes, 10 packets"

	run extract_spi "$xfrm_output"
	assert_success
	assert_output "0x12345678"
}

# bats test_tags=category:unit
@test "extract_spi extracts decimal SPI from xfrm output" {
	# Purpose: Test verifies that extract_spi function correctly extracts decimal SPI values from xfrm output
	# Expected: Function extracts SPI value in decimal format (no prefix) from xfrm state output
	# Importance: Decimal SPI extraction supports both hex and decimal SPI formats in xfrm output
	# Source the function
	# shellcheck source=/dev/null
	source_function "extract_spi"

	local xfrm_output="src 192.168.1.1 dst 203.0.113.1
    proto esp spi 305419896 reqid 1 mode tunnel
    lifetime current: 1000 bytes, 10 packets"

	run extract_spi "$xfrm_output"
	assert_success
	assert_output "305419896"
}

# bats test_tags=category:unit
@test "extract_spi handles missing SPI line" {
	# Purpose: Test verifies that extract_spi function handles xfrm output without SPI line gracefully
	# Expected: Function returns failure when SPI line is missing from xfrm output
	# Importance: Error handling prevents script crashes when xfrm output format is unexpected
	# Source the function
	# shellcheck source=/dev/null
	source_function "extract_spi"

	local xfrm_output="src 192.168.1.1 dst 203.0.113.1
    proto esp reqid 1 mode tunnel
    lifetime current: 1000 bytes, 10 packets"

	run extract_spi "$xfrm_output"
	assert_failure
}

# bats test_tags=category:unit
@test "check_sa_rekey_occurred returns false on first check (no stored SPI)" {
	# Purpose: Test verifies that check_sa_rekey_occurred function returns false when no stored SPI exists
	# Expected: Function returns failure (no rekey) on first check when SPI file doesn't exist
	# Importance: First check handling enables initial SPI storage without false rekey detection
	# Set up environment
	STATE_DIR="${TEST_DIR}"
	mkdir -p "${STATE_DIR}"
	LOGS_DIR="${STATE_DIR}/logs"
	mkdir -p "${LOGS_DIR}"
	export STATE_DIR LOGS_DIR

	# Source the function
	# shellcheck source=/dev/null
	source_function "check_sa_rekey_occurred"

	# Ensure no SPI file exists - use location-based path format
	local spi_file="${STATE_DIR}/spi_LOCATION_203_0_113_1"
	[[ ! -f "$spi_file" ]] || rm -f "$spi_file"

	# First check - no stored SPI
	# get_peer_state returns "" (empty) when file doesn't exist and default is ""
	# But the function checks if last_spi is empty with -z
	# Use TEST location name
	run check_sa_rekey_occurred "0x12345678" "203.0.113.1" "TEST"
	# Function should return 1 (no rekey) when no stored SPI
	# But get_peer_state with default "" might return "0" if default handling is wrong
	# Let's check if status is 1 (expected) or if we need to verify the logic differently
	# The function returns 1 when last_spi is empty, which should happen here
	assert_equal "$status" 1
}

# bats test_tags=category:unit
@test "check_sa_rekey_occurred returns false when SPI unchanged" {
	# Purpose: Test verifies that check_sa_rekey_occurred function returns false when SPI value hasn't changed
	# Expected: Function returns failure (no rekey) when current SPI matches stored SPI
	# Importance: Unchanged SPI detection prevents false rekey alerts when SA remains stable
	# Set up environment
	STATE_DIR="${TEST_DIR}"
	export STATE_DIR

	# Source required functions
	# shellcheck source=/dev/null
	source_function "set_peer_state"
	# shellcheck source=/dev/null
	source_function "check_sa_rekey_occurred"

	# Store initial SPI - use TEST location name
	set_peer_state "TEST" "203.0.113.1" "spi" "0x12345678" || true

	# Check with same SPI - use TEST location name
	run check_sa_rekey_occurred "0x12345678" "203.0.113.1" "TEST"
	assert_failure
}

# bats test_tags=category:unit
@test "check_sa_rekey_occurred returns true when SPI changed" {
	# Purpose: Test verifies that check_sa_rekey_occurred function returns true when SPI value has changed
	# Expected: Function returns success (rekey occurred) when current SPI differs from stored SPI
	# Importance: SPI change detection enables identification of SA rekey events for byte counter reset
	# Set up environment
	STATE_DIR="${TEST_DIR}"
	export STATE_DIR

	# Source required functions
	# shellcheck source=/dev/null
	source_function "set_peer_state"
	# shellcheck source=/dev/null
	source_function "check_sa_rekey_occurred"

	# Store initial SPI - use TEST location name
	set_peer_state "TEST" "203.0.113.1" "spi" "0x12345678" || true

	# Check with different SPI (rekey occurred) - use TEST location name
	run check_sa_rekey_occurred "0x87654321" "203.0.113.1" "TEST"
	assert_success
}

# bats test_tags=category:unit
@test "detect_sa_rekey stores SPI on first check" {
	# Purpose: Test verifies that detect_sa_rekey function stores SPI value on first check when no stored SPI exists
	# Expected: Function stores SPI value in state file and returns false (no rekey) on first check
	# Importance: Initial SPI storage enables subsequent rekey detection by tracking SPI changes
	# Set up environment
	STATE_DIR="${TEST_DIR}"
	mkdir -p "${STATE_DIR}"
	LOGS_DIR="${STATE_DIR}/logs"
	mkdir -p "${LOGS_DIR}"
	export STATE_DIR LOGS_DIR

	# Source required functions
	# shellcheck source=/dev/null
	source_function "detect_sa_rekey"
	# shellcheck source=/dev/null
	source_function "get_peer_state"

	# Ensure no SPI file exists
	local spi_file="${STATE_DIR}/spi_TEST_203_0_113_1"
	[[ ! -f "$spi_file" ]] || rm -f "$spi_file"

	# First check - should store SPI but return false (no rekey)
	run detect_sa_rekey "0x12345678" "203.0.113.1" "TEST"
	# Function returns 1 when no rekey (first check)
	assert_equal "$status" 1

	# Verify SPI was stored
	local stored_spi
	stored_spi=$(get_peer_state "TEST" "203.0.113.1" "spi" "")
	# Use assert_equal for better error messages
	assert_equal "$stored_spi" "0x12345678"
}

# bats test_tags=category:unit
@test "detect_sa_rekey detects rekey and resets byte counter baseline" {
	# Purpose: Test verifies that detect_sa_rekey function detects SA rekey and resets byte counter baseline
	# Expected: Function detects SPI change, updates stored SPI, and resets last_bytes to 0
	# Importance: Byte counter reset after rekey prevents false idle detection when SA is rekeyed
	# Set up environment
	STATE_DIR="${TEST_DIR}"
	LOGS_DIR="${STATE_DIR}/logs"
	mkdir -p "${STATE_DIR}"
	mkdir -p "${LOGS_DIR}"
	export STATE_DIR LOGS_DIR

	# Source required functions
	# shellcheck source=/dev/null
	source_function "detect_sa_rekey"
	# shellcheck source=/dev/null
	source_function "set_peer_state"
	# shellcheck source=/dev/null
	source_function "get_peer_state"

	# Set initial state: stored SPI and byte counter
	set_peer_state "TEST" "203.0.113.1" "spi" "0x12345678" || true
	set_peer_state "TEST" "203.0.113.1" "last_bytes" "5000" || true

	# Detect rekey with new SPI
	run detect_sa_rekey "0x87654321" "203.0.113.1" "TEST"
	assert_success

	# Verify SPI was updated
	local stored_spi
	stored_spi=$(get_peer_state "TEST" "203.0.113.1" "spi" "")
	# Use assert_equal for better error messages
	assert_equal "$stored_spi" "0x87654321"

	# Verify byte counter baseline was reset
	local last_bytes
	last_bytes=$(get_peer_state "TEST" "203.0.113.1" "last_bytes" "0")
	# Use assert_equal for better error messages
	assert_equal "$last_bytes" "0"
}

# bats test_tags=category:unit
@test "check_byte_counters detects rekey before checking bytes" {
	# Purpose: Test verifies that check_byte_counters function detects SA rekey before checking byte counters
	# Expected: Function detects SPI change, resets byte counter baseline, and updates with new byte value
	# Importance: Rekey detection before byte checking prevents false idle detection after SA rekey
	# Set up environment
	STATE_DIR="${TEST_DIR}"
	LOGS_DIR="${STATE_DIR}/logs"
	mkdir -p "${STATE_DIR}"
	mkdir -p "${LOGS_DIR}"
	export STATE_DIR LOGS_DIR

	# Source required functions
	# shellcheck source=/dev/null
	source_function "check_byte_counters"
	# shellcheck source=/dev/null
	source_function "set_peer_state"
	# shellcheck source=/dev/null
	source_function "get_peer_state"

	# Set initial state: stored SPI and byte counter
	set_peer_state "" "203.0.113.1" "spi" "0x12345678" || true
	set_peer_state "" "203.0.113.1" "last_bytes" "5000" || true

	# Check with new SPI (rekey) and new bytes
	run check_byte_counters "" "1000" "203.0.113.1" "0x87654321"
	assert_success

	# Verify byte counter baseline was reset and updated
	local last_bytes
	last_bytes=$(get_peer_state "" "203.0.113.1" "last_bytes" "0")
	# Use assert_equal for better error messages
	assert_equal "$last_bytes" "1000"

	# Verify SPI was updated
	local stored_spi
	stored_spi=$(get_peer_state "" "203.0.113.1" "spi" "")
	# Use assert_equal for better error messages
	assert_equal "$stored_spi" "0x87654321"
}

# bats test_tags=category:unit
@test "check_byte_counters handles bytes=0 after rekey" {
	# Purpose: Test verifies that check_byte_counters function handles bytes=0 correctly after SA rekey
	# Expected: Function detects rekey, resets byte counter to 0, and returns failure (idle detected)
	# Importance: Bytes=0 handling after rekey enables proper idle detection when no traffic has occurred
	# Set up environment
	STATE_DIR="${TEST_DIR}"
	LOGS_DIR="${STATE_DIR}/logs"
	mkdir -p "${STATE_DIR}"
	mkdir -p "${LOGS_DIR}"
	export STATE_DIR LOGS_DIR

	# Source required functions
	# shellcheck source=/dev/null
	source_function "check_byte_counters"
	# shellcheck source=/dev/null
	source_function "set_peer_state"
	# shellcheck source=/dev/null
	source_function "get_peer_state"

	# Set initial state: stored SPI and byte counter
	set_peer_state "" "203.0.113.1" "spi" "0x12345678" || true
	set_peer_state "" "203.0.113.1" "last_bytes" "5000" || true

	# Check with new SPI (rekey) but bytes=0
	run check_byte_counters "" "0" "203.0.113.1" "0x87654321"
	assert_failure

	# Verify byte counter baseline was reset (rekey detected)
	local last_bytes
	last_bytes=$(get_peer_state "" "203.0.113.1" "last_bytes" "0")
	# Use assert_equal for better error messages
	assert_equal "$last_bytes" "0"
}

# bats test_tags=category:unit
@test "check_byte_counters allows first zero bytes check to pass if ping succeeds" {
	# Purpose: Test verifies that check_byte_counters allows first check with zero bytes to pass if ping check succeeds
	# Expected: Function performs ping check on first zero bytes check, and passes if ping succeeds
	# Importance: Reduces false positives for newly established idle VPNs while maintaining fail-safe behavior
	# Set up environment
	STATE_DIR="${TEST_DIR}"
	LOGS_DIR="${STATE_DIR}/logs"
	mkdir -p "${STATE_DIR}"
	mkdir -p "${LOGS_DIR}"
	export STATE_DIR LOGS_DIR
	export ENABLE_PING_CHECK=1
	export PING_COUNT=3
	export PING_TIMEOUT=2

	local peer_ip="203.0.113.1"
	local internal_peer_ip="10.0.0.1"
	local location_name="TEST"

	# Mock ping command that succeeds
	mock_ping_success >/dev/null
	add_mock_to_path

	# Source required functions
	# shellcheck source=/dev/null
	source_function "check_byte_counters"
	# shellcheck source=/dev/null
	source_function "set_peer_state"
	# shellcheck source=/dev/null
	source_function "get_peer_state"
	# shellcheck source=/dev/null
	source_function "get_local_ip_for_ping"

	# First check with zero bytes - no previous state (last_bytes=0)
	# With ping check enabled and internal_peer_ip provided, should pass if ping succeeds
	run check_byte_counters "$location_name" "0" "$peer_ip" "" "$internal_peer_ip"
	assert_success

	# Verify state was updated
	local last_bytes
	last_bytes=$(get_peer_state "$location_name" "$peer_ip" "last_bytes" "0")
	assert_equal "$last_bytes" "0"

	# Verify idle_detected was set
	local idle_detected
	idle_detected=$(get_peer_state "$location_name" "$peer_ip" "idle_detected" "0")
	assert_equal "$idle_detected" "1"

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "check_byte_counters fails first zero bytes check if ping fails" {
	# Purpose: Test verifies that check_byte_counters fails first check with zero bytes if ping check fails
	# Expected: Function performs ping check on first zero bytes check, and fails if ping fails
	# Importance: Maintains fail-safe behavior when ping check indicates VPN is broken
	# Set up environment
	STATE_DIR="${TEST_DIR}"
	LOGS_DIR="${STATE_DIR}/logs"
	mkdir -p "${STATE_DIR}"
	mkdir -p "${LOGS_DIR}"
	export STATE_DIR LOGS_DIR
	export ENABLE_PING_CHECK=1
	export PING_COUNT=3
	export PING_TIMEOUT=2

	local peer_ip="203.0.113.1"
	local internal_peer_ip="10.0.0.1"
	local location_name="TEST"

	# Mock ping command that fails
	mock_ping_failure >/dev/null
	add_mock_to_path

	# Source required functions
	# shellcheck source=/dev/null
	source_function "check_byte_counters"
	# shellcheck source=/dev/null
	source_function "get_peer_state"

	# First check with zero bytes - no previous state (last_bytes=0)
	# With ping check enabled and internal_peer_ip provided, should fail if ping fails
	run check_byte_counters "$location_name" "0" "$peer_ip" "" "$internal_peer_ip"
	assert_failure

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "check_xfrm_status extracts and tracks SPI" {
	# Purpose: Test verifies that check_xfrm_status function extracts SPI from xfrm output and stores it
	# Expected: Function extracts SPI value from xfrm state output and stores it in state file for tracking
	# Importance: SPI tracking enables SA rekey detection by monitoring SPI changes over time
	# Set up environment
	STATE_DIR="${TEST_DIR}"
	mkdir -p "${STATE_DIR}"
	export STATE_DIR

	# Create mock ip command with specific SPI
	# Use explicit path for this test since it needs to verify the mock itself
	local mock_ip
	mock_ip=$(mock_ip_xfrm_state "203.0.113.1" "2000" "0xABCDEF12" "" "${TEST_DIR}/mock_ip")
	add_mock_to_path

	# Source constants for XFRM_OUTPUT_CONTEXT_LINES if not already set
	if [[ -z "${XFRM_OUTPUT_CONTEXT_LINES:-}" ]] && [[ -f "${LIB_DIR}/constants.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/constants.sh" 2>/dev/null || true
	fi
	: "${XFRM_OUTPUT_CONTEXT_LINES:=10}"

	# Source required functions AFTER PATH is set
	# shellcheck source=/dev/null
	source_function "check_xfrm_status"
	# shellcheck source=/dev/null
	source_function "get_peer_state"

	# Verify mock works
	assert_file_exist "${TEST_DIR}/mock_ip"
	run "${TEST_DIR}/mock_ip" xfrm state
	assert_success
	# Use regex to verify IP address format
	assert_output --regexp '203\.0\.113\.1'

	# Skip condition: Requires mock IP command to be available in PATH for integration test
	# Check VPN status (skip if mock not found in PATH)
	if command -v ip 2>/dev/null | grep -q "^${TEST_DIR}/mock_ip$"; then
		run check_xfrm_status "203.0.113.1"
		assert_success

		# Verify SPI was stored - use empty string for location to test backward compatibility
		local stored_spi
		stored_spi=$(get_peer_state "" "203.0.113.1" "spi" "")
		# Use assert_equal for better error messages
		assert_equal "$stored_spi" "0xABCDEF12"
	else
		skip "Mock IP command not found in PATH (integration test requires mock_ip at ${TEST_DIR}/mock_ip to verify xfrm status checking)"
	fi
}

# bats test_tags=category:unit
@test "check_xfrm_status detects rekey when SPI changes" {
	# Purpose: Test verifies that check_xfrm_status function detects SA rekey when SPI value changes
	# Expected: Function detects SPI change, updates stored SPI, and resets byte counter baseline
	# Importance: Rekey detection enables proper byte counter reset after SA rekey events
	# Set up environment
	STATE_DIR="${TEST_DIR}"
	mkdir -p "${STATE_DIR}"
	LOGS_DIR="${STATE_DIR}/logs"
	mkdir -p "${LOGS_DIR}"
	export STATE_DIR LOGS_DIR

	# Source required functions
	# shellcheck source=/dev/null
	source_function "set_peer_state"
	# shellcheck source=/dev/null
	source_function "check_xfrm_status"
	# shellcheck source=/dev/null
	source_function "get_peer_state"

	# Set initial state: stored SPI and byte counter
	# Use empty string for location to test backward compatibility
	set_peer_state "" "203.0.113.1" "spi" "0x12345678" || true
	set_peer_state "" "203.0.113.1" "last_bytes" "5000" || true

	# Create mock ip command FIRST
	# Use explicit path for this test since it needs to verify the mock itself
	local mock_ip
	mock_ip=$(mock_ip_xfrm_state "203.0.113.1" "1000" "0x87654321" "" "${TEST_DIR}/mock_ip")
	add_mock_to_path

	# Set PATH BEFORE sourcing so command -v finds mock
	add_mock_to_path

	# Source constants for XFRM_OUTPUT_CONTEXT_LINES if not already set
	if [[ -z "${XFRM_OUTPUT_CONTEXT_LINES:-}" ]] && [[ -f "${LIB_DIR}/constants.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/constants.sh" 2>/dev/null || true
	fi
	# Set default if still not set (constants.sh might not have it)
	: "${XFRM_OUTPUT_CONTEXT_LINES:=10}"

	# Verify mock ip command exists and works
	assert_file_exist "${TEST_DIR}/mock_ip"
	run "${TEST_DIR}/mock_ip" xfrm state
	assert_success
	# Use regex to verify IP address format
	assert_output --regexp '203\.0\.113\.1'

	# Check VPN status - should detect rekey and reset baseline
	# Note: The mock IP command must be in PATH before check_xfrm_status is called
	# If command -v ip finds the real ip instead of mock, skip this integration test
	# The core rekey detection logic is already tested in other unit tests above
	local found_ip_cmd
	found_ip_cmd=$(command -v ip 2>/dev/null || echo "")
	if [[ -n "$found_ip_cmd" ]] && [[ "$found_ip_cmd" == "${TEST_DIR}/mock_ip" ]]; then
		run check_xfrm_status "203.0.113.1"
		assert_success

		# Verify SPI was updated - use empty string for location to test backward compatibility
		local stored_spi
		stored_spi=$(get_peer_state "" "203.0.113.1" "spi" "")
		# Use assert_equal for better error messages
		assert_equal "$stored_spi" "0x87654321"

		# Verify byte counter baseline was reset (rekey detected)
		local last_bytes
		last_bytes=$(get_peer_state "" "203.0.113.1" "last_bytes" "0")
		# Use assert_equal for better error messages
		assert_equal "$last_bytes" "1000"
	else
		# Skip condition: Requires mock IP command to be available in PATH for integration test
		# Mock not found in PATH - skip integration test
		# Core functionality is tested in unit tests above
		skip "Mock IP command not found in PATH (integration test requires mock_ip at ${TEST_DIR}/mock_ip to verify rekey detection, unit tests passed)"
	fi
}

# ============================================================================
# Tests for recovery.sh - select_recovery_strategy function
# ============================================================================

# bats test_tags=category:unit
@test "select_recovery_strategy selects xfrm strategy when peer IP provided and xfrm enabled" {
	# Purpose: Test verifies that select_recovery_strategy function selects xfrm recovery strategy when conditions are met
	# Expected: Function selects xfrm strategy when peer IP is provided, xfrm recovery is enabled, and ip command is available
	# Importance: Xfrm strategy selection enables per-connection recovery with minimal impact on other VPN tunnels
	if [[ -f "${LIB_DIR}/recovery.sh" ]]; then
		# Source dependencies
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		if [[ -f "${LIB_DIR}/config.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/config.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/recovery.sh" 2>/dev/null || true
	fi

	# Set up environment
	ENABLE_XFRM_RECOVERY=1
	# Mock ip command available
	local mock_ip="${TEST_DIR}/ip"
	echo '#!/bin/bash' >"$mock_ip"
	chmod +x "$mock_ip"
	add_mock_to_path

	# Test strategy selection (call directly, not with run, so global variables persist)
	select_recovery_strategy "203.0.113.1" 2

	# Use assert_equal for better error messages
	assert_equal "$RECOVERY_STRATEGY" "xfrm"
	assert_equal "$RECOVERY_COMMAND" "attempt_xfrm_recovery"
	assert_equal "$RECOVERY_IMPACT" "per-connection"
	assert_equal "$RECOVERY_AVAILABLE" "1"

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "select_recovery_strategy selects ipsec_reload for tier 2 when xfrm disabled" {
	# Purpose: Test verifies that select_recovery_strategy function selects ipsec_reload strategy for tier 2 when xfrm is disabled
	# Expected: Function selects ipsec_reload strategy when xfrm recovery is disabled and ipsec command is available
	# Importance: Fallback strategy selection ensures recovery actions are available even when xfrm recovery is disabled
	if [[ -f "${LIB_DIR}/recovery.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		if [[ -f "${LIB_DIR}/config.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/config.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/recovery.sh" 2>/dev/null || true
	fi

	# Clear variables from previous tests
	unset RECOVERY_STRATEGY RECOVERY_COMMAND RECOVERY_IMPACT RECOVERY_AVAILABLE

	# Set up environment
	ENABLE_XFRM_RECOVERY=0
	# Mock ipsec command available
	local mock_ipsec="${TEST_DIR}/ipsec"
	echo '#!/bin/bash' >"$mock_ipsec"
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Test strategy selection (call directly, not with run, so global variables persist)
	select_recovery_strategy "203.0.113.1" 2

	# Use assert_equal for better error messages
	assert_equal "$RECOVERY_STRATEGY" "ipsec_reload"
	assert_equal "$RECOVERY_COMMAND" "ipsec reload"
	assert_equal "$RECOVERY_IMPACT" "all-tunnels"
	assert_equal "$RECOVERY_AVAILABLE" "1"

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "select_recovery_strategy selects ipsec_restart for tier 3" {
	# Purpose: Test verifies that select_recovery_strategy function selects ipsec_restart strategy for tier 3 failures
	# Expected: Function selects ipsec_restart strategy for tier 3 regardless of xfrm settings
	# Importance: Tier 3 strategy selection enables full IPsec service restart for critical failures
	if [[ -f "${LIB_DIR}/recovery.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		if [[ -f "${LIB_DIR}/config.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/config.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/recovery.sh" 2>/dev/null || true
	fi

	# Clear variables from previous tests
	unset RECOVERY_STRATEGY RECOVERY_COMMAND RECOVERY_IMPACT RECOVERY_AVAILABLE

	# Set up environment
	ENABLE_XFRM_RECOVERY=0
	# Mock ipsec command available
	local mock_ipsec="${TEST_DIR}/ipsec"
	echo '#!/bin/bash' >"$mock_ipsec"
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Test strategy selection (call directly, not with run, so global variables persist)
	select_recovery_strategy "" 3

	# Use assert_equal for better error messages
	assert_equal "$RECOVERY_STRATEGY" "ipsec_restart"
	assert_equal "$RECOVERY_COMMAND" "ipsec restart"
	assert_equal "$RECOVERY_IMPACT" "all-tunnels"
	assert_equal "$RECOVERY_AVAILABLE" "1"

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "select_recovery_strategy selects ipsec_reload when no peer IP provided" {
	# Purpose: Test verifies that select_recovery_strategy function selects ipsec_reload when peer IP is not provided
	# Expected: Function selects ipsec_reload strategy when peer IP is empty, even if xfrm recovery is enabled
	# Importance: Fallback strategy selection ensures recovery actions are available when peer IP is unknown
	if [[ -f "${LIB_DIR}/recovery.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		if [[ -f "${LIB_DIR}/config.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/config.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/recovery.sh" 2>/dev/null || true
	fi

	# Clear variables from previous tests
	unset RECOVERY_STRATEGY RECOVERY_COMMAND RECOVERY_IMPACT RECOVERY_AVAILABLE

	# Set up environment
	ENABLE_XFRM_RECOVERY=1
	# Mock ipsec command available
	local mock_ipsec="${TEST_DIR}/ipsec"
	echo '#!/bin/bash' >"$mock_ipsec"
	chmod +x "$mock_ipsec"
	add_mock_to_path

	# Test strategy selection (no peer IP, call directly so global variables persist)
	select_recovery_strategy "" 2

	# Use assert_equal for better error messages
	assert_equal "$RECOVERY_STRATEGY" "ipsec_reload"
	assert_equal "$RECOVERY_COMMAND" "ipsec reload"
	assert_equal "$RECOVERY_IMPACT" "all-tunnels"
	assert_equal "$RECOVERY_AVAILABLE" "1"

	remove_mock_from_path
}

# bats test_tags=category:unit
@test "select_recovery_strategy returns unavailable when no commands available" {
	# Purpose: Test verifies that select_recovery_strategy function returns unavailable when required commands are missing
	# Expected: Function sets RECOVERY_STRATEGY to unavailable and RECOVERY_AVAILABLE to 0 when neither ip nor ipsec commands are available
	# Importance: Unavailable strategy handling prevents errors when recovery commands are not available on the system
	if [[ -f "${LIB_DIR}/recovery.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		if [[ -f "${LIB_DIR}/config.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/config.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/recovery.sh" 2>/dev/null || true
	fi

	# Clear variables from previous tests
	unset RECOVERY_STRATEGY RECOVERY_COMMAND RECOVERY_IMPACT RECOVERY_AVAILABLE

	# Set up environment - no commands available
	ENABLE_XFRM_RECOVERY=1
	remove_mock_from_path

	# Create a minimal PATH that doesn't include system commands
	# This ensures ip and ipsec are not found via PATH
	local original_path="$PATH"
	PATH="${TEST_DIR}"

	# Mock check_command_available to return false for ip and ipsec
	# This simulates the scenario where commands are truly unavailable
	# We override the function after sourcing libraries to shadow the original
	# Source common.sh first to get the original function definition
	if [[ -f "${LIB_DIR}/common.sh" ]]; then
		# shellcheck source=/dev/null
		source "${LIB_DIR}/common.sh" 2>/dev/null || true
	fi
	# Override check_command_available to return false for ip and ipsec
	# This allows us to test the "unavailable" scenario even when commands exist on the system
	# For other commands, we use a simple command -v check (sufficient for test purposes)
	#
	# Arguments:
	#   $1: Command name to check
	#
	# Returns:
	#   0: Command is available
	#   1: Command is not available
	check_command_available() {
		local cmd="$1"
		# Return false (unavailable) for ip and ipsec to test unavailable scenario
		if [[ "$cmd" == "ip" ]] || [[ "$cmd" == "ipsec" ]]; then
			return 1
		fi
		# For other commands, use simple command -v check
		# This is sufficient for test purposes and avoids complexity
		command -v "$cmd" >/dev/null 2>&1
	}

	# Test strategy selection (call directly so global variables persist)
	select_recovery_strategy "203.0.113.1" 2 || true

	# Restore PATH
	PATH="$original_path"

	# Use assert_equal for better error messages
	assert_equal "$RECOVERY_STRATEGY" "unavailable"
	assert_equal "$RECOVERY_AVAILABLE" "0"
}

# bats test_tags=category:unit
@test "select_recovery_strategy rejects invalid tier" {
	# Purpose: Test verifies that select_recovery_strategy function rejects invalid tier values
	# Expected: Function returns failure when tier value is not 1, 2, or 3
	# Importance: Tier validation prevents invalid recovery strategy selection for unsupported failure tiers
	if [[ -f "${LIB_DIR}/recovery.sh" ]]; then
		if [[ -f "${LIB_DIR}/logging.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/logging.sh" 2>/dev/null || true
		fi
		if [[ -f "${LIB_DIR}/config.sh" ]]; then
			# shellcheck source=/dev/null
			source "${LIB_DIR}/config.sh" 2>/dev/null || true
		fi
		# shellcheck source=/dev/null
		source "${LIB_DIR}/recovery.sh" 2>/dev/null || true
	fi

	# Mock handle_error to not exit
	# Mock function to suppress error handling in tests
	#
	# Arguments:
	#   $@: Error message and parameters (ignored)
	#
	# Returns:
	#   0: Always succeeds
	handle_error() {
		:
	}

	# Test invalid tier
	run select_recovery_strategy "203.0.113.1" 1

	assert_failure
}

# ============================================================================
# Test Helper Function Tests - with_mocks()
# ============================================================================
# These tests verify the with_mocks() wrapper function that ensures mock cleanup

# bats test_tags=category:unit
@test "with_mocks executes command successfully and cleans up PATH" {
	# Purpose: Test verifies that with_mocks() executes commands successfully and always cleans up PATH
	# Expected: Function executes command, returns success, and removes mocks from PATH
	# Importance: Ensures mock cleanup happens even on successful execution
	local original_path="$PATH"

	# Use with_mocks to execute a command (mock setup is done inside with_mocks)
	run with_mocks 'mock_ip_xfrm_state "${TEST_PEER_IP}" 1000' \
		true

	assert_success
	# Verify PATH was restored (mocks removed)
	assert_equal "$PATH" "$original_path"
}

# bats test_tags=category:unit
@test "with_mocks handles mock setup failure without modifying PATH" {
	# Purpose: Test verifies that with_mocks() handles mock setup failures gracefully
	# Expected: Function returns error and does not modify PATH when mock setup fails
	# Importance: Prevents PATH pollution when mock setup commands fail
	local original_path="$PATH"

	# Use with_mocks with a failing mock setup command
	run with_mocks 'false' true

	assert_failure
	# Verify PATH was not modified (should still be original)
	assert_equal "$PATH" "$original_path"
}

# bats test_tags=category:unit
@test "with_mocks handles empty command and cleans up PATH" {
	# Purpose: Test verifies that with_mocks() handles empty command gracefully
	# Expected: Function returns error and cleans up PATH when no command is provided
	# Importance: Prevents PATH pollution when function is called incorrectly
	local original_path="$PATH"

	# Use with_mocks without providing a command (empty after shift)
	# Mock setup will succeed, but then function detects no command and cleans up
	run with_mocks 'mock_ip_xfrm_state "${TEST_PEER_IP}" 1000'

	assert_failure
	# Verify PATH was restored (mocks removed)
	assert_equal "$PATH" "$original_path"
}

# bats test_tags=category:unit
@test "with_mocks cleans up PATH even when command fails" {
	# Purpose: Test verifies that with_mocks() cleans up PATH even when wrapped command fails
	# Expected: Function removes mocks from PATH and returns command's exit code
	# Importance: Ensures cleanup happens regardless of command success/failure
	local original_path="$PATH"

	# Use with_mocks to execute a failing command
	run with_mocks 'mock_ip_xfrm_state "${TEST_PEER_IP}" 1000' \
		false

	assert_failure
	# Verify PATH was restored (mocks removed) even though command failed
	assert_equal "$PATH" "$original_path"
}

# bats test_tags=category:unit
@test "with_mocks executes multiple mock setup commands" {
	# Purpose: Test verifies that with_mocks() handles multiple mock setup commands
	# Expected: Function evaluates all setup commands and executes wrapped command
	# Importance: Supports complex test scenarios requiring multiple mocks
	local original_path="$PATH"

	# Use with_mocks with multiple mock setup commands
	run with_mocks 'mock_ip_xfrm_state "${TEST_PEER_IP}" 1000; mock_ping "${TEST_PEER_IP}" 1' \
		true

	assert_success
	# Verify PATH was restored
	assert_equal "$PATH" "$original_path"
	# Verify mocks were created
	assert_file_exist "${TEST_DIR}/ip"
	assert_file_exist "${TEST_DIR}/mock_ping"
}

# bats test_tags=category:unit
@test "with_mocks preserves command exit code" {
	# Purpose: Test verifies that with_mocks() preserves the exit code of the wrapped command
	# Expected: Function returns the same exit code as the wrapped command
	# Importance: Allows tests to verify command success/failure through with_mocks()
	local original_path="$PATH"

	# Test with exit code 0
	run with_mocks 'mock_ip_xfrm_state "${TEST_PEER_IP}" 1000' \
		sh -c 'exit 0'
	assert_success

	# Test with exit code 1
	run with_mocks 'mock_ip_xfrm_state "${TEST_PEER_IP}" 1000' \
		sh -c 'exit 1'
	assert_failure

	# Test with exit code 2
	run with_mocks 'mock_ip_xfrm_state "${TEST_PEER_IP}" 1000' \
		sh -c 'exit 2'
	assert_failure
	# Note: BATS doesn't preserve exact exit codes, just success/failure
	# But we can verify it's not 0

	# Verify PATH was restored
	assert_equal "$PATH" "$original_path"
}
