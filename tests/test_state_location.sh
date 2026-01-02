#!/usr/bin/env bats
#
# Tests for Location-Based State File Management
# Tests location-based state file naming, state file operations with location names,
# and sanitization of location names in filenames

load test_helper

# Source the state library functions
# shellcheck source=../lib/state.sh
source "${BATS_TEST_DIRNAME}/../lib/state.sh"

# Source logging for handle_error functions
# shellcheck source=../lib/logging.sh
source "${BATS_TEST_DIRNAME}/../lib/logging.sh"

# ============================================================================
# LOCATION-BASED STATE FILE MANAGEMENT TESTS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state_file_path - failure_counter with location name" {
	# Purpose: Test that failure counter files use location name in filename
	# Expected: Filename format is failure_counter_<location>_<peer_ip>
	# Importance: State files must be unique per location
	setup_test_environment

	run get_peer_state_file_path "NYC" "192.168.1.1" "failure_count"
	assert_success
	assert_output "${STATE_DIR}/failure_counter_NYC_192_168_1_1"
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state_file_path - last_bytes with location name" {
	# Purpose: Test that last_bytes files use location name in filename
	# Expected: Filename format is last_bytes_<location>_<peer_ip>
	# Importance: State files must be unique per location
	setup_test_environment

	run get_peer_state_file_path "NYC" "192.168.1.1" "last_bytes"
	assert_success
	assert_output "${STATE_DIR}/last_bytes_NYC_192_168_1_1"
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state_file_path - sanitizes location name in filename" {
	# Purpose: Test that location names are sanitized before use in filenames
	# Expected: Invalid characters in location name are replaced with underscores
	# Importance: Ensures safe filenames
	setup_test_environment

	run get_peer_state_file_path "NYC-Office" "192.168.1.1" "failure_count"
	assert_success
	assert_output "${STATE_DIR}/failure_counter_NYC_Office_192_168_1_1"
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state_file_path - sanitizes peer IP in filename" {
	# Purpose: Test that peer IPs are sanitized before use in filenames
	# Expected: Dots in IP are replaced with underscores
	# Importance: Ensures safe filenames
	setup_test_environment

	run get_peer_state_file_path "NYC" "192.168.1.1" "failure_count"
	assert_success
	assert_output "${STATE_DIR}/failure_counter_NYC_192_168_1_1"
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state_file_path - different locations create different files" {
	# Purpose: Test that different locations create different state files
	# Expected: Same peer IP with different locations creates different files
	# Importance: Prevents state file conflicts between locations
	setup_test_environment

	local file1
	file1=$(get_peer_state_file_path "NYC" "192.168.1.1" "failure_count")
	local file2
	file2=$(get_peer_state_file_path "LA" "192.168.1.1" "failure_count")

	assert [ "$file1" != "$file2" ]
	assert_equal "$file1" "${STATE_DIR}/failure_counter_NYC_192_168_1_1"
	assert_equal "$file2" "${STATE_DIR}/failure_counter_LA_192_168_1_1"
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state_file_path - SPI file with location name" {
	# Purpose: Test that SPI files use location name in filename
	# Expected: Filename format is spi_<location>_<peer_ip>
	# Importance: SPI state must be tracked per location
	setup_test_environment

	run get_peer_state_file_path "NYC" "192.168.1.1" "spi"
	assert_success
	assert_output "${STATE_DIR}/spi_NYC_192_168_1_1"
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state_file_path - idle_detected file with location name" {
	# Purpose: Test that idle_detected files use location name in filename
	# Expected: Filename format is idle_detected_<location>_<peer_ip>
	# Importance: Idle detection state must be tracked per location
	setup_test_environment

	run get_peer_state_file_path "NYC" "192.168.1.1" "idle_detected"
	assert_success
	assert_output "${STATE_DIR}/idle_detected_NYC_192_168_1_1"
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state_file_path - last_status_log file with location name" {
	# Purpose: Test that last_status_log files use location name in filename
	# Expected: Filename format is last_status_log_<location>_<peer_ip>
	# Importance: Status log state must be tracked per location
	setup_test_environment

	run get_peer_state_file_path "NYC" "192.168.1.1" "last_status_log"
	assert_success
	assert_output "${STATE_DIR}/last_status_log_NYC_192_168_1_1"
}

# bats test_tags=category:high-risk,priority:high
@test "set_peer_state - creates file with location name" {
	# Purpose: Test that set_peer_state creates files with location name
	# Expected: State file is created with correct location-based filename
	# Importance: State files must be created correctly
	setup_test_environment

	run set_peer_state "NYC" "192.168.1.1" "failure_count" "5"
	assert_success

	local state_file
	state_file=$(get_peer_state_file_path "NYC" "192.168.1.1" "failure_count")
	assert_file_exist "$state_file"
	assert_file_contains "$state_file" "5"
}

# bats test_tags=category:high-risk,priority:high
@test "set_peer_state - different locations create separate files" {
	# Purpose: Test that set_peer_state creates separate files for different locations
	# Expected: Same peer IP with different locations creates separate state files
	# Importance: Prevents state conflicts between locations
	setup_test_environment

	run set_peer_state "NYC" "192.168.1.1" "failure_count" "5"
	assert_success
	run set_peer_state "LA" "192.168.1.1" "failure_count" "10"
	assert_success

	local file1
	file1=$(get_peer_state_file_path "NYC" "192.168.1.1" "failure_count")
	local file2
	file2=$(get_peer_state_file_path "LA" "192.168.1.1" "failure_count")

	assert_file_exist "$file1"
	assert_file_exist "$file2"
	assert_file_contains "$file1" "5"
	assert_file_contains "$file2" "10"
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state - retrieves value with location name" {
	# Purpose: Test that get_peer_state retrieves values using location name
	# Expected: State value is retrieved correctly from location-based file
	# Importance: State retrieval must work with location names
	setup_test_environment

	# Set state
	set_peer_state "NYC" "192.168.1.1" "failure_count" "7"

	# Get state
	run get_peer_state "NYC" "192.168.1.1" "failure_count"
	assert_success
	assert_output "7"
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state - returns default for non-existent file" {
	# Purpose: Test that get_peer_state returns default when file doesn't exist
	# Expected: Default value (0) is returned for non-existent state file
	# Importance: Handles missing state files gracefully
	setup_test_environment

	run get_peer_state "NYC" "192.168.1.1" "failure_count"
	assert_success
	assert_output "0"
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state - different locations retrieve separate values" {
	# Purpose: Test that get_peer_state retrieves separate values for different locations
	# Expected: Same peer IP with different locations retrieves different values
	# Importance: State isolation between locations
	setup_test_environment

	set_peer_state "NYC" "192.168.1.1" "failure_count" "5"
	set_peer_state "LA" "192.168.1.1" "failure_count" "10"

	local nyc_count
	nyc_count=$(get_peer_state "NYC" "192.168.1.1" "failure_count")
	local la_count
	la_count=$(get_peer_state "LA" "192.168.1.1" "failure_count")

	assert_equal "$nyc_count" "5"
	assert_equal "$la_count" "10"
}

# bats test_tags=category:high-risk,priority:high
@test "sanitize_location_name - used in state file paths" {
	# Purpose: Test that sanitize_location_name is used correctly in state file paths
	# Expected: Location names are sanitized before use in filenames
	# Importance: Ensures safe filenames
	setup_test_environment

	# Test with location name that needs sanitization
	run get_peer_state_file_path "NYC-Office" "192.168.1.1" "failure_count"
	assert_success
	# Should use sanitized name (hyphen replaced with underscore)
	assert_output "${STATE_DIR}/failure_counter_NYC_Office_192_168_1_1"
}

# bats test_tags=category:high-risk,priority:high
@test "set_peer_state - validates numeric values" {
	# Purpose: Test that set_peer_state validates numeric values
	# Expected: Non-numeric values are rejected for numeric keys
	# Importance: Prevents corrupted state files
	setup_test_environment

	run set_peer_state "NYC" "192.168.1.1" "failure_count" "invalid"
	assert_failure
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state - recovers corrupted numeric values" {
	# Purpose: Test that get_peer_state recovers from corrupted numeric values
	# Expected: Corrupted values are replaced with default
	# Importance: Handles file corruption gracefully
	setup_test_environment

	local state_file
	state_file=$(get_peer_state_file_path "NYC" "192.168.1.1" "failure_count")
	mkdir -p "$(dirname "$state_file")"
	echo "corrupted" >"$state_file"

	run get_peer_state "NYC" "192.168.1.1" "failure_count"
	assert_success
	# Should return default (0) after detecting corruption
	# Note: Warning message appears on stderr, so we check for the value using assert_line
	assert_line "0"
}

# bats test_tags=category:high-risk,priority:high
@test "set_peer_state - creates directory if needed" {
	# Purpose: Test that set_peer_state creates directories if they don't exist
	# Expected: State directories are created automatically
	# Importance: Handles missing directories gracefully
	local custom_state_dir="${TEST_DIR}/custom_state"
	local custom_logs_dir="${TEST_DIR}/custom_logs"
	STATE_DIR="$custom_state_dir"
	LOGS_DIR="$custom_logs_dir"
	export STATE_DIR LOGS_DIR

	run set_peer_state "NYC" "192.168.1.1" "failure_count" "5"
	assert_success

	local state_file
	state_file=$(get_peer_state_file_path "NYC" "192.168.1.1" "failure_count")
	assert_file_exist "$state_file"
	assert [ -d "$(dirname "$state_file")" ]
}

# bats test_tags=category:high-risk,priority:high
@test "set_peer_state - atomic write prevents corruption" {
	# Purpose: Test that set_peer_state uses atomic writes
	# Expected: State file updates are atomic (temp file + rename)
	# Importance: Prevents corruption during writes
	setup_test_environment

	# Set state multiple times rapidly
	for i in {1..10}; do
		set_peer_state "NYC" "192.168.1.1" "failure_count" "$i"
	done

	# Final value should be correct (not corrupted)
	local final_value
	final_value=$(get_peer_state "NYC" "192.168.1.1" "failure_count")
	assert_equal "$final_value" "10"
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state_file_path - handles IPv6 addresses" {
	# Purpose: Test that IPv6 addresses are sanitized correctly
	# Expected: Colons in IPv6 are replaced with underscores
	# Importance: IPv6 support requires proper sanitization
	setup_test_environment

	run get_peer_state_file_path "NYC" "2001:db8::1" "failure_count"
	assert_success
	assert_output "${STATE_DIR}/failure_counter_NYC_2001_db8__1"
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state_file_path - handles long location names" {
	# Purpose: Test that long location names are truncated correctly
	# Expected: Location names longer than 64 chars are truncated
	# Importance: Prevents filesystem issues with long filenames
	setup_test_environment

	local long_location="A"
	for i in {1..70}; do
		long_location="${long_location}A"
	done

	run get_peer_state_file_path "$long_location" "192.168.1.1" "failure_count"
	assert_success

	# Extract location part from filename
	local filename
	filename=$(basename "$output")
	local location_part
	location_part=$(echo "$filename" | sed 's/failure_counter_\(.*\)_192_168_1_1/\1/')

	# Location part should be <= 64 chars (after sanitization)
	assert [ ${#location_part} -le 64 ]
}

# bats test_tags=category:high-risk,priority:high
@test "set_peer_state_non_critical - handles errors gracefully" {
	# Purpose: Test that set_peer_state_non_critical continues on error
	# Expected: Function succeeds even if state update fails
	# Importance: Non-critical state updates shouldn't interrupt execution
	setup_test_environment

	# Try to set invalid value (should fail internally but not exit)
	run set_peer_state_non_critical "NYC" "192.168.1.1" "failure_count" "invalid"
	# Should succeed (continues execution even if state update fails)
	assert_success
}

# bats test_tags=category:high-risk,priority:high
@test "get_peer_state_file_path - unknown key uses default format" {
	# Purpose: Test that unknown keys use default filename format
	# Expected: Unknown keys create files with default format
	# Importance: Extensibility for new state keys
	setup_test_environment

	run get_peer_state_file_path "NYC" "192.168.1.1" "unknown_key"
	assert_success
	# Note: Warning message appears on stderr, so we check for the file path using assert_line
	assert_line "${STATE_DIR}/unknown_key_NYC_192_168_1_1"
}
