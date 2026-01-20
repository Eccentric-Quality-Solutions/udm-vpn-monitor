#!/usr/bin/env bats
#
# Tests for System-Wide Failure Coordination Functions
# Tests individual coordination functions in isolation
#
# These tests address the coverage gap identified in TEST_INFRASTRUCTURE_REVIEW.md:
# - get_system_wide_failure_state* (5 variants)
# - should_coordinate_recovery
# - clear_system_wide_failure_coordinator
# - should_location_attempt_recovery
# - detect_system_wide_failure (coordination aspects)

load test_helper

# Path to the VPN monitor script
VPN_MONITOR_SCRIPT="${BATS_TEST_DIRNAME}/../vpn-monitor.sh"

# ============================================================================
# STATE FILE PATH FUNCTIONS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "get_system_wide_failure_state_file: returns default path when SYSTEM_WIDE_FAILURE_STATE_FILE not set" {
	# Purpose: Test verifies that get_system_wide_failure_state_file returns default path
	# Expected: Returns ${STATE_DIR}/system_wide_failure_state when env var not set
	# Importance: Ensures correct file path is used for state storage
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source the function
	source_function "get_system_wide_failure_state_file"

	# Get state file path
	local state_file
	state_file=$(get_system_wide_failure_state_file)

	# Verify path is correct
	assert_equal "$state_file" "${STATE_DIR}/system_wide_failure_state"
}

# bats test_tags=category:high-risk,priority:high
@test "get_system_wide_failure_state_file: returns custom path when SYSTEM_WIDE_FAILURE_STATE_FILE is set" {
	# Purpose: Test verifies that get_system_wide_failure_state_file respects custom path
	# Expected: Returns custom path when SYSTEM_WIDE_FAILURE_STATE_FILE is set
	# Importance: Allows customization of state file location
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Set custom state file path
	local custom_path="${TEST_DIR}/custom_state_file"
	export SYSTEM_WIDE_FAILURE_STATE_FILE="$custom_path"

	# Source the function
	source_function "get_system_wide_failure_state_file"

	# Get state file path
	local state_file
	state_file=$(get_system_wide_failure_state_file)

	# Verify path is custom
	assert_equal "$state_file" "$custom_path"

	unset SYSTEM_WIDE_FAILURE_STATE_FILE
}

# bats test_tags=category:high-risk,priority:high
@test "get_system_wide_failure_timestamp_file: returns default path when SYSTEM_WIDE_FAILURE_TIMESTAMP_FILE not set" {
	# Purpose: Test verifies that get_system_wide_failure_timestamp_file returns default path
	# Expected: Returns ${STATE_DIR}/system_wide_failure_timestamp when env var not set
	# Importance: Ensures correct file path is used for timestamp storage
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source the function
	source_function "get_system_wide_failure_timestamp_file"

	# Get timestamp file path
	local timestamp_file
	timestamp_file=$(get_system_wide_failure_timestamp_file)

	# Verify path is correct
	assert_equal "$timestamp_file" "${STATE_DIR}/system_wide_failure_timestamp"
}

# bats test_tags=category:high-risk,priority:high
@test "get_system_wide_failure_timestamp_file: returns custom path when SYSTEM_WIDE_FAILURE_TIMESTAMP_FILE is set" {
	# Purpose: Test verifies that get_system_wide_failure_timestamp_file respects custom path
	# Expected: Returns custom path when SYSTEM_WIDE_FAILURE_TIMESTAMP_FILE is set
	# Importance: Allows customization of timestamp file location
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Set custom timestamp file path
	local custom_path="${TEST_DIR}/custom_timestamp_file"
	export SYSTEM_WIDE_FAILURE_TIMESTAMP_FILE="$custom_path"

	# Source the function
	source_function "get_system_wide_failure_timestamp_file"

	# Get timestamp file path
	local timestamp_file
	timestamp_file=$(get_system_wide_failure_timestamp_file)

	# Verify path is custom
	assert_equal "$timestamp_file" "$custom_path"

	unset SYSTEM_WIDE_FAILURE_TIMESTAMP_FILE
}

# bats test_tags=category:high-risk,priority:high
@test "get_system_wide_failure_coordinator_file: returns default path when SYSTEM_WIDE_FAILURE_COORDINATOR_FILE not set" {
	# Purpose: Test verifies that get_system_wide_failure_coordinator_file returns default path
	# Expected: Returns ${STATE_DIR}/system_wide_failure_coordinator when env var not set
	# Importance: Ensures correct file path is used for coordinator storage
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source the function
	source_function "get_system_wide_failure_coordinator_file"

	# Get coordinator file path
	local coordinator_file
	coordinator_file=$(get_system_wide_failure_coordinator_file)

	# Verify path is correct
	assert_equal "$coordinator_file" "${STATE_DIR}/system_wide_failure_coordinator"
}

# bats test_tags=category:high-risk,priority:high
@test "get_system_wide_failure_coordinator_file: returns custom path when SYSTEM_WIDE_FAILURE_COORDINATOR_FILE is set" {
	# Purpose: Test verifies that get_system_wide_failure_coordinator_file respects custom path
	# Expected: Returns custom path when SYSTEM_WIDE_FAILURE_COORDINATOR_FILE is set
	# Importance: Allows customization of coordinator file location
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Set custom coordinator file path
	local custom_path="${TEST_DIR}/custom_coordinator_file"
	export SYSTEM_WIDE_FAILURE_COORDINATOR_FILE="$custom_path"

	# Source the function
	source_function "get_system_wide_failure_coordinator_file"

	# Get coordinator file path
	local coordinator_file
	coordinator_file=$(get_system_wide_failure_coordinator_file)

	# Verify path is custom
	assert_equal "$coordinator_file" "$custom_path"

	unset SYSTEM_WIDE_FAILURE_COORDINATOR_FILE
}

# ============================================================================
# STATE GET/SET FUNCTIONS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "get_system_wide_failure_state: returns 0 when file does not exist" {
	# Purpose: Test verifies that get_system_wide_failure_state returns 0 for missing file
	# Expected: Returns "0" when state file doesn't exist
	# Importance: Ensures default behavior when no state is stored
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "get_system_wide_failure_state_file"
	source_function "get_system_wide_failure_state"

	# Get state (file doesn't exist)
	local state
	state=$(get_system_wide_failure_state)

	# Verify state is 0
	assert_equal "$state" "0"
}

# bats test_tags=category:high-risk,priority:high
@test "get_system_wide_failure_state: returns 1 when state file contains 1" {
	# Purpose: Test verifies that get_system_wide_failure_state reads state correctly
	# Expected: Returns "1" when state file contains "1"
	# Importance: Ensures state is correctly retrieved
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "get_system_wide_failure_state_file"
	source_function "get_system_wide_failure_state"
	source_function "set_system_wide_failure_state"

	# Set state to 1
	set_system_wide_failure_state 1

	# Get state
	local state
	state=$(get_system_wide_failure_state)

	# Verify state is 1
	assert_equal "$state" "1"
}

# bats test_tags=category:high-risk,priority:high
@test "get_system_wide_failure_state: recovers corrupted file (non-numeric value)" {
	# Purpose: Test verifies that get_system_wide_failure_state recovers corrupted files
	# Expected: Corrupted file is backed up and reset to 0
	# Importance: Prevents invalid state from causing false positives
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "get_system_wide_failure_state_file"
	source_function "get_system_wide_failure_state"

	# Create corrupted state file
	local state_file
	state_file=$(get_system_wide_failure_state_file)
	mkdir -p "$(dirname "$state_file")"
	echo "invalid" >"$state_file"

	# Get state (should recover corrupted file)
	local state
	state=$(get_system_wide_failure_state)

	# Verify state was recovered (should return 0)
	assert_equal "$state" "0"

	# Verify corrupted file was backed up
	local backup_count
	backup_count=$(find "${STATE_DIR}" -name "system_wide_failure_state.corrupted.*" 2>/dev/null | wc -l)
	assert [ "$backup_count" -gt 0 ]

	# Verify state file now has valid value
	local file_content
	file_content=$(cat "$state_file")
	assert_equal "$file_content" "0"
}

# bats test_tags=category:high-risk,priority:high
@test "set_system_wide_failure_state: sets state to 1 successfully" {
	# Purpose: Test verifies that set_system_wide_failure_state sets state correctly
	# Expected: State file contains "1" after setting state to 1
	# Importance: Ensures state can be set correctly
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "get_system_wide_failure_state_file"
	source_function "set_system_wide_failure_state"
	source_function "get_system_wide_failure_state"

	# Set state to 1
	run set_system_wide_failure_state 1
	assert_success

	# Verify state was set
	local state
	state=$(get_system_wide_failure_state)
	assert_equal "$state" "1"
}

# bats test_tags=category:high-risk,priority:high
@test "set_system_wide_failure_state: sets state to 0 and clears coordinator" {
	# Purpose: Test verifies that set_system_wide_failure_state clears coordinator when setting to 0
	# Expected: Coordinator file is removed when state is set to 0
	# Importance: Ensures coordinator is cleared when system-wide failure is resolved
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "get_system_wide_failure_state_file"
	source_function "get_system_wide_failure_coordinator_file"
	source_function "set_system_wide_failure_state"
	source_function "clear_system_wide_failure_coordinator"

	# Set state to 1 first
	set_system_wide_failure_state 1

	# Create coordinator file
	local coordinator_file
	coordinator_file=$(get_system_wide_failure_coordinator_file)
	mkdir -p "$(dirname "$coordinator_file")"
	echo "TEST1" >"$coordinator_file"
	assert_file_exist "$coordinator_file"

	# Set state to 0 (should clear coordinator)
	run set_system_wide_failure_state 0
	assert_success

	# Verify coordinator was cleared
	assert_file_not_exist "$coordinator_file"
}

# bats test_tags=category:high-risk,priority:high
@test "set_system_wide_failure_state: rejects invalid value (not 0 or 1)" {
	# Purpose: Test verifies that set_system_wide_failure_state validates input
	# Expected: Returns error when value is not 0 or 1
	# Importance: Prevents invalid state values from being stored
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "set_system_wide_failure_state"

	# Try to set invalid state
	run set_system_wide_failure_state 2
	assert_failure

	# Try to set invalid state (non-numeric)
	run set_system_wide_failure_state "invalid"
	assert_failure
}

# bats test_tags=category:high-risk,priority:high
@test "get_system_wide_failure_timestamp: returns 0 when file does not exist" {
	# Purpose: Test verifies that get_system_wide_failure_timestamp returns 0 for missing file
	# Expected: Returns "0" when timestamp file doesn't exist
	# Importance: Ensures default behavior when no timestamp is stored
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "get_system_wide_failure_timestamp_file"
	source_function "get_system_wide_failure_timestamp"

	# Get timestamp (file doesn't exist)
	local timestamp
	timestamp=$(get_system_wide_failure_timestamp)

	# Verify timestamp is 0
	assert_equal "$timestamp" "0"
}

# bats test_tags=category:high-risk,priority:high
@test "get_system_wide_failure_timestamp: returns timestamp when file exists" {
	# Purpose: Test verifies that get_system_wide_failure_timestamp reads timestamp correctly
	# Expected: Returns timestamp value when file exists
	# Importance: Ensures timestamp is correctly retrieved
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "get_system_wide_failure_timestamp_file"
	source_function "get_system_wide_failure_timestamp"
	source_function "set_system_wide_failure_timestamp"

	# Set timestamp
	local test_timestamp=1234567890
	set_system_wide_failure_timestamp "$test_timestamp"

	# Get timestamp
	local timestamp
	timestamp=$(get_system_wide_failure_timestamp)

	# Verify timestamp is correct
	assert_equal "$timestamp" "$test_timestamp"
}

# bats test_tags=category:high-risk,priority:high
@test "get_system_wide_failure_timestamp: recovers corrupted file (non-numeric value)" {
	# Purpose: Test verifies that get_system_wide_failure_timestamp recovers corrupted files
	# Expected: Corrupted file is backed up and reset to 0
	# Importance: Prevents invalid timestamp from causing issues
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "get_system_wide_failure_timestamp_file"
	source_function "get_system_wide_failure_timestamp"

	# Create corrupted timestamp file
	local timestamp_file
	timestamp_file=$(get_system_wide_failure_timestamp_file)
	mkdir -p "$(dirname "$timestamp_file")"
	echo "invalid" >"$timestamp_file"

	# Get timestamp (should recover corrupted file)
	local timestamp
	timestamp=$(get_system_wide_failure_timestamp)

	# Verify timestamp was recovered (should return 0)
	assert_equal "$timestamp" "0"

	# Verify corrupted file was backed up
	local backup_count
	backup_count=$(find "${STATE_DIR}" -name "system_wide_failure_timestamp.corrupted.*" 2>/dev/null | wc -l)
	assert [ "$backup_count" -gt 0 ]

	# Verify timestamp file now has valid value
	local file_content
	file_content=$(cat "$timestamp_file")
	assert_equal "$file_content" "0"
}

# bats test_tags=category:high-risk,priority:high
@test "set_system_wide_failure_timestamp: sets timestamp successfully" {
	# Purpose: Test verifies that set_system_wide_failure_timestamp sets timestamp correctly
	# Expected: Timestamp file contains correct value after setting
	# Importance: Ensures timestamp can be set correctly
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "get_system_wide_failure_timestamp_file"
	source_function "set_system_wide_failure_timestamp"
	source_function "get_system_wide_failure_timestamp"

	# Set timestamp
	local test_timestamp=1234567890
	run set_system_wide_failure_timestamp "$test_timestamp"
	assert_success

	# Verify timestamp was set
	local timestamp
	timestamp=$(get_system_wide_failure_timestamp)
	assert_equal "$timestamp" "$test_timestamp"
}

# bats test_tags=category:high-risk,priority:high
@test "set_system_wide_failure_timestamp: rejects invalid value (non-numeric)" {
	# Purpose: Test verifies that set_system_wide_failure_timestamp validates input
	# Expected: Returns error when value is not numeric
	# Importance: Prevents invalid timestamp values from being stored
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "set_system_wide_failure_timestamp"

	# Try to set invalid timestamp
	run set_system_wide_failure_timestamp "invalid"
	assert_failure
}

# ============================================================================
# COORDINATION FUNCTIONS
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "should_coordinate_recovery: returns 1 when detection is disabled" {
	# Purpose: Test verifies that should_coordinate_recovery returns 1 when detection disabled
	# Expected: Returns 1 (no coordination) when ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=0
	# Importance: Ensures coordination is disabled when detection is disabled
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "should_coordinate_recovery"

	# Disable detection
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=0

	# Check if coordination needed
	run should_coordinate_recovery
	assert_failure

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
}

# bats test_tags=category:high-risk,priority:high
@test "should_coordinate_recovery: returns 1 when system-wide failure not detected" {
	# Purpose: Test verifies that should_coordinate_recovery returns 1 when no system-wide failure
	# Expected: Returns 1 (no coordination) when system-wide failure state is 0
	# Importance: Ensures coordination only happens during system-wide failures
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "should_coordinate_recovery"
	source_function "set_system_wide_failure_state"

	# Enable detection
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1
	export COORDINATE_SYSTEM_WIDE_RECOVERY=1

	# Set state to 0 (no system-wide failure)
	set_system_wide_failure_state 0

	# Check if coordination needed
	run should_coordinate_recovery
	assert_failure

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
	unset COORDINATE_SYSTEM_WIDE_RECOVERY
}

# bats test_tags=category:high-risk,priority:high
@test "should_coordinate_recovery: returns 0 when system-wide failure detected and coordination enabled" {
	# Purpose: Test verifies that should_coordinate_recovery returns 0 when coordination needed
	# Expected: Returns 0 (coordination needed) when system-wide failure detected and coordination enabled
	# Importance: Ensures coordination is triggered correctly
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "should_coordinate_recovery"
	source_function "set_system_wide_failure_state"

	# Enable detection and coordination
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1
	export COORDINATE_SYSTEM_WIDE_RECOVERY=1

	# Set state to 1 (system-wide failure detected)
	set_system_wide_failure_state 1

	# Check if coordination needed
	run should_coordinate_recovery
	assert_success

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
	unset COORDINATE_SYSTEM_WIDE_RECOVERY
}

# bats test_tags=category:high-risk,priority:high
@test "should_coordinate_recovery: returns 1 when coordination is disabled" {
	# Purpose: Test verifies that should_coordinate_recovery returns 1 when coordination disabled
	# Expected: Returns 1 (no coordination) when COORDINATE_SYSTEM_WIDE_RECOVERY=0
	# Importance: Ensures coordination can be disabled via configuration
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "should_coordinate_recovery"
	source_function "set_system_wide_failure_state"

	# Enable detection but disable coordination
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1
	export COORDINATE_SYSTEM_WIDE_RECOVERY=0

	# Set state to 1 (system-wide failure detected)
	set_system_wide_failure_state 1

	# Check if coordination needed
	run should_coordinate_recovery
	assert_failure

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
	unset COORDINATE_SYSTEM_WIDE_RECOVERY
}

# bats test_tags=category:high-risk,priority:high
@test "should_location_attempt_recovery: returns 0 when coordination not needed" {
	# Purpose: Test verifies that should_location_attempt_recovery returns 0 when coordination disabled
	# Expected: Returns 0 (attempt recovery) when coordination is not needed
	# Importance: Ensures all locations can attempt recovery when coordination is disabled
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "should_location_attempt_recovery"

	# Disable coordination
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=0

	# Check if location should attempt recovery
	run should_location_attempt_recovery "TEST1"
	assert_success

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
}

# bats test_tags=category:high-risk,priority:high
@test "should_location_attempt_recovery: returns 0 when location is coordinator" {
	# Purpose: Test verifies that should_location_attempt_recovery returns 0 for coordinator
	# Expected: Returns 0 (attempt recovery) when location is the coordinator
	# Importance: Ensures coordinator location attempts recovery
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "should_location_attempt_recovery"
	source_function "get_system_wide_failure_coordinator_file"
	source_function "set_system_wide_failure_state"

	# Enable coordination
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1
	export COORDINATE_SYSTEM_WIDE_RECOVERY=1

	# Set system-wide failure state
	set_system_wide_failure_state 1

	# Pre-set coordinator to TEST1
	local coordinator_file
	coordinator_file=$(get_system_wide_failure_coordinator_file)
	mkdir -p "$(dirname "$coordinator_file")"
	echo "TEST1" >"$coordinator_file"

	# Check if TEST1 should attempt recovery (it's the coordinator)
	run should_location_attempt_recovery "TEST1"
	assert_success

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
	unset COORDINATE_SYSTEM_WIDE_RECOVERY
}

# bats test_tags=category:high-risk,priority:high
@test "should_location_attempt_recovery: returns 1 when another location is coordinator" {
	# Purpose: Test verifies that should_location_attempt_recovery returns 1 for non-coordinator
	# Expected: Returns 1 (skip recovery) when another location is the coordinator
	# Importance: Ensures non-coordinator locations skip recovery
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "should_location_attempt_recovery"
	source_function "get_system_wide_failure_coordinator_file"
	source_function "set_system_wide_failure_state"

	# Enable coordination
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1
	export COORDINATE_SYSTEM_WIDE_RECOVERY=1

	# Set system-wide failure state
	set_system_wide_failure_state 1

	# Pre-set coordinator to TEST2
	local coordinator_file
	coordinator_file=$(get_system_wide_failure_coordinator_file)
	mkdir -p "$(dirname "$coordinator_file")"
	echo "TEST2" >"$coordinator_file"

	# Check if TEST1 should attempt recovery (TEST2 is coordinator)
	run should_location_attempt_recovery "TEST1"
	assert_failure

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
	unset COORDINATE_SYSTEM_WIDE_RECOVERY
}

# bats test_tags=category:high-risk,priority:high
@test "should_location_attempt_recovery: becomes coordinator when no coordinator exists" {
	# Purpose: Test verifies that should_location_attempt_recovery creates coordinator atomically
	# Expected: First location to check becomes coordinator and returns 0
	# Importance: Ensures atomic coordinator selection prevents race conditions
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "should_location_attempt_recovery"
	source_function "get_system_wide_failure_coordinator_file"
	source_function "set_system_wide_failure_state"

	# Enable coordination
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1
	export COORDINATE_SYSTEM_WIDE_RECOVERY=1

	# Set system-wide failure state
	set_system_wide_failure_state 1

	# No coordinator exists yet - TEST1 should become coordinator
	run should_location_attempt_recovery "TEST1"
	assert_success

	# Verify coordinator file was created with TEST1
	local coordinator_file
	coordinator_file=$(get_system_wide_failure_coordinator_file)
	assert_file_exist "$coordinator_file"
	local coordinator
	coordinator=$(cat "$coordinator_file")
	assert_equal "$coordinator" "TEST1"

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
	unset COORDINATE_SYSTEM_WIDE_RECOVERY
}

# bats test_tags=category:high-risk,priority:high
@test "should_location_attempt_recovery: returns 1 when empty location name provided" {
	# Purpose: Test verifies that should_location_attempt_recovery handles empty location name
	# Expected: Returns 1 (skip recovery) when location name is empty
	# Importance: Prevents errors from invalid input
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "should_location_attempt_recovery"
	source_function "set_system_wide_failure_state"

	# Enable coordination
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1
	export COORDINATE_SYSTEM_WIDE_RECOVERY=1

	# Set system-wide failure state
	set_system_wide_failure_state 1

	# Check with empty location name
	run should_location_attempt_recovery ""
	assert_failure

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
	unset COORDINATE_SYSTEM_WIDE_RECOVERY
}

# bats test_tags=category:high-risk,priority:high
@test "clear_system_wide_failure_coordinator: removes coordinator file when it exists" {
	# Purpose: Test verifies that clear_system_wide_failure_coordinator removes coordinator file
	# Expected: Coordinator file is removed when clear_system_wide_failure_coordinator is called
	# Importance: Ensures coordinator is properly cleared
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "clear_system_wide_failure_coordinator"
	source_function "get_system_wide_failure_coordinator_file"

	# Create coordinator file
	local coordinator_file
	coordinator_file=$(get_system_wide_failure_coordinator_file)
	mkdir -p "$(dirname "$coordinator_file")"
	echo "TEST1" >"$coordinator_file"
	assert_file_exist "$coordinator_file"

	# Clear coordinator
	run clear_system_wide_failure_coordinator
	assert_success

	# Verify coordinator file was removed
	assert_file_not_exist "$coordinator_file"
}

# bats test_tags=category:high-risk,priority:high
@test "clear_system_wide_failure_coordinator: succeeds when coordinator file does not exist" {
	# Purpose: Test verifies that clear_system_wide_failure_coordinator handles missing file gracefully
	# Expected: Returns success even when coordinator file doesn't exist
	# Importance: Ensures function is non-fatal and idempotent
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "clear_system_wide_failure_coordinator"

	# Clear coordinator (file doesn't exist)
	run clear_system_wide_failure_coordinator
	assert_success
}

# ============================================================================
# DETECTION FUNCTION (COORDINATION ASPECTS)
# ============================================================================

# bats test_tags=category:high-risk,priority:high
@test "detect_system_wide_failure: returns 0 when all locations fail (threshold 100%)" {
	# Purpose: Test verifies that detect_system_wide_failure detects system-wide failure correctly
	# Expected: Returns 0 (detected) when all locations fail and threshold is 100%
	# Importance: Ensures detection works correctly for coordination
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "detect_system_wide_failure"

	# Enable detection
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1
	export SYSTEM_WIDE_FAILURE_THRESHOLD=100

	# Create location arrays (all failing)
	declare -A location_names
	declare -A failure_statuses
	location_names["TEST1"]="TEST1"
	location_names["TEST2"]="TEST2"
	location_names["TEST3"]="TEST3"
	failure_statuses["TEST1"]=1
	failure_statuses["TEST2"]=1
	failure_statuses["TEST3"]=1

	# Detect system-wide failure (call directly to get global variables)
	detect_system_wide_failure "location_names" "failure_statuses"
	local result=$?
	assert_equal "$result" "0"

	# Verify global variables were set
	assert_equal "$SYSTEM_WIDE_FAILURE_DETECTED" "1"
	assert_equal "$FAILED_LOCATION_COUNT" "3"
	assert_equal "$TOTAL_LOCATION_COUNT" "3"

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
	unset SYSTEM_WIDE_FAILURE_THRESHOLD
}

# bats test_tags=category:high-risk,priority:high
@test "detect_system_wide_failure: returns 1 when threshold not met" {
	# Purpose: Test verifies that detect_system_wide_failure returns 1 when threshold not met
	# Expected: Returns 1 (not detected) when failed percentage < threshold
	# Importance: Ensures detection only triggers when threshold is met
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "detect_system_wide_failure"

	# Enable detection with high threshold
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1
	export SYSTEM_WIDE_FAILURE_THRESHOLD=100

	# Create location arrays (only 1 out of 3 failing = 33% < 100%)
	declare -A location_names
	declare -A failure_statuses
	location_names["TEST1"]="TEST1"
	location_names["TEST2"]="TEST2"
	location_names["TEST3"]="TEST3"
	failure_statuses["TEST1"]=1
	failure_statuses["TEST2"]=0
	failure_statuses["TEST3"]=0

	# Detect system-wide failure (call directly to get global variables)
	# Use || to capture return value without triggering set -e failure
	local result=0
	detect_system_wide_failure "location_names" "failure_statuses" || result=$?
	assert_equal "$result" "1"

	# Verify global variables were set
	assert_equal "$SYSTEM_WIDE_FAILURE_DETECTED" "0"
	assert_equal "$FAILED_LOCATION_COUNT" "1"
	assert_equal "$TOTAL_LOCATION_COUNT" "3"

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
	unset SYSTEM_WIDE_FAILURE_THRESHOLD
}

# bats test_tags=category:high-risk,priority:high
@test "detect_system_wide_failure: returns 1 when detection is disabled" {
	# Purpose: Test verifies that detect_system_wide_failure returns 1 when detection disabled
	# Expected: Returns 1 (not detected) when ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=0
	# Importance: Ensures detection can be disabled
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "detect_system_wide_failure"

	# Disable detection
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=0

	# Create location arrays (all failing)
	declare -A location_names
	declare -A failure_statuses
	location_names["TEST1"]="TEST1"
	location_names["TEST2"]="TEST2"
	failure_statuses["TEST1"]=1
	failure_statuses["TEST2"]=1

	# Detect system-wide failure (call directly)
	# Use || to capture return value without triggering set -e failure
	local result=0
	detect_system_wide_failure "location_names" "failure_statuses" || result=$?
	assert_equal "$result" "1"

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
}

# bats test_tags=category:high-risk,priority:high
@test "detect_system_wide_failure: returns 1 when less than 2 locations" {
	# Purpose: Test verifies that detect_system_wide_failure returns 1 for single location
	# Expected: Returns 1 (not detected) when total locations < 2
	# Importance: Single location failure is not "system-wide"
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "detect_system_wide_failure"

	# Enable detection
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1
	export SYSTEM_WIDE_FAILURE_THRESHOLD=100

	# Create location arrays (only 1 location)
	declare -A location_names
	declare -A failure_statuses
	location_names["TEST1"]="TEST1"
	failure_statuses["TEST1"]=1

	# Detect system-wide failure (call directly)
	# Use || to capture return value without triggering set -e failure
	local result=0
	detect_system_wide_failure "location_names" "failure_statuses" || result=$?
	assert_equal "$result" "1"

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
	unset SYSTEM_WIDE_FAILURE_THRESHOLD
}

# bats test_tags=category:high-risk,priority:high
@test "detect_system_wide_failure: handles threshold percentage correctly (80%)" {
	# Purpose: Test verifies that detect_system_wide_failure handles percentage thresholds correctly
	# Expected: Returns 0 when 80% of locations fail and threshold is 80%
	# Importance: Ensures percentage calculation works correctly
	setup_test_environment "${TEST_DIR}" "${TEST_DIR}/logs"

	# Source required functions
	source_function "detect_system_wide_failure"

	# Enable detection with 80% threshold
	export ENABLE_SYSTEM_WIDE_FAILURE_DETECTION=1
	export SYSTEM_WIDE_FAILURE_THRESHOLD=80

	# Create location arrays (4 out of 5 failing = 80% >= 80%)
	declare -A location_names
	declare -A failure_statuses
	location_names["TEST1"]="TEST1"
	location_names["TEST2"]="TEST2"
	location_names["TEST3"]="TEST3"
	location_names["TEST4"]="TEST4"
	location_names["TEST5"]="TEST5"
	failure_statuses["TEST1"]=1
	failure_statuses["TEST2"]=1
	failure_statuses["TEST3"]=1
	failure_statuses["TEST4"]=1
	failure_statuses["TEST5"]=0

	# Detect system-wide failure (call directly to get global variables)
	detect_system_wide_failure "location_names" "failure_statuses"
	local result=$?
	assert_equal "$result" "0"

	# Verify global variables were set
	assert_equal "$SYSTEM_WIDE_FAILURE_DETECTED" "1"
	assert_equal "$FAILED_LOCATION_COUNT" "4"
	assert_equal "$TOTAL_LOCATION_COUNT" "5"

	unset ENABLE_SYSTEM_WIDE_FAILURE_DETECTION
	unset SYSTEM_WIDE_FAILURE_THRESHOLD
}
